#!/usr/bin/env bash
#########################################################
# OpenSnitch Hardened Setup & Pre-configured Rules Script
# For Fedora 44/45 + KDE Plasma (Wayland/X11)
#########################################################

set -euo pipefail

#########################################################
# Options & Directories Setup
#########################################################
VERSION=""
DOWNLOAD_DIR=""
NEXTDNS_ID=""
HARDCORE_MODE="false"
SKIP_PROTOBUF_FIX="false"
VERIFY_ONLY="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --download-dir) DOWNLOAD_DIR="$2"; shift 2 ;;
        --nextdns-id) NEXTDNS_ID="$2"; shift 2 ;;
        --hardcore) HARDCORE_MODE="true"; shift ;;
        --skip-protobuf-fix) SKIP_PROTOBUF_FIX="true"; shift ;;
        --verify-setup) VERIFY_ONLY="true"; shift ;;
        --help|-h)
            cat <<EOF
Usage: $(basename "$0") [OPTIONS]
Options:
    --version VERSION     Specify OpenSnitch version
    --download-dir PATH   Custom download directory
    --nextdns-id ID       NextDNS device identifier tag
    --hardcore            Enable default-deny firewall policy
    --skip-protobuf-fix   Skip protobuf 3.x compatibility fix
    --verify-setup        Run verification checks only
    --help                Show this help message
EOF
            exit 0
            ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"

SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads/opensnitch/opensnitch_${FILENAME_TIMESTAMP}"
SCRIPT_DATA_LOGS="${SCRIPT_DATA}/logs/opensnitch/opensnitch_${FILENAME_TIMESTAMP}"

mkdir -p "${SCRIPT_DATA_DOWNLOADS}" "${SCRIPT_DATA_LOGS}"

if [[ -n "${DOWNLOAD_DIR}" ]]; then
    SCRIPT_DATA_DOWNLOADS="${DOWNLOAD_DIR}"
    mkdir -p "${SCRIPT_DATA_DOWNLOADS}"
fi

readonly LOG_FILE="${SCRIPT_DATA_LOGS}/installation.log"
log_info()    { echo -e "\e[34m[INFO]\e[0m $*" | tee -a "${LOG_FILE}"; }
log_success() { echo -e "\e[32m[✓]\e[0m $*" | tee -a "${LOG_FILE}"; }
log_warn()    { echo -e "\e[33m[!]\e[0m $*" | tee -a "${LOG_FILE}"; }
log_error()   { echo -e "\e[31m[✗]\e[0m $*" | tee -a "${LOG_FILE}" >&2; }
log_die()     { log_error "$*"; exit 1; }

if [[ $EUID -eq 0 ]]; then
    log_die "Do not run this script directly as root. Use sudo ./$(basename "$0") instead."
fi

run_verification() {
    log_info "Running OpenSnitch verification checks..."
    local errors=0
    systemctl is-active --quiet opensnitch.service && log_success "Daemon active" || { log_error "Daemon inactive"; ((errors++)); }
    command -v opensnitch-ui &>/dev/null && log_success "UI binary present" || { log_error "UI binary missing"; ((errors++)); }
    [[ -f /etc/systemd/system/opensnitch.service.d/10-hardening.conf ]] && log_success "Daemon hardening active" || { log_error "Hardening missing"; ((errors++)); }
    [[ -f "${HOME_DIR}/.config/systemd/user/opensnitch-ui.service" ]] && log_success "Tray UI user service configured" || { log_error "Tray UI service missing"; ((errors++)); }
    [[ -d /etc/opensnitchd/rules ]] && log_success "Rules directory present" || { log_error "Rules directory missing"; ((errors++)); }
    return ${errors}
}

if [[ "${VERIFY_ONLY}" == "true" ]]; then
    run_verification
    exit $?
fi

log_info "Starting OpenSnitch deployment on Fedora $(rpm -E '%{fedora}')..."

# 1. Install dependencies & PyQt6 stack
log_info "Installing system dependencies and PyQt6 stack..."
sudo dnf install -y python3-pyqt6 python3-protobuf python3-grpcio nftables systemd jq curl wget2

# 2. Protobuf 3.x compatibility fix (#1137)
if [[ "${SKIP_PROTOBUF_FIX}" != "true" ]]; then
    current_proto=$(python3 -c "import google.protobuf; print(google.protobuf.__version__)" 2>/dev/null || echo "none")
    if [[ "${current_proto}" =~ ^4\. ]]; then
        log_warn "Detected protobuf 4.x. Downgrading to compatible 3.x series..."
        sudo pip3 install --upgrade pip setuptools wheel
        sudo pip3 install "protobuf==3.20.3"
    fi
fi

# 3. Download & Install RPMs (Fixed asset naming URL structure)
if [[ -z "${VERSION}" ]]; then
    VERSION=$(curl -sL https://api.github.com/repos/evilsocket/opensnitch/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | tr -d 'v')
fi
base_url="https://github.com/evilsocket/opensnitch/releases/download/v${VERSION}"

log_info "Downloading OpenSnitch v${VERSION}..."
wget -q --show-progress -O "${SCRIPT_DATA_DOWNLOADS}/opensnitch.rpm" "${base_url}/opensnitch-${VERSION}-1.x86_64.rpm"
wget -q --show-progress -O "${SCRIPT_DATA_DOWNLOADS}/opensnitch-ui.rpm" "${base_url}/opensnitch-ui-${VERSION}-1.noarch.rpm"

sudo dnf install -y "${SCRIPT_DATA_DOWNLOADS}/opensnitch.rpm" "${SCRIPT_DATA_DOWNLOADS}/opensnitch-ui.rpm"

# 4. Systemd Daemon Hardening
log_info "Configuring systemd daemon hardening..."
sudo mkdir -p /etc/systemd/system/opensnitch.service.d
sudo tee /etc/systemd/system/opensnitch.service.d/10-hardening.conf > /dev/null <<'EOF'
[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_DAC_READ_SEARCH CAP_KILL CAP_SYS_PTRACE CAP_BPF CAP_PERFMON
AmbientCapabilities=CAP_NET_ADMIN CAP_DAC_READ_SEARCH CAP_KILL CAP_SYS_PTRACE CAP_BPF CAP_PERFMON
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
ProtectClock=yes
ProtectHostname=yes
ProtectKernelLogs=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
ReadWritePaths=/etc/opensnitchd /var/lib/opensnitch /run/opensnitchd
RestrictSUIDSGID=yes
RemoveIPC=yes
LockPersonality=yes
KeyringMode=private
RestrictRealtime=yes
RestrictNamespaces=yes
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
SystemCallArchitectures=native
RestartSec=5
EOF

# 5. Pre-configure Firewalld-style Service Rules for Known Apps
log_info "Pre-configuring service rules for Syncthing, SSH, and DNF..."
sudo mkdir -p /etc/opensnitchd/rules

# Syncthing Rule
sudo tee /etc/opensnitchd/rules/001-allow-syncthing.json > /dev/null <<'EOF'
{
  "name": "001-allow-syncthing",
  "enabled": true,
  "action": "allow",
  "duration": "always",
  "operator": {
    "type": "simple",
    "operand": "process.path",
    "data": "/usr/bin/syncthing"
  }
}
EOF

# SSH Client Rule
sudo tee /etc/opensnitchd/rules/002-allow-ssh.json > /dev/null <<'EOF'
{
  "name": "002-allow-ssh",
  "enabled": true,
  "action": "allow",
  "duration": "always",
  "operator": {
    "type": "simple",
    "operand": "process.path",
    "data": "/usr/bin/ssh"
  }
}
EOF

# DNF Package Manager Rule
sudo tee /etc/opensnitchd/rules/003-allow-dnf.json > /dev/null <<'EOF'
{
  "name": "003-allow-dnf",
  "enabled": true,
  "action": "allow",
  "duration": "always",
  "operator": {
    "type": "simple",
    "operand": "process.path",
    "data": "/usr/bin/dnf"
  }
}
EOF

sudo chmod 640 /etc/opensnitchd/rules/*.json

# 6. User-level Tray UI Service (`opensnitch-ui`)
log_info "Creating user systemd service for system tray UI..."
mkdir -p "${HOME_DIR}/.config/systemd/user"
cat > "${HOME_DIR}/.config/systemd/user/opensnitch-ui.service" <<EOF
[Unit]
Description=OpenSnitch Interactive Firewall UI Tray App
PartOf=graphical-session.target
After=graphical-session.target
Requires=opensnitch.service

[Service]
Type=simple
ExecStart=/usr/bin/opensnitch-ui --socket 127.0.0.1:50051
Restart=on-failure
RestartSec=5
WorkingDirectory=%h
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.config/opensnitch %h/.local/share/opensnitch %h/.cache/opensnitch
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

[Install]
WantedBy=graphical-session.target
EOF

rm -f "${HOME_DIR}/.config/autostart/opensnitch_ui.desktop" 2>/dev/null || true

# 7. Optional Hardcore Mode
if [[ "${HARDCORE_MODE}" == "true" ]]; then
    log_warn "Enabling Hardcore Mode (Default-Deny Policy)..."
    sudo mkdir -p /etc/opensnitchd
    echo '{"default_action": {"name": "deny", "type": "boolean"}, "default_duration": "always"}' | sudo tee /etc/opensnitchd/default-config.json > /dev/null
fi

# 8. Start Services
sudo systemctl daemon-reload
sudo systemctl enable --now opensnitch.service

sudo -u "${REAL_USER}" systemctl --user daemon-reload
sudo -u "${REAL_USER}" systemctl --user enable --now opensnitch-ui.service 2>/dev/null || \
    log_warn "User session not active; tray UI will start automatically on graphical login."

log_success "OpenSnitch setup, sandboxing, and service rules deployment completed."
run_verification