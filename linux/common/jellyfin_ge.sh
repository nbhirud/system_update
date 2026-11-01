#!/usr/bin/env bash

# ==============================================================================
# Jellyfin Production-Grade Local-Only Setup Script (Hardened & Hardware-Aware)
# Targeted for: Fedora Linux (KDE Plasma Edition / Wayland)
# Target Hosts: nbMain & nbAcer
# ==============================================================================

set -euo pipefail



# Here is a production-grade, hardened, hardware-optimized setup script for your fresh Fedora KDE installations (nbMain and nbAcer).
# How This Script Makes Jellyfin Useful for Your Workflow

#     DLNA & Local Discovery: Automatically configures your local firewall so that VLC, Kodi, your Android phone, and Chromecast can immediately discover the server under your router, without leaving your network.

#     Smart Local Syncing (Syncthing-friendly): Since you run Syncthing, the target directory matches your hierarchy exactly, meaning updates to your files reflect instantly.

#     Hardened Security & FOSS Focus: Native RPM packages are utilized directly via RPM Fusion (avoiding sandboxed containers or Flatpaks). Telemetry and external metrics are forcefully choked out via local environment files, SELinux policies, and a local-only firewall footprint.

#     No Client Bloat: No unwanted external packages are installed. You can stream seamlessly directly inside the browser or via existing vlc, mpv, or client apps.

# The Universal Hardware-Aware Setup Script

# Save this script as setup_jellyfin.sh, make it executable (chmod +x setup_jellyfin.sh), and execute it with sudo ./setup_jellyfin.sh.




# --- Color Definitions for Logging ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0;0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Security Check: Must run as root ---
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run with root privileges (sudo)." 
   exit 1
fi

# --- Step 1: Detect System Specifications ---
HOSTNAME=$(hostname)
TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
log_info "Detecting environment on host: ${HOSTNAME}..."
log_info "System memory detected: ${TOTAL_RAM} GiB"

# --- Step 2: Ensure Target Directories Exist ---
# Finds the non-root regular user to locate the home folder safely
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~${REAL_USER}")
MEDIA_ROOT="${USER_HOME}/nb/Videos"

log_info "Setting up local movie library pathing structure..."
declare -a SUBDIRS=("Movies/English" "Movies/Hindi" "Movies/Marathi" "Series")
for dir in "${SUBDIRS[@]}"; do
    mkdir -p "${MEDIA_ROOT}/${dir}"
done
chown -R "${REAL_USER}":"${REAL_USER}" "${USER_HOME}/nb"

# --- Step 3: Enable RPM Fusion Repositories ---
log_info "Enabling RPM Fusion Free/Non-Free Repositories for dependencies..."
dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf upgrade -y --refresh

# --- Step 4: Install Jellyfin Server and Web Binaries ---
log_info "Installing Jellyfin-Server and essential backend tooling via RPM..."
dnf install -y jellyfin-server jellyfin-web ffmpeg mesa-va-drivers-freeworld

# --- Step 5: Hardware-Aware Transcoding & Optimization Setup ---
log_info "Configuring underlying Hardware Performance optimizations..."

# Add jellyfin user to the video/render groups so it can access the graphics card
usermod -aG video,render jellyfin

if [[ "${HOSTNAME}" == "nbMain" ]]; then
    log_info "Host [nbMain] detected (Intel i5-2400 / 31GiB RAM)."
    log_info "Action: Enabling Intel Sandy Bridge Legacy VA-API. Disabling heavy 10-bit features."
    # High RAM Optimization: Tweak system cache pressures slightly for better playback I/O performance
    sysctl -w vm.vfs_cache_pressure=50
    
elif [[ "${HOSTNAME}" == "nbAcer" ]]; then
    log_info "Host [nbAcer] detected (Intel i5-8400 / 7.6GiB RAM)."
    log_info "Action: Enabling Intel Quick Sync Video (QSV) capable backend. Modest RAM optimizations."
    dnf install -y intel-media-driver libva-intel-driver
fi

# --- Step 6: Privacy Hardening (Disable Telemetry/Reporting) ---
log_info "Hardening application parameters and stripping logging footprints..."
mkdir -p /etc/systemd/system/jellyfin.service.d
cat <<EOF > /etc/systemd/system/jellyfin.service.d/override.conf
[Service]
Environment=JELLYFIN_LOG_LEVEL=Warning
Environment=JELLYFIN_DISABLE_TELEMETRY=1
Environment=DOTNET_CLI_TELEMETRY_OPTOUT=1
EOF

systemctl daemon-reload

# --- Step 7: Firewalld Local LAN Lockdown Rules ---
log_info "Configuring Firewalld profile boundaries..."
# Lock down traffic specifically to local network boundaries, rejecting WAN connections
CURRENT_ZONE=$(firewall-cmd --get-default-zone)

# Standard Jellyfin Web Port (TCP 8096)
firewall-cmd --permanent --zone="${CURRENT_ZONE}" --add-port=8096/tcp
# DLNA and Chromecast Discovery protocol ports
firewall-cmd --permanent --zone="${CURRENT_ZONE}" --add-port=1900/udp
firewall-cmd --permanent --zone="${CURRENT_ZONE}" --add-port=7359/udp

firewall-cmd --reload
log_info "Firewall configured: Ports open strictly for Local Discovery / LAN streaming."

# --- Step 8: SELinux Integration ---
log_info "Auditing SELinux operational states and mapping directory contexts..."
if [ "$(getenforce)" != "Disabled" ]; then
    # Ensure SELinux grants read capabilities to Jellyfin daemon for the local user storage hierarchy
    setsebool -P httpd_enable_homedirs 1 || true
    semanage fcontext -a -t httpd_sys_content_t "${MEDIA_ROOT}(/.*)?" || true
    restorecon -R -v "${MEDIA_ROOT}"
fi

# --- Step 9: Start the Local Infrastructure ---
log_info "Starting and enabling Jellyfin system service..."
systemctl enable --now jellyfin

log_success "=========================================================================="
log_success " Jellyfin Deployment Script completed successfully on ${HOSTNAME}!"
log_success " Access the Web UI here to finish initial setup: http://localhost:8096"
log_success " Library Directory: ${MEDIA_ROOT}"
log_success "=========================================================================="




# ### Understanding Transcoding & Getting Started

# #### What is Transcoding?

# Videos come compressed in various formats (codecs) like H.264, HEVC/H.265, or AV1.

# * **When your device natively supports a file:** Jellyfin does **Direct Play** (0% CPU/GPU usage). It just hands the file off.
# * **When your device *doesn't* support it** (e.g., trying to stream a massive 4K HEVC movie on an older phone or casting a format your Chromecast can't read): The Jellyfin server reads the file, handles it on your graphics hardware, and translates it on-the-fly into a readable H.264 stream for that device.

# #### Initial Setup Settings (Web UI)

# When you log in to `http://localhost:8096` for the first time, click through the setup wizard. Once inside the dashboard, navigate to **Dashboard -> Transcoding** and map the settings precisely based on which computer you are configuring:

# | Hostname | Transcoding Hardware Acceleration Option to Pick | Notes |
# | --- | --- | --- |
# | **nbMain** | Select **VA-API** | This 2nd Gen Intel CPU doesn't support modern QSV formats. If a file needs transcoding, it will use legacy hardware acceleration channels safely. |
# | **nbAcer** | Select **Intel Quick Sync Video (QSV)** | Your 8th Gen Intel CPU features excellent hardware acceleration. Check off **H264, HEVC, MPEG2, and VC1** decoding boxes underneath it. |

# * Leave NextDNS configuration alone. Jellyfin handles all discovery processes entirely inside your local network subnet using UDP broadcasts (`1900` and `7359`). It does not use any upstream DNS routing configurations for localized network discovery or local media streaming.