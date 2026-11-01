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
#   8. Configures SELinux contexts for Jellyfin data and media paths
#   9. Adds Jellyfin transcode cache to tmpfs (RAM disk) on nbMain (31GB RAM)
#  10. Prints post-install checklist including OpenSubtitles plugin setup
#
# What you must fill in before running:
#   - OPENSUBTITLES_USER  : your opensubtitles.com username
#   - OPENSUBTITLES_PASS  : your opensubtitles.com password
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
# STEP 14: Print OpenSubtitles Setup Instructions
# =============================================================================
# OpenSubtitles plugin must be configured through the Jellyfin web UI.
# It cannot be scripted because the plugin installs itself from the catalog
# and stores credentials in its own encrypted config file.

print_opensubtitles_instructions() {
    section "OpenSubtitles Plugin Setup (Manual Steps Required)"

    cat << EOF
Your OpenSubtitles credentials for reference:
  Username: ${OPENSUBTITLES_USER}
  Password: (the one you set in this script)

Steps to configure in Jellyfin web UI:
1. Open http://$(hostname).local:${JELLYFIN_PORT} in your browser
2. Log in as administrator
3. Dashboard → Plugins → Catalog
4. Search for "OpenSubtitles" → Install
5. Restart Jellyfin: sudo systemctl restart jellyfin
6. Dashboard → Plugins → OpenSubtitles → Configure
7. Enter your opensubtitles.com credentials (use .com not .org)
8. Click "Validate and Save"

Then enable auto-subtitle download per library:
9. Dashboard → Libraries → [Movies] → Edit → Subtitle Downloaders
10. Enable OpenSubtitles, set language to English
11. Repeat for Series library

For videos WITHOUT any subtitles, Jellyfin will auto-search and download.
For videos WITH embedded subtitles (e.g. forced subs in MKV), those play directly.
For videos WITH external .srt files in the same folder, Jellyfin picks them up automatically.

IMPORTANT: SRT subtitles = direct play (no performance hit)
           PGS/ASS/image subtitles = may trigger transcoding (CPU/GPU usage)
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
        warn "OPENSUBTITLES_USER is not set. Subtitle auto-download will need manual setup."
        warn "Edit the script and fill in OPENSUBTITLES_USER and OPENSUBTITLES_PASS."
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

    # Print all manual steps needed after installation
    print_vaapi_instructions
    print_opensubtitles_instructions
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
  4. Install and configure OpenSubtitles plugin (see instructions above)
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



# Perfect. Writing the script now.Important finding: **FileBot's rename feature requires a paid license** (~$6/year or $48 lifetime). It's not free for renaming. Better FOSS alternative: **tinyMediaManager** (free, open source, does metadata + renaming, Jellyfin-compatible). I'll use that instead.

# Now writing the script.Here's what the script does and the key decisions made:

# ---

# **Hardware decisions applied:**

# | Machine | Transcoding | Cache | Max Streams |
# |---|---|---|---|
# | nbMain (i5-2400, 31GB) | Software only (Sandy Bridge too old for reliable VAAPI) | 8GB tmpfs RAM disk | 1 |
# | nbAcer (i5-8400, 8GB) | VAAPI via Intel UHD 630 iHD driver | Disk | 4 |

# ---

# **What the script installs and configures:**

# - Jellyfin via RPM Fusion (the current official Fedora path - they dropped their own RPM repo in 2024)
# - `jellyfin` dedicated system user, added to `video` + `render` groups
# - Firewalld: ports 8096 (UI), 1900 (DLNA), 7359 (Jellyfin discovery), mDNS - LAN only, home zone
# - Avahi: publishes Jellyfin so clients see `nbMain.local:8096` automatically - no IP needed
# - SELinux: proper file contexts on media dir, data dir, and transcode cache
# - VAAPI packages on nbAcer; legacy libva-intel-driver on nbMain (suppresses log noise)
# - tinyMediaManager (FOSS, replaces FileBot which requires a paid license for renaming)
# - tmpfs mount for transcode cache on nbMain (31GB RAM - wastes it otherwise)

# **What needs manual steps in the web UI** (cannot be scripted - Jellyfin generates its config during the wizard):
# 1. VAAPI enable on nbAcer - Dashboard → Playback → Transcoding
# 2. OpenSubtitles plugin - install from catalog, enter your credentials
# 3. Adding your movie/series libraries during setup wizard

# **Key thing about subtitles:** SRT files direct play with zero performance cost. PGS/image subtitles (common in MKV/Blu-ray rips) trigger burn-in transcoding. After the OpenSubtitles plugin downloads `.srt` files alongside your videos, you'll almost never hit the transcode penalty.

# **FileBot note:** Dropped it - the rename feature requires a paid license (~$6/year). tinyMediaManager does the same job (rename + metadata + NFO files) completely free, and it's actually better integrated with Jellyfin's NFO format.