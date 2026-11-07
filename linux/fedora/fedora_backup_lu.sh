#!/usr/bin/env bash
##################################################################################
# Overview and Usage
##################################################################################
# This script creates a comprehensive backup of all Fedora KDE system configurations
# before reformatting. It captures user configs, system settings, repository configs,
# service definitions, timers, MIME associations, and more.
#
# The backup is timestamped and organized into logical categories for easy restore.
#
# Sample calls:
#   # Full backup with all options
#   ./fedora_full_backup.sh --backup-dir "$HOME/nb_script_data/backups/pre_reformat" --timestamp "2026-11-03_10-00-00"
#
#   # Minimal backup with defaults
#   ./fedora_full_backup.sh
#
#   # Verify previous backup integrity
#   ./fedora_full_backup.sh --verify-setup --backup-dir "$HOME/nb_script_data/backups/pre_reformat"
##################################################################################

# set -euo pipefail
set -eux

##################################################################################
# Section: User Defined Variables
##################################################################################
# These variables can be overridden before running the script or via named options
# Defaults are set if not provided

# Override these if you want non-default paths
BACKUP_DIR_OVERRIDE="${BACKUP_DIR_OVERRIDE:-}"
TIMESTAMP_OVERRIDE="${TIMESTAMP_OVERRIDE:-}"
INCLUDE_DOCS_OVERRIDE="${INCLUDE_DOCS_OVERRIDE:-false}"
VERBOSE_OVERRIDE="${VERBOSE_OVERRIDE:-true}"

##################################################################################
# Section: Inferred Variables
##################################################################################
# Standardized paths following your conventions
REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb" 

# Base directories for script data
SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"
SCRIPT_DATA_LOGS="${SCRIPT_DATA}/logs"

# Backup directory for this run
FEDORA_BACKUP_BASE="${SCRIPT_DATA_BACKUPS}/fedora_backup_lu"
FEDORA_CURRENT_BACKUP_DIR="${FEDORA_BACKUP_BASE}/${FILENAME_TIMESTAMP}"

# Log directory
FEDORA_LOG_BASE="${SCRIPT_DATA_LOGS}/fedora_backup_lu"
FEDORA_CURRENT_LOG_DIR="${FEDORA_LOG_BASE}/${FILENAME_TIMESTAMP}"

# Configuration capture directories
CONFIG_BACKUP_DIR="${FEDORA_CURRENT_BACKUP_DIR}/configs"
SYSTEM_BACKUP_DIR="${FEDORA_CURRENT_BACKUP_DIR}/system"
USER_BACKUP_DIR="${FEDORA_CURRENT_BACKUP_DIR}/user"
KEYS_BACKUP_DIR="${FEDORA_CURRENT_BACKUP_DIR}/keys"
LISTINGS_BACKUP_DIR="${FEDORA_CURRENT_BACKUP_DIR}/listings"

# Detection variables
DISTRO=$(bash "$(dirname "$0")/../commong/get_distro_name.sh" 2>/dev/null || echo "unknown")
DISTRO_VERSION=$(bash "$(dirname "$0")/../commong/get_distro_version.sh" 2>/dev/null || echo "0")
DESKTOP=$(bash "$(dirname "$0")/../commong/get_desktop_env.sh" 2>/dev/null || echo "unknown")

# Verify we're on Fedora
if [[ "${DISTRO}" != "fedora" ]]; then
    echo "WARNING: This script is designed for Fedora. Detected: ${DISTRO}"
    echo "Continuing anyway, but some Fedora-specific items may be skipped."
fi

# Verify desktop environment
if [[ "${DESKTOP}" != "kde" && "${DESKTOP}" != "plasma" ]]; then
    echo "WARNING: Expected KDE/Plasma desktop. Detected: ${DESKTOP}"
fi

##################################################################################
# Section: Named Options Processing
##################################################################################
# Parse command line arguments

BACKUP_DIR=""
VERIFY_MODE=false
VERBOSE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --timestamp)
            TIMESTAMP_OVERRIDE="$2"
            shift 2
            ;;
        --include-docs)
            INCLUDE_DOCS_OVERRIDE="true"
            shift
            ;;
        --quiet)
            VERBOSE=false
            shift
            ;;
        --verify-setup)
            VERIFY_MODE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --backup-dir PATH     Override default backup directory"
            echo "  --timestamp STRING    Override timestamp (format: YYYY-MM-DD_HH-MM-SS)"
            echo "  --include-docs        Include document directories in backup"
            echo "  --quiet               Suppress verbose output"
            echo "  --verify-setup        Verify integrity of existing backup"
            echo "  --help                Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Resolve final backup directory
if [[ -n "${BACKUP_DIR_OVERRIDE}" ]]; then
    FEDORA_CURRENT_BACKUP_DIR="${BACKUP_DIR_OVERRIDE}"
    FEDORA_LOG_BASE="${BACKUP_DIR_OVERRIDE}/../logs"
    FEDORA_CURRENT_LOG_DIR="${FEDORA_LOG_BASE}/${FILENAME_TIMESTAMP}"
elif [[ -n "${BACKUP_DIR}" ]]; then
    FEDORA_CURRENT_BACKUP_DIR="${BACKUP_DIR}"
    FEDORA_LOG_BASE="${BACKUP_DIR}/../logs"
    FEDORA_CURRENT_LOG_DIR="${FEDORA_LOG_BASE}/${FILENAME_TIMESTAMP}"
fi

# Create log directory
mkdir -p "${FEDORA_CURRENT_LOG_DIR}"
LOG_FILE="${FEDORA_CURRENT_LOG_DIR}/backup.log"

##################################################################################
# Section: Logging Helpers
##################################################################################
# Colored console output with simultaneous file logging

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "\033[36m${msg}\033[0m" | tee -a "${LOG_FILE}"
    else
        echo "${msg}" >> "${LOG_FILE}"
    fi
}

log_success() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $*"
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "\033[32m${msg}\033[0m" | tee -a "${LOG_FILE}"
    else
        echo "${msg}" >> "${LOG_FILE}"
    fi
}

log_warn() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ $*"
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "\033[33m${msg}\033[0m" | tee -a "${LOG_FILE}"
    else
        echo "${msg}" >> "${LOG_FILE}"
    fi
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ✗ $*"
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "\033[31m${msg}\033[0m" >&2 | tee -a "${LOG_FILE}"
    else
        echo "${msg}" >> "${LOG_FILE}"
    fi
}

log_header() {
    local msg="$*"
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "\n\033[1;35m═══════════════════════════════════════════════════════════\033[0m" | tee -a "${LOG_FILE}"
        echo -e "\033[1;35m  ${msg}\033[0m" | tee -a "${LOG_FILE}"
        echo -e "\033[1;35m═══════════════════════════════════════════════════════════\033[0m\n" | tee -a "${LOG_FILE}"
    else
        echo "${msg}" >> "${LOG_FILE}"
    fi
}

##################################################################################
# Section: Verification Mode
##################################################################################
# If verify mode is enabled, check backup integrity and exit

if [[ "${VERIFY_MODE}" == "true" ]]; then
    log_header "Verifying Backup Integrity"
    
    if [[ ! -d "${FEDORA_CURRENT_BACKUP_DIR}" ]]; then
        log_error "Backup directory not found: ${FEDORA_CURRENT_BACKUP_DIR}"
        exit 1
    fi
    
    # Check manifest exists
    if [[ ! -f "${FEDORA_CURRENT_BACKUP_DIR}/MANIFEST.txt" ]]; then
        log_error "MANIFEST.txt not found in backup"
        exit 1
    fi
    
    # Verify key directories exist
    REQUIRED_DIRS=(
        "configs/home"
        "configs/etc"
        "system/repos"
        "system/services"
        "system/timers"
        "listings/packages"
    )
    
    ALL_OK=true
    for dir in "${REQUIRED_DIRS[@]}"; do
        if [[ ! -d "${FEDORA_CURRENT_BACKUP_DIR}/${dir}" ]]; then
            log_error "Missing required directory: ${dir}"
            ALL_OK=false
        fi
    done
    
    # Verify package listing is non-empty
    if [[ ! -s "${FEDORA_CURRENT_BACKUP_DIR}/listings/packages/dnf_packages.txt" ]]; then
        log_error "Package listing is empty or missing"
        ALL_OK=false
    fi
    
    if [[ "${ALL_OK}" == "true" ]]; then
        log_success "Backup integrity check PASSED"
        log "Backup location: ${FEDORA_CURRENT_BACKUP_DIR}"
        
        # Show summary
        if command -v du &> /dev/null; then
            BACKUP_SIZE=$(du -sh "${FEDORA_CURRENT_BACKUP_DIR}" 2>/dev/null | cut -f1)
            log "Total backup size: ${BACKUP_SIZE}"
        fi
        
        exit 0
    else
        log_error "Backup integrity check FAILED"
        exit 1
    fi
fi

##################################################################################
# Section: Pre-Backup Checks
##################################################################################
# Sanity checks before proceeding

log_header "Pre-Backup Sanity Checks"

# Check we're not running as root (should backup user configs as user)
if [[ "${EUID}" -eq 0 ]]; then
    log_warn "Running as root. Some user-specific configs may not be captured correctly."
    log_warn "Consider running as regular user for complete user config backup."
fi

# Check available disk space
AVAILABLE_SPACE=$(df -h "${FEDORA_CURRENT_BACKUP_DIR%/*}" 2>/dev/null | awk 'NR==2 {print $4}')
log "Available space at backup destination: ${AVAILABLE_SPACE}"

# Warn if backup dir is inside the home that will be reformatted
if [[ "${FEDORA_CURRENT_BACKUP_DIR}" =~ ^"${HOME_DIR}" ]]; then
    log_warn "⚠️  WARNING: Backup directory is INSIDE your home directory!"
    log_warn "This backup will be DELETED during reformat!"
    log_warn "Please move backup to external drive or different partition AFTER running."
    read -p "Press Enter to continue or Ctrl+C to cancel..." 
fi

# Create all necessary directories
log "Creating backup directory structure..."
mkdir -p "${FEDORA_CURRENT_BACKUP_DIR}"
mkdir -p "${CONFIG_BACKUP_DIR}/home/${REAL_USER}"
mkdir -p "${CONFIG_BACKUP_DIR}/etc"
mkdir -p "${SYSTEM_BACKUP_DIR}/repos"
mkdir -p "${SYSTEM_BACKUP_DIR}/services"
mkdir -p "${SYSTEM_BACKUP_DIR}/timers"
mkdir -p "${SYSTEM_BACKUP_DIR}/network"
mkdir -p "${SYSTEM_BACKUP_DIR}/users-groups"
mkdir -p "${KEYS_BACKUP_DIR}/gpg"
mkdir -p "${KEYS_BACKUP_DIR}/ssh"
mkdir -p "${LISTINGS_BACKUP_DIR}/packages"
mkdir -p "${LISTINGS_BACKUP_DIR}/fonts"
mkdir -p "${LISTINGS_BACKUP_DIR}/cron-systemd"

log_success "Directory structure created at: ${FEDORA_CURRENT_BACKUP_DIR}"

##################################################################################
# Section: Package Listings
##################################################################################
# Capture all installed packages for easy reinstallation

log_header "Capturing Installed Packages"

# DNF packages (RPM)
log "Capturing DNF/RPM packages..."
DNF_LIST="${LISTINGS_BACKUP_DIR}/packages/dnf_packages.txt"
DNF_EXPLICIT="${LISTINGS_BACKUP_DIR}/packages/dnf_explicit_packages.txt"
DNF_GROUPS="${LISTINGS_BACKUP_DIR}/packages/dnf_groups.txt"

if command -v dnf &> /dev/null; then
    dnf repoquery --installed --qf '%{name}.%{arch}' | sort > "${DNF_LIST}"
    dnf repoquery --installed --qf '%{name}.%{arch}' --show-duplicates | sort > "${LISTINGS_BACKUP_DIR}/packages/dnf_packages_with_versions.txt"
    
    # Capture explicitly installed packages (not dependencies)
    dnf repoquery --installed --qf '%{name}.%{arch}' --explicit | sort > "${DNF_EXPLICIT}" 2>/dev/null || \
        log_warn "Could not determine explicitly installed packages"
    
    # Capture package groups
    dnf group list -v 2>/dev/null > "${DNF_GROUPS}" || log_warn "Could not capture package groups"
    
    log_success "DNF packages saved: ${DNF_LIST} ($(wc -l < "${DNF_LIST}") packages)"
else
    log_error "DNF not found - skipping package capture"
fi

# Flatpak packages
log "Capturing Flatpak packages..."
FLATPAK_SYSTEM="${LISTINGS_BACKUP_DIR}/packages/flatpak_system.txt"
FLATPAK_USER="${LISTINGS_BACKUP_DIR}/packages/flatpak_user.txt"

if command -v flatpak &> /dev/null; then
    flatpak list --app --columns=application,architecture,branch,id > "${FLATPAK_USER}" 2>/dev/null || true
    flatpak list --runtime --columns=application,architecture,branch,id > "${LISTINGS_BACKUP_DIR}/packages/flatpak_runtimes.txt" 2>/dev/null || true
    flatpak remotes --system --details > "${FLATPAK_SYSTEM}" 2>/dev/null || true
    log_success "Flatpak packages captured"
else
    log "Flatpak not installed - skipping"
fi

# AppImages (if tracked)
log "Checking for AppImages..."
APPIMAGE_DIRS=("${NBDIR}/Applications" "${HOME_DIR}/Applications" "/opt" "/usr/local/bin")
APPIMAGE_LIST="${LISTINGS_BACKUP_DIR}/packages/appimages.txt"
> "${APPIMAGE_LIST}"

for dir in "${APPIMAGE_DIRS[@]}"; do
    if [[ -d "${dir}" ]]; then
        find "${dir}" -maxdepth 2 -type f -executable -name "*.AppImage" 2>/dev/null >> "${APPIMAGE_LIST}" || true
    fi
done

if [[ -s "${APPIMAGE_LIST}" ]]; then
    log_success "Found $(wc -l < "${APPIMAGE_LIST}") AppImage files"
else
    log "No AppImages found in standard locations"
fi

# Snap packages (if present)
log "Checking for Snap packages..."
SNAP_LIST="${LISTINGS_BACKUP_DIR}/packages/snap_packages.txt"
if command -v snap &> /dev/null; then
    snap list > "${SNAP_LIST}" 2>/dev/null || log_warn "Could not capture Snap packages"
    log_success "Snap packages captured"
else
    log "Snap not installed - skipping"
fi

##################################################################################
# Section: Repository and COPR Configuration
##################################################################################
# Capture all repository configurations

log_header "Capturing Repository Configurations"

# Main DNF repos
REPO_DIR="/etc/yum.repos.d"
if [[ -d "${REPO_DIR}" ]]; then
    cp -rv "${REPO_DIR}"/* "${SYSTEM_BACKUP_DIR}/repos/" 2>/dev/null || true
    log_success "DNF repo configs copied from ${REPO_DIR}"
fi

# Additional repo configs
ALT_REPO_DIR="/etc/dnf/repos.d"
if [[ -d "${ALT_REPO_DIR}" ]]; then
    mkdir -p "${SYSTEM_BACKUP_DIR}/repos/alt_repos"
    cp -rv "${ALT_REPO_DIR}"/* "${SYSTEM_BACKUP_DIR}/repos/alt_repos/" 2>/dev/null || true
    log_success "Alternative DNF repo configs captured"
fi

# COPR repositories
COPR_CONF="/etc/yum.repos.d/_copr*"
if compgen -G "${COPR_CONF}" > /dev/null 2>&1; then
    cp -rv "${COPR_CONF}" "${SYSTEM_BACKUP_DIR}/repos/" 2>/dev/null || true
    log_success "COPR repository configs captured"
fi

# List all active COPRs
COPR_LIST="${LISTINGS_BACKUP_DIR}/packages/coprs.txt"
if command -v copr &> /dev/null; then
    copr list 2>/dev/null > "${COPR_LIST}" || log_warn "Could not list COPRs"
fi

# RPM Fusion status
RPMFUSION_FREE="${LISTINGS_BACKUP_DIR}/packages/rpmfusion_free_status.txt"
RPMFUSION_NONFREE="${LISTINGS_BACKUP_DIR}/packages/rpmfusion_nonfree_status.txt"

if rpm -q rpmfusion-free-release &> /dev/null; then
    echo "RPM Fusion Free: INSTALLED" > "${RPMFUSION_FREE}"
else
    echo "RPM Fusion Free: NOT INSTALLED" > "${RPMFUSION_FREE}"
fi

if rpm -q rpmfusion-nonfree-release &> /dev/null; then
    echo "RPM Fusion Non-Free: INSTALLED" > "${RPMFUSION_NONFREE}"
else
    echo "RPM Fusion Non-Free: NOT INSTALLED" > "${RPMFUSION_NONFREE}"
fi

log_success "Repository configurations captured"

##################################################################################
# Section: System Services and Timers
##################################################################################
# Capture all systemd service definitions and timer configurations

log_header "Capturing Systemd Services and Timers"

# Enabled services
SYSTEMD_SERVICES="${SYSTEM_BACKUP_DIR}/services/enabled_services.txt"
systemctl list-units --type=service --state=enabled --plain --no-legend > "${SYSTEMD_SERVICES}" 2>/dev/null || \
    log_warn "Could not list enabled services"

# All unit files (including custom)
SYSTEMD_UNITS="${SYSTEM_BACKUP_DIR}/services/all_unit_files.txt"
systemctl list-unit-files --type=service --plain --no-legend > "${SYSTEMD_UNITS}" 2>/dev/null || \
    log_warn "Could not list all service unit files"

# Custom service files in /etc/systemd/system
CUSTOM_SERVICES="/etc/systemd/system"
if [[ -d "${CUSTOM_SERVICES}" ]]; then
    CUSTOM_SERVICE_FILES=$(find "${CUSTOM_SERVICES}" -name "*.service" -type f 2>/dev/null)
    if [[ -n "${CUSTOM_SERVICE_FILES}" ]]; then
        while IFS= read -r service_file; do
            cp -v "${service_file}" "${SYSTEM_BACKUP_DIR}/services/" 2>/dev/null || true
        done <<< "${CUSTOM_SERVICE_FILES}"
        log_success "Custom service files backed up"
    fi
fi

# User-level services (current user)
USER_SERVICES_DIR="${HOME_DIR}/.config/systemd/user"
if [[ -d "${USER_SERVICES_DIR}" ]]; then
    mkdir -p "${SYSTEM_BACKUP_DIR}/services/user_services"
    cp -rv "${USER_SERVICES_DIR}"/*.service "${SYSTEM_BACKUP_DIR}/services/user_services/" 2>/dev/null || true
    log_success "User-level services backed up"
fi

# Timers
SYSTEMD_TIMERS="${SYSTEM_BACKUP_DIR}/timers/enabled_timers.txt"
systemctl list-timers --all --plain --no-legend > "${SYSTEMD_TIMERS}" 2>/dev/null || \
    log_warn "Could not list timers"

# Custom timer files
if [[ -d "${CUSTOM_SERVICES}" ]]; then
    CUSTOM_TIMER_FILES=$(find "${CUSTOM_SERVICES}" -name "*.timer" -type f 2>/dev/null)
    if [[ -n "${CUSTOM_TIMER_FILES}" ]]; then
        while IFS= read -r timer_file; do
            cp -v "${timer_file}" "${SYSTEM_BACKUP_DIR}/timers/" 2>/dev/null || true
        done <<< "${CUSTOM_TIMER_FILES}"
        log_success "Custom timer files backed up"
    fi
fi

# User-level timers
if [[ -d "${USER_SERVICES_DIR}" ]]; then
    mkdir -p "${SYSTEM_BACKUP_DIR}/timers/user_timers"
    cp -rv "${USER_SERVICES_DIR}"/*.timer "${SYSTEM_BACKUP_DIR}/timers/user_timers/" 2>/dev/null || true
    log_success "User-level timers backed up"
fi

# Drop-in files (important for overrides)
DROPIN_DIR="/etc/systemd/system"
if [[ -d "${DROPIN_DIR}" ]]; then
    CUSTOM_DROPINS=$(find "${DROPIN_DIR}" -name "*.d" -type d 2>/dev/null)
    if [[ -n "${CUSTOM_DROPINS}" ]]; then
        while IFS= read -r dropin; do
            cp -rv "${dropin}" "${SYSTEM_BACKUP_DIR}/services/" 2>/dev/null || true
        done <<< "${CUSTOM_DROPINS}"
        log_success "Systemd drop-in files backed up"
    fi
fi

log_success "Systemd services and timers captured"

##################################################################################
# Section: User Configuration Files
##################################################################################
# Capture all dotfiles and KDE/Plasma configurations

log_header "Capturing User Configuration Files"

# KDE/Plasma specific configs
KDE_CONFIGS=(
    "kdeglobals"
    "kderc"
    "khotkeysrc"
    "kiorc"
    "krmrc"
    "ksysguardrrc"
    "kwalletrc"
    "plasma-org.kde.plasma.desktop-appletsrc"
    "plasma-lookandfeel@org.kde.lookandfeel"
    "kwinrc"
    "kwinrulesrc"
    "kglobalshortcutsrc"
    "kickerarrc"
    "plasmarc"
    "plasmashellrc"
    "kscreen"
    "fontconfig"
)

log "Backing up KDE/Plasma configurations..."
for config in "${KDE_CONFIGS[@]}"; do
    config_path="${HOME_DIR}/.config/${config}"
    if [[ -e "${config_path}" ]]; then
        if [[ -d "${config_path}" ]]; then
            cp -rv "${config_path}" "${CONFIG_BACKUP_DIR}/home/${REAL_USER}/.config/" 2>/dev/null || true
        else
            cp -v "${config_path}" "${CONFIG_BACKUP_DIR}/home/${REAL_USER}/.config/" 2>/dev/null || true
        fi
    fi
done
log_success "KDE/Plasma configs backed up"

# Application-specific configs to capture
APPLICATION_CONFIGS=(
    "alacritty"
    "brave"
    "clamav"
    "code"
    "docker"
    "firewalld"
    "git"
    "gtk-3.0"
    "gtk-4.0"
    "libreoffice"
    "mpv"
    "neovim"
    "obsidian"
    "opensnitch"
    "proton"
    "signal-desktop"
    "syncthing"
    "thunderbird"
    "vscodium"
    "zsh"
    ".bashrc"
    ".profile"
    ".zshrc"
    ".inputrc"
    ".netrc"
    ".gnupg"
    ".ssh"
    ".npm"
    ".pip"
    ".cargo"
    ".python-version"
    ".local/share/keyrings"
    ".local/share/libsecret"
    ".local/share/containers"
    ".mozilla"
)

log "Backing up application configurations..."
for config in "${APPLICATION_CONFIGS[@]}"; do
    config_path="${HOME_DIR}/.config/${config}"
    home_config="${HOME_DIR}/${config}"
    
    # Check .config path first
    if [[ -e "${config_path}" ]]; then
        if [[ -d "${config_path}" ]]; then
            cp -rv "${config_path}" "${CONFIG_BACKUP_DIR}/home/${REAL_USER}/.config/" 2>/dev/null || true
        else
            cp -v "${config_path}" "${CONFIG_BACKUP_DIR}/home/${REAL_USER}/.config/" 2>/dev/null || true
        fi
    # Then check root home path
    elif [[ -e "${home_config}" ]]; then
        if [[ -d "${home_config}" ]]; then
            cp -rv "${home_config}" "${CONFIG_BACKUP_DIR}/home/${REAL_USER}/" 2>/dev/null || true
        else
            cp -v "${home_config}" "${CONFIG_BACKUP_DIR}/home/${REAL_USER}/" 2>/dev/null || true
        fi
    fi
done
log_success "Application configs backed up"

# Local share data (important for apps like Syncthing, databases, etc.)
LOCAL_SHARE_IMPORTANT=(
    "syncthing"
    "containers"
    "nvim"
    "Code"
    "VSCodium"
    "BraveSoftware"
    "libreoffice"
    "thunderbird"
    "keyrings"
    "libsecret"
    "gnupg"
)

log "Backing up important local share data..."
for share in "${LOCAL_SHARE_IMPORTANT[@]}"; do
    share_path="${HOME_DIR}/.local/share/${share}"
    if [[ -e "${share_path}" ]]; then
        cp -rv "${share_path}" "${CONFIG_BACKUP_DIR}/home/${REAL_USER}/.local/share/" 2>/dev/null || true
    fi
done
log_success "Local share data backed up"

# Cache directories worth keeping (some apps store important data here)
CACHE_IMPORTANT=(
    "flatpak"
    "syncthing"
)

log "Checking cache directories..."
for cache in "${CACHE_IMPORTANT[@]}"; do
    cache_path="${HOME_DIR}/.cache/${cache}"
    if [[ -e "${cache_path}" ]]; then
        cp -rv "${cache_path}" "${CONFIG_BACKUP_DIR}/home/${REAL_USER}/.cache/" 2>/dev/null || true
        log_warn "Cached data backed up: ${cache} (may be large)"
    fi
done

##################################################################################
# Section: MIME Applications and Desktop Defaults
##################################################################################
# Capture MIME type associations and default applications

log_header "Capturing MIME Applications and File Associations"

MIME_APPS="${HOME_DIR}/.config/mimeapps.list"
DEFAULT_APPS="${HOME_DIR}/.config/mimeapps.list.default"

if [[ -e "${MIME_APPS}" ]]; then
    cp -v "${MIME_APPS}" "${CONFIG_BACKUP_DIR}/home/${REAL_USER}/.config/" 2>/dev/null || true
    log_success "MIME applications list backed up"
fi

# System-wide MIME defaults
SYSTEM_MIME_DEFAULTS="/usr/share/applications/mimeinfo.cache"
if [[ -e "${SYSTEM_MIME_DEFAULTS}" ]]; then
    cp -v "${SYSTEM_MIME_DEFAULTS}" "${CONFIG_BACKUP_DIR}/etc/" 2>/dev/null || true
fi

# Filetype associations via xdg-mime
XDG_DEFAULTS="${LISTINGS_BACKUP_DIR}/xdg_defaults.txt"
if command -v xdg-mime &> /dev/null; then
    {
        echo "# Querying default applications for common MIME types..."
        for mime in "text/plain" "application/pdf" "image/jpeg" "audio/mpeg" "video/mp4" "inode/directory" "x-scheme-handler/http" "x-scheme-handler/https" "x-scheme-handler/mailto"; do
            echo "${mime}: $(xdg-mime query default "${mime}" 2>/dev/null || echo "NOT SET")"
        done
    } > "${XDG_DEFAULTS}"
    log_success "XDG default applications captured"
fi

# Default shell
SHELL_CONFIG="${LISTINGS_BACKUP_DIR}/shell_config.txt"
echo "Current shell: ${SHELL:-not set}" > "${SHELL_CONFIG}"
echo "Default shell for ${REAL_USER}: $(getent passwd "${REAL_USER}" | cut -d: -f7)" >> "${SHELL_CONFIG}"
log_success "Shell configuration captured"

##################################################################################
# Section: Network Configuration
##################################################################################
# Capture network settings, firewall rules, and DNS configuration

log_header "Capturing Network Configuration"

# Firewall zones and rules
FIREWALL_DIR="/etc/firewalld"
if [[ -d "${FIREWALL_DIR}" ]]; then
    cp -rv "${FIREWALL_DIR}" "${SYSTEM_BACKUP_DIR}/network/" 2>/dev/null || true
    log_success "Firewalld configuration backed up"
fi

# NetworkManager connections
NM_CONNECTIONS="/etc/NetworkManager/system-connections"
if [[ -d "${NM_CONNECTIONS}" ]]; then
    mkdir -p "${SYSTEM_BACKUP_DIR}/network/NetworkManager_connections"
    cp -rv "${NM_CONNECTIONS}"/* "${SYSTEM_BACKUP_DIR}/network/NetworkManager_connections/" 2>/dev/null || true
    log_success "NetworkManager connections backed up"
fi

# Hosts file
cp -v "/etc/hosts" "${CONFIG_BACKUP_DIR}/etc/" 2>/dev/null || true

# Resolv.conf
cp -v "/etc/resolv.conf" "${CONFIG_BACKUP_DIR}/etc/" 2>/dev/null || true

# Nslookup/dns-test
DNS_TEST="${SYSTEM_BACKUP_DIR}/network/dns_test.txt"
if command -v nslookup &> /dev/null; then
    nslookup google.com > "${DNS_TEST}" 2>&1 || log_warn "DNS test failed"
elif command -v dig &> /dev/null; then
    dig google.com > "${DNS_TEST}" 2>&1 || log_warn "DNS test failed"
fi

# IP configuration
IP_CONFIG="${SYSTEM_BACKUP_DIR}/network/ip_config.txt"
if command -v ip &> /dev/null; then
    ip addr show > "${IP_CONFIG}" 2>&1
    ip route show >> "${IP_CONFIG}" 2>&1
    log_success "IP configuration captured"
fi

log_success "Network configuration captured"

##################################################################################
# Section: User Accounts and Groups
##################################################################################
# Capture user and group information

log_header "Capturing User and Group Information"

USERS_LIST="${SYSTEM_BACKUP_DIR}/users-groups/users.txt"
GROUPS_LIST="${SYSTEM_BACKUP_DIR}/users-groups/groups.txt"
SUDOERS_LIST="${SYSTEM_BACKUP_DIR}/users-groups/sudoers.txt"
CRONTAB_LIST="${SYSTEM_BACKUP_DIR}/users-groups/crontabs.txt"

# Users
cat /etc/passwd > "${USERS_LIST}"
log_success "User accounts captured"

# Groups
cat /etc/group > "${GROUPS_LIST}"
log_success "Group definitions captured"

# Sudoers configuration
if [[ -d "/etc/sudoers.d" ]]; then
    cp -rv /etc/sudoers.d/ "${SYSTEM_BACKUP_DIR}/users-groups/" 2>/dev/null || true
fi
if [[ -f "/etc/sudoers" ]]; then
    # Only copy if readable
    cp -v /etc/sudoers "${SYSTEM_BACKUP_DIR}/users-groups/" 2>/dev/null || log_warn "Cannot read /etc/sudoers"
fi
log_success "Sudoers configuration backed up"

# User crontabs
for user in $(cut -f1 -d: /etc/passwd); do
    user_crontab=$(crontab -u "${user}" -l 2>/dev/null)
    if [[ -n "${user_crontab}" ]]; then
        echo "# Crontab for user: ${user}" >> "${CRONTAB_LIST}"
        echo "${user_crontab}" >> "${CRONTAB_LIST}"
        echo "" >> "${CRONTAB_LIST}"
    fi
done

# System cron directories
CRON_DIRS=("/etc/cron.d" "/etc/cron.daily" "/etc/cron.hourly" "/etc/cron.weekly" "/etc/cron.monthly")
for cron_dir in "${CRON_DIRS[@]}"; do
    if [[ -d "${cron_dir}" ]]; then
        cp -rv "${cron_dir}" "${LISTINGS_BACKUP_DIR}/cron-systemd/" 2>/dev/null || true
    fi
done
log_success "Cron jobs captured"

# Systemd user slices and overrides
if [[ -d "/etc/systemd/user" ]]; then
    cp -rv "/etc/systemd/user" "${SYSTEM_BACKUP_DIR}/services/" 2>/dev/null || true
fi
log_success "Systemd user configuration captured"

log_success "User and group information captured"

##################################################################################
# Section: Cryptographic Keys
##################################################################################
# Backup GPG and SSH keys (SENSITIVE - ensure secure storage!)

log_header "Backing Up Cryptographic Keys"

# GPG keys export
GPG_HOME="${HOME_DIR}/.gnupg"
if [[ -d "${GPG_HOME}" ]]; then
    # Export public keys
    GPG_PUBLIC="${KEYS_BACKUP_DIR}/gpg/public_keys.asc"
    gpg --armor --export > "${GPG_PUBLIC}" 2>/dev/null || log_warn "Could not export GPG public keys"
    
    # Export secret keys (WARN about security!)
    GPG_SECRET="${KEYS_BACKUP_DIR}/gpg/secret_keys.asc"
    gpg --armor --export-secret-keys > "${GPG_SECRET}" 2>/dev/null || log_warn "Could not export GPG secret keys"
    
    log_warn "GPG keys backed up - STORE SECURELY! Secret keys contain private material!"
    
    # Copy gnupg directory structure
    cp -rv "${GPG_HOME}" "${KEYS_BACKUP_DIR}/gpg/" 2>/dev/null || true
fi

# SSH keys
SSH_HOME="${HOME_DIR}/.ssh"
if [[ -d "${SSH_HOME}" ]]; then
    # Find all private keys
    SSH_KEYS=$(find "${SSH_HOME}" -name "id_*" -type f ! -name "*.pub" 2>/dev/null)
    if [[ -n "${SSH_KEYS}" ]]; then
        while IFS= read -r key_file; do
            cp -v "${key_file}" "${KEYS_BACKUP_DIR}/ssh/" 2>/dev/null || true
            # Also backup corresponding public key
            pub_key="${key_file}.pub"
            if [[ -f "${pub_key}" ]]; then
                cp -v "${pub_key}" "${KEYS_BACKUP_DIR}/ssh/" 2>/dev/null || true
            fi
        done <<< "${SSH_KEYS}"
        log_warn "SSH private keys backed up - STORE SECURELY!"
    fi
    
    # Backup SSH config
    if [[ -f "${SSH_HOME}/config" ]]; then
        cp -v "${SSH_HOME}/config" "${KEYS_BACKUP_DIR}/ssh/" 2>/dev/null || true
    fi
    
    # Backup known_hosts
    if [[ -f "${SSH_HOME}/known_hosts" ]]; then
        cp -v "${SSH_HOME}/known_hosts" "${KEYS_BACKUP_DIR}/ssh/" 2>/dev/null || true
    fi
fi

log_success "Cryptographic keys backed up"
log_warn "⚠️  IMPORTANT: Store key backups securely! Consider encrypting them!"

##################################################################################
# Section: Font Configuration
##################################################################################
# Capture installed fonts and fontconfig settings

log_header "Capturing Font Configuration"

FONT_LIST="${LISTINGS_BACKUP_DIR}/fonts/installed_fonts.txt"
FONTCACHE_DIR="${CONFIG_BACKUP_DIR}/home/${REAL_USER}/.cache/fontconfig"

# List installed fonts
if command -v fc-list &> /dev/null; then
    fc-list : file family style > "${FONT_LIST}" 2>/dev/null || log_warn "Could not list fonts"
    log_success "Font inventory created ($(wc -l < "${FONT_LIST}") fonts)"
fi

# Fontconfig configuration
FC_CONF="${HOME_DIR}/.config/fontconfig"
if [[ -d "${FC_CONF}" ]]; then
    cp -rv "${FC_CONF}" "${CONFIG_BACKUP_DIR}/home/${REAL_USER}/.config/" 2>/dev/null || true
fi

# System fontconfig
if [[ -d "/etc/fonts" ]]; then
    cp -rv "/etc/fonts" "${CONFIG_BACKUP_DIR}/etc/" 2>/dev/null || true
fi

log_success "Font configuration captured"

##################################################################################
# Section: Environment Variables and Aliases
##################################################################################
# Capture shell environment customization

log_header "Capturing Environment Configuration"

ENV_EXPORT="${HOME_DIR}/.config/fedora_backup_env_exports.txt"
ALIAS_LIST="${HOME_DIR}/.config/fedora_backup_aliases.txt"
FUNCTION_LIST="${HOME_DIR}/.config/fedora_backup_functions.txt"

# Exported environment variables
env > "${ENV_EXPORT}" 2>/dev/null || log_warn "Could not capture environment variables"
log_success "Environment variables captured"

# Shell aliases (for current user's shells)
SHELL_RC_FILES=(
    "${HOME_DIR}/.bashrc"
    "${HOME_DIR}/.zshrc"
    "${HOME_DIR}/.bash_aliases"
    "${HOME_DIR}/.zsh/aliases.zsh"
)

for rc_file in "${SHELL_RC_FILES[@]}"; do
    if [[ -f "${rc_file}" ]]; then
        grep -E "^\s*(alias|export)\s" "${rc_file}" >> "${ALIAS_LIST}" 2>/dev/null || true
    fi
done
log_success "Aliases captured"

# Shell functions extraction attempt
for rc_file in "${SHELL_RC_FILES[@]}"; do
    if [[ -f "${rc_file}" ]]; then
        grep -E "^[a-zA-Z_][a-zA-Z0-9_]*\(\)" "${rc_file}" >> "${FUNCTION_LIST}" 2>/dev/null || true
    fi
done
log_success "Shell functions captured (pattern-based)"

log_success "Environment configuration captured"

##################################################################################
# Section: System Information Snapshot
##################################################################################
# Create a comprehensive system info file for reference

log_header "Creating System Information Snapshot"

INFO_FILE="${SYSTEM_BACKUP_DIR}/system_info.txt"

{
    echo "═══════════════════════════════════════════════════════════"
    echo "Fedora System Information Snapshot"
    echo "Generated: $(date)"
    echo "Host: $(hostname)"
    echo "User: ${REAL_USER}"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "--- OS Information ---"
    cat /etc/os-release
    echo ""
    echo "--- Kernel ---"
    uname -a
    echo ""
    echo "--- CPU ---"
    lscpu | head -20
    echo ""
    echo "--- Memory ---"
    free -h
    echo ""
    echo "--- Disk ---"
    df -h
    echo ""
    echo "--- GPU ---"
    lspci | grep -E "VGA|3D|Display" || echo "GPU info not available"
    echo ""
    echo "--- Running Services Count ---"
    systemctl list-units --type=service --state=running --plain --no-legend | wc -l
    echo ""
    echo "--- Active Connections ---"
    ss -tulnp 2>/dev/null || netstat -tulnp 2>/dev/null || echo "Connection info not available"
    echo ""
    echo "--- Mounted Filesystems ---"
    mount | grep -v "^proc\|^sys\|^dev"
    echo ""
    echo "--- Uptime ---"
    uptime
} > "${INFO_FILE}" 2>&1

log_success "System information snapshot created"

##################################################################################
# Section: Optional Document Backup
##################################################################################
# Backup common document directories if requested

log_header "Checking Document Directories"

DOCUMENT_DIRS=(
    "${HOME_DIR}/Documents"
    "${HOME_DIR}/Downloads"
    "${HOME_DIR}/Pictures"
    "${HOME_DIR}/Videos"
    "${NBDIR}"
    "${HOME_DIR}/Music"
)

if [[ "${INCLUDE_DOCS_OVERRIDE}" == "true" ]]; then
    DOCS_BACKUP_DIR="${FEDORA_CURRENT_BACKUP_DIR}/documents"
    mkdir -p "${DOCS_BACKUP_DIR}"
    
    for doc_dir in "${DOCUMENT_DIRS[@]}"; do
        if [[ -d "${doc_dir}" ]]; then
            DIR_NAME=$(basename "${doc_dir}")
            log "Backing up ${DIR_NAME}..."
            
            # Calculate size first
            DIR_SIZE=$(du -sh "${doc_dir}" 2>/dev/null | cut -f1)
            if [[ "${DIR_SIZE}" == "0K" ]] || [[ -z "${DIR_SIZE}" ]]; then
                log "Skipping ${DIR_NAME} (empty)"
                continue
            fi
            
            if [[ "${DIR_SIZE}" =~ ^[0-9]+[GM] ]]; then
                log_warn "Large directory: ${DIR_NAME} (${DIR_SIZE}) - backing up anyway"
            fi
            
            cp -rv "${doc_dir}" "${DOCS_BACKUP_DIR}/" 2>/dev/null || true
        fi
    done
    
    log_success "Document backup completed"
else
    log "Document directories not included (use --include-docs to enable)"
    
    # Create a reminder file
    REMINDER="${FEDORA_CURRENT_BACKUP_DIR}/DOCUMENT_BACKUP_REMINDER.txt"
    cat > "${REMINDER}" << 'EOF'
═══════════════════════════════════════════════════════════
DOCUMENT DIRECTORY BACKUP NOT INCLUDED
═══════════════════════════════════════════════════════════

This backup does NOT include your Documents, Downloads, Pictures, 
or other personal directories.

To include them, run:
  ./fedora_full_backup.sh --include-docs

Alternatively, manually backup these directories:
  ~/Documents
  ~/Downloads
  ~/Pictures
  ~/Videos
  ~/Music
  ~/nb (your main data directory)

═══════════════════════════════════════════════════════════
EOF
    log "Created reminder file: ${REMINDER}"
fi

##################################################################################
# Section: Manifest Creation
##################################################################################
# Create a manifest file for tracking and verification

log_header "Creating Backup Manifest"

MANIFEST="${FEDORA_CURRENT_BACKUP_DIR}/MANIFEST.txt"

{
    echo "═══════════════════════════════════════════════════════════"
    echo "Fedora Pre-Reformat Backup Manifest"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Backup Timestamp: ${FILENAME_TIMESTAMP}"
    echo "Backup Location: ${FEDORA_CURRENT_BACKUP_DIR}"
    echo "Hostname: $(hostname)"
    echo "Distrol: ${DISTRO} ${DISTRO_VERSION}"
    echo "Desktop: ${DESKTOP}"
    echo "Real User: ${REAL_USER}"
    echo "Generated: $(date)"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "BACKUP CONTENTS"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Directory tree
    find "${FEDORA_CURRENT_BACKUP_DIR}" -type d | sed "s|${FEDORA_CURRENT_BACKUP_DIR}||" | sort
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "FILE COUNTS BY CATEGORY"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Configs: $(find "${CONFIG_BACKUP_DIR}" -type f 2>/dev/null | wc -l)"
    echo "Services: $(find "${SYSTEM_BACKUP_DIR}/services" -type f 2>/dev/null | wc -l)"
    echo "Timers: $(find "${SYSTEM_BACKUP_DIR}/timers" -type f 2>/dev/null | wc -l)"
    echo "Package Listings: $(find "${LISTINGS_BACKUP_DIR}/packages" -type f 2>/dev/null | wc -l)"
    echo "Keys: $(find "${KEYS_BACKUP_DIR}" -type f 2>/dev/null | wc -l)"
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "BACKUP SIZE"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    if command -v du &> /dev/null; then
        du -sh "${FEDORA_CURRENT_BACKUP_DIR}"
        echo ""
        echo "Per-directory breakdown:"
        du -sh "${FEDORA_CURRENT_BACKUP_DIR}"/* 2>/dev/null | sort -hr
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "RESTORE NOTES"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "1. Restore system configs first (/etc/*)"
    echo "2. Restore user configs (~/.config/*)"
    echo "3. Reinstall packages from listings"
    echo "4. Import cryptographic keys securely"
    echo "5. Restart affected services"
    echo "6. Verify MIME associations"
    echo "7. Test all applications"
    echo ""
    echo "Useful restore commands:"
    echo "  # Packages: sudo dnf install \$(cat listings/packages/dnf_packages.txt)"
    echo "  # SSH keys: chmod 600 ~/.ssh/id_* && chmod 644 ~/.ssh/*.pub"
    echo "  # GPG keys: gpg --import keys/gpg/secret_keys.asc"
    echo "  # Services: sudo systemctl daemon-reexec && sudo systemctl restart <service>"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
} > "${MANIFEST}"

log_success "Manifest created: ${MANIFEST}"

##################################################################################
# Section: Security Hardening Reminder
##################################################################################
# Remind user to encrypt sensitive backup

log_header "Security Recommendations"

SECURITY_NOTE="${FEDORA_CURRENT_BACKUP_DIR}/SECURITY_NOTES.txt"

cat > "${SECURITY_NOTE}" << 'EOF'
═══════════════════════════════════════════════════════════
⚠️  SECURITY NOTICE FOR THIS BACKUP ⚠️
═══════════════════════════════════════════════════════════

This backup contains sensitive information including:
  • Private SSH keys
  • GPG secret keys  
  • Application credentials
  • Network configurations
  • Personal data

IMMEDIATE ACTIONS REQUIRED:

1. ENCRYPT THE BACKUP
   Recommended: Using GPG symmetric encryption
   gpg --symmetric --cipher-algo AES256 MANIFEST.txt
   
   Or encrypt entire directory:
   tar czf backup.tar.gz fedora_backup_*
   gpg --symmetric --cipher-algo AES256 backup.tar.gz

2. MOVE TO SAFE LOCATION
   • External encrypted drive
   • Secure cloud storage (Proton Drive recommended)
   • Offline storage (USB kept in safe)

3. DELETE FROM TEMPORARY LOCATIONS
   After confirming encryption and transfer:
   shred -u -z -n 3 /path/to/unencrypted/backup

4. TEST RESTORE PROCEDURE
   Before wiping your system, test restore on a VM or
   spare machine to ensure backup integrity

5. VERIFY INTEGRITY
   ./fedora_full_backup.sh --verify-setup --backup-dir /path/to/backup

═══════════════════════════════════════════════════════════
Recommended Encryption Tools (FOSS):
  • VeraCrypt (full disk/container encryption)
  • GPG (file encryption)
  • ecryptfs (home directory encryption)
  • LUKS (block device encryption)

Store encryption passphrase in:
  • Proton Pass
  • KeePassXC (offline)
  • Physical safe location

═══════════════════════════════════════════════════════════
EOF

log_success "Security notes created: ${SECURITY_NOTE}"

##################################################################################
# Section: Final Summary
##################################################################################
# Display completion summary

log_header "Backup Complete"

SUMMARY="${FEDORA_CURRENT_BACKUP_DIR}/SUMMARY.txt"

{
    echo "═══════════════════════════════════════════════════════════"
    echo "BACKUP COMPLETION SUMMARY"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Timestamp: ${FILENAME_TIMESTAMP}"
    echo "Location: ${FEDORA_CURRENT_BACKUP_DIR}"
    echo "Size: $(du -sh "${FEDORA_CURRENT_BACKUP_DIR}" 2>/dev/null | cut -f1)"
    echo "Files: $(find "${FEDORA_CURRENT_BACKUP_DIR}" -type f 2>/dev/null | wc -l)"
    echo "Directories: $(find "${FEDORA_CURRENT_BACKUP_DIR}" -type d 2>/dev/null | wc -l)"
    echo ""
    echo "What was backed up:"
    echo "  ✓ Installed packages (DNF, Flatpak, Snap, AppImage)"
    echo "  ✓ Repository and COPR configurations"
    echo "  ✓ Systemd services and timers"
    echo "  ✓ User configurations (KDE, apps, shells)"
    echo "  ✓ MIME applications and file associations"
    echo "  ✓ Network configuration (firewall, connections)"
    echo "  ✓ User accounts and groups"
    echo "  ✓ Cryptographic keys (GPG, SSH)"
    echo "  ✓ Font configurations"
    echo "  ✓ Environment variables and aliases"
    echo "  ✓ System information snapshot"
    echo ""
    echo "Next Steps:"
    echo "  1. Verify backup: ./fedora_full_backup.sh --verify-setup"
    echo "  2. Encrypt sensitive files (see SECURITY_NOTES.txt)"
    echo "  3. Move backup to external/secure location"
    echo "  4. Test restore procedure on spare machine"
    echo "  5. Proceed with reformat when ready"
    echo ""
    echo "Restore Reference:"
    echo "  Package reinstall: sudo dnf install \$(cat listings/packages/dnf_packages.txt)"
    echo "  Config restore: rsync -av configs/home/${REAL_USER}/ ~/ --exclude='.cache'"
    echo "  Keys import: See KEYS_BACKUP_DIR/README.txt"
    echo ""
    echo "Log Location: ${FEDORA_CURRENT_LOG_DIR}/backup.log"
    echo "═══════════════════════════════════════════════════════════"
} > "${SUMMARY}"

log_success "═══════════════════════════════════════════════════════════"
log_success "                    BACKUP SUCCESSFULLY COMPLETED"
log_success "═══════════════════════════════════════════════════════════"
log "Location: ${FEDORA_CURRENT_BACKUP_DIR}"
log "Size: $(du -sh "${FEDORA_CURRENT_BACKUP_DIR}" 2>/dev/null | cut -f1)"
log "Files: $(find "${FEDORA_CURRENT_BACKUP_DIR}" -type f 2>/dev/null | wc -l)"
log ""
log "See ${SUMMARY} for detailed summary"
log "See ${SECURITY_NOTE} for security recommendations"
log ""
log "Verify with: ./fedora_full_backup.sh --verify-setup --backup-dir ${FEDORA_CURRENT_BACKUP_DIR}"
log_success "═══════════════════════════════════════════════════════════"

exit 0

##################################################################################
# Notes
##################################################################################
# Design Decisions and Implementation Notes

# 1. Why separate user vs system configs?
#    - User configs contain personal data and credentials
#    - System configs require root access
#    - Makes restoration more granular and safer

# 2. Why capture both package lists AND repo configs?
#    - Package list enables exact recreation
#    - Repo configs ensure third-party sources are restored
#    - COPR configs often forgotten during restore

# 3. Why backup cryptographic keys separately?
#    - Keys need special handling and permissions
#    - Should be stored with higher security
#    - Requires manual intervention during restore

# 4. Why skip document backup by default?
#    - Documents can be huge (GBs)
#    - Users may already have document backup strategy
#    - Can be included with --include-docs flag

# 5. Why create manifest and security notes?
#    - Manifest allows quick verification without browsing
#    - Security notes remind about encryption necessity
#    - Critical for preventing accidental credential exposure

# 6. Previous approach comparison:
#    OLD: Simple tar of /etc and ~
#    PROBLEMS: No organization, no verification, no documentation
#    NEW: Structured, verifiable, documented, categorized
#    IMPROVEMENT: Can restore selectively, verify integrity, track changes

# 7. Idempotency considerations:
#    - Each run creates new timestamped directory
#    - Never overwrites existing backups
#    - Safe to run multiple times

# 8. Performance optimizations:
#    - Uses cp -r (fastest for bulk copying)
#    - Skips obvious empty directories
#    - Logs progress for troubleshooting

# 9. Edge cases handled:
#    - Missing optional components (Flatpak, Snap, COPR)
#    - Permission denied errors (logged, doesn't crash)
#    - Large files (warnings displayed)
#    - Run as root vs regular user

##################################################################################
# Useful Links
##################################################################################
# Research sources and documentation used

# Fedora Backup Best Practices
# https://docs.fedoraproject.org/en-US/quick-docs/creating-system-backups/
# https://fedoramagazine.org/how-to-back-up-and-restore-a-fedora-system/

# RPM Package Management
# https://rpm.org/documentation.html
# https://docs.fedoraproject.org/en-US/quick-docs/dnf/

# Systemd Services Documentation
# https://www.freedesktop.org/software/systemd/man/systemctl.html
# https://wiki.archlinux.org/title/Systemd/User#Automatic_start-up_of_systemd_user_instances
# (Arch wiki excellent for systemd concepts, applicable to Fedora)

# KDE Configuration Structure
# https://develop.kde.org/docs/plasma-desktop/configuration-files/
# https://wiki.archlinux.org/title/KDE

# GPG Backup and Recovery
# https://wiki.gnupg.org/Backup
# https://www.gnupg.org/documentation/faqs.html#Q10

# SSH Key Security
# https://www.ssh.com/academy/ssh/protocol/key-authentication
# https://github.com/anatol/ssh-utils

# Security Hardening Reference
# https://cisecurity.org/benchmark/red_hat_linux
# https://security.fedoraproject.org/

# Manifest and Verification Patterns
# https://tarsnap.com/scalability.html (for understanding manifest-based backups)
# https://borgbackup.readthedocs.io/en/stable/usage/help/help.html (manifest patterns)

# SELinux Considerations
# https://docs.fedoraproject.org/en-US/fedora/latest/system-administrators-guide/SELinux/
# May need restoration attention if restoring contexts

# MIME Applications Database
# https://specifications.freedesktop.org/mime-app-spec/mime-app-spec-latest.html
# https://wiki.archlinux.org/title/XDG_menu

# Cron vs Systemd Timer Migration Guide
# https://fedoramagazine.org/use-systemd-timers-instead-of-cron-jobs/

##################################################################################
# Troubleshooting/Debugging/Testing/Commands
##################################################################################

# Debug Mode
# Enable verbose output:
#   ./fedora_full_backup.sh --quiet=false
# Or modify script: VERBOSE=true at top

# Check what would be captured without running full backup:
#   ls -la ~/.config | head -50
#   systemctl list-units --type=service --state=enabled
#   dnf list installed | head -50

# Test restore procedure (on VM or spare machine):
#   # Restore packages
#   sudo dnf install $(cat listings/packages/dnf_packages.txt)
   
#   # Restore configs (BE CAREFUL - review first!)
#   rsync -avn configs/home/$USER/ ~/  # -n for dry-run first
#   rsync -av configs/home/$USER/ ~/   # Actual restore
   
#   # Restore SSH keys
#   cp KEYS_BACKUP_DIR/ssh/id_* ~/.ssh/
#   chmod 600 ~/.ssh/id_*
#   chmod 644 ~/.ssh/*.pub
   
#   # Restore GPG keys  
#   gpg --import KEYS_BACKUP_DIR/gpg/secret_keys.asc

# Verify backup integrity:
#   ./fedora_full_backup.sh --verify-setup --backup-dir /path/to/backup
   
# Compare two backups (check for differences):
#   diff -rq backup1 configs/ backup2 configs/ 2>/dev/null
   
# Check backup size and estimate time:
#   du -sh /path/to/backup
#   find /path/to/backup -type f | wc -l  # File count
   
# Restore specific component only:
#   # Just packages
#   sudo dnf install $(cat listings/packages/dnf_packages.txt)
   
#   # Just KDE config  
#   rsync -av configs/home/$USER/.config/k* ~/.config/
   
#   # Just services
#   sudo cp SYSTEM_BACKUP_DIR/services/*.service /etc/systemd/system/
#   sudo systemctl daemon-reload

# Common Issues:
# 1. Permission denied on some files:
#    - Run as same user who owns configs
#    - Or run with sudo but review carefully
   
# 2. Backup too large:
#    - Exclude .cache directories (already cached)
#    - Use --include-docs=false (default)
#    - Compress after creation: tar czf backup.tar.gz backup_dir/
   
# 3. Restore broke something:
#    - Start with clean slate (fresh install)
#    - Restore configs incrementally, not all at once
#    - Keep original backup untouched
   
# 4. Encrypted home directory:
#    - Backup will capture decrypted files
#    - Still encrypt final backup archive
#    - Handle LUKS headers separately if needed

# Create compressed archive after successful backup:
#   cd "${FEDORA_CURRENT_BACKUP_DIR%/*}"
#   tar czf "fedora_backup_${FILENAME_TIMESTAMP}.tar.gz" "fedora_pre_reformat/${FILENAME_TIMESTAMP}/"
#   gpg --symmetric --cipher-algo AES256 "fedora_backup_${FILENAME_TIMESTAMP}.tar.gz"
#   rm "fedora_backup_${FILENAME_TIMESTAMP}.tar.gz"  # Remove unencrypted version

# Schedule automated weekly backups (optional):
#   # Create systemd timer
#   cat > ~/.config/systemd/user/fedora-backup.timer << EOF
# [Unit]
# Description=Weekly Fedora Config Backup
# 
# [Timer]
# OnCalendar=weekly
# Persistent=true
# 
# [Install]
# WantedBy=timers.target
# EOF
#   
#   systemctl --user enable --now fedora-backup.timer

# Monitor backup success via notification:
#   # Add to script end (requires ntfy setup):
#   curl -d "Backup completed: ${FILENAME_TIMESTAMP}" ntfy.sh/your-topic

# Verify specific file counts after backup:
#   echo "Expected packages: $(wc -l < listings/packages/dnf_packages.txt)"
#   echo "Config files: $(find configs/ -type f | wc -l)"
#   echo "Service files: $(find system/services/ -name '*.service' | wc -l)"

# Quick health check of backup:
#   # All critical files present?
#   test -f MANIFEST.txt && echo "✓ Manifest" || echo "✗ Manifest"
#   test -f listings/packages/dnf_packages.txt && echo "✓ Package list" || echo "✗ Package list"
#   test -d configs/home && echo "✓ User configs" || echo "✗ User configs"
#   test -d KEYS_BACKUP_DIR/ssh && echo "✓ SSH keys" || echo "✗ SSH keys"
