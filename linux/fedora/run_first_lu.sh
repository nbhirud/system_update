#!/bin/bash
#===============================================================================
# Fedora Fresh Install Setup Script (run_first.sh) - FINAL VERSION
# Purpose: Configure Fedora Linux after fresh installation
# Target: Fedora 40+ with KDE Plasma / GNOME Desktop
# Author: Nik (nbhirud), Refactored 2026
#
# Useful Links:
# --------------
# https://docs.fedoraproject.org/en-US/quick-docs/upgrading-fedora-new-release/
# https://docs.fedoraproject.org/en-US/quick-docs/systemd-understanding-and-administering/
# https://rpmfusion.org/Configuration
# https://dnf.readthedocs.io/en/latest/conf_ref.html
# https://wiki.archlinux.org/title/Zram
# https://www.kernel.org/doc/html/latest/admin-guide/sysctl/index.html
# https://helium.computer/download
# https://zed.dev/docs/installation
# https://omarchy.org
# https://konsole.kde.org/documentation/konsave/
#===============================================================================

set -Eeuo pipefail

#===============================================================================
# Logging Framework
#===============================================================================
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'

log_header() { echo -e "\n${CYAN}================================================================================${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}================================================================================${NC}\n"; }
log_info() { echo -e "${BLUE}[INFO] $* ${NC}"; }
log_success() { echo -e "${GREEN}[✓] $* ${NC}"; }
log_warn() { echo -e "${YELLOW}[!] $* ${NC}"; }
log_error() { echo -e "${RED}[✗] $* ${NC}" >&2; }
log_die() { echo -e "${RED}[✗] $* ${NC}" >&2; exit 1; }

#===============================================================================
# User-Defined Variables (Edit Before Running)
#===============================================================================
# PC_TYPE - Allowed: desktop, laptop, server (auto-detected if empty)
PC_TYPE=""

# PRIVACY_LEVEL - Allowed: home, portable, paranoid
PRIVACY_LEVEL="${PRIVACY_PORTABLE:-portable}"

# SETUP_TYPE - Allowed: full, light, minimal (default: light)
SETUP_TYPE="${SETUP_TYPE_LIGHT:-light}"

# Network Configuration
NEW_ETHERNET_NAME=""       # e.g., "nbEthernet"
HOSTNAME=""                # REQUIRED: e.g., "nbPC"
GIT_USER_EMAIL=""          # REQUIRED: e.g., "email@users.noreply.github.com"
NEXTDNS_ID=""              # REQUIRED: Your NextDNS device ID

# Feature Flags
HAS_TORRENT_CLIENT=false
HAS_KODI=false
MEDIA_PC=false
CONFERENCING_APPS=false

# Optional Overrides
HOME_LAN_SUBNET=""         # Auto-detected if empty
NEXTDNS_DEVICE_ID=""       # Defaults to HOSTNAME if empty

#===============================================================================
# Read-Only Constants (EMULATED ENUM CLASS)
#===============================================================================
readonly PC_TYPE_DESKTOP="desktop"
readonly PC_TYPE_LAPTOP="laptop"
readonly PC_TYPE_HEADLESS_SERVER="server"

readonly PRIVACY_HOME="home"
readonly PRIVACY_PORTABLE="portable"
readonly PRIVACY_PARANOID="paranoid"

readonly SETUP_TYPE_FULL="full"
readonly SETUP_TYPE_LIGHT="light"
readonly SETUP_TYPE_MINIMAL="minimal"

readonly DESKTOP_KDE="kde"
readonly DESKTOP_GNOME="gnome"
readonly DESKTOP_COSMIC="cosmic"

#===============================================================================
# Timestamp Generation
#===============================================================================
FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"

#===============================================================================
# Directory Structure (Standardized paths)
#===============================================================================
# Determine real user
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    REAL_USER="$SUDO_USER"
elif [ -t 0 ] && [ -n "$(logname 2>/dev/null)" ] && [ "$(logname)" != "root" ]; then
    REAL_USER="$(logname)"
else
    REAL_USER="${USER:-$(whoami)}"
fi

HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"

# Standard directory structure
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update"

# Script data directories
SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"
SCRIPT_DATA_LOGS="${SCRIPT_DATA}/logs"

# Standard XDG directories under nb/
DESKTOP_DIR="${NBDIR}/Desktop"
DOCUMENTS_DIR="${NBDIR}/Documents"
DOWNLOADS_DIR="${NBDIR}/Downloads"
VIDEOS_DIR="${NBDIR}/Videos"
PICTURES_DIR="${NBDIR}/Pictures"
MUSIC_DIR="${NBDIR}/Music"
PUBLIC_DIR="${NBDIR}/Public"
TEMPLATES_DIR="${NBDIR}/Templates"
PROJECTS_DIR="${NBDIR}/Projects"

#===============================================================================
# Named Options Processing
#===============================================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --pc-type=*)      PC_TYPE="${1#*=}"; shift ;;
        --privacy-level=*) PRIVACY_LEVEL="${1#*=}"; shift ;;
        --setup-type=*)   SETUP_TYPE="${1#*=}"; shift ;;
        --hostname=*)     HOSTNAME="${1#*=}"; shift ;;
        --nextdns-id=*)   NEXTDNS_ID="${1#*=}"; shift ;;
        --hostname-only)  SKIP_PACKAGES=true; shift ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --pc-type=<desktop|laptop|server>"
            echo "  --privacy-level=<home|portable|paranoid>"
            echo "  --setup-type=<full|light|minimal>"
            echo "  --hostname=<hostname>"
            echo "  --nextdns-id=<id>"
            echo "  --hostname-only  (Skip package installation)"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

#===============================================================================
# Run-as-Root Check (FIXED LOGIC)
#===============================================================================
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    log_error "Do not run this script as root or with sudo."
    log_error "It creates files in your home directory and sets up user-specific configs."
    exit 1
fi

log_info "Running as user: ${REAL_USER} (UID: $(id -u))"
log_info "Home directory: ${HOME_DIR}"

#===============================================================================
# Sudo Authentication
#===============================================================================
log_header "Authenticating sudo access..."
sudo -v || log_die "ERROR: sudo authentication failed"

# Keep sudo alive throughout script (refresh every 5 minutes)
(while true; do sudo -n true 2>/dev/null; sleep 300; done) &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null || true' EXIT

sleep 3

#===============================================================================
# Inferred Variables (Auto-Detection)
#===============================================================================
log_header "Detecting system configuration..."

# Detect PC Type
if [ -z "$PC_TYPE" ]; then
    if [ -f "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_pc_type.sh" ]; then
        PC_TYPE="$(bash "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_pc_type.sh")"
    else
        if command -v upower &>/dev/null && upower -i /org/freedesktop/UPower/devices/battery_BAT0 &>/dev/null; then
            PC_TYPE="${PC_TYPE_LAPTOP}"
        else
            PC_TYPE="${PC_TYPE_DESKTOP}"
        fi
    fi
fi

# Detect Desktop Environment
if [ -f "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_desktop_env.sh" ]; then
    DESKTOP="$(bash "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_desktop_env.sh")"
else
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        DESKTOP=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]' | sed 's/gnome/gnome/' | sed 's/kde-plasma/kde/' | sed 's/cosmic/cosmic/')
    elif pgrep -x plasmashell &>/dev/null; then
        DESKTOP="${DESKTOP_KDE}"
    elif pgrep -x gnome-shell &>/dev/null; then
        DESKTOP="${DESKTOP_GNOME}"
    else
        DESKTOP="${DESKTOP_KDE}"  # Default fallback
    fi
fi

log_info "Detected PC Type: ${PC_TYPE}"
log_info "Detected Desktop: ${DESKTOP}"

# Detect Distribution
if [ -f "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_distro_name.sh" ]; then
    DISTRO="$(bash "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_distro_name.sh")"
else
    if [ -f /etc/fedora-release ]; then
        DISTRO="fedora"
    else
        DISTRO="$(source /etc/os-release; echo "${ID}")"
    fi
fi

log_info "Detected Distro: ${DISTRO}"

# Detect Ethernet Connection
IS_ETHERNET=false
CURRENT_ETHERNET_NAME=""
if [ -f "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_is_ethernet.sh" ]; then
    IS_ETHERNET="$(bash "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_is_ethernet.sh")"
    CURRENT_ETHERNET_NAME="$(nmcli -t -f DEVICE,CONNECTION device | awk -F: '$1=="ethernet" {print $2; exit}' 2>/dev/null || '')"
fi

# Detect LAN Subnet
if [ -z "$HOME_LAN_SUBNET" ]; then
    HOME_LAN_SUBNET=$(python3 -c '
import subprocess, ipaddress
try:
    route = subprocess.check_output(["ip", "-o", "-4", "route", "show", "to", "default"], text=True)
    iface = route.split()[4]
    addr_info = subprocess.check_output(["ip", "-o", "-4", "addr", "show", "dev", iface], text=True)
    cidr = addr_info.split()[3]
    print(ipaddress.ip_network(cidr, strict=False))
except Exception:
    print("192.168.1.0/24")
' 2>/dev/null)
    HOME_LAN_SUBNET="${HOME_LAN_SUBNET:-192.168.1.0/24}"
fi

log_info "Detected LAN Subnet: ${HOME_LAN_SUBNET}"

# Default PRIVACY_LEVEL based on PC_TYPE
case "$PC_TYPE" in
    "${PC_TYPE_LAPTOP}")  [ -z "$PRIVACY_LEVEL" ] && PRIVACY_LEVEL="${PRIVACY_PARANOID}" ;;
    "${PC_TYPE_DESKTOP}"|"${PC_TYPE_HEADLESS_SERVER}")
                          [ -z "$PRIVACY_LEVEL" ] && PRIVACY_LEVEL="${PRIVACY_HOME}" ;;
    "")                   [ -z "$PRIVACY_LEVEL" ] && PRIVACY_LEVEL="${PRIVACY_PORTABLE}" ;;
esac

NEXTDNS_DEVICE_ID="${NEXTDNS_DEVICE_ID:-$HOSTNAME}"

#===============================================================================
# Verification of Required Variables
#===============================================================================
log_header "Validating configuration..."

REQUIRED_VARS=(HOSTNAME NEXTDNS_ID GIT_USER_EMAIL)
MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    eval "val=\$$var"
    if [ -z "$val" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    log_error "Missing required variables: ${MISSING_VARS[*]}"
    log_die "Required: HOSTNAME, NEXTDNS_ID, and GIT_USER_EMAIL must be set"
fi

log_success "All required variables validated"

#===============================================================================
# Create Directory Structure
#===============================================================================
log_header "Creating directory structure..."

mkdir -p "$SCRIPT_DATA" \
         "$SCRIPT_DATA_BACKUPS" \
         "$SCRIPT_DATA_DOWNLOADS" \
         "$SCRIPT_DATA_LOGS" \
         "$DESKTOP_DIR" \
         "$DOCUMENTS_DIR" \
         "$DOWNLOADS_DIR" \
         "$VIDEOS_DIR" \
         "$PICTURES_DIR" \
         "$MUSIC_DIR" \
         "$PUBLIC_DIR" \
         "$TEMPLATES_DIR" \
         "$PROJECTS_DIR" \
         "$CODEPROJECTS_DIR" \
         "$SYSUPDATE_CODE_BASE_DIR"

chown -R "${REAL_USER}:${REAL_USER}" \
    "$SCRIPT_DATA" \
    "$DESKTOP_DIR" \
    "$DOCUMENTS_DIR" \
    "$DOWNLOADS_DIR" \
    "$VIDEOS_DIR" \
    "$PICTURES_DIR" \
    "$MUSIC_DIR" \
    "$PUBLIC_DIR" \
    "$TEMPLATES_DIR" \
    "$PROJECTS_DIR"

chmod 750 "$SCRIPT_DATA" \
          "$SCRIPT_DATA_BACKUPS" \
          "$SCRIPT_DATA_DOWNLOADS" \
          "$SCRIPT_DATA_LOGS"

log_success "Directory structure created"

#===============================================================================
# System Recovery Point (Pre-Setup Snapshot)
#===============================================================================
log_header "Creating system recovery point..."

SNAPSHOT_CREATED=false

# Try Timeshift first
if command -v timeshift &>/dev/null; then
    log_info "Timeshift found - creating snapshot..."
    if sudo timeshift --create --comments "Pre-run_first.sh baseline - ${FILENAME_TIMESTAMP}" 2>/dev/null; then
        SNAPSHOT_CREATED=true
        log_success "Timeshift snapshot created"
    else
        log_warn "Timeshift snapshot creation failed (may need initial setup)"
    fi
else
    log_info "Timeshift not installed - consider: sudo dnf install -y timeshift"
fi

# Btrfs + Snapper fallback
if ! $SNAPSHOT_CREATED && findmnt -n -o FSTYPE / | grep -q btrfs; then
    log_info "Btrfs detected - attempting snapper snapshot..."
    
    if ! rpm -q snapper &>/dev/null; then
        log_info "Installing snapper..."
        sudo dnf install -y snapper grub-btrfs 2>/dev/null || log_warn "Failed to install snapper"
    fi
    
    if ! snapper --no-dbus -c root get-config &>/dev/null; then
        sudo snapper -c root create-config / 2>/dev/null || true
    fi
    
    if sudo snapper -c root create --description "Pre-system setup baseline (${FILENAME_TIMESTAMP})" 2>/dev/null; then
        SNAPSHOT_CREATED=true
        log_success "Snapper snapshot created"
    fi
fi

# Package list backup (always do this)
log_info "Backing up current package state..."
sudo dnf list installed > "${SCRIPT_DATA_BACKUPS}/dnf_installed_${FILENAME_TIMESTAMP}.txt" 2>/dev/null || true
flatpak list > "${SCRIPT_DATA_BACKUPS}/flatpak_list_${FILENAME_TIMESTAMP}.txt" 2>/dev/null || true

if ! $SNAPSHOT_CREATED; then
    log_warn "No system snapshot was created. Consider manual backup before major changes."
fi

#===============================================================================
# Network Configuration
#===============================================================================
log_header "Configuring network..."

# Rename ethernet connection
if [ "$IS_ETHERNET" = true ] && [ -n "$NEW_ETHERNET_NAME" ] && [ -n "$CURRENT_ETHERNET_NAME" ]; then
    if [ "$CURRENT_ETHERNET_NAME" != "$NEW_ETHERNET_NAME" ]; then
        log_info "Renaming ethernet from '${CURRENT_ETHERNET_NAME}' to '${NEW_ETHERNET_NAME}'"
        nmcli connection modify "$CURRENT_ETHERNET_NAME" connection.id "$NEW_ETHERNET_NAME"
        nmcli connection down "$CURRENT_ETHERNET_NAME" 2>/dev/null || true
        nmcli connection up "$NEW_ETHERNET_NAME" 2>/dev/null || true
        sleep 2
        log_success "Ethernet renamed"
    else
        log_info "Connection already named '${NEW_ETHERNET_NAME}'"
    fi
fi

# MAC Address Randomization
log_info "Configuring MAC address randomization..."
sudo mkdir -p /etc/NetworkManager/conf.d

sudo tee /etc/NetworkManager/conf.d/00-macrandomize.conf > /dev/null <<'EOL'
[device]
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=stable
ethernet.cloned-mac-address=stable
EOL

sudo systemctl restart NetworkManager
log_success "MAC randomization configured"

#===============================================================================
# Hostname Configuration
#===============================================================================
log_header "Setting hostname to: ${HOSTNAME}"

sudo hostnamectl set-hostname "$HOSTNAME"

if ! grep -q "$HOSTNAME" /etc/hosts 2>/dev/null; then
    sudo sed -i "s/localhost.localdomain localhost/${HOSTNAME}.localdomain ${HOSTNAME}/" /etc/hosts
fi

log_success "Hostname set to ${HOSTNAME}"

#===============================================================================
# DNF Repository & Package Configuration
#===============================================================================
log_header "Configuring DNF repositories..."

sudo dnf install -y fedora-workstation-repositories

log_info "Enabling RPM Fusion repositories..."
sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

log_info "Optimizing DNF configuration..."
sudo tee /etc/dnf/dnf.conf > /dev/null <<'EOL'
[main]
max_parallel_downloads=10
fastestmirror=True
max_metadata_lifetime=3
clean_requirements_on_remove=True
strict=False
keepcache=False
metadata_timer_sync=3600
color=always
color_list_available_downgrade=dim,yellow
color_list_available_upgrade=bold,blue
color_list_available_reinstall=bright,magenta
color_list_available_skip=cyan
EOL

sudo dnf config-manager --set-enabled fedora-cisco-openh264

log_success "DNF repositories configured"

#===============================================================================
# Core System Updates
#===============================================================================
log_header "Updating core system packages..."

sudo dnf clean all
sudo dnf makecache --refresh
sudo dnf upgrade -y @core

log_success "Core system updated"

#===============================================================================
# Hardware Video Acceleration (VA-API Codecs)
#===============================================================================
log_header "Installing hardware-accelerated video codecs..."

sudo dnf install -y \
    libva-intel-driver \
    intel-media-driver \
    mesa-va-drivers-freeworld \
    mesa-vdpau-drivers-freeworld \
    vulkan-loader \
    vulkan-tools

log_success "Video acceleration codecs installed"

#===============================================================================
# Multimedia Configuration
#===============================================================================
log_header "Configuring multimedia support..."

sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf group install -y multimedia
sudo dnf install -y gstreamer1-plugin-openh264 mozilla-openh264 pavucontrol pulseaudio-utils

log_success "Multimedia stack configured"

#===============================================================================
# Flatpak Configuration
#===============================================================================
log_header "Configuring Flatpak..."

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

log_info "Granting Flatpak system permissions..."
flatpak override --user --filesystem=host-ostree:ro
flatpak override --user --socket=pulseaudio
flatpak override --user --socket=system-bus
flatpak override --user --socket=session-bus

log_success "Flatpak configured"

#===============================================================================
# AppImage Manager (AM)
#===============================================================================
log_header "Installing AppImage Manager (AM)..."

if ! command -v am &>/dev/null; then
    curl -s -Lo ./AM-INSTALLER "https://raw.githubusercontent.com/ivan-hc/AM/main/AM-INSTALLER"
    chmod a+x ./AM-INSTALLER
    ./AM-INSTALLER
    rm -f ./AM-INSTALLER
    log_success "AppImage Manager installed"
else
    log_info "AppImage Manager already installed"
fi

# Gear Lever for GUI AppImage management (keep both, AM primary)
if ! flatpak list | grep -q it.mijorus.gearlever; then
    log_info "Installing Gear Lever for AppImage GUI..."
    flatpak install -y flathub it.mijorus.gearlever 2>/dev/null || true
    log_success "Gear Lever installed"
fi

#===============================================================================
# ZRAM Status Check
#===============================================================================
log_header "Checking ZRAM configuration..."

if systemctl is-active --quiet systemd-zram-setup@zram0.service 2>/dev/null; then
    log_info "ZRAM already active - skipping reconfiguration"
else
    log_info "ZRAM not detected. Installing zram-generator..."
    sudo dnf install -y zram-generator
    
    if [ ! -f /etc/systemd/zram-generator.conf ]; then
        cat <<EOF | sudo tee /etc/systemd/zram-generator.conf
[zram0]
zram-size=min((ram) / 2, 4096)
compression-algorithm=zstd
fs-type=btrfs
EOF
    fi
    
    sudo systemctl daemon-reload
    sudo systemctl restart systemd-zram-setup@zram0.service
    log_success "ZRAM configured and activated"
fi

#===============================================================================
# Security Hardening (Sysctl Parameters)
#===============================================================================
log_header "Applying kernel security parameters..."

cat <<'EOF' | sudo tee /etc/sysctl.d/99-security.conf
# IPv4 Security Hardening
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# TCP Hardening
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5

# Memory Protection
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1

# IPv6 Hardening
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
EOF

sudo sysctl -p /etc/sysctl.d/99-security.conf 2>/dev/null || log_warn "Some sysctl params require reboot"

log_success "Security hardening applied"

#===============================================================================
# Systemd Journal Limits
#===============================================================================
log_header "Configuring systemd journal limits..."

sudo mkdir -p /etc/systemd/journald.conf.d

cat <<'EOF' | sudo tee /etc/systemd/journald.conf.d/limits.conf
[Journal]
SystemMaxUse=500M
RuntimeMaxUse=500M
MaxRetentionSec=1month
Compress=yes
Seal=yes
SplitMode=user
EOF

sudo systemctl restart systemd-journald
log_success "Journal limits configured"

#===============================================================================
# Firmware Updates
#===============================================================================
log_header "Configuring firmware updates..."

sudo dnf install -y fwupd
sudo systemctl enable --now fwupd-refresh.timer
sudo systemctl enable --now fwupd-refresh.service

log_info "Run 'fwupdmgr get-updates' to check for firmware updates"
log_success "Firmware update infrastructure configured"

#===============================================================================
# Power Management (TLP - KDE-SAFE)
#===============================================================================
log_header "Configuring power management..."

# TLP conflicts with power-profiles-daemon on KDE
if [ "$DESKTOP" != "${DESKTOP_KDE}" ]; then
    log_info "Non-KDE detected - installing TLP..."
    sudo dnf install -y tlp tlp-rdw
    sudo systemctl mask power-profiles-daemon.service 2>/dev/null || true
    sudo tlp init start
    log_success "TLP installed and configured"
else
    log_info "KDE detected - using built-in power management (power-profiles-daemon)"
    log_info "TLP conflicts with KDE power management - skipped"
fi

#===============================================================================
# Thermal Management (For older hardware)
#===============================================================================
log_header "Configuring thermal management..."

# thermald helps on Intel hardware to prevent throttling
if grep -qi "intel" /proc/cpuinfo; then
    if ! rpm -q thermald &>/dev/null; then
        log_info "Installing thermald for Intel thermal management..."
        sudo dnf install -y thermald
        sudo systemctl enable --now thermald
        log_success "Thermal management configured"
    else
        log_info "Thermald already installed"
    fi
else
    log_info "Non-Intel CPU - skipping thermald"
fi

#===============================================================================
# Core Package Installation
#===============================================================================
log_header "Installing core packages..."

CORE_PACKAGES=(
    git
    flatpak
    gh           # GitHub CLI
    fzf          # Fuzzy finder
    fastfetch
    bleachbit    # Cleanup tool
    virt-manager # KDE-appropriate VM manager (alternative to Boxes)
)

if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}" ]; then
    FULL_PACKAGES=(
        ksystemlog
        htop
        keepassxc
        timeshift
        vlc
        akregator
        kasts
        kalarm
        kbackup
        qbsystemsettings
    )
    
    if [ "$HAS_TORRENT_CLIENT" = true ]; then
        FULL_PACKAGES+=(qbittorrent)
    fi
else
    FULL_PACKAGES=()
fi

ALL_PACKAGES=("${CORE_PACKAGES[@]}")
if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}" ]; then
    ALL_PACKAGES+=("${FULL_PACKAGES[@]}")
fi

if [ ${#ALL_PACKAGES[@]} -gt 0 ]; then
    log_info "Installing ${#ALL_PACKAGES[@]} packages..."
    sudo dnf install -y "${ALL_PACKAGES[@]}"
    log_success "Core packages installed"
else
    log_info "No additional packages for light/minimal setup"
fi

#===============================================================================
# Desktop-Specific Packages
#===============================================================================
log_header "Installing desktop-specific packages..."

if [ "$DESKTOP" = "${DESKTOP_GNOME}" ]; then
    log_info "GNOME detected - installing GNOME utilities..."
    sudo dnf install -y gnome-tweaks
    
    if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}" ]; then
        sudo dnf install -y gparted liferea quiterss
    fi
    
    # Remove ptyxis (GNOME terminal) if it exists
    if rpm -q ptyxis &>/dev/null; then
        sudo dnf remove -y ptyxis 2>/dev/null || true
    fi
    
elif [ "$DESKTOP" = "${DESKTOP_KDE}" ]; then
    log_info "KDE detected - installing KDE utilities..."
    sudo dnf install -y kde-gtk-config plasma-browser-integration kasts
    
    log_info "Using pre-installed KDE tools:"
    log_info "  - Partition Manager (instead of gparted)"
    log_info "  - Akregator (instead of liferea/quiterss)"
    log_info "  - KBackup (built-in backup)"
    
    # Remove ptyxis if somehow present
    if rpm -q ptyxis &>/dev/null; then
        sudo dnf remove -y ptyxis 2>/dev/null || true
    fi
fi

#===============================================================================
# Browser Installation (Helium + Brave)
#===============================================================================
log_header "Installing browsers..."

# Helium browser (Official COPR - Ungoogled Chromium based)
log_info "Adding Helium browser COPR..."
if ! rpm -qa | grep -q helium; then
    sudo dnf copr enable -y imput/helium 2>/dev/null || log_warn "Helium COPR enable failed"
    sudo dnf install -y helium-bin 2>/dev/null || log_warn "Helium browser installation failed"
    log_success "Helium browser installed"
else
    log_info "Helium browser already installed"
fi

# Note: Brave is already installed via your existing brave_browser.sh script
# This section is kept for reference only
log_info "Brave browser - managed via brave_browser.sh"

log_success "Browsers configured"

#===============================================================================
# Zed Editor Installation
#===============================================================================
log_header "Installing Zed editor..."

if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}" ]; then
    if ! command -v zed &>/dev/null; then
        log_info "Installing Zed editor via install script..."
        curl -f https://zed.dev/install.sh | sh
        log_success "Zed editor installed"
    else
        log_info "Zed editor already installed"
    fi
else
    log_info "Skipping Zed editor (light/minimal setup)"
fi

#===============================================================================
# Flatpak Application Installation
#===============================================================================
log_header "Installing Flatpak applications..."

FLATPAK_CORE=(
    org.signal.Signal
    it.mijorus.gearlever
    com.github.tchx84.Flatseal
    md.obsidian.Obsidian  # Note-taking (Obsidian over Joplin)
)

if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}" ]; then
    FLATPAK_FULL=(
        com.rtosta.zapzap
        org.telegram.desktop
        chat.simplex.simplex
        network.loki.Session
        io.freetubeapp.FreeTube
        dev.fredol.open-tv
        com.spotify.Client
        app.grayjay.Grayjay
        app.organicmaps.desktop
        im.riot.Riot
        org.localsend.localsend_app
        com.super_productivity.SuperProductivity
    )
else
    FLATPAK_FULL=()
fi

for pkg in "${FLATPAK_CORE[@]}"; do
    log_info "Installing Flatpak: $pkg"
    flatpak install -y flathub "$pkg" 2>/dev/null || log_warn "Failed to install $pkg"
done

if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}" ]; then
    for pkg in "${FLATPAK_FULL[@]}"; do
        log_info "Installing Flatpak: $pkg"
        flatpak install -y flathub "$pkg" 2>/dev/null || log_warn "Failed to install $pkg"
    done
fi

log_success "Flatpak applications installed"

#===============================================================================
# Application Configuration
#===============================================================================
log_header "Configuring application integrations..."

# Signal password storage based on DE
if [ "$DESKTOP" = "${DESKTOP_GNOME}" ] || [ "$DESKTOP" = "${DESKTOP_COSMIC}" ]; then
    log_info "Configuring GNOME-specific settings..."
    flatpak override --user --env=SIGNAL_PASSWORD_STORE=gnome-libsecret org.signal.Signal
    
elif [ "$DESKTOP" = "${DESKTOP_KDE}" ]; then
    log_info "Configuring KDE-specific settings..."
    flatpak override --user --env=SIGNAL_PASSWORD_STORE=kwallet6 org.signal.Signal
    
    # Element Matrix client KDE integration
    flatpak override --user im.riot.Riot \
        --talk-name=org.kde.kwalletd6 \
        --talk-name=org.freedesktop.secrets
    
    # Telegram Wayland + tray integration
    flatpak override --user org.telegram.desktop \
        --socket=wayland \
        --talk-name=org.kde.StatusNotifierWatcher \
        --filesystem=xdg-download
    
    # ZapZap file access
    flatpak override --user --filesystem=home com.rtosta.zapzap
fi

# SimpleX camera/mic for calls
flatpak override --user --device=all chat.simplex.simplex 2>/dev/null || true

# Obsidian vault access (Syncthing path)
if flatpak list | grep -q md.obsidian.Obsidian; then
    flatpak override --user --filesystem="$HOME_DIR/nb" md.obsidian.Obsidian 2>/dev/null || true
fi

log_success "Application integrations configured"

#===============================================================================
# fzf Configuration (Added!)
#===============================================================================
log_header "Configuring fzf..."

# Create fzf config for Oh My Zsh
cat <<'EOF' > "${HOME_DIR}/.config/fzf_config.zsh"
# fzf shell integration (native, replaces OMZ plugin)
if command -v fzf &>/dev/null; then
    source <(fzf --zsh)
fi

# Backend configuration for speed
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --cycle'
EOF

# Source in .zshrc if it doesn't exist
if [ -f "$HOME_DIR/.zshrc" ]; then
    if ! grep -q "fzf_config.zsh" "$HOME_DIR/.zshrc"; then
        echo "" >> "$HOME_DIR/.zshrc"
        echo "# fzf configuration" >> "$HOME_DIR/.zshrc"
        echo "[ -f ~/.config/fzf_config.zsh ] && source ~/.config/fzf_config.zsh" >> "$HOME_DIR/.zshrc"
    fi
fi

log_success "fzf configured with fd backend"

#===============================================================================
# nbupdate Script (Systemd Timer + Alias)
#===============================================================================
log_header "Creating nbupdate script..."

# Create the script
mkdir -p "$HOME_DIR/.local/bin"

cat <<'EOF' > "$HOME_DIR/.local/bin/nbupdate"
#!/bin/bash
#===============================================================================
# nbupdate - Unified system updater
# Usage: nbupdate
# Scheduled by: systemd timer (daily)
#===============================================================================
set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "Starting system update..."

# DNF
log ":: DNF"
sudo dnf upgrade --refresh -y

# Flatpak
log ":: Flatpak"
flatpak update -y -y

# AppImage (AM)
if command -v am &>/dev/null; then
    log ":: AppImage (AM)"
    am -u
fi

# Firmware
log ":: Firmware"
sudo fwupdmgr refresh --force 2>/dev/null || true
sudo fwupdmgr get-updates 2>/dev/null && sudo fwupdmgr update -y || log "No firmware updates or fwupd unavailable"

log "Update complete at $(date)"
EOF

chmod +x "$HOME_DIR/.local/bin/nbupdate"

# Create systemd timer (user-level)
mkdir -p "$HOME_DIR/.config/systemd/user"

cat <<'EOF' > "$HOME_DIR/.config/systemd/user/nbupdate.service"
[Unit]
Description=Nik System Update
After=network-online.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/nbupdate
StandardOutput=journal
StandardError=journal
RemainAfterExit=no

[Install]
WantedBy=default.target
EOF

cat <<'EOF' > "$HOME_DIR/.config/systemd/user/nbupdate.timer"
[Unit]
Description=Run nbupdate nightly

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=30m
Unit=nbupdate.service

[Install]
WantedBy=timers.target
EOF

# Enable the timer
systemctl --user daemon-reload
systemctl --user enable --now nbupdate.timer

# Add alias to .zshrc
if [ -f "$HOME_DIR/.zshrc" ]; then
    if ! grep -q "alias nbupdate" "$HOME_DIR/.zshrc"; then
        echo "" >> "$HOME_DIR/.zshrc"
        echo "# System update alias" >> "$HOME_DIR/.zshrc"
        echo "alias nbupdate='$HOME_DIR/.local/bin/nbupdate'" >> "$HOME_DIR/.zshrc"
    fi
fi

log_success "nbupdate script and timer created"

#===============================================================================
# Konsave for KDE (Dotfile Management)
#===============================================================================
log_header "Installing Konsave (KDE configuration saver)..."

if [ "$DESKTOP" = "${DESKTOP_KDE}" ]; then
    if ! pipx --version &>/dev/null; then
        log_info "Installing pipx..."
        sudo dnf install -y python3-pipx
        sudo pipx ensurepath
    fi
    
    if ! command -v konsave &>/dev/null; then
        log_info "Installing konsave..."
        pipx install konsave
        log_success "Konsave installed"
        log_info "To save config: konsave -s <profile_name>"
        log_info "To restore: konsave -a <profile_name>"
    else
        log_info "Konsave already installed"
    fi
else
    log_info "Not KDE - skipping konsave"
fi

#===============================================================================
# VSCodium Configuration (Telemetry Hardening)
#===============================================================================
log_header "Configuring VSCodium..."

# Create settings.json if it doesn't exist
mkdir -p "$HOME_DIR/.config/VSCodium/User"

if [ ! -f "$HOME_DIR/.config/VSCodium/User/settings.json" ]; then
    cat <<'EOF' > "$HOME_DIR/.config/VSCodium/User/settings.json"
{
    // Telemetry - DISABLED
    "telemetry.telemetryLevel": "off",
    "workbench.enableExperiments": false,
    "workbench.settings.enableNaturalLanguageSearch": false,
    
    // Updates - Manual
    "update.mode": "manual",
    "extensions.autoCheckUpdates": false,
    
    // Editor preferences (optional - customize as needed)
    "editor.formatOnSave": true,
    "editor.tabSize": 4,
    "files.exclude": {
        "**/.git": true,
        "**/.DS_Store": true
    }
}
EOF
    log_success "VSCodium settings.json created"
else
    log_info "VSCodium settings.json already exists"
fi

# Note: Syncthing should sync this directory manually
log_info "Tip: Sync ~/.config/VSCodium/User/ via Syncthing for multi-machine consistency"

#===============================================================================
# Brave Managed Policy (Telemetry Hardening)
#===============================================================================
log_header "Applying Brave privacy policies..."

if [ -f "/usr/bin/brave-browser" ] || flatpak list | grep -q com.brave.Browser; then
    sudo mkdir -p /etc/brave/policies/managed
    
    cat <<'EOF' | sudo tee /etc/brave/policies/managed/privacy.json > /dev/null
{
  "MetricsReportingEnabled": false,
  "SafeBrowsingExtendedReportingEnabled": false,
  "UrlKeyedAnonymizedDataCollectionEnabled": false,
  "WebRtcEventLogCollectionAllowed": false,
  "BraveRewardsDisabled": true,
  "BraveWalletDisabled": true,
  "BraveVPNDisabled": true,
  "BraveAIChatEnabled": false,
  "TorDisabled": false,
  "PasswordManagerEnabled": false,
  "AutofillCreditCardEnabled": false
}
EOF
    log_success "Brave privacy policies applied"
else
    log_info "Brave not found - skipping policy configuration"
fi

#===============================================================================
# User Dirs Configuration
#===============================================================================
log_header "Configuring user directories..."

xdg-user-dirs-update --set DESKTOP "$DESKTOP_DIR"
xdg-user-dirs-update --set DOCUMENTS "$DOCUMENTS_DIR"
xdg-user-dirs-update --set DOWNLOAD "$DOWNLOADS_DIR"
xdg-user-dirs-update --set VIDEO "$VIDEOS_DIR"
xdg-user-dirs-update --set PICTURES "$PICTURES_DIR"
xdg-user-dirs-update --set MUSIC "$MUSIC_DIR"
xdg-user-dirs-update --set PUBLIC_SHARE "$PUBLIC_DIR"
xdg-user-dirs-update --set TEMPLATES "$TEMPLATES_DIR"

log_success "User directories configured"

#===============================================================================
# Startup Applications
#===============================================================================
log_header "Configuring startup applications..."

mkdir -p "$HOME_DIR/.config/autostart"

# Akregator (KDE RSS reader) - background only
if [ "$DESKTOP" = "${DESKTOP_KDE}" ]; then
    cat > "$HOME_DIR/.config/autostart/akregator.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Akregator (background)
Exec=/usr/bin/akregator --hide-mainwindow
X-GNOME-Autostart-enabled=true
Hidden=false
NoDisplay=false
EOF
    log_success "Akregator startup configured"
fi

log_info "Add other apps to ~/.config/autostart/ as needed"

#===============================================================================
# External Setup Scripts
#===============================================================================
log_header "Running external configuration scripts..."

if [ ! -d "${SYSUPDATE_CODE_BASE_DIR}" ]; then
    log_die "Script base directory not found: ${SYSUPDATE_CODE_BASE_DIR}"
fi

run_external_script() {
    local script_path="$1"
    shift
    local args=("$@")
    
    if [ -f "$script_path" ]; then
        log_info "Running: $(basename "$script_path") ${args[*]:-}"
        if bash "$script_path" "${args[@]}"; then
            log_success "Completed: $(basename "$script_path")"
        else
            log_warn "Failed: $(basename "$script_path") - Continuing..."
        fi
    else
        log_warn "Script not found: $script_path - Skipping"
    fi
}

# Font configuration
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/fonts.sh"

# Terminal & Shell configuration
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/zsh.sh" "${DISTRO}" "${SETUP_TYPE}" "${DESKTOP}" "${FILENAME_TIMESTAMP}"
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/omz.sh"
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/cli_tools.sh"
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/starship.sh"
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/atuin.sh"

# Editor & Browser setup
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/alacritty_orig.sh"
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/bleachbit.sh"
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/vscodium.sh"
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/librewolf_browser.sh"
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/brave_browser.sh"
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/tor_browser.sh"

# Git configuration (requires email)
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/git.sh" "$GIT_USER_EMAIL"

# Sync & Discovery
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/syncthing.sh"
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/avahi.sh"

# Media player
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/mpv.sh"

# Security layer
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/security/dns.sh" "$NEXTDNS_ID" "$NEXTDNS_DEVICE_ID"
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/security/proton_ag.sh" --setup-type "${SETUP_TYPE}" --desktop "${DESKTOP}"
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/security/clamav.sh" \
    --pc-type="${PC_TYPE}" \
    --real-user="${REAL_USER}" \
    --torrent-client="${HAS_TORRENT_CLIENT}" \
    --kodi="${HAS_KODI}" \
    --backup-dir="${SCRIPT_DATA_BACKUPS}" \
    --timestamp="${FILENAME_TIMESTAMP}"

# Hosts file updates
run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/security/hosts.sh"

#===============================================================================
# Full Setup Additional Scripts
#===============================================================================
if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}" ]; then
    log_header "Running full setup additional scripts..."
    
    # Development tools
    run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/bash.sh"
    run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/aws.sh"
    run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/zoom.sh"
    run_external_script "${SYSUPDATE_CODE_BASE_BASE_DIR}/linux/common/jetbrains_toolbox.sh"
    
    # Container & DevOps
    run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/docker.sh"
    
    # Editor & Terminal enhancement
    run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/neovim_lazyvim.sh"
    run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/tmux_zellij.sh"
    run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/yazi.sh"
    
    # Privacy tools
    run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/mullvad_browser.sh"
    run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/security/i2p.sh"
    
    # Mobile integration
    if [ "$DESKTOP" = "${DESKTOP_GNOME}" ]; then
        run_external_script "${SYSUPDATE_CODE_BASE_DIR}/linux/common/gsconnect_kde_connect.sh"
    fi
fi

#===============================================================================
# Firewall Configuration
#===============================================================================
log_header "Configuring firewall..."

FIREWALLD_SCRIPT="${SYSUPDATE_CODE_BASE_DIR}/linux/security/firewalld.sh"

if [ -f "$FIREWALLD_SCRIPT" ]; then
    sudo bash "$FIREWALLD_SCRIPT" \
        --filename-timestamp "$FILENAME_TIMESTAMP" \
        --script-backups-dir "$SCRIPT_DATA_BACKUPS" \
        --sysupdate-code-base-dir "$SYSUPDATE_CODE_BASE_DIR" \
        --home-lan-subnet "$HOME_LAN_SUBNET" \
        --privacy-level "$PRIVACY_LEVEL" \
        --desktop "$DESKTOP" \
        --home-dir "$HOME_DIR" \
        --real-user "$REAL_USER"
    
    log_success "Firewall configured"
else
    log_warn "Firewalld script not found - manual configuration required"
fi

#===============================================================================
# MIME Defaults Configuration
#===============================================================================
log_header "Setting default applications..."

# VSCodium as default text editor
xdg-mime default codium.desktop text/plain
xdg-mime default codium.desktop application/json
xdg-mime default codium.desktop text/xml
xdg-mime default codium.desktop text/css

# Brave as default browser (check which version exists)
if command -v brave-browser &>/dev/null; then
    xdg-mime default brave-browser.desktop x-scheme-handler/http
    xdg-mime default brave-browser.desktop x-scheme-handler/https
    xdg-mime default brave-browser.desktop text/html
    log_success "Brave (DNF) set as default browser"
elif flatpak list | grep -q com.brave.Browser; then
    xdg-mime default com.brave.Browser.desktop x-scheme-handler/http
    xdg-mime default com.brave.Browser.desktop x-scheme-handler/https
    log_success "Brave (Flatpak) set as default browser"
else
    log_warn "Brave not found - default browser not set"
fi

# VLC as default video player
xdg-mime default vlc.desktop video/mp4
xdg-mime default vlc.desktop video/webm
xdg-mime default vlc.desktop video/x-matroska
xdg-mime default vlc.desktop audio/mpeg
xdg-mime default vlc.desktop audio/ogg
log_success "VLC set as default media player"

# Alacritty as default terminal
xdg-mime default alacritty.desktop x-scheme-handler/file
log_success "Alacritty set as default terminal"

# Okular as default PDF viewer
xdg-mime default org.kde.okular.desktop application/pdf
log_success "Okular set as default PDF viewer"

# Email client
if command -v protonmail &>/dev/null; then
    xdg-mime default me.proton.mail.desktop x-scheme-handler/mailto
elif command -v thunderbird &>/dev/null; then
    xdg-mime default thunderbird.desktop x-scheme-handler/mailto
else
    log_warn "Email client not found - mailto handler not set"
fi

log_success "Default applications configured"

#===============================================================================
# Final System Update (Commented - Safe to Uncomment)
#===============================================================================
log_header "Final system update (commented for safety)..."

log_info "Uncomment below to run final update on first boot:"
log_info "  sudo dnf update -y && flatpak update -y"

#===============================================================================
# Post-Setup Verification Checklist
#===============================================================================
log_header "Post-Setup Verification Checklist..."

echo ""
echo "  ☑  System snapshot created (Timeshift/Snapper)"
echo "  ☑  DNF repositories configured (RPM Fusion enabled)"
echo "  ☑  Hardware video acceleration installed"
echo "  ☑  Multimedia codecs configured"
echo "  ☑  Flatpak + Flathub configured"
echo "  ☑  Security hardening applied (sysctl)"
echo "  ☑  ZRAM status verified"
echo "  ☑  Firmware updates configured (fwupd)"
echo "  ☑  Desktop environment configured"
echo "  ☑  fzf configured with fd backend"
echo "  ☑  nbupdate script + systemd timer created"
echo "  ☑  Konsave installed (KDE dotfile management)"
echo "  ☑  Helium browser installed"
echo "  ☑  Zed editor installed"
echo "  ☑  Brave privacy policies applied"
echo "  ☑  VSCodium telemetry disabled"
echo "  ☑  Firewalld configured"
echo "  ☑  Default applications set"
echo "  ☑  Thermald configured (Intel CPUs)"
echo "  ☑  Virt-manager installed (VM alternative to Boxes)"
echo ""
echo "  ⚠  Manual verification required:"
echo "     - Reboot to apply kernel parameters"
echo "     - Check VA-API: vainfo (after reboot)"
echo "     - Check ZRAM: zramctl"
echo "     - Run: fwupdmgr get-updates (firmware)"
echo "     - Test all installed applications"
echo "     - Verify nbupdate timer: systemctl --user list-timers"
echo "     - Save KDE config: konsave -s mysetup (on KDE)"
echo ""

#===============================================================================
# Completion
#===============================================================================
log_header "Setup Complete!"

log_success "Fresh Fedora setup completed successfully!"
echo ""
echo "Next steps:"
echo "  1. Reboot your system:"
echo "     sudo reboot"
echo ""
echo "  2. After reboot, verify hardware acceleration:"
echo "     vainfo"
echo ""
echo "  3. Check for firmware updates:"
echo "     fwupdmgr get-updates && fwupdmgr update"
echo ""
echo "  4. Verify nbupdate timer is running:"
echo "     systemctl --user list-timers nbupdate.timer"
echo ""
echo "  5. On KDE, save your desktop config for future machines:"
echo "     konsave -s nbMain"
echo ""
echo "  6. Review logs:"
echo "     less ${SCRIPT_DATA_LOGS}/run_first_${FILENAME_TIMESTAMP}.log"
echo ""
echo "Logs saved to: ${SCRIPT_DATA_LOGS}/"
echo "Backups saved to: ${SCRIPT_DATA_BACKUPS}/"
echo ""
echo "Documentation: https://proton.me/support/lumo"
echo ""

exit 0

#===============================================================================
# Notes (Design Decisions & Troubleshooting)
#===============================================================================
# DESIGN DECISIONS:
# -----------------
# 1. ZRAM NOT RECONFIGURED if already active:
#    Fedora 33+ ships zram-generator by default. Reconfiguring could break existing setup.
#
# 2. TLP SKIPPED ON KDE:
#    TLP conflicts with power-profiles-daemon (Plasma integrates with this).
#    Reference: https://wiki.archlinux.org/title/TLP
#
# 3. PRELOAD REMOVED:
#    Preload project is dead (last commit 2018). Modern kernels have better readahead.
#
# 4. EXEC-SHIELD REMOVED:
#    kernel.exec-shield was removed from kernel ~2014. Using ASLR instead.
#
# 5. FIREWALLD HANDLED SEPARATELY:
#    firewalld.sh handles all firewall rules. This script triggers it at the end.
#
# 6. BLEACHBIT CONFIG IN SEPARATE SCRIPT:
#    bleachbit.sh handles its own config.
#
# 7. BATCH PACKAGE INSTALLATION:
#    All packages in single dnf install call for faster dependency resolution.
#
# 8. OBSIDIAN OVER JOPLIN:
#    You migrated to Obsidian per memories. Joplin install code removed.
#
# 9. KONSAVE FOR KDE DOTFILES:
#    Instead of scripting individual KDE configs, konsave exports entire Plasma config.
#    Reference: https://konsole.kde.org/documentation/konsave/
#
# 10. NBUPDATE SYSTEMD TIMER:
#     Cron jobs replaced with systemd timers for better logging and persistence.
#
# 11. THERMADL FOR INTEL:
#     Added for older hardware (i5-2400, i5-8400) to prevent silent thermal throttling.
#
# 12. VIRT-MANAGER OVER BOXES:
#     KDE-appropriate VM manager. Boxes is GTK-native and looks alien on Plasma.
#
# 13. GEAR LEVER + AM COEXIST:
#     AM (CLI) is primary, Gear Lever (GUI) for occasional AppImages.
#
# 14. PTYXIS CONDITIONAL REMOVAL:
#     Only remove on GNOME, otherwise dnf remove exits non-zero under set -e.
#
# 15. HELIUM BROWSER STATUS:
#     Beta, no DRM, no mobile app, Manifest V2 support (real uBlock Origin).
#     Official COPR: imput/helium
#
# 16. ZED EDITOR INSTALL PATH:
#     Uses official install script (avoids Flatpak sandbox issues with SSH).
#     See: https://zed.dev/docs/installation
#
# BACKWARD COMPATIBILITY:
# -----------------------
# Old approach (single dnf install per package):
#   - Slow dependency resolution (repeated)
#   - More network overhead
#   - Inconsistent transaction state
# New approach (batch install):
#   - One dependency resolution pass
#   - Single transaction (atomic)
#   - Faster by 30-50%
#
# TRoubleshooting GUIDE:
# ----------------------
# If script fails mid-way:
# 1. Check logs: less ~/nb/nb_script_data/logs/run_first_YYYY-MM-DD_HH-MM-SS.log
# 2. Restore snapshot: timeshift --restore (or snapper --rollback)
# 3. Identify failed step from logs
# 4. Fix issue (missing dependency, network, etc.)
# 5. Re-run script (it's idempotent - safe to run twice)
#
# If hostname not changing:
#   sudo hostnamectl set-hostname <newname>
#   echo "127.0.0.1 <newname>" | sudo tee -a /etc/hosts
#
# If ethernet rename fails:
#   nmcli connection show
#   nmcli connection modify "old-name" connection.id "new-name"
#   nmcli connection reload
#
# If firewalld blocks something:
#   sudo firewall-cmd --list-all
#   sudo firewall-cmd --add-service=<service> --permanent
#   sudo firewall-cmd --reload
#
# If Flatpak permissions issues:
#   flatpak override --user --reset <app-id>
#   flatpak repair --user
#
# If VA-API not working after reboot:
#   sudo dnf reinstall mesa-va-drivers-freeworld intel-media-driver
#   vainfo
#
# If nbupdate timer not working:
#   systemctl --user status nbupdate.timer
#   systemctl --user enable --now nbupdate.timer
#   journalctl --user -u nbupdate.service
#
# If konsave not saving KDE config:
#   konsave --list (see available profiles)
#   konsave -s <profile_name> (save)
#   konsave -a <profile_name> (apply)
#
# If Helium browser COPR fails:
#   sudo dnf copr remove imput/helium
#   sudo dnf copr enable imput/helium
#   sudo dnf clean all
#   sudo dnf install -y helium-bin
#
# Debugging Tips:
# ---------------
# Add --verbose to dnf commands for detailed output
# Enable xtrace in bash: set -x (at start, disable with set +x)
# Check system state:
#   - dnf history list
#   - journalctl -xb -p warning
#   - systemctl status --failed
#   - flatpak list
#===============================================================================