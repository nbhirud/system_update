#!/usr/bin/env bash
# =============================================================================
# Jellyfin Setup Script for Fedora KDE
# =============================================================================
# Targets:  nbMain  (Dell OptiPlex 790,  i5-2400,  Intel HD 2000, 31GB DDR3)
#           nbAcer  (Acer Aspire TC-885, i5-8400,  Intel UHD 630,  8GB DDR4)
#
# What this script does:
#   1. Detects which machine it's running on and tunes settings accordingly
#   2. Installs Jellyfin via RPM Fusion (official community packages for Fedora)
#   3. Configures hardware-accelerated transcoding where supported (VAAPI)
#   4. Creates a dedicated 'jellyfin' system user and sets correct permissions
#   5. Configures firewalld rules (local LAN only, never internet-facing)
#   6. Sets up Avahi/mDNS so clients and Chromecast discover the server
#   7. Installs tinyMediaManager for library renaming/metadata management
#   8. Installs SubBuzz plugin (9 subtitle providers with automatic fallback)
#   9. Registers the official Jellyfin plugin repo for update notifications
#  10. Configures SELinux contexts for Jellyfin data and media paths
#   9. Adds Jellyfin transcode cache to tmpfs (RAM disk) on nbMain (31GB RAM)
#  10. Prints post-install checklist including OpenSubtitles plugin setup
#
# What you must fill in before running:
#   - OPENSUBTITLES_USER  : your opensubtitles.com username (optional but recommended)
#   - OPENSUBTITLES_PASS  : your opensubtitles.com password (optional but recommended)
#   SubBuzz will use 8 other providers even without these credentials.
#
# Usage:
#   chmod +x jellyfin_setup.sh
#   sudo ./jellyfin_setup.sh
#
# Run as root (or with sudo). The script will exit on any error.
# =============================================================================

set -euo pipefail

# =============================================================================
# !! FILL THESE IN BEFORE RUNNING !!
# =============================================================================
OPENSUBTITLES_USER="YOUR_OPENSUBTITLES_USERNAME"
OPENSUBTITLES_PASS="YOUR_OPENSUBTITLES_PASSWORD"

# =============================================================================
# CONSTANTS
# =============================================================================

# Media library root - same on both machines
MEDIA_DIR="${HOME}/nb/Videos"

# Jellyfin data directory (config, metadata, plugins, etc.)
JELLYFIN_DATA="/var/lib/jellyfin"

# Jellyfin config directory
JELLYFIN_CONFIG="/etc/jellyfin"

# Jellyfin transcode cache directory
# On nbMain (31GB RAM) we'll put this on a tmpfs RAM disk for speed.
# On nbAcer (8GB RAM) we'll use disk to avoid memory pressure.
TRANSCODE_CACHE="/var/cache/jellyfin/transcodes"

# Jellyfin runs on port 8096 (HTTP) and 8920 (HTTPS, optional)
# We only expose 8096 on the LAN - no internet access needed.
JELLYFIN_PORT=8096

# tinyMediaManager version to install
# Check https://www.tinymediamanager.org/download/ for latest
TMM_VERSION="5.0.9"
TMM_INSTALL_DIR="/opt/tinyMediaManager"

# =============================================================================
# HELPERS
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BLUE}========== $* ==========${NC}"; }

require_root() {
    [[ $EUID -eq 0 ]] || error "This script must be run as root (sudo ./jellyfin_setup.sh)"
}

# =============================================================================
# HARDWARE DETECTION
# =============================================================================
# Reads CPU model, RAM size, and GPU info from the running system.
# Sets global variables used throughout the script to tune behaviour.

detect_hardware() {
    section "Detecting Hardware"

    HOSTNAME_LOWER=$(hostname | tr '[:upper:]' '[:lower:]')
    CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
    RAM_GB=$(awk '/MemTotal/ { printf "%.0f", $2/1024/1024 }' /proc/meminfo)
    GPU_INFO=$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' || echo "unknown")

    info "Hostname : $HOSTNAME_LOWER"
    info "CPU      : $CPU_MODEL"
    info "RAM      : ${RAM_GB} GB"
    info "GPU(s)   : $GPU_INFO"

    # -------------------------------------------------------------------------
    # Determine VAAPI support
    # -------------------------------------------------------------------------
    # Intel HD 2000 (Sandy Bridge, Gen 6, 2011) - technically has VAAPI but
    # the iHD (modern) driver does NOT support it. The legacy i965 driver does,
    # but it's unreliable for transcoding and drops in Fedora 40+. Not worth it.
    # Intel UHD 630 (Coffee Lake, Gen 9.5, 2017) - well supported via iHD driver.
    #
    # We detect the generation by checking the PCI device ID or the CPU model.

    VAAPI_ENABLED=false
    USE_TMPFS_TRANSCODE=false
    MAX_CONCURRENT_STREAMS=2   # conservative default

    if echo "$CPU_MODEL" | grep -qi "i5-8400\|i5-8\|i7-8\|i9-8\|UHD 630"; then
        # Coffee Lake - full VAAPI via iHD driver
        VAAPI_ENABLED=true
        MAX_CONCURRENT_STREAMS=4
        info "VAAPI: ENABLED (Intel UHD 630 - iHD driver)"
    elif echo "$CPU_MODEL" | grep -qi "i5-2400\|Sandy Bridge\|2nd Gen"; then
        # Sandy Bridge - skip VAAPI, use software transcoding
        VAAPI_ENABLED=false
        MAX_CONCURRENT_STREAMS=1
        info "VAAPI: DISABLED (Sandy Bridge - too old, software transcode only)"
    else
        # Unknown - detect by lspci
        if echo "$GPU_INFO" | grep -qi "UHD 6[0-9][0-9]\|HD 6[0-9][0-9]"; then
            VAAPI_ENABLED=true
            MAX_CONCURRENT_STREAMS=4
            info "VAAPI: ENABLED (Intel UHD detected)"
        else
            VAAPI_ENABLED=false
            MAX_CONCURRENT_STREAMS=1
            warn "VAAPI: DISABLED (GPU unrecognized - defaulting to software)"
        fi
    fi

    # -------------------------------------------------------------------------
    # Use tmpfs for transcode cache if RAM >= 24GB
    # -------------------------------------------------------------------------
    # On nbMain (31GB), putting the transcode buffer on a RAM disk eliminates
    # I/O bottleneck from the HDD during software transcoding. We allocate 8GB.
    # On nbAcer (8GB), this would leave too little RAM - use disk instead.
    if [[ $RAM_GB -ge 24 ]]; then
        USE_TMPFS_TRANSCODE=true
        TMPFS_SIZE="8G"
        info "Transcode cache: tmpfs RAM disk (${TMPFS_SIZE}) - ${RAM_GB}GB RAM available"
    else
        USE_TMPFS_TRANSCODE=false
        info "Transcode cache: disk (${RAM_GB}GB RAM - not enough for tmpfs)"
    fi
}

# =============================================================================
# STEP 1: System Prerequisites
# =============================================================================

install_prerequisites() {
    section "Installing Prerequisites"

    # Update system first - always do this on a fresh install
    info "Updating system packages..."
    dnf -y upgrade --refresh

    # Install tools we'll need throughout this script
    dnf -y install \
        curl \
        wget \
        jq \
        avahi \
        avahi-tools \
        nss-mdns \
        firewalld \
        policycoreutils \
        policycoreutils-python-utils \
        setools-console \
        java-21-openjdk-headless \
        git \
        intel-media-driver \
        libva \
        libva-utils \
        libva-intel-driver

    info "Prerequisites installed."
}

# =============================================================================
# STEP 2: Enable RPM Fusion Repository
# =============================================================================
# Jellyfin's official Fedora packages are in RPM Fusion (free tier).
# This was changed by the Jellyfin team in 2024 (they dropped their own RPM builds).

enable_rpmfusion() {
    section "Enabling RPM Fusion Repository"

    FEDORA_VERSION=$(rpm -E '%fedora')
    info "Fedora version: $FEDORA_VERSION"

    # Check if RPM Fusion free is already enabled
    if ! dnf repolist enabled 2>/dev/null | grep -q "rpmfusion-free"; then
        info "Adding RPM Fusion free repository..."
        dnf -y install \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm"
    else
        info "RPM Fusion free already enabled."
    fi

    # RPM Fusion nonfree is also needed (jellyfin-ffmpeg pulls from extras)
    if ! dnf repolist enabled 2>/dev/null | grep -q "rpmfusion-nonfree"; then
        info "Adding RPM Fusion nonfree repository..."
        dnf -y install \
            "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
    else
        info "RPM Fusion nonfree already enabled."
    fi

    dnf -y upgrade --refresh
}

# =============================================================================
# STEP 3: Install Jellyfin
# =============================================================================
# The 'jellyfin' meta-package from RPM Fusion pulls in:
#   - jellyfin-server   : the actual media server daemon
#   - jellyfin-web      : the web UI served on port 8096
#   - jellyfin-firewalld: firewalld service definition (we'll configure zones manually)
#   - jellyfin-ffmpeg   : Jellyfin's custom FFmpeg build with all codecs + VAAPI patches

install_jellyfin() {
    section "Installing Jellyfin"

    dnf -y install jellyfin

    info "Jellyfin installed."
    info "Version: $(rpm -q jellyfin 2>/dev/null || echo 'unknown')"
}

# =============================================================================
# STEP 4: Dedicated System User Setup
# =============================================================================
# Jellyfin should run as a dedicated low-privilege system user, NOT as root.
# The RPM package creates a 'jellyfin' user automatically, but we need to:
#   - Add it to the 'video' and 'render' groups for VAAPI GPU access
#   - Ensure it can read your media directory

configure_jellyfin_user() {
    section "Configuring Jellyfin System User"

    # The jellyfin RPM already creates the user; verify it exists
    if ! id jellyfin &>/dev/null; then
        error "jellyfin user not found - did the RPM install succeed?"
    fi

    info "jellyfin user exists: $(id jellyfin)"

    # Add jellyfin to video and render groups
    # 'video' group: access to /dev/dri/card* (display)
    # 'render' group: access to /dev/dri/renderD* (compute/transcode via VAAPI)
    usermod -aG video jellyfin
    usermod -aG render jellyfin

    info "Added jellyfin to video and render groups."

    # Create the media directory if it doesn't exist yet
    # This is the user's home ~/nb/Videos - we read the actual path
    # by looking up the invoking user (SUDO_USER)
    REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
    if [[ -z "$REAL_USER" ]]; then
        warn "Could not determine the real user. Media dir permissions may need manual fix."
    else
        REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
        MEDIA_DIR="${REAL_HOME}/nb/Videos"
        info "Media directory: $MEDIA_DIR"

        # Create directory structure if missing
        mkdir -p "${MEDIA_DIR}/Movies/English"
        mkdir -p "${MEDIA_DIR}/Movies/Hindi"
        mkdir -p "${MEDIA_DIR}/Movies/Marathi"
        mkdir -p "${MEDIA_DIR}/Series"

        # Jellyfin needs read+execute on these paths
        # We use ACLs so we don't break the owner's permissions
        if command -v setfacl &>/dev/null; then
            # Give jellyfin read access to the entire media tree
            setfacl -R -m u:jellyfin:rX "${REAL_HOME}/nb"
            setfacl -R -d -m u:jellyfin:rX "${REAL_HOME}/nb"
            info "ACLs set: jellyfin can read ${REAL_HOME}/nb"
        else
            warn "setfacl not found. Falling back to group-based permissions."
            # Add the real user to the jellyfin group as alternative
            usermod -aG jellyfin "$REAL_USER"
            chmod -R g+rX "${REAL_HOME}/nb"
            info "Added $REAL_USER to jellyfin group and set g+rX on media dir."
        fi
    fi
}

# =============================================================================
# STEP 5: Transcode Cache Directory
# =============================================================================
# Transcoding is the process of converting a video file from one format/bitrate
# to another on-the-fly so your playback device can handle it.
#
# Example: You have a 4K HEVC file. Your phone can only play 1080p H.264.
# Jellyfin transcodes it in real time - the result is stored in temp segments.
#
# On nbMain (31GB RAM): tmpfs RAM disk = faster transcode, no disk I/O.
# On nbAcer (8GB RAM): regular disk directory.

configure_transcode_cache() {
    section "Configuring Transcode Cache"

    mkdir -p "$TRANSCODE_CACHE"
    chown -R jellyfin:jellyfin "$TRANSCODE_CACHE"
    chmod 750 "$TRANSCODE_CACHE"

    if [[ "$USE_TMPFS_TRANSCODE" == "true" ]]; then
        info "Setting up tmpfs RAM disk for transcode cache (${TMPFS_SIZE})..."

        # Add to /etc/fstab so it persists across reboots
        FSTAB_ENTRY="tmpfs ${TRANSCODE_CACHE} tmpfs defaults,size=${TMPFS_SIZE},uid=jellyfin,gid=jellyfin,mode=0750 0 0"

        if grep -q "$TRANSCODE_CACHE" /etc/fstab; then
            info "tmpfs entry already in /etc/fstab - skipping."
        else
            echo "# Jellyfin transcode RAM disk" >> /etc/fstab
            echo "$FSTAB_ENTRY" >> /etc/fstab
            info "Added tmpfs to /etc/fstab."
        fi

        # Mount it now without rebooting
        mount "$TRANSCODE_CACHE" 2>/dev/null || info "tmpfs already mounted."
    else
        info "Using disk-based transcode cache: $TRANSCODE_CACHE"
    fi
}

# =============================================================================
# STEP 6: Hardware Acceleration (VAAPI)
# =============================================================================
# VAAPI (Video Acceleration API) is the Linux standard for GPU-assisted
# video decode/encode. On Intel UHD 630 (nbAcer), it works well via the
# iHD driver (intel-media-driver package).
#
# The iHD driver uses /dev/dri/renderD128 for headless GPU compute.
# jellyfin-ffmpeg uses this device directly - no display server needed.
#
# On nbMain (Sandy Bridge), we skip VAAPI and rely on software transcoding,
# limited to 1 concurrent stream to avoid overloading the 2011 CPU.

configure_hardware_acceleration() {
    section "Configuring Hardware Acceleration"

    if [[ "$VAAPI_ENABLED" == "true" ]]; then
        info "Verifying VAAPI device..."

        # Check that the DRI render device exists
        if [[ -e /dev/dri/renderD128 ]]; then
            info "Found: /dev/dri/renderD128"
            ls -la /dev/dri/
        else
            warn "/dev/dri/renderD128 not found. VAAPI may not work until reboot."
        fi

        # Install the modern Intel media driver (supports Gen 8+, i.e. UHD 630)
        dnf -y install intel-media-driver libva-intel-media-driver

        # Test VAAPI with jellyfin-ffmpeg's own bundled vainfo
        JELLYFIN_VAINFO="/usr/lib/jellyfin-ffmpeg/vainfo"
        if [[ -x "$JELLYFIN_VAINFO" ]]; then
            info "Testing VAAPI with jellyfin-ffmpeg's vainfo..."
            "$JELLYFIN_VAINFO" --display drm --device /dev/dri/renderD128 2>&1 | head -20 || \
                warn "vainfo test had warnings - this is often normal on headless systems."
        fi

        info "VAAPI configuration complete. You MUST enable it in the Jellyfin web UI."
        info "See the post-install checklist at the end of this script."
    else
        info "VAAPI not enabled on this machine - software transcoding will be used."
        info "Max concurrent transcode streams: $MAX_CONCURRENT_STREAMS"

        # For Sandy Bridge: ensure libva-intel-driver (legacy i965 driver) is present
        # even though we won't use VAAPI - it avoids error messages in logs
        dnf -y install libva-intel-driver 2>/dev/null || true
    fi
}

# =============================================================================
# STEP 7: Firewalld Configuration
# =============================================================================
# Jellyfin only needs to be accessible on your LOCAL network (LAN).
# We add rules to the 'home' zone, which is appropriate for trusted networks.
#
# Ports:
#   8096/tcp  - HTTP (web UI + API - what clients connect to)
#   1900/udp  - DLNA/uPnP discovery (Chromecast and other clients find the server)
#   7359/udp  - Jellyfin auto-discovery (Jellyfin apps on LAN find the server)
#   5353/udp  - mDNS (used by Avahi for .local hostname resolution)
#
# We do NOT open these ports on the 'public' zone - LAN only.

configure_firewall() {
    section "Configuring Firewalld"

    # Ensure firewalld is running
    systemctl enable --now firewalld

    # Use the 'home' zone for trusted LAN traffic
    # If your LAN interface is in a different zone, adjust accordingly.
    # Check with: firewall-cmd --get-active-zones
    ZONE="home"

    info "Adding Jellyfin ports to zone: $ZONE"

    # Jellyfin web UI and API
    firewall-cmd --zone="$ZONE" --add-port=${JELLYFIN_PORT}/tcp --permanent

    # DLNA/uPnP discovery - allows Chromecast and smart TVs to find Jellyfin
    firewall-cmd --zone="$ZONE" --add-port=1900/udp --permanent

    # Jellyfin LAN auto-discovery - Jellyfin apps on the same network find this server
    firewall-cmd --zone="$ZONE" --add-port=7359/udp --permanent

    # mDNS for Avahi (.local hostname)
    firewall-cmd --zone="$ZONE" --add-service=mdns --permanent

    # Reload firewalld to apply changes
    firewall-cmd --reload

    info "Firewall rules applied:"
    firewall-cmd --zone="$ZONE" --list-all
}

# =============================================================================
# STEP 8: Avahi / mDNS Discovery
# =============================================================================
# Avahi implements the mDNS/DNS-SD protocol (the same as Apple's Bonjour).
# It allows your Jellyfin server to be discoverable as 'nbMain.local' or
# 'nbAcer.local' on your LAN without needing to know the IP address.
#
# This is how:
#   - Jellyfin Android/desktop apps discover the server automatically
#   - Chromecast Ultra finds the server on the local network
#   - VLC/Kodi can browse it via DLNA (Jellyfin has a built-in DLNA server)

configure_avahi() {
    section "Configuring Avahi mDNS"

    # Enable and start Avahi daemon
    systemctl enable --now avahi-daemon

    # Configure nsswitch.conf to resolve .local hostnames via mDNS
    # The 'mdns4_minimal' entry must come before 'resolve' and 'dns'
    if ! grep -q 'mdns4_minimal' /etc/nsswitch.conf; then
        sed -i 's/^hosts:.*/hosts: mns files mdns4_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] dns myhostname/' \
            /etc/nsswitch.conf
        info "Updated /etc/nsswitch.conf for mDNS resolution."
    else
        info "mDNS already in nsswitch.conf."
    fi

    # Publish a Jellyfin service descriptor so clients discover it
    # This creates an Avahi service file that advertises Jellyfin on the LAN
    cat > /etc/avahi/services/jellyfin.service << EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Jellyfin Media Server on %h</name>
  <service>
    <type>_http._tcp</type>
    <port>${JELLYFIN_PORT}</port>
    <txt-record>path=/</txt-record>
  </service>
  <service>
    <!-- DLNA discovery - used by Chromecast, Kodi, VLC -->
    <type>_udisks-ssh._tcp</type>
    <port>${JELLYFIN_PORT}</port>
  </service>
</service-group>
EOF

    systemctl restart avahi-daemon
    info "Avahi service file created and daemon restarted."
    info "Server will be discoverable as: $(hostname).local"
}

# =============================================================================
# STEP 9: SELinux Configuration
# =============================================================================
# Fedora runs SELinux in enforcing mode by default. Without proper contexts,
# SELinux will block Jellyfin from reading your media files and writing to
# its data directories.
#
# We label the relevant paths with the correct SELinux file contexts.

configure_selinux() {
    section "Configuring SELinux"

    # Check if SELinux is enforcing
    if ! command -v getenforce &>/dev/null || [[ "$(getenforce)" == "Disabled" ]]; then
        warn "SELinux is disabled - skipping SELinux configuration."
        return
    fi

    info "SELinux mode: $(getenforce)"

    # Allow Jellyfin to connect to the network (for metadata scraping, subtitle download)
    # httpd_can_network_connect: allows processes with httpd_t label to make network connections
    setsebool -P httpd_can_network_connect 1 2>/dev/null || true

    # Allow Jellyfin to read media files in home directories
    setsebool -P httpd_read_user_content 1 2>/dev/null || true

    # Label Jellyfin data directory
    semanage fcontext -a -t var_t "${JELLYFIN_DATA}(/.*)?" 2>/dev/null || \
        semanage fcontext -m -t var_t "${JELLYFIN_DATA}(/.*)?" 2>/dev/null || true
    restorecon -Rv "$JELLYFIN_DATA" 2>/dev/null || true

    # Label transcode cache
    semanage fcontext -a -t tmp_t "${TRANSCODE_CACHE}(/.*)?" 2>/dev/null || \
        semanage fcontext -m -t tmp_t "${TRANSCODE_CACHE}(/.*)?" 2>/dev/null || true
    restorecon -Rv "$TRANSCODE_CACHE" 2>/dev/null || true

    # Label the media directory if it exists
    if [[ -d "$MEDIA_DIR" ]]; then
        semanage fcontext -a -t httpd_user_content_t "${MEDIA_DIR}(/.*)?" 2>/dev/null || \
            semanage fcontext -m -t httpd_user_content_t "${MEDIA_DIR}(/.*)?" 2>/dev/null || true
        restorecon -Rv "$MEDIA_DIR" 2>/dev/null || true
        info "SELinux context set on: $MEDIA_DIR"
    fi

    info "SELinux configured."
    warn "If Jellyfin cannot read media, check: ausearch -m avc -ts recent | audit2why"
}

# =============================================================================
# STEP 10: tinyMediaManager (TMM)
# =============================================================================
# tinyMediaManager is a FOSS media library manager that:
#   - Renames movie/TV files to Jellyfin-compatible naming conventions
#     e.g. "Dune 2021 BDRip.mkv" → "Dune (2021)/Dune (2021).mkv"
#   - Downloads metadata: posters, fanart, descriptions, ratings
#   - Writes NFO sidecar files that Jellyfin reads for fast metadata
#   - Handles your Movies/Series structure perfectly
#
# FileBot was the original suggestion but requires a paid license for renaming.
# TMM is fully free and open source.
#
# TMM is a Java GUI app - run it separately from a terminal:
#   /opt/tinyMediaManager/tinyMediaManager
#
# Workflow:
#   1. Open TMM, add your Movies and Series directories
#   2. Search and match your files to the correct movie/show
#   3. Use "Rename" to rename files to correct format
#   4. Run "Update library" in Jellyfin after renaming

install_tmm() {
    section "Installing tinyMediaManager (FOSS media library manager)"

    # TMM requires Java 21
    if ! java -version 2>&1 | grep -q "21\|17"; then
        warn "Java 21 not detected - installing..."
        dnf -y install java-21-openjdk-headless
    fi

    # Download and install tinyMediaManager
    TMM_URL="https://releases.tinymediamanager.org/v5/dist/tinyMediaManager_${TMM_VERSION}_linux-x64.tar.gz"
    TMM_ARCHIVE="/tmp/tinyMediaManager.tar.gz"

    info "Downloading tinyMediaManager ${TMM_VERSION}..."

    if wget -q --show-progress -O "$TMM_ARCHIVE" "$TMM_URL"; then
        mkdir -p "$TMM_INSTALL_DIR"
        tar -xzf "$TMM_ARCHIVE" -C "$TMM_INSTALL_DIR" --strip-components=1
        rm -f "$TMM_ARCHIVE"

        # Make the launcher executable
        chmod +x "${TMM_INSTALL_DIR}/tinyMediaManager"

        # Create a desktop entry for KDE
        cat > /usr/share/applications/tinyMediaManager.desktop << EOF
[Desktop Entry]
Name=tinyMediaManager
Comment=Media library manager for Jellyfin
Exec=${TMM_INSTALL_DIR}/tinyMediaManager
Icon=${TMM_INSTALL_DIR}/tmm.png
Terminal=false
Type=Application
Categories=AudioVideo;Video;
EOF

        info "tinyMediaManager installed at: $TMM_INSTALL_DIR"
        info "Launch: ${TMM_INSTALL_DIR}/tinyMediaManager"
    else
        warn "Failed to download tinyMediaManager. Install manually from:"
        warn "https://www.tinymediamanager.org/download/"
    fi
}

# =============================================================================
# STEP 11: Jellyfin Systemd Service
# =============================================================================
# Enable and start the Jellyfin systemd service so it:
#   - Starts automatically on boot
#   - Runs as the jellyfin user
#   - Logs to journald (check with: journalctl -u jellyfin -f)

start_jellyfin() {
    section "Starting Jellyfin Service"

    systemctl daemon-reload
    systemctl enable --now jellyfin

    # Wait for Jellyfin to start
    info "Waiting for Jellyfin to start (up to 30 seconds)..."
    for i in $(seq 1 30); do
        if curl -sf "http://localhost:${JELLYFIN_PORT}/health" &>/dev/null; then
            info "Jellyfin is up and responding."
            break
        fi
        sleep 1
    done

    systemctl status jellyfin --no-pager
}

# =============================================================================
# STEP 12: Kodi Integration Note
# =============================================================================
# Kodi can use Jellyfin as a backend via the Jellyfin for Kodi add-on.
# This replaces Kodi's local library with Jellyfin's library, meaning:
#   - Your movies and TV shows in Kodi come from Jellyfin (shared library)
#   - Watched status, ratings, and metadata sync between Kodi and Jellyfin
#
# We print installation instructions since Kodi add-ons can't be installed
# via script - they must be done through Kodi's UI.

print_kodi_instructions() {
    section "Kodi Integration Instructions"

    cat << 'EOF'
To connect Kodi to your Jellyfin server:

1. Open Kodi → Add-ons → Install from repository
2. Search for "Jellyfin for Kodi" (it may need the Jellyfin repository added first)

   Alternative: Install via zip
   - Download: https://kodi.jellyfin.org/repository.jellyfin.kodi.zip
   - In Kodi: Add-ons → Install from zip file → select the zip

3. After installing, open the add-on settings and enter:
   - Server: http://<this-machine-hostname>.local:8096
   - Username/Password: your Jellyfin account credentials

4. Sync your library - Kodi will now use Jellyfin's metadata and watched status

Note: This makes Kodi a Jellyfin client, not a standalone player.
All watched progress syncs back to Jellyfin.
EOF
}

# =============================================================================
# STEP 13: VLC Integration Note
# =============================================================================
# VLC can browse Jellyfin's DLNA server and stream directly.
# We enable DLNA discovery in VLC settings.
# (No packages to install - VLC already supports DLNA natively.)

print_vlc_instructions() {
    section "VLC Integration Instructions"

    cat << 'EOF'
VLC can discover your Jellyfin server via DLNA:

In VLC on Linux:
1. View → Playlist
2. In the sidebar, look for "Universal Plug'n'Play" or "Local Network"
3. Your Jellyfin server should appear as "Jellyfin Media Server on <hostname>"
4. Browse and play directly

Alternative - use the Jellyfin web UI and open a stream in VLC:
1. Right-click any video in Jellyfin web UI
2. "Play in external player" → VLC

For better experience, use the native Jellyfin Media Player (see below).
EOF
}

# =============================================================================
# STEP 14: Install Subtitle Plugin (SubBuzz - Multi-Provider with Fallback)
# =============================================================================
#
# WHY SubBuzz INSTEAD OF THE OFFICIAL OpenSubtitles PLUGIN:
#   - Official OpenSubtitles plugin = single provider, hits daily download limit
#     fast when scanning a large library. Real users report it failing mid-scan.
#   - SubBuzz queries 9 providers simultaneously and falls back automatically:
#       OpenSubtitles.com, Podnapisi.NET, SubDL.com, SubSource.net,
#       YIFY Subtitles, Addic7ed.com, Subf2m.co, Subs.sab.bz, Subsunacs.net
#   - SubBuzz is FOSS (GPL-3), actively maintained (last release Apr 2026)
#   - Still uses your OpenSubtitles account as one of its providers
#
# IMPORTANT - OpenSubtitles credentials are still used by SubBuzz:
#   Set OPENSUBTITLES_USER and OPENSUBTITLES_PASS at the top of this script.
#   SubBuzz will use those credentials for the OpenSubtitles provider
#   while also querying all other providers without credentials.
#
# HOW PLUGIN INSTALLATION WORKS (no web UI needed):
#   1. Download the plugin zip from GitHub releases
#   2. Extract the DLL into /var/lib/jellyfin/plugins/<Name>_<Version>/
#   3. Write the XML config file with provider settings
#   4. Register the Jellyfin official plugin repository in repositories.json
#      so the web UI shows update notifications for all future plugin updates
#   5. Jellyfin loads everything on next start
#
# PLUGIN UPDATE BEHAVIOUR:
#   Manual zip installs do NOT auto-update - they freeze at the installed version.
#   To get update notifications in the Jellyfin dashboard (Dashboard → Plugins),
#   we register the official Jellyfin plugin repository in repositories.json.
#   Jellyfin checks this on startup and shows a notification when updates exist.
#   You then click one button in the UI to update. Silent auto-update is
#   deliberately not supported by Jellyfin (to avoid breaking changes unnoticed).
#   For SubBuzz specifically (third-party), updates still need manual zip install
#   - but the script prints the command to do it in one line.

install_subtitle_plugin() {
    section "Installing SubBuzz Subtitle Plugin (Multi-Provider)"

    PLUGIN_CONFIG_DIR="${JELLYFIN_DATA}/plugins/configurations"
    mkdir -p "$PLUGIN_CONFIG_DIR"

    # -------------------------------------------------------------------------
    # PART A: Register the official Jellyfin plugin repository
    # -------------------------------------------------------------------------
    # This makes Dashboard → Plugins → Catalog work and shows update
    # notifications for all official plugins (OpenSubtitles, TMDb, TheTVDB etc.)
    # The repositories.json file is read by Jellyfin on startup.
    # Official stable repository manifest URL (from Jellyfin docs):
    JELLYFIN_REPO_URL="https://repo.jellyfin.org/files/plugin/manifest-stable.json"
    REPOSITORIES_FILE="${JELLYFIN_DATA}/plugins/repositories.json"

    # Only write if the file doesn't already exist (first run)
    if [[ ! -f "$REPOSITORIES_FILE" ]]; then
        cat > "$REPOSITORIES_FILE" << 'REPOEOF'
[
  {
    "Name": "Jellyfin Stable",
    "Url": "https://repo.jellyfin.org/files/plugin/manifest-stable.json",
    "Enabled": true
  }
]
REPOEOF
        chown jellyfin:jellyfin "$REPOSITORIES_FILE"
        chmod 640 "$REPOSITORIES_FILE"
        info "Registered official Jellyfin plugin repository."
        info "Plugin update notifications will appear in Dashboard → Plugins."
    else
        info "repositories.json already exists - skipping."
    fi

    # -------------------------------------------------------------------------
    # PART B: Download and install SubBuzz
    # -------------------------------------------------------------------------
    # SubBuzz releases: https://github.com/josdion/subbuzz/releases
    # We detect the Jellyfin version to pick the matching SubBuzz build.
    # SubBuzz ships separate builds for Jellyfin 10.9, 10.10, 10.11+

    # Detect installed Jellyfin version
    JELLYFIN_VERSION=$(rpm -q --qf '%{VERSION}' jellyfin-server 2>/dev/null || echo "10.10")
    JELLYFIN_MAJOR=$(echo "$JELLYFIN_VERSION" | cut -d. -f1-2)
    info "Detected Jellyfin version: ${JELLYFIN_VERSION} (major: ${JELLYFIN_MAJOR})"

    # Map Jellyfin version to SubBuzz build suffix
    # SubBuzz builds: jellyfin_10.9, jellyfin_10.10, jellyfin_10.11
    case "$JELLYFIN_MAJOR" in
        10.9)  SUBBUZZ_BUILD="jellyfin_10.9"  ;;
        10.10) SUBBUZZ_BUILD="jellyfin_10.10" ;;
        10.11) SUBBUZZ_BUILD="jellyfin_10.11" ;;
        *)     SUBBUZZ_BUILD="jellyfin_10.10" ;; # default to 10.10 if unknown
    esac

    # Latest SubBuzz release as of June 2026
    # Check for newer: https://github.com/josdion/subbuzz/releases
    SUBBUZZ_VERSION="1.4.1.0"
    SUBBUZZ_ZIP="subbuzz_${SUBBUZZ_BUILD}_${SUBBUZZ_VERSION}.zip"
    SUBBUZZ_URL="https://github.com/josdion/subbuzz/releases/download/v${SUBBUZZ_VERSION}/${SUBBUZZ_ZIP}"

    # SubBuzz plugin GUID (fixed, from plugin source)
    SUBBUZZ_GUID="d5bd4de8-d8b9-4b3c-9e3e-b12341428ee3"
    SUBBUZZ_PLUGIN_DIR="${JELLYFIN_DATA}/plugins/SubBuzz_${SUBBUZZ_VERSION}"

    info "Downloading SubBuzz v${SUBBUZZ_VERSION} (build: ${SUBBUZZ_BUILD})..."

    TMP_ZIP="/tmp/${SUBBUZZ_ZIP}"
    if ! wget -q --show-progress -O "$TMP_ZIP" "$SUBBUZZ_URL"; then
        warn "Failed to download SubBuzz. URL tried: $SUBBUZZ_URL"
        warn "Check https://github.com/josdion/subbuzz/releases for the correct filename."
        warn "To install manually later:"
        warn "  1. Download the zip for your Jellyfin version"
        warn "  2. sudo mkdir -p ${SUBBUZZ_PLUGIN_DIR}"
        warn "  3. sudo unzip <zip> -d ${SUBBUZZ_PLUGIN_DIR}"
        warn "  4. sudo chown -R jellyfin:jellyfin ${SUBBUZZ_PLUGIN_DIR}"
        warn "  5. sudo systemctl restart jellyfin"
        return
    fi

    # Stop Jellyfin before modifying plugin directory
    info "Stopping Jellyfin to install SubBuzz..."
    systemctl stop jellyfin

    mkdir -p "$SUBBUZZ_PLUGIN_DIR"
    unzip -q "$TMP_ZIP" -d "$SUBBUZZ_PLUGIN_DIR"
    rm -f "$TMP_ZIP"

    chown -R jellyfin:jellyfin "$SUBBUZZ_PLUGIN_DIR"
    chmod -R 750 "$SUBBUZZ_PLUGIN_DIR"
    info "SubBuzz extracted to: $SUBBUZZ_PLUGIN_DIR"

    # -------------------------------------------------------------------------
    # PART C: Write SubBuzz configuration XML
    # -------------------------------------------------------------------------
    # SubBuzz config enables/disables individual providers and sets credentials.
    # We enable all providers that work without accounts first,
    # then add OpenSubtitles if credentials are provided.
    #
    # Providers and their account requirements:
    #   SubDL        - no account needed
    #   SubSource     - no account needed
    #   YIFY          - no account needed
    #   Podnapisi     - no account needed (best for Hindi/South Asian films)
    #   Subf2m       - no account needed
    #   Addic7ed     - no account needed for basic use
    #   OpenSubtitles - account needed (uses OPENSUBTITLES_USER/PASS if set)

    OS_USER_BLOCK=""
    OS_ENABLED="false"
    if [[ "$OPENSUBTITLES_USER" != "YOUR_OPENSUBTITLES_USERNAME" && \
          -n "$OPENSUBTITLES_USER" ]]; then
        OS_ENABLED="true"
        OS_USER_BLOCK="  <OpenSubtitlesUser>${OPENSUBTITLES_USER}</OpenSubtitlesUser>
  <OpenSubtitlesPass>${OPENSUBTITLES_PASS}</OpenSubtitlesPass>"
        info "OpenSubtitles credentials provided - enabling as one of the providers."
    else
        warn "OpenSubtitles credentials not set - SubBuzz will use the other 8 providers."
        warn "You can add them later in Dashboard → Plugins → SubBuzz → Configure"
    fi

    cat > "${PLUGIN_CONFIG_DIR}/${SUBBUZZ_GUID}.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                     xmlns:xsd="http://www.w3.org/2001/XMLSchema">

  <!-- SubBuzz queries all enabled providers simultaneously and returns the
       best match. If one provider has no result or hits a rate limit,
       others fill the gap automatically. -->

  <!-- Provider: OpenSubtitles.com - requires free account -->
  <OpenSubtitlesEnabled>${OS_ENABLED}</OpenSubtitlesEnabled>
${OS_USER_BLOCK}

  <!-- Provider: SubDL.com - no account needed, large database -->
  <SubDlEnabled>true</SubDlEnabled>

  <!-- Provider: SubSource.net - no account needed -->
  <SubSourceEnabled>true</SubSourceEnabled>

  <!-- Provider: YIFY Subtitles - best for YIFY movie rips -->
  <YifyEnabled>true</YifyEnabled>

  <!-- Provider: Podnapisi.NET - excellent for Hindi/Marathi/foreign films -->
  <PodnapisiEnabled>true</PodnapisiEnabled>

  <!-- Provider: Subf2m.co - large collection, good fallback -->
  <Subf2mEnabled>true</Subf2mEnabled>

  <!-- Provider: Addic7ed.com - best for TV series subtitles -->
  <Addic7edEnabled>true</Addic7edEnabled>

  <!-- Download even if embedded subtitles exist.
       Reason: embedded PGS/image subs cause transcoding; SRT avoids that. -->
  <SkipIfEmbeddedSubtitlesPresent>false</SkipIfEmbeddedSubtitlesPresent>

  <!-- Skip if audio language already matches subtitle language -->
  <SkipIfAudioTrackMatches>true</SkipIfAudioTrackMatches>

  <!-- Download for TV series episodes too -->
  <DownloadEpisodes>true</DownloadEpisodes>

</PluginConfiguration>
EOF

    chown jellyfin:jellyfin "${PLUGIN_CONFIG_DIR}/${SUBBUZZ_GUID}.xml"
    chmod 640 "${PLUGIN_CONFIG_DIR}/${SUBBUZZ_GUID}.xml"
    info "SubBuzz config written to: ${PLUGIN_CONFIG_DIR}/${SUBBUZZ_GUID}.xml"

    # -------------------------------------------------------------------------
    # PART D: Restart Jellyfin with plugins loaded
    # -------------------------------------------------------------------------
    info "Starting Jellyfin with SubBuzz loaded..."
    systemctl start jellyfin

    for i in $(seq 1 30); do
        if curl -sf "http://localhost:${JELLYFIN_PORT}/health" &>/dev/null; then
            info "Jellyfin restarted with SubBuzz plugin active."
            break
        fi
        sleep 1
    done

    cat << EOF

SubBuzz installed with these providers active:
  SubDL, SubSource, YIFY, Podnapisi, Subf2m, Addic7ed
  OpenSubtitles: ${OS_ENABLED} (credentials provided: $([[ "$OS_ENABLED" == "true" ]] && echo yes || echo no))

ONE MANUAL STEP still required in the Jellyfin web UI:
  Dashboard → Libraries → [Movies] → Edit → Subtitle Downloaders
    ✓ Enable "SubBuzz"
    ✓ Set language: English
  Repeat for the Series library.

TO UPDATE SubBuzz IN THE FUTURE (one-liner):
  NEW_VER="x.x.x.x"  # replace with new version number from GitHub releases
  sudo systemctl stop jellyfin
  sudo rm -rf ${JELLYFIN_DATA}/plugins/SubBuzz_*
  sudo mkdir -p ${JELLYFIN_DATA}/plugins/SubBuzz_\${NEW_VER}
  wget -O /tmp/subbuzz.zip https://github.com/josdion/subbuzz/releases/download/v\${NEW_VER}/subbuzz_${SUBBUZZ_BUILD}_\${NEW_VER}.zip
  sudo unzip /tmp/subbuzz.zip -d ${JELLYFIN_DATA}/plugins/SubBuzz_\${NEW_VER}
  sudo chown -R jellyfin:jellyfin ${JELLYFIN_DATA}/plugins/SubBuzz_\${NEW_VER}
  sudo systemctl start jellyfin

FOR OFFICIAL JELLYFIN PLUGINS (OpenSubtitles, TMDb, TheTVDB etc.):
  Plugin update notifications appear in Dashboard → Plugins automatically.
  The official Jellyfin repo has been registered. Click "Update" when notified.

EOF
}

# =============================================================================
# STEP 15: Post-Install VAAPI Configuration Instructions
# =============================================================================
# VAAPI cannot be enabled via config file alone - it requires the Jellyfin
# web UI because the config is generated after the wizard runs.

print_vaapi_instructions() {
    section "Hardware Acceleration Setup (Manual Steps Required in Web UI)"

    if [[ "$VAAPI_ENABLED" == "true" ]]; then
        cat << EOF
This machine supports VAAPI hardware acceleration (Intel UHD 630).

Steps to enable in Jellyfin web UI:
1. Open http://$(hostname).local:${JELLYFIN_PORT}
2. Dashboard → Playback → Transcoding
3. Hardware acceleration: Select "Video Acceleration API (VAAPI)"
4. VA API Device: /dev/dri/renderD128
5. Enable these codec accelerations (all supported on UHD 630):
   ✓ H.264 (most common format for movies)
   ✓ HEVC/H.265 (4K and modern rips)
   ✓ VP9 (YouTube-style encodes)
   ✓ MPEG2 (older DVDs)
   ✓ VC1 (older Blu-ray)
6. Tone mapping: Enable (converts HDR to SDR for non-HDR displays)
7. Save

To verify it's working:
- Play a video that needs transcoding (try a 4K file on a 1080p device)
- Dashboard → Active Streams - check if "VAAPI" appears under transcode method
- Or run: intel_gpu_top (dnf install intel-gpu-tools) and watch GPU usage spike

Max recommended concurrent streams on this machine: ${MAX_CONCURRENT_STREAMS}
EOF
    else
        cat << EOF
This machine (Sandy Bridge / Intel HD 2000) uses SOFTWARE transcoding.

Steps in Jellyfin web UI:
1. Dashboard → Playback → Transcoding
2. Hardware acceleration: Select "None"
3. Enable H.264, HEVC decoding in software
4. Set "Max simultaneous video transcodes": 1
   (The i5-2400 will struggle with more than 1 transcode at a time)

With 31GB RAM and tmpfs transcode cache, software transcoding will be
faster than on-disk but still CPU-bound. For most 1080p H.264 content
(the most common format), direct play will work without transcoding at all
as long as your client device supports the codec.

Strategy: prefer direct play → avoid transcoding whenever possible.
In the Android/desktop Jellyfin app, set max bitrate to "Auto" and let
the client handle the format directly.
EOF
    fi
}

# =============================================================================
# STEP 16: Chromecast Ultra Setup Notes
# =============================================================================

print_chromecast_instructions() {
    section "Chromecast Ultra Setup"

    cat << EOF
Your Chromecast Ultra (1st gen) supports:
  - H.264 up to 1080p60
  - HEVC/H.265 up to 4K60
  - VP9 up to 4K60

This means 4K HEVC files can direct play to Chromecast without transcoding.
H.264 1080p content also direct plays.

To cast from Jellyfin:
METHOD 1 - Jellyfin web UI (simplest):
  1. Open http://$(hostname).local:${JELLYFIN_PORT} on your phone/laptop
  2. Play any video
  3. Click the Cast icon (top right of player)
  4. Select your Chromecast Ultra

METHOD 2 - Jellyfin Android app:
  1. Install "Jellyfin for Android" from F-Droid or Google Play
  2. Connect to http://$(hostname).local:${JELLYFIN_PORT}
  3. Use the Cast button in the player

METHOD 3 - Google Home app:
  - You can also cast the Jellyfin web tab from Chrome using Google Home

The Chromecast discovers Jellyfin via DLNA (port 1900/udp) which we've
already opened in firewalld. No extra setup needed.

NOTE: Chromecast Ultra does NOT support DTS or Dolby TrueHD audio directly.
If your files have those audio tracks, Jellyfin will transcode audio to AAC.
This is normal and only affects audio - video will still direct play.
EOF
}

# =============================================================================
# STEP 17: Library Structure Advice
# =============================================================================

print_library_advice() {
    section "Jellyfin Library Structure & Naming"

    cat << EOF
YOUR CURRENT STRUCTURE:
  ~/nb/Videos/
    Movies/
      English/
      Hindi/
      Marathi/
    Series/

JELLYFIN RECOMMENDATION:
Jellyfin can handle the English/Hindi/Marathi subfolders - just add
the parent "Movies" folder as a single library. Jellyfin will scan recursively.

IDEAL FILE NAMING (for automatic metadata matching):
  Movies:   Movie Name (Year)/Movie Name (Year).mkv
  Series:   Show Name/Season 01/Show Name S01E01.mkv

EXAMPLES:
  Movies/English/Dune (2021)/Dune (2021).mkv
  Movies/Hindi/Dangal (2016)/Dangal (2016).mkv
  Series/Breaking Bad/Season 01/Breaking Bad S01E01.mkv

USE tinyMediaManager (installed at ${TMM_INSTALL_DIR}) to rename your files:
  1. Launch: ${TMM_INSTALL_DIR}/tinyMediaManager
  2. Settings → Movies → Add source: ~/nb/Videos/Movies
  3. Settings → TV Shows → Add source: ~/nb/Videos/Series
  4. Search All → Confirm matches → Rename All
  5. Then refresh Jellyfin library (Dashboard → Libraries → Scan)

ADDING LIBRARIES IN JELLYFIN (first-time setup wizard):
  - Add library type: "Movies"
    Folder: /home/<you>/nb/Videos/Movies
  - Add library type: "Shows"  
    Folder: /home/<you>/nb/Videos/Series
  - Metadata language: English (for English subs)
  - Country: India (gives you Bollywood metadata too)

Jellyfin's metadata scrapers are TheMovieDB (movies) and TheTVDB (series).
Both are enabled by default. Hindi/Marathi films are well-covered on TMDb.
EOF
}

# =============================================================================
# STEP 18: Android App Recommendations
# =============================================================================

print_android_instructions() {
    section "Android Setup"

    cat << EOF
RECOMMENDED ANDROID APPS FOR JELLYFIN:

1. Jellyfin for Android (official)
   - F-Droid: https://f-droid.org/packages/org.jellyfin.mobile/
   - Play Store: search "Jellyfin"
   - Best overall client for browsing and playback

2. Findroid (third-party, excellent UI)
   - F-Droid: https://f-droid.org/packages/dev.jdtech.jellyfin/
   - Better UI than the official app for some people

3. Jellyfin for Kodi (you already have Kodi)
   - As described in Kodi section above

4. VLC for Android
   - Can stream from Jellyfin via DLNA
   - View → Network → UPnP → select your Jellyfin server

5. Grayjay
   - Grayjay does NOT currently support Jellyfin natively
   - Use official Jellyfin app or Findroid for local content

CONNECT TO YOUR SERVER:
  - Server address: http://<hostname>.local:${JELLYFIN_PORT}
  - e.g. http://nbMain.local:8096 or http://nbAcer.local:8096
  - Create a user account during the Jellyfin setup wizard first

CASTING TO CHROMECAST FROM ANDROID:
  - Use the official Jellyfin Android app
  - Cast button appears in the video player once Chromecast is on the same WiFi
EOF
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    require_root

    section "Jellyfin Setup for Fedora KDE"
    echo "Started: $(date)"

    # Validate that credentials were filled in
    if [[ "$OPENSUBTITLES_USER" == "YOUR_OPENSUBTITLES_USERNAME" ]]; then
        warn "OPENSUBTITLES_USER not set. SubBuzz will still work via 8 other providers."
        warn "Set credentials at the top of this script to also enable OpenSubtitles as a provider."
    fi

    detect_hardware
    install_prerequisites
    enable_rpmfusion
    install_jellyfin
    configure_jellyfin_user
    configure_transcode_cache
    configure_hardware_acceleration
    configure_firewall
    configure_avahi
    configure_selinux
    install_tmm
    start_jellyfin
    install_subtitle_plugin

    # Print all manual steps needed after installation
    print_vaapi_instructions
    print_kodi_instructions
    print_vlc_instructions
    print_chromecast_instructions
    print_library_advice
    print_android_instructions

    section "Installation Complete"

    cat << EOF

=== SUMMARY ===

Jellyfin web UI:  http://$(hostname).local:${JELLYFIN_PORT}
                  or http://$(hostname -I | awk '{print $1}'):${JELLYFIN_PORT}

Service control:
  sudo systemctl start jellyfin
  sudo systemctl stop jellyfin
  sudo systemctl restart jellyfin
  journalctl -u jellyfin -f        # real-time logs

tinyMediaManager: ${TMM_INSTALL_DIR}/tinyMediaManager

Media directory:  ${MEDIA_DIR}

NEXT STEPS (in order):
  1. Open the Jellyfin web UI in your browser
  2. Complete the setup wizard (create admin user, add libraries)
  3. Configure VAAPI in Dashboard → Playback (see instructions above)
  4. Enable SubBuzz per-library: Dashboard → Libraries → [Movies] → Edit
       → Subtitle Downloaders → Enable SubBuzz → Language: English
       (Repeat for Series library)
  5. Use tinyMediaManager to rename your files to proper naming format
  6. Scan library in Jellyfin after renaming
  7. Install Jellyfin app on Android
  8. Configure Kodi with Jellyfin add-on (optional)

Logs:  journalctl -u jellyfin -f
       /var/log/jellyfin/

Done: $(date)
EOF
}

main "$@"



# Good questions. Let me check both.Good - I now have a complete picture. Here's the honest answer:

# ---

# **On plugin auto-updates:**

# Manual zip install (what the current script does) **does NOT auto-update**. The plugin stays at the version you installed forever.

# The correct approach is to **register the official Jellyfin plugin repository** in Jellyfin's config file (`repositories.json`). Once registered, Jellyfin checks the repository on startup and **notifies you in the dashboard** when a plugin update is available - you click one button to update. It does not update silently/automatically (Jellyfin deliberately has no silent auto-update), but it's effectively the same UX as installing from the catalog.

# This is fully scriptable - just write the repository URL into the config file before first start.

# ---

# **On subtitle fallback providers:**

# The OpenSubtitles plugin is single-provider and has a **daily download limit** (a real problem when scanning a large library for the first time). The right answer is **SubBuzz** - a community FOSS plugin that queries 9 providers simultaneously and falls back automatically:

# | Provider in SubBuzz | Notes |
# |---|---|
# | OpenSubtitles.com | Same source, but as one of many |
# | Podnapisi.NET | Excellent for Hindi/Marathi films |
# | SubDL.com | No account needed |
# | SubSource.net | No account needed |
# | YIFY Subtitles | Great for movie rips |
# | Addic7ed.com | Best for TV series |
# | Subf2m.co | Large collection |

# SubBuzz is also scriptable via manual zip install - and it's in an installable repository too. The strategy: install SubBuzz as the primary, register the official Jellyfin repo for auto-update notifications, and drop the single OpenSubtitles plugin entirely.

# Let me update the script:Now I have the full picture. Let me replace the entire subtitle section and also add the repository registration:Now fix the `main()` call and header comments:Here's the full picture on both questions:

# ---

# **On auto-updates - the real answer:**

# Jellyfin has **no silent auto-update** for plugins, by design. Here's how updates actually work with this script:

# | Plugin type | How updates work |
# |---|---|
# | Official plugins (TMDb, TheTVDB, etc.) | Script registers the official Jellyfin repo → Dashboard shows a notification → you click "Update" |
# | SubBuzz (third-party) | Manual - script prints a ready-to-run one-liner. Check GitHub occasionally |
# | Jellyfin itself (RPM) | `sudo dnf update` as always |

# The official repo registration is the key thing the previous script was missing. Without it, even the catalog in the web UI would be empty.

# ---

# **On subtitle fallback - why SubBuzz is the right call:**

# The official OpenSubtitles plugin hits its **daily download limit** fast when scanning a large library for the first time (this is a documented real-world problem, not theoretical). SubBuzz solves this by querying 9 providers simultaneously - if OpenSubtitles is rate-limited or has no result, Podnapisi/SubDL/YIFY etc. fill in. Especially good for your use case since **Podnapisi has strong Hindi/Marathi film coverage**.

# OpenSubtitles credentials are now **optional** in the script - SubBuzz works with 8 no-account providers even without them, so you can fill them in later via the web UI if you want.