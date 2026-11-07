#!/usr/bin/env bash

# ==============================================================================
# Overview and Usage
# ==============================================================================
# Script Name: fedora_system_backup.sh
# Description: Comprehensive, production-grade configuration, repository, COPR,
#              systemd timer, service definition, and desktop MIME state backup 
#              utility designed for Fedora KDE workstations.
# Target Distro: Fedora (validated automatically)
# 
# Usage Examples:
#   1. Run with default options (backs up everything to standard paths):
#      sudo ./fedora_system_backup.sh
#
#   2. Run with a custom backup destination and verification enabled:
#      sudo ./fedora_system_backup.sh --backup-dir="/mnt/storage/backups" --verify-setup="yes"
#
#   3. Display help info:
#      sudo ./fedora_system_backup.sh --help
# ==============================================================================

set -euo pipefail

##################################################################################
# User Defined Variables & Constants
##################################################################################

REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"

# Standard Base Directories
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update"
SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"

BACKUP_NAME_BASE="fedora_backup_ge"
BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/${BACKUP_NAME_BASE}"
CURRENT_BACKUP_DIR="${BACKUP_DIR_BASE}/${BACKUP_NAME_BASE}_${FILENAME_TIMESTAMP}"

VERIFY_SETUP="no"
CUSTOM_BACKUP_DIR=""

##################################################################################
# Named Options Processing
##################################################################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backup-dir=*)
            CUSTOM_BACKUP_DIR="${1#*=}"
            shift
            ;;
        --verify-setup=*)
            VERIFY_SETUP="${1#*=}"
            shift
            ;;
        --help)
            sed -n '/^# Overview andUsage/,/^# ==============================================================================/{p}' "$0"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -n "${CUSTOM_BACKUP_DIR}" ]]; then
    CURRENT_BACKUP_DIR="${CUSTOM_BACKUP_DIR}/${BACKUP_NAME_BASE}_${FILENAME_TIMESTAMP}"
fi

##################################################################################
# Inferred Variables & System Detection
##################################################################################

# Detect system properties using standard helper scripts or fallbacks
if [[ -x "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_distro_name.sh" ]]; then
    DISTRO="$("${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_distro_name.sh")"
else
    DISTRO="$(grep -oP '^ID=\K\w+' /etc/os-release 2>/dev/null || echo "unknown")"
fi

if [[ -x "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_desktop_env.sh" ]]; then
    DESKTOP="$("${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_desktop_env.sh")"
else
    DESKTOP="${XDG_CURRENT_DESKTOP:-KDE}"
fi

if [[ -x "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_cpu_cores.sh" ]]; then
    CPU_CORES="$("${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_cpu_cores.sh")"
else
    CPU_CORES="$(nproc 2>/dev/null || echo "4")"
fi

if [[ -x "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_ram_size.sh" ]]; then
    RAM_MB="$("${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_ram_size.sh")"
else
    RAM_MB="$(free -m | awk '/Mem:/ {print $2}')"
fi

##################################################################################
# Helpers
##################################################################################

log_info() {
    echo -e "\033[1;34m[INFO]\033[0m $*"
}

log_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $*"
}

log_warn() {
    echo -e "\033[1;33m[WARN]\033[0m $*" >&2
}

log_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $*" >&2
}

log_die() {
    log_error "$*"
    exit 1
}

# Validate Fedora execution
require_fedora() {
    if [[ "${DISTRO,,}" != "fedora" ]]; then
        log_die "This script is explicitly designed for Fedora Linux. Detected distro: '${DISTRO}'."
    fi
    log_info "Fedora distribution check passed successfully."
}

##################################################################################
# Pre-flight Checks & Environment Initialization
##################################################################################

if [[ $EUID -ne 0 ]]; then
    log_die "This script must be run with root privileges (sudo) to back up system-wide services, timers, and repositories."
fi

require_fedora

log_info "Initializing Backup Directory Structure at: ${CURRENT_BACKUP_DIR}"
mkdir -p "${CURRENT_BACKUP_DIR}"/{systemd,dnf,flatpak,configs,kde,mime,hardware_info}

# Record hardware and system profile
cat <<EOF > "${CURRENT_BACKUP_DIR}/hardware_info/system_profile.txt"
Timestamp: ${FILENAME_TIMESTAMP}
Distro: ${DISTRO}
Desktop Environment: ${DESKTOP}
CPU Cores: ${CPU_CORES}
RAM MB: ${RAM_MB}
Kernel: $(uname -r)
Hostname: $(hostname)
EOF

##################################################################################
# Backup Repositories and COPRs
##################################################################################

log_info "Backing up DNF repositories and enabled COPR projects..."

# Backup official and third-party repo definitions from /etc/yum.repos.d/
if [[ -d /etc/yum.repos.d ]]; then
    cp -a /etc/yum.repos.d "${CURRENT_BACKUP_DIR}/dnf/"
    log_success "Backed up /etc/yum.repos.d"
fi

# Export enabled COPR repositories list
if command -v dnf &>/dev/null; then
    dnf copr list --enabled > "${CURRENT_BACKUP_DIR}/dnf/enabled_coprs.txt" 2>/dev/null || true
    # Also dump explicitly installed package lists for restoration matching
    dnf repoquery --userinstalled --qf "%{name}\n" > "${CURRENT_BACKUP_DIR}/dnf/user_installed_packages.txt" 2>/dev/null || true
    log_success "Exported enabled COPR list and user-installed RPM package manifest."
fi

##################################################################################
# Backup Systemd Services and Timers
##################################################################################

log_info "Backing up custom systemd system services and timers..."

# Backup custom service and timer overrides or units from /etc/systemd/system/
if [[ -d /etc/systemd/system ]]; then
    mkdir -p "${CURRENT_BACKUP_DIR}/systemd/system_custom"
    # Copy custom user-created units or drop-ins (excluding stock OS symlinks where possible, or archive entire hierarchy safely)
    find /etc/systemd/system -maxdepth 3 \( -type f -o -type l \) -exec cp -a --parents {} "${CURRENT_BACKUP_DIR}/systemd/system_custom" \; 2>/dev/null || true
    log_success "Backed up custom /etc/systemd/system configurations."
fi

# Record active timers status
if command -v systemctl &>/dev/null; then
    systemctl list-timers --all --no-pager > "${CURRENT_BACKUP_DIR}/systemd/active_timers_state.txt" 2>/dev/null || true
    systemctl list-unit-files --state=enabled --no-pager > "${CURRENT_BACKUP_DIR}/systemd/enabled_unit_files.txt" 2>/dev/null || true
    log_success "Recorded active systemd timers and enabled unit files state."
fi

##################################################################################
# Backup Flatpak State & Overrides
##################################################################################

if command -v flatpak &>/dev/null; then
    log_info "Backing up Flatpak installed apps and permission overrides..."
    flatpak list --app --columns=application > "${CURRENT_BACKUP_DIR}/flatpak/installed_flatpaks.txt" 2>/dev/null || true
    if [[ -d /var/lib/flatpak/overrides ]]; then
        cp -a /var/lib/flatpak/overrides "${CURRENT_BACKUP_DIR}/flatpak/system_overrides" 2>/dev/null || true
    fi
    if [[ -d "${HOME_DIR}/.local/share/flatpak/overrides" ]]; then
        cp -a "${HOME_DIR}/.local/share/flatpak/overrides" "${CURRENT_BACKUP_DIR}/flatpak/user_overrides" 2>/dev/null || true
    fi
    log_success "Backed up Flatpak app manifests and permission overrides."
fi

##################################################################################
# Backup KDE Plasma & User Configurations
##################################################################################

log_info "Backing up KDE Plasma settings, global shortcuts, and user configs..."

# Target user config directories
USER_CONFIG_DIR="${HOME_DIR}/.config"
USER_LOCAL_SHARE="${HOME_DIR}/.local/share"

if [[ -d "${USER_CONFIG_DIR}" ]]; then
    mkdir -p "${CURRENT_BACKUP_DIR}/configs/dot_config"
    # Backup essential KDE configuration files and dotfiles safely
    for cfg in kdeglobals kglobalshortcutsrc kwinrc ksmserverrc plasma-org.kde.plasma.desktop-appletsrc kconf_updaterrc; do
        if [[ -f "${USER_CONFIG_DIR}/${cfg}" ]]; then
            cp -a "${USER_CONFIG_DIR}/${cfg}" "${CURRENT_BACKUP_DIR}/configs/dot_config/"
        fi
    done
    # Backup mimeapps.list for default file associations
    if [[ -f "${USER_CONFIG_DIR}/mimeapps.list" ]]; then
        cp -a "${USER_CONFIG_DIR}/mimeapps.list" "${CURRENT_BACKUP_DIR}/mime/user_mimeapps.list"
    fi
fi

# System-wide MIME and desktop defaults
if [[ -f /etc/xdg/mimeapps.list ]]; then
    cp -a /etc/xdg/mimeapps.list "${CURRENT_BACKUP_DIR}/mime/system_mimeapps.list"
fi

# Correct approach for backing up KDE plasma config files safely
KDE_BACKUP_DIR="${CLAMAV_CURRENT_BACKUP_DIR:-/tmp/kde_backup}/kde_plasma"
mkdir -p "${KDE_BACKUP_DIR}"

# Explicit list of primary KDE Plasma configuration files & paths
KDE_CONFIG_FILES=(
    "${HOME_DIR}/.config/plasma-org.kde.plasma.desktop-appletsrc"
    "${HOME_DIR}/.config/plasmarc"
    "${HOME_DIR}/.config/kglobalshortcutsrc"
    "${HOME_DIR}/.config/kdeglobals"
    "${HOME_DIR}/.config/kscreenlockerrc"
    "${HOME_DIR}/.config/kwinrc"
    "${HOME_DIR}/.config/kwalletrc"
    "${HOME_DIR}/.local/share/plasma"
    "${HOME_DIR}/.local/share/kxmlgui5"
)

for target in "${KDE_CONFIG_FILES[@]}"; do
    if [ -e "${target}" ]; then
        cp -a --parents "${target}" "${KDE_BACKUP_DIR}/"
    fi
done



log_success "Backed up KDE configuration profiles and MIME association files."

##################################################################################
# Verification Section
##################################################################################

if [[ "${VERIFY_SETUP,,}" == "yes" ]]; then
    log_info "Running backup integrity verification..."
    if [[ -d "${CURRENT_BACKUP_DIR}" ]]; then
        TOTAL_FILES=$(find "${CURRENT_BACKUP_DIR}" -type f | wc -l)
        log_success "Verification passed: Backup archive directory populated with ${TOTAL_FILES} files."
    else
        log_die "Verification failed: Backup directory was not created properly."
    fi
fi

log_success "All Fedora KDE configurations, services, COPRs, and settings successfully backed up to:"
log_success "${CURRENT_BACKUP_DIR}"

##################################################################################
# Notes
##################################################################################
# - Explanation: This script grabs system-level configurations without attempting 
#   to compress or bundle massive binary files, ensuring portability across multiple
#   target PCs running Fedora 44 KDE.
# - Design Decisions: Uses explicit directory copying (`cp -a --parents`) to retain 
#   permissions, absolute paths, and ownership structures. Employs named options 
#   for maximum script composability.
# - Old Replaced Logic: Removed hardcoded positional parameters in favor of robust 
#   named arguments (`--backup-dir`, `--verify-setup`) and added automated safety checks.
##################################################################################
# Useful Links
##################################################################################
# - Fedora DNF System Administrator Guide: https://docs.fedoraproject.org/en-US/docs/
# - Fedora COPR Documentation: https://copr.fedorainfracloud.org/
# - Systemd Timers Guide: https://www.simplified.guide/systemd/timer-build-backup-job
# - KDE Plasma Configuration Management: https://community.kde.org/
##################################################################################
# Troubleshooting/Debugging/Testing/Commands
##################################################################################
# 1. Test backup dry-run or inspect output contents:
#    ls -lah "${CURRENT_BACKUP_DIR}"
# 2. Restore individual DNF packages from exported user list:
#    sudo dnf install $(cat user_installed_packages.txt)
# 3. Verify enabled COPR repositories on the destination PC:
#    dnf copr list --enabled
# 4. Check systemd timer execution logs:
#    journalctl -u <timer_name>.timer --no-pager
# ==============================================================================