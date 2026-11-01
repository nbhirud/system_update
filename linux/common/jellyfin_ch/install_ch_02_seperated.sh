#!/usr/bin/env bash
set -Eeuo pipefail



# fedora-jellyfin-setup/
# ├── install.sh
# ├── uninstall.sh
# ├── update.sh
# ├── README.md
# │
# ├── lib/
# │   ├── logging.sh
# │   ├── common.sh
# │   ├── hardware.sh
# │   ├── packages.sh
# │   ├── jellyfin.sh
# │   ├── firewall.sh
# │   ├── selinux.sh
# │   ├── permissions.sh
# │   ├── network.sh
# │   ├── systemd.sh
# │   ├── verify.sh
# │
# ├── helpers/
# │   ├── jf-status
# │   ├── jf-logs
# │   ├── jf-health
# │   ├── jf-update
# │
# └── config/
#     └── media.env

# Below is a complete, minimal-but-production-structured repo you can copy into a folder and run on Fedora.

# It is intentionally:

# fully working
# safe (LAN-only, SELinux enforcing)
# modular
# not over-engineered beyond what’s useful right now
# consistent with your ~/nb/Videos requirement
# hardware-aware (VAAPI / NVENC detection)




ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/hardware.sh"
source "$ROOT_DIR/lib/packages.sh"
source "$ROOT_DIR/lib/jellyfin.sh"
source "$ROOT_DIR/lib/firewall.sh"
source "$ROOT_DIR/lib/selinux.sh"
source "$ROOT_DIR/lib/permissions.sh"
source "$ROOT_DIR/lib/network.sh"
source "$ROOT_DIR/lib/systemd.sh"
source "$ROOT_DIR/lib/verify.sh"

require_root
check_fedora

log "Starting Fedora Jellyfin setup"

detect_hardware
install_base_packages

setup_firewall
setup_selinux

install_jellyfin
configure_jellyfin_service

setup_media_permissions
configure_network

setup_helpers
run_verification

ok "INSTALL COMPLETE → http://localhost:8096"