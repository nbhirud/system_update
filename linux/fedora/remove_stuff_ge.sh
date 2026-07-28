#!/usr/bin/env bash
# ==============================================================================
# Script Name   : debloat_system.sh
# Description   : Universal Debloat and Low-RAM Optimization Script for Fedora KDE
# Targets       : nbAcer & nbLenovo
# Security      : Hardened execution, non-destructive to user Flatpaks
# ==============================================================================

set -euo pipefail

# --- Color Codes for UI Output ---
RED='\030[0;31m'
GREEN='\032[0;32m'
YELLOW='\033[1;33m'
BLUE='\034[0;34m'
NC='\033[0m' # No Color

# --- Logging Helper Functions ---
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Security & Root Check ---
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)."
   exit 1
fi

HOSTNAME=$(hostname)
log_info "Starting optimization for machine hostname: ${HOSTNAME}"

# ==============================================================================
# 1. DEFINE TARGET PACKAGE LISTS
# ==============================================================================

# Common DNF packages to remove from BOTH nbAcer and nbLenovo
DNF_REMOVE_COMMON=(
    # Office & Productivity
    "libreoffice-*"
    "calligra-*"
    
    # KDE Games Suite
    "kmines"
    "kpat"
    "kmahjongg"
    "ksudoku"
    "kdiamond"
    "kbreakout"
    "knetwalk"
    "kolf"
    "granatier"
    "kapman"
    "katomic"
    "kblackbox"
    "blocks"
    "bovo"
    "kreversi"
    "ksquirrell"
    
    # KDE PIM Suite & Akonadi (Massive RAM consumption)
    "kmail"
    "korganizer"
    "kaddressbook"
    "kontact"
    "akonadi-*"
    "kalarm"
    "kleopatra"
    "knotes"

    # RSS, Podcasts, Media
    "akregator"
    "kasts"
    "dragon"
    "elisa-player"
    "kolourpaint"
    "k3b"
    
    # Remote Desktop & Unnecessary Services
    "krdc"
    "krfb"
    "skanlite"
    "sane-*"
    
    # Telemetry & Automated Bug Reporting
    "abrt*"
)

# Machine-Specific Modifications
DNF_REMOVE_SPECIFIC=()

if [[ "${HOSTNAME}" == "nbLenovo" ]]; then
    log_info "Detected nbLenovo: Preserving webcam software (kamera / kamoso)..."
elif [[ "${HOSTNAME}" == "nbAcer" ]]; then
    log_info "Detected nbAcer: Adding camera packages to removal list..."
    DNF_REMOVE_SPECIFIC+=("kamera" "kamoso")
else
    log_warn "Machine '${HOSTNAME}' is not explicitly nbAcer or nbLenovo. Proceeding with common removals."
fi

# Combine removal arrays
DNF_REMOVE_TOTAL=("${DNF_REMOVE_COMMON[@]}" "${DNF_REMOVE_SPECIFIC[@]}")

# Targeted default Fedora Flatpaks (Pre-installed non-essential apps)
FLATPAK_REMOVE_TARGETS=(
    # "org.fedoraproject.MediaWriter"
)

# ==============================================================================
# 2. DNF PACKAGE REMOVAL
# ==============================================================================
log_info "Removing bloatware RPM packages via DNF..."

# Execute DNF removal silently ignoring missing packages
if dnf remove -y "${DNF_REMOVE_TOTAL[@]}" &>/dev/null; then
    log_success "DNF package cleanup completed successfully."
else
    log_warn "DNF encountered non-critical warnings during package removal. Proceeding..."
fi

# ==============================================================================
# 3. FLATPAK APP CLEANUP (USER FLATPAKS PRESERVED)
# ==============================================================================
log_info "Cleaning pre-installed default Flatpaks..."

if command -v flatpak &>/dev/null; then
    for app in "${FLATPAK_REMOVE_TARGETS[@]}"; do
        if flatpak info "${app}" &>/dev/null; then
            log_info "Removing pre-installed Flatpak: ${app}"
            flatpak uninstall -y --noninteractive "${app}" || true
        fi
    done
    log_success "Flatpak cleanup complete. Flatpak core and user-installed apps remain active."
else
    log_warn "Flatpak is not installed on this system."
fi

# ==============================================================================
# 4. DISABLE RAM-HEAVY KDE BACKGROUND SERVICES
# ==============================================================================
log_info "Disabling Akonadi and Baloo file indexing background daemons..."

# Obtain target user (non-root running user)
SUDO_REAL_USER="${SUDO_USER:-$USER}"

if [[ "${SUDO_REAL_USER}" != "root" ]]; then
    USER_HOME=$(eval echo "~${SUDO_REAL_USER}")
    
    # Disable Baloo File Indexer (Reduces continuous disk I/O on HDDs)
    sudo -u "${SUDO_REAL_USER}" balooctl6 disable &>/dev/null || true
    
    # Write config overrides to stop Baloo & Akonadi autostart
    mkdir -p "${USER_HOME}/.config"
    
    cat <<EOF > "${USER_HOME}/.config/baloofilerc"
[Basic Settings]
Indexing-Enabled=false
EOF

    cat <<EOF > "${USER_HOME}/.config/akonadiric"
[Development]
StartServer=false
EOF

    chown -R "${SUDO_REAL_USER}:${SUDO_REAL_USER}" "${USER_HOME}/.config/baloofilerc" "${USER_HOME}/.config/akonadiric"
    log_success "Background indexing and PIM autostart disabled for user: ${SUDO_REAL_USER}"
fi

# ==============================================================================
# 5. LOW-RAM & HDD SYSCTL / ZRAM OPTIMIZATIONS
# ==============================================================================
log_info "Applying Sysctl optimizations for Low RAM (5-8 GB) and Mechanical HDDs..."

SYSCTL_CONF="/etc/sysctl.d/99-lowram-optimizations.conf"

cat <<EOF > "${SYSCTL_CONF}"
# Reduce aggressiveness of swapping to preserve RAM
vm.swappiness=15

# Consolidate disk writes to minimize HDD thrashing
vm.dirty_background_ratio=5
vm.dirty_ratio=10

# Preserve filesystem cache in memory longer
vm.vfs_cache_pressure=50
EOF

sysctl --system --pattern="vm\." &>/dev/null
log_success "Applied kernel virtual memory tuning in ${SYSCTL_CONF}"

# ==============================================================================
# COMPLETION
# ==============================================================================
echo -e "\n----------------------------------------------------------------------"
log_success "Debloat and system optimization complete for ${HOSTNAME}!"
log_info "Disk I/O and RAM overhead have been significantly reduced."
echo -e "----------------------------------------------------------------------\n"
