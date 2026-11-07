#!/bin/bash
#########################################################
# OpenSnitch Interactive Application Firewall Setup Script
# For Fedora 45 + KDE Plasma (Wayland/X11)
# Includes systemd hardening with verified capability set
#########################################################
# Useful Links
# ==============
# Official Project: https://github.com/evilsocket/opensnitch
# Installation Wiki: https://github.com/evilsocket/opensnitch/wiki/Installation
# OpenSnitch Website: https://opensnitch.org/
# Known Issues (Fedora): https://github.com/evilsocket/opensnitch/issues/1137
# Fedora Discussion: https://discussion.fedoraproject.org/t/opensnitch-anyone-using-could-it-be-packaged-for-fedora/114826
# protobuf compatibility fix: https://github.com/evilsocket/opensnitch/issues/1129
# Systemd Security Reference: https://www.freedesktop.org/software/systemd/man/systemd.exec.html
# Lynis Hardening Guide: https://cisofy.com/lynis/
# systemd-analyze security: https://www.freedesktop.org/software/systemd/man/systemd-analyze.html
#########################################################

set -euo pipefail

##################################################################
# Overview and Usage
##################################################################
# This script performs a complete OpenSnitch installation with
# verified systemd hardening for the daemon and UI components.
#
# Key Features:
#   - Clean installation from official RPM packages
#   - Automated protobuf 3.x compatibility fix (Fedora 40+ issue #1137)
#   - Verified capability bounding set (CAP_NET_ADMIN + eBPF)
#   - Protected filesystem paths with ProtectSystem=strict
#   - User-level UI service with aggressive sandboxing
#   - Full backup before any changes
#   - Idempotent re-runs (backups + fresh install each time)
#   - Verification mode (--verify-setup)
#
# Sample Calls:
#   # Minimal (uses defaults):
#   sudo bash setup_opensnitch_hardened.sh
#
#   # With custom options:
#   sudo bash setup_opensnitch_hardened.sh \
#       --version 1.8.0 \
#       --nextdns-id nbMain \
#       --hardcore
#
#   # Verify existing installation:
#   bash setup_opensnitch_hardened.sh --verify-setup
#
# Required Parameters: None (all optional)
# Permissions: Requires root via sudo for package installation
##################################################################

##################################################################
# Named Options Processing
##################################################################
VERSION=""                    # --version VERSION
DOWNLOAD_DIR=""              # --download-dir PATH
NEXTDNS_ID=""                # --nextdns-id ID
HARDCORE_MODE="false"        # --hardcore
SKIP_PROTOBUF_FIX="false"    # --skip-protobuf-fix
VERIFY_ONLY="false"          # --verify-setup

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --download-dir)
            DOWNLOAD_DIR="$2"
            shift 2
            ;;
        --nextdns-id)
            NEXTDNS_ID="$2"
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
        --help|-h)
            cat <<EOF
OpenSnitch Hardened Setup Script for Fedora 45 + KDE

Usage: $(basename "$0") [OPTIONS]

Options:
    --version VERSION     Specify OpenSnitch version (e.g., 1.8.0). Default: latest release
    --download-dir PATH   Custom download directory. Default: auto-created under ~/nb/nb_script_data
    --nextdns-id ID       NextDNS device identifier for tagging notes
    --hardcore            Start with default-deny policy (ALL connections blocked initially)
    --skip-protobuf-fix   Skip protobuf 3.x compatibility fix (NOT RECOMMENDED)
    --verify-setup        Only run verification checks, skip installation
    --help                Show this help message

Environment Variables (optional overrides):
    REAL_USER             Override user context (defaults to $USER or $SUDO_USER)
    FILENAME_TIMESTAMP    Override timestamp format (defaults to YYYY-MM-DD_HH-MM-SS)

Examples:
    $(basename "$0")
    $(basename "$0") --version 1.8.0 --hardcore
    $(basename "$0") --verify-setup
EOF
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

##################################################################
# Standard Directory Structure (User-Defined)
##################################################################
REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update"

SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"
SCRIPT_DATA_LOGS="${SCRIPT_DATA}/logs"

# Package-specific directories
OPENSNUITCH_DOWNLOADS_BASE="${SCRIPT_DATA_DOWNLOADS}/opensnitch"
OPENSNUITCH_CURRENT_DOWNLOADS="${OPENSNUITCH_DOWNLOADS_BASE}/opensnitch_${FILENAME_TIMESTAMP}"
OPENSNUITCH_BACKUP_BASE="${SCRIPT_DATA_BACKUPS}/opensnitch"
OPENSNUITCH_CURRENT_BACKUP="${OPENSNUITCH_BACKUP_BASE}/opensnitch_${FILENAME_TIMESTAMP}"
OPENSNUITCH_LOG_BASE="${SCRIPT_DATA_LOGS}/opensnitch"
OPENSNUITCH_CURRENT_LOG="${OPENSNUITCH_LOG_BASE}/opensnitch_${FILENAME_TIMESTAMP}"

# Ensure directories exist
mkdir -p "${OPENSNUITCH_CURRENT_DOWNLOADS}"
mkdir -p "${OPENSNUITCH_CURRENT_BACKUP}"
mkdir -p "${OPENSNUITCH_CURRENT_LOG}"

# Custom download directory override
if [[ -n "${DOWNLOAD_DIR}" ]]; then
    OPENSNUITCH_CURRENT_DOWNLOADS="${DOWNLOAD_DIR}"
    mkdir -p "${OPENSNUITCH_CURRENT_DOWNLOADS}"
fi

##################################################################
# Logging Functions
##################################################################
readonly LOG_FILE="${OPENSNUITCH_CURRENT_LOG}/installation.log"
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'

log_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_FILE}"
}

log_header() {
    local msg="==================== $* ===================="
    echo -e "\n${CYAN}${msg}${NC}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO] $*${NC}" | tee -a "${LOG_FILE}"
    log_file "INFO: $*"
}

log_success() {
    echo -e "${GREEN}[✓] $*${NC}" | tee -a "${LOG_FILE}"
    log_file "SUCCESS: $*"
}

log_warn() {
    echo -e "${YELLOW}[!] WARNING: $*${NC}" | tee -a "${LOG_FILE}"
    log_file "WARN: $*"
}

log_error() {
    echo -e "${RED}[✗] ERROR: $*${NC}" | tee -a "${LOG_FILE}" >&2
    log_file "ERROR: $*"
}

log_die() {
    log_error "$*"
    exit 1
}

##################################################################
# Helpers Section
##################################################################
# Helper: Check if script runs as root via sudo, re-exec as real user if needed
ensure_not_root() {
    if [[ $EUID -eq 0 ]]; then
        log_die "This script should NOT be run directly as root. Use sudo when prompted."
    fi
}

# Helper: Verify Fedora
check_fedora() {
    if [[ ! -f /etc/fedora-release ]]; then
        log_die "This script is designed for Fedora Linux. /etc/fedora-release not found."
    fi
    local fedora_ver
    fedora_ver=$(rpm -E '%{fedora}')
    log_info "Detected Fedora version: ${fedora_ver}"
    if [[ ${fedora_ver} -lt 38 ]]; then
        log_warn "Fedora ${fedora_ver} detected. Script targets Fedora 38+. Some features may not work."
    fi
    echo "${fedora_ver}"
}

# Helper: Detect desktop environment
check_desktop() {
    local de="${XDG_CURRENT_DESKTOP:-unknown}"
    log_info "Desktop environment: ${de}"
    if [[ "${de}" != *"KDE"* && "${de}" != *"GNOME"* && "${de}" != *"Unity"* && "${de}" != *"XFCE"* ]]; then
        log_warn "Unrecognized desktop environment. OpenSnitch UI may still work but tray integration could fail."
    fi
    echo "${de}"
}

# Helper: Detect display server
detect_display_server() {
    local session="${XDG_SESSION_TYPE:-x11}"
    if [[ "${session}" == "wayland" ]]; then
        log_info "Running under Wayland session."
    else
        log_info "Running under X11 session."
    fi
    echo "${session}"
}

# Helper: Check systemd availability
check_systemd() {
    if ! command -v systemctl &>/dev/null; then
        log_die "systemd not found. This script requires systemd."
    fi
}

# Helper: Check if OpenSnitch already installed
check_existing_install() {
    local daemon_installed="false"
    local ui_installed="false"
    
    if rpm -q opensnitch &>/dev/null; then
        daemon_installed="true"
        log_warn "Existing OpenSnitch daemon detected."
    fi
    
    if rpm -q opensnitch-ui &>/dev/null; then
        ui_installed="true"
        log_warn "Existing OpenSnitch UI detected."
    fi
    
    if [[ "${daemon_installed}" == "true" || "${ui_installed}" == "true" ]]; then
        return 0
    fi
    return 1
}

# Helper: Get system info for logging
get_system_info() {
    cat <<EOF
Hostname: $(hostname)
Kernel: $(uname -r)
Architecture: $(uname -m)
Python 3: $(python3 --version 2>&1 | awk '{print $2}')
CPU Cores: $(nproc)
RAM: $(free -m | awk '/^Mem:/{print $2}') MB
EOF
}

##################################################################
# Backup Section
##################################################################
backup_existing_setup() {
    log_header "Backing Up Existing Configuration"
    
    if ! check_existing_install; then
        log_info "No previous OpenSnitch installation found. Skipping backup."
        return 0
    fi
    
    log_info "Creating backup at: ${OPENSNUITCH_CURRENT_BACKUP}"
    
    # Backup daemon configuration
    if [[ -d /etc/opensnitchd ]]; then
        log_info "Backing up /etc/opensnitchd..."
        cp -r /etc/opensnitchd "${OPENSNUITCH_CURRENT_BACKUP}/etc_opensnitchd" 2>/dev/null || {
            log_warn "Failed to backup /etc/opensnitchd"
        }
    fi
    
    # Backup UI configuration
    if [[ -d "${HOME_DIR}/.config/opensnitch" ]]; then
        log_info "Backing up ${HOME_DIR}/.config/opensnitch..."
        cp -r "${HOME_DIR}/.config/opensnitch" "${OPENSNUITCH_CURRENT_BACKUP}/user_config" 2>/dev/null || {
            log_warn "Failed to backup user config"
        }
    fi
    
    # Backup autostart entry (old method)
    if [[ -f "${HOME_DIR}/.config/autostart/opensnitch_ui.desktop" ]]; then
        log_info "Backing up old autostart entry..."
        cp "${HOME_DIR}/.config/autostart/opensnitch_ui.desktop" "${OPENSNUITCH_CURRENT_BACKUP}/" 2>/dev/null || true
    fi
    
    # Backup existing systemd units (daemon and user)
    if [[ -f /etc/systemd/system/opensnitch.service ]] || [[ -f /etc/systemd/system/opensnitchd.service ]]; then
        log_info "Backing up daemon systemd unit..."
        cp /etc/systemd/system/opensnitch.service "${OPENSNUITCH_CURRENT_BACKUP}/opensnitch.service" 2>/dev/null || \
        cp /etc/systemd/system/opensnitchd.service "${OPENSNUITCH_CURRENT_BACKUP}/opensnitchd.service" 2>/dev/null || true
    fi
    
    if [[ -f "${HOME_DIR}/.config/systemd/user/opensnitch-ui.service" ]]; then
        log_info "Backing up user-level UI systemd unit..."
        cp "${HOME_DIR}/.config/systemd/user/opensnitch-ui.service" "${OPENSNUITCH_CURRENT_BACKUP}/opensnitch-ui.service" 2>/dev/null || true
    fi
    
    # Export current firewall rules if CLI available
    if command -v opensnitch-cli &>/dev/null; then
        log_info "Exporting current firewall rules..."
        opensnitch-cli dump-rules 2>/dev/null > "${OPENSNUITCH_CURRENT_BACKUP}/rules_backup.json" || {
            log_warn "Could not export rules"
        }
    fi
    
    # Backup nftables table state
    log_info "Saving nftables table state..."
    nft list table inet opensnitch > "${OPENSNUITCH_CURRENT_BACKUP}/nftables_table.txt" 2>/dev/null || {
        log_info "No OpenSnitch nftables table found"
    }
    
    log_success "Backup complete: ${OPENSNUITCH_CURRENT_BACKUP}"
}

##################################################################
# Reset Section (Clean Previous Install)
##################################################################
reset_previous_install() {
    log_header "Resetting Previous Installation"
    
    if ! check_existing_install; then
        log_info "No previous installation to reset."
        return 0
    fi
    
    # Stop services
    log_info "Stopping OpenSnitch daemon..."
    sudo systemctl stop opensnitch.service 2>/dev/null || \
    sudo systemctl stop opensnitchd.service 2>/dev/null || true
    
    log_info "Stopping UI service if running..."
    sudo -u "${REAL_USER}" systemctl --user stop opensnitch-ui.service 2>/dev/null || true
    
    # Remove packages
    log_info "Removing RPM packages..."
    sudo dnf remove -y opensnitch opensnitch-ui 2>/dev/null || {
        log_warn "Package removal failed or packages not installed"
    }
    
    # Clean configuration directories
    log_info "Cleaning configuration directories..."
    sudo rm -rf /etc/opensnitchd 2>/dev/null || true
    rm -rf "${HOME_DIR}/.config/opensnitch" 2>/dev/null || true
    rm -rf "${HOME_DIR}/.local/share/opensnitch" 2>/dev/null || true
    rm -rf "${HOME_DIR}/.cache/opensnitch" 2>/dev/null || true
    
    # Remove autostart entries (old method)
    rm -f "${HOME_DIR}/.config/autostart/opensnitch_ui.desktop" 2>/dev/null || true
    
    # Remove systemd units (both daemon and user)
    log_info "Removing systemd units..."
    sudo rm -f /etc/systemd/system/opensnitch.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/opensnitchd.service 2>/dev/null || true
    sudo rm -rf /etc/systemd/system/opensnitch.service.d 2>/dev/null || true
    
    rm -f "${HOME_DIR}/.config/systemd/user/opensnitch-ui.service" 2>/dev/null || true
    rm -rf "${HOME_DIR}/.config/systemd/user/opensnitch-ui.service.d" 2>/dev/null || true
    
    # Reload systemd
    sudo systemctl daemon-reload
    systemctl --user daemon-reload
    
    # Remove nftables table
    log_info "Cleaning nftables rules..."
    sudo nft delete table inet opensnitch 2>/dev/null || true
    
    log_success "Reset complete. Ready for fresh installation."
}

##################################################################
# Download Section
##################################################################
determine_release_url() {
    log_info "Determining OpenSnitch release..."
    
    if [[ -z "${VERSION}" ]]; then
        log_info "Fetching latest release from GitHub..."
        VERSION=$(curl -sL https://api.github.com/repos/evilsocket/opensnitch/releases/latest | \
                  grep '"tag_name":' | \
                  sed -E 's/.*"([^"]+)".*/\1/' | \
                  tr -d 'v')
        
        if [[ -z "${VERSION}" ]]; then
            log_die "Failed to fetch latest version from GitHub API. Check internet connectivity."
        fi
        
        log_info "Latest version determined: ${VERSION}"
    else
        log_info "Using specified version: ${VERSION}"
    fi
    
    # Construct download URLs for x86_64/x86
    # Note: Package naming changed across versions - try multiple patterns
    local daemon_url=""
    local ui_url=""
    
    # Try Fedora 38 pattern first (newest packaging)
    daemon_url="https://github.com/evilsocket/opensnitch/releases/download/v${VERSION}/opensnitch-${VERSION}-1.fc38.x86_64.rpm"
    ui_url="https://github.com/evilsocket/opensnitch/releases/download/v${VERSION}/opensnitch-ui-${VERSION}-1.noarch.rpm"
    
    echo "${daemon_url}"
    echo "${ui_url}"
}

download_packages() {
    log_header "Downloading OpenSnitch Packages"
    
    local urls
    mapfile -t urls < <(determine_release_url)
    local daemon_url="${urls[0]}"
    local ui_url="${urls[1]}"
    
    log_info "Daemon package URL: ${daemon_url}"
    log_info "UI package URL: ${ui_url}"
    
    # Download daemon
    log_info "Downloading daemon package..."
    if ! curl -L -f -o "${OPENSNUITCH_CURRENT_DOWNLOADS}/opensnitch.rpm" "${daemon_url}" 2>&1 | tee -a "${LOG_FILE}"; then
        log_die "Failed to download daemon package. Check URL and connectivity."
    fi
    
    # Download UI
    log_info "Downloading UI package..."
    if ! curl -L -f -o "${OPENSNUITCH_CURRENT_DOWNLOADS}/opensnitch-ui.rpm" "${ui_url}" 2>&1 | tee -a "${LOG_FILE}"; then
        log_die "Failed to download UI package. Check URL and connectivity."
    fi
    
    # Verify downloads are non-empty
    if [[ ! -s "${OPENSNUITCH_CURRENT_DOWNLOADS}/opensnitch.rpm" ]]; then
        log_die "Daemon RPM file is empty or corrupted"
    fi
    
    if [[ ! -s "${OPENSNUITCH_CURRENT_DOWNLOADS}/opensnitch-ui.rpm" ]]; then
        log_die "UI RPM file is empty or corrupted"
    fi
    
    log_success "Packages downloaded successfully"
    log_info "Daemon: ${OPENSNUITCH_CURRENT_DOWNLOADS}/opensnitch.rpm ($(du -h "${OPENSNUITCH_CURRENT_DOWNLOADS}/opensnitch.rpm" | cut -f1))"
    log_info "UI: ${OPENSNUITCH_CURRENT_DOWNLOADS}/opensnitch-ui.rpm ($(du -h "${OPENSNUITCH_CURRENT_DOWNLOADS}/opensnitch-ui.rpm" | cut -f1))"
}

##################################################################
# Install Section
##################################################################
install_dependencies() {
    log_header "Installing Required Dependencies"
    
    log_info "Refreshing package metadata..."
    sudo dnf update -y --refresh 2>&1 | tee -a "${LOG_FILE}" || {
        log_warn "DNF update had warnings, continuing..."
    }
    
    # Core dependencies required by OpenSnitch
    local core_packages=(
        "python3"
        "python3-pip"
        "python3-devel"
        "nftables"
        "systemd"
        "jq"
    )
    
    log_info "Installing core dependencies..."
    sudo dnf install -y "${core_packages[@]}" 2>&1 | tee -a "${LOG_FILE}"
    
    # Qt5/PyQt5 for UI (essential, not optional)
    local qt5_packages=(
        "python3-PyQt5"
        "qt5-qtbase"
        "qt5-qttools"
        "qt5-qtsvg"
        "qt5-qtbase-gui"
    )
    
    log_info "Installing Qt5/PyQt5 dependencies..."
    sudo dnf install -y "${qt5_packages[@]}" 2>&1 | tee -a "${LOG_FILE}"
    
    # gRPC Python dependencies
    local grpc_packages=(
        "python3-grpcio"
        "python3-grpcio-tools"
    )
    
    log_info "Installing gRPC dependencies..."
    sudo dnf install -y "${grpc_packages[@]}" 2>&1 | tee -a "${LOG_FILE}"
    
    # Check for dependency issues
    log_info "Checking for broken dependencies..."
    sudo dnf install -y -f 2>&1 | tee -a "${LOG_FILE}" || {
        log_warn "Dependency resolution had issues, manual intervention may be needed"
    }
    
    log_success "Dependencies installed"
}

fix_protobuf_compatibility() {
    log_header "Fixing protobuf Compatibility (GitHub Issue #1137)"
    
    if [[ "${SKIP_PROTOBUF_FIX}" == "true" ]]; then
        log_warn "Skipping protobuf fix as requested (NOT RECOMMENDED - UI may fail to start)"
        return 0
    fi
    
    log_info "Checking current protobuf version..."
    local current_proto
    current_proto=$(python3 -c "import google.protobuf; print(google.protobuf.__version__)" 2>/dev/null || echo "unknown")
    log_info "Current protobuf version: ${current_proto}"
    
    # Check if version is 4.x (known incompatible with OpenSnitch's generated code)
    if [[ "${current_proto}" =~ ^4\. ]]; then
        log_warn "Detected protobuf 4.x (${current_proto}) - known incompatibility with OpenSnitch UI"
        log_info "Installing compatible protobuf 3.x via pip3..."
        
        # Upgrade pip tools first
        sudo pip3 install --upgrade pip setuptools wheel 2>&1 | tail -5 | tee -a "${LOG_FILE}"
        
        # Install specific compatible version (3.20.3 is the last 3.x series)
        sudo pip3 install "protobuf==3.20.3" 2>&1 | tail -5 | tee -a "${LOG_FILE}"
        
        # Verify installation
        local fixed_proto
        fixed_proto=$(python3 -c "import google.protobuf; print(google.protobuf.__version__)" 2>/dev/null || echo "failed")
        log_info "After fix, protobuf version: ${fixed_proto}"
        
        if [[ "${fixed_proto}" =~ ^3\. ]]; then
            log_success "Protobuf compatibility fixed (downgraded to 3.x)"
        else
            log_warn "Could not verify successful protobuf downgrade. UI startup may fail."
            log_info "Manual workaround: pip3 install 'protobuf==3.20.3'"
        fi
    elif [[ "${current_proto}" =~ ^3\. ]]; then
        log_info "Protobuf version ${current_proto} is 3.x - appears compatible"
        log_success "No fix needed"
    else
        log_info "Unknown protobuf version (${current_proto}). Attempting install anyway for safety..."
        sudo pip3 install "protobuf==3.20.3" 2>&1 | tail -3 | tee -a "${LOG_FILE}" || true
    fi
}

install_opensnitch_rpm() {
    log_header "Installing OpenSnitch RPM Packages"
    
    # Install daemon first
    log_info "Installing daemon package..."
    sudo dnf install -y "${OPENSNUITCH_CURRENT_DOWNLOADS}/opensnitch.rpm" 2>&1 | tee -a "${LOG_FILE}"
    
    # Install UI
    log_info "Installing UI package..."
    sudo dnf install -y "${OPENSNUITCH_CURRENT_DOWNLOADS}/opensnitch-ui.rpm" 2>&1 | tee -a "${LOG_FILE}"
    
    # Force dependency fix if any issues
    log_info "Final dependency check..."
    sudo dnf distro-sync -y 2>&1 | tail -20 | tee -a "${LOG_FILE}" || {
        log_warn "distro-sync had issues, checking with fix-broken..."
        sudo dnf install -y -f 2>&1 | tail -10 | tee -a "${LOG_FILE}" || true
    }
    
    log_success "OpenSnitch packages installed"
    
    # Verify binaries exist
    if ! command -v opensnitchd &>/dev/null; then
        log_die "Daemon binary not found after installation!"
    fi
    
    if ! command -v opensnitch-ui &>/dev/null; then
        log_die "UI binary not found after installation!"
    fi
    
    log_info "Daemon binary: $(which opensnitchd)"
    log_info "UI binary: $(which opensnitch-ui)"
}

##################################################################
# Systemd Hardening - Daemon Unit
##################################################################
create_daemon_hardening() {
    log_header "Configuring Systemd Daemon Hardening"
    
    # Create drop-in directory
    sudo mkdir -p /etc/systemd/system/opensnitch.service.d
    
    # Write hardened drop-in
    # NOTE: OpenSnitch requires CAP_NET_ADMIN for nftables control
    # It also needs access to /proc/<pid>/* for process attribution (DO NOT protect this)
    # If using eBPF process monitor, CAP_BPF + CAP_PERFMON needed (kernel 5.8+)
    cat | sudo tee /etc/systemd/system/opensnitch.service.d/10-hardening.conf > /dev/null <<'HARDENING_EOF'
# OpenSnitch Daemon Hardening Profile
# Generated by automated setup script
#
# CRITICAL NOTES:
# - Do NOT set PrivateNetwork=yes - this breaks nftables management
# - Do NOT set ProtectProc=invisible or ProcSubset=pid - this breaks process attribution
# - CAP_NET_ADMIN is required for nftables rule management
# - CAP_BPF + CAP_PERFMON needed if eBPF process monitor is enabled
#
# Security Score Target: ~4.0/10.0 (medium) - acceptable for privileged network daemon
# Trade-off: Full process monitoring capability vs maximum hardening

[Service]
# === Capabilities ===
# Strip all except those demonstrably needed:
#   CAP_NET_ADMIN: Manage nftables rules (NON-NEGOTIABLE)
#   CAP_DAC_READ_SEARCH: Read files bypassing permission checks (for process inspection)
#   CAP_KILL: Send signals to other processes (for connection termination)
#   CAP_SYS_PTRACE: Trace processes (for process monitoring)
#   CAP_BPF: Load BPF programs (needed for eBPF process monitor on kernel 5.8+)
#   CAP_PERFMON: Performance monitoring events (paired with CAP_BPF)
CapabilityBoundingSet=CAP_NET_ADMIN CAP_DAC_READ_SEARCH CAP_KILL CAP_SYS_PTRACE CAP_BPF CAP_PERFMON
AmbientCapabilities=CAP_NET_ADMIN CAP_DAC_READ_SEARCH CAP_KILL CAP_SYS_PTRACE CAP_BPF CAP_PERFMON
NoNewPrivileges=yes

# === Filesystem Protection ===
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
ProtectClock=yes
ProtectHostname=yes
ProtectKernelLogs=yes
ProtectKernelModules=yes
ProtectControlGroups=yes

# === Paths we legitimately need to write ===
ReadWritePaths=/etc/opensnitchd
ReadWritePaths=/var/lib/opensnitch
ReadWritePaths=/run/opensnitchd

# === Additional Hardening ===
RestrictSUIDSGID=yes
RemoveIPC=yes
LockPersonality=yes
KeyringMode=private
RestrictRealtime=yes
RestrictNamespaces=yes

# === Syscall Filtering (conservative) ===
# Block dangerous groups while allowing normal operation
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
SystemCallArchitectures=native

# === Restart Behavior ===
# Shorter restart interval for faster recovery
RestartSec=5
TimeoutStopSec=10
HARDENING_EOF

    # Ensure correct permissions
    sudo chmod 644 /etc/systemd/system/opensnitch.service.d/10-hardening.conf
    
    log_success "Daemon hardening drop-in created"
    log_info "Location: /etc/systemd/system/opensnitch.service.d/10-hardening.conf"
    
    # Display summary of protections
    log_info "Active hardening measures:"
    log_info "  - CapabilityBoundingSet: 6 capabilities retained (down from full set)"
    log_info "  - ProtectSystem=strict + ProtectHome=read-only"
    log_info "  - PrivateTmp, PrivateDevices enabled"
    log_info "  - NoNewPrivileges=yes"
    log_info "  - SystemCallFilter applied"
}

##################################################################
# Systemd Hardening - UI User Service
##################################################################
create_ui_service() {
    log_header "Creating User-Level UI Service (Aggressive Hardening)"
    
    # Create user systemd directory
    mkdir -p "${HOME_DIR}/.config/systemd/user"
    
    # Create UI service unit
    cat > "${HOME_DIR}/.config/systemd/user/opensnitch-ui.service" <<EOF
[Unit]
Description=OpenSnitch Interactive Firewall UI
Documentation=https://github.com/evilsocket/opensnitch/wiki
PartOf=graphical-session.target
After=graphical-session.target
Requires=opensnitch.service

[Service]
Type=simple
ExecStart=/usr/bin/opensnitch-ui --socket 127.0.0.1:50051
Restart=on-failure
RestartSec=5
WorkingDirectory=%h

# === Aggressive Hardening (UI has no privileged operations) ===
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=read-only
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes

# === Path Access ===
ReadWritePaths=%h/.config/opensnitch
ReadWritePaths=%h/.local/share/opensnitch
ReadWritePaths=%h/.cache/opensnitch

# === Network Restriction ===
# UI only needs localhost for daemon communication
IPAddressExclude=private

# === Namespace Restrictions ===
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

# === Capabilities ===
# UI runs as regular user - no special caps needed
CapabilityBoundingSet=
AmbientCapabilities=

# === Additional ===
LockPersonality=yes
MemoryDenyWriteExecute=yes
KeyringMode=private
RemoveIPC=yes
UMask=0077

# === Syscall Filtering ===
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @mount @reboot @raw-io
SystemCallArchitectures=native

[Install]
WantedBy=graphical-session.target
EOF
    
    # Set permissions
    chmod 600 "${HOME_DIR}/.config/systemd/user/opensnitch-ui.service"
    
    log_success "User-level UI service created"
    log_info "Location: ${HOME_DIR}/.config/systemd/user/opensnitch-ui.service"
    
    # Remove old autostart entry (conflicts with systemd service)
    if [[ -f "${HOME_DIR}/.config/autostart/opensnitch_ui.desktop" ]]; then
        log_info "Removing old .desktop autostart (replaced by systemd service)..."
        rm -f "${HOME_DIR}/.config/autostart/opensnitch_ui.desktop"
    fi
    
    log_info "Enable with: systemctl --user enable opensnitch-ui.service"
    log_info "Start with: systemctl --user start opensnitch-ui.service"
}

##################################################################
# Firewall and Services Configuration
##################################################################
enable_and_start_services() {
    log_header "Enabling and Starting OpenSnitch Services"
    
    # Enable and start daemon
    log_info "Enabling OpenSnitch daemon at boot..."
    sudo systemctl enable opensnitch.service
    
    log_info "Starting OpenSnitch daemon..."
    sudo systemctl daemon-reload
    sudo systemctl start opensnitch.service
    
    # Wait for daemon to initialize
    sleep 3
    
    # Verify daemon status
    if systemctl is-active --quiet opensnitch.service; then
        log_success "OpenSnitch daemon is running"
        log_info "Status: $(systemctl show opensnitch.service --property=MainPID --value)"
    else
        log_error "OpenSnitch daemon failed to start!"
        log_info "Check logs: sudo journalctl -u opensnitch.service -n 50 --no-pager"
        log_die "Installation cannot continue without running daemon"
    fi
    
    # Enable and start UI (user-level)
    log_info "Enabling OpenSnitch UI service..."
    sudo -u "${REAL_USER}" systemctl --user enable opensnitch-ui.service
    
    log_info "Starting OpenSnitch UI service..."
    sudo -u "${REAL_USER}" systemctl --user daemon-reload
    sudo -u "${REAL_USER}" systemctl --user start opensnitch-ui.service
    
    sleep 2
    
    if sudo -u "${REAL_USER}" systemctl --user is-active --quiet opensnitch-ui.service; then
        log_success "OpenSnitch UI service is running"
    else
        log_warn "UI service did not start (may require graphical session)"
        log_info "Start manually after login: systemctl --user start opensnitch-ui.service"
    fi
    
    log_success "Services enabled and started"
}

configure_nftables_base() {
    log_header "Verifying nftables Infrastructure"
    
    # Check nftables is functional
    if ! command -v nft &>/dev/null; then
        log_die "nft binary not found. nftables is required for OpenSnitch."
    fi
    
    # Check if nftables service is enabled (though OpenSnitch manages its own table)
    if ! systemctl is-enabled --quiet nftables.service 2>/dev/null; then
        log_info "nftables service not enabled. This is OK - OpenSnitch creates its own table."
    else
        log_success "nftables service is enabled"
    fi
    
    # List existing tables (should be minimal)
    log_info "Current nftables tables:"
    nft list tables 2>&1 | tee -a "${LOG_FILE}" || true
    
    log_success "nftables infrastructure verified"
}

apply_hardcore_mode() {
    if [[ "${HARDCORE_MODE}" != "true" ]]; then
        log_info "Hardcore mode disabled. OpenSnitch will allow new connections until explicit rules are created."
        log_info "Tip: Review the first few connection prompts carefully to establish baseline rules."
        return 0
    fi
    
    log_header "APPLYING HARDCORE MODE (Default-Deny Policy)"
    log_warn "⚠️  ALL NEW NETWORK CONNECTIONS WILL BE BLOCKED BY DEFAULT!"
    log_warn "You will need to explicitly ALLOW each application that needs network access."
    
    # Create default-deny configuration
    sudo mkdir -p /etc/opensnitchd
    
    cat | sudo tee /etc/opensnitchd/default-config.json > /dev/null <<EOF
{
    "default_action": {
        "name": "deny",
        "type": "boolean"
    },
    "default_duration": "always",
    "log_level": "info",
    "process_monitor": "syslog"
}
EOF
    
    sudo chown root:root /etc/opensnitchd/default-config.json
    sudo chmod 640 /etc/opensnitchd/default-config.json
    
    # Restart daemon to apply config
    sudo systemctl restart opensnitch.service
    
    log_success "Hardcore mode activated"
    log_warn "ESSENTIAL SERVICES TO CONSIDER ALLOWING:"
    log_warn "  - Web browser (firefox, brave, chromium, etc.)"
    log_warn "  - Package manager (dnf, flatpak, snap)"
    log_warn "  - System services (systemd-resolved, NetworkManager, chronyd)"
    log_warn "  - SSH client/server (if remote access needed)"
    log_warn "  - Terminal emulators (alacritty, gnome-terminal, etc.)"
    log_warn ""
    log_warn "REMEMBER: You can temporarily relax with: sudo systemctl stop opensnitch"
    log_warn "But this disables ALL firewall protection."
}

##################################################################
# Integration Sections
##################################################################
configure_nextdns_integration() {
    if [[ -z "${NEXTDNS_ID:-}" ]]; then
        log_info "No NextDNS device ID provided. Skipping integration."
        return 0
    fi
    
    log_header "NextDNS Device Integration"
    
    log_info "NextDNS device ID: ${NEXTDNS_ID}"
    
    # Create integration notes file
    cat > "${OPENSNUITCH_CURRENT_DOWNLOADS}/opensnitch_nextdns_notes.txt" <<EOF
OpenSnitch Rules Tagged for NextDNS Device: ${NEXTDNS_ID}
Host: $(hostname)
Machine Type: $(uname -m)

INTENTION:
When reviewing firewall rules in OpenSnitch UI, you can tag rules
manually with this device identifier for easier correlation with
your NextDNS dashboard logs if you monitor multiple machines.

NOTE:
OpenSnitch does not natively integrate with NextDNS. This is purely
documentation for your own tracking purposes. NextDNS operates at
the DNS resolver level, while OpenSnitch filters application-level
outbound connections. Both can be complementary layers.

For NextDNS profile configuration: https://${NEXTDNS_ID}.my.nextdns.io
EOF
    
    log_success "Integration notes saved: ${OPENSNUITCH_CURRENT_DOWNLOADS}/opensnitch_nextdns_notes.txt"
}

setup_clamav_integration() {
    log_header "ClamAV Integration (If Installed)"
    
    if ! command -v clamscan &>/dev/null; then
        log_info "ClamAV not installed. Skipping integration."
        return 0
    fi
    
    log_info "Adding OpenSnitch paths to ClamAV exclusions..."
    
    # Freshclam config (signature updates)
    if [[ -f /etc/clamav/freshclam.conf ]]; then
        if ! grep -q "opensnitch" /etc/clamav/freshclam.conf; then
            cat >> /etc/clamav/freshclam.conf <<EOF

# OpenSnitch exclusions added by setup script
ExcludePath /usr/bin/opensnitchd
ExcludePath /usr/bin/opensnitch-ui
EOF
            log_success "Added OpenSnitch to freshclam exclusions"
        else
            log_info "OpenSnitch already excluded from freshclam"
        fi
    fi
    
    # Clamd config (scanner daemon)
    if [[ -f /etc/clamav/clamd.conf ]]; then
        if ! grep -q "opensnitch" /etc/clamav/clamd.conf; then
            cat >> /etc/clamav/clamd.conf <<EOF

# OpenSnitch exclusions
ExcludePath /usr/bin/opensnitchd
ExcludePath /usr/bin/opensnitch-ui
ExcludePath /etc/opensnitchd
ExcludePath /var/lib/opensnitch
EOF
            log_success "Added OpenSnitch to clamd exclusions"
        else
            log_info "OpenSnitch already excluded from clamd"
        fi
    fi
    
    log_success "ClamAV integration complete"
}

setup_bleachbit_integration() {
    log_header "BleachBit Integration (If Installed)"
    
    if ! command -v bleachbit &>/dev/null; then
        log_info "BleachBit not installed. Skipping integration."
        return 0
    fi
    
    log_info "Creating BleachBit custom cleaner for OpenSnitch..."
    
    local bleachbit_dir="${HOME_DIR}/.config/bleachbit"
    mkdir -p "${bleachbit_dir}/cleaners"
    
    cat > "${bleachbit_dir}/cleaners/opensnitch.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<cleaner>
    <option id="opensnitch_cache">
        <name>OpenSnitch Cache</name>
        <description>Clear OpenSnitch cache and temporary files</description>
        <path>~/.cache/opensnitch</path>
        <action>delete_path</action>
    </option>
    <option id="opensnitch_ui_logs">
        <name>OpenSnitch UI Logs</name>
        <description>Clear OpenSnitch UI log files</description>
        <path>~/.cache/opensnitch/log</path>
        <action>delete_path</action>
    </option>
</cleaner>
EOF
    
    log_success "BleachBit cleaner created"
    log_info "Location: ${bleachbit_dir}/cleaners/opensnitch.xml"
    log_info "Enable in BleachBit Preferences → Advanced → Custom Cleaners"
}

setup_log_rotation() {
    log_header "Configuring Log Rotation"
    
    if [[ ! -d /etc/logrotate.d ]]; then
        log_info "Log rotation directory not found. Skipping."
        return 0
    fi
    
    cat | sudo tee /etc/logrotate.d/opensnitch > /dev/null <<EOF
/var/log/opensnitchd.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 640 root adm
    postrotate
        systemctl reload opensnitch.service > /dev/null 2>&1 || true
    endscript
}

/var/log/opensnitch/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 640 root adm
}
EOF
    
    sudo chown root:root /etc/logrotate.d/opensnitch
    sudo chmod 644 /etc/logrotate.d/opensnitch
    
    log_success "Log rotation configured: /etc/logrotate.d/opensnitch"
}

configure_selinux_policy() {
    log_header "SELinux Policy Configuration"
    
    # Check SELinux status
    local selinux_status
    selinux_status=$(getenforce 2>/dev/null || echo "disabled")
    
    if [[ "${selinux_status}" == "Disabled" ]]; then
        log_info "SELinux is disabled. Skipping policy configuration."
        return 0
    fi
    
    log_info "SELinux mode: ${selinux_status}"
    
    # Check if semanage is available
    if ! command -v semanage &>/dev/null; then
        log_warn "semanage not found (policycoreutils-python-utils). Skipping boolean configuration."
        log_info "Install with: sudo dnf install policycoreutils-python-utils"
        return 0
    fi
    
    # OpenSnitch primarily uses netlink sockets (handled by kernel)
    # No custom SELinux booleans exist upstream - document what to do if denials occur
    log_info "No custom SELinux booleans shipped by OpenSnitch upstream."
    log_info "If you encounter AVC denials, run:"
    log_info "  sudo ausearch -m avc -ts recent | sudo audit2allow -M opensnitch-local"
    log_info "  sudo semodule -i opensnitch-local.pp"
    
    log_success "SELinux integration documentation complete"
}

setup_ntfy_notifications() {
    log_header "ntfy Push Notification Integration (Optional)"
    
    if ! command -v ntfy &>/dev/null; then
        log_info "ntfy CLI not found. Skipping notification setup."
        log_info "Install with: sudo dnf install ntfy-sh"
        log_info "Or from: https://ntfy.sh/docs/install/"
        return 0
    fi
    
    log_info "Creating OpenSnitch notification bridge..."
    
    # Create notification helper
    cat > /usr/local/bin/opensnitch-notify <<'NOTIFY_SCRIPT'
#!/bin/bash
# OpenSnitch to ntfy notification bridge
# Configure NTFY_TOPIC and NTFY_SERVER in ~/.config/ntfy/opensnitch.conf

CONFIG_FILE="${HOME}/.config/ntfy/opensnitch.conf"
source "${CONFIG_FILE}" 2>/dev/null || true

NTFY_TOPIC="${NTFY_TOPIC:-opensnitch-alerts}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"

# Parse command line arguments
APP_NAME="${1:-unknown}"
ACTION="${2:-connection_blocked}"

# Send notification
ntfy publish \
    --server "${NTFY_SERVER}" \
    --topic "${NTFY_TOPIC}" \
    --title "🔥 OpenSnitch Alert" \
    --message "${APP_NAME}: ${ACTION}" \
    --priority high \
    --tag shield \
    --attach "" 2>/dev/null

exit 0
NOTIFY_SCRIPT
    
    chmod 755 /usr/local/bin/opensnitch-notify
    
    # Create sample config
    mkdir -p "${HOME_DIR}/.config/ntfy"
    if [[ ! -f "${HOME_DIR}/.config/ntfy/opensnitch.conf" ]]; then
        cat > "${HOME_DIR}/.config/ntfy/opensnitch.conf" <<EOF
# OpenSnitch Notification Configuration
# Edit these values to match your ntfy setup

NTFY_TOPIC="opensnitch-alerts"
NTFY_SERVER="https://ntfy.sh"  # Or self-hosted server
EOF
        chmod 600 "${HOME_DIR}/.config/ntfy/opensnitch.conf"
    fi
    
    log_success "Notification helper created: /usr/local/bin/opensnitch-notify"
    log_info "Sample config: ${HOME_DIR}/.config/ntfy/opensnitch.conf"
    log_info "Test with: opensnitch-notify 'Firefox' 'outbound connection blocked'"
    log_warn "NOTE: OpenSnitch does not natively call external scripts."
    log_warn "You must configure this manually via OpenSnitch's hooks or monitoring."
}

##################################################################
# Verification Section
##################################################################
run_verification() {
    log_header "OpenSnitch Installation Verification"
    
    local errors=0
    local warnings=0
    
    # 1. Daemon service active
    log_info "Check 1: Daemon service status..."
    if systemctl is-active --quiet opensnitch.service; then
        log_success "  ✓ Daemon is running"
    else
        log_error "  ✗ Daemon is NOT running"
        ((errors++))
    fi
    
    # 2. Daemon enabled at boot
    log_info "Check 2: Daemon enabled at boot..."
    if systemctl is-enabled --quiet opensnitch.service; then
        log_success "  ✓ Daemon is enabled"
    else
        log_warn "  ⚠ Daemon is NOT enabled (sudo systemctl enable opensnitch)"
        ((warnings++))
    fi
    
    # 3. UI service exists
    log_info "Check 3: UI service file present..."
    if [[ -f "${HOME_DIR}/.config/systemd/user/opensnitch-ui.service" ]]; then
        log_success "  ✓ UI service file exists"
    else
        log_error "  ✗ UI service file MISSING"
        ((errors++))
    fi
    
    # 4. UI service enabled
    log_info "Check 4: UI service enabled..."
    if sudo -u "${REAL_USER}" systemctl --user is-enabled --quiet opensnitch-ui.service 2>/dev/null; then
        log_success "  ✓ UI service is enabled"
    else
        log_warn "  ⚠ UI service is NOT enabled"
        ((warnings++))
    fi
    
    # 5. Binaries exist
    log_info "Check 5: Binary executables..."
    if command -v opensnitchd &>/dev/null; then
        log_success "  ✓ opensnitchd found: $(which opensnitchd)"
    else
        log_error "  ✗ opensnitchd NOT found"
        ((errors++))
    fi
    
    if command -v opensnitch-ui &>/dev/null; then
        log_success "  ✓ opensnitch-ui found: $(which opensnitch-ui)"
    else
        log_error "  ✗ opensnitch-ui NOT found"
        ((errors++))
    fi
    
    # 6. nftables support
    log_info "Check 6: nftables..."
    if command -v nft &>/dev/null && nft list ruleset &>/dev/null; then
        log_success "  ✓ nftables available and functional"
    else
        log_error "  ✗ nftables not functional"
        ((errors++))
    fi
    
    # 7. nftables table exists
    log_info "Check 7: OpenSnitch nftables table..."
    if nft list table inet opensnitch &>/dev/null; then
        log_success "  ✓ OpenSnitch nftables table exists"
    else
        log_error "  ✗ OpenSnitch nftables table MISSING"
        ((errors++))
    fi
    
    # 8. Hardening drop-in
    log_info "Check 8: Daemon hardening configuration..."
    if [[ -f /etc/systemd/system/opensnitch.service.d/10-hardening.conf ]]; then
        log_success "  ✓ Hardening drop-in present"
        # Verify key settings
        if grep -q "NoNewPrivileges=yes" /etc/systemd/system/opensnitch.service.d/10-hardening.conf; then
            log_success "  ✓ NoNewPrivileges=yes confirmed"
        else
            log_warn "  ⚠ NoNewPrivileges not set in drop-in"
        fi
    else
        log_warn "  ⚠ Hardening drop-in not found"
        ((warnings++))
    ]
    
    # 9. UI hardening
    log_info "Check 9: UI service hardening..."
    if [[ -f "${HOME_DIR}/.config/systemd/user/opensnitch-ui.service" ]]; then
        if grep -q "NoNewPrivileges=yes" "${HOME_DIR}/.config/systemd/user/opensnitch-ui.service"; then
            log_success "  ✓ UI NoNewPrivileges=yes confirmed"
        else
            log_warn "  ⚠ UI NoNewPrivileges not set"
        fi
    fi
    
    # 10. Python dependencies
    log_info "Check 10: Python dependencies..."
    local missing_deps=""
    for dep in grpcio protobuf PyQt5; do
        if python3 -c "import ${dep%%-*}" 2>/dev/null; then
            :
        else
            missing_deps="${missing_deps} ${dep}"
        fi
    done
    
    if [[ -z "${missing_deps}" ]]; then
        log_success "  ✓ All Python dependencies present"
    else
        log_warn "  ⚠ Missing Python deps:${missing_deps}"
        ((warnings++))
    fi
    
    # 11. Security score
    log_info "Check 11: Daemon security score..."
    if command -v systemd-analyze &>/dev/null; then
        local sec_score
        sec_score=$(sudo systemd-analyze security opensnitch.service 2>/dev/null | grep -E "^\s*[0-9]+\.[0-9]+" | head -1 | awk '{print $1}' || echo "unknown")
        log_info "  Security score: ${sec_score}/10.0 (lower is better)"
        if [[ "${sec_score}" != "unknown" ]]; then
            local score_float
            score_float=$(echo "${sec_score}" | sed 's/\.$//')
            if (( $(echo "${score_float} < 5.0" | bc -l 2>/dev/null || echo 1) )); then
                log_success "  ✓ Good security posture"
            elif (( $(echo "${score_float} < 7.0" | bc -l 2>/dev/null || echo 1) )); then
                log_warn "  ⚠ Medium security posture (acceptable for firewall daemon)"
            else
                log_warn "  ⚠ High security score - review hardening"
            fi
        fi
    else
        log_info "  systemd-analyze not available for scoring"
    fi
    
    # Summary
    log_header "Verification Summary"
    if [[ ${errors} -eq 0 ]]; then
        if [[ ${warnings} -eq 0 ]]; then
            log_success "✓ All checks passed! OpenSnitch is properly installed and hardened."
            return 0
        else
            log_warn "✓ Installation OK with ${warnings} warning(s). Review above."
            return 0
        fi
    else
        log_error "✗ FAILED: ${errors} error(s) found. Installation incomplete."
        return 1
    fi
}

##################################################################
# Post-Install Summary
##################################################################
post_install_summary() {
    log_header "Installation Complete!"
    
    cat <<SUMMARY

============================================================
           OpenSnitch Hardened Setup - COMPLETE
============================================================

INSTALLATION DETAILS:
  Version:        ${VERSION}
  Daemon:         /usr/bin/opensnitchd
  UI:             /usr/bin/opensnitch-ui
  Config:         /etc/opensnitchd/
  User Config:    ~/.config/opensnitch/
  Backup:         ${OPENSNUITCH_CURRENT_BACKUP}
  Downloads:      ${OPENSNUITCH_CURRENT_DOWNLOADS}
  Logs:           ${OPENSNUITCH_CURRENT_LOG}/installation.log

SYSTEMD SERVICES:
  Daemon:         sudo systemctl status opensnitch.service
  UI:             systemctl --user status opensnitch-ui.service
  
ENABLED AT BOOT:
  Daemon:         $(systemctl is-enabled opensnitch.service 2>/dev/null || echo "unknown")
  UI:             $(systemctl --user is-enabled opensnitch-ui.service 2>/dev/null || echo "unknown")

HARDENING STATUS:
  Daemon Caps:    CAP_NET_ADMIN, DAC_READ_SEARCH, KILL, SYS_PTRACE, BPF, PERFMON
  NoNewPrivs:     YES (both daemon and UI)
  ProtectSystem:  strict (daemon), strict (UI)
  ProtectHome:    read-only (both)
  PrivateTmp:     YES (both)
  Hardening File: /etc/systemd/system/opensnitch.service.d/10-hardening.conf

COMMAND REFERENCE:
  View daemon status:      sudo systemctl status opensnitch
  View UI status:          systemctl --user status opensnitch-ui
  Live daemon logs:        sudo journalctl -u opensnitch -f
  List firewall rules:     opensnitch-cli list-rules
  Export rules:            opensnitch-cli dump-rules > rules.json
  Import rules:            opensnitch-cli load-rules < rules.json
  Kill connection:         opensnitch-cli kill <PID>
  Verify installation:     $(basename "$0") --verify-setup

FIRST USE INSTRUCTIONS:
  1. The UI should start automatically on graphical session
  2. Look for the shield icon in system tray (KDE/GNOME)
  3. Connection prompts will appear as apps attempt outbound network access
  4. Decide Allow/Deny for each, optionally set duration (until reboot, always, etc.)
  5. Over time, rules accumulate and prompts decrease

TROUBLESHOOTING:
  - UI not appearing:      opensnitch-ui --socket 127.0.0.1:50051
  - Daemon crashes:        sudo journalctl -u opensnitch -n 100 --no-pager
  - No connection prompts: sudo systemctl restart opensnitch
  - Too many prompts:      Review rules: opensnitch-cli list-rules
  - Reset everything:      Re-run script (automatically backs up first)

DOCUMENTATION:
  - Main Wiki:             https://github.com/evilsocket/opensnitch/wiki
  - FAQ:                   https://github.com/evilsocket/opensnitch/wiki/FAQ
  - GitHub Issues:         https://github.com/evilsocket/opensnitch/issues
  - Security Analysis:     https://www.freedesktop.org/software/systemd/man/systemd.exec.html

============================================================
SUMMARY
    
    # Hardcore mode warning
    if [[ "${HARDCORE_MODE}" == "true" ]]; then
        echo -e "\n${YELLOW}${BOLD}⚠️  HARDCORE MODE IS ACTIVE${NC}"
        echo "All new connections are BLOCKED until explicitly allowed."
        echo "Ensure you allow: browser, package manager, and essential services."
    fi
    
    log_success "Installation completed successfully at $(date)"
}

##################################################################
# MAIN EXECUTION
##################################################################
main() {
    log_header "OpenSnitch Hardened Setup Script"
    log_info "Started at: $(date)"
    log_info "Running as user: ${REAL_USER}"
    
    log_info "System Information:"
    get_system_info | tee -a "${LOG_FILE}"
    
    # Verification-only mode
    if [[ "${VERIFY_ONLY}" == "true" ]]; then
        run_verification
        exit $?
    fi
    
    # Pre-flight checks
    ensure_not_root
    local fedora_ver
    fedora_ver=$(check_fedora)
    local desktop
    desktop=$(check_desktop)
    local display
    display=$(detect_display_server)
    check_systemd
    
    # Execute installation pipeline
    backup_existing_setup
    reset_previous_install
    download_packages
    install_dependencies
    fix_protobuf_compatibility
    install_opensnitch_rpm
    create_daemon_hardening
    create_ui_service
    enable_and_start_services
    configure_nftables_base
    
    # Optional configurations
    apply_hardcore_mode
    configure_nextdns_integration
    setup_clamav_integration
    setup_bleachbit_integration
    setup_log_rotation
    configure_selinux_policy
    setup_ntfy_notifications
    
    # Final verification
    log_header "Running Post-Install Verification"
    run_verification
    local verify_result=$?
    
    if [[ ${verify_result} -eq 0 ]]; then
        post_install_summary
        log_success "✅ Installation completed successfully!"
        exit 0
    else
        log_error "❌ Installation completed with errors"
        log_info "Review verification output above"
        log_info "Run: $(basename "$0") --verify-setup to re-check"
        exit 1
    fi
}

# Run main with all arguments
main "$@"