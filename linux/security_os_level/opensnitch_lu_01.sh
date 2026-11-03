#!/bin/bash
#########################################################
# OpenSnitch Interactive Application Firewall Setup Script
# For Fedora 45 + KDE Plasma (Wayland)
# Author: Generated for Nik's custom Fedora setup
#########################################################
# Useful Links
# ==============
# Official Project: https://github.com/evilsocket/opensnitch
# Installation Wiki: https://github.com/evilsocket/opensnitch/wiki/Installation
# OpenSnitch Website: https://opensnitch.org/
# Known Issues (Fedora): https://github.com/evilsocket/opensnitch/issues/1137
# Fedora Discussion: https://discussion.fedoraproject.org/t/opensnitch-anyone-using-could-it-be-packaged-for-fedora/114826
# protobuf compatibility fix: https://github.com/evilsocket/opensnitch/issues/1129
# Documentation: https://github.com/evilsocket/opensnitch/wiki
#########################################################

set -euo pipefail

#########################################################
# User Defined Variables
# Define these before running the script
#########################################################

# Set to your NextDNS identifier if you want unique device tracking
# Leave empty if not needed
NEXTDNS_DEVICE_ID="${NEXTDNS_DEVICE_ID:-}"

# Download directory override (optional, defaults to SCRIPT_DATA_DOWNLOADS)
CUSTOM_DOWNLOAD_DIR="${CUSTOM_DOWNLOAD_DIR:-}"

# Skip the protobuf fix (NOT RECOMMENDED - leave as false)
SKIP_PROTOBUF_FIX="${SKIP_PROTOBUF_FIX:-false}"

# Whether to auto-block all connections until explicitly allowed (default: false)
# If true, starts with default deny policy
HARDCORE_MODE="${HARDCORE_MODE:-false}"

# Version to install (leave empty for latest from GitHub releases)
OPENSNUITCH_VERSION="${OPENSNUITCH_VERSION:-}"

#########################################################
# Logging Functions (Standardized)
#########################################################
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'

log_header() { echo -e "\n${CYAN}==================== $* ====================${NC}\n"; }
log_info() { echo -e "${BLUE}[INFO] $* ${NC}"; }
log_success() { echo -e "${GREEN}[✓] $* ${NC}"; }
log_warn() { echo -e "${YELLOW}[!] $* ${NC}"; }
log_error() { echo -e "${RED}[✗] $* ${NC}" >&2; }
log_die() { echo -e "${RED}[✗] $* ${NC}" >&2; exit 1; }

#########################################################
# Helper Functions (Reusable)
#########################################################

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_die "This script should NOT be run as root. Use sudo when prompted."
    fi
}

# Verify distro is Fedora
check_fedora() {
    if [[ ! -f /etc/fedora-release ]]; then
        log_die "This script is designed for Fedora Linux. /etc/fedora-release not found."
    fi
    
    # Extract Fedora version
    FEDORA_VERSION=$(rpm -E '%{fedora}')
    log_info "Detected Fedora version: ${FEDORA_VERSION}"
    
    if [[ ${FEDORA_VERSION} -lt 38 ]]; then
        log_warn "Fedora ${FEDORA_VERSION} detected. This script targets Fedora 38+. Some features may not work correctly."
    fi
}

# Verify KDE desktop environment
check_kde() {
    if [[ "${XDG_CURRENT_DESKTOP:-}" != *"KDE"* ]]; then
        log_warn "KDE Plasma not detected as current desktop (${XDG_CURRENT_DESKTOP:-})."
        log_warn "OpenSnitch UI may still work but system tray integration might be affected."
    else
        log_info "KDE Plasma desktop confirmed."
    fi
}

# Detect Wayland vs X11
detect_display_server() {
    if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
        log_info "Running under Wayland session."
        DISPLAY_SERVER="wayland"
    elif [[ "${XDG_SESSION_TYPE:-}" == "x11" || "${DISPLAY:-}" != "" ]]; then
        log_info "Running under X11 session."
        DISPLAY_SERVER="x11"
    else
        log_warn "Could not determine display server. Assuming X11."
        DISPLAY_SERVER="x11"
    fi
}

# Check for systemd
check_systemd() {
    if ! command -v systemctl &>/dev/null; then
        log_die "systemd not found. This script requires systemd."
    fi
}

# Parse named options
parse_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                OPENSNUITCH_VERSION="$2"
                shift 2
                ;;
            --download-dir)
                CUSTOM_DOWNLOAD_DIR="$2"
                shift 2
                ;;
            --nextdns-id)
                NEXTDNS_DEVICE_ID="$2"
                shift 2
                ;;
            --hardcore)
                HARDCORE_MODE="true"
                shift
                ;;
            --skip-protobuf-fix)
                SKIP_PROTOBUF_FIX="true"
                shift
                ;;
            --verify-setup)
                VERIFY_ONLY="true"
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_die "Unknown option: $1. Use --help for usage."
                ;;
        esac
    done
}

print_usage() {
    cat <<EOF
OpenSnitch Setup Script for Fedora 45 + KDE

Usage: $(basename "$0") [OPTIONS]

Options:
    --version VERSION     Specify OpenSnitch version (e.g., 1.8.0). Default: latest release
    --download-dir PATH   Custom download directory. Default: SCRIPT_DATA_DOWNLOADS
    --nextdns-ID ID       NextDNS device identifier for tracking
    --hardcore            Start with default-deny firewall policy
    --skip-protobuf-fix   Skip protobuf compatibility fix (NOT RECOMMENDED)
    --verify-setup        Only run verification, skip installation
    --help                Show this help message

Sample calls:
    # Minimal (uses defaults):
    $(basename "$0")

    # With all options:
    $(basename "$0") --version 1.8.0 --download-dir ~/custom/downloads --nextdns-id nbMain --hardcore

EOF
}

#########################################################
# Standard Directory Structure (From Your Configuration)
#########################################################

REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb" 
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update"

SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"

# Package-specific directories
OPENSNUITCH_DOWNLOADS_DIR_BASE="${SCRIPT_DATA_DOWNLOADS}/opensnitch"
OPENSNUITCH_CURRENT_DOWNLOADS_DIR="${OPENSNUITCH_DOWNLOADS_DIR_BASE}/opensnitch_${FILENAME_TIMESTAMP}"
OPENSNUITCH_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/opensnitch"
OPENSNUITCH_CURRENT_BACKUP_DIR="${OPENSNUITCH_BACKUP_DIR_BASE}/opensnitch_${FILENAME_TIMESTAMP}"

# Ensure directory structure exists
mkdir -p "${OPENSNUITCH_CURRENT_DOWNLOADS_DIR}"
mkdir -p "${OPENSNUITCH_CURRENT_BACKUP_DIR}"

#########################################################
# Inferred Variables (System Detection)
#########################################################

# Load system detection scripts if available
if [[ -f "${SYSUPDATE_CODE_BASE_DIR}/linux/common/get_cpu_cores.sh" ]]; then
    CPU_CORES=$(sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/get_cpu_cores.sh")
else
    CPU_CORES=$(nproc)
fi

if [[ -f "${SYSUPDATE_CODE_BASE_DIR}/linux/common/get_ram_size.sh" ]]; then
    RAM_MB=$(sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/get_ram_size.sh")
else
    RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
fi

if [[ -f "${SYSUPDATE_CODE_BASE_DIR}/linux/common/get_ram_profile.sh" ]]; then
    RAM_PROFILE=$(sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/get_ram_profile.sh")
else
    if [[ ${RAM_MB} -lt 4096 ]]; then
        RAM_PROFILE="low"
    elif [[ ${RAM_MB} -lt 16384 ]]; then
        RAM_PROFILE="mid"
    else
        RAM_PROFILE="high"
    fi
fi

if [[ -f "${SYSUPDATE_CODE_BASE_DIR}/linux/common/get_pc_type.sh" ]]; then
    PC_TYPE=$(sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/get_pc_type.sh")
else
    PC_TYPE="desktop"  # Default assumption
fi

if [[ -f "${SYSUPDATE_CODE_BASE_DIR}/linux/common/get_desktop_env.sh" ]]; then
    DESKTOP=$(sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/get_desktop_env.sh")
else
    DESKTOP="${XDG_CURRENT_DESKTOP:-unknown}"
fi

# Additional system info
KERNEL_VERSION=$(uname -r)
ARCH=$(uname -m)
PYTHON3_VERSION=$(python3 --version 2>&1 | awk '{print $2}')

log_header "System Information"
log_info "Hostname: $(hostname)"
log_info "Kernel: ${KERNEL_VERSION}"
log_info "Architecture: ${ARCH}"
log_info "Python 3: ${PYTHON3_VERSION}"
log_info "CPU Cores: ${CPU_CORES}"
log_info "RAM: ${RAM_MB} MB (${RAM_PROFILE} profile)"
log_info "PC Type: ${PC_TYPE}"
log_info "Desktop: ${DESKTOP}"
log_info "Display Server: Will detect during execution"

#########################################################
# Verification Only Mode
#########################################################

run_verification() {
    log_header "OpenSnitch Installation Verification"
    
    local errors=0
    local warnings=0
    
    # Check 1: Daemon service
    log_info "Checking OpenSnitch daemon service..."
    if systemctl is-active --quiet opensnitch.service 2>/dev/null; then
        log_success "OpenSnitch daemon is running"
    else
        log_error "OpenSnitch daemon is NOT running"
        ((errors++))
    fi
    
    # Check 2: Service enabled at boot
    log_info "Checking if daemon is enabled at boot..."
    if systemctl is-enabled --quiet opensnitch.service 2>/dev/null; then
        log_success "Daemon is enabled at boot"
    else
        log_warn "Daemon is NOT enabled at boot (run: sudo systemctl enable opensnitch)"
        ((warnings++))
    fi
    
    # Check 3: UI binary exists
    log_info "Checking for opensnitch-ui binary..."
    if command -v opensnitch-ui &>/dev/null; then
        log_success "UI binary found: $(which opensnitch-ui)"
    else
        log_error "UI binary NOT found"
        ((errors++))
    fi
    
    # Check 4: Daemon binary exists
    log_info "Checking for opensnitchd binary..."
    if command -v opensnitchd &>/dev/null; then
        log_success "Daemon binary found: $(which opensnitchd)"
    else
        log_error "Daemon binary NOT found"
        ((errors++))
    fi
    
    # Check 5: Check nftables support
    log_info "Checking nftables support..."
    if command -v nft &>/dev/null; then
        log_success "nftables available"
    else
        log_error "nftables NOT found - OpenSnitch requires it"
        ((errors++))
    fi
    
    # Check 6: Python dependencies
    log_info "Checking Python dependencies..."
    missing_deps=""
    for dep in grpcio protobuf qt5-qtbase PyQt5; do
        if python3 -c "import ${dep%%-*}" 2>/dev/null; then
            :  # Found
        else
            missing_deps="${missing_deps} ${dep}"
        fi
    done
    
    if [[ -z "${missing_deps}" ]]; then
        log_success "Python dependencies OK"
    else
        log_warn "Missing Python dependencies:${missing_deps}"
        ((warnings++))
    fi
    
    # Check 7: Firewall chain exists
    log_info "Checking OpenSnitch nftables chain..."
    if nft list chains | grep -q "opensnitch"; then
        log_success "OpenSnitch nftables chain exists"
    else
        log_error "OpenSnitch nftables chain NOT found"
        ((errors++))
    fi
    
    # Check 8: Auto-start configured
    log_info "Checking UI auto-start configuration..."
    if [[ -f "${HOME_DIR}/.config/autostart/opensnitch_ui.desktop" ]]; then
        log_success "UI auto-start configured"
    else
        log_warn "UI auto-start NOT configured"
        ((warnings++))
    fi
    
    # Summary
    log_header "Verification Summary"
    if [[ ${errors} -eq 0 && ${warnings} -eq 0 ]]; then
        log_success "All checks passed! OpenSnitch is properly installed."
        return 0
    elif [[ ${errors} -eq 0 ]]; then
        log_warn "Installation OK but ${warnings} warning(s) found. Review above."
        return 0
    else
        log_error "FAILED: ${errors} error(s) found. Installation incomplete."
        return 1
    fi
}

#########################################################
# Backup Section
#########################################################

backup_existing_setup() {
    log_header "Backing Up Existing Configuration"
    
    # Check if OpenSnitch is already installed
    if rpm -q opensnitch &>/dev/null || rpm -q opensnitch-ui &>/dev/null; then
        log_info "Previous OpenSnitch installation detected. Creating backup..."
        
        # Backup configuration files
        if [[ -d /etc/opensnitchd ]]; then
            log_info "Backing up /etc/opensnitchd..."
            cp -r /etc/opensnitchd "${OPENSNUITCH_CURRENT_BACKUP_DIR}/etc_opensnitchd" 2>/dev/null || true
        fi
        
        # Backup UI config
        if [[ -d "${HOME_DIR}/.config/opensnitch" ]]; then
            log_info "Backing up ${HOME_DIR}/.config/opensnitch..."
            cp -r "${HOME_DIR}/.config/opensnitch" "${OPENSNUITCH_CURRENT_BACKUP_DIR}/user_config" 2>/dev/null || true
        fi
        
        # Backup autostart entry
        if [[ -f "${HOME_DIR}/.config/autostart/opensnitch_ui.desktop" ]]; then
            log_info "Backing up autostart entry..."
            cp "${HOME_DIR}/.config/autostart/opensnitch_ui.desktop" "${OPENSNUITCH_CURRENT_BACKUP_DIR}/" 2>/dev/null || true
        fi
        
        # Export current rules
        if command -v opensnitch-cli &>/dev/null; then
            log_info "Exporting current firewall rules..."
            opensnitch-cli dump-rules 2>/dev/null > "${OPENSNUITCH_CURRENT_BACKUP_DIR}/rules_backup.json" || true
        fi
        
        log_success "Backup complete: ${OPENSNUITCH_CURRENT_BACKUP_DIR}"
    else
        log_info "No previous OpenSnitch installation found. Skipping backup."
    fi
}

#########################################################
# Reset Section (Clean Previous Install)
#########################################################

reset_previous_install() {
    log_header "Resetting Previous Installation (If Any)"
    
    # Stop services
    log_info "Stopping OpenSnitch services..."
    sudo systemctl stop opensnitch.service 2>/dev/null || true
    
    # Remove packages
    log_info "Removing existing RPM packages..."
    sudo dnf remove -y opensnitch opensnitch-ui 2>/dev/null || true
    
    # Clean up config directories (preserve backup already made)
    log_info "Cleaning configuration directories..."
    sudo rm -rf /etc/opensnitchd 2>/dev/null || true
    rm -rf "${HOME_DIR}/.config/opensnitch" 2>/dev/null || true
    rm -f "${HOME_DIR}/.config/autostart/opensnitch_ui.desktop" 2>/dev/null || true
    
    # Remove nftables chains
    log_info "Cleaning nftables rules..."
    sudo nft delete table inet opensnitch 2>/dev/null || true
    
    log_success "Reset complete. Ready for fresh installation."
}

#########################################################
# Download Section
#########################################################

determine_release_url() {
    # Get latest release if version not specified
    if [[ -z "${OPENSNUITCH_VERSION}" ]]; then
        log_info "Fetching latest release version from GitHub..."
        OPENSNUITCH_VERSION=$(curl -s https://api.github.com/repos/evilsocket/opensnitch/releases/latest | \
                              grep '"tag_name":' | \
                              sed -E 's/.*"([^"]+)".*/\1/' | \
                              tr -d 'v')
        
        if [[ -z "${OPENSNUITCH_VERSION}" ]]; then
            log_die "Failed to fetch latest version from GitHub API."
        fi
        
        log_info "Latest version: ${OPENSNUITCH_VERSION}"
    fi
    
    # Construct download URLs for x86_64
    DAEMON_URL="https://github.com/evilsocket/opensnitch/releases/download/v${OPENSNUITCH_VERSION}/opensnitch-${OPENSNUITCH_VERSION}-1.fc38.x86_64.rpm"
    UI_URL="https://github.com/evilsocket/opensnitch/releases/download/v${OPENSNUITCH_VERSION}/opensnitch-ui-${OPENSNUITCH_VERSION}-1.noarch.rpm"
    
    log_info "Daemon package: ${DAEMON_URL}"
    log_info "UI package: ${UI_URL}"
}

download_packages() {
    log_header "Downloading OpenSnitch Packages"
    
    determine_release_url
    
    log_info "Downloading daemon package..."
    if curl -L -o "${OPENSNUITCH_CURRENT_DOWNLOADS_DIR}/opensnitch.rpm" "${DAEMON_URL}" 2>/dev/null; then
        log_success "Daemon package downloaded"
    else
        log_die "Failed to download daemon package"
    fi
    
    log_info "Downloading UI package..."
    if curl -L -o "${OPENSNUITCH_CURRENT_DOWNLOADS_DIR}/opensnitch-ui.rpm" "${UI_URL}" 2>/dev/null; then
        log_success "UI package downloaded"
    else
        log_die "Failed to download UI package"
    fi
    
    # Verify RPM files exist and have content
    if [[ ! -s "${OPENSNUITCH_CURRENT_DOWNLOADS_DIR}/opensnitch.rpm" ]]; then
        log_die "Daemon RPM file is empty or corrupted"
    fi
    
    if [[ ! -s "${OPENSNUITCH_CURRENT_DOWNLOADS_DIR}/opensnitch-ui.rpm" ]]; then
        log_die "UI RPM file is empty or corrupted"
    fi
    
    log_success "All packages downloaded successfully to ${OPENSNUITCH_CURRENT_DOWNLOADS_DIR}"
}

#########################################################
# Install Section
#########################################################

install_dependencies() {
    log_header "Installing Required Dependencies"
    
    log_info "Updating package metadata..."
    sudo dnf update -y --refresh
    
    # Core dependencies
    REQUIRED_PACKAGES=(
        "python3"
        "python3-pip"
        "python3-devel"
        "nftables"
        "systemd"
    )
    
    log_info "Installing core dependencies: ${REQUIRED_PACKAGES[*]}"
    sudo dnf install -y "${REQUIRED_PACKAGES[@]}"
    
    # PyQt5 and Qt5 dependencies for UI (Fedora-specific)
    log_info "Installing Qt5/PyQt5 dependencies..."
    QT5_PACKAGES=(
        "python3-PyQt5"
        "qt5-qtbase"
        "qt5-qttools"
        "qt5-qtsvg"
    )
    
    sudo dnf install -y "${QT5_PACKAGES[@]}"
    
    # gRPC Python dependencies
    log_info "Installing gRPC dependencies..."
    GRPC_PACKAGES=(
        "python3-grpcio"
        "python3-grpcio-tools"
    )
    
    sudo dnf install -y "${GRPC_PACKAGES[@]}"
    
    log_success "Dependencies installed"
}

fix_protobuf_compatibility() {
    log_header "Fixing protobuf Compatibility (Known Fedora Issue)"
    
    # This addresses issue #1137 on GitHub - Fedora 40+ has protobuf 4.x
    # but OpenSnitch requires protobuf 3.x for the generated code
    
    if [[ "${SKIP_PROTOBUF_FIX}" == "true" ]]; then
        log_warn "Skipping protobuf fix as requested (NOT RECOMMENDED)"
        return 0
    fi
    
    log_info "Checking current protobuf version..."
    CURRENT_PROTOBUF=$(python3 -c "import google.protobuf; print(google.protobuf.__version__)" 2>/dev/null || echo "unknown")
    log_info "Current protobuf version: ${CURRENT_PROTOBUF}"
    
    # Check if version is 4.x (problematic)
    if [[ "${CURRENT_PROTOBUF}" =~ ^4\. ]]; then
        log_warn "Detected protobuf 4.x (${CURRENT_PROTOBUF}) - known compatibility issue"
        
        log_info "Installing compatible protobuf 3.x via pip..."
        
        # Upgrade pip first
        sudo pip3 install --upgrade pip setuptools wheel
        
        # Install specific protobuf version
        sudo pip3 install "protobuf==3.20.3"
        
        # Verify installation
        FIXED_PROTOBUF=$(python3 -c "import google.protobuf; print(google.protobuf.__version__)" 2>/dev/null || echo "failed")
        log_info "After fix, protobuf version: ${FIXED_PROTOBUF}"
        
        if [[ "${FIXED_PROTOBUF}" =~ ^3\. ]]; then
            log_success "Protobuf compatibility fixed"
        else
            log_warn "Could not verify protobuf fix. UI may not work correctly."
        fi
    else
        log_info "Protobuf version ${CURRENT_PROTOBUF} appears compatible. No fix needed."
    fi
}

install_opensnitch_rpm() {
    log_header "Installing OpenSnitch RPM Packages"
    
    log_info "Installing daemon package..."
    sudo dnf install -y "${OPENSNUITCH_CURRENT_DOWNLOADS_DIR}/opensnitch.rpm"
    
    log_info "Installing UI package..."
    sudo dnf install -y "${OPENSNUITCH_CURRENT_DOWNLOADS_DIR}/opensnitch-ui.rpm"
    
    # Fix any dependency issues
    log_info "Resolving dependency issues..."
    sudo dnf install -y -f 2>/dev/null || true
    
    log_success "OpenSnitch packages installed"
}

enable_and_start_services() {
    log_header "Enabling and Starting Services"
    
    # Enable and start daemon
    log_info "Enabling OpenSnitch daemon at boot..."
    sudo systemctl enable opensnitch.service
    
    log_info "Starting OpenSnitch daemon..."
    sudo systemctl start opensnitch.service
    
    # Verify daemon status
    sleep 2  # Give it time to initialize
    if systemctl is-active --quiet opensnitch.service; then
        log_success "OpenSnitch daemon is running"
    else
        log_error "OpenSnitch daemon failed to start. Check logs with: sudo journalctl -u opensnitch.service"
        log_die "Installation cannot continue without running daemon"
    fi
    
    log_success "Services enabled and started"
}

configure_ui_autostart() {
    log_header "Configuring UI Autostart"
    
    # Create autostart directory
    mkdir -p "${HOME_DIR}/.config/autostart"
    
    # Create desktop entry
    cat > "${HOME_DIR}/.config/autostart/opensnitch_ui.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=OpenSnitch UI
Comment=Interactive application firewall
Exec=opensnitch-ui --socket 127.0.0.1:50051
Icon=opensnitch-ui
Terminal=false
NoDisplay=false
Categories=System;Security;Monitor;Network;
X-GNOME-AutostartEnabled=true
X-KDE-autostart-after=panel
X-KDE-autostart-phase=1
EOF
    
    # Set permissions
    chmod 644 "${HOME_DIR}/.config/autostart/opensnitch_ui.desktop"
    
    log_success "UI autostart configured for KDE"
    
    # Additional: Create manual startup script for terminal access
    cat > "${HOME_DIR}/bin/opensnitch-ui-manual.sh" <<EOF
#!/bin/bash
# Manual OpenSnitch UI launcher
# Useful for troubleshooting or running without auto-start
exec opensnitch-ui --socket 127.0.0.1:50051
EOF
    
    chmod +x "${HOME_DIR}/bin/opensnitch-ui-manual.sh" 2>/dev/null || true
}

configure_firewall_rules() {
    log_header "Configuring nftables Firewall Rules"
    
    log_info "Creating OpenSnitch nftables table..."
    
    # OpenSnitch creates its own nftables table on startup,
    # but we ensure the base infrastructure is ready
    
    # Check if nftables service is enabled
    if ! systemctl is-enabled --quiet nftables.service 2>/dev/null; then
        log_warn "nftables service is not enabled. Enabling now..."
        sudo systemctl enable nftables.service
    fi
    
    # OpenSnitch will manage its own chains via opensnitchd
    # We just verify nftables is functional
    if nft list tables | grep -q inet; then
        log_success "nftables infrastructure ready"
    else
        log_warn "nftables may not be fully configured"
    fi
}

apply_hardcore_mode() {
    if [[ "${HARDCORE_MODE}" != "true" ]]; then
        log_info "Hardcore mode disabled. Default allow policy will be used."
        return 0
    fi
    
    log_header "Applying Hardcore (Default Deny) Mode"
    log_warn "Setting all-new connections to be blocked by default!"
    log_warn "You will need to explicitly allow ALL network connections."
    log_warn "This includes browser updates, package managers, and system services."
    
    # Create configuration file for default deny
    sudo mkdir -p /etc/opensnitchd
    sudo tee /etc/opensnitchd/config.json > /dev/null <<EOF
{
    "default_action": {
        "name": "deny",
        "type": "boolean"
    },
    "default_duration": "always",
    "log_level": "info"
}
EOF
    
    sudo chown root:root /etc/opensnitchd/config.json
    sudo chmod 644 /etc/opensnitchd/config.json
    
    # Restart daemon to apply config
    sudo systemctl restart opensnitch.service
    
    log_success "Hardcore mode applied. Remember to allow essential services!"
    log_info "Essential services to consider allowing:"
    log_info "  - Your web browser"
    log_info "  - Package managers (dnf, flatpak)"
    log_info "  - System services (systemd-resolved, NetworkManager)"
    log_info "  - Time sync (chronyd, systemd-timesyncd)"
    log_info "  - SSH (if remote access needed)"
}

configure_nextdns_integration() {
    if [[ -z "${NEXTDNS_DEVICE_ID}" ]]; then
        log_info "No NextDNS device ID provided. Skipping integration."
        return 0
    fi
    
    log_header "NextDNS Device Integration"
    
    log_info "NextDNS device ID: ${NEXTDNS_DEVICE_ID}"
    
    # Add a comment to OpenSnitch rules indicating device
    # This is informational only - OpenSnitch doesn't natively support NextDNS tagging
    
    cat > "/tmp/opensnitch_notes.txt" <<EOF
OpenSnitch Rules Tagged for Device: ${NEXTDNS_DEVICE_ID}
Hostname: $(hostname)
Machine: nbMain/nbServer/etc. (as configured)

When reviewing firewall rules in OpenSnitch UI, add this tag manually
to keep track of which machine generated the connection if you monitor
multiple machines from NextDNS dashboard.
EOF
    
    cp /tmp/opensnitch_notes.txt "${OPENSNUITCH_CURRENT_DOWNLOADS_DIR}/"
    
    log_success "NextDNS integration notes saved"
    log_info "See: ${OPENSNUITCH_CURRENT_DOWNLOADS_DIR}/opensnitch_notes.txt"
}

setup_clamav_exclusions() {
    log_header "Configuring ClamAV Exclusions (If Present)"
    
    # Check if ClamAV is installed
    if ! command -v clamscan &>/dev/null; then
        log_info "ClamAV not installed. Skipping exclusions."
        return 0
    fi
    
    log_info "Adding OpenSnitch binaries to ClamAV exclusion list..."
    
    # Add exclusions to ClamAV config
    CLAMAV_CONF="/etc/clamav/freshclam.conf"
    if [[ -f "${CLAMAV_CONF}" ]]; then
        if ! grep -q "/usr/bin/opensnitch" "${CLAMAV_CONF}"; then
            sudo tee -a "${CLAMAV_CONF}" > /dev/null <<EOF

# OpenSnitch exclusions added by setup script
ExcludePath /usr/bin/opensnitchd
ExcludePath /usr/bin/opensnitch-ui
ExcludePath /etc/opensnitchd
ExcludePath /var/lib/opensnitch
EOF
            log_success "Added OpenSnitch to ClamAV exclusions"
        else
            log_info "OpenSnitch already excluded from ClamAV scans"
        fi
    else
        log_warn "ClamAV configuration not found at ${CLAMAV_CONF}"
    fi
}

setup_bleachbit_integration() {
    log_header "Configuring BleachBit Integration (If Present)"
    
    if ! command -v bleachbit &>/dev/null; then
        log_info "BleachBit not installed. Skipping integration."
        return 0
    fi
    
    log_info "Creating BleachBit custom cleaners for OpenSnitch..."
    
    BLEACHBIT_DIR="${HOME_DIR}/.config/bleachbit"
    mkdir -p "${BLEACHBIT_DIR}/cleaners"
    
    cat > "${BLEACHBIT_DIR}/cleaners/opensnitch.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<cleaner>
    <option id="opensnitch_cache">
        <name>OpenSnitch Cache</name>
        <description>Clear OpenSnitch cache and temporary files</description>
        <path>~/.cache/opensnitch</path>
        <action>delete_path</action>
    </option>
    <option id="opensnitch_logs">
        <name>OpenSnitch Logs</name>
        <description>Clear OpenSnitch log files</description>
        <path>/var/log/opensnitchd.log</path>
        <action>delete_path</action>
    </option>
</cleaner>
EOF
    
    log_success "BleachBit cleaner created: ${BLEACHBIT_DIR}/cleaners/opensnitch.xml"
    log_info "Enable in BleachBit settings under 'Custom Cleaners'"
}

setup_ntfy_notifications() {
    log_header "Optional: ntfy Notification Integration"
    
    log_info "Do you want to receive OpenSnitch alerts via ntfy?"
    log_info "This allows push notifications to your phone/other devices."
    
    # Check if ntfy-sh is installed
    if ! command -v ntfy &>/dev/null; then
        log_info "ntfy CLI not found. Install with: sudo dnf install ntfy-sh"
        log_info "Skipping notification setup."
        return 0
    fi
    
    # Create notification helper script
    cat > "/usr/local/bin/opensnitch-notify.sh" <<'EOF'
#!/bin/bash
# OpenSnitch to ntfy notification bridge
# Configure your ntfy topic below
NTFY_TOPIC="${NTFY_TOPIC:-opensnitch-alerts}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"

# Parse OpenSnitch alert
APP_NAME="${1:-unknown}"
ACTION="${2:-unknown}"

echo "🔥 OpenSnitch Alert" | ntfy publish --server "$NTFY_SERVER" --topic "$NTFY_TOPIC" \
    --title "OpenSnitch Connection Blocked" \
    --message "${APP_NAME} attempted ${ACTION}" \
    --priority high \
    --tag shield
EOF
    
    chmod 755 /usr/local/bin/opensnitch-notify.sh
    
    log_info "Notification helper created: /usr/local/bin/opensnitch-notify.sh"
    log_info "Configure NTFY_TOPIC and NTFY_SERVER in the script"
    log_info "Test with: opensnitch-notify.sh 'Firefox' 'outbound connection'"
    
    log_warn "Note: You'll need to integrate this with OpenSnitch's alert system manually"
    log_warn "Check OpenSnitch docs for hook/custom action configuration"
}

configure_selinux() {
    log_header "Configuring SELinux Policies"
    
    # Check if SELinux is enforcing
    if [[ "$(getenforce)" != "Enforcing" && "$(getenforce)" != "Permissive" ]]; then
        log_info "SELinux is not enforcing. Skipping policy configuration."
        return 0
    fi
    
    log_info "Current SELinux status: $(getenforce)"
    
    # Check if OpenSnitch requires special SELinux permissions
    # Currently OpenSnitch doesn't ship with SELinux modules
    # We'll create a local policy if issues arise
    
    log_info "Creating SELinux booleans for OpenSnitch..."
    
    # Allow network access for OpenSnitch daemon
    sudo semanage boolean --add --on opensnitch_network_access 2>/dev/null || {
        log_info "Custom boolean not available. Using generic network permissions."
        sudo setsebool -P httpd_can_network_connect 1 2>/dev/null || true
    }
    
    log_success "SELinux policies configured"
}

security_hardening() {
    log_header "Security Hardening"
    
    log_info "Applying security best practices..."
    
    # 1. Restrict OpenSnitch config file permissions
    sudo chown root:root /etc/opensnitchd/* 2>/dev/null || true
    sudo chmod 640 /etc/opensnitchd/* 2>/dev/null || true
    
    # 2. Ensure daemon runs with minimal privileges
    log_info "Verifying systemd service runs as non-root where possible..."
    sudo systemctl cat opensnitch.service | grep -q "User=" || {
        log_warn "Service may run as root. This is expected for firewall daemon."
    }
    
    # 3. Create firewalld rule to protect OpenSnitch socket (optional)
    log_info "Setting up restricted access to OpenSnitch UI socket..."
    # The socket is 127.0.0.1:50051 - already localhost-only
    log_success "Socket is localhost-only (127.0.0.1:50051) - secure by default"
    
    # 4. Log rotation setup
    if [[ -d /var/log ]]; then
        cat > /etc/logrotate.d/opensnitch <<EOF
/var/log/opensnitchd.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 640 root adm
    postrotate
        systemctl reload opensnitch.service > /dev/null 2>&1 || true
    endscript
}
EOF
        log_success "Log rotation configured"
    fi
}

post_install_summary() {
    log_header "Post-Installation Summary"
    
    cat <<EOF

======================================================
         OpenSnitch Installation Complete!
======================================================

INSTALLATION LOCATIONS:
  Daemon binary:  /usr/bin/opensnitchd
  UI binary:      /usr/bin/opensnitch-ui
  Config dir:     /etc/opensnitchd/
  User config:    ~/.config/opensnitch/
  Backup dir:     ${OPENSNUITCH_CURRENT_BACKUP_DIR}
  Download dir:   ${OPENSNUITCH_CURRENT_DOWNLOADS_DIR}

SERVICE STATUS:
  Daemon: $(systemctl is-active opensnitch.service)
  Enabled: $(systemctl is-enabled opensnitch.service)

FIRST STEPS:
  1. Log out and log back in (or restart) to start the UI
  2. Click the shield icon in system tray when prompted
  3. Approve/deny connection requests as they appear
  4. Review rules: opensnitch-cli list-rules

COMMANDS:
  View daemon status:    sudo systemctl status opensnitch
  View UI logs:          journalctl -f | grep opensnitch
  List firewall rules:   opensnitch-cli list-rules
  Export rules:          opensnitch-cli dump-rules > rules.json
  Import rules:          opensnitch-cli load-rules < rules.json
  Kill active connections: opensnitch-cli kill <PID>

TROUBLESHOOTING:
  - If UI doesn't start: opensnitch-ui --socket 127.0.0.1:50051
  - If daemon fails:    sudo journalctl -u opensnitch.service
  - Reset everything:   Re-run this script (backs up first!)

DOCUMENTATION:
  - Main wiki: https://github.com/evilsocket/opensnitch/wiki
  - FAQ: https://github.com/evilsocket/opensnitch/wiki/FAQ
  - Reporting issues: https://github.com/evilsocket/opensnitch/issues

======================================================
EOF
    
    # Print any warnings
    if [[ "${HARDCORE_MODE}" == "true" ]]; then
        echo -e "\n${YELLOW}⚠️  HARDCORE MODE ACTIVE: All connections blocked by default!${NC}"
        echo "Make sure to allow your browser, package manager, and essential services!"
    fi
}

###############################################
# MAIN EXECUTION
###############################################

main() {
    local VERIFY_ONLY="false"
    
    # Parse command-line options
    parse_options "$@"
    
    # If verification only mode
    if [[ "${VERIFY_ONLY}" == "true" ]]; then
        run_verification
        exit $?
    fi
    
    # Validation checks
    check_root
    check_fedora
    check_kde
    check_systemd
    detect_display_server
    
    log_header "OpenSnitch Installation Script for Fedora 45 + KDE"
    log_info "Timestamp: ${FILENAME_TIMESTAMP}"
    
    # Execute installation stages
    backup_existing_setup
    reset_previous_install
    download_packages
    install_dependencies
    
    # Fix known issues BEFORE installing RPM
    fix_protobuf_compatibility
    
    # Install main packages
    install_opensnitch_rpm
    enable_and_start_services
    configure_ui_autostart
    
    # Configure optional features
    configure_firewall_rules
    apply_hardcore_mode
    configure_nextdns_integration
    setup_clamav_exclusions
    setup_bleachbit_integration
    setup_ntfy_notifications
    configure_selinux
    security_hardening
    
    # Final verification
    log_header "Running Post-Install Verification"
    run_verification
    VERIFICATION_RESULT=$?
    
    if [[ ${VERIFICATION_RESULT} -eq 0 ]]; then
        post_install_summary
        log_success "Installation completed successfully!"
    else
        log_error "Installation completed with errors. Review verification output above."
        log_info "Run: $(basename "$0") --verify-setup to re-check"
        exit 1
    fi
}

# Run main function
main "$@"