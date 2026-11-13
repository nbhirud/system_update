#!/usr/bin/env bash
##################################################################################
# Overview and Usage
##################################################################################
# setup_virt_manager.sh
#
# Overview
#   Builds a complete KVM/QEMU + libvirt + virt-manager stack on Fedora, tuned to the
#   machine it runs on. Everything is detected at run time (CPU vendor, RAM, disks,
#   network type, desktop environment, installed tools); nothing is hardcoded to a
#   specific computer.
#
#   Docker: never modified. If Docker is installed, a small scoped firewall helper keeps
#   libvirt guests online next to it (see setup_docker_coexistence).
#
#   What it does, in order:
#     1. Backup   : saves every config it may touch (never VM disk images).
#     2. Reset    : removes the old libvirt networks/pools DEFINITIONS and old config
#                   this script manages, then starts fresh. VM disks and VM
#                   definitions are never deleted.
#     3. Setup    : packages, modular libvirt daemons, KVM module options, storage
#                   pools (fast + auto-detected bulk disk), virtual networks (NAT,
#                   isolated, and a LAN bridge when the machine is a desktop on
#                   ethernet), libvirt-guests, user integration (libvirt group,
#                   default URI, virt-manager preferences, MIME, Bleachbit), a
#                   security layer (SELinux labels, firewalld, ClamAV exclusions) and
#                   a "vm-create" helper for cloud-init (EC2 style) VMs.
#     4. Verify   : self-checks everything (also runnable alone with --verify-setup).
#
# Sample calls (assuming the caller uses the same variable names)
#   (a) All options:
#       sudo bash "$COMMON_DIR"/setup_virt_manager.sh \
#            --real-user "$REAL_USER" --filename-timestamp "$FILENAME_TIMESTAMP" \
#            --fast-pool-dir /var/lib/libvirt/images --bulk-pool-dir "$NBDIR/vm_images"
#   (b) Mandatory only (there are no mandatory options; everything is auto-detected):
#       sudo bash "$COMMON_DIR"/setup_virt_manager.sh
#   (c) Verification only:
#       sudo bash "$COMMON_DIR"/setup_virt_manager.sh --verify-setup
#
# Named options (all optional)
#   --real-user NAME           Non-root user to configure (default: the user who ran sudo)
#   --filename-timestamp STR   Shared timestamp for backup/log dirs (default: now)
#   --fast-pool-dir DIR        Directory of the "default" (fast) storage pool
#   --bulk-pool-dir DIR        Directory of the "bulk" (capacity) storage pool; when
#                              omitted, the largest data disk is auto-detected
#   --verify-setup             Only run the verification section
#   -h, --help                 Show this overview

set -uo pipefail

# Used before the logging helper is loaded.
early_die() { echo "ERROR: $*" >&2; exit 1; }

##################################################################################
# User defined variables
##################################################################################
# Standard variables shared by all setup scripts (names must not change).
REAL_USER="${REAL_USER:-${SUDO_USER:-${USER:-}}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"

# "default" pool: where VMs you use interactively live. /var/lib/libvirt/images is
# the location Fedora's SELinux policy already knows about, so it needs no extra labels.
VM_FAST_POOL_DIR="${VM_FAST_POOL_DIR:-/var/lib/libvirt/images}"

# "bulk" pool: capacity storage for ISOs and big lab VMs. Empty = auto-detect the
# mounted data disk with the most free space (never the disk holding "/").
VM_BULK_POOL_DIR="${VM_BULK_POOL_DIR:-}"
# A disk must have at least this many free GB to be auto-selected as bulk storage.
VM_BULK_MIN_FREE_GB="${VM_BULK_MIN_FREE_GB:-50}"

# /24 networks (first three octets) for the virtual networks. The first candidate that
# does not overlap ANY route or address already on this machine wins.
# 10.x is used on purpose: Docker allocates its networks from 172.16.0.0/12 and then
# from 192.168.0.0/16, and Kubernetes-in-Docker tools use 10.96.0.0/12 and 10.244.0.0/16.
# Staying out of all of those means heavy Docker use can never collide with the VMs.
VM_NAT_SUBNET_CANDIDATES=(10.77.122 10.78.122 10.79.122 10.80.122)
VM_ISOLATED_SUBNET_CANDIDATES=(10.77.123 10.78.123 10.79.123 10.80.123)
# Bridge name of the NAT network (pinned so firewall rules can refer to it).
NAT_BRIDGE_NAME="virbr0"

# Optional DNS forwarders (space separated IPs) for the NAT network's dnsmasq.
# Leave EMPTY (recommended): guests then use the host's resolver, so they inherit the
# host's encrypted DNS (DNS-over-TLS) and its per-device DNS identity. libvirt can only
# forward to plain (unencrypted) DNS servers, which is a privacy downgrade.
VM_NAT_DNS_FORWARDERS="${VM_NAT_DNS_FORWARDERS:-}"

# NextDNS profile ID (for example abc123). When set, VMs created with vm-create get their
# OWN NextDNS device identity (device name = VM name) through DNS-over-TLS inside the
# guest, so they show up separately in NextDNS and do not depend on the host's resolver.
# Leave empty to disable.
NEXTDNS_PROFILE_ID="${NEXTDNS_PROFILE_ID:-}"

# Name of the Linux bridge (also the NetworkManager profile id) used for LAN-visible VMs.
BRIDGE_NAME="${BRIDGE_NAME:-vmbr0}"
BRIDGE_PORT_PROFILE="${BRIDGE_NAME}-port"

# Libvirt object names this script owns. Reset only ever touches these names.
NET_NAT="default"; NET_ISOLATED="isolated"; NET_BRIDGED="bridged"
POOL_FAST="default"; POOL_BULK="bulk"

VERIFY_ONLY=false

##################################################################################
# Named Options processing
##################################################################################
# This section runs BEFORE "Inferred variables" because values such as HOME_DIR depend
# on --real-user. The original arguments are kept so the script can re-run itself under
# sudo and under the logging wrapper with exactly the same options.
ORIGINAL_ARGS=("$@")

while [ $# -gt 0 ]; do
  case "$1" in
    --real-user)           [ $# -ge 2 ] || early_die "--real-user needs a value"; REAL_USER="$2"; shift 2 ;;
    --real-user=*)         REAL_USER="${1#*=}"; shift ;;
    --filename-timestamp)  [ $# -ge 2 ] || early_die "--filename-timestamp needs a value"; FILENAME_TIMESTAMP="$2"; shift 2 ;;
    --filename-timestamp=*) FILENAME_TIMESTAMP="${1#*=}"; shift ;;
    --fast-pool-dir)       [ $# -ge 2 ] || early_die "--fast-pool-dir needs a value"; VM_FAST_POOL_DIR="$2"; shift 2 ;;
    --fast-pool-dir=*)     VM_FAST_POOL_DIR="${1#*=}"; shift ;;
    --bulk-pool-dir)       [ $# -ge 2 ] || early_die "--bulk-pool-dir needs a value"; VM_BULK_POOL_DIR="$2"; shift 2 ;;
    --bulk-pool-dir=*)     VM_BULK_POOL_DIR="${1#*=}"; shift ;;
    --verify-setup)        VERIFY_ONLY=true; shift ;;
    -h|--help)             sed -n '2,45p' "$0"; exit 0 ;;
    *)                     early_die "Unknown option: $1 (see --help)" ;;
  esac
done

[ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ] \
  || early_die "Run this with sudo from your normal account, or pass --real-user NAME."
id "$REAL_USER" >/dev/null 2>&1 || early_die "User '$REAL_USER' does not exist."

##################################################################################
# Inferred variables
##################################################################################
# --- Standard directory layout (names must not change) ---
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects" # all code projects
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update" # linux setup project
COMMON_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/common" # setup scripts for general things
GETTER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commong" # all the get_* getters
HELPER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commonh" # all the helper_* helpers
SECURITY_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/security" # security/privacy setup scripts
FEDORA_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/fedora" # fedora specific things
SCRIPT_DATA="${NBDIR}/nb_script_data" # base dir for all stuff created by scripts
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"; SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"; SCRIPT_DATA_LOGS="${SCRIPT_DATA}/logs"

# Per-package directories (package name: virt_manager). This script downloads nothing,
# so only backup and log directories are defined.
VIRT_MANAGER_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/virt_manager"
VIRT_MANAGER_CURRENT_BACKUP_DIR="${VIRT_MANAGER_BACKUP_DIR_BASE}/virt_manager_${FILENAME_TIMESTAMP}"
VIRT_MANAGER_LOG_DIR_BASE="${SCRIPT_DATA_LOGS}/virt_manager"
VIRT_MANAGER_CURRENT_LOG_DIR="${VIRT_MANAGER_LOG_DIR_BASE}/virt_manager_${FILENAME_TIMESTAMP}"

SCRIPT_PATH="$(readlink -f "$0")"
REAL_UID="$(id -u "$REAL_USER")"
REAL_GROUP="$(id -gn "$REAL_USER")"

# Small private directory where this script remembers what it changed (ACLs, SELinux
# labels, the original network profile) so a later run can undo it precisely.
STATE_DIR="/var/lib/virt_manager_setup"

# --- Privileges: everything below needs root; re-run under sudo if needed ---
if [ "$(id -u)" -ne 0 ]; then
  echo "Root privileges are required; re-running with sudo..." >&2
  exec sudo REAL_USER="$REAL_USER" FILENAME_TIMESTAMP="$FILENAME_TIMESTAMP" bash "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"
fi

# --- Logging: keep the terminal colored AND write everything to the log dir ---
# Piping through tee would remove colors (stdout stops being a terminal). Running the
# script inside util-linux "script" gives it a pseudo-terminal, so colors stay intact
# and the same bytes are copied to the log file (which therefore contains color codes).
ensure_user_dir() { install -d -o "$REAL_USER" -g "$REAL_GROUP" -m 0755 "$1"; }
if [ -z "${VIRT_MANAGER_LOGGING_ACTIVE:-}" ] && command -v script >/dev/null 2>&1; then
  for d in "$SCRIPT_DATA" "$SCRIPT_DATA_LOGS" "$VIRT_MANAGER_LOG_DIR_BASE" "$VIRT_MANAGER_CURRENT_LOG_DIR"; do ensure_user_dir "$d"; done
  export VIRT_MANAGER_LOGGING_ACTIVE=1 REAL_USER FILENAME_TIMESTAMP
  quoted_cmd="$(printf '%q ' bash "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}")"
  exec script --quiet --return --flush --command "$quoted_cmd" "${VIRT_MANAGER_CURRENT_LOG_DIR}/setup_virt_manager.log"
fi

# --- Helpers from the shared helper directory ---
for helper in helper_logging helper_dnf helper_backup helper_mimeapps; do
  [ -r "${HELPER_DIR}/${helper}.sh" ] || early_die "Missing helper: ${HELPER_DIR}/${helper}.sh"
  # shellcheck source=/dev/null
  source "${HELPER_DIR}/${helper}.sh"
done

# --- Hardware and environment detection via the shared getters ---
run_getter() { sh "${GETTER_DIR}/$1.sh" 2>/dev/null; }
CPU_CORES="$(run_getter get_cpu_cores)"
RAM_MB="$(run_getter get_ram_size)"
RAM_PROFILE="$(run_getter get_ram_profile)"
SSD_PRESENT="$(run_getter get_ssd_present)"
PC_TYPE="$(run_getter get_pc_type)"
DESKTOP="$(run_getter get_desktop_env)"
DISTRO="$(run_getter get_distro_name)"
DISTRO_VERSION="$(run_getter get_distro_version)"
CPU_MODEL="$(run_getter get_cpu_model)"
GPU_TIER="$(run_getter get_gpu_tier)"

: "${CPU_CORES:=1}" "${RAM_MB:=0}" "${RAM_PROFILE:=low}" "${PC_TYPE:=desktop}" "${DESKTOP:=unknown}"

# Which CPU virtualization extension exists: vmx = Intel VT-x, svm = AMD-V.
VIRT_FLAG="$(grep -m1 -Eo '\b(vmx|svm)\b' /proc/cpuinfo 2>/dev/null || true)"
case "$VIRT_FLAG" in
  vmx) KVM_MODULE="kvm_intel" ;;
  svm) KVM_MODULE="kvm_amd" ;;
  *)   KVM_MODULE="" ;;
esac

# RAM the host keeps for itself; the rest is the budget for running guests at once.
case "$RAM_PROFILE" in
  low)  HOST_RESERVE_MB=2048; PARALLEL_SHUTDOWN=1 ;;
  mid)  HOST_RESERVE_MB=3072; PARALLEL_SHUTDOWN=2 ;;
  *)    HOST_RESERVE_MB=4096; PARALLEL_SHUTDOWN=4 ;;
esac
GUEST_BUDGET_MB=$(( RAM_MB - HOST_RESERVE_MB )); [ "$GUEST_BUDGET_MB" -lt 0 ] && GUEST_BUDGET_MB=0

# Filled in by the setup steps.
BULK_DIR=""; BRIDGE_READY=false; TMP_DIR=""

##################################################################################
# Helpers
##################################################################################
# virsh pinned to the system connection. Plain "virsh" run as a normal user would talk
# to the per-user "session" libvirt instead, which is a different, separate world.
vsh() { virsh -c qemu:///system "$@"; }

# Run a command as the real user with the environment desktop tools need
# (HOME and the D-Bus session address used by gsettings/dconf).
run_as_user() {
  sudo -u "$REAL_USER" -H env HOME="$HOME_DIR" XDG_RUNTIME_DIR="/run/user/${REAL_UID}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${REAL_UID}/bus" "$@"
}

# Remember temp files and clean up on exit; also hand the log directory to the user.
cleanup() {
  [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
  chown -R "$REAL_USER:$REAL_GROUP" "$VIRT_MANAGER_CURRENT_LOG_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Is a package manager name installed, either by rpm or on PATH?
have_cmd() { command -v "$1" >/dev/null 2>&1; }

# Is an SSH session currently connected to this machine? Reconfiguring the main network
# card would cut such a session off, so network changes are skipped when one exists.
ssh_session_active() { ss -Htn state established '( sport = :ssh )' 2>/dev/null | grep -q .; }

selinux_active() { have_cmd getenforce && [ "$(getenforce 2>/dev/null)" != "Disabled" ]; }

# Verification counters
VERIFY_PASS=0; VERIFY_WARN=0; VERIFY_FAIL=0
check_pass() { log_success "$*"; VERIFY_PASS=$((VERIFY_PASS + 1)); }
check_warn() { log_warn "$*";    VERIFY_WARN=$((VERIFY_WARN + 1)); }
check_fail() { log_error "$*";   VERIFY_FAIL=$((VERIFY_FAIL + 1)); }

# Record a state-query command's output in the backup directory (never aborts the script).
rec() { local label="$1"; shift; "$@" >/dev/null 2>&1 && backup_record "$VIRT_MANAGER_CURRENT_BACKUP_DIR" "$label" "$@" || true; }

# Does the /24 network "<a.b.c>.0/24" overlap anything this machine already uses (any
# route, including Docker bridges and VPNs, or any interface address)? Python's
# ipaddress module does the overlap maths; plain text matching would miss big routes
# such as 10.0.0.0/8.
subnet_in_use() {
  python3 - "$1" <<'PY'
import ipaddress, subprocess, sys
candidate = ipaddress.ip_network(sys.argv[1] + ".0/24")
lines = subprocess.run(["ip", "-4", "route", "show", "table", "all"],
                       capture_output=True, text=True).stdout.splitlines()
for line in lines:
    tokens = line.split()
    if not tokens:
        continue
    if tokens[0] in ("local", "broadcast", "multicast", "unreachable", "blackhole", "prohibit"):
        tokens = tokens[1:]
    if not tokens or tokens[0] == "default":
        continue
    try:
        if candidate.overlaps(ipaddress.ip_network(tokens[0], strict=False)):
            sys.exit(0)   # in use
    except ValueError:
        pass
sys.exit(1)               # free
PY
}
# Print the first free candidate prefix (candidates are "a.b.c" strings).
pick_subnet() {
  local prefix
  for prefix in "$@"; do
    if ! subnet_in_use "$prefix"; then echo "$prefix"; return 0; fi
  done
  return 1
}

# Is the Docker engine installed? (Looks for its systemd unit; a podman "docker" shim
# does not create one.) Docker itself is never modified by this script.
docker_present() { systemctl cat docker.service >/dev/null 2>&1; }

# Pick the mounted data disk with the most free space. Skips: the root disk (including
# other btrfs subvolumes of it such as /home), boot/EFI, removable media mounts.
detect_bulk_dir() {
  local root_src min_bytes target source avail best_target="" best_avail=0
  root_src="$(findmnt -rno SOURCE / 2>/dev/null | sed 's/\[.*//')"
  min_bytes=$(( VM_BULK_MIN_FREE_GB * 1024 * 1024 * 1024 ))
  while read -r target source avail; do
    source="${source%%\[*}"          # btrfs shows /dev/sda3[/home]; drop the [subvolume] part
    case "$target" in
      /|/boot|/boot/*|/efi|/efi/*|/sysroot*|/run/media/*|/media/*|/var/lib/*|*\\x*) continue ;;
    esac
    [ "$source" = "$root_src" ] && continue
    [ "$avail" -ge "$min_bytes" ] 2>/dev/null || continue
    if [ "$avail" -gt "$best_avail" ]; then best_avail="$avail"; best_target="$target"; fi
  done < <(findmnt -rnb -t ext4,xfs,btrfs,f2fs -o TARGET,SOURCE,AVAIL 2>/dev/null)
  printf '%s' "$best_target"
}

# Wait until the modular libvirt daemons answer (they start on demand via sockets).
wait_for_libvirt() {
  local i
  for i in $(seq 1 30); do vsh version >/dev/null 2>&1 && return 0; sleep 1; done
  return 1
}

##################################################################################
# Backup
##################################################################################
# Everything this script can change is copied first. VM disk images are NOT copied
# (they can be hundreds of GB); this script never deletes them, so they do not need it.
backup_existing() {
  log_header "Backup"
  install -d -m 0700 "$VIRT_MANAGER_BACKUP_DIR_BASE" "$VIRT_MANAGER_CURRENT_BACKUP_DIR"

  local paths=(
    /etc/libvirt                                   # all libvirt config, network and pool definitions
    /etc/sysconfig/libvirt-guests
    /etc/modprobe.d/kvm-nested.conf
    /etc/NetworkManager/system-connections         # holds the ethernet profile we convert (and secrets: backup dir is 0700)
    /etc/sysctl.d /etc/sysctl.conf                 # only read by this script, saved for reference
    /etc/clamd.d                                   # exclusions may be added for the pool directories
    /etc/firewalld
    /etc/selinux/targeted/contexts/files/file_contexts.local
    /etc/polkit-1/rules.d
    /usr/local/bin/vm-create
    /usr/local/libexec/libvirt-docker-forward
    /etc/systemd/system/libvirt-docker-forward.service
    "$STATE_DIR"
    "$HOME_DIR/.config/libvirt"
    "$HOME_DIR/.config/mimeapps.list"
    "$HOME_DIR/.config/bleachbit"
    "$HOME_DIR/.var/app/org.bleachbit.BleachBit/config/bleachbit"
    "$HOME_DIR/.cache/virt-manager"
  )
  local p
  for p in "${paths[@]}"; do
    [ -e "$p" ] && backup_path_parents "$p" "${VIRT_MANAGER_CURRENT_BACKUP_DIR}/files"
  done

  # Runtime state that is not in files.
  have_cmd virsh && { rec virsh_networks vsh net-list --all; rec virsh_pools vsh pool-list --all --details; rec virsh_domains vsh list --all; }
  have_cmd nmcli && { rec nm_connections nmcli connection show; rec nm_devices nmcli device status; }
  rec ip_addr ip -d addr show
  rec ip_route ip route show
  rec libvirt_units systemctl list-unit-files 'virt*' 'libvirt*'
  have_cmd semanage && rec selinux_fcontext_local semanage fcontext -l -C
  have_cmd firewall-cmd && rec firewalld_zones firewall-cmd --list-all-zones
  rec libvirt_group getent group libvirt
  have_cmd dconf && rec virt_manager_dconf run_as_user dconf dump /org/virt-manager/virt-manager/
  log_success "Backup stored in ${VIRT_MANAGER_CURRENT_BACKUP_DIR}"
}

##################################################################################
# Reset
##################################################################################
# Fresh start: remove what this script created before, then rebuild. Libvirt pool and
# network entries are only UNDEFINED (config removed); "pool-delete" is never used and
# files inside the pools are never touched, so VM disks survive a reset.

# Undo the NetworkManager bridge (if a previous run made one) and restore the original
# ethernet profile.
reset_bridge() {
  have_cmd nmcli || return 0
  local existing
  existing="$(nmcli -t -e no -f NAME connection show 2>/dev/null | grep -Fx -e "$BRIDGE_NAME" -e "$BRIDGE_PORT_PROFILE" || true)"
  [ -n "$existing" ] || return 0
  ssh_session_active && log_die "An SSH session is active and a bridge exists; reverting it would drop the connection. Run this at the machine itself."

  log_info "Reverting existing bridge ${BRIDGE_NAME} to the original ethernet profile"
  local origin=""
  [ -r "$STATE_DIR/bridge_origin_profile" ] && origin="$(cat "$STATE_DIR/bridge_origin_profile")"
  nmcli connection delete "$BRIDGE_PORT_PROFILE" >/dev/null 2>&1 || true
  nmcli connection delete "$BRIDGE_NAME" >/dev/null 2>&1 || true
  if [ -n "$origin" ] && nmcli connection show "$origin" >/dev/null 2>&1; then
    nmcli connection modify "$origin" connection.autoconnect yes
    nmcli connection up "$origin" >/dev/null 2>&1 || log_warn "Could not re-activate profile '$origin'; activate your ethernet profile manually."
  else
    log_warn "Original ethernet profile unknown; re-enable autoconnect on your ethernet profile manually if the network is down."
  fi
  # Give NetworkManager a moment to bring the physical card back before detection runs.
  local i
  for i in $(seq 1 30); do
    nmcli -t -e no -f TYPE,STATE device 2>/dev/null | grep -q '^ethernet:connected' && break
    sleep 1
  done
}

reset_previous_setup() {
  log_header "Reset"

  if have_cmd virsh && vsh list --state-running --name 2>/dev/null | grep -q .; then
    log_die "Running VMs found. Shut them down first: this script redefines the virtual networks."
  fi

  # Libvirt networks and pools this script owns.
  if have_cmd virsh; then
    local net pool
    for net in "$NET_NAT" "$NET_ISOLATED" "$NET_BRIDGED"; do
      if vsh net-info "$net" >/dev/null 2>&1; then
        vsh net-destroy "$net" >/dev/null 2>&1 || true
        vsh net-undefine "$net" >/dev/null 2>&1 || true
      fi
    done
    for pool in "$POOL_FAST" "$POOL_BULK"; do
      if vsh pool-info "$pool" >/dev/null 2>&1; then
        vsh pool-destroy "$pool" >/dev/null 2>&1 || true    # stops the pool; does not delete files
        vsh pool-undefine "$pool" >/dev/null 2>&1 || true   # removes only the definition
      fi
    done
  fi

  reset_bridge

  # The old monolithic libvirtd conflicts with the modular daemons. Disable it.
  systemctl disable --now libvirtd.service libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket \
    libvirtd-tcp.socket libvirtd-tls.socket >/dev/null 2>&1 || true

  # Files written by this script.
  rm -f /etc/modprobe.d/kvm-nested.conf /etc/sysconfig/libvirt-guests /usr/local/bin/vm-create

  # Docker coexistence: remove our private chain and unit (Docker's own rules are untouched).
  [ -x /usr/local/libexec/libvirt-docker-forward ] && /usr/local/libexec/libvirt-docker-forward stop >/dev/null 2>&1
  systemctl disable --now libvirt-docker-forward.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/libvirt-docker-forward.service /usr/local/libexec/libvirt-docker-forward
  systemctl daemon-reload

  # SELinux labels and ACLs added by a previous run (recorded in the state directory).
  local p
  if [ -r "$STATE_DIR/fcontext_paths" ] && have_cmd semanage; then
    while read -r p; do
      [ -n "$p" ] || continue
      semanage fcontext -d "${p}(/.*)?" >/dev/null 2>&1 || true
      [ -d "$p" ] && restorecon -RF "$p" >/dev/null 2>&1 || true
    done < "$STATE_DIR/fcontext_paths"
  fi
  if [ -r "$STATE_DIR/acl_paths" ] && have_cmd setfacl; then
    while read -r p; do
      [ -n "$p" ] && [ -e "$p" ] && setfacl -x u:qemu "$p" >/dev/null 2>&1 || true
    done < "$STATE_DIR/acl_paths"
  fi

  # ClamAV exclusion blocks.
  local conf
  for conf in /etc/clamd.d/*.conf; do
    [ -f "$conf" ] && sed -i '/^# BEGIN virt-manager-setup/,/^# END virt-manager-setup/d' "$conf"
  done

  # User-level settings.
  rm -f "$HOME_DIR/.config/libvirt/libvirt.conf"
  rm -f "$HOME_DIR/.config/bleachbit/cleaners/virt_manager.xml" \
        "$HOME_DIR/.var/app/org.bleachbit.BleachBit/config/bleachbit/cleaners/virt_manager.xml"
  if have_cmd gsettings && [ -S "/run/user/${REAL_UID}/bus" ]; then
    run_as_user gsettings reset-recursively org.virt-manager.virt-manager >/dev/null 2>&1 || true
  fi
  run_as_user bash -c 'source "$1"; shift; mimeapps_forget "$@"' _ "${HELPER_DIR}/helper_mimeapps.sh" application/x-virt-viewer >/dev/null 2>&1 || true

  rm -rf "$STATE_DIR"
  install -d -m 0700 "$STATE_DIR"
  log_success "Previous setup removed; VM disks and VM definitions untouched."
}

##################################################################################
# Security
##################################################################################
# Make a storage pool directory usable by QEMU while keeping SELinux enforcing.
secure_pool_dir() {
  local dir="$1" p fs
  mkdir -p "$dir"
  chown root:root "$dir"
  chmod 0711 "$dir"    # libvirt's standard: others may enter but not list

  # btrfs copy-on-write fragments qcow2 files badly; +C turns it off for NEW files here.
  fs="$(findmnt -no FSTYPE -T "$dir" 2>/dev/null)"
  if [ "$fs" = "btrfs" ]; then
    chattr +C "$dir" 2>/dev/null && log_info "btrfs: copy-on-write disabled for new files in $dir" \
      || log_warn "Could not set +C on $dir"
  fi

  # SELinux: QEMU may only read/write files labelled virt_image_t. The default image
  # directory already has that label from the system policy; other paths need a rule.
  if selinux_active && have_cmd semanage; then
    case "$dir" in
      /var/lib/libvirt/*) ;;
      *)
        semanage fcontext -d "${dir}(/.*)?" >/dev/null 2>&1 || true
        semanage fcontext -a -t virt_image_t "${dir}(/.*)?" || log_warn "semanage failed for $dir"
        echo "$dir" >> "$STATE_DIR/fcontext_paths"
        ;;
    esac
    restorecon -RF "$dir" >/dev/null 2>&1 || true
  fi

  # Every parent directory must be enterable by the qemu user, otherwise a pool under a
  # private home directory fails with "permission denied". Grant only the execute bit
  # (enter, not list) through an ACL, and only where it is missing.
  if getent passwd qemu >/dev/null 2>&1 && have_cmd setfacl; then
    p="$(dirname "$dir")"
    while [ "$p" != "/" ]; do
      if ! runuser -u qemu -- test -x "$p" 2>/dev/null; then
        setfacl -m u:qemu:x "$p" && { echo "$p" >> "$STATE_DIR/acl_paths"; log_info "ACL: qemu may enter $p"; }
      fi
      p="$(dirname "$p")"
    done
  fi
}

# Exclude VM disk directories from ClamAV on-access scanning (it would scan every write
# a guest makes and slow guests to a crawl; malware inside a guest disk is not malware
# on the host).
exclude_pools_from_clamav() {
  local conf dirs=("$@") d u
  for conf in /etc/clamd.d/*.conf; do
    [ -f "$conf" ] || continue
    sed -i '/^# BEGIN virt-manager-setup/,/^# END virt-manager-setup/d' "$conf"
    {
      echo "# BEGIN virt-manager-setup"
      echo "# VM disk images: excluded from on-access scanning (see setup_virt_manager.sh)."
      for d in "${dirs[@]}"; do echo "OnAccessExcludePath $d"; done
      echo "# END virt-manager-setup"
    } >> "$conf"
    log_info "ClamAV exclusions written to $conf"
  done
  for u in $(systemctl list-units --state=active --no-legend 'clamd*' 'clamav-clamonacc*' 2>/dev/null | awk '{print $1}'); do
    systemctl try-restart "$u" >/dev/null 2>&1 || log_warn "Could not restart $u"
  done
}

# Keep bridged guest traffic flowing through firewalld. If the kernel's br_netfilter
# module is active (Docker/Kubernetes tools load it), frames crossing a bridge are
# passed to the host firewall's FORWARD rules, which then drop guest traffic unless the
# bridge's zone allows forwarding inside the zone. Only applied when needed.
configure_firewalld_for_bridge() {
  have_cmd firewall-cmd && systemctl is-active --quiet firewalld || { log_info "firewalld not running; nothing to adjust."; return 0; }
  local zone need=false
  lsmod | grep -q '^br_netfilter' && need=true
  docker_present && need=true
  [ "$need" = true ] || { log_info "br_netfilter not in use: no firewalld forwarding change needed."; return 0; }
  firewall-cmd --help 2>&1 | grep -q -- '--add-forward' || { log_warn "This firewalld has no --add-forward; see Troubleshooting if bridged guests lose network."; return 0; }

  zone="$(firewall-cmd --get-zone-of-interface="$BRIDGE_NAME" 2>/dev/null)"
  case "$zone" in ""|*"no zone"*) zone="$(firewall-cmd --get-default-zone)" ;; esac
  firewall-cmd --permanent --zone="$zone" --add-forward >/dev/null 2>&1 \
    && firewall-cmd --zone="$zone" --add-forward >/dev/null 2>&1 \
    && log_info "firewalld: forwarding enabled inside zone '$zone' (bridge ${BRIDGE_NAME} + its uplink only)" \
    || log_warn "Could not enable forwarding in zone '$zone'"
}

# Make libvirt and Docker coexist WITHOUT changing Docker at all.
#
# The problem: Docker sets the firewall FORWARD policy to DROP and loads br_netfilter,
# so (1) NAT guests lose internet, and (2) guests talking over a bridge (guest to guest,
# guest to LAN) are dropped too, because bridged frames also pass through that chain.
# The tempting fixes (turning off br_netfilter, changing Docker's iptables setting)
# would break Docker networks, Compose and kind/Kubernetes tooling, so none is used.
#
# The fix: Docker documents a chain named DOCKER-USER that it never touches and
# evaluates first. A small systemd unit, started whenever docker.service starts, adds a
# jump from DOCKER-USER to its own chain LIBVIRT-DOCKER whose rules are scoped to the
# libvirt bridges only:
#   - frames switched inside a libvirt bridge are accepted (guest<->guest, bridged LAN)
#   - traffic from NAT guests towards Docker networks is handed BACK to Docker's rules
#     (RETURN), so containers stay exactly as isolated as before
#   - NAT guests to everything else, and the replies, are accepted
# Docker's own chains, rules, daemon.json and sysctls are never changed.
setup_docker_coexistence() {
  log_header "Docker coexistence"
  if ! docker_present; then
    log_info "Docker not installed: nothing to do. Re-run this script after installing Docker."
    return 0
  fi

  install -d -m 0755 /usr/local/libexec
  cat > /usr/local/libexec/libvirt-docker-forward <<'DOCKER_FWD_EOF'
#!/usr/bin/env bash
# libvirt-docker-forward start|stop
# Written by setup_virt_manager.sh. Adds/removes a private chain, LIBVIRT-DOCKER, that
# lets libvirt guest traffic through Docker's firewall without touching Docker's rules.
set -u
CHAIN="LIBVIRT-DOCKER"
NAT_BRIDGE="@NAT_BRIDGE@"
LAN_BRIDGE="@LAN_BRIDGE@"      # empty when no LAN bridge exists

apply() {
  local ipt="$1" i
  command -v "$ipt" >/dev/null 2>&1 || return 0
  # DOCKER-USER appears once Docker has started; wait briefly for it.
  for i in $(seq 1 30); do "$ipt" -n -L DOCKER-USER >/dev/null 2>&1 && break; sleep 1; done
  if ! "$ipt" -n -L DOCKER-USER >/dev/null 2>&1; then
    echo "$ipt: no DOCKER-USER chain (Docker not running, IPv6 off, or nftables backend): nothing to do"
    return 0
  fi
  "$ipt" -N "$CHAIN" 2>/dev/null || "$ipt" -F "$CHAIN"
  # 1) Frames switched inside a libvirt bridge (br_netfilter shows them as in=out=bridge).
  "$ipt" -A "$CHAIN" -i "virbr+" -o "virbr+" -j ACCEPT
  [ -n "$LAN_BRIDGE" ] && "$ipt" -A "$CHAIN" -i "$LAN_BRIDGE" -o "$LAN_BRIDGE" -j ACCEPT
  # 2) Anything from NAT guests aimed at a Docker network: let Docker's rules decide.
  "$ipt" -A "$CHAIN" -i "$NAT_BRIDGE" -o docker0 -j RETURN
  "$ipt" -A "$CHAIN" -i "$NAT_BRIDGE" -o "br-+" -j RETURN
  # 3) NAT guests to everything else, plus the replies coming back.
  "$ipt" -A "$CHAIN" -i "$NAT_BRIDGE" -j ACCEPT
  "$ipt" -A "$CHAIN" -o "$NAT_BRIDGE" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  # Hook the chain in first place of DOCKER-USER (once).
  "$ipt" -C DOCKER-USER -j "$CHAIN" 2>/dev/null || "$ipt" -I DOCKER-USER 1 -j "$CHAIN"
}

remove() {
  local ipt="$1"
  command -v "$ipt" >/dev/null 2>&1 || return 0
  while "$ipt" -D DOCKER-USER -j "$CHAIN" 2>/dev/null; do :; done
  "$ipt" -F "$CHAIN" 2>/dev/null
  "$ipt" -X "$CHAIN" 2>/dev/null
  return 0
}

case "${1:-}" in
  start) apply iptables; apply ip6tables ;;
  stop)  remove iptables; remove ip6tables ;;
  *) echo "usage: $0 start|stop" >&2; exit 1 ;;
esac
DOCKER_FWD_EOF
  local lan_bridge=""
  [ "$BRIDGE_READY" = true ] && lan_bridge="$BRIDGE_NAME"
  sed -i -e "s|@NAT_BRIDGE@|${NAT_BRIDGE_NAME}|" -e "s|@LAN_BRIDGE@|${lan_bridge}|" /usr/local/libexec/libvirt-docker-forward
  chown root:root /usr/local/libexec/libvirt-docker-forward
  chmod 0755 /usr/local/libexec/libvirt-docker-forward
  selinux_active && restorecon /usr/local/libexec/libvirt-docker-forward >/dev/null 2>&1 || true

  # Started with Docker (WantedBy), restarted whenever Docker restarts (PartOf), so the
  # rules are always present exactly while Docker's own rules are.
  cat > /etc/systemd/system/libvirt-docker-forward.service <<'EOF'
[Unit]
Description=Let libvirt guest traffic through Docker's firewall (scoped to libvirt bridges)
After=docker.service
PartOf=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/libexec/libvirt-docker-forward start
ExecStop=/usr/local/libexec/libvirt-docker-forward stop

[Install]
WantedBy=docker.service
EOF
  systemctl daemon-reload
  systemctl enable libvirt-docker-forward.service >/dev/null 2>&1 || log_warn "Could not enable libvirt-docker-forward.service"
  if systemctl is-active --quiet docker.service; then
    systemctl restart libvirt-docker-forward.service || log_warn "libvirt-docker-forward.service failed; see journalctl -u libvirt-docker-forward"
  else
    log_info "Docker is not running now; the rules are added automatically when it starts."
  fi
  log_success "Docker coexistence in place (Docker itself unchanged)."
}

##################################################################################
# main setup
##################################################################################
sanity_checks() {
  log_header "Sanity checks"
  require_fedora
  log_info "Distro=${DISTRO} ${DISTRO_VERSION} | CPU=${CPU_MODEL} (${CPU_CORES} cores) | RAM=${RAM_MB} MB (${RAM_PROFILE}) | PC=${PC_TYPE} | DE=${DESKTOP}"
  if [ -z "$VIRT_FLAG" ]; then
    if have_cmd systemd-detect-virt && systemd-detect-virt -q; then
      log_die "This system is itself a VM without nested virtualization. Enable nested virtualization on the host."
    fi
    log_die "No VT-x/AMD-V found. Enable 'Intel Virtualization Technology' / 'SVM Mode' in the firmware (BIOS/UEFI) setup."
  fi
  log_success "CPU virtualization extension present (${VIRT_FLAG})"
  [ "$PC_TYPE" = "server" ] && log_warn "Headless server: virt-manager is installed anyway; manage guests with virsh or vm-create."
  return 0
}

install_packages() {
  log_header "Packages"
  # Explicit list instead of the "virtualization" group: the group no longer contains
  # virt-manager on recent Fedora, and a list shows exactly what is installed and why.
  local required=(
    qemu-kvm qemu-img                       # the emulator and disk image tool
    libvirt-daemon-kvm                      # libvirt's QEMU/KVM driver (pulls the modular daemons)
    libvirt-daemon-config-network           # default NAT network definition
    libvirt-client virt-install virt-manager virt-viewer
    edk2-ovmf                               # UEFI firmware for guests
    guestfs-tools libosinfo                 # virt-customize/virt-sysprep, osinfo-query
    xorriso                                 # builds cloud-init seed ISOs
    acl policycoreutils-python-utils        # setfacl, semanage
  )
  local optional=(
    cloud-utils genisoimage                 # cloud-localds and an ISO builder fallback
    qemu-device-usb-redirect qemu-audio-pipewire qemu-char-spice
    qemu-device-display-virtio-gpu qemu-device-display-virtio-gpu-gl
    qemu-ui-opengl qemu-ui-spice-core
  )
  # GTK integration so the GTK3-based virt-manager follows the Plasma theme.
  case "$DESKTOP" in
    *kde*|*plasma*) optional+=(kde-gtk-config breeze-gtk) ;;
    *gnome*|*lxqt*|*cosmic*|*hypr*) : ;;   # GTK-native or theme handled by the DE itself
  esac

  dnf_install_packages "${required[@]}"
  local available
  available="$(dnf_available_names "${optional[@]}")"
  # shellcheck disable=SC2086
  [ -n "$available" ] && dnf_install_packages $available
  local missing=()
  for p in "${optional[@]}"; do
    echo "$available" | tr ' ' '\n' | grep -qx "$p" || missing+=("$p")
  done
  [ "${#missing[@]}" -gt 0 ] && log_info "Optional packages not available in this release (skipped): ${missing[*]}"
  return 0
}

configure_kvm_modules() {
  log_header "KVM kernel modules"
  modprobe "$KVM_MODULE" 2>/dev/null || true       # creates /dev/kvm right now (no reboot needed)
  [ -e /dev/kvm ] || log_warn "/dev/kvm is missing; check that virtualization is enabled in firmware."

  # Nested virtualization (VMs inside VMs, e.g. a Kubernetes/kind lab in a guest).
  local nested
  nested="$(cat "/sys/module/${KVM_MODULE}/parameters/nested" 2>/dev/null || echo "")"
  case "$nested" in
    Y|y|1) log_info "Nested virtualization already enabled." ;;
    N|n|0)
      cat > /etc/modprobe.d/kvm-nested.conf <<EOF
# Written by setup_virt_manager.sh
# Allow guests to run their own hypervisor (nested virtualization).
options ${KVM_MODULE} nested=1
EOF
      log_info "Nested virtualization enabled for next boot (/etc/modprobe.d/kvm-nested.conf)."
      ;;
    *) log_info "Nested virtualization state unknown." ;;
  esac

  if [ -d /sys/kernel/iommu_groups ] && [ -n "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]; then
    log_info "IOMMU active (device passthrough possible)."
  else
    log_info "IOMMU not active (only needed for PCI passthrough; ignore otherwise)."
  fi
}

setup_services() {
  log_header "Libvirt services (modular daemons)"
  # Modern Fedora runs one small daemon per driver, each started on demand by a systemd
  # socket. The old all-in-one libvirtd is disabled (see Reset). Each daemon also has a
  # read-only and an admin socket.
  local daemon
  for daemon in virtqemud virtnetworkd virtstoraged virtnodedevd virtsecretd virtnwfilterd virtinterfaced; do
    systemctl enable --now "${daemon}.socket" "${daemon}-ro.socket" "${daemon}-admin.socket" >/dev/null 2>&1 \
      || log_warn "Could not enable ${daemon} sockets"
  done
  systemctl enable --now virtlogd.socket virtlockd.socket >/dev/null 2>&1 || true
  wait_for_libvirt || log_die "libvirt did not become ready. See: journalctl -u virtqemud"
  log_success "libvirt is answering on qemu:///system"
}

define_pool() {
  local name="$1" dir="$2"
  vsh pool-define-as --name "$name" --type dir --target "$dir" >/dev/null || { log_error "pool-define failed for $name"; return 1; }
  vsh pool-autostart "$name" >/dev/null
  vsh pool-start "$name" >/dev/null || log_warn "Pool $name did not start"
}

setup_storage_pools() {
  log_header "Storage pools"
  BULK_DIR="$VM_BULK_POOL_DIR"
  if [ -z "$BULK_DIR" ]; then
    local mount_point
    mount_point="$(detect_bulk_dir)"
    [ -n "$mount_point" ] && BULK_DIR="${mount_point%/}/vm_images"
  fi
  # A bulk pool identical to the fast pool would be pointless.
  if [ -n "$BULK_DIR" ] && [ "$(realpath -m "$BULK_DIR")" = "$(realpath -m "$VM_FAST_POOL_DIR")" ]; then BULK_DIR=""; fi

  secure_pool_dir "$VM_FAST_POOL_DIR"
  define_pool "$POOL_FAST" "$VM_FAST_POOL_DIR"
  log_info "Pool '${POOL_FAST}' -> ${VM_FAST_POOL_DIR} (fast; SSD present: ${SSD_PRESENT})"

  local iso_parent="$VM_FAST_POOL_DIR"
  if [ -n "$BULK_DIR" ]; then
    secure_pool_dir "$BULK_DIR"
    define_pool "$POOL_BULK" "$BULK_DIR"
    iso_parent="$BULK_DIR"
    log_info "Pool '${POOL_BULK}' -> ${BULK_DIR} (capacity disk, auto-selected or user defined)"
  else
    log_info "No separate data disk found: using one pool."
  fi

  # ISOs are large and read rarely: they go to bulk storage. Cloud image templates are
  # small and read often as qcow2 backing files: they stay on the fast pool.
  install -d -o "$REAL_USER" -g "$REAL_GROUP" -m 0755 "${iso_parent}/iso" "${VM_FAST_POOL_DIR}/templates"
  ISO_DIR="${iso_parent}/iso"; TEMPLATES_DIR="${VM_FAST_POOL_DIR}/templates"
  selinux_active && restorecon -RF "$ISO_DIR" "$TEMPLATES_DIR" >/dev/null 2>&1 || true

  if [ -n "$BULK_DIR" ]; then exclude_pools_from_clamav "$VM_FAST_POOL_DIR" "$BULK_DIR"; else exclude_pools_from_clamav "$VM_FAST_POOL_DIR"; fi
}

# Turn the machine's ethernet connection into a bridge port so VMs can be full citizens
# of the LAN. Safe by design: the original profile is kept, connectivity is tested, and
# everything is rolled back automatically if the network does not come back.
rollback_bridge() {
  local origin="$1"
  log_warn "Bridge did not come up: rolling back."
  nmcli connection delete "$BRIDGE_PORT_PROFILE" >/dev/null 2>&1 || true
  nmcli connection delete "$BRIDGE_NAME" >/dev/null 2>&1 || true
  nmcli connection modify "$origin" connection.autoconnect yes >/dev/null 2>&1 || true
  nmcli connection up "$origin" >/dev/null 2>&1 || true
  rm -f "$STATE_DIR/bridge_origin_profile"
}

setup_bridge() {
  BRIDGE_READY=false
  local conn_type
  conn_type="$(run_getter get_connection_type)"

  # Bridging needs wired ethernet: wifi access points reject extra MAC addresses.
  # Laptops also roam between untrusted networks, where bridging would expose guests.
  if [ "$PC_TYPE" = "laptop" ]; then log_info "Laptop: LAN bridge skipped (NAT + isolated networks only)."; return 0; fi
  if [ "$conn_type" != "ethernet" ]; then log_info "Active connection is '${conn_type:-none}', not ethernet: LAN bridge skipped."; return 0; fi
  have_cmd nmcli && systemctl is-active --quiet NetworkManager || { log_warn "NetworkManager not active: LAN bridge skipped."; return 0; }
  ssh_session_active && { log_warn "SSH session active: refusing to reconfigure the main network card. Re-run at the machine."; return 0; }

  local dev profile line
  line="$(nmcli -t -e no -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null | awk -F: '$2=="ethernet" && $3=="connected" {print $1 "\t" $4; exit}')"
  IFS=$'\t' read -r dev profile <<< "$line"
  [ -n "${dev:-}" ] && [ -n "${profile:-}" ] || { log_warn "No connected ethernet device with a NetworkManager profile: LAN bridge skipped."; return 0; }
  [ -e "/sys/class/net/${dev}/device" ] || { log_warn "${dev} is not a physical card: LAN bridge skipped."; return 0; }
  [ -e "/sys/class/net/${dev}/master" ] && { log_warn "${dev} already belongs to another bridge: LAN bridge skipped."; return 0; }

  local mac zone had_default=false
  mac="$(cat "/sys/class/net/${dev}/address")"
  ip route show default 2>/dev/null | grep -q " dev ${dev} " && had_default=true
  log_info "Creating bridge ${BRIDGE_NAME} with uplink ${dev} (profile '${profile}')"

  # The bridge takes over the card's MAC address, so the router keeps handing out the
  # same IP address and any DHCP reservation or per-device DNS identity stays valid.
  nmcli connection add type bridge ifname "$BRIDGE_NAME" con-name "$BRIDGE_NAME" \
    bridge.stp no bridge.mac-address "$mac" connection.autoconnect yes >/dev/null \
    || { log_warn "Could not create bridge profile."; return 0; }
  nmcli connection modify "$BRIDGE_NAME" connection.autoconnect-ports 1 >/dev/null 2>&1 \
    || nmcli connection modify "$BRIDGE_NAME" connection.autoconnect-slaves 1 >/dev/null 2>&1 || true

  # Copy IP, DNS and name-resolution settings from the original profile to the bridge.
  local prop value
  for prop in ipv4.method ipv4.addresses ipv4.gateway ipv4.dns ipv4.dns-search ipv4.ignore-auto-dns \
              ipv4.ignore-auto-routes ipv4.routes ipv4.route-metric ipv4.never-default \
              ipv4.dhcp-client-id ipv4.dhcp-hostname \
              ipv6.method ipv6.addresses ipv6.gateway ipv6.dns ipv6.dns-search ipv6.ignore-auto-dns \
              ipv6.ip6-privacy ipv6.addr-gen-mode \
              connection.mdns connection.llmnr connection.dns-over-tls; do
    value="$(nmcli -e no -g "$prop" connection show "$profile" 2>/dev/null)"
    case "$value" in ""|"--") continue ;; esac
    nmcli connection modify "$BRIDGE_NAME" "$prop" "$value" >/dev/null 2>&1 || log_info "  (property $prop not copied)"
  done

  # Same firewalld zone as the original connection: the host's firewall policy is unchanged.
  zone="$(nmcli -e no -g connection.zone connection show "$profile" 2>/dev/null)"
  case "$zone" in ""|"--") : ;; *) nmcli connection modify "$BRIDGE_NAME" connection.zone "$zone" >/dev/null 2>&1 || true ;; esac

  # The physical card becomes a "port" of the bridge. Newer NetworkManager names the
  # options port-type/controller; older ones bridge-slave/master. Try new, then old.
  nmcli connection add type ethernet port-type bridge controller "$BRIDGE_NAME" ifname "$dev" \
      con-name "$BRIDGE_PORT_PROFILE" connection.autoconnect yes >/dev/null 2>&1 \
    || nmcli connection add type bridge-slave master "$BRIDGE_NAME" ifname "$dev" \
      con-name "$BRIDGE_PORT_PROFILE" connection.autoconnect yes >/dev/null 2>&1 \
    || { log_warn "Could not create bridge port profile."; nmcli connection delete "$BRIDGE_NAME" >/dev/null 2>&1; return 0; }

  # Remember the original profile, stop it from claiming the card at boot, and switch.
  echo "$profile" > "$STATE_DIR/bridge_origin_profile"
  nmcli connection modify "$profile" connection.autoconnect no >/dev/null 2>&1 || true
  nmcli connection up "$BRIDGE_NAME" >/dev/null 2>&1 || true
  nmcli connection up "$BRIDGE_PORT_PROFILE" >/dev/null 2>&1 || true

  # Success = NetworkManager reports the bridge connected (state 100), and, if the
  # machine had a default route before, it now goes through the bridge.
  local i ok=false state
  for i in $(seq 1 45); do
    state="$(nmcli -g GENERAL.STATE device show "$BRIDGE_NAME" 2>/dev/null | cut -d' ' -f1)"
    if [ "$state" = "100" ]; then
      if [ "$had_default" = false ] || ip route show default 2>/dev/null | grep -q " dev ${BRIDGE_NAME} "; then ok=true; break; fi
    fi
    sleep 1
  done
  if [ "$ok" != true ]; then rollback_bridge "$profile"; return 0; fi

  BRIDGE_READY=true
  log_success "Bridge ${BRIDGE_NAME} is up (uplink ${dev})."
  configure_firewalld_for_bridge
}

define_network() {
  local name="$1" xml="$2"
  vsh net-define "$xml" >/dev/null || { log_error "net-define failed for $name"; return 1; }
  vsh net-autostart "$name" >/dev/null
  vsh net-start "$name" >/dev/null || log_warn "Network $name did not start"
}

setup_networks() {
  log_header "Virtual networks"
  TMP_DIR="$(mktemp -d)"
  setup_bridge

  # NAT: guests reach the internet through the host; the LAN cannot see them.
  local nat_prefix iso_prefix dns_xml=""
  nat_prefix="$(pick_subnet "${VM_NAT_SUBNET_CANDIDATES[@]}")" || log_die "No free subnet for the NAT network."
  if [ -n "$VM_NAT_DNS_FORWARDERS" ]; then
    local f; dns_xml="  <dns>"
    for f in $VM_NAT_DNS_FORWARDERS; do dns_xml+=$'\n'"    <forwarder addr='${f}'/>"; done
    dns_xml+=$'\n'"  </dns>"
  fi
  cat > "$TMP_DIR/nat.xml" <<EOF
<network>
  <name>${NET_NAT}</name>
  <forward mode='nat'/>
  <bridge name='${NAT_BRIDGE_NAME}' stp='on' delay='0'/>
${dns_xml}
  <ip address='${nat_prefix}.1' netmask='255.255.255.0'>
    <dhcp><range start='${nat_prefix}.2' end='${nat_prefix}.254'/></dhcp>
  </ip>
</network>
EOF
  define_network "$NET_NAT" "$TMP_DIR/nat.xml" && log_info "Network '${NET_NAT}' (NAT) on ${nat_prefix}.0/24"

  # Isolated: no <forward> element = no route out. Guests talk only to the host and each
  # other. Use it for untrusted software and for internal lab networks.
  iso_prefix="$(pick_subnet "${VM_ISOLATED_SUBNET_CANDIDATES[@]}")" || log_die "No free subnet for the isolated network."
  cat > "$TMP_DIR/isolated.xml" <<EOF
<network>
  <name>${NET_ISOLATED}</name>
  <bridge name='virbr%d' stp='on' delay='0'/>
  <ip address='${iso_prefix}.1' netmask='255.255.255.0'>
    <dhcp><range start='${iso_prefix}.2' end='${iso_prefix}.254'/></dhcp>
  </ip>
</network>
EOF
  define_network "$NET_ISOLATED" "$TMP_DIR/isolated.xml" && log_info "Network '${NET_ISOLATED}' (no outside access) on ${iso_prefix}.0/24"

  if [ "$BRIDGE_READY" = true ]; then
    cat > "$TMP_DIR/bridged.xml" <<EOF
<network>
  <name>${NET_BRIDGED}</name>
  <forward mode='bridge'/>
  <bridge name='${BRIDGE_NAME}'/>
</network>
EOF
    define_network "$NET_BRIDGED" "$TMP_DIR/bridged.xml" && log_info "Network '${NET_BRIDGED}' (LAN bridge via ${BRIDGE_NAME})"
  fi
}

setup_libvirt_guests() {
  log_header "Guest shutdown handling (libvirt-guests)"
  # Without this, powering off the host kills running VMs like pulling a plug.
  cat > /etc/sysconfig/libvirt-guests <<EOF
# Written by setup_virt_manager.sh
# Which libvirt connection to manage.
URIS=qemu:///system
# Do not auto-resume guests at boot here; guests marked "autostart" are started by libvirt itself.
ON_BOOT=ignore
# On host shutdown, ask guests to shut down cleanly (ACPI). The default, "suspend",
# writes each guest's RAM to disk, which is slow and uses lots of space.
ON_SHUTDOWN=shutdown
# Seconds to wait for a guest to stop before giving up on it.
SHUTDOWN_TIMEOUT=120
# How many guests shut down at the same time. Scaled to host RAM so a small machine's
# disk is not hammered by simultaneous flushes (low=1, mid=2, high=4).
PARALLEL_SHUTDOWN=${PARALLEL_SHUTDOWN}
EOF
  chmod 0644 /etc/sysconfig/libvirt-guests
  systemctl enable libvirt-guests.service >/dev/null 2>&1 || log_warn "Could not enable libvirt-guests.service"
}

# Tiny wrapper around gsettings that warns instead of failing.
gset() { run_as_user gsettings set "$@" >/dev/null 2>&1 || log_warn "gsettings could not set: $*"; }

setup_user_integration() {
  log_header "User integration for ${REAL_USER}"

  # 1) Group membership: members of "libvirt" may manage the system libvirt without
  #    a password prompt (a polkit rule shipped with libvirt grants this).
  if getent group libvirt >/dev/null 2>&1; then
    usermod -aG libvirt "$REAL_USER" && log_info "Added ${REAL_USER} to group 'libvirt' (log out and back in to activate it)."
  else
    log_warn "Group 'libvirt' does not exist; check the libvirt-daemon packages."
  fi

  # 2) Make virsh/virt-install/virt-manager all use the SAME connection. Without this,
  #    virsh run as a normal user talks to a separate per-user libvirt ("session") and
  #    shows none of the VMs that virt-manager shows.
  install -d -o "$REAL_USER" -g "$REAL_GROUP" -m 0755 "$HOME_DIR/.config" "$HOME_DIR/.config/libvirt"
  cat > "$HOME_DIR/.config/libvirt/libvirt.conf" <<'EOF'
# Written by setup_virt_manager.sh
# Default connection for virsh, virt-install and other libvirt tools.
# qemu:///system = machine-wide libvirt (needed for bridged networking, shared pools).
# qemu:///session = per-user libvirt (what GNOME Boxes uses; separate set of VMs).
uri_default = "qemu:///system"
EOF
  chown "$REAL_USER:$REAL_GROUP" "$HOME_DIR/.config/libvirt/libvirt.conf"

  # 3) virt-manager preferences (needs the user's desktop session bus).
  if have_cmd gsettings && [ -S "/run/user/${REAL_UID}/bus" ]; then
    gset org.virt-manager.virt-manager.connections uris "['qemu:///system']"
    gset org.virt-manager.virt-manager.connections autoconnect "['qemu:///system']"
    gset org.virt-manager.virt-manager xmleditor-enabled true      # edit guest XML in the details window
    # Statistics polling costs CPU on every refresh. On small or low-power machines poll
    # less often and skip disk/network graphs.
    if [ "$RAM_PROFILE" = "low" ]; then
      gset org.virt-manager.virt-manager.stats update-interval 5
      gset org.virt-manager.virt-manager.stats enable-disk-poll false
      gset org.virt-manager.virt-manager.stats enable-net-poll false
    fi
    log_info "virt-manager preferences applied."
  else
    log_warn "No desktop session bus for ${REAL_USER}: virt-manager preferences skipped. Re-run after logging in to the desktop."
  fi

  # 4) MIME: .vv connection files open in remote-viewer (part of virt-viewer).
  if [ -f /usr/share/applications/remote-viewer.desktop ]; then
    run_as_user bash -c 'source "$1"; shift; mimeapps_set_default "$@"' _ "${HELPER_DIR}/helper_mimeapps.sh" \
      remote-viewer.desktop application/x-virt-viewer >/dev/null 2>&1 \
      && log_info "MIME default set: application/x-virt-viewer -> remote-viewer" || log_warn "MIME default not set."
  fi

  setup_bleachbit_cleaner
  install_vm_create
}

# Bleachbit custom cleaner, written to the right place for each install type
# (RPM: ~/.config/bleachbit, Flatpak: ~/.var/app/<id>/config/bleachbit).
setup_bleachbit_cleaner() {
  local targets=()
  rpm_is_installed bleachbit && targets+=("$HOME_DIR/.config/bleachbit/cleaners")
  if have_cmd flatpak && run_as_user flatpak list --app --columns=application 2>/dev/null | grep -qx 'org.bleachbit.BleachBit'; then
    targets+=("$HOME_DIR/.var/app/org.bleachbit.BleachBit/config/bleachbit/cleaners")
    # The Flatpak sandbox can only see what it is allowed to: grant just this one cache dir.
    run_as_user flatpak override --user --filesystem=xdg-cache/virt-manager org.bleachbit.BleachBit >/dev/null 2>&1 || true
  fi
  [ "${#targets[@]}" -gt 0 ] || { log_info "Bleachbit not installed: cleaner not written."; return 0; }

  local dir
  for dir in "${targets[@]}"; do
    install -d -o "$REAL_USER" -g "$REAL_GROUP" -m 0755 "$dir"
    cat > "$dir/virt_manager.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!-- Written by setup_virt_manager.sh: logs and caches of virt-manager / virt-install. -->
<cleaner id="virt_manager">
  <label>virt-manager</label>
  <description>Logs and caches of virt-manager and virt-install</description>
  <option id="cache_logs">
    <label>Cache and logs</label>
    <description>Delete ~/.cache/virt-manager (logs, thumbnails, cached state)</description>
    <action command="delete" search="walk.files" path="~/.cache/virt-manager"/>
  </option>
</cleaner>
EOF
    chown "$REAL_USER:$REAL_GROUP" "$dir/virt_manager.xml"
    log_info "Bleachbit cleaner written to $dir"
  done
}

# Install the "vm-create" helper: one command to create a cloud-init VM from a cloud
# image, the same workflow as launching an EC2 instance with user-data.
install_vm_create() {
  cat > /usr/local/bin/vm-create <<'VM_CREATE_EOF'
#!/usr/bin/env bash
# vm-create - create a VM from a cloud image with cloud-init (EC2-style workflow)
# Written by setup_virt_manager.sh
#
# Usage: vm-create --name NAME --image IMAGE [options]
#   --image IMAGE     Cloud image (qcow2/img). A bare file name is looked up in the templates dir.
#   --vcpus N         default: 2 (1 on single-core hosts)
#   --memory MB       default: 2048 (1024 when the host has under 4 GB available)
#   --disk-gb N       default: 20
#   --network NET     nat | isolated | bridged | <libvirt network name>   (default: nat)
#   --pool POOL       libvirt storage pool for the VM disk (default: default)
#   --ssh-key FILE    public key to install (default: first of ed25519/ecdsa/rsa in ~/.ssh)
#   --user NAME       login user created in the guest (default: current user)
#   --os-variant ID   osinfo short id (default: linux2022; falls back to generic)
#   --dns MODE        nextdns | host. nextdns (default when a NextDNS profile ID was set
#                     at install time): the guest gets its own NextDNS device identity
#                     named after the VM, over DNS-over-TLS via systemd-resolved. host:
#                     leave the guest's DNS alone (NAT guests then use the host resolver;
#                     bridged guests use the router's DNS). No effect on 'isolated'.
set -euo pipefail

TEMPLATES_DIR="@TEMPLATES_DIR@"
NEXTDNS_ID="@NEXTDNS_ID@"
DNS_MODE="host"; [ -n "$NEXTDNS_ID" ] && DNS_MODE="nextdns"
NAME=""; IMAGE=""; DISK_GB=20; NETWORK="nat"; POOL="default"; SSH_KEY=""
LOGIN_USER="${SUDO_USER:-$USER}"; OS_VARIANT="linux2022"

# Defaults chosen from the host's real resources at run time.
VCPUS=2; [ "$(nproc)" -lt 2 ] && VCPUS=1
MEM_MB=2048
avail_mb="$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)"
[ "$avail_mb" -lt 4096 ] && MEM_MB=1024

usage() { sed -n '2,14p' "$0"; exit "${1:-0}"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;      --image) IMAGE="$2"; shift 2 ;;
    --vcpus) VCPUS="$2"; shift 2 ;;    --memory) MEM_MB="$2"; shift 2 ;;
    --disk-gb) DISK_GB="$2"; shift 2 ;; --network) NETWORK="$2"; shift 2 ;;
    --pool) POOL="$2"; shift 2 ;;      --ssh-key) SSH_KEY="$2"; shift 2 ;;
    --user) LOGIN_USER="$2"; shift 2 ;; --os-variant) OS_VARIANT="$2"; shift 2 ;;
    --dns) DNS_MODE="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done
[ -n "$NAME" ] && [ -n "$IMAGE" ] || usage 1

# Resolve the image: explicit path, or a name inside the templates directory.
if [ ! -f "$IMAGE" ] && [ -f "$TEMPLATES_DIR/$IMAGE" ]; then IMAGE="$TEMPLATES_DIR/$IMAGE"; fi
[ -f "$IMAGE" ] || { echo "Image not found: $IMAGE (templates dir: $TEMPLATES_DIR)" >&2; exit 1; }
IMAGE="$(readlink -f "$IMAGE")"
echo "Note: the qemu service user must be able to read $IMAGE (keep images in $TEMPLATES_DIR)."

# SSH key to log in with.
if [ -z "$SSH_KEY" ]; then
  user_home="$(getent passwd "$LOGIN_USER" | cut -d: -f6)"
  for k in id_ed25519 id_ecdsa id_rsa; do [ -f "$user_home/.ssh/$k.pub" ] && { SSH_KEY="$user_home/.ssh/$k.pub"; break; }; done
fi
[ -n "$SSH_KEY" ] && [ -f "$SSH_KEY" ] || { echo "No SSH public key found; pass --ssh-key FILE." >&2; exit 1; }

case "$NETWORK" in nat) NET="default" ;; isolated) NET="isolated" ;; bridged) NET="bridged" ;; *) NET="$NETWORK" ;; esac
virsh -c qemu:///system net-info "$NET" >/dev/null 2>&1 || { echo "Libvirt network '$NET' does not exist." >&2; exit 1; }

# Fall back to the generic OS profile when this system's osinfo database does not know the id.
if command -v osinfo-query >/dev/null 2>&1; then
  osinfo-query -f short-id os short-id="$OS_VARIANT" 2>/dev/null | grep -qw "$OS_VARIANT" || OS_VARIANT="generic"
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/meta-data" <<EOF
instance-id: ${NAME}
local-hostname: ${NAME}
EOF
# Passwordless sudo is the cloud-image convention and fine for throwaway lab VMs;
# password login is locked, so only your SSH key works.
cat > "$TMP/user-data" <<EOF
#cloud-config
hostname: ${NAME}
users:
  - name: ${LOGIN_USER}
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - $(cat "$SSH_KEY")
EOF

# Own NextDNS device identity for this guest. The device name is encoded in the DoT
# host name (<device>-<profile>.dns.nextdns.io), so each VM appears separately in
# NextDNS. Needs systemd-resolved in the guest (Fedora, Ubuntu and most cloud images
# have it); on other guests configure DNS-over-TLS by hand.
if [ "$DNS_MODE" = "nextdns" ] && [ -n "$NEXTDNS_ID" ] && [ "$NET" != "isolated" ]; then
  dev_name="$(printf '%s' "$NAME" | tr -c 'A-Za-z0-9-' '-' | cut -c1-40 | sed 's/-*$//')"
  dot_host="${dev_name}-${NEXTDNS_ID}.dns.nextdns.io"
  cat >> "$TMP/user-data" <<EOF
write_files:
  - path: /etc/systemd/resolved.conf.d/10-nextdns.conf
    permissions: '0644'
    content: |
      [Resolve]
      DNS=45.90.28.0#${dot_host}
      DNS=2a07:a8c0::#${dot_host}
      DNS=45.90.30.0#${dot_host}
      DNS=2a07:a8c0::1#${dot_host}
      DNSOverTLS=yes
      Domains=~.
runcmd:
  - [ systemctl, try-restart, systemd-resolved ]
EOF
  echo "DNS: guest will use NextDNS device '${dot_host%%.*}'"
fi

virt-install --connect qemu:///system \
  --name "$NAME" --memory "$MEM_MB" --vcpus "$VCPUS" --cpu host-passthrough \
  --os-variant "$OS_VARIANT" --import \
  --disk "pool=${POOL},size=${DISK_GB},backing_store=${IMAGE},format=qcow2,bus=virtio" \
  --network "network=${NET},model=virtio" \
  --graphics none --noautoconsole \
  --cloud-init "user-data=${TMP}/user-data,meta-data=${TMP}/meta-data"

cat <<EOF

VM '${NAME}' created (${VCPUS} vCPU, ${MEM_MB} MB, ${DISK_GB} GB, network ${NET}).
  Find its IP : virsh domifaddr ${NAME}        (bridged: add --source arp)
  Log in      : ssh ${LOGIN_USER}@<ip>
  Console     : virsh console ${NAME}          (leave with Ctrl+])
  Delete      : virsh destroy ${NAME}; virsh undefine ${NAME} --remove-all-storage
EOF
VM_CREATE_EOF
  sed -i -e "s|@TEMPLATES_DIR@|${TEMPLATES_DIR}|" -e "s|@NEXTDNS_ID@|${NEXTDNS_PROFILE_ID}|" /usr/local/bin/vm-create
  chown root:root /usr/local/bin/vm-create
  chmod 0755 /usr/local/bin/vm-create
  selinux_active && restorecon /usr/local/bin/vm-create >/dev/null 2>&1 || true
  log_info "Installed /usr/local/bin/vm-create (templates dir: ${TEMPLATES_DIR})"
}

print_summary() {
  log_header "Summary"
  log_info "Guest RAM budget: about ${GUEST_BUDGET_MB} MB in total across running VMs (host keeps ${HOST_RESERVE_MB} MB)."
  log_info "Keep total vCPUs of running VMs at or below $(( CPU_CORES * 2 )) (host has ${CPU_CORES} cores)."
  [ "$GPU_TIER" = "low" ] && log_info "Weak GPU: use the default SPICE display; 3D acceleration (virgl) will be limited."
  log_info "Next steps: log out and back in (group 'libvirt'), then start virt-manager."
  log_info "Create a cloud-init VM: vm-create --name test1 --image <cloud-image> --network nat"
}

##################################################################################
# Verification
##################################################################################
run_verification() {
  log_header "Verification"

  # --- Host ---
  [ -n "$VIRT_FLAG" ] && check_pass "CPU virtualization extension: ${VIRT_FLAG}" || check_fail "No VT-x/AMD-V."
  [ -e /dev/kvm ] && check_pass "/dev/kvm exists" || check_fail "/dev/kvm missing."
  [ -n "$KVM_MODULE" ] && lsmod | grep -q "^${KVM_MODULE}" && check_pass "${KVM_MODULE} loaded" || check_warn "KVM module not loaded."
  if have_cmd virt-host-validate; then
    log_info "virt-host-validate output:"
    virt-host-validate qemu 2>&1 | sed 's/^/    /'
  fi

  # --- Packages ---
  local pkg
  for pkg in qemu-kvm libvirt-daemon-kvm virt-manager virt-install edk2-ovmf guestfs-tools; do
    rpm_is_installed "$pkg" && check_pass "Package installed: $pkg" || check_fail "Package missing: $pkg"
  done

  # --- Services ---
  local daemon
  for daemon in virtqemud virtnetworkd virtstoraged virtnodedevd virtsecretd; do
    systemctl is-active --quiet "${daemon}.socket" && check_pass "${daemon}.socket active" || check_fail "${daemon}.socket not active"
  done
  systemctl is-enabled --quiet libvirtd.service 2>/dev/null && check_fail "Old monolithic libvirtd is enabled (conflicts with modular daemons)." || check_pass "Monolithic libvirtd not enabled"
  systemctl is-enabled --quiet libvirt-guests.service 2>/dev/null && check_pass "libvirt-guests enabled" || check_warn "libvirt-guests not enabled"
  vsh version >/dev/null 2>&1 && check_pass "libvirt reachable on qemu:///system (root)" || check_fail "libvirt not reachable."
  run_as_user virsh -c qemu:///system list >/dev/null 2>&1 \
    && check_pass "${REAL_USER} can manage libvirt without a password" \
    || check_warn "${REAL_USER} cannot reach libvirt yet (log out and back in so the 'libvirt' group applies)."
  getent group libvirt | grep -qw "$REAL_USER" && check_pass "${REAL_USER} is in group libvirt" || check_fail "${REAL_USER} is not in group libvirt"

  # --- Networks ---
  local net
  for net in "$NET_NAT" "$NET_ISOLATED"; do
    vsh net-info "$net" 2>/dev/null | grep -q 'Active:.*yes' && check_pass "Network '$net' active" || check_fail "Network '$net' not active"
    vsh net-info "$net" 2>/dev/null | grep -q 'Autostart:.*yes' && check_pass "Network '$net' autostart" || check_warn "Network '$net' not autostart"
  done
  if have_cmd firewall-cmd && systemctl is-active --quiet firewalld; then
    local z; z="$(firewall-cmd --get-zone-of-interface=virbr0 2>/dev/null)"
    [ "$z" = "libvirt" ] && check_pass "virbr0 is in firewalld zone 'libvirt'" || check_warn "virbr0 firewalld zone is '${z:-none}' (expected 'libvirt'); check your custom zones."
  fi
  if vsh net-info "$NET_BRIDGED" >/dev/null 2>&1; then
    ip -br addr show "$BRIDGE_NAME" 2>/dev/null | grep -q 'UP' && check_pass "Bridge ${BRIDGE_NAME} is UP" || check_fail "Bridge ${BRIDGE_NAME} not UP"
    ip route show default 2>/dev/null | grep -q " dev ${BRIDGE_NAME} " && check_pass "Default route goes through ${BRIDGE_NAME}" || check_warn "Default route does not use ${BRIDGE_NAME}"
    [ -n "$(ls -A "/sys/class/net/${BRIDGE_NAME}/brif" 2>/dev/null)" ] && check_pass "Bridge has an uplink port" || check_fail "Bridge has no port"
  else
    log_info "No bridged network defined (laptop, non-ethernet, or skipped for safety)."
  fi

  # Settings elsewhere on this machine that silently break NAT networking.
  if grep -rhsE '^\s*net\.ipv4\.ip_forward\s*=\s*0' /etc/sysctl.conf /etc/sysctl.d/ 2>/dev/null | grep -q .; then
    check_warn "A sysctl file forces net.ipv4.ip_forward=0, which breaks NAT networking for guests. Remove it or set it to 1."
  else
    check_pass "No sysctl file forces ip_forward=0"
  fi
  if docker_present; then
    systemctl is-enabled --quiet libvirt-docker-forward.service 2>/dev/null \
      && check_pass "libvirt-docker-forward.service enabled (Docker coexistence)" \
      || check_fail "libvirt-docker-forward.service not enabled; guests may lose network while Docker runs."
    if systemctl is-active --quiet docker.service && have_cmd iptables && iptables -n -L DOCKER-USER >/dev/null 2>&1; then
      iptables -C DOCKER-USER -j LIBVIRT-DOCKER 2>/dev/null \
        && check_pass "DOCKER-USER jumps to LIBVIRT-DOCKER (guest traffic allowed, Docker rules untouched)" \
        || check_fail "LIBVIRT-DOCKER chain not hooked into DOCKER-USER: try 'sudo systemctl restart libvirt-docker-forward'"
    fi
  fi

  # --- Storage ---
  local pool
  for pool in "$POOL_FAST" "$POOL_BULK"; do
    vsh pool-info "$pool" >/dev/null 2>&1 || { [ "$pool" = "$POOL_FAST" ] && check_fail "Pool '$pool' missing"; continue; }
    vsh pool-info "$pool" 2>/dev/null | grep -q 'State:.*running' && check_pass "Pool '$pool' running" || check_fail "Pool '$pool' not running"
    vsh pool-info "$pool" 2>/dev/null | grep -q 'Autostart:.*yes' && check_pass "Pool '$pool' autostart" || check_warn "Pool '$pool' not autostart"
    local pdir; pdir="$(vsh pool-dumpxml "$pool" 2>/dev/null | sed -n 's|.*<path>\(.*\)</path>.*|\1|p' | head -1)"
    if selinux_active && [ -n "$pdir" ]; then
      [[ "$(ls -dZ "$pdir" 2>/dev/null)" == *virt_image_t* ]] && check_pass "SELinux label OK on $pdir" || check_warn "$pdir is not labelled virt_image_t"
    fi
    if getent passwd qemu >/dev/null 2>&1 && [ -n "$pdir" ]; then
      runuser -u qemu -- test -x "$pdir" 2>/dev/null && check_pass "qemu can enter $pdir" || check_fail "qemu cannot enter $pdir (parent directory permissions)"
    fi
  done

  # --- Config and integration ---
  grep -q 'qemu:///system' "$HOME_DIR/.config/libvirt/libvirt.conf" 2>/dev/null && check_pass "Default libvirt URI set for ${REAL_USER}" || check_fail "libvirt.conf missing or wrong"
  [ -x /usr/local/bin/vm-create ] && check_pass "vm-create installed" || check_fail "vm-create missing"
  [ -f /etc/sysconfig/libvirt-guests ] && check_pass "libvirt-guests configured" || check_fail "libvirt-guests config missing"
  grep -qE '^(vnc|spice)_listen *= *"0\.0\.0\.0"' /etc/libvirt/qemu.conf 2>/dev/null \
    && check_warn "qemu.conf exposes VNC/SPICE on all interfaces. Use 127.0.0.1." || check_pass "VNC/SPICE not exposed to the network"
  if compgen -G "/etc/clamd.d/*.conf" >/dev/null; then
    grep -qs 'BEGIN virt-manager-setup' /etc/clamd.d/*.conf && check_pass "ClamAV exclusions present" || check_warn "ClamAV exclusions missing"
  fi
  if selinux_active && have_cmd ausearch; then
    ausearch -m avc -ts recent 2>/dev/null | grep -Eq 'svirt|virtqemud|qemu' \
      && check_warn "Recent SELinux denials involving qemu/libvirt. Run: sudo ausearch -m avc -ts recent | audit2why" \
      || check_pass "No recent SELinux denials for qemu/libvirt"
  fi

  log_info "Result: ${VERIFY_PASS} passed, ${VERIFY_WARN} warnings, ${VERIFY_FAIL} failed."
  [ "$VERIFY_FAIL" -eq 0 ]
}

main() {
  if [ "$VERIFY_ONLY" = true ]; then run_verification; exit $?; fi
  sanity_checks
  install -d -m 0700 "$STATE_DIR"
  backup_existing
  reset_previous_setup
  install_packages
  configure_kvm_modules
  setup_services
  setup_storage_pools
  setup_networks
  setup_docker_coexistence
  setup_libvirt_guests
  setup_user_integration
  run_verification
  local rc=$?
  print_summary
  exit "$rc"
}

main

##################################################################################
# Notes
##################################################################################
# Design decisions
# - Section order: "Named Options processing" comes before "Inferred variables" because
#   inferred values (home directory, log directory) depend on --real-user.
# - Modular daemons vs libvirtd: older guides enable a single "libvirtd" service. Fedora
#   now ships one daemon per driver (virtqemud, virtnetworkd, virtstoraged, ...), each
#   started on demand by a systemd socket. This script enables those sockets and
#   disables the old libvirtd units, because running both causes conflicts.
# - Explicit package list instead of the "virtualization" group: the group no longer
#   contains virt-manager on recent Fedora, and a list documents each dependency.
# - qemu:///system, not session: the system connection supports bridged networking,
#   shared storage pools and PCI/USB passthrough. GNOME Boxes uses the per-user session
#   connection, so its VMs are separate from the ones managed here. The libvirt.conf
#   written for the user makes virsh agree with virt-manager.
# - Two storage pools: "default" on the fast/system disk, "bulk" on the roomiest data
#   disk. Disks sharing the root disk's device (btrfs subvolumes such as /home) are
#   ignored. ISOs go to bulk (big, rarely read); cloud image templates stay on fast.
# - btrfs: qcow2 files on copy-on-write filesystems fragment heavily. chattr +C on the
#   pool directory makes new files there non-CoW (this also disables btrfs checksums,
#   compression and snapshots for those files; qcow2 has its own snapshots).
# - Pools outside /var/lib/libvirt need (1) an SELinux rule labelling them virt_image_t
#   and (2) execute permission for user "qemu" on every parent directory; both are
#   applied and recorded in the state directory so a rerun can undo them.
# - Bridge: NAT + isolated networks are always created. A LAN bridge is created only on
#   desktops/servers with an active ethernet connection and no SSH session, because wifi
#   cannot be bridged and laptops roam onto untrusted networks. The bridge copies the
#   card's MAC address and IP settings, keeps the original profile, and rolls back
#   automatically if the network does not return within 45 seconds.
# - DNS paths. NAT guests: the guest asks libvirt's dnsmasq on the virtual bridge, which
#   forwards to the host's resolver (systemd-resolved), so they inherit the host's
#   encrypted DNS and appear in NextDNS as the host. Bridged guests are separate machines
#   on the LAN: they use whatever DNS the router hands out and never touch the host's
#   resolved (its stub listens on loopback only, and should not be exposed to the LAN).
#   Setting NEXTDNS_PROFILE_ID makes vm-create give each guest its own DNS-over-TLS
#   identity (<vm-name>-<profile>.dns.nextdns.io) on NAT and bridged networks.
#   Guests made with virt-manager need the same resolved.conf.d snippet by hand.
# - Docker: this script never changes Docker (no daemon.json, sysctl, br_netfilter or
#   changes to Docker's own firewall chains). Docker's FORWARD policy DROP and
#   br_netfilter would otherwise cut libvirt guest traffic, so a private chain
#   (LIBVIRT-DOCKER) is hooked into DOCKER-USER, the chain Docker reserves for user rules.
#   Its rules are limited to libvirt's bridges; traffic from NAT guests towards Docker
#   networks (docker0 and br-*) is returned to Docker's own rules, so container isolation
#   is unchanged. A Docker network with a custom bridge name outside docker0/br-* is
#   not recognised and would be reachable from NAT guests. With Docker's experimental
#   nftables backend there is no DOCKER-USER chain; the helper then does nothing.
# - Subnets: the virtual networks use 10.77-80.x.x (not 192.168.x) so they cannot collide
#   with Docker's default address pools, kind/Kubernetes ranges or typical home LANs. A
#   candidate is rejected if it overlaps any existing route (Docker bridges, VPNs).
# - br_netfilter + firewalld: with br_netfilter active, bridged frames also traverse the
#   host firewall's FORWARD rules. The script enables forwarding inside the bridge's
#   firewalld zone, and only when Docker/br_netfilter is present.
# - KSM (kernel same-page merging) is deliberately not enabled: it saves RAM across
#   similar guests but enables cross-VM side-channel attacks.
# - No telemetry: libvirt, QEMU and virt-manager do not send usage data, so nothing
#   needs to be disabled. VNC/SPICE listen on 127.0.0.1 by default.
# - Systemd sandboxing is not applied to the libvirt daemons: they must open devices,
#   mount namespaces and network bridges, and hardening them tends to break guests.
# - Windows guests (virtio-win, swtpm) are intentionally not included.
# - Coexistence with a local DNS cache (dnsmasq on 127.0.0.1:53): libvirt's own dnsmasq
#   binds only to the virtual bridge addresses, so both can run. Do not let the system
#   dnsmasq bind to all interfaces.
# - OpenSnitch: guest traffic leaves through the kernel, not through a host process, so
#   it is not attributed to a binary; only host-side helpers (dnsmasq) appear.
# - Android: bVNC / aSPICE (open source, on F-Droid) can open a guest's console over an
#   SSH tunnel to the host. Use "virsh domdisplay NAME" to find the display address.
#
# Replaced approaches
# - "systemctl enable --now libvirtd" (old guides): replaced by the modular sockets.
# - Adding the user to group "kvm": not needed; the logged-in desktop user gets access
#   to /dev/kvm automatically and libvirt's QEMU runs as its own "qemu" user.

##################################################################################
# Useful Links
##################################################################################
# Libvirt daemon architecture (modular daemons): https://libvirt.org/daemons.html
# Fedora change "Libvirt modular daemons": https://fedoraproject.org/wiki/Changes/LibvirtModularDaemons
# Fedora virtualization quick-doc: https://docs.fedoraproject.org/en-US/quick-docs/virtualization-getting-started/
# Fedora Server virtualization guide: https://docs.fedoraproject.org/or/fedora-server/virtualization/installation/
# Libvirt network XML format: https://libvirt.org/formatnetwork.html
# Libvirt QEMU driver (security, SELinux): https://libvirt.org/drvqemu.html
# Libvirt networking handbook (bridged network): https://jamielinux.com/docs/libvirt-networking-handbook/bridged-network.html
# Arch wiki, network bridge: https://wiki.archlinux.org/title/Network_bridge
# NetworkManager nmcli settings reference: https://networkmanager.dev/docs/api/latest/nm-settings-nmcli.html
# cloud-init with libvirt (virt-install --cloud-init): https://docs.cloud-init.io/en/latest/howto/launch_libvirt.html
# firewalld documentation: https://firewalld.org/documentation/
# virt-manager project: https://virt-manager.org/

##################################################################################
# Troubleshooting/Debugging/Testing/Commands
##################################################################################
# Overall check, any time:            sudo bash setup_virt_manager.sh --verify-setup
# Host readiness report:              virt-host-validate qemu
# Which connection am I on:           virsh uri          (expect qemu:///system)
# List everything:                    virsh list --all; virsh net-list --all; virsh pool-list --all
# Daemons and sockets:                systemctl status virtqemud.socket virtnetworkd.socket
#                                     journalctl -u virtqemud -u virtnetworkd --since "10 min ago"
# "Permission denied" on a disk/ISO:  ls -ldZ <dir>; sudo ausearch -m avc -ts recent | audit2why
#                                     sudo restorecon -RFv <dir>
#                                     sudo -u qemu test -r <file> && echo ok   (use: sudo runuser -u qemu -- test -r <file>)
# virt-manager shows no VMs:          check the connection (File > Add Connection > QEMU/KVM) is "system",
#                                     not "session"; check: id | grep libvirt (re-login after group change)
# Guest has no internet (NAT):        virsh net-dumpxml default; firewall-cmd --get-zone-of-interface=virbr0
#                                     cat /proc/sys/net/ipv4/ip_forward   (must be 1)
#                                     grep -r ip_forward /etc/sysctl.d /etc/sysctl.conf
# Docker + libvirt:                   systemctl status libvirt-docker-forward
#                                     sudo iptables -S LIBVIRT-DOCKER; sudo iptables -S DOCKER-USER
#                                     (expect "-A DOCKER-USER -j LIBVIRT-DOCKER"); sudo systemctl restart libvirt-docker-forward
#                                     Remove the integration: sudo systemctl disable --now libvirt-docker-forward
# Bridged guest has no LAN access:    nmcli connection show; ip -br link show master vmbr0
#                                     lsmod | grep br_netfilter; firewall-cmd --zone=<zone> --query-forward
# Revert the bridge by hand:          sudo nmcli connection delete vmbr0-port vmbr0
#                                     sudo nmcli connection modify "<original profile>" connection.autoconnect yes
#                                     sudo nmcli connection up "<original profile>"
# Nested virtualization state:        cat /sys/module/kvm_intel/parameters/nested   (or kvm_amd)
# Disk image info / convert:          qemu-img info disk.qcow2; qemu-img convert -O qcow2 -c in.img out.qcow2
# Cloud image workflow:               put an image in <fast pool>/templates, then:
#                                     vm-create --name lab1 --image <file> --network isolated
# Remove a VM and its disk:           virsh destroy NAME; virsh undefine NAME --remove-all-storage --nvram
# Restore from the script's backup:   ls ~/nb/nb_script_data/backups/virt_manager/