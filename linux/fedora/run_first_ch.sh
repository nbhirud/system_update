#!/usr/bin/env bash
# Fedora post-install bootstrap
# Intended invocation:
#   bash ~/nb/CodeProjects/system_update/linux/fedora/run_first.sh
#
# This script is an orchestrator. It calls the existing scripts in this
# repository, but does not replace their internal implementation.

set -Eeuo pipefail
shopt -s inherit_errexit

###############################################################################
# 1. User-configurable settings
###############################################################################

# These can be edited here or supplied as environment variables before launch.
# Example:
#   NEXTDNS_ID=abcdef TARGET_HOSTNAME=nbAcer bash .../run_first.sh
# Optional examples:
#   SETUP_TYPE=full MEDIA_PC=true CONFERENCING_APPS=true bash .../run_first.sh
#   INSTALL_VIRTUALIZATION=true INSTALL_OPENSSH_SERVER=true bash .../run_first.sh

PC_TYPE="${PC_TYPE:-}"                         # desktop | laptop | server
PRIVACY_LEVEL="${PRIVACY_LEVEL:-}"             # home | portable | paranoid; auto-detected if empty
SETUP_TYPE="${SETUP_TYPE:-light}"              # full | light | minimal

TARGET_HOSTNAME="${TARGET_HOSTNAME:-}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-}"
NEXTDNS_ID="${NEXTDNS_ID:-}"
NEXTDNS_DEVICE_ID="${NEXTDNS_DEVICE_ID:-}"

NEW_ETHERNET_NAME="${NEW_ETHERNET_NAME:-}"
HOME_LAN_SUBNET="${HOME_LAN_SUBNET:-}"         # Optional explicit IPv4/IPv6 CIDR; never guessed

HAS_TORRENT_CLIENT="${HAS_TORRENT_CLIENT:-false}"
HAS_KODI="${HAS_KODI:-false}"
MEDIA_PC="${MEDIA_PC:-false}"                 # Install optional media-oriented applications
CONFERENCING_APPS="${CONFERENCING_APPS:-false}" # Install Zoom and related conferencing tools
INSTALL_AM="${INSTALL_AM:-false}"               # Remote AppMan installer is opt-in
REMOVE_UNWANTED_PACKAGES="${REMOVE_UNWANTED_PACKAGES:-true}"
CLAMAV_DEBUG="${CLAMAV_DEBUG:-0}"

# Optional feature switches. These are deliberately off unless requested.
INSTALL_VIRTUALIZATION="${INSTALL_VIRTUALIZATION:-false}"
INSTALL_OPENSSH_SERVER="${INSTALL_OPENSSH_SERVER:-false}"

###############################################################################
# 2. Constants
###############################################################################

readonly PC_TYPE_DESKTOP="desktop"
readonly PC_TYPE_LAPTOP="laptop"
readonly PC_TYPE_SERVER="server"

readonly PRIVACY_HOME="home"
readonly PRIVACY_PORTABLE="portable"
readonly PRIVACY_PARANOID="paranoid"

readonly SETUP_TYPE_FULL="full"
readonly SETUP_TYPE_LIGHT="light"
readonly SETUP_TYPE_MINIMAL="minimal"

readonly DESKTOP_KDE="kde"
readonly DESKTOP_GNOME="gnome"
readonly DESKTOP_COSMIC="cosmic"
readonly DESKTOP_HEADLESS="headless"

readonly FILENAME_TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"

###############################################################################
# 3. Logging and error handling
###############################################################################

log_info()    { printf '[%s] [INFO]    %s\n' "$(date '+%F %T')" "$*"; }
log_success() { printf '[%s] [SUCCESS] %s\n' "$(date '+%F %T')" "$*"; }
log_warning() { printf '[%s] [WARNING] %s\n' "$(date '+%F %T')" "$*" >&2; }
log_error()   { printf '[%s] [ERROR]   %s\n' "$(date '+%F %T')" "$*" >&2; }

on_error() {
    local status=$?
    local line="${1:-unknown}"
    trap - ERR
    log_error "Setup failed at line ${line} (exit status ${status})."
    log_error "Review the log file and fix the failing operation before rerunning."
    exit "$status"
}
trap 'on_error "$LINENO"' ERR

on_exit() {
    local status=$?
    if (( status == 0 )); then
        log_success "run_first.sh finished successfully."
    else
        log_error "run_first.sh exited with status ${status}."
    fi
}
trap on_exit EXIT

run_phase() {
    local phase="$1"
    shift
    printf '\n%s\n' '=============================================================================='
    log_info "PHASE: ${phase}"
    "$@"
    log_success "PHASE COMPLETE: ${phase}"
}

###############################################################################
# 4. Preflight: user, OS, repository, and required commands
###############################################################################

if (( EUID == 0 )); then
    log_error "Do not run this script as root or with sudo. Run it as your normal user."
    exit 1
fi

readonly REAL_USER="$(id -un)"
readonly REAL_UID="$(id -u)"
readonly REAL_GID="$(id -g)"
readonly REAL_GROUP="$(id -gn)"

HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"
if [[ -z "$HOME_DIR" || ! -d "$HOME_DIR" ]]; then
    log_error "Could not determine a valid home directory for ${REAL_USER}."
    exit 1
fi

# Ensure child scripts resolve user paths against the actual account home.
export HOME="$HOME_DIR"
export USER="$REAL_USER"
export LOGNAME="$REAL_USER"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if command -v git >/dev/null 2>&1 && git -C "$SCRIPT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    SYSUPDATE_CODE_BASE_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
else
    # run_first.sh is expected at <repo>/linux/fedora/run_first.sh
    SYSUPDATE_CODE_BASE_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
fi

if [[ ! -d "$SYSUPDATE_CODE_BASE_DIR/linux" ]]; then
    log_error "Could not identify the system_update repository root: ${SYSUPDATE_CODE_BASE_DIR}"
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    log_error "/etc/os-release is unavailable."
    exit 1
fi
# shellcheck disable=SC1091
source /etc/os-release
DISTRO_ID="${ID:-unknown}"
DISTRO_NAME="${PRETTY_NAME:-${NAME:-unknown}}"

if [[ "$DISTRO_ID" != "fedora" ]]; then
    log_error "This script targets Fedora. Detected: ${DISTRO_NAME} (${DISTRO_ID})."
    exit 1
fi

if ! command -v dnf >/dev/null 2>&1; then
    log_error "DNF was not found."
    exit 1
fi

# This script is written for current Fedora's DNF5 command line.
if ! dnf --version 2>&1 | grep -qi 'dnf5'; then
    log_warning "DNF does not identify itself as DNF5. Some DNF5-specific behavior may differ."
fi

NBDIR="$HOME_DIR/nb"
CODEPROJECTS_DIR="$NBDIR/CodeProjects"
DESKTOP_DIR="$NBDIR/Desktop"
DOCUMENTS_DIR="$NBDIR/Documents"
DOWNLOADS_DIR="$NBDIR/Downloads"
VIDEOS_DIR="$NBDIR/Videos"
PICTURES_DIR="$NBDIR/Pictures"
MUSIC_DIR="$NBDIR/Music"
PUBLIC_DIR="$NBDIR/Public"
TEMPLATES_DIR="$NBDIR/Templates"
PROJECTS_DIR="$NBDIR/Projects"

SCRIPT_DATA_DIR="$NBDIR/nb_script_data"
SCRIPT_BACKUPS_DIR="$SCRIPT_DATA_DIR/backups"
SCRIPT_DOWNLOADS_DIR="$SCRIPT_DATA_DIR/downloads"
SCRIPT_LOGS_DIR="$SCRIPT_DATA_DIR/logs"
SCRIPT_INVENTORY_DIR="$SCRIPT_DATA_DIR/inventory"
SCRIPT_RUN_DIR="$SCRIPT_DATA_DIR/run_first"

install -d -m 700 \
    "$SCRIPT_DATA_DIR" "$SCRIPT_BACKUPS_DIR" "$SCRIPT_DOWNLOADS_DIR" \
    "$SCRIPT_LOGS_DIR" "$SCRIPT_INVENTORY_DIR" "$SCRIPT_RUN_DIR"

LOG_FILE="$SCRIPT_LOGS_DIR/run_first_${FILENAME_TIMESTAMP}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log_info "Starting Fedora bootstrap."
log_info "User: ${REAL_USER}; home: ${HOME_DIR}"
log_info "Repository: ${SYSUPDATE_CODE_BASE_DIR}"
log_info "OS: ${DISTRO_NAME}; kernel: $(uname -r); architecture: $(uname -m)"
log_info "Log: ${LOG_FILE}"

for command_name in sudo rpm dnf systemctl getent awk grep sed findmnt; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        log_error "Required command is missing: ${command_name}"
        exit 1
    fi
done

# Authenticate now, but keep the overall script running as the regular user.
sudo -v

###############################################################################
# 5. Helper functions
###############################################################################

prompt_required() {
    local variable_name="$1"
    local prompt_text="$2"
    local current_value="${!variable_name:-}"

    if [[ -z "$current_value" ]]; then
        if [[ ! -t 0 ]]; then
            log_error "${variable_name} is required. Set it in the script or environment."
            exit 1
        fi
        read -r -p "$prompt_text" current_value
        if [[ -z "$current_value" ]]; then
            log_error "${variable_name} cannot be empty."
            exit 1
        fi
        printf -v "$variable_name" '%s' "$current_value"
    fi
}

backup_path() {
    local source_path="$1"
    [[ -e "$source_path" || -L "$source_path" ]] || return 0

    log_info "Backing up ${source_path}"
    sudo cp -a --parents -- "$source_path" "$BACKUP_DIR"
    sudo chown -R "$REAL_UID:$REAL_GID" "$BACKUP_DIR"
}

run_child_user() {
    local script="$1"
    shift
    if [[ ! -f "$script" ]]; then
        log_error "Required child script not found: ${script}"
        return 1
    fi
    log_info "Running as ${REAL_USER}: ${script}"
    bash "$script" "$@"
}

run_child_root() {
    local script="$1"
    shift
    if [[ ! -f "$script" ]]; then
        log_error "Required child script not found: ${script}"
        return 1
    fi
    log_info "Running with root privileges: ${script}"
    sudo env \
        NB_SCRIPT_BACKUP_DIR="$BACKUP_DIR" \
        NB_SCRIPT_BACKUPS_ROOT="$SCRIPT_BACKUPS_DIR" \
        NB_SCRIPT_DOWNLOAD_DIR="$SCRIPT_DOWNLOADS_DIR" \
        NB_SCRIPT_LOG_DIR="$SCRIPT_LOGS_DIR" \
        NB_SCRIPT_TIMESTAMP="$FILENAME_TIMESTAMP" \
        NB_SCRIPT_REPO_DIR="$SYSUPDATE_CODE_BASE_DIR" \
        bash "$script" "$@"
}

is_true() {
    case "${1,,}" in
        true|1|yes|y) return 0 ;;
        false|0|no|n) return 1 ;;
        *) log_error "Expected true/false value, got: $1"; return 2 ;;
    esac
}

set_mime_if_present() {
    local desktop_id="$1"
    shift
    local found=false
    local search_dir

    for search_dir in "$HOME_DIR/.local/share/applications" /usr/local/share/applications /usr/share/applications; do
        if [[ -f "$search_dir/$desktop_id" ]]; then
            found=true
            break
        fi
    done

    if [[ "$found" == true ]]; then
        local mime_type
        for mime_type in "$@"; do
            xdg-mime default "$desktop_id" "$mime_type"
        done
        log_success "MIME default set: ${desktop_id} -> $*"
    else
        log_warning "Desktop entry ${desktop_id} not found; leaving MIME defaults unchanged for: $*"
    fi
}

###############################################################################
# 6. User choices and machine detection
###############################################################################

prompt_required TARGET_HOSTNAME "Hostname for this machine: "
prompt_required NEXTDNS_ID "NextDNS configuration ID: "

if [[ -z "$NEXTDNS_DEVICE_ID" ]]; then
    NEXTDNS_DEVICE_ID="$TARGET_HOSTNAME"
fi

if [[ ! "$TARGET_HOSTNAME" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
    log_error "Invalid hostname: ${TARGET_HOSTNAME}"
    exit 1
fi

case "$SETUP_TYPE" in
    "$SETUP_TYPE_FULL"|"$SETUP_TYPE_LIGHT"|"$SETUP_TYPE_MINIMAL") ;;
    *) log_error "Invalid SETUP_TYPE: ${SETUP_TYPE}"; exit 1 ;;
esac

case "$HAS_TORRENT_CLIENT" in true|false|TRUE|FALSE|1|0|yes|no|YES|NO) ;;
    *) log_error "HAS_TORRENT_CLIENT must be true or false."; exit 1 ;;
esac
case "$HAS_KODI" in true|false|TRUE|FALSE|1|0|yes|no|YES|NO) ;;
    *) log_error "HAS_KODI must be true or false."; exit 1 ;;
esac
for boolean_setting in HAS_TORRENT_CLIENT HAS_KODI INSTALL_AM REMOVE_UNWANTED_PACKAGES INSTALL_VIRTUALIZATION INSTALL_OPENSSH_SERVER MEDIA_PC CONFERENCING_APPS; do
    case "${!boolean_setting}" in
        true|false|TRUE|FALSE|1|0|yes|no|YES|NO) ;;
        *) log_error "${boolean_setting} must be true or false."; exit 1 ;;
    esac
    # Normalize accepted spellings so child scripts receive predictable values.
    case "${!boolean_setting,,}" in
        true|1|yes) printf -v "$boolean_setting" '%s' true ;;
        false|0|no) printf -v "$boolean_setting" '%s' false ;;
    esac
done

if [[ -z "$PC_TYPE" ]]; then
    pc_type_helper="$SYSUPDATE_CODE_BASE_DIR/linux/commong/get_pc_type.sh"
    if [[ -f "$pc_type_helper" ]]; then
        PC_TYPE="$(bash "$pc_type_helper")"
    fi
fi

case "${PC_TYPE,,}" in
    *desktop*) PC_TYPE="$PC_TYPE_DESKTOP" ;;
    *laptop*) PC_TYPE="$PC_TYPE_LAPTOP" ;;
    *server*|*headless*) PC_TYPE="$PC_TYPE_SERVER" ;;
    *) log_error "PC_TYPE must be desktop, laptop, or server; detected '${PC_TYPE:-empty}'."; exit 1 ;;
esac

if [[ -z "$PRIVACY_LEVEL" ]]; then
    case "$PC_TYPE" in
        "$PC_TYPE_LAPTOP") PRIVACY_LEVEL="$PRIVACY_PORTABLE" ;;
        "$PC_TYPE_DESKTOP"|"$PC_TYPE_SERVER") PRIVACY_LEVEL="$PRIVACY_HOME" ;;
    esac
fi

case "$PRIVACY_LEVEL" in
    "$PRIVACY_HOME"|"$PRIVACY_PORTABLE"|"$PRIVACY_PARANOID") ;;
    *) log_error "PRIVACY_LEVEL must be home, portable, or paranoid."; exit 1 ;;
esac

DESKTOP=""
desktop_helper="$SYSUPDATE_CODE_BASE_DIR/linux/commong/get_desktop_env.sh"
if [[ -f "$desktop_helper" ]]; then
    DESKTOP="$(bash "$desktop_helper")"
fi
if [[ -z "$DESKTOP" ]]; then
    case "${XDG_CURRENT_DESKTOP,,}" in
        *kde*|*plasma*) DESKTOP="$DESKTOP_KDE" ;;
        *gnome*) DESKTOP="$DESKTOP_GNOME" ;;
        *cosmic*) DESKTOP="$DESKTOP_COSMIC" ;;
    esac
fi
case "${DESKTOP,,}" in
    *kde*|*plasma*) DESKTOP="$DESKTOP_KDE" ;;
    *gnome*) DESKTOP="$DESKTOP_GNOME" ;;
    *cosmic*) DESKTOP="$DESKTOP_COSMIC" ;;
    *)
        if [[ "$PC_TYPE" == "$PC_TYPE_SERVER" ]]; then
            DESKTOP="$DESKTOP_HEADLESS"
        else
            log_error "Could not identify a supported desktop environment: '${DESKTOP:-empty}'."
            exit 1
        fi
        ;;
esac

# Validate every child script needed by the selected profile before changing
# repositories or installing packages. This avoids a half-configured machine
# caused by a missing file late in the run.
validate_child_script_inventory() {
    local common="$SYSUPDATE_CODE_BASE_DIR/linux/common"
    local security="$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level"
    local -a required=(
        "$security/dns.sh"
        "$security/clamav.sh"
        "$security/hosts.sh"
        "$security/firewalld.sh"
        "$common/zsh.sh"
        "$common/omz.sh"
        "$common/cli_tools.sh"
        "$common/starship.sh"
        "$common/atuin.sh"
    )

    if [[ "$DESKTOP" != "$DESKTOP_HEADLESS" && "$SETUP_TYPE" != "$SETUP_TYPE_MINIMAL" ]]; then
        required+=(
            "$common/vscodium.sh" "$common/librewolf_browser.sh"
            "$common/brave_browser.sh" "$common/tor_browser.sh"
            "$common/fonts.sh" "$common/alacritty_orig.sh"
            "$common/bleachbit.sh" "$common/syncthing.sh"
            "$common/avahi.sh" "$common/mpv.sh"
            "$security/proton_ag.sh"
        )
    elif [[ "$DESKTOP" == "$DESKTOP_HEADLESS" ]]; then
        required+=("$common/syncthing.sh" "$common/avahi.sh")
    fi

    if [[ -n "$GIT_USER_EMAIL" ]]; then
        required+=("$common/git.sh")
    fi

    if [[ "$SETUP_TYPE" == "$SETUP_TYPE_FULL" ]]; then
        required+=(
            "$common/bash.sh" "$common/aws.sh" "$common/docker.sh"
            "$common/neovim_lazyvim.sh" "$security/i2p.sh"
            "$common/tmux_zellij.sh" "$common/yazi.sh"
        )
        if [[ "$DESKTOP" != "$DESKTOP_HEADLESS" ]]; then
            required+=("$common/jetbrains_toolbox.sh" "$common/mullvad_browser.sh")
            [[ "$DESKTOP" != "$DESKTOP_GNOME" ]] || required+=("$common/gsconnect_kde_connect.sh")
        fi
    fi

    if is_true "$CONFERENCING_APPS" && [[ "$DESKTOP" != "$DESKTOP_HEADLESS" ]]; then
        required+=("$common/zoom.sh")
    fi

    local missing=0 script
    for script in "${required[@]}"; do
        if [[ ! -f "$script" ]]; then
            log_error "Required child script is missing: ${script}"
            missing=1
        fi
    done
    (( missing == 0 )) || return 1
    log_success "All child scripts required by this setup profile are present."
}

validate_child_script_inventory

# Identify the currently active wired profile. No undefined CURRENT_ETHERNET_NAME.
CURRENT_ETHERNET_NAME=""
if command -v nmcli >/dev/null 2>&1; then
    CURRENT_ETHERNET_NAME="$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null \
        | awk -F: '$2 == "802-3-ethernet" {sub(/^[^:]*:/, ""); print; exit}')"
fi
IS_ETHERNET=false
[[ -n "$CURRENT_ETHERNET_NAME" ]] && IS_ETHERNET=true

# Derive a LAN subnet only when exactly one active physical NetworkManager
# interface (Wi-Fi or Ethernet) can be identified. Never assume 192.168.1.0/24.
if [[ -z "$HOME_LAN_SUBNET" && "$PRIVACY_LEVEL" == "$PRIVACY_HOME" && "$PC_TYPE" != "$PC_TYPE_LAPTOP" ]] \
    && command -v python3 >/dev/null 2>&1 && command -v nmcli >/dev/null 2>&1; then
    HOME_LAN_SUBNET="$(python3 - <<'PY'
import ipaddress
import subprocess

try:
    raw = subprocess.check_output(
        ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device", "status"],
        text=True, stderr=subprocess.DEVNULL
    )
    active = []
    for line in raw.splitlines():
        fields = line.split(":")
        if len(fields) >= 3:
            dev, kind, state = fields[0], fields[1], fields[2]
            if state == "connected" and kind in {"wifi", "ethernet"}:
                active.append(dev)
    if len(active) == 1:
        addr = subprocess.check_output(
            ["ip", "-o", "-4", "addr", "show", "dev", active[0]],
            text=True, stderr=subprocess.DEVNULL
        )
        for field in addr.split():
            if "/" in field:
                try:
                    network = ipaddress.ip_interface(field).network
                    if not network.is_loopback and not network.is_link_local:
                        print(network)
                        raise SystemExit(0)
                except ValueError:
                    pass
except Exception:
    pass
PY
)"
fi

if [[ -n "$HOME_LAN_SUBNET" ]]; then
    if ! python3 -c 'import ipaddress,sys; ipaddress.ip_network(sys.argv[1], strict=False)' "$HOME_LAN_SUBNET" 2>/dev/null; then
        log_error "HOME_LAN_SUBNET is not a valid IPv4/IPv6 CIDR: ${HOME_LAN_SUBNET}"
        exit 1
    fi
else
    log_warning "Could not safely identify one unambiguous physical LAN subnet. No guessed trusted subnet will be used."
    log_warning "If your firewalld script requires a LAN subnet, set HOME_LAN_SUBNET explicitly before running."
fi

log_info "Machine type: ${PC_TYPE}; privacy profile: ${PRIVACY_LEVEL}; setup: ${SETUP_TYPE}"
log_info "Optional features: MEDIA_PC=${MEDIA_PC}; CONFERENCING_APPS=${CONFERENCING_APPS}; virtualization=${INSTALL_VIRTUALIZATION}; SSH=${INSTALL_OPENSSH_SERVER}"
log_info "Desktop: ${DESKTOP}; active Ethernet profile: ${CURRENT_ETHERNET_NAME:-none}"
log_info "Hostname: ${TARGET_HOSTNAME}; NextDNS device label: ${NEXTDNS_DEVICE_ID}"
log_info "Home LAN subnet: ${HOME_LAN_SUBNET:-not detected}"

###############################################################################
# 7. Directories, backups, and inventory
###############################################################################

create_user_directories() {
    install -d \
        "$NBDIR" "$CODEPROJECTS_DIR" \
        "$DESKTOP_DIR" "$DOCUMENTS_DIR" "$DOWNLOADS_DIR" "$VIDEOS_DIR" \
        "$PICTURES_DIR" "$MUSIC_DIR" "$PUBLIC_DIR" "$TEMPLATES_DIR" "$PROJECTS_DIR" \
        "$SCRIPT_DATA_DIR" "$SCRIPT_BACKUPS_DIR" "$SCRIPT_DOWNLOADS_DIR" \
        "$SCRIPT_LOGS_DIR" "$SCRIPT_INVENTORY_DIR" "$SCRIPT_RUN_DIR"
}

create_backup_directory() {
    BACKUP_DIR="$SCRIPT_BACKUPS_DIR/run_first_${FILENAME_TIMESTAMP}"
    install -d -m 700 "$BACKUP_DIR"
    log_info "Configuration backups will be stored in ${BACKUP_DIR}"
    # Export a consistent contract for child scripts. Existing children may
    # adopt these variables without needing hard-coded per-machine paths.
    export NB_SCRIPT_BACKUP_DIR="$BACKUP_DIR"
    export NB_SCRIPT_BACKUPS_ROOT="$SCRIPT_BACKUPS_DIR"
    export NB_SCRIPT_DOWNLOAD_DIR="$SCRIPT_DOWNLOADS_DIR"
    export NB_SCRIPT_LOG_DIR="$SCRIPT_LOGS_DIR"
    export NB_SCRIPT_TIMESTAMP="$FILENAME_TIMESTAMP"
    export NB_SCRIPT_REPO_DIR="$SYSUPDATE_CODE_BASE_DIR"
}

collect_inventory() {
    local inventory_file="$SCRIPT_INVENTORY_DIR/system_${FILENAME_TIMESTAMP}.txt"
    {
        echo "Collected: $(date --iso-8601=seconds)"
        echo "User: ${REAL_USER}"
        echo "Fedora: ${DISTRO_NAME}"
        echo "Kernel: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo
        echo '### CPU'
        lscpu 2>&1 || true
        echo
        echo '### Memory'
        free -h 2>&1 || true
        echo
        echo '### Block devices'
        lsblk -o NAME,TYPE,SIZE,FSTYPE,FSVER,LABEL,UUID,MOUNTPOINTS 2>&1 || true
        echo
        echo '### Mounts'
        findmnt 2>&1 || true
        echo
        echo '### PCI devices and drivers'
        lspci -nnk 2>&1 || true
        echo
        echo '### USB devices'
        lsusb 2>&1 || true
        echo
        echo '### Secure Boot'
        mokutil --sb-state 2>&1 || true
        echo
        echo '### SELinux'
        getenforce 2>&1 || true
        sestatus 2>&1 || true
        echo
        echo '### NetworkManager devices'
        nmcli device status 2>&1 || true
        echo
        echo '### Failed systemd units'
        systemctl --failed --no-pager 2>&1 || true
    } > "$inventory_file"
    chmod 600 "$inventory_file"
    log_success "System inventory saved: ${inventory_file}"
}

run_phase "Create user directories" create_user_directories
run_phase "Create backup location" create_backup_directory
run_phase "Collect pre-change system inventory" collect_inventory

###############################################################################
# 8. Recovery and safety checks
###############################################################################

check_recovery_state() {
    local root_fstype
    root_fstype="$(findmnt -n -o FSTYPE / || true)"

    if [[ "$root_fstype" == "btrfs" ]]; then
        log_info "Root filesystem is Btrfs. Inspecting existing Snapper configuration."
        if rpm -q snapper >/dev/null 2>&1 && sudo snapper -c root get-config >/dev/null 2>&1; then
            log_info "Existing Snapper root configuration found; creating a pre-bootstrap snapshot."
            sudo snapper -c root create --description "Pre-run_first baseline ${FILENAME_TIMESTAMP}"
        else
            log_warning "Btrfs detected, but no working Snapper root configuration exists."
            log_warning "Not creating one automatically: Fedora subvolume layouts vary, and an incorrect Snapper config can be misleading."
        fi
        sudo btrfs filesystem usage / 2>&1 || true
    else
        log_info "Root filesystem is ${root_fstype:-unknown}; no Btrfs snapshot action is applicable."
    fi

    local selinux_state
    selinux_state="$(getenforce 2>/dev/null || printf 'unknown')"
    if [[ "$selinux_state" != "Enforcing" ]]; then
        log_warning "SELinux is ${selinux_state}, not Enforcing. Investigate before treating this machine as hardened."
    else
        log_success "SELinux is Enforcing."
    fi
}

backup_existing_configuration() {
    backup_path /etc/hostname
    backup_path /etc/dnf/dnf.conf
    backup_path /etc/NetworkManager/conf.d/00-macrandomize.conf
    backup_path "$HOME_DIR/.config/mimeapps.list"
    backup_path "$HOME_DIR/.zshrc"
    backup_path "$HOME_DIR/.bashrc"
    backup_path "$HOME_DIR/.gitconfig"
    backup_path "$HOME_DIR/.config/starship.toml"
    backup_path "$HOME_DIR/.config/atuin/config.toml"
    backup_path "$HOME_DIR/.config/mpv/mpv.conf"
    backup_path "$HOME_DIR/.config/VSCodium/User/settings.json"
    backup_path "$HOME_DIR/.config/zsh/aliases.zsh"
    # Do not back up entire browser profiles: they can be very large and
    # contain credentials, cookies, and other sensitive session data.
}

run_phase "Recovery and security pre-checks" check_recovery_state
run_phase "Back up configuration files before modification" backup_existing_configuration

###############################################################################
# 9. Hostname, NetworkManager, and DNF configuration
###############################################################################

configure_hostname_and_network() {
    sudo hostnamectl set-hostname "$TARGET_HOSTNAME"

    if [[ "$IS_ETHERNET" == true && -n "$NEW_ETHERNET_NAME" ]]; then
        log_info "Renaming active Ethernet profile '${CURRENT_ETHERNET_NAME}' to '${NEW_ETHERNET_NAME}'."
        nmcli connection modify "$CURRENT_ETHERNET_NAME" connection.id "$NEW_ETHERNET_NAME"
        CURRENT_ETHERNET_NAME="$NEW_ETHERNET_NAME"
    fi

    # Scan MAC randomization is already the NetworkManager default on current
    # releases; state it explicitly. Stable per-connection Wi-Fi MACs avoid
    # random changes at every reconnect. Do not randomize Ethernet globally.
    sudo install -d -m 755 /etc/NetworkManager/conf.d
    sudo tee /etc/NetworkManager/conf.d/00-macrandomize.conf >/dev/null <<'NETWORKMANAGER_CONF'
[device]
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=stable
NETWORKMANAGER_CONF
    sudo chmod 644 /etc/NetworkManager/conf.d/00-macrandomize.conf

    # Reload configuration without restarting NetworkManager and forcibly
    # disconnecting the current network. Existing profiles pick up changes
    # when they are next activated.
    nmcli general reload conf || log_warning "NetworkManager config reload failed; new defaults may require a later restart."
}

configure_host_and_package_manager() {
    configure_hostname_and_network
    configure_dnf
}

configure_dnf() {
    # config-manager is shipped by dnf5-plugins and is not guaranteed to be
    # present on minimal Fedora installs. Install it before using setopt.
    if ! sudo dnf config-manager --help >/dev/null 2>&1; then
        sudo dnf install -y dnf5-plugins
    fi

    # DNF5 config-manager setopt updates only this option in the main config;
    # it does not replace the file or erase unrelated Fedora/user settings.
    sudo dnf config-manager setopt max_parallel_downloads=5
    log_success "Configured DNF5 max_parallel_downloads=5 while preserving other settings."
}

run_phase "Hostname, NetworkManager, and DNF configuration" configure_host_and_package_manager

###############################################################################
# 10. Repositories and system update
###############################################################################

configure_repositories_and_update() {
    local releasever
    releasever="$(rpm -E '%fedora')"

    log_info "Enabling RPM Fusion for Fedora ${releasever}."
    sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${releasever}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${releasever}.noarch.rpm"

    sudo dnf makecache --refresh
    sudo dnf upgrade --refresh -y

    log_info "Enabled DNF repositories:"
    dnf repolist --enabled || true
}

run_phase "Enable repositories and update Fedora" configure_repositories_and_update

###############################################################################
# 11. Base packages, diagnostics, and optional package removal
###############################################################################

install_base_packages() {
    local -a base_packages=(
        git flatpak curl wget jq fzf fastfetch gh
        fwupd smartmontools nvme-cli lm_sensors pciutils usbutils libva-utils
        policycoreutils policycoreutils-python-utils
    )

    sudo dnf install -y "${base_packages[@]}"

    # These tools are diagnostic utilities. Their installation does not
    # enable unnecessary daemons or change GPU drivers automatically.
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files fstrim.timer --no-legend 2>/dev/null | grep -q fstrim.timer; then
        sudo systemctl enable --now fstrim.timer
    fi

    if is_true "$REMOVE_UNWANTED_PACKAGES"; then
        local -a remove_candidates=(totem yelp gnome-tour gnome-connections firefox)
        local -a installed_packages=()
        local package_name

        for package_name in "${remove_candidates[@]}"; do
            if rpm -q "$package_name" >/dev/null 2>&1; then
                installed_packages+=("$package_name")
            fi
        done

        if ((${#installed_packages[@]})); then
            log_info "Removing selected preinstalled applications: ${installed_packages[*]}"
            sudo dnf remove -y "${installed_packages[@]}"
        else
            log_info "No selected preinstalled applications need removal."
        fi
    fi

    # Do not delete ~/.mozilla, browser profiles, or /opt/firefox blindly.
    # Those locations may contain user data or manually managed installations.
}

run_phase "Install base and diagnostic packages" install_base_packages

###############################################################################
# 12. Multimedia and hardware acceleration diagnostics
###############################################################################

configure_multimedia() {
    # Full FFmpeg from RPM Fusion, when Fedora's restricted build is installed.
    if rpm -q ffmpeg-free >/dev/null 2>&1; then
        sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
    elif ! rpm -q ffmpeg >/dev/null 2>&1; then
        sudo dnf install -y ffmpeg
    fi

    # Install the multimedia group once. A group-upgrade command would not
    # reliably install missing group members on a fresh Fedora installation.
    sudo dnf group install -y multimedia \
        --setopt=install_weak_deps=False \
        --exclude=PackageKit-gstreamer-plugin

    sudo dnf install -y gstreamer1-plugin-openh264 mozilla-openh264

    log_info "Detected graphics hardware (driver selection is intentionally not automatic):"
    lspci -nnk | grep -A3 -Ei 'VGA compatible controller|3D controller|Display controller' || true
    log_info "VA-API diagnostic command: vainfo"
    log_info "Do not infer working hardware decoding from package installation alone."
}

run_phase "Multimedia setup and GPU diagnostics" configure_multimedia

###############################################################################
# 13. Flatpak remote and application installation
###############################################################################

install_flatpak_apps() {
    local app_id

    if [[ "$DESKTOP" == "$DESKTOP_HEADLESS" || "$SETUP_TYPE" == "$SETUP_TYPE_MINIMAL" ]]; then
        log_info "Headless/minimal profile selected; skipping desktop Flatpak applications."
        return 0
    fi

    local -a base_flatpaks=(
        org.signal.Signal
        com.github.tchx84.Flatseal
        it.mijorus.gearlever
    )
    # Application manifest: keep communication/productivity applications
    # separate from optional media-PC applications. IDs are centralized here
    # so they can be audited without hunting through installation commands.
    local -a full_flatpaks=(
        com.rtosta.zapzap
        org.telegram.desktop
        chat.simplex.simplex
        network.loki.Session
        im.riot.Riot
        org.localsend.localsend_app
        com.super_productivity.SuperProductivity
        md.obsidian.Obsidian
    )
    local -a media_flatpaks=(
        io.freetubeapp.FreeTube
        dev.fredol.open-tv
        com.spotify.Client
        app.grayjay.Grayjay
        app.organicmaps.desktop
    )

    # Keep this setup's Flatpak applications in the invoking user's scope.
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

    for app_id in "${base_flatpaks[@]}"; do
        flatpak install --user --assumeyes flathub "$app_id"
    done

    if [[ "$SETUP_TYPE" == "$SETUP_TYPE_FULL" ]]; then
        for app_id in "${full_flatpaks[@]}"; do
            flatpak install --user --assumeyes flathub "$app_id"
        done
        if is_true "$MEDIA_PC"; then
            for app_id in "${media_flatpaks[@]}"; do
                flatpak install --user --assumeyes flathub "$app_id"
            done
        else
            log_info "MEDIA_PC=false; skipping optional media-focused Flatpaks."
        fi
    fi

    case "$DESKTOP" in
        "$DESKTOP_GNOME")
            flatpak install --user --assumeyes flathub com.mattjakeman.ExtensionManager
            if [[ "$SETUP_TYPE" == "$SETUP_TYPE_FULL" ]]; then
                flatpak install --user --assumeyes flathub org.gnome.Podcasts de.haeckerfelix.Shortwave
            fi
            ;;
        "$DESKTOP_KDE")
            if [[ "$SETUP_TYPE" == "$SETUP_TYPE_FULL" ]]; then
                flatpak install --user --assumeyes flathub io.github.amit9838.mousam
            fi
            ;;
    esac

    # User-scoped overrides must be run as the user, without sudo.
    case "$DESKTOP" in
        "$DESKTOP_GNOME"|"$DESKTOP_COSMIC")
            flatpak override --user --env=SIGNAL_PASSWORD_STORE=gnome-libsecret org.signal.Signal
            ;;
        "$DESKTOP_KDE")
            flatpak override --user --env=SIGNAL_PASSWORD_STORE=kwallet6 org.signal.Signal
            if [[ "$SETUP_TYPE" == "$SETUP_TYPE_FULL" ]]; then
                flatpak override --user im.riot.Riot \
                    --talk-name=org.kde.kwalletd6 \
                    --talk-name=org.freedesktop.secrets
            fi
            ;;
    esac

    # Deliberately do not grant ZapZap unrestricted home-directory access.
    # If drag-and-drop needs access, grant only the specific folder required.
    log_info "User Flatpak applications:"
    flatpak list --user --app || true
    log_info "User Flatpak overrides:"
    flatpak override --user --show || true
}

run_phase "Install and configure user-scoped Flatpak applications" install_flatpak_apps

###############################################################################
# 14. RPM applications and desktop-specific packages
###############################################################################

install_desktop_packages() {
    local -a common_packages=(ksystemlog htop keepassxc vlc)

    if [[ "$DESKTOP" == "$DESKTOP_HEADLESS" ]]; then
        log_info "Headless server detected; skipping desktop-only RPM packages."
        return 0
    fi

    if [[ "$SETUP_TYPE" != "$SETUP_TYPE_MINIMAL" ]]; then
        sudo dnf install -y "${common_packages[@]}"
    fi

    if is_true "$HAS_TORRENT_CLIENT"; then
        sudo dnf install -y qbittorrent
    fi
    if is_true "$HAS_KODI"; then
        sudo dnf install -y kodi
    fi

    case "$DESKTOP" in
        "$DESKTOP_GNOME")
            if [[ "$SETUP_TYPE" != "$SETUP_TYPE_MINIMAL" ]]; then
                sudo dnf install -y gnome-tweaks
            fi
            if [[ "$SETUP_TYPE" == "$SETUP_TYPE_FULL" ]]; then
                sudo dnf install -y gparted
            fi
            ;;
        "$DESKTOP_KDE")
            if [[ "$SETUP_TYPE" != "$SETUP_TYPE_MINIMAL" ]]; then
                sudo dnf install -y kde-gtk-config plasma-browser-integration kasts
            fi
            log_info "KDE provides Partition Manager and Akregator on standard installations; Kasts is installed explicitly."
            ;;
        "$DESKTOP_COSMIC")
            log_warning "COSMIC is detected, but this script has no dedicated COSMIC desktop-tweaks phase yet."
            ;;
    esac
}

run_phase "Install desktop RPM applications" install_desktop_packages

###############################################################################
# 15. Optional AppMan/AM installer (explicit opt-in)
###############################################################################

install_appman_if_requested() {
    if ! is_true "$INSTALL_AM"; then
        log_info "Skipping AppMan/AM. Set INSTALL_AM=true to request its installer."
        return 0
    fi

    local installer="$SCRIPT_DOWNLOADS_DIR/AM-INSTALLER"
    log_warning "AppMan's installer will be downloaded from its moving main branch and executed."
    log_warning "Review the installer yourself if you require a pinned, independently verified release."

    if [[ -t 0 ]]; then
        local answer
        read -r -p "Download and execute the current AppMan installer? [y/N] " answer
        [[ "$answer" =~ ^[Yy]$ ]] || { log_info "AppMan installation cancelled."; return 0; }
    else
        log_error "INSTALL_AM=true requires an interactive confirmation in this script."
        return 1
    fi

    curl --fail --location --silent --show-error \
        --output "$installer" \
        https://raw.githubusercontent.com/ivan-hc/AM/main/AM-INSTALLER
    chmod 700 "$installer"
    bash -n "$installer"
    sha256sum "$installer" | tee "${installer}.sha256"
    bash "$installer"
    log_info "AppMan installer and checksum retained in ${SCRIPT_DOWNLOADS_DIR} for audit."
}

run_phase "Optional AppMan installation" install_appman_if_requested

###############################################################################
# 16. User directories, hostname-dependent settings, and optional features
###############################################################################

configure_user_desktop_basics() {
    if [[ "$DESKTOP" == "$DESKTOP_HEADLESS" ]]; then
        log_info "Headless server detected; skipping graphical desktop settings."
        return 0
    fi

    if command -v xdg-user-dirs-update >/dev/null 2>&1; then
        xdg-user-dirs-update --set DOWNLOAD "$DOWNLOADS_DIR"
    fi

    if [[ "$DESKTOP" == "$DESKTOP_GNOME" ]] && command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
    fi
}

install_optional_system_features() {
    if is_true "$INSTALL_VIRTUALIZATION"; then
        sudo dnf install -y @virtualization virt-manager virt-viewer
        # libvirtd is the conventional service on current Fedora installations.
        if systemctl list-unit-files libvirtd.service --no-legend 2>/dev/null | grep -q libvirtd.service; then
            sudo systemctl enable --now libvirtd
        fi
    fi

    if is_true "$INSTALL_OPENSSH_SERVER"; then
        sudo dnf install -y openssh-server
        sudo systemctl enable --now sshd
        log_warning "sshd is enabled. Review /etc/ssh/sshd_config and firewall exposure before using it on untrusted networks."
    fi
}

run_phase "Configure user desktop basics" configure_user_desktop_basics
run_phase "Install explicitly requested optional system features" install_optional_system_features

###############################################################################
# 17. Existing user and security setup scripts
###############################################################################

configure_zsh_productivity() {
    local zshrc="$HOME_DIR/.zshrc"
    local alias_dir="$HOME_DIR/.config/zsh"
    local alias_file="$alias_dir/aliases.zsh"

    install -d -m 700 "$alias_dir"
    if [[ ! -e "$alias_file" ]]; then
        cat > "$alias_file" <<'ALIASES'
# Small, interactive-only convenience aliases managed by run_first.sh.
# Keep machine-specific or project-specific aliases in a separate file.
alias ll='ls -alF --group-directories-first'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias dfh='df -hT'
alias freeh='free -h'
alias ports='ss -tulpn'
alias jfailed='systemctl --failed --no-pager'
ALIASES
        chmod 600 "$alias_file"
    else
        log_info "Preserving existing Zsh aliases file: ${alias_file}"
    fi

    if [[ -f "$zshrc" ]]; then
        local source_line='[[ -r "$HOME/.config/zsh/aliases.zsh" ]] && source "$HOME/.config/zsh/aliases.zsh"'
        if ! grep -Fq '.config/zsh/aliases.zsh' "$zshrc"; then
            printf '\n# User aliases maintained by run_first.sh.\n%s\n' "$source_line" >> "$zshrc"
        fi

        # fzf's maintained shell integration provides key bindings and
        # completion. Add it only when this installed version supports --zsh.
        if command -v fzf >/dev/null 2>&1 && fzf --zsh >/dev/null 2>&1; then
            if ! grep -Fq 'fzf --zsh' "$zshrc"; then
                printf '\n# fzf Zsh key bindings and completion.\nsource <(fzf --zsh)\n' >> "$zshrc"
            fi
        else
            log_warning "Installed fzf does not expose 'fzf --zsh'; leaving shell integration unchanged."
        fi
    else
        log_warning "${zshrc} was not created by the Zsh setup script; aliases are installed but not sourced automatically."
    fi
}

run_existing_user_setup() {
    local base="$SYSUPDATE_CODE_BASE_DIR/linux/common"

    if [[ "$DESKTOP" == "$DESKTOP_HEADLESS" || "$SETUP_TYPE" == "$SETUP_TYPE_MINIMAL" ]]; then
        log_info "Headless/minimal profile: installing only the core shell and CLI user environment."
        run_child_user "$base/zsh.sh"
        run_child_user "$base/omz.sh"
        run_child_user "$base/cli_tools.sh"
        run_child_user "$base/starship.sh"
        run_child_user "$base/atuin.sh"
        configure_zsh_productivity
        if [[ -n "$GIT_USER_EMAIL" ]]; then
            run_child_user "$base/git.sh" "$GIT_USER_EMAIL"
        else
            log_warning "GIT_USER_EMAIL is empty; skipping Git identity configuration to avoid setting an empty email."
        fi
        if [[ "$DESKTOP" == "$DESKTOP_HEADLESS" ]]; then
            run_child_user "$base/syncthing.sh"
            run_child_user "$base/avahi.sh"
        fi
        return 0
    fi

    run_child_user "$base/vscodium.sh"
    run_child_user "$base/librewolf_browser.sh"
    run_child_user "$base/brave_browser.sh"
    if command -v brave-browser >/dev/null 2>&1; then
        export CHROME_EXECUTABLE="$(command -v brave-browser)"
    else
        unset CHROME_EXECUTABLE || true
    fi
    run_child_user "$base/tor_browser.sh"
    run_child_user "$base/fonts.sh"

    # These scripts configure the invoking user's environment. They must not
    # be launched as root; any required privileged package operation belongs
    # inside the child script via sudo.
    run_child_user "$base/zsh.sh"
    run_child_user "$base/omz.sh"
    run_child_user "$base/cli_tools.sh"
    run_child_user "$base/starship.sh"
    run_child_user "$base/atuin.sh"
    configure_zsh_productivity

    run_child_user "$base/alacritty_orig.sh"
    run_child_user "$base/bleachbit.sh"
    if [[ -n "$GIT_USER_EMAIL" ]]; then
        run_child_user "$base/git.sh" "$GIT_USER_EMAIL"
    else
        log_warning "GIT_USER_EMAIL is empty; skipping Git identity configuration to avoid setting an empty email."
    fi
    run_child_user "$base/syncthing.sh"
    run_child_user "$base/avahi.sh"
    run_child_user "$base/mpv.sh"
}

run_existing_security_setup() {
    local security="$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level"

    # DNS and firewall scripts configure system state and are run with sudo.
    run_child_root "$security/dns.sh" "$NEXTDNS_ID" "$NEXTDNS_DEVICE_ID"

    if [[ "$DESKTOP" != "$DESKTOP_HEADLESS" && "$SETUP_TYPE" != "$SETUP_TYPE_MINIMAL" ]]; then
        run_child_user "$security/proton_ag.sh" \
            --setup-type "$SETUP_TYPE" \
            --desktop "$DESKTOP"
    fi

    if [[ ! -f "$security/clamav.sh" ]]; then
        log_error "Required child script not found: $security/clamav.sh"
        return 1
    fi
    log_info "Running ClamAV setup with root privileges."
    sudo env \
        DEBUG="$CLAMAV_DEBUG" \
        NB_SCRIPT_BACKUP_DIR="$BACKUP_DIR" \
        NB_SCRIPT_BACKUPS_ROOT="$SCRIPT_BACKUPS_DIR" \
        NB_SCRIPT_DOWNLOAD_DIR="$SCRIPT_DOWNLOADS_DIR" \
        NB_SCRIPT_LOG_DIR="$SCRIPT_LOGS_DIR" \
        NB_SCRIPT_TIMESTAMP="$FILENAME_TIMESTAMP" \
        NB_SCRIPT_REPO_DIR="$SYSUPDATE_CODE_BASE_DIR" \
        bash "$security/clamav.sh" \
        --pc-type="$PC_TYPE" \
        --real-user="$REAL_USER" \
        --torrent-client="$HAS_TORRENT_CLIENT" \
        --kodi="$HAS_KODI" \
        --backup-dir="$SCRIPT_BACKUPS_DIR" \
        --timestamp="$FILENAME_TIMESTAMP"

    run_child_user "$security/hosts.sh"

    if is_true "$CONFERENCING_APPS"; then
        if [[ "$DESKTOP" != "$DESKTOP_HEADLESS" ]]; then
            run_child_user "$SYSUPDATE_CODE_BASE_DIR/linux/common/zoom.sh"
        fi
    else
        log_info "CONFERENCING_APPS=false; skipping Zoom installation."
    fi

    if [[ "$SETUP_TYPE" == "$SETUP_TYPE_FULL" ]]; then
        local common="$SYSUPDATE_CODE_BASE_DIR/linux/common"
        run_child_user "$common/bash.sh"
        run_child_user "$common/aws.sh"
        run_child_user "$common/docker.sh"
        run_child_user "$common/neovim_lazyvim.sh"
        run_child_user "$security/i2p.sh"
        run_child_user "$common/tmux_zellij.sh"
        run_child_user "$common/yazi.sh"

        if [[ "$DESKTOP" != "$DESKTOP_HEADLESS" ]]; then
            run_child_user "$common/jetbrains_toolbox.sh"
            # Mullvad Browser setup was previously ordered after ClamAV.
            run_child_user "$common/mullvad_browser.sh"

            if [[ "$DESKTOP" == "$DESKTOP_GNOME" ]]; then
                run_child_user "$common/gsconnect_kde_connect.sh"
            fi
        fi
    fi
}

run_phase "Configure user applications and development environment" run_existing_user_setup
run_phase "Configure DNS, privacy, antivirus, and optional full-profile tools" run_existing_security_setup

###############################################################################
# 18. Firewall: deliberately late, after application installation
###############################################################################

configure_firewall() {
    local firewall_script="$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/firewalld.sh"

    if [[ ! -f "$firewall_script" ]]; then
        log_error "Firewall setup script not found: ${firewall_script}"
        return 1
    fi

    if [[ -z "$HOME_LAN_SUBNET" ]]; then
        log_warning "HOME_LAN_SUBNET is empty. The firewall child script must treat it as 'no trusted LAN subnet', not as a broad allow rule."
    fi

    run_child_root "$firewall_script" \
        --filename-timestamp "$FILENAME_TIMESTAMP" \
        --script-backups-dir "$SCRIPT_BACKUPS_DIR" \
        --sysupdate-code-base-dir "$SYSUPDATE_CODE_BASE_DIR" \
        --home-lan-subnet "$HOME_LAN_SUBNET" \
        --privacy-level "$PRIVACY_LEVEL" \
        --desktop "$DESKTOP" \
        --home-dir "$HOME_DIR" \
        --real-user "$REAL_USER"
}

run_phase "Configure firewalld after application installation" configure_firewall

###############################################################################
# 19. MIME defaults
###############################################################################

configure_mime_defaults() {
    if [[ "$DESKTOP" == "$DESKTOP_HEADLESS" ]]; then
        log_info "Headless server detected; skipping MIME defaults."
        return 0
    fi

    command -v xdg-mime >/dev/null 2>&1 || {
        log_warning "xdg-mime is unavailable; skipping MIME configuration."
        return 0
    }

    # Desktop-file IDs are checked before use. A package may use a different
    # ID or may not be installed in this setup profile.
    set_mime_if_present codium.desktop text/plain

    local browser_id
    for browser_id in brave-browser.desktop com.brave.Browser.desktop; do
        if [[ -f "$HOME_DIR/.local/share/applications/$browser_id" || -f "/usr/local/share/applications/$browser_id" || -f "/usr/share/applications/$browser_id" ]]; then
            set_mime_if_present "$browser_id" x-scheme-handler/http x-scheme-handler/https x-scheme-handler/about
            break
        fi
    done

    set_mime_if_present mpv.desktop \
        video/mp4 video/x-matroska video/webm video/quicktime \
        video/x-msvideo video/mpeg video/ogg video/3gpp video/x-flv \
        audio/mpeg audio/mp4 audio/ogg audio/flac audio/x-wav audio/x-matroska
    set_mime_if_present org.kde.okular.desktop application/pdf

    # Do not force a mail client or terminal handler: this setup does not
    # guarantee one particular installed application on every profile, and
    # terminal selection is desktop-specific rather than a reliable MIME map.
}

run_phase "Configure verified MIME defaults" configure_mime_defaults

###############################################################################
# 20. Final updates and verification
###############################################################################

final_updates() {
    # RPM updates were applied after repository configuration. Flatpak apps
    # were installed afterward, so update their user installation now.
    flatpak update --user --assumeyes

    if ! sudo dnf check; then
        log_warning "dnf check reported dependency or package database issues. Review before rebooting."
    fi
}

verify_system() {
    local verification_file="$SCRIPT_INVENTORY_DIR/verification_${FILENAME_TIMESTAMP}.txt"

    {
        echo "Verification collected: $(date --iso-8601=seconds)"
        echo "Fedora: ${DISTRO_NAME}"
        echo "Kernel: $(uname -r)"
        echo
        echo '### DNF repositories'
        dnf repolist --enabled 2>&1 || true
        echo
        echo '### SELinux'
        getenforce 2>&1 || true
        sestatus 2>&1 || true
        echo
        echo '### firewalld'
        systemctl is-enabled firewalld 2>&1 || true
        systemctl is-active firewalld 2>&1 || true
        sudo firewall-cmd --state 2>&1 || true
        sudo firewall-cmd --get-active-zones 2>&1 || true
        sudo firewall-cmd --list-all-zones 2>&1 || true
        echo
        echo '### Flatpak user remotes and apps'
        flatpak remotes --user 2>&1 || true
        flatpak list --user --app 2>&1 || true
        echo
        echo '### Snapper'
        if command -v snapper >/dev/null 2>&1; then
            sudo snapper -c root get-config 2>&1 || true
            sudo snapper -c root list 2>&1 || true
        else
            echo 'Snapper is not installed.'
        fi
        echo
        echo '### TRIM timer'
        systemctl status fstrim.timer --no-pager 2>&1 || true
        echo
        echo '### Swap and zram'
        swapon --show 2>&1 || true
        zramctl 2>&1 || true
        echo
        echo '### Power management services (report only)'
        systemctl is-active tuned 2>&1 || true
        systemctl is-active power-profiles-daemon 2>&1 || true
        echo
        echo '### Listening sockets'
        sudo ss -tulpn 2>&1 || true
        echo
        echo '### Failed systemd units'
        systemctl --failed --no-pager 2>&1 || true
        echo
        echo '### Recent boot errors'
        sudo journalctl -p err -b --no-pager -n 60 2>&1 || true
    } > "$verification_file"

    chmod 600 "$verification_file"
    log_success "Verification report saved: ${verification_file}"

    printf '\n'
    log_info "Quick status summary:"
    printf '  SELinux:       %s\n' "$(getenforce 2>/dev/null || echo unknown)"
    printf '  firewalld:     %s\n' "$(systemctl is-active firewalld 2>/dev/null || echo unknown)"
    printf '  fstrim.timer:  %s\n' "$(systemctl is-active fstrim.timer 2>/dev/null || echo unknown)"
    printf '  Failed units:  %s\n' "$(systemctl --failed --no-legend 2>/dev/null | wc -l | tr -d ' ')"
    printf '  Log:           %s\n' "$LOG_FILE"
    printf '  Inventory:     %s\n' "$SCRIPT_INVENTORY_DIR"
    printf '  Backups:       %s\n' "$BACKUP_DIR"

    if [[ "$(getenforce 2>/dev/null || true)" != "Enforcing" ]]; then
        log_warning "SELinux is not Enforcing. Investigate this before considering setup complete."
    fi
    if ! systemctl is-active --quiet firewalld; then
        log_warning "firewalld is not active. Review the firewall child script and verification report."
    fi
}

run_phase "Update installed user Flatpaks and check DNF consistency" final_updates
run_phase "Verify final system state" verify_system

###############################################################################
# 21. Completion notes
###############################################################################

cat <<COMPLETION

===============================================================================
Fedora post-install bootstrap completed.

Important follow-up checks:
  1. Review: ${LOG_FILE}
  2. Review: ${SCRIPT_INVENTORY_DIR}/verification_${FILENAME_TIMESTAMP}.txt
  3. Review the firewall zones and trusted LAN subnet before using public Wi-Fi.
  4. Run 'vainfo' and test actual hardware decoding in MPV and your browsers.
  5. Run 'fwupdmgr get-updates' and apply firmware updates deliberately.
  6. Test your backup and rollback procedures; Btrfs snapshots are not backups.
  7. Review ~/.config/zsh/aliases.zsh and ~/.zshrc shell integration.
  8. Reboot if the kernel, GPU driver, multimedia stack, or core system libraries changed.

This script does not automatically:
  - Create a Snapper configuration on an unverified Btrfs layout.
  - Create systemd timers without a defined maintenance job; add timers alongside
    the actual job scripts rather than creating empty or speculative schedules.
  - Enable SSH unless INSTALL_OPENSSH_SERVER=true.
  - Install OpenSnitch or USBGuard.
  - Enable virtualization unless INSTALL_VIRTUALIZATION=true.
  - Execute the AppMan installer unless INSTALL_AM=true and confirmed.
  - Disable SELinux or change Secure Boot.

Child scripts remain responsible for their own idempotence, backups, and
--verify-setup support. Review their behavior before relying on this bootstrap
for unattended or repeated deployments.
===============================================================================
COMPLETION
