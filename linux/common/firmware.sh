#!/usr/bin/env bash
##################################################################################
# Overview and Usage
##################################################################################
# Firmware updater for Fedora (latest release, any DE). It covers every firmware
# path that exists on a Linux desktop/laptop and reports the devices that have none:
#
#   1. fwupd / LVFS        BIOS/UEFI capsules, Secure Boot dbx, NVMe/SSD, Thunderbolt,
#                          docks, TPM, keyboards/mice/webcams... (whatever LVFS supports)
#   2. dnf firmware pkgs   linux-firmware (Wi-Fi, Bluetooth, GPU blobs, AMD microcode),
#                          microcode_ctl (Intel microcode), fwupd, fwupd-efi, shim
#   3. Inventory report    disks, PCI devices, BIOS age, CPU vulnerability status,
#                          kernel "failed to load firmware" messages, and a table that
#                          says which component has which update path (or none)
#   4. systemd timer       weekly unattended run that applies LOW-RISK updates only
#                          and logs/notifies everything that needs a human (BIOS etc.)
#
# Modes (named options; none are positional):
#   (default)        Set up everything (backup -> reset -> install timer), then run
#                    interactively: show each pending update, ask, apply.
#   --apply          Same, but apply every pending update without asking (BIOS/UEFI
#                    included, if the pre-flash safety checks pass).
#   --scheduled      Used by the systemd timer. No setup, no prompts, never flashes
#                    BIOS/dbx/NVMe/Thunderbolt/TPM; those are logged + ntfy-notified.
#   --verify-setup   Run only the Verification section.
#   --real-user <u>, --filename-timestamp <ts>   Optional; set by a parent script.
#   --ntfy-topic <t>, --ntfy-server <url>        Optional ntfy notification target.
#
# Sample calls (assuming REAL_USER / FILENAME_TIMESTAMP are exported by the caller):
#   (a) all options:
#       ./firmware_update.sh --apply --real-user "$REAL_USER" \
#           --filename-timestamp "$FILENAME_TIMESTAMP" \
#           --ntfy-topic my-private-topic --ntfy-server https://ntfy.sh
#   (b) mandatory only (nothing is mandatory; this is the interactive default):
#       ./firmware_update.sh
#   (c) verification only:
#       ./firmware_update.sh --verify-setup
#   (d) what the timer runs (do not call by hand unless testing):
#       sudo bash /usr/local/libexec/firmware-update/firmware_update.sh --scheduled

set -u -o pipefail
# systemd services may not export USER; the standard variable block below needs it.
export USER="${USER:-root}"

##################################################################################
# User defined variables
##################################################################################
# Everything an operator might want to change lives here. Each can also be set from
# the environment (e.g. NTFY_TOPIC=abc ./firmware_update.sh).

# systemd OnCalendar= expression for the unattended run, plus random jitter so many
# machines do not hit the LVFS CDN at the same second. Examples: daily, weekly,
# "Sun 03:00". See: man systemd.time
FIRMWARE_TIMER_ONCALENDAR="${FIRMWARE_TIMER_ONCALENDAR:-weekly}"
FIRMWARE_TIMER_RANDOM_DELAY="${FIRMWARE_TIMER_RANDOM_DELAY:-1h}"

# ntfy push notifications. Empty topic = notifications disabled. HTTPS is enforced.
# A topic on a public server is readable by anyone who guesses it: pick a long random
# one or use an access token (NTFY_TOKEN) / your own server.
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
NTFY_TOPIC="${NTFY_TOPIC:-}"
NTFY_TOKEN="${NTFY_TOKEN:-}"

# Safety thresholds before any BIOS/UEFI capsule is staged.
ESP_MIN_FREE_MB="${ESP_MIN_FREE_MB:-64}"          # free space on the EFI System Partition
MIN_BATTERY_PERCENT="${MIN_BATTERY_PERCENT:-50}"  # laptops: minimum charge (AC is also required)
SNAPSHOT_KEEP="${SNAPSHOT_KEEP:-3}"               # btrfs pre-flash snapshots to retain
BIOS_STALE_YEARS="${BIOS_STALE_YEARS:-3}"         # warn when BIOS is older than this

# Plugins (fwupd's name for a device driver) that the unattended timer must NEVER
# apply: a failure here can brick the machine, break boot, or lock you out of LUKS.
HIGH_RISK_PLUGINS="uefi_capsule uefi_dbx uefi_pk uefi_kek nvme scsi ata thunderbolt tpm intel_me intel_spi flashrom"

# Package names that count as "firmware plumbing" and are upgraded together.
FIRMWARE_PKG_REGEX='^(linux-firmware(-whence)?|[a-z0-9_+-]+-firmware|microcode_ctl|fwupd(-[a-z0-9-]+)?|libfwupd|fwupd-efi|shim-x64)$'

# Fixed locations (not user-specific).
SERVICE_NAME="firmware-update"
SYSTEMD_UNIT_DIR="/etc/systemd/system"
FW_INSTALL_ROOT="/usr/local/libexec/firmware-update"   # self-contained runtime copy for the timer
FW_CONF_DIR="/etc/firmware-update"
FW_STATE_DIR="/var/lib/firmware-update"
FW_SNAPSHOT_DIR="${FW_STATE_DIR}/snapshots"
FW_PENDING_FILE="${FW_STATE_DIR}/pending_manual.txt"
LVFS_REMOTE_CONF="/etc/fwupd/remotes.d/lvfs.conf"
OPENSNITCH_RULE_FILE="/etc/opensnitchd/rules/allow-fwupd-lvfs.json"

# Mode flags (set by option parsing below).
MODE_APPLY=false
MODE_SCHEDULED=false
MODE_VERIFY=false

# Standard variables. Wrapped in a function so they can be re-derived after the named
# options (--real-user, --filename-timestamp) have changed their inputs.
derive_paths() {
  REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
  FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
  HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
  NBDIR="${HOME_DIR}/nb"
  CODEPROJECTS_DIR="${NBDIR}/CodeProjects" # all code projects
  SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update" # linux setup project
  COMMON_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/common" # setup scripts for general things
  GETTER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commong" # all get_* getters
  HELPER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commonh" # all helper_* helpers
  SECURITY_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/security" # security/privacy setup scripts
  FEDORA_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/fedora" # fedora specific things
  SCRIPT_DATA="${NBDIR}/nb_script_data" # base dir for all stuff created by scripts
  SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"
  SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"
  SCRIPT_DATA_LOGS="${SCRIPT_DATA}/logs"
  # Per-package dirs (package = "firmware"). DOWNLOAD dirs are defined for consistency
  # but unused: fwupd and dnf download and signature-verify their own payloads.
  FIRMWARE_DOWNLOAD_DIR_BASE="${SCRIPT_DATA_DOWNLOADS}/firmware"
  FIRMWARE_CURRENT_DOWNLOAD_DIR="${FIRMWARE_DOWNLOAD_DIR_BASE}/firmware_${FILENAME_TIMESTAMP}"
  FIRMWARE_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/firmware"
  FIRMWARE_CURRENT_BACKUP_DIR="${FIRMWARE_BACKUP_DIR_BASE}/firmware_${FILENAME_TIMESTAMP}"
  FIRMWARE_LOG_DIR_BASE="${SCRIPT_DATA_LOGS}/firmware"
  FIRMWARE_CURRENT_LOG_DIR="${FIRMWARE_LOG_DIR_BASE}/firmware_${FILENAME_TIMESTAMP}"
}
derive_paths

# Absolute path of this script (needed to copy it into the timer's runtime dir).
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

##################################################################################
# Named Options processing
##################################################################################
usage() { sed -n '/^# Firmware updater/,/^#       sudo bash/p' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'; }

ORIGINAL_ARGS=("$@")   # kept so we can re-exec ourselves under sudo with identical options
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)              MODE_APPLY=true; shift ;;
    --scheduled)          MODE_SCHEDULED=true; shift ;;
    --verify-setup)       MODE_VERIFY=true; shift ;;
    --real-user)          REAL_USER="${2:?--real-user needs a value}"; shift 2 ;;
    --filename-timestamp) FILENAME_TIMESTAMP="${2:?--filename-timestamp needs a value}"; shift 2 ;;
    --ntfy-topic)         NTFY_TOPIC="${2:?--ntfy-topic needs a value}"; shift 2 ;;
    --ntfy-server)        NTFY_SERVER="${2:?--ntfy-server needs a value}"; shift 2 ;;
    -h|--help)            usage; exit 0 ;;
    *) printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
derive_paths   # re-derive: REAL_USER / FILENAME_TIMESTAMP may have changed

##################################################################################
# Inferred variables
##################################################################################
# Timer runs use a relocated, self-contained copy (see "Notes" for why): getters and
# helpers come from FW_INSTALL_ROOT and logs/backups go to /var, not $HOME. A
# systemd service has no business reading a user's home directory, and SELinux and
# ProtectHome= would block it anyway.
if [ "$MODE_SCHEDULED" = true ]; then
  GETTER_DIR="${FW_INSTALL_ROOT}/getters"
  HELPER_DIR="${FW_INSTALL_ROOT}/helpers"
  FIRMWARE_LOG_DIR_BASE="/var/log/firmware-update"
  FIRMWARE_CURRENT_LOG_DIR="${FIRMWARE_LOG_DIR_BASE}/firmware_${FILENAME_TIMESTAMP}"
  FIRMWARE_BACKUP_DIR_BASE="${FW_STATE_DIR}/backups"
  FIRMWARE_CURRENT_BACKUP_DIR="${FIRMWARE_BACKUP_DIR_BASE}/firmware_${FILENAME_TIMESTAMP}"
fi

# This script modifies system files, so it must run as root. If it was started as a
# normal user, re-run it under sudo with the same options. (Getters/helpers are not
# available yet, so plain printf is used for errors.)
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || { echo "Run as root (sudo not found)." >&2; exit 1; }
  exec sudo -- "$SCRIPT_PATH" --real-user "$REAL_USER" \
       --filename-timestamp "$FILENAME_TIMESTAMP" "${ORIGINAL_ARGS[@]}"
fi

# Running the installed copy by hand (not via the timer) would make "Reset" delete
# the very file bash is reading. Refuse early with a clear message.
if [ "$MODE_SCHEDULED" = false ] && [ "$MODE_VERIFY" = false ] \
   && [[ "$SCRIPT_PATH" == "$FW_INSTALL_ROOT"/* ]]; then
  echo "Run the full setup from the source tree, not from ${FW_INSTALL_ROOT}." >&2
  exit 1
fi

##################################################################################
# Helpers
##################################################################################
# Shared helpers (logging, dnf, backup). See HELPER_DIR for details of each.
for _h in helper_logging.sh helper_dnf.sh helper_backup.sh; do
  if [ ! -r "${HELPER_DIR}/${_h}" ]; then
    echo "Missing helper: ${HELPER_DIR}/${_h}" >&2; exit 1
  fi
  # shellcheck disable=SC1090
  . "${HELPER_DIR}/${_h}"
done
unset _h

# Terminal keeps its colors; the log file gets the same text with ANSI codes stripped
# (sed -u = unbuffered so a crash does not lose the last lines).
start_logging() {
  mkdir -p "$FIRMWARE_CURRENT_LOG_DIR" "$FW_STATE_DIR"
  chmod 0750 "$FIRMWARE_CURRENT_LOG_DIR"
  chmod 0700 "$FW_STATE_DIR"
  LOG_FILE="${FIRMWARE_CURRENT_LOG_DIR}/firmware_update.log"
  exec > >(tee >(sed -u 's/\x1b\[[0-9;]*[A-Za-z]//g' >>"$LOG_FILE")) 2>&1
  if [ "$MODE_SCHEDULED" = false ]; then
    chown -R "${REAL_USER}:${REAL_USER}" "$FIRMWARE_LOG_DIR_BASE" 2>/dev/null || true
  else
    # Keep only the 12 newest scheduled-run log directories.
    # shellcheck disable=SC2012
    ls -1dt "${FIRMWARE_LOG_DIR_BASE}"/firmware_* 2>/dev/null | tail -n +13 | xargs -r rm -rf
  fi
}

# Getter wrapper: VAR=$(getter get_pc_type) keeps the call style identical everywhere.
getter() { sh "${GETTER_DIR}/${1}.sh"; }

# Ask a yes/no question. Default is NO. Without a terminal the answer is always no,
# so an unattended run can never apply something nobody confirmed.
confirm() {
  local reply
  if [ ! -t 0 ]; then
    log_warn "No terminal for prompt '${1}'; treating as 'no'."
    return 1
  fi
  read -r -p "${1} [y/N] " reply
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ntfy push notification: notify <title> <message> [priority]. No-op if disabled.
notify() {
  [ -n "${NTFY_TOPIC:-}" ] || return 0
  command -v curl >/dev/null 2>&1 || { log_warn "curl missing; ntfy skipped"; return 0; }
  local auth=()
  [ -n "${NTFY_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${NTFY_TOKEN}")
  curl -fsS --proto '=https' --tlsv1.2 --max-time 15 "${auth[@]}" \
       -H "Title: ${1}" -H "Priority: ${3:-default}" -H "Tags: package" \
       -d "${2}" "${NTFY_SERVER%/}/${NTFY_TOPIC}" >/dev/null \
    || log_warn "ntfy notification failed (server/topic/network?)"
}

# Record something a human must do. Written to the log, a state file, and ntfy.
PENDING_MANUAL=()
record_manual() {
  PENDING_MANUAL+=("$1")
  log_warn "MANUAL ACTION REQUIRED: $1"
  printf '%s | %s\n' "$(date -Is)" "$1" >>"$FW_PENDING_FILE"
}

# is_in_list <word> <space separated list>
is_in_list() { [[ " ${2} " == *" ${1} "* ]]; }

# Turn fwupd JSON into pipe-separated rows (python is far more reliable than
# parsing fwupdmgr's human-readable tree output, which is not a stable interface).
#   mode "updates":   id|name|plugin|current|new|urgency|flags|summary
#   mode "inventory": name|plugin|version|updatable|lvfs-supported
fw_json_rows() {
  python3 - "$1" "$2" <<'PY'
import json, sys
path, mode = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path))
except Exception:
    sys.exit(0)                      # empty/invalid JSON == nothing to report
for d in data.get("Devices", []):
    flags = d.get("Flags", []) or []
    if mode == "updates":
        rel = (d.get("Releases") or [{}])[0]
        row = [d.get("DeviceId", ""), d.get("Name", ""), d.get("Plugin", ""),
               d.get("Version", "?"), rel.get("Version", "?"),
               str(rel.get("Urgency", "")), ",".join(flags),
               (rel.get("Summary") or "").replace("|", " ")]
    else:
        row = [d.get("Name", ""), d.get("Plugin", "-"), d.get("Version", "-"),
               "yes" if "updatable" in flags else "no",
               "yes" if "supported" in flags else "no"]
    print("|".join(row))
PY
}

# Power / ESP helpers used by the pre-flash checks.
ac_online() {
  local s found=false
  for s in /sys/class/power_supply/*; do
    [ -r "$s/type" ] || continue
    if [ "$(cat "$s/type")" = "Mains" ]; then
      found=true
      [ "$(cat "$s/online" 2>/dev/null)" = "1" ] && return 0
    fi
  done
  [ "$found" = false ]   # no mains supply registered == desktop/server, counts as AC
}
battery_ok() {
  local s cap
  for s in /sys/class/power_supply/*; do
    [ -r "$s/type" ] && [ "$(cat "$s/type")" = "Battery" ] || continue
    cap="$(cat "$s/capacity" 2>/dev/null || echo 0)"
    if [ "$cap" -lt "$MIN_BATTERY_PERCENT" ]; then
      log_warn "Battery at ${cap}% (< ${MIN_BATTERY_PERCENT}%)"; return 1
    fi
  done
  return 0
}
esp_mount() {
  local m
  for m in /boot/efi /efi /boot; do
    if findmnt -rn -t vfat "$m" >/dev/null 2>&1; then echo "$m"; return 0; fi
  done
  return 1
}

##################################################################################
# Backup
##################################################################################
# Back up every file this script will create, replace or edit, plus places where an
# older hand-made setup might have left similar files.
backup_existing() {
  log_header "Backup of existing firmware-related state"
  mkdir -p "$FIRMWARE_CURRENT_BACKUP_DIR"
  local p
  for p in \
      /etc/fwupd \
      "${SYSTEMD_UNIT_DIR}/${SERVICE_NAME}.service" \
      "${SYSTEMD_UNIT_DIR}/${SERVICE_NAME}.timer" \
      "${SYSTEMD_UNIT_DIR}/fwupd-refresh.service.d" \
      "${SYSTEMD_UNIT_DIR}/fwupd-refresh.timer.d" \
      "${SYSTEMD_UNIT_DIR}/fwupd.service.d" \
      "${HOME_DIR}/.config/systemd/user/${SERVICE_NAME}.service" \
      "${HOME_DIR}/.config/systemd/user/${SERVICE_NAME}.timer" \
      "$FW_INSTALL_ROOT" "$FW_CONF_DIR" "$OPENSNITCH_RULE_FILE"; do
    if [ -e "$p" ]; then
      backup_path "$p" "$FIRMWARE_CURRENT_BACKUP_DIR" "$(basename "$p")"
    fi
  done
  # State records (command output) that help if something must be rolled back.
  backup_record "$FIRMWARE_CURRENT_BACKUP_DIR" fwupd_devices fwupdmgr get-devices --no-unreported-check
  backup_record "$FIRMWARE_CURRENT_BACKUP_DIR" fwupd_remotes fwupdmgr get-remotes
  backup_record "$FIRMWARE_CURRENT_BACKUP_DIR" firmware_packages sh -c "rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' | grep -E '(firmware|microcode|fwupd|shim)' | sort"
  backup_record "$FIRMWARE_CURRENT_BACKUP_DIR" timers systemctl list-timers --all --no-pager
  backup_record "$FIRMWARE_CURRENT_BACKUP_DIR" root_crontab crontab -l
  backup_record "$FIRMWARE_CURRENT_BACKUP_DIR" dmi_bios sh -c "grep -H . /sys/class/dmi/id/bios_* 2>/dev/null"
  log_success "Backup stored in ${FIRMWARE_CURRENT_BACKUP_DIR}"
}

##################################################################################
# Reset
##################################################################################
# Remove everything this script owns so the install below starts clean. NOT removed:
#   - /etc/fwupd/remotes.d/lvfs.conf: owned by the fwupd RPM; deleting it would break
#     fwupd. configure_fwupd_remote() sets the same keys to the same values on every
#     run, which gives the same idempotent result.
#   - ${FW_STATE_DIR} (snapshots, pending list): data, not configuration.
reset_existing() {
  log_header "Reset (removing old timer, runtime copy, config, rules)"
  systemctl disable --now "${SERVICE_NAME}.timer" >/dev/null 2>&1 || true
  systemctl stop "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
  rm -f  "${SYSTEMD_UNIT_DIR}/${SERVICE_NAME}.service" "${SYSTEMD_UNIT_DIR}/${SERVICE_NAME}.timer"
  rm -f  "${HOME_DIR}/.config/systemd/user/${SERVICE_NAME}.service" "${HOME_DIR}/.config/systemd/user/${SERVICE_NAME}.timer"
  rm -rf "${FW_INSTALL_ROOT:?}" "${FW_CONF_DIR:?}"
  rm -f  "$OPENSNITCH_RULE_FILE"
  systemctl daemon-reload
}

##################################################################################
# Security
##################################################################################
# 1) OpenSnitch (only if installed): allow ONLY the fwupd daemon to reach the LVFS
#    hosts on 443. fwupdmgr itself does not download anything; the fwupd daemon does.
# 2) SELinux: restore default labels on the runtime copy (done in install step).
# 3) firewalld: outbound is not filtered by default; no rule is needed.
configure_security() {
  log_header "Security integration"
  if rpm_is_installed opensnitch; then
    install -d -m 0755 "$(dirname "$OPENSNITCH_RULE_FILE")"
    cat >"$OPENSNITCH_RULE_FILE" <<RULE
{
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "name": "allow-fwupd-lvfs",
  "description": "fwupd daemon -> LVFS metadata/firmware CDN over HTTPS only",
  "action": "allow",
  "duration": "always",
  "enabled": true,
  "precedence": false,
  "nolog": false,
  "operator": {
    "type": "list", "operand": "list", "sensitive": false, "data": "",
    "list": [
      {"type": "simple", "operand": "process.path", "sensitive": false, "data": "/usr/libexec/fwupd/fwupd"},
      {"type": "regexp", "operand": "dest.host", "sensitive": false, "data": "^(cdn\\\\.)?fwupd\\\\.org\$"},
      {"type": "simple", "operand": "dest.port", "sensitive": false, "data": "443"}
    ]
  }
}
RULE
    chmod 0644 "$OPENSNITCH_RULE_FILE"
    log_success "OpenSnitch rule written (reload with: systemctl restart opensnitchd)"
  else
    log_info "OpenSnitch not installed; no egress rule written."
  fi
}

##################################################################################
# Main setup
##################################################################################
ensure_prerequisites() {
  log_header "Prerequisites"
  require_fedora
  [ "$(uname -m)" = "x86_64" ] || log_die "x86_64 only (found $(uname -m))"
  local missing=() pkg
  for pkg in fwupd fwupd-efi python3 pciutils util-linux mokutil curl dracut; do
    rpm_is_installed "$pkg" || missing+=("$pkg")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    log_info "Installing: ${missing[*]}"
    dnf_install_packages "${missing[@]}" || log_die "Could not install prerequisites"
  fi
  # btrfs-progs only matters on btrfs roots (used for the pre-flash snapshot).
  if [ "$(findmnt -no FSTYPE /)" = "btrfs" ] && ! rpm_is_installed btrfs-progs; then
    dnf_install_packages btrfs-progs || log_warn "btrfs-progs missing; snapshots disabled"
  fi
}

# Privacy: no success reports to LVFS, no HSI security reports, LVFS enabled.
# (fwupdmgr is additionally always called with --no-unreported-check.)
set_ini_key() {   # set_ini_key <file> <key> <value>
  if grep -q "^${2}=" "$1"; then sed -i "s|^${2}=.*|${2}=${3}|" "$1"; else printf '%s=%s\n' "$2" "$3" >>"$1"; fi
}
configure_fwupd_remote() {
  log_header "fwupd remote (LVFS) privacy configuration"
  if [ ! -f "$LVFS_REMOTE_CONF" ]; then
    log_warn "${LVFS_REMOTE_CONF} not found; fwupd layout differs. Skipping remote hardening."
    return 0
  fi
  set_ini_key "$LVFS_REMOTE_CONF" Enabled true
  set_ini_key "$LVFS_REMOTE_CONF" ReportURI ""                # blank = never upload update reports
  set_ini_key "$LVFS_REMOTE_CONF" SecurityReportURI ""        # blank = never upload HSI reports
  set_ini_key "$LVFS_REMOTE_CONF" AutomaticReports false
  set_ini_key "$LVFS_REMOTE_CONF" AutomaticSecurityReports false
  systemctl restart fwupd.service >/dev/null 2>&1 || true
  log_success "LVFS enabled; reporting/telemetry endpoints blanked"
}

# Install a SELF-CONTAINED runtime copy for the timer: script + getters + helpers.
# Reason: the source tree lives in a home directory, which a hardened system service
# (ProtectHome=true, SELinux init_t) must not read.
install_runtime_and_timer() {
  log_header "Installing runtime copy and systemd timer"
  install -d -m 0755 -o root -g root "$FW_INSTALL_ROOT" "${FW_INSTALL_ROOT}/getters" "${FW_INSTALL_ROOT}/helpers"
  install -m 0755 -o root -g root "$SCRIPT_PATH" "${FW_INSTALL_ROOT}/firmware_update.sh"
  cp -a "${GETTER_DIR}/." "${FW_INSTALL_ROOT}/getters/"
  cp -a "${HELPER_DIR}/." "${FW_INSTALL_ROOT}/helpers/"
  chown -R root:root "$FW_INSTALL_ROOT"
  chmod -R u=rwX,go=rX "$FW_INSTALL_ROOT"
  command -v restorecon >/dev/null 2>&1 && restorecon -R "$FW_INSTALL_ROOT"

  # ntfy settings for unattended runs (0600: may contain a token).
  install -d -m 0700 -o root -g root "$FW_CONF_DIR"
  if [ -n "$NTFY_TOPIC" ]; then
    {
      printf 'NTFY_SERVER=%q\n' "$NTFY_SERVER"
      printf 'NTFY_TOPIC=%q\n'  "$NTFY_TOPIC"
      printf 'NTFY_TOKEN=%q\n'  "$NTFY_TOKEN"
    } >"${FW_CONF_DIR}/ntfy.conf"
    chmod 0600 "${FW_CONF_DIR}/ntfy.conf"
    log_success "ntfy configured for scheduled runs"
  else
    log_info "No ntfy topic given: scheduled runs will only log (pass --ntfy-topic to enable)."
  fi

  # Service: one-shot, low priority, hardened but still able to run dnf/dracut.
  # (ProtectSystem=strict would break dnf, so only the safe subset is used.)
  cat >"${SYSTEMD_UNIT_DIR}/${SERVICE_NAME}.service" <<UNIT
[Unit]
Description=Firmware update run (fwupd + linux-firmware + microcode; low-risk only)
Documentation=man:fwupdmgr(1)
After=network-online.target
Wants=network-online.target
# Never run on battery (laptops). On desktops this condition is true.
ConditionACPower=true

[Service]
Type=oneshot
ExecStart=/usr/bin/bash ${FW_INSTALL_ROOT}/firmware_update.sh --scheduled
Nice=19
IOSchedulingClass=idle
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictRealtime=true
LockPersonality=true
UNIT
  cat >"${SYSTEMD_UNIT_DIR}/${SERVICE_NAME}.timer" <<UNIT
[Unit]
Description=Periodic firmware update run

[Timer]
OnCalendar=${FIRMWARE_TIMER_ONCALENDAR}
RandomizedDelaySec=${FIRMWARE_TIMER_RANDOM_DELAY}
# Persistent=true: if the machine was off at the scheduled time, run at next boot.
Persistent=true

[Install]
WantedBy=timers.target
UNIT
  chmod 0644 "${SYSTEMD_UNIT_DIR}/${SERVICE_NAME}.service" "${SYSTEMD_UNIT_DIR}/${SERVICE_NAME}.timer"
  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}.timer" || log_die "Could not enable timer"
  log_success "Timer enabled: ${FIRMWARE_TIMER_ONCALENDAR} (+ up to ${FIRMWARE_TIMER_RANDOM_DELAY} jitter)"
}

# ---------- dnf firmware packages (linux-firmware, microcode_ctl, fwupd, shim) ------
SNAPSHOT_DONE=false
REBOOT_REQUIRED=false

rebuild_initramfs_if_needed() {
  # Microcode and GPU/Wi-Fi blobs are embedded in the initramfs; package updates do
  # not rebuild it on their own. Rebuild for the RUNNING kernel only, keeping a copy
  # so a failed dracut run can be rolled back.
  local kver img
  kver="$(uname -r)"; img="/boot/initramfs-${kver}.img"
  command -v dracut >/dev/null 2>&1 || { log_warn "dracut not found; rebuild initramfs manually"; return 0; }
  [ -f "$img" ] || { log_warn "${img} not found (non-standard layout); rebuild manually: dracut -f --kver ${kver}"; return 0; }
  mkdir -p "$FIRMWARE_CURRENT_BACKUP_DIR"
  cp -a "$img" "${FIRMWARE_CURRENT_BACKUP_DIR}/initramfs-${kver}.img.bak" || { log_warn "initramfs backup failed; not rebuilding"; return 0; }
  if dracut --force --kver "$kver"; then
    log_success "initramfs rebuilt for ${kver}"
    REBOOT_REQUIRED=true
  else
    log_error "dracut failed; restoring previous initramfs"
    cp -a "${FIRMWARE_CURRENT_BACKUP_DIR}/initramfs-${kver}.img.bak" "$img"
  fi
}

update_firmware_packages() {
  log_header "Distro firmware packages (dnf)"
  local pkgs=() before after rc
  mapfile -t pkgs < <(rpm -qa --qf '%{NAME}\n' | sort -u | grep -E "$FIRMWARE_PKG_REGEX")
  [ "${#pkgs[@]}" -gt 0 ] || { log_warn "No firmware packages found"; return 0; }
  dnf -q check-update --refresh "${pkgs[@]}"; rc=$?      # 100 = updates available, 0 = none
  if [ "$rc" -eq 0 ]; then log_success "Firmware packages are up to date"; return 0; fi
  if [ "$rc" -ne 100 ]; then log_warn "dnf check-update failed (rc=${rc})"; return 0; fi
  if [ "$MODE_APPLY" = false ] && [ "$MODE_SCHEDULED" = false ]; then
    confirm "Upgrade the firmware packages listed above?" || { log_info "Skipped"; return 0; }
  fi
  before="$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' "${pkgs[@]}" | sort)"
  if dnf upgrade -y "${pkgs[@]}"; then
    after="$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' "${pkgs[@]}" | sort)"
    if [ "$before" != "$after" ]; then
      log_success "Firmware packages upgraded"
      rebuild_initramfs_if_needed
    fi
  else
    log_error "dnf upgrade of firmware packages failed"
  fi
}

# ---------- fwupd / LVFS --------------------------------------------------------
# Pre-flash safety checks for BIOS/UEFI capsules. Returns 1 (and logs why) if any fail.
preflight_system_firmware() {
  local fail=0 esp free
  [ -d /sys/firmware/efi ] || { log_warn "Booted in legacy BIOS mode: UEFI capsules cannot work"; return 1; }
  [ -d /sys/firmware/efi/esrt/entries ] || { log_warn "No UEFI ESRT table: firmware does not support capsule updates"; fail=1; }
  ac_online || { log_warn "AC power not connected"; fail=1; }
  battery_ok || fail=1
  if esp="$(esp_mount)"; then
    free="$(df -Pm "$esp" | awk 'NR==2{print $4}')"
    [ "${free:-0}" -ge "$ESP_MIN_FREE_MB" ] || { log_warn "ESP ${esp} has ${free} MB free (< ${ESP_MIN_FREE_MB} MB)"; fail=1; }
  else
    log_warn "EFI System Partition not mounted (/boot/efi): capsule cannot be staged"; fail=1
  fi
  # TPM-bound LUKS (systemd-cryptenroll) can demand the recovery passphrase after a BIOS flash.
  if command -v cryptsetup >/dev/null 2>&1; then
    local dev
    while read -r dev; do
      cryptsetup luksDump "$dev" 2>/dev/null | grep -qi 'systemd-tpm2' \
        && log_warn "${dev}: TPM2-bound LUKS slot; have your recovery passphrase ready after the flash"
    done < <(lsblk -prno NAME,FSTYPE | awk '$2=="crypto_LUKS"{print $1}')
  fi
  return "$fail"
}

# Once per run, right before the first system-firmware flash: copy the ESP and take a
# read-only btrfs snapshot. (The snapshot protects the OS side; it cannot roll back
# a flashed BIOS. See Notes.)
prepare_flash_safety_net() {
  [ "$SNAPSHOT_DONE" = true ] && return 0
  local esp s
  mkdir -p "$FIRMWARE_CURRENT_BACKUP_DIR"
  if esp="$(esp_mount)" && [ -d "${esp}/EFI" ]; then
    backup_path "${esp}/EFI" "$FIRMWARE_CURRENT_BACKUP_DIR" "esp_EFI" && log_success "ESP copied"
  fi
  if [ "$(findmnt -no FSTYPE /)" = "btrfs" ] && command -v btrfs >/dev/null 2>&1; then
    install -d -m 0700 "$FW_SNAPSHOT_DIR"
    if btrfs subvolume snapshot -r / "${FW_SNAPSHOT_DIR}/pre-firmware_${FILENAME_TIMESTAMP}" >/dev/null; then
      log_success "btrfs snapshot: ${FW_SNAPSHOT_DIR}/pre-firmware_${FILENAME_TIMESTAMP}"
    else
      log_warn "btrfs snapshot failed"
    fi
    # shellcheck disable=SC2012
    for s in $(ls -1dt "${FW_SNAPSHOT_DIR}"/pre-firmware_* 2>/dev/null | tail -n +$((SNAPSHOT_KEEP + 1))); do
      btrfs subvolume delete "$s" >/dev/null && log_info "Pruned old snapshot $(basename "$s")"
    done
  else
    log_info "Root is not btrfs: snapshot skipped (ESP copy still made)"
  fi
  SNAPSHOT_DONE=true
}

RESULTS=()
process_fwupd_updates() {
  log_header "fwupd / LVFS updates"
  local tmp updates id name plugin cur new urg flags summ action
  tmp="$(mktemp -d)"; updates="${tmp}/updates.json"
  # refresh exit code 2 = "metadata already current": not an error.
  fwupdmgr refresh --force --no-unreported-check >/dev/null 2>&1 \
    || log_warn "fwupdmgr refresh returned non-zero (offline, or LVFS blocked by DNS filtering?)"
  fwupdmgr get-updates --json --no-unreported-check --no-metadata-check >"$updates" 2>/dev/null
  if [ -z "$(fw_json_rows "$updates" updates)" ]; then
    log_success "fwupd reports no pending firmware updates"
    rm -rf "$tmp"; return 0
  fi
  fw_json_rows "$updates" updates >"${tmp}/rows.txt"
  {
    echo "DEVICE|PLUGIN|CURRENT|NEW|URGENCY"
    awk -F'|' '{print $2"|"$3"|"$4"|"$5"|"$6}' "${tmp}/rows.txt"
  } | column -t -s'|'

  while IFS='|' read -r -u 4 id name plugin cur new urg flags summ; do
    action="ask"
    if [ "$MODE_SCHEDULED" = true ]; then
      if is_in_list "$plugin" "$HIGH_RISK_PLUGINS"; then
        record_manual "${name}: ${cur} -> ${new} needs a manual run (plugin ${plugin} is never applied unattended). Run: sudo ${FW_INSTALL_ROOT}/firmware_update.sh --apply"
        RESULTS+=("${name}|${cur} -> ${new}|deferred (manual)")
        continue
      fi
      action="apply"
    elif [ "$MODE_APPLY" = true ]; then
      action="apply"
    fi

    if [ "$plugin" = "uefi_capsule" ]; then
      if ! preflight_system_firmware; then
        record_manual "${name}: BIOS/UEFI ${cur} -> ${new} NOT applied (pre-flash checks failed, see log above)"
        RESULTS+=("${name}|${cur} -> ${new}|skipped (preflight failed)")
        continue
      fi
    fi

    if [ "$action" = "ask" ]; then
      log_info "${name}: ${cur} -> ${new} [${plugin}] ${summ}"
      confirm "Apply this update?" || { RESULTS+=("${name}|${cur} -> ${new}|skipped by user"); continue; }
    fi

    [ "$plugin" = "uefi_capsule" ] && prepare_flash_safety_net

    log_info "Applying ${name}: ${cur} -> ${new}"
    # systemd-inhibit stops suspend/shutdown/idle from interrupting a flash.
    if systemd-inhibit --what=sleep:shutdown:idle --who=firmware-update --why="Applying firmware: ${name}" \
         fwupdmgr update "$id" -y --no-reboot-check --no-unreported-check --no-metadata-check; then
      RESULTS+=("${name}|${cur} -> ${new}|applied")
      case ",${flags}," in *,needs-reboot,*) REBOOT_REQUIRED=true ;; esac
      [ "$plugin" = "uefi_capsule" ] && REBOOT_REQUIRED=true
    else
      RESULTS+=("${name}|${cur} -> ${new}|FAILED")
      log_error "fwupd failed to update ${name}"
    fi
  done 4<"${tmp}/rows.txt"
  rm -rf "$tmp"
}

##################################################################################
# Inventory (what is where, and what has NO update path)
##################################################################################
report_inventory() {
  log_header "Firmware inventory"
  local tmp inv names rows dmi_v dmi_d dmi_vendor bios_year age sb
  tmp="$(mktemp -d)"; inv="${tmp}/devices.json"; names="${tmp}/names.txt"
  fwupdmgr get-devices --json --no-unreported-check >"$inv" 2>/dev/null
  fw_json_rows "$inv" inventory >"${tmp}/inventory.txt"
  cut -d'|' -f1 "${tmp}/inventory.txt" >"$names"

  dmi_v="$(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo unknown)"
  dmi_d="$(cat /sys/class/dmi/id/bios_date 2>/dev/null || echo unknown)"
  dmi_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo unknown)"
  if [ -d /sys/firmware/efi ]; then
    sb="$(mokutil --sb-state 2>/dev/null | head -n1)"; [ -n "$sb" ] || sb="unknown"
  else
    sb="n/a (legacy BIOS boot)"
  fi

  log_info "System summary"
  {
    echo "ITEM|VALUE"
    echo "BIOS vendor/version|$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null) / ${dmi_v}"
    echo "BIOS date|${dmi_d}"
    echo "Boot mode|$([ -d /sys/firmware/efi ] && echo UEFI || echo 'legacy BIOS')"
    echo "Secure Boot|${sb}"
    echo "TPM device|$([ -e /dev/tpm0 ] && echo present || echo none)"
    echo "CPU|$(getter get_cpu_model)"
    echo "CPU microcode rev|$(awk '/microcode/{print $3; exit}' /proc/cpuinfo)"
    echo "GPU vendors|$(getter get_gpu_vendors)  (NVIDIA driver: $(getter get_nvidia_driver))"
    echo "Chassis|$(getter get_pc_type)"
    echo "Kernel|$(uname -r)"
  } | column -t -s'|'

  bios_year="${dmi_d##*/}"
  if [[ "$bios_year" =~ ^[0-9]{4}$ ]]; then
    age=$(( $(date +%Y) - bios_year ))
    if [ "$age" -ge "$BIOS_STALE_YEARS" ] && ! grep -q '^.*|uefi_capsule|' "${tmp}/inventory.txt"; then
      log_warn "BIOS is ${age} years old and fwupd has no capsule path for it. Check the ${dmi_vendor} support site manually (USB/DOS/Windows flasher)."
    fi
  fi

  log_info "Devices fwupd can see"
  { echo "DEVICE|PLUGIN|VERSION|UPDATABLE|LVFS-SUPPORTED"; cat "${tmp}/inventory.txt"; } | column -t -s'|'

  log_info "Storage devices"
  rows=("DISK|TYPE|MODEL|FIRMWARE|UPDATE PATH")
  local blk n model fw kind rot path
  for blk in /sys/block/*; do
    n="$(basename "$blk")"
    case "$n" in loop*|zram*|dm-*|sr*|md*|ram*) continue ;; esac
    model="$(xargs <"${blk}/device/model" 2>/dev/null)"; [ -n "$model" ] || model="?"
    fw="$(xargs <"${blk}/device/firmware_rev" 2>/dev/null || xargs <"${blk}/device/rev" 2>/dev/null)"; [ -n "$fw" ] || fw="?"
    rot="$(cat "${blk}/queue/rotational" 2>/dev/null)"
    case "$n" in nvme*) kind="NVMe" ;; *) [ "$rot" = "1" ] && kind="HDD" || kind="SSD" ;; esac
    if [ "$model" != "?" ] && grep -qiF -- "${model:0:12}" "$names"; then
      path="fwupd (LVFS)"
    else
      path="NONE via Linux: vendor tool/bootable ISO (check vendor site)"
    fi
    rows+=("${n}|${kind}|${model}|${fw}|${path}")
  done
  printf '%s\n' "${rows[@]}" | column -t -s'|'

  log_info "PCI devices that load firmware blobs (update path: linux-firmware via dnf)"
  {
    echo "DEVICE|KERNEL DRIVER"
    lspci -nnk 2>/dev/null | awk '
      /^[0-9a-f]/ { if (dev) print dev "|" drv; dev=$0; sub(/^[^ ]+ /,"",dev); drv="-" }
      /Kernel driver in use:/ { drv=$5 }
      END { if (dev) print dev "|" drv }' \
      | grep -E 'Network|Ethernet|Wireless|VGA|3D|Display|Audio|Non-Volatile|SATA|Bluetooth'
  } | column -t -s'|'
  if getter get_gpu_vendors | grep -q nvidia; then
    log_info "NVIDIA GPU: the video BIOS cannot be updated from Linux; only the driver package (dnf/RPM Fusion/vendor) changes its behavior."
  fi

  log_info "Kernel messages about missing/failed firmware (this boot)"
  journalctl -k -b --no-pager -g 'Direct firmware load.*failed|failed to load firmware|firmware.*not found' 2>/dev/null | tail -n 15
  [ "${PIPESTATUS[0]}" -eq 0 ] || log_info "(none)"

  log_info "CPU vulnerability status (older CPUs no longer receive microcode fixes)"
  {
    echo "ISSUE|STATUS"
    local f
    for f in /sys/devices/system/cpu/vulnerabilities/*; do
      printf '%s|%s\n' "$(basename "$f")" "$(cut -c1-70 "$f")"
    done
  } | column -t -s'|'

  log_info "Update path per component"
  {
    echo "COMPONENT|PATH|STATUS"
    if grep -q '^.*|uefi_capsule|' "${tmp}/inventory.txt"; then
      echo "BIOS/UEFI|fwupd capsule|automatable (manual in timer)"
    else
      echo "BIOS/UEFI|vendor site only|NO fwupd path"
    fi
    echo "Secure Boot dbx|fwupd uefi_dbx|$(grep -q '|uefi_dbx|' "${tmp}/inventory.txt" && echo available || echo 'not listed')"
    echo "CPU microcode|dnf (microcode_ctl / linux-firmware)|automated"
    echo "Wi-Fi/BT/GPU blobs|dnf (linux-firmware)|automated"
    echo "Disks|see storage table|per device"
    echo "Embedded controller/ME|part of BIOS package|follows BIOS"
    echo "Monitors, USB hubs, misc|fwupd if listed above|otherwise none"
  } | column -t -s'|'
  rm -rf "$tmp"
}

##################################################################################
# Verification
##################################################################################
VERIFY_FAILS=0
vcheck() {   # vcheck <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then log_success "PASS  ${desc}"; else log_error "FAIL  ${desc}"; VERIFY_FAILS=$((VERIFY_FAILS + 1)); fi
}
verify_setup() {
  log_header "Verification"
  vcheck "running on Fedora" test "$(getter get_distro_name)" = "fedora"
  vcheck "fwupdmgr works and daemon answers" fwupdmgr --version
  vcheck "python3 present (JSON parsing)" command -v python3
  vcheck "LVFS remote enabled" grep -q '^Enabled=true' "$LVFS_REMOTE_CONF"
  vcheck "LVFS ReportURI blank" grep -q '^ReportURI=$' "$LVFS_REMOTE_CONF"
  vcheck "LVFS SecurityReportURI blank" grep -q '^SecurityReportURI=$' "$LVFS_REMOTE_CONF"
  vcheck "runtime script installed" test -x "${FW_INSTALL_ROOT}/firmware_update.sh"
  vcheck "runtime script owned by root" test "$(stat -c %U "${FW_INSTALL_ROOT}/firmware_update.sh")" = "root"
  vcheck "bundled getters present" test -r "${FW_INSTALL_ROOT}/getters/get_pc_type.sh"
  vcheck "bundled helpers present" test -r "${FW_INSTALL_ROOT}/helpers/helper_logging.sh"
  vcheck "service unit passes systemd-analyze" systemd-analyze verify "${SYSTEMD_UNIT_DIR}/${SERVICE_NAME}.service"
  vcheck "timer enabled" systemctl is-enabled "${SERVICE_NAME}.timer"
  vcheck "timer active" systemctl is-active "${SERVICE_NAME}.timer"
  if [ -d /sys/firmware/efi ]; then
    vcheck "ESP mounted" esp_mount
    vcheck "capsule support (ESRT) visible" test -d /sys/firmware/efi/esrt/entries
  fi
  if [ -n "$NTFY_TOPIC" ]; then vcheck "ntfy config 0600" test "$(stat -c %a "${FW_CONF_DIR}/ntfy.conf" 2>/dev/null)" = "600"; fi
  if rpm_is_installed opensnitch; then vcheck "OpenSnitch rule present" test -f "$OPENSNITCH_RULE_FILE"; fi
  if command -v lsinitrd >/dev/null 2>&1 && [ -f "/boot/initramfs-$(uname -r).img" ]; then
    vcheck "running kernel's initramfs carries early microcode" sh -c "lsinitrd /boot/initramfs-$(uname -r).img | grep -q 'kernel/x86/microcode'"
  fi
  systemctl list-timers "${SERVICE_NAME}.timer" --no-pager
  if [ "$VERIFY_FAILS" -eq 0 ]; then log_success "All verification checks passed"; else log_error "${VERIFY_FAILS} verification check(s) failed"; fi
  return "$VERIFY_FAILS"
}

##################################################################################
# Run
##################################################################################
start_logging
log_header "Firmware update (${FILENAME_TIMESTAMP}) mode: $( [ "$MODE_SCHEDULED" = true ] && echo scheduled || { [ "$MODE_APPLY" = true ] && echo apply || echo interactive; } )"

# Load ntfy settings saved by the setup run (timer runs have no command-line options).
if [ "$MODE_SCHEDULED" = true ] && [ -r "${FW_CONF_DIR}/ntfy.conf" ]; then
  # shellcheck disable=SC1091
  . "${FW_CONF_DIR}/ntfy.conf"
fi

if [ "$MODE_VERIFY" = true ]; then
  verify_setup; exit $?
fi

if [ "$MODE_SCHEDULED" = false ]; then
  ensure_prerequisites
  backup_existing
  reset_existing
  configure_fwupd_remote
  install_runtime_and_timer
  configure_security
else
  require_fedora
  fwupdmgr --version >/dev/null 2>&1 || log_die "fwupd unavailable"
fi

report_inventory
update_firmware_packages
process_fwupd_updates

log_header "Summary"
if [ "${#RESULTS[@]}" -gt 0 ]; then
  { echo "DEVICE|CHANGE|RESULT"; printf '%s\n' "${RESULTS[@]}"; } | column -t -s'|'
else
  log_info "No fwupd updates were processed"
fi
[ "$REBOOT_REQUIRED" = true ] && log_warn "REBOOT REQUIRED to finish firmware/microcode updates (BIOS capsules flash during reboot; do not power off)."

if [ "${#PENDING_MANUAL[@]}" -gt 0 ] || [ "$REBOOT_REQUIRED" = true ] || [ "${#RESULTS[@]}" -gt 0 ]; then
  msg="$(printf '%s\n' "${RESULTS[@]:-}" "${PENDING_MANUAL[@]:-}")"
  [ "$REBOOT_REQUIRED" = true ] && msg="${msg}"$'\n'"Reboot required."
  notify "Firmware: $(hostname -s)" "$msg" "$([ "${#PENDING_MANUAL[@]}" -gt 0 ] && echo high || echo default)"
fi

[ "$MODE_SCHEDULED" = false ] && verify_setup
log_info "Log: ${LOG_FILE}"
exit 0

##################################################################################
# Notes
##################################################################################
# * Why the timer runs a COPY under /usr/local/libexec: the source tree is in a
#   home directory. SELinux's init_t domain and systemd's ProtectHome= both deny a
#   system service access to it. The copy bundles the getters/helpers it needs.
# * Why the timer never flashes BIOS/dbx/NVMe/Thunderbolt/TPM: these need a human
#   present (AC power, no interruptions, recovery passphrase for TPM-bound LUKS,
#   possible boot-order/Secure Boot side effects). They are logged to
#   ${FW_PENDING_FILE}, the journal, the per-run log and ntfy. Peripherals (mice,
#   keyboards, docks without the risk plugins) are applied automatically.
# * Snapshot honesty: a btrfs snapshot of / protects the OS state (initramfs, /etc);
#   it CANNOT undo a flashed BIOS. The ESP copy is likewise for boot entries only.
#   fwupd rolls back failed capsules on its own where the firmware supports it.
# * Reports/telemetry: fwupd can upload success reports to LVFS and HSI reports.
#   Both endpoints are blanked in the LVFS remote and every call passes
#   --no-unreported-check. The fwupd package may drop a lvfs.conf.rpmnew on upgrade;
#   re-running this script re-applies the settings.
# * fwupdmgr output is not a stable interface; JSON (--json) is parsed instead.
#   Exit code 2 from fwupdmgr means "nothing to do", not an error.
# * Intel microcode: Fedora ships it in microcode_ctl; AMD microcode in
#   amd-ucode-firmware (a linux-firmware subpackage). Microcode is embedded in the
#   initramfs, hence the rebuild for the running kernel after package updates.
#   Sandy Bridge-era and older CPUs no longer receive microcode fixes from Intel;
#   the vulnerability table shows what remains exposed.
# * No downloads are made by this script itself (fwupd and dnf download and verify
#   signatures: PKCS#7/GPG/Jcat for LVFS, GPG for RPMs), so no extra clamscan step.
# * NextDNS: fwupd uses the system resolver (systemd-resolved -> NextDNS profile), so
#   no per-app DNS setting exists. Make sure fwupd.org and cdn.fwupd.org are allowed.
# * Not implemented on purpose: Fedora Server/macOS paths (Fedora Workstation/KDE
#   targeted), automatic reboot, automatic BIOS flashing by timer.

##################################################################################
# Useful Links
##################################################################################
# fwupdmgr man page ................ https://fwupd.github.io/libfwupdplugin/fwupdmgr.html
# fwupd remote config (ReportURI) .. https://www.mankier.com/5/fwupd-remotes.d
# LVFS supported devices ........... https://fwupd.org/lvfs/devices/
# Fedora fwupd quick-doc ........... https://docs.fedoraproject.org/en-US/quick-docs/fwupd/
# Fedora microcode QA test case .... https://fedoraproject.org/wiki/QA:Testcase_microcode_update
# Fedora linux-firmware packages ... https://packages.fedoraproject.org/pkgs/linux-firmware/amd-ucode-firmware
# Kernel microcode loading ......... https://docs.kernel.org/arch/x86/microcode.html
# systemd sandboxing options ....... man systemd.exec
# OpenSnitch rules ................. https://github.com/evilsocket/opensnitch/wiki/Rules

##################################################################################
# Troubleshooting/Debugging/Testing/Commands
##################################################################################
# Is my device supported by fwupd?      fwupdmgr get-devices ; fwupdmgr get-devices --show-all
# Why is an update not offered?         fwupdmgr get-updates -v ; fwupdmgr get-history
# Refresh metadata by hand              fwupdmgr refresh --force
# Platform security (HSI) report        fwupdmgr security
# Daemon log                            journalctl -u fwupd -b
# Timer status / next run               systemctl list-timers firmware-update.timer
# Run the timer job now                 sudo systemctl start firmware-update.service ; journalctl -u firmware-update -e
# Pending manual items                  cat /var/lib/firmware-update/pending_manual.txt
# Latest logs (timer)                   ls -t /var/log/firmware-update/
# UEFI capsule support?                 ls /sys/firmware/efi/esrt/entries ; fwupdtool esp-list
# ESP free space                        df -h /boot/efi
# Capsule did not apply after reboot    journalctl -b -u fwupd-offline-update ; fwupdmgr get-history
# Downloads blocked / refresh fails     resolvectl query cdn.fwupd.org  (NextDNS blocklist?) ; OpenSnitch rule
# Which microcode is loaded?            journalctl -k -b | grep -i microcode ; grep -m1 microcode /proc/cpuinfo
# Early microcode in initramfs?         lsinitrd /boot/initramfs-$(uname -r).img | grep microcode
# Rollback a bad initramfs              copy back the .bak from the backup dir listed in the run log
# List / delete pre-flash snapshots     sudo btrfs subvolume list / ; sudo btrfs subvolume delete <path>
# Re-enable LVFS if disabled            sudo fwupdmgr enable-remote lvfs
# Downgrade (if vendor allows)          fwupdmgr get-releases <id> ; fwupdmgr downgrade <id>
# SELinux denials from the service      sudo ausearch -m avc -ts recent ; sudo sealert -a /var/log/audit/audit.log