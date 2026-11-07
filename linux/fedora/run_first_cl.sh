#!/bin/bash
##################################################################################
# Overview and Usage
##################################################################################
# Overview: bootstraps a freshly installed Fedora. Stages (each one resumable): inventory, backup, reset,
# hostname and network privacy, early firewall, DNF configuration, full upgrade (reboot, then resume), snapshots,
# repositories, hardware-specific codecs/GPU/memory/power/firmware, packages, Flatpak apps, desktop configuration,
# application scripts, AppImages (AppMan), shell extras, MIME defaults, security hardening, automatic updates,
# final snapshot, report and verification. Security stages: sysctl, module blacklist, telemetry, core dumps, key
# permissions, conditional SSH hardening, auditd rules, journald limits, automatic updates, disk-health monitoring.
#
# USAGE-BEGIN
# Fresh-install bootstrap for Fedora (KDE edition primarily; GNOME branches kept).
#
# Mandatory options:
#   --hostname <name>              New machine hostname (also the default NextDNS device name)
#   --nextdns-id <id>              NextDNS configuration ID
#
# Optional options (defaults in brackets):
#   --nextdns-device-id <name>     [hostname]
#   --git-user-email <email>       Git noreply email [empty: warning only]
#   --pc-type <desktop|laptop|server>           [detected]
#   --privacy-level <home|portable|paranoid>    [laptop: paranoid, desktop/server: home]
#   --setup-type <full|light|minimal>           [light]  (minimal = core only, see Profiles)
#   --new-ethernet-name <name>     Rename the active wired connection [empty: no rename]
#   --home-connection <name>       NetworkManager connection to bind to firewalld zone "home"
#                                  [privacy=home: the connection active during install; else none]
#   --home-lan-subnet <cidr>       Trusted LAN subnet passed to firewalld.sh
#                                  [privacy=home: detected; else an unroutable placeholder]
#   --ntfy-server <url>            [https://ntfy.sh]
#   --ntfy-topic <topic>           Enables notifications (run summary, dnf-automatic, smartd, scrub, flatpak)
#   --ntfy-token <token>           Access token (or export NTFY_TOKEN; avoids showing it in `ps`)
#   --has-torrent-client <true|false>   [true for setup-type full, else false]
#   --has-kodi <true|false>        [false]
#   --media-pc <true|false>        Also install the media apps (FreeTube, Spotify, Grayjay, ...) when
#                                  setup-type is not full (full always installs them) [false]
#   --nvidia-driver-stream <auto|current|580xx>   Force the NVIDIA driver branch [auto: from the GPU name]
#   --debug-subscripts <true|false>  Run clamav.sh with DEBUG=1 [true, as in the tested script]
#   --trace <true|false>           set -x: print every command and value (goes to the log, so it can
#                                  show secrets such as an ntfy token) [true while this script is being tested]
#   --verify-setup                 Only run the Verification section and exit
#   --help
#
# Sample call - all options:
#   bash ~/nb/CodeProjects/system_update/linux/fedora/run_first.sh \
#     --hostname myhost --nextdns-id abc123 --nextdns-device-id myhost \
#     --git-user-email "12345+user@users.noreply.github.com" \
#     --pc-type desktop --privacy-level home --setup-type full \
#     --new-ethernet-name wired-home --home-connection wired-home --home-lan-subnet 192.168.1.0/24 \
#     --ntfy-server https://ntfy.sh --ntfy-topic my-long-random-topic --ntfy-token tk_xxx \
#     --has-torrent-client true --has-kodi false --nvidia-driver-stream auto \
#     --media-pc false --debug-subscripts true --trace false
#
# Sample call - mandatory options only:
#   bash ~/nb/CodeProjects/system_update/linux/fedora/run_first.sh --hostname myhost --nextdns-id abc123
#
# Verification only:
#   bash ~/nb/CodeProjects/system_update/linux/fedora/run_first.sh --hostname myhost --nextdns-id abc123 --verify-setup
#
# Profiles:
#   setup-type full    everything
#   setup-type light   desktop apps without the heavy extras
#   setup-type minimal core only: system config, security, shell and CLI tools (no GUI apps)
#   headless           (pc-type server) behaves like minimal. A desktop PC whose desktop cannot be
#                      detected is an error (fix get_desktop_env.sh), as in the earlier script versions.
#   light and minimal  also run linux/fedora/remove_stuff.sh when it exists
#
# If the script stops for a required reboot, reboot and run the SAME command again:
# completed stages are skipped automatically. After a fully successful run the state is cleared,
# so the next run starts fresh.
# USAGE-END

##################################################################################
# Strict mode
##################################################################################
# set -E : ERR trap is inherited by functions, command substitutions and subshells
# set -e : exit immediately if a command fails (inside a stage; see helper_steps.sh for how stages are isolated)
# set -u : unset variables are errors
# set -o pipefail : a pipeline fails if ANY stage fails, not just the last one
# set -x : (debugging only) print every command before running it
# Table of the most common options:
#   set -e / -o errexit    Exit immediately on a command failure
#   set -u / -o nounset    Error when an unset variable is used
#   set -x / -o xtrace     Print each command before running it
#   set -o pipefail        Fail a pipeline if any command in it fails
#   set +e                 Disable an option (plus instead of dash), commonly used for a block of code
#   set -o                 List all options and their state
#   set -- a b c           Set the positional parameters
set -Eeuo pipefail
# inherit_errexit: command substitutions $( ... ) also honor `set -e` (bash >= 4.4)
shopt -s inherit_errexit

##################################################################################
# Read only constants
##################################################################################
# Emulated enums: named constants avoid typos in string comparisons.
readonly PC_TYPE_DESKTOP="desktop"
readonly PC_TYPE_LAPTOP="laptop"
readonly PC_TYPE_HEADLESS_SERVER="server"

readonly PRIVACY_HOME="home"         # Never leaves the home network. Higher trust.
readonly PRIVACY_PORTABLE="portable" # Can leave home. Lower trust.
readonly PRIVACY_PARANOID="paranoid" # Public Wi-Fi (library, airport). Zero trust.

readonly SETUP_TYPE_FULL="full"
readonly SETUP_TYPE_LIGHT="light"
readonly SETUP_TYPE_MINIMAL="minimal" # TBD: bare minimum, would also remove LibreOffice etc.

readonly DESKTOP_KDE="kde"
readonly DESKTOP_GNOME="gnome"
readonly DESKTOP_COSMIC="cosmic"
readonly DESKTOP_LXQT="lxqt"
readonly DESKTOP_HYPRLAND="hyprland"

# Placeholder subnet from RFC 5737 (TEST-NET-1). It is never routable, so using it means
# "no LAN is trusted". Passed to firewalld.sh when no trustworthy home subnet is known.
readonly NO_TRUSTED_SUBNET="192.0.2.0/24"

##################################################################################
# Standard variables and directories
##################################################################################
# These are needed first because the helper files and logging live inside the repo.
REAL_USER="${REAL_USER:-${SUDO_USER:-${USER:-$(id -un)}}}"   # The script refuses to run as root, so this is the invoking user.
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"   # all code projects
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update"   # linux setup project

# Fallback: derive the repo root from this file's location (<repo>/linux/fedora/run_first.sh).
if [ ! -d "${SYSUPDATE_CODE_BASE_DIR}/linux/common" ]; then
  SYSUPDATE_CODE_BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
HELPER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commonh"
GETTER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commong"

DESKTOP_DIR="${NBDIR}/Desktop"
DOCUMENTS_DIR="${NBDIR}/Documents"
DOWNLOADS_DIR="${NBDIR}/Downloads"
VIDEOS_DIR="${NBDIR}/Videos"
PICTURES_DIR="${NBDIR}/Pictures"
MUSIC_DIR="${NBDIR}/Music"
PUBLIC_DIR="${NBDIR}/Public"
TEMPLATES_DIR="${NBDIR}/Templates"
PROJECTS_DIR="${NBDIR}/Projects"
APPIMAGES_DIR="${NBDIR}/AppImages"   # AppMan keeps all AppImages here

SCRIPT_DATA="${NBDIR}/nb_script_data"   # base dir for all stuff created by scripts
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"
SCRIPT_DATA_LOGS="${SCRIPT_DATA}/logs"
SCRIPT_DATA_STATE="${SCRIPT_DATA}/state"           # resumable-run state (this script only)
SCRIPT_DATA_INVENTORY="${SCRIPT_DATA}/inventory"   # pre/post-run system reports (this script only)

# Legacy names. Older sub-scripts still read these, so they stay exported for them (see init_state).
SCRIPT_DATA_DIR="${SCRIPT_DATA}"
SCRIPT_BACKUPS_DIR="${SCRIPT_DATA_BACKUPS}"
SCRIPT_DOWNLOADS_DIR="${SCRIPT_DATA_DOWNLOADS}"
SCRIPT_LOGS_DIR="${SCRIPT_DATA_LOGS}"

# Per-package directories: <PACKAGE>_<X>_DIR_BASE and <PACKAGE>_CURRENT_<X>_DIR for X in DOWNLOAD, BACKUP, LOG.
# The CURRENT directories carry the run timestamp and are used for ALL downloads, backups and logs.
# A function, because the timestamp can change when a previous run is resumed (see load_state_timestamp).
compute_package_dirs() {
  RUN_FIRST_DOWNLOAD_DIR_BASE="${SCRIPT_DATA_DOWNLOADS}/run_first"
  RUN_FIRST_CURRENT_DOWNLOAD_DIR="${RUN_FIRST_DOWNLOAD_DIR_BASE}/run_first_${FILENAME_TIMESTAMP}"
  RUN_FIRST_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/run_first"
  RUN_FIRST_CURRENT_BACKUP_DIR="${RUN_FIRST_BACKUP_DIR_BASE}/run_first_${FILENAME_TIMESTAMP}"
  RUN_FIRST_LOG_DIR_BASE="${SCRIPT_DATA_LOGS}/run_first"
  RUN_FIRST_CURRENT_LOG_DIR="${RUN_FIRST_LOG_DIR_BASE}/run_first_${FILENAME_TIMESTAMP}"
}
compute_package_dirs

##################################################################################
# User defined variables
##################################################################################
# Defaults live here; named options override them (see "Named Options processing").
NEW_HOSTNAME=""                     # MANDATORY. (Not called HOSTNAME: bash manages that variable itself.)
NEXTDNS_ID=""                       # MANDATORY.
NEXTDNS_DEVICE_ID=""                # Default: NEW_HOSTNAME. Lets each device be identified on the NextDNS site.
GIT_USER_EMAIL=""                   # e.g. "<GITHUB PRIVATE EMAIL>@users.noreply.github.com"

PC_TYPE=""                          # desktop | laptop | server. Empty = detected.
PRIVACY_LEVEL=""                    # home | portable | paranoid. Empty = derived from PC_TYPE.
SETUP_TYPE="${SETUP_TYPE_LIGHT}"    # full | light | minimal

NEW_ETHERNET_NAME=""                # Renames the wired connection active at run time (ignored on Wi-Fi).
HOME_CONNECTION=""                  # NetworkManager connection bound to firewalld zone "home".
HOME_LAN_SUBNET=""                  # Trusted LAN subnet for firewalld.sh.

NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
NTFY_TOPIC="${NTFY_TOPIC:-}"        # Empty = notifications disabled.
NTFY_TOKEN="${NTFY_TOKEN:-}"

HAS_TORRENT_CLIENT=""               # Empty = true for setup-type full, else false (qBittorrent is only installed when true).
HAS_KODI=false
MEDIA_PC=""                         # Empty = false. Adds the media apps to non-full setups.

NVIDIA_DRIVER_STREAM="auto"         # auto | current | 580xx
DEBUG_SUBSCRIPTS=true            # clamav.sh was run with DEBUG=1 in the tested script
TRACE=true                          # set -x while the script is being tested; set to false when it is trusted
VERIFY_ONLY=false

DNF_MAX_PARALLEL_DOWNLOADS=5        # DNF5 default is 3; the maximum is 20. 5 is polite to mirrors.
AUTO_UPDATE_TYPE="security"         # dnf5-automatic upgrade_type: security | default
AM_INSTALLER_REF="main"             # Git ref of AM-INSTALLER (pin to a tag for reproducibility)
ZAPZAP_FILESYSTEM="xdg-download"    # Flatpak filesystem access for ZapZap drag-and-drop/attachments. The tested
                                    # script used "home"; widen only if drops from other folders fail.
APPIMAGE_APPS=(obsidian)            # Installed with AppMan (names from the AM catalog)
FLATPAK_REMOVE_FEDORA_REMOTE=true   # Remove the "fedora" flatpak remote so every app comes from Flathub.

# Default applications (the helper skips a .desktop file that does not exist)
DEFAULT_EDITOR_DESKTOP="codium.desktop"
DEFAULT_BROWSER_DESKTOP="brave-browser.desktop"
DEFAULT_VIDEO_DESKTOP="vlc.desktop"
DEFAULT_PDF_DESKTOP="org.kde.okular.desktop"
DEFAULT_MAIL_DESKTOP=""             # e.g. "thunderbird.desktop" or "me.proton.Mail.desktop"; empty = leave unchanged
DEFAULT_TEL_DESKTOP="org.kde.kdeconnect.handler.desktop"   # tel: links -> phone (KDE Connect); skipped if absent
DEFAULT_GEO_DESKTOP="app.organicmaps.desktop.desktop"      # geo: links -> Organic Maps; skipped if absent
DEFAULT_TERMINAL_KDE="alacritty"    # Value for kdeglobals TerminalApplication

# Flatpak application lists (all from Flathub)
FLATPAK_BASE_APPS=(org.signal.Signal com.github.tchx84.Flatseal)
FLATPAK_FULL_APPS=(com.rtosta.zapzap org.telegram.desktop chat.simplex.simplex network.loki.Session
  app.organicmaps.desktop im.riot.Riot org.localsend.localsend_app com.sindresorhus.Caprine
  com.super_productivity.SuperProductivity)
# Installed for full setups, or for any setup with --media-pc true
FLATPAK_MEDIA_APPS=(io.freetubeapp.FreeTube dev.fredol.open-tv com.spotify.Client app.grayjay.Grayjay)
# Not installed (kept as a record): it.mijorus.gearlever (replaced by AppMan; md.obsidian.Obsidian is an AppImage via AppMan), com.bitwarden.desktop,
# io.github.hkdb.Aerion, net.rpdev.OpenTodoList, im.fluffychat.Fluffychat, org.gnome.Fractal,
# io.github.kolunmi.Bazaar, dev.zed.Zed, ca.desrt.dconf-editor

##################################################################################
# Inferred variables
##################################################################################
# Everything below is detected at run time, so the script works on any 64-bit PC (roughly 2008 onward).
infer_system() {
  CPU_CORES="$(infer_getter get_cpu_cores.sh 1)"
  RAM_MB="$(infer_getter get_ram_size.sh 0)"
  RAM_PROFILE="$(infer_getter get_ram_profile.sh mid)"           # low | mid | high
  SSD_PRESENT="$(infer_getter get_ssd_present.sh false)"         # false if any of the key directories is on an HDD
  [ -n "${PC_TYPE}" ] || PC_TYPE="$(infer_getter get_pc_type.sh desktop)"
  DESKTOP="$(infer_getter get_desktop_env.sh "")"
  DISTRO="$(infer_getter get_distro_name.sh "")"
  CPU_MODEL="$(infer_getter get_cpu_model.sh unknown)"
  GPU_VENDORS="$(infer_getter get_gpu_vendors.sh none)"          # e.g. "intel nvidia"
  GPU_NAMES="$(infer_getter get_gpu_names.sh "")"                # one per line
  NVIDIA_DRIVER="$(infer_getter get_nvidia_driver.sh none)"      # proprietary | nouveau | none
  INTEL_GENERATION="$(infer_getter get_intel_gen.sh 0)"          # Core generation: 2 = Sandy Bridge ... 12 = Alder Lake
  CPU_IS_ULV="$(infer_getter get_cpu_is_ulv.sh false)"
  AMD_GPU_CLASS="$(infer_getter get_amd_gpu_class.sh none)"      # none | legacy | modern | discrete
  GPU_TIER="$(infer_getter get_gpu_tier.sh low)"                 # low | mid | high
  IS_ETHERNET="$(infer_getter get_is_ethernet.sh false)"

  # Root filesystem type (btrfs enables snapshots and scrubbing).
  ROOT_FSTYPE="$(findmnt -n -o FSTYPE / 2>/dev/null || echo unknown)"
  # Is this a virtual machine? (SMART monitoring makes no sense there.)
  if have systemd-detect-virt && systemd-detect-virt -q; then IS_VM=true; else IS_VM=false; fi

  # Active network interface, connection and LAN subnet (no python needed).
  ACTIVE_IFACE="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  ACTIVE_CONNECTION=""
  DETECTED_SUBNET=""
  if [ -n "${ACTIVE_IFACE}" ]; then
    ACTIVE_CONNECTION="$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | awk -F: -v d="${ACTIVE_IFACE}" '$NF==d{print $1; exit}')"
    DETECTED_SUBNET="$(ip -4 -o route show dev "${ACTIVE_IFACE}" proto kernel scope link 2>/dev/null | awk '{print $1; exit}')"
  fi

  export CPU_CORES RAM_MB RAM_PROFILE SSD_PRESENT PC_TYPE DESKTOP DISTRO GPU_VENDORS GPU_TIER
}

# Decide which LAN is "home". Trusting whatever network happens to be active during installation
# is unsafe (the install may happen on a cafe network), so detection is only used for desktops
# declared as home devices, or when the active connection IS the declared home connection.
resolve_home_network() {
  # The connection name that will exist AFTER the optional wired-connection rename.
  local active_final="${ACTIVE_CONNECTION}"
  if [ "${IS_ETHERNET}" = true ] && [ -n "${NEW_ETHERNET_NAME}" ]; then active_final="${NEW_ETHERNET_NAME}"; fi

  if [ "${PRIVACY_LEVEL}" = "${PRIVACY_HOME}" ] && [ -z "${HOME_CONNECTION}" ]; then
    HOME_CONNECTION="${active_final}"
  fi
  if [ -z "${HOME_LAN_SUBNET}" ]; then
    if [ -n "${DETECTED_SUBNET}" ] && [ -n "${HOME_CONNECTION}" ] && [ "${HOME_CONNECTION}" = "${active_final}" ]; then
      HOME_LAN_SUBNET="${DETECTED_SUBNET}"
    else
      HOME_LAN_SUBNET="${NO_TRUSTED_SUBNET}"
      log_warn "No trusted home subnet known; using placeholder ${NO_TRUSTED_SUBNET} (no LAN is trusted)."
    fi
  fi
}

##################################################################################
# Named Options processing
##################################################################################
parse_options() {
  local opt val
  while [ $# -gt 0 ]; do
    opt="$1"; shift
    case "$opt" in
      # Flags (no value)
      --verify-setup)     VERIFY_ONLY=true; continue ;;
      --help|-h)          print_usage; exit 0 ;;
      # "--name=value" form
      --*=*)              val="${opt#*=}"; opt="${opt%%=*}" ;;
      # "--name value" form
      --*)                [ $# -ge 1 ] || log_die "Option ${opt} requires a value"; val="$1"; shift ;;
      *)                  log_die "Unknown argument: ${opt} (see --help)" ;;
    esac
    case "$opt" in
      --hostname)              NEW_HOSTNAME="$val" ;;
      --nextdns-id)            NEXTDNS_ID="$val" ;;
      --nextdns-device-id)     NEXTDNS_DEVICE_ID="$val" ;;
      --git-user-email)        GIT_USER_EMAIL="$val" ;;
      --pc-type)               PC_TYPE="$val" ;;
      --privacy-level)         PRIVACY_LEVEL="$val" ;;
      --setup-type)            SETUP_TYPE="$val" ;;
      --new-ethernet-name)     NEW_ETHERNET_NAME="$val" ;;
      --home-connection)       HOME_CONNECTION="$val" ;;
      --home-lan-subnet)       HOME_LAN_SUBNET="$val" ;;
      --ntfy-server)           NTFY_SERVER="$val" ;;
      --ntfy-topic)            NTFY_TOPIC="$val" ;;
      --ntfy-token)            NTFY_TOKEN="$val" ;;
      --has-torrent-client)    HAS_TORRENT_CLIENT="$val" ;;
      --has-kodi)              HAS_KODI="$val" ;;
      --media-pc)              MEDIA_PC="$val" ;;
      --debug-subscripts)      DEBUG_SUBSCRIPTS="$val" ;;
      --nvidia-driver-stream)  NVIDIA_DRIVER_STREAM="$val" ;;
      --trace)                 TRACE="$val" ;;
      *)                       log_die "Unknown option: ${opt} (see --help)" ;;
    esac
  done
}

# Validate user input and fill sensible defaults. Runs after parsing and after inference.
validate_user_variables() {
  prompt_required NEW_HOSTNAME "Hostname (--hostname)"
  prompt_required NEXTDNS_ID "NextDNS configuration ID (--nextdns-id)"
  [[ "${NEW_HOSTNAME}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] \
    || log_die "--hostname must be 1-63 letters, digits or hyphens (not starting/ending with a hyphen)."
  NEXTDNS_DEVICE_ID="${NEXTDNS_DEVICE_ID:-${NEW_HOSTNAME}}"

  case "${SETUP_TYPE}" in
    "${SETUP_TYPE_FULL}"|"${SETUP_TYPE_LIGHT}"|"${SETUP_TYPE_MINIMAL}") ;;
    *) log_die "--setup-type must be full, light or minimal." ;;
  esac

  case "${PC_TYPE}" in
    "${PC_TYPE_DESKTOP}"|"${PC_TYPE_LAPTOP}"|"${PC_TYPE_HEADLESS_SERVER}") ;;
    *) log_die "PC_TYPE '${PC_TYPE}' is invalid (desktop|laptop|server)." ;;
  esac

  # Privacy level: explicit value wins; otherwise a laptop is assumed to roam (paranoid) and
  # a desktop/server to stay home.
  if [ -z "${PRIVACY_LEVEL}" ]; then
    case "${PC_TYPE}" in
      "${PC_TYPE_LAPTOP}") PRIVACY_LEVEL="${PRIVACY_PARANOID}" ;;
      *)                   PRIVACY_LEVEL="${PRIVACY_HOME}" ;;
    esac
  fi
  case "${PRIVACY_LEVEL}" in
    "${PRIVACY_HOME}"|"${PRIVACY_PORTABLE}"|"${PRIVACY_PARANOID}") ;;
    *) log_die "--privacy-level must be home, portable or paranoid." ;;
  esac

  if [ -z "${HAS_TORRENT_CLIENT}" ]; then
    if [ "${SETUP_TYPE}" = "${SETUP_TYPE_FULL}" ]; then HAS_TORRENT_CLIENT=true; else HAS_TORRENT_CLIENT=false; fi
  fi
  case "${NVIDIA_DRIVER_STREAM}" in auto|current|580xx) ;; *) log_die "--nvidia-driver-stream must be auto|current|580xx." ;; esac

  MEDIA_PC="${MEDIA_PC:-false}"

  # Profile: HEADLESS = no supported desktop (or a server); GUI = install graphical stages.
  # A desktop PC whose desktop cannot be identified is an error (same rule as the earlier script versions).
  HEADLESS=false
  if [ "${PC_TYPE}" = "${PC_TYPE_HEADLESS_SERVER}" ]; then
    HEADLESS=true
  else
    case "${DESKTOP}" in
      "${DESKTOP_KDE}"|"${DESKTOP_GNOME}"|"${DESKTOP_COSMIC}"|"${DESKTOP_LXQT}"|"${DESKTOP_HYPRLAND}") ;;
      "") log_die "Desktop not identified. Fix get_desktop_env.sh and run again." ;;
      *)  log_warn "Desktop '${DESKTOP}' has no specific configuration here; generic stages only." ;;
    esac
  fi
  GUI=true
  if [ "${HEADLESS}" = true ] || [ "${SETUP_TYPE}" = "${SETUP_TYPE_MINIMAL}" ]; then GUI=false; fi

  [ -n "${GIT_USER_EMAIL}" ] || log_warn "--git-user-email not provided (git identity will not be configured)."
  [ -n "${NTFY_TOPIC}" ]     || log_info "No --ntfy-topic: notifications are disabled."
}

##################################################################################
# Helpers
##################################################################################
# Reusable helpers live in separate files (helper_<functionality>.sh); see each file's header for usage.
if [ ! -f "${HELPER_DIR}/helper_logging.sh" ]; then
  echo "ERROR: ${HELPER_DIR}/helper_logging.sh not found. Clone the repo to ${SYSUPDATE_CODE_BASE_DIR} first." >&2
  exit 1
fi
# Existing repo helpers first (logging, verified backups, python-based mimeapps editing), then the
# helpers added with this script (step runner, ntfy). helper_download.sh is optional.
for _helper in helper_logging.sh helper_backup.sh helper_mimeapps.sh helper_steps.sh helper_ntfy.sh; do
  [ -f "${HELPER_DIR}/${_helper}" ] || { echo "ERROR: missing ${HELPER_DIR}/${_helper}" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "${HELPER_DIR}/${_helper}"
done
unset _helper
# shellcheck source=/dev/null
[ ! -f "${HELPER_DIR}/helper_download.sh" ] || source "${HELPER_DIR}/helper_download.sh"

# --- Local helpers (specific to this script) ---

# True if an RPM with this exact name is installed.
pkg_installed() { rpm -q "$1" &>/dev/null; }

# True if the given command exists.
have() { command -v "$1" &>/dev/null; }

# "swap": replace $1 with $2 when $1 is installed, otherwise just install $2.
# RPM Fusion documents `dnf swap` for the *-freeworld and ffmpeg replacements because both
# packages provide the same files; a plain install would conflict.
swap_or_install() {
  local old="$1" new="$2"
  if pkg_installed "$new"; then return 0; fi
  if pkg_installed "$old"; then
    sudo dnf swap -y "$old" "$new" --allowerasing
  else
    sudo dnf install -y "$new"
  fi
}

# Write stdin to a root-owned file with a given mode, then fix the SELinux label.
#   write_root_file /etc/foo.conf 644 <<'EOF' ... EOF
write_root_file() {
  local path="$1" mode="${2:-644}"
  sudo install -d -m 755 "$(dirname "$path")"
  sudo tee "$path" >/dev/null
  sudo chmod "$mode" "$path"
  sudo chown root:root "$path"
  if have restorecon; then sudo restorecon -F "$path" 2>/dev/null || true; fi
}

# Create a directory owned by the real user. ~/nb may be a separately mounted data disk that is
# still owned by root on a fresh install, in which case plain mkdir fails and sudo is needed.
make_user_dir() {
  mkdir -p "$1" 2>/dev/null || sudo install -d -o "${REAL_USER}" -g "${REAL_USER}" "$1"
}

# Run a helper from linux/commonh that prints one value. If the helper is missing, use the fallback
# so the rest of the script can still proceed (e.g. on a partially cloned repo).
infer_getter() {
  local script="${GETTER_DIR}/$1" fallback="$2"
  if [ -f "$script" ]; then
    bash "$script" 2>/dev/null || printf '%s' "$fallback"
  else
    log_warn "Helper $1 not found; using fallback '${fallback}'"
    printf '%s' "$fallback"
  fi
}

# Run a repo sub-script as the normal user / as root. Exported variables travel with `env`
# because sudo resets the environment by default (env_reset).
run_sub() {
  local script="${SYSUPDATE_CODE_BASE_DIR}/$1"
  shift
  [ -f "$script" ] || { log_error "Sub-script not found: ${script}"; return 1; }
  bash "$script" "$@"
}
# Like run_sub, but a missing script is only a warning (for scripts that are still being written).
run_sub_optional() {
  if [ ! -f "${SYSUPDATE_CODE_BASE_DIR}/$1" ]; then
    log_warn "Optional sub-script not found yet: $1 (skipped)"
    return 0
  fi
  run_sub "$@"
}
run_sub_root() {
  local script="${SYSUPDATE_CODE_BASE_DIR}/$1"
  shift
  [ -f "$script" ] || { log_error "Sub-script not found: ${script}"; return 1; }
  sudo env "${SUB_ENV[@]}" bash "$script" "$@"
}

# Back up a path (kept under its full original path) with the repo's helper_backup.sh. The helper runs
# as root here so root-only files (NetworkManager connections, /etc/nb, ...) are copied too.
backup_any() {
  { [ -e "$1" ] || [ -L "$1" ]; } || return 0
  sudo env HELPER_DIR="${HELPER_DIR}" bash -c \
    'source "${HELPER_DIR}/helper_logging.sh"; source "${HELPER_DIR}/helper_backup.sh"; backup_path_parents "$1" "$2"' \
    _ "$1" "${RUN_FIRST_CURRENT_BACKUP_DIR}"
}

# True if an application's .desktop file exists (dnf, flatpak system/user, or ~/.local).
desktop_file_exists() {
  local d
  for d in /usr/share/applications /var/lib/flatpak/exports/share/applications \
           "${HOME_DIR}/.local/share/applications" "${HOME_DIR}/.local/share/flatpak/exports/share/applications"; do
    [ -f "${d}/$1" ] && return 0
  done
  return 1
}

# Set a default application with the repo's mimeapps helper, but only if that application exists.
set_default_app() {
  local desktop="$1"
  shift
  [ -n "${desktop}" ] || return 0
  if ! desktop_file_exists "${desktop}"; then
    log_warn "MIME: ${desktop} is not installed; skipping defaults for: $*"
    return 0
  fi
  mimeapps_set_default "${desktop}" "$@"
  log_success "MIME: ${desktop} is now the default for $# type(s)"
}

# Keep the sudo timestamp fresh for the whole (long) run so the password is asked only once.
start_sudo_keepalive() {
  sudo -v || log_die "sudo authentication failed."
  (
    set +x   # no trace spam from the keep-alive loop when --trace is on
    while true; do
      sudo -n true 2>/dev/null || exit 0
      sleep 50
      kill -0 "$$" 2>/dev/null || exit 0   # stop when the main script is gone ($$ is the parent shell's PID)
    done
  ) &
  SUDO_KEEPALIVE_PID=$!
}

cleanup_on_exit() {
  [ -z "${SUDO_KEEPALIVE_PID:-}" ] || kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
}

# Ask for a mandatory value when it was not given as an option and a terminal is attached.
# Without a terminal (cron, CI) a missing value is an error.
prompt_required() {
  local var="$1" label="$2" val=""
  if [ -n "${!var}" ]; then return 0; fi
  if [ -t 0 ]; then
    read -r -p "${label}: " val
    printf -v "${var}" '%s' "${val}"
  fi
  [ -n "${!var}" ] || log_die "${label} is mandatory (pass the option, or run from a terminal to be asked)."
}

print_usage() { sed -n '/^# USAGE-BEGIN/,/^# USAGE-END/p' "${BASH_SOURCE[0]}" | sed '1d;$d;s/^# \{0,1\}//'; }

##################################################################################
# Preflight
##################################################################################
# Order of the early work (each part is a function so main() can sequence them):
#   preflight_root -> preflight_dirs -> setup_logging (may re-exec under script(1)) -> preflight
preflight_root() {
  # Running as root would make every file the script creates root-owned inside $HOME.
  [ "$(id -u)" -ne 0 ] || log_die "Do not run this script as root or with sudo. It calls sudo itself when needed."
  have sudo || log_die "sudo is not installed."
}

# A previous, unfinished run leaves its timestamp in the state file. Adopting it keeps the log, the
# backups and the downloads of one logical run together, even across the reboot in the middle.
load_state_timestamp() {
  STATE_DIR="${SCRIPT_DATA_STATE}"
  STATE_FILE="${STATE_DIR}/run_first.state"
  REBOOT_NOW_FLAG="${STATE_DIR}/reboot_required_now"
  REBOOT_END_FLAG="${STATE_DIR}/reboot_required_at_end"
  RESUMING=false
  if [ -f "${STATE_FILE}" ] && grep -q '^TS=' "${STATE_FILE}"; then
    FILENAME_TIMESTAMP="$(grep -m1 '^TS=' "${STATE_FILE}" | cut -d= -f2)"
    RESUMING=true
  fi
  compute_package_dirs
}

preflight_dirs() {
  local d
  for d in "${NBDIR}" "${CODEPROJECTS_DIR}" "${SCRIPT_DATA}" "${SCRIPT_DATA_BACKUPS}" "${SCRIPT_DATA_DOWNLOADS}" \
           "${SCRIPT_DATA_LOGS}" "${SCRIPT_DATA_STATE}" "${SCRIPT_DATA_INVENTORY}" "${DESKTOP_DIR}" "${DOCUMENTS_DIR}" \
           "${DOWNLOADS_DIR}" "${VIDEOS_DIR}" "${PICTURES_DIR}" "${MUSIC_DIR}" "${PUBLIC_DIR}" "${TEMPLATES_DIR}" \
           "${PROJECTS_DIR}" "${APPIMAGES_DIR}"; do
    make_user_dir "$d"
  done
  # Only the top-level directory is fixed (no recursive chown over a possibly huge data disk).
  [ -O "${NBDIR}" ] || sudo chown "${REAL_USER}:${REAL_USER}" "${NBDIR}"
  chmod 700 "${SCRIPT_DATA_BACKUPS}"   # backups may contain keys and credentials
  load_state_timestamp
  make_user_dir "${RUN_FIRST_CURRENT_LOG_DIR}"
  make_user_dir "${RUN_FIRST_CURRENT_DOWNLOAD_DIR}"
}

# Terminal output must stay colored (progress bars, dnf colors) AND be logged. Piping stdout into
# `tee` makes tools think they are not on a terminal and they drop colors and progress bars.
# script(1) runs the command inside a pseudo-terminal instead, so the display is unchanged while
# everything is recorded. The script re-executes itself once under script(1); RUN_FIRST_UNDER_SCRIPT
# marks the second pass. If script(1) is unavailable, plain tee logging is the fallback.
setup_logging() {
  LOG_FILE="${RUN_FIRST_CURRENT_LOG_DIR}/run_first.log"
  [ -z "${RUN_FIRST_UNDER_SCRIPT:-}" ] || return 0
  have script || sudo dnf install -y util-linux-script >/dev/null 2>&1 || true
  if have script; then
    export RUN_FIRST_UNDER_SCRIPT=1
    # -q quiet, -e return the child's exit code, -f flush after every write, -a append, -c command
    exec script -qefa -c "$(printf '%q ' bash "$(readlink -f "${BASH_SOURCE[0]}")" "${ORIG_ARGS[@]}")" "${LOG_FILE}"
  fi
  log_warn "script(1) not available; logging through tee (some tools drop colors and progress bars)."
  exec > >(tee -a "${LOG_FILE}") 2>&1
}

preflight() {
  trap cleanup_on_exit EXIT
  trap 'log_error "Error at line ${LINENO}: ${BASH_COMMAND}"' ERR
  start_sudo_keepalive
  log_info "Logging to ${LOG_FILE}"

  # Distro check (the script is Fedora specific)
  local os_id
  os_id="$(. /etc/os-release && echo "${ID:-unknown}")"
  [ "${os_id}" = "fedora" ] || log_die "This script targets Fedora (detected: ${os_id})."
  FEDORA_VERSION="$(rpm -E %fedora)"
  [ "${FEDORA_VERSION}" -ge 43 ] 2>/dev/null || log_warn "Written for Fedora 44 (DNF5); detected Fedora ${FEDORA_VERSION}."
  have dnf || log_die "dnf not found."

  have curl || sudo dnf install -y curl
  curl -fsSI --max-time 15 https://download.fedoraproject.org >/dev/null 2>&1 || log_die "No internet access (cannot reach download.fedoraproject.org)."
}

# Find every repo sub-script this file references and report the missing ones BEFORE anything is changed,
# instead of discovering them half way through the run. The list is read from this file itself, so it
# cannot drift from the calls below. (Some references are conditional on the profile; a warning is enough.)
preflight_subscript_inventory() {
  local f missing=0 self
  self="$(readlink -f "${BASH_SOURCE[0]}")"
  while read -r f; do
    [ -f "${SYSUPDATE_CODE_BASE_DIR}/${f}" ] && continue
    if [ "${f}" = "linux/fedora/remove_stuff.sh" ]; then
      log_info "linux/fedora/remove_stuff.sh does not exist yet (work in progress); that stage will be skipped."
      continue
    fi
    log_warn "Referenced sub-script not found: ${f}"
    missing=$((missing + 1))
  done < <(grep -oE 'linux/[a-z_]+/[A-Za-z0-9_]+\.sh' "${self}" | sort -u)
  [ "${missing}" -eq 0 ] || log_warn "${missing} referenced sub-script(s) missing: those stages will FAIL and be retried on the next run."
}

# Non-fatal warnings about things this script cannot fix after installation.
preflight_warnings() {
  if have getenforce && [ "$(getenforce)" != "Enforcing" ]; then
    log_warn "SELinux is not Enforcing ($(getenforce)). Fix with: sudo setenforce 1 and /etc/selinux/config."
  fi
  if ! lsblk -rno TYPE 2>/dev/null | grep -qx crypt; then
    if [ "${PC_TYPE}" = "${PC_TYPE_LAPTOP}" ]; then
      log_warn "No LUKS-encrypted volume found on a LAPTOP. Full-disk encryption can only be chosen at install time."
    else
      log_info "No LUKS-encrypted volume detected."
    fi
  fi
  if have mokutil && mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
    log_info "Secure Boot is enabled (proprietary NVIDIA modules will need MOK enrollment)."
  fi
  if [ "${DISTRO}" != "fedora" ]; then log_warn "get_distro_name.sh reported '${DISTRO}' (expected fedora)."; fi
  log_info "Profile: GUI=${GUI}, HEADLESS=${HEADLESS}, setup-type=${SETUP_TYPE}"
}

# Create the state file for a new run and export the environment handed to every sub-script.
init_state() {
  if [ "${RESUMING}" = true ]; then
    log_info "Resuming previous run (${FILENAME_TIMESTAMP}); completed stages will be skipped."
  else
    echo "TS=${FILENAME_TIMESTAMP}" > "${STATE_FILE}"
  fi
  rm -f "${REBOOT_NOW_FLAG}" "${REBOOT_END_FLAG}"

  # Sub-scripts default their own FILENAME_TIMESTAMP from the environment, so all backups of one run
  # land under the same timestamp. Legacy variable names stay exported for older sub-scripts.
  export REAL_USER HOME_DIR NBDIR FILENAME_TIMESTAMP SYSUPDATE_CODE_BASE_DIR SCRIPT_DATA PRIVACY_LEVEL SETUP_TYPE
  export SCRIPT_DATA_DOWNLOADS SCRIPT_DATA_BACKUPS SCRIPT_DATA_LOGS
  export SCRIPT_DATA_DIR SCRIPT_BACKUPS_DIR SCRIPT_DOWNLOADS_DIR SCRIPT_LOGS_DIR
  export RUN_FIRST_CURRENT_DOWNLOAD_DIR RUN_FIRST_CURRENT_BACKUP_DIR RUN_FIRST_CURRENT_LOG_DIR
  SUB_ENV=("REAL_USER=${REAL_USER}" "HOME_DIR=${HOME_DIR}" "NBDIR=${NBDIR}" "FILENAME_TIMESTAMP=${FILENAME_TIMESTAMP}"
           "SYSUPDATE_CODE_BASE_DIR=${SYSUPDATE_CODE_BASE_DIR}" "SCRIPT_DATA=${SCRIPT_DATA}"
           "SCRIPT_DATA_DOWNLOADS=${SCRIPT_DATA_DOWNLOADS}" "SCRIPT_DATA_BACKUPS=${SCRIPT_DATA_BACKUPS}"
           "SCRIPT_DATA_LOGS=${SCRIPT_DATA_LOGS}" "SCRIPT_DATA_DIR=${SCRIPT_DATA_DIR}"
           "SCRIPT_BACKUPS_DIR=${SCRIPT_BACKUPS_DIR}" "SCRIPT_DOWNLOADS_DIR=${SCRIPT_DOWNLOADS_DIR}"
           "SCRIPT_LOGS_DIR=${SCRIPT_LOGS_DIR}"
           "PRIVACY_LEVEL=${PRIVACY_LEVEL}" "SETUP_TYPE=${SETUP_TYPE}" "PC_TYPE=${PC_TYPE}" "DESKTOP=${DESKTOP}")
  if [ "${DEBUG_SUBSCRIPTS}" = true ]; then SUB_ENV+=("DEBUG=1"); fi
}

request_reboot_now()    { touch "${REBOOT_NOW_FLAG}"; }
request_reboot_at_end() { touch "${REBOOT_END_FLAG}"; }

##################################################################################
# Inventory (what the machine looked like before and after)
##################################################################################
# A plain-text snapshot of hardware, storage, network, repositories and installed packages. Written
# before any change and again at the end, so problems can be traced with a simple diff.
write_inventory() {
  local out="$1"
  {
    echo "== Date / kernel / OS";    date; uname -a; cat /etc/os-release
    echo "== CPU and memory";        lscpu; free -h
    echo "== Block devices";         lsblk -f; findmnt --real
    echo "== Graphics (PCI)";        lspci -nnk | grep -A3 -Ei 'vga|3d|display'
    echo "== Network";               ip -br addr; nmcli -f NAME,UUID,TYPE,DEVICE,ACTIVE connection show
    echo "== firewalld";             sudo firewall-cmd --get-default-zone; sudo firewall-cmd --get-active-zones
    echo "== Repositories";          dnf repolist --all
    echo "== Enabled unit files";    systemctl list-unit-files --state=enabled --no-pager
    echo "== Flatpak";               flatpak remotes; flatpak list
    echo "== Security state";        getenforce; mokutil --sb-state; lsblk -rno TYPE | sort | uniq -c
    echo "== Detected by run_first.sh"
    echo "PC_TYPE=${PC_TYPE} DESKTOP=${DESKTOP} RAM_MB=${RAM_MB} RAM_PROFILE=${RAM_PROFILE} SSD_PRESENT=${SSD_PRESENT}"
    echo "GPU_VENDORS=${GPU_VENDORS} GPU_TIER=${GPU_TIER} INTEL_GENERATION=${INTEL_GENERATION} AMD_GPU_CLASS=${AMD_GPU_CLASS}"
  } > "${out}" 2>&1 || true   # one missing tool must not stop the report
  chmod 600 "${out}"
}

step_inventory() {
  make_user_dir "${SCRIPT_DATA_INVENTORY}"
  write_inventory "${SCRIPT_DATA_INVENTORY}/pre_run_${FILENAME_TIMESTAMP}.txt"
  rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > "${SCRIPT_DATA_INVENTORY}/packages_pre_${FILENAME_TIMESTAMP}.txt"
  log_success "Inventory written to ${SCRIPT_DATA_INVENTORY}"
}

##################################################################################
# Backup
##################################################################################
# Everything this script touches is copied (with its full path) before any change, including the
# locations where older setups (previous versions of this script, manual edits) may have left files.
step_backup() {
  log_info "Backing up to ${RUN_FIRST_CURRENT_BACKUP_DIR}"
  make_user_dir "${RUN_FIRST_CURRENT_BACKUP_DIR}"
  local p
  for p in \
    /etc/hostname /etc/hosts /etc/machine-info \
    /etc/dnf /etc/yum.repos.d /etc/pki/rpm-gpg \
    /etc/NetworkManager/conf.d /etc/NetworkManager/system-connections \
    /etc/sysctl.d /etc/sysctl.conf /etc/modprobe.d /etc/systemd/zram-generator.conf /etc/systemd/zram-generator.conf.d \
    /etc/systemd/journald.conf /etc/systemd/journald.conf.d /etc/systemd/coredump.conf /etc/systemd/coredump.conf.d \
    /etc/ssh /etc/audit \
    /etc/smartd.conf /etc/snapper/configs /etc/nb \
    /etc/systemd/system/nb-flatpak-update.service /etc/systemd/system/nb-flatpak-update.timer \
    /etc/systemd/system/nb-btrfs-scrub.service /etc/systemd/system/nb-btrfs-scrub.timer \
    /usr/local/bin/nb-ntfy /usr/local/bin/nb-smartd-notify \
    /etc/firewalld /etc/selinux/config /etc/default/grub \
    /var/lib/flatpak/overrides /opt/firefox \
    "${HOME_DIR}/.mozilla" "${HOME_DIR}/.local/share/applications/firefox.desktop" \
    "${HOME_DIR}/.config/mimeapps.list" "${HOME_DIR}/.local/share/applications/mimeapps.list" \
    "${HOME_DIR}/.config/user-dirs.dirs" "${HOME_DIR}/.config/user-dirs.locale" \
    "${HOME_DIR}/.config/kdeglobals" "${HOME_DIR}/.config/baloofilerc" "${HOME_DIR}/.config/PlasmaUserFeedback" \
    "${HOME_DIR}/.local/share/flatpak/overrides" \
    "${HOME_DIR}/.zshrc" "${HOME_DIR}/.zprofile" "${HOME_DIR}/.bashrc" "${HOME_DIR}/.bash_profile" "${HOME_DIR}/.profile" \
    "${HOME_DIR}/.gitconfig" "${HOME_DIR}/.config/starship.toml" "${HOME_DIR}/.config/atuin" "${HOME_DIR}/.config/mpv" \
    "${HOME_DIR}/.config/zsh" "${HOME_DIR}/.config/VSCodium/User/settings.json" \
    "${HOME_DIR}/.config/appman" "${HOME_DIR}/.local/bin/appman" "${HOME_DIR}/.local/bin/nbupdate" \
    "${HOME_DIR}/.config/systemd/user" "${HOME_DIR}/.config/autostart"; do
    backup_any "$p"
  done
  sudo chown -R "${REAL_USER}:${REAL_USER}" "${RUN_FIRST_CURRENT_BACKUP_DIR}"
  chmod -R go-rwx "${RUN_FIRST_CURRENT_BACKUP_DIR}"
}

##################################################################################
# Reset
##################################################################################
# Previous configuration written by this script (or by its old versions) is deleted so every run
# starts from a known state instead of patching leftovers. Package-owned files and user data
# (snapper snapshots, flatpak data, AppImages) are never deleted: they are data, not configuration.
# AppMan itself (program and config) IS reset, so it is reinstalled with the AppImage directory that
# is set in this script; the AppImages inside that directory stay and are managed again afterwards.
step_reset() {
  # Stop units owned by this script
  local unit
  for unit in nb-flatpak-update.timer nb-btrfs-scrub.timer; do
    sudo systemctl disable --now "${unit}" 2>/dev/null || true
  done
  systemctl --user disable --now nb-appimage-update.timer 2>/dev/null || true

  sudo rm -f \
    /etc/dnf/libdnf5.conf.d/90-nb.conf \
    /etc/dnf/repos.override.d/99-nb-countme.repo \
    /etc/dnf/automatic.conf \
    /etc/dnf/libdnf5-plugins/actions.d/snapper.actions \
    /etc/NetworkManager/conf.d/00-nb-privacy.conf \
    /etc/NetworkManager/conf.d/00-macrandomize.conf \
    /etc/sysctl.d/90-nb-hardening.conf /etc/sysctl.d/90-nb-zram.conf \
    /etc/modprobe.d/90-nb-blacklist.conf \
    /etc/systemd/journald.conf.d/90-nb.conf /etc/systemd/coredump.conf.d/90-nb.conf \
    /etc/ssh/sshd_config.d/10-nb-hardening.conf /etc/audit/rules.d/90-nb.rules \
    /etc/systemd/zram-generator.conf \
    /etc/systemd/system/nb-flatpak-update.service /etc/systemd/system/nb-flatpak-update.timer \
    /etc/systemd/system/nb-btrfs-scrub.service /etc/systemd/system/nb-btrfs-scrub.timer \
    /usr/local/bin/nb-ntfy /usr/local/bin/nb-smartd-notify /etc/nb/ntfy.env

  rm -f "${HOME_DIR}/.local/bin/nbupdate" "${HOME_DIR}/.config/zsh/nb-extras.zsh" \
        "${HOME_DIR}/.config/autostart/org.kde.akregator-nb.desktop" \
        "${HOME_DIR}/.config/systemd/user/nb-appimage-update.service" "${HOME_DIR}/.config/systemd/user/nb-appimage-update.timer" \
        "${HOME_DIR}/.local/bin/appman"
  rm -rf "${HOME_DIR}/.config/appman"
  # Remove only the block this script appended to .zshrc (between its markers)
  if [ -f "${HOME_DIR}/.zshrc" ]; then
    sed -i '/# >>> nb-extras >>>/,/# <<< nb-extras <<</d' "${HOME_DIR}/.zshrc"
  fi

  # The previous version of this script rewrote /etc/dnf/dnf.conf. Remove only the lines it added;
  # Fedora's own lines stay untouched.
  if [ -f /etc/dnf/dnf.conf ]; then
    sudo sed -i -e '/^deltarpm=/d' -e '/^fastestmirror=/d' -e '/^defaultyes=/d' -e '/^max_parallel_downloads=/d' /etc/dnf/dnf.conf
  fi
  sudo systemctl daemon-reload
  systemctl --user daemon-reload 2>/dev/null || true
}

##################################################################################
# Stage: network and early firewall
##################################################################################
# The hostname is set FIRST so DHCP, mDNS and logs never announce the installer's default name.
step_hostname() {
  sudo hostnamectl set-hostname "${NEW_HOSTNAME}"
  log_success "Hostname: $(hostnamectl --static)"
}

step_ethernet_rename() {
  if [ "${IS_ETHERNET}" != true ] || [ -z "${NEW_ETHERNET_NAME}" ]; then
    log_info "No wired connection rename requested."; return 0
  fi
  if [ -z "${ACTIVE_CONNECTION}" ] || [ "$(nmcli -g connection.type connection show "${ACTIVE_CONNECTION}")" != "802-3-ethernet" ]; then
    log_warn "Active connection is not a wired connection; not renaming."; return 0
  fi
  sudo nmcli connection modify "${ACTIVE_CONNECTION}" connection.id "${NEW_ETHERNET_NAME}"
  log_success "Renamed '${ACTIVE_CONNECTION}' to '${NEW_ETHERNET_NAME}'"
}

# MAC address and DHCP identity policy by privacy level.
#   home     : Wi-Fi MAC stable per saved network (survives DHCP reservations), wired MAC unchanged.
#   portable : Wi-Fi MAC derived from the network name (stable-ssid): the same on every visit to the same
#              SSID, different across SSIDs; hostname not sent to DHCP.
#   paranoid : fresh random MAC for every connection, hostname not sent.
# On a home network that filters by MAC address, use the real MAC for that profile instead:
#   nmcli connection modify "<ssid>" wifi.cloned-mac-address permanent
step_network_privacy() {
  local wifi_mac eth_mac hostname_lines=""
  case "${PRIVACY_LEVEL}" in
    "${PRIVACY_HOME}")     wifi_mac="stable";      eth_mac="preserve" ;;
    "${PRIVACY_PORTABLE}") wifi_mac="stable-ssid"; eth_mac="stable" ;;
    "${PRIVACY_PARANOID}") wifi_mac="random";      eth_mac="random" ;;
  esac
  if [ "${PRIVACY_LEVEL}" != "${PRIVACY_HOME}" ]; then
    hostname_lines=$'ipv4.dhcp-send-hostname=0\nipv6.dhcp-send-hostname=0'
  fi

  write_root_file /etc/NetworkManager/conf.d/00-nb-privacy.conf 644 <<EOF
# Managed by run_first.sh (privacy level: ${PRIVACY_LEVEL})
[device]
# Randomize the MAC used while merely scanning for Wi-Fi networks
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=${wifi_mac}
ethernet.cloned-mac-address=${eth_mac}
# Temporary IPv6 addresses (RFC 4941) in addition to the stable one
ipv6.ip6-privacy=2
${hostname_lines}
EOF
  # "reload" re-reads configuration WITHOUT dropping the current connection (restart would).
  sudo nmcli general reload || log_warn "nmcli reload failed; changes apply after reboot."
  log_success "NetworkManager privacy policy written. Existing profiles pick it up when reconnected."
}

# Fedora's default firewalld zone (FedoraWorkstation) opens TCP/UDP 1025-65535. Switch to the
# stricter "public" zone immediately so the long installation does not run exposed. The detailed
# per-application rules are applied at the end by firewalld.sh.
step_firewall_baseline() {
  sudo systemctl enable --now firewalld
  sudo firewall-cmd --set-default-zone=public
  if ! systemctl is-active --quiet sshd; then
    sudo firewall-cmd --permanent --zone=public --remove-service=ssh 2>/dev/null || true
  fi
  # Bind the home connection to the "home" zone: the zone follows the NETWORK PROFILE, so a laptop
  # taken to a cafe is back in "public" automatically, with no subnet hard-coding.
  if [ -n "${HOME_CONNECTION}" ]; then
    local conn="${HOME_CONNECTION}"   # a renamed wired connection already carries its new name here
    if nmcli -g connection.id connection show "${conn}" &>/dev/null; then
      sudo nmcli connection modify "${conn}" connection.zone home
      [ -z "${ACTIVE_IFACE}" ] || sudo firewall-cmd --zone=home --change-interface="${ACTIVE_IFACE}" || true
      log_success "Connection '${conn}' bound to firewalld zone 'home'"
    else
      log_warn "Home connection '${conn}' not found in NetworkManager; zone binding skipped."
    fi
  fi
  sudo firewall-cmd --reload
  log_success "Default firewalld zone: $(sudo firewall-cmd --get-default-zone)"
}

##################################################################################
# Stage: DNF configuration, unwanted packages, full upgrade
##################################################################################
# A drop-in file is used instead of rewriting /etc/dnf/dnf.conf, so Fedora's own defaults survive
# package updates. (deltarpm and fastestmirror are DNF4-only options and are not written.)
step_dnf_config() {
  write_root_file /etc/dnf/libdnf5.conf.d/90-nb.conf 644 <<EOF
# Managed by run_first.sh
[main]
max_parallel_downloads=${DNF_MAX_PARALLEL_DOWNLOADS}
# Default answer to prompts is yes. This does NOT skip prompts; -y is still passed explicitly.
defaultyes=True
# Third-party repos (VSCodium, Brave, ...) are sometimes down; do not let one break every upgrade.
skip_if_unavailable=True
installonly_limit=3
clean_requirements_on_remove=True
color=always
EOF
  # Fedora's repo files set countme=1 per repo, and per-repo values beat [main], so countme=false in
  # dnf.conf has no effect. The override directory applies to every repo.
  write_root_file /etc/dnf/repos.override.d/99-nb-countme.repo 644 <<'EOF'
# Managed by run_first.sh - disable the anonymous Fedora "countme" request
[*]
countme=0
EOF
}

# DNF5 fails the whole transaction if any argument is not installed, so only installed packages are passed.
step_remove_unwanted_packages() {
  local candidates=(totem yelp gnome-tour gnome-connections) p
  local to_remove=()
  candidates+=(firefox)   # LibreWolf, Brave, Tor and Mullvad browsers are installed by their own scripts
  for p in "${candidates[@]}"; do
    if pkg_installed "$p"; then to_remove+=("$p"); fi
  done
  if [ "${#to_remove[@]}" -gt 0 ]; then
    sudo dnf remove -y "${to_remove[@]}"
  else
    log_info "None of the unwanted packages are installed."
  fi
  # Leftovers from a manual Firefox install or an older Fedora profile (already backed up).
  sudo rm -rf /opt/firefox
  rm -f "${HOME_DIR}/.local/share/applications/firefox.desktop"
  rm -rf "${HOME_DIR}/.mozilla"
}

# A fresh ISO install is weeks or months behind. Upgrading BEFORE building kernel modules or
# swapping codecs avoids compiling the NVIDIA module for a kernel that is about to be replaced.
step_system_upgrade() {
  sudo dnf upgrade --refresh -y
  local newest
  newest="$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -1)"
  if [ -n "${newest}" ] && [ "${newest}" != "$(uname -r)" ]; then
    log_warn "A newer kernel (${newest}) was installed; a reboot is needed before the hardware stages."
    request_reboot_now
  fi
}

##################################################################################
# Stage: snapshots (btrfs + snapper)
##################################################################################
# Timeshift cannot manage Fedora's default btrfs layout (it requires Ubuntu-style @ and @home
# subvolumes), so snapper is used. libdnf5's "actions" plugin takes pre/post snapshots around
# every dnf transaction. (python3-dnf-plugin-snapper is a DNF4 plugin and does nothing on DNF5.)
step_snapshots() {
  if [ "${ROOT_FSTYPE}" != "btrfs" ]; then log_info "Root is ${ROOT_FSTYPE}, not btrfs; snapshots skipped."; return 0; fi
  sudo dnf install -y snapper libdnf5-plugin-actions btrfs-assistant

  if ! sudo snapper list-configs 2>/dev/null | grep -qw root; then sudo snapper -c root create-config /; fi
  # Pre/post snapshots cover package changes; hourly timeline snapshots would only add I/O on HDDs.
  sudo snapper -c root set-config TIMELINE_CREATE=no NUMBER_CLEANUP=yes NUMBER_LIMIT=20 NUMBER_LIMIT_IMPORTANT=5

  local home_cfg=false
  if [ "$(findmnt -n -o TARGET -T /home)" = "/home" ] && [ "$(findmnt -n -o FSTYPE -T /home)" = "btrfs" ]; then
    if ! sudo snapper list-configs 2>/dev/null | grep -qw home; then sudo snapper -c home create-config /home; fi
    sudo snapper -c home set-config TIMELINE_CREATE=no NUMBER_CLEANUP=yes NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=3
    home_cfg=true
  else
    log_info "/home is not a separate btrfs mount; only the root config is created."
  fi

  # Hook definition: record the dnf command line, create a "pre" snapshot, then a matching "post".
  write_root_file /etc/dnf/libdnf5-plugins/actions.d/snapper.actions 644 <<'EOF'
# Managed by run_first.sh - snapper pre/post snapshots around dnf transactions
pre_transaction::::/usr/bin/sh -c echo\ "tmp.cmd=$(ps\ -o\ command\ --no-headers\ -p\ '${pid}')"
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_root=$(snapper\ -c\ root\ create\ -t\ pre\ -p\ -d\ '${tmp.cmd}')"
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre_root}"\ ]\ &&\ snapper\ -c\ root\ create\ -t\ post\ --pre-number\ "${tmp.snapper_pre_root}"\ -d\ "${tmp.cmd}"
EOF
  if [ "${home_cfg}" = true ]; then
    sudo tee -a /etc/dnf/libdnf5-plugins/actions.d/snapper.actions >/dev/null <<'EOF'
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_home=$(snapper\ -c\ home\ create\ -t\ pre\ -p\ -d\ '${tmp.cmd}')"
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre_home}"\ ]\ &&\ snapper\ -c\ home\ create\ -t\ post\ --pre-number\ "${tmp.snapper_pre_home}"\ -d\ "${tmp.cmd}"
EOF
  fi
  sudo systemctl enable --now snapper-cleanup.timer
  sudo snapper -c root create -d "run_first: after upgrade, before configuration" || log_warn "Baseline snapshot failed."
}

##################################################################################
# Stage: repositories
##################################################################################
step_repos() {
  if ! pkg_installed rpmfusion-free-release || ! pkg_installed rpmfusion-nonfree-release; then
    sudo dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
  fi
  # AppStream metadata so Discover can list RPM Fusion software
  sudo dnf install -y rpmfusion-free-appstream-data rpmfusion-nonfree-appstream-data || log_warn "appstream-data packages unavailable."
  # Cisco OpenH264 repo (normally already enabled by default)
  sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1 || true
  # Opt-in definitions for third-party repos (disabled until enabled one by one)
  sudo dnf install -y fedora-workstation-repositories

  sudo dnf install -y flatpak
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  # Fedora can ship a *filtered* flathub (a subset of apps); remove the filter.
  sudo flatpak remote-modify --no-filter --enable flathub || true
  if [ "${FLATPAK_REMOVE_FEDORA_REMOTE}" = true ] && flatpak remotes --system --columns=name 2>/dev/null | grep -qx fedora; then
    if flatpak list --app --columns=origin 2>/dev/null | grep -qx fedora; then
      log_warn "Apps are installed from the 'fedora' flatpak remote; leaving it in place."
    else
      sudo flatpak remote-delete fedora
    fi
  fi
}

##################################################################################
# Stage: hardware (codecs, GPU, memory, power, firmware)
##################################################################################
has_vendor() { [[ " ${GPU_VENDORS} " == *" $1 "* ]]; }

# ffmpeg and the multimedia group come from RPM Fusion; Fedora's ffmpeg-free lacks patented codecs.
step_hw_codecs() {
  if [ "${GUI}" != true ]; then log_info "Headless/minimal profile: codecs skipped."; return 0; fi
  swap_or_install ffmpeg-free ffmpeg
  # Group install with weak dependencies off avoids pulling a second, redundant codec stack.
  sudo dnf group install -y multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin \
    || log_warn "dnf group install multimedia failed (group id or syntax changed?). See Troubleshooting."
  sudo dnf install -y gstreamer1-plugin-openh264 mozilla-openh264
}

# Hardware video acceleration, chosen from the detected GPU instead of installing everything.
#   Intel Core gen 5+ (Broadwell and newer) : intel-media-driver (iHD)
#   Intel Core gen 2-4 (Sandy to Haswell)   : libva-intel-driver (i965)
#   AMD GCN/RDNA                            : mesa VA-API + VDPAU "freeworld" (adds H.264/H.265)
#   AMD legacy (TeraScale)                  : VDPAU only (no VA-API on the radeon driver)
step_hw_gpu_video() {
  if [ "${GUI}" != true ]; then log_info "Headless/minimal profile: GPU video skipped."; return 0; fi
  if [ "${GPU_VENDORS}" = "none" ]; then log_info "No GPU detected."; return 0; fi
  sudo dnf install -y libva-utils
  local vendors v gen
  read -ra vendors <<< "${GPU_VENDORS}"
  for v in "${vendors[@]}"; do
    case "$v" in
      intel)
        gen="${INTEL_GENERATION//[^0-9]/}"; gen="${gen:-0}"
        if [ "$gen" -ge 5 ] || [ "$gen" -eq 0 ]; then   # 0 = unknown/new Intel naming: assume modern
          sudo dnf install -y intel-media-driver
        else
          sudo dnf install -y libva-intel-driver
        fi
        sudo dnf install -y intel-gpu-tools ;;
      amd)
        case "${AMD_GPU_CLASS}" in
          modern|discrete)
            swap_or_install mesa-va-drivers mesa-va-drivers-freeworld
            swap_or_install mesa-vdpau-drivers mesa-vdpau-drivers-freeworld ;;
          legacy)
            swap_or_install mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
            sudo dnf install -y vdpauinfo ;;
        esac ;;
    esac
  done
}

# Map the NVIDIA GPU name to the driver branch that supports it on Fedora 44.
#   Turing and newer (RTX, GTX 16xx) : current driver (akmod-nvidia)
#   Maxwell/Pascal/Volta (GTX 750, 9xx, 10xx, Titan X, MX1xx/2xx) : legacy 580xx branch
#   Kepler (GTX 6xx/7xx)             : 470xx, which has no Wayland support -> unsupported on KDE 44
detect_nvidia_stream() {
  local n
  n="$(printf '%s\n' "${GPU_NAMES}" | grep -i nvidia | head -1)"
  if   grep -Eiq 'RTX|GTX ?16[0-9]{2}' <<< "$n"; then echo current
  elif grep -Eiq 'GTX ?(9[0-9]{2}|10[0-9]{2}|750|745|TITAN X)|GT ?10[0-9]{2}|MX ?[12][0-9]{2}|Quadro ?[MP][0-9]' <<< "$n"; then echo 580xx
  elif grep -Eiq 'G[TX]+ ?[67][0-9]{2}' <<< "$n"; then echo 470xx
  else echo unknown
  fi
}

step_hw_nvidia() {
  if ! has_vendor nvidia; then log_info "No NVIDIA GPU."; return 0; fi
  if [ "${GUI}" != true ]; then log_info "Headless/minimal profile: NVIDIA driver skipped."; return 0; fi
  local stream="${NVIDIA_DRIVER_STREAM}"
  [ "$stream" != auto ] || stream="$(detect_nvidia_stream)"
  log_info "NVIDIA stream: ${stream} (GPU: $(printf '%s' "${GPU_NAMES}" | grep -i nvidia | head -1))"

  local pkgs=()
  case "$stream" in
    current) pkgs=(akmod-nvidia xorg-x11-drv-nvidia-cuda)
             if pkg_installed akmod-nvidia-580xx; then
               sudo dnf remove -y akmod-nvidia-580xx xorg-x11-drv-nvidia-580xx xorg-x11-drv-nvidia-580xx-cuda
             fi ;;
    580xx)   pkgs=(akmod-nvidia-580xx xorg-x11-drv-nvidia-580xx xorg-x11-drv-nvidia-580xx-cuda)
             if pkg_installed akmod-nvidia; then sudo dnf remove -y akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda; fi ;;
    470xx)   log_warn "Kepler GPU: the 470xx driver has no Wayland support and Fedora 44 KDE is Wayland-only. Staying on nouveau."; return 0 ;;
    *)       log_warn "NVIDIA GPU not recognized for automatic selection. Re-run with --nvidia-driver-stream current|580xx."; return 0 ;;
  esac

  # Secure Boot: the akmods-built module must be signed with a key the firmware trusts (MOK).
  if have mokutil && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    sudo dnf install -y akmods mokutil openssl kmodtool
    [ -f /etc/pki/akmods/certs/public_key.der ] || sudo kmodgenca -a
    if ! mokutil --test-key /etc/pki/akmods/certs/public_key.der 2>&1 | grep -qi "already enrolled"; then
      log_warn "Secure Boot: enter a ONE-TIME password now; at the next boot choose 'Enroll MOK' and type it."
      sudo mokutil --import /etc/pki/akmods/certs/public_key.der
    fi
  fi

  sudo dnf install -y "${pkgs[@]}" nvidia-vaapi-driver
  # Build the kernel module now instead of at first boot (the build takes minutes).
  sudo akmods --force --kernels "$(uname -r)" || log_warn "akmods build reported a problem; check: journalctl -u akmods"
  request_reboot_at_end
}

# zram swap and VM tuning by RAM size. Fedora's default is min(ram, 8192); smaller machines
# benefit from compressing more, large machines barely need swap.
step_hw_memory() {
  sudo dnf install -y zram-generator-defaults
  local zsize swappiness
  case "${RAM_PROFILE}" in
    low)  zsize="min(ram, 8192)";     swappiness=180 ;;
    mid)  zsize="min(ram / 2, 4096)"; swappiness=180 ;;
    *)    zsize="min(ram / 4, 4096)"; swappiness=100 ;;
  esac
  write_root_file /etc/systemd/zram-generator.conf 644 <<EOF
# Managed by run_first.sh (RAM profile: ${RAM_PROFILE}, ${RAM_MB} MB)
[zram0]
zram-size = ${zsize}
compression-algorithm = zstd
EOF
  # swappiness > 100 is valid on kernels >= 5.8 and tells the kernel that swapping to RAM-backed
  # zram is cheaper than dropping page cache. page-cluster=0 disables swap read-ahead (useless for zram).
  write_root_file /etc/sysctl.d/90-nb-zram.conf 644 <<EOF
# Managed by run_first.sh
vm.swappiness=${swappiness}
vm.page-cluster=0
EOF
  sudo sysctl --system >/dev/null
  log_success "zram: ${zsize}, zstd; applied fully after reboot."
}

# Periodic TRIM tells an SSD which blocks are free (keeps writes fast and wear even). Harmless elsewhere,
# so it is only enabled when a fast disk is present.
step_hw_storage() {
  if [ "${SSD_PRESENT}" != true ]; then log_info "No SSD detected; fstrim.timer not enabled."; return 0; fi
  sudo systemctl enable --now fstrim.timer
}

# Laptops: tuned (with the power-profiles-daemon-compatible tuned-ppd) is Fedora's default since 41.
# TLP would conflict with it, so it is only reported.
step_hw_power() {
  if [ "${PC_TYPE}" != "${PC_TYPE_LAPTOP}" ]; then log_info "Not a laptop; power tuning skipped."; return 0; fi
  if pkg_installed tlp; then log_warn "TLP is installed and conflicts with tuned-ppd; choose one."; fi
  sudo dnf install -y tuned tuned-ppd
  sudo systemctl enable --now tuned.service
  sudo systemctl enable --now tuned-ppd.service || log_warn "tuned-ppd service could not be enabled."
  if grep -qi intel <<< "${CPU_MODEL}"; then
    sudo dnf install -y thermald
    sudo systemctl enable --now thermald.service || true   # exits harmlessly on CPUs without needed sensors
  fi
}

# Firmware: only REPORT updates. Applying them reboots into the updater and is the owner's call.
step_hw_firmware() {
  sudo dnf install -y fwupd
  if [ "${IS_VM}" = true ]; then log_info "Virtual machine; no firmware to update."; return 0; fi
  sudo fwupdmgr refresh --force || log_warn "fwupd could not refresh metadata."
  if sudo fwupdmgr get-updates; then   # exit code 2 = nothing to update
    log_warn "Firmware updates are available. Apply with: sudo fwupdmgr update"
  fi
}

##################################################################################
# Stage: packages
##################################################################################
step_packages() {
  # Core tools for every profile (headless and minimal included)
  sudo dnf install -y git curl jq gh fzf fastfetch smartmontools
  if [ "${GUI}" != true ]; then return 0; fi

  sudo dnf install -y flatpak xdg-user-dirs
  if [ "${SETUP_TYPE}" = "${SETUP_TYPE_FULL}" ]; then
    sudo dnf install -y ksystemlog htop keepassxc vlc
  fi
  if [ "${HAS_TORRENT_CLIENT}" = true ]; then sudo dnf install -y qbittorrent; fi

  case "${DESKTOP}" in
    "${DESKTOP_GNOME}")
      sudo dnf install -y gnome-tweaks
      [ "${SETUP_TYPE}" != "${SETUP_TYPE_FULL}" ] || sudo dnf install -y gparted liferea quiterss ;;
    "${DESKTOP_KDE}")
      sudo dnf install -y kde-gtk-config plasma-browser-integration kasts
      # Apps to try out (not essential, so a missing package is skipped instead of failing the stage)
      sudo dnf install -y --skip-unavailable kalarm kbackup ;;
    *) log_info "No desktop-specific packages for '${DESKTOP}'." ;;
  esac
}

##################################################################################
# Stage: flatpak apps and sandbox permissions
##################################################################################
step_flatpak_apps() {
  if [ "${GUI}" != true ]; then log_info "Headless/minimal profile: Flatpak apps skipped."; return 0; fi
  # Explicit remote ("flathub") so installation never depends on remote ordering.
  sudo flatpak install --system -y --noninteractive flathub "${FLATPAK_BASE_APPS[@]}"
  if [ "${SETUP_TYPE}" = "${SETUP_TYPE_FULL}" ]; then
    sudo flatpak install --system -y --noninteractive flathub "${FLATPAK_FULL_APPS[@]}"
    case "${DESKTOP}" in
      "${DESKTOP_KDE}")   sudo flatpak install --system -y --noninteractive flathub io.github.amit9838.mousam ;;
      "${DESKTOP_GNOME}") sudo flatpak install --system -y --noninteractive flathub com.mattjakeman.ExtensionManager ;;
    esac
  fi
  # Media apps: always part of a full setup; other setups get them with --media-pc true.
  if [ "${SETUP_TYPE}" = "${SETUP_TYPE_FULL}" ] || [ "${MEDIA_PC}" = true ]; then
    sudo flatpak install --system -y --noninteractive flathub "${FLATPAK_MEDIA_APPS[@]}"
  fi

  # Secret storage for Signal (a system-wide override, as in the earlier script versions)
  if [ "${DESKTOP}" = "${DESKTOP_KDE}" ]; then
    sudo flatpak override --env=SIGNAL_PASSWORD_STORE=kwallet6 org.signal.Signal
    # Element: allow KWallet and the Secret Service API (per-user override)
    flatpak override --user im.riot.Riot --talk-name=org.kde.kwalletd6 --talk-name=org.freedesktop.secrets
  else
    sudo flatpak override --env=SIGNAL_PASSWORD_STORE=gnome-libsecret org.signal.Signal
  fi
  # `sudo flatpak override --user` (used by the earlier script) wrote root's overrides, which have no
  # effect for the real user, so this one runs as the user. Least privilege: ZAPZAP_FILESYSTEM defaults to
  # the Downloads folder instead of all of $HOME; set it to "home" for the old behavior.
  if [ "${SETUP_TYPE}" = "${SETUP_TYPE_FULL}" ]; then
    flatpak override --user --filesystem="${ZAPZAP_FILESYSTEM}" com.rtosta.zapzap
  fi
}

##################################################################################
# Stage: AppImages with AppMan
##################################################################################
# AppMan is the user-mode edition of AM (the AppImage manager): no root needed, apps live in one directory
# (APPIMAGES_DIR), desktop entries and updates are handled by AppMan itself.
#   Add an app:         appman -i <name>      (alias: nbappadd)
#   Update all apps:    appman -u             (alias: nbappupdate; also part of `nbupdate` and a weekly user timer)
# The installer is downloaded to this run's download directory and scanned with clamscan BEFORE it is run,
# instead of piping a download into a shell. Runs after clamav.sh so clamscan is installed.
# appman_location only takes effect while ~/.config/appman/appman-config does not exist (the reset step
# removes it), and AM-INSTALLER supports "-i appman" non-interactively since AM 10.4.
step_appimages() {
  if [ "${GUI}" != true ]; then log_info "Headless/minimal profile: AppImages skipped."; return 0; fi
  make_user_dir "${APPIMAGES_DIR}"
  local installer="${RUN_FIRST_CURRENT_DOWNLOAD_DIR}/AM-INSTALLER"
  local url="https://raw.githubusercontent.com/ivan-hc/AM/${AM_INSTALLER_REF}/AM-INSTALLER"

  if declare -F download_file >/dev/null 2>&1; then
    download_file "${url}" "${installer}"
  else
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --connect-timeout 15 -o "${installer}" "${url}"
  fi
  [ -s "${installer}" ] || log_die "AM-INSTALLER download is empty."
  if declare -F scan_downloaded_file >/dev/null 2>&1; then
    scan_downloaded_file "${installer}"
  elif have clamscan; then
    clamscan --no-summary "${installer}" || log_die "clamscan flagged AM-INSTALLER."
  else
    log_warn "clamscan not available; AM-INSTALLER was NOT scanned."
  fi

  chmod 700 "${installer}"
  appman_location="${APPIMAGES_DIR}" "${installer}" -i appman
  have appman || export PATH="${HOME_DIR}/.local/bin:${PATH}"
  have appman || log_die "appman was not installed (expected in ~/.local/bin)."

  local app
  for app in "${APPIMAGE_APPS[@]}"; do
    appman -i "${app}" || log_warn "AppMan could not install '${app}' (name in the AM catalog?)."
  done
}

##################################################################################
# Stage: shell extras (fzf, update command, aliases)
##################################################################################
# Written to a separate file that .zshrc sources through one marked block, so the zsh scripts' own
# configuration is never rewritten. The block is removed again by the reset step.
step_shell_extras() {
  make_user_dir "${HOME_DIR}/.local/bin"
  make_user_dir "${HOME_DIR}/.config/zsh"

  # --- nbupdate: one manual command for every package source ---
  cat > "${HOME_DIR}/.local/bin/nbupdate" <<'EOF'
#!/usr/bin/env bash
# nbupdate - update every package source on this machine (managed by run_first.sh)
#   dnf packages, Flatpak apps, AppImages (AppMan) and a firmware update check.
# Automatic updates also run on timers (dnf5-automatic, nb-flatpak-update.timer, nb-appimage-update.timer);
# this command is for updating on demand.
set -u
echo "==> dnf";      sudo dnf upgrade --refresh
echo "==> Flatpak";  flatpak update -y && flatpak uninstall --unused -y
if command -v appman >/dev/null 2>&1; then echo "==> AppImages (AppMan)"; appman -u; fi
if command -v fwupdmgr >/dev/null 2>&1; then
  echo "==> Firmware (check only; apply with: sudo fwupdmgr update)"
  sudo fwupdmgr refresh --force; sudo fwupdmgr get-updates
fi
echo "==> Reboot needed? (compare running and newest kernel)"
newest="$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -1)"
[ "${newest}" = "$(uname -r)" ] && echo "No" || echo "Yes: newest installed kernel is ${newest}"
EOF
  chmod 755 "${HOME_DIR}/.local/bin/nbupdate"

  # --- zsh extras: fzf integration and aliases ---
  cat > "${HOME_DIR}/.config/zsh/nb-extras.zsh" <<'EOF'
# nb-extras.zsh - managed by run_first.sh (sourced from ~/.zshrc)
# ~/.local/bin holds nbupdate and AppMan
case ":${PATH}:" in *":${HOME}/.local/bin:"*) ;; *) export PATH="${HOME}/.local/bin:${PATH}" ;; esac

# fzf: Ctrl-T (file picker), Alt-C (cd into a directory), Ctrl-R (history search)
if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline'
  # Prefer fd, then ripgrep, for fast listings that skip .git; plain `find` is the fallback fzf uses itself
  if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="${FZF_DEFAULT_COMMAND}"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  elif command -v rg >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
    export FZF_CTRL_T_COMMAND="${FZF_DEFAULT_COMMAND}"
  fi
  # If atuin is installed, keep its Ctrl-R history search instead of fzf's
  (( ${+widgets[atuin-search]} )) && bindkey '^r' atuin-search
fi

alias nbappadd='appman -i'       # add an AppImage from the AM catalog
alias nbappupdate='appman -u'    # update all AppImages
EOF
  chmod 644 "${HOME_DIR}/.config/zsh/nb-extras.zsh"

  if [ -f "${HOME_DIR}/.zshrc" ]; then
    sed -i '/# >>> nb-extras >>>/,/# <<< nb-extras <<</d' "${HOME_DIR}/.zshrc"   # idempotent: drop an older block first
    cat >> "${HOME_DIR}/.zshrc" <<'EOF'

# >>> nb-extras >>>
[ -f "${HOME}/.config/zsh/nb-extras.zsh" ] && source "${HOME}/.config/zsh/nb-extras.zsh"
# <<< nb-extras <<<
EOF
  else
    log_warn "${HOME_DIR}/.zshrc does not exist (zsh.sh not run yet?); source ${HOME_DIR}/.config/zsh/nb-extras.zsh manually."
  fi

  # --- weekly AppImage update (user timer: AppMan needs no root) ---
  if [ "${GUI}" = true ]; then
    make_user_dir "${HOME_DIR}/.config/systemd/user"
    cat > "${HOME_DIR}/.config/systemd/user/nb-appimage-update.service" <<'EOF'
# Managed by run_first.sh
[Unit]
Description=Update AppImages managed by AppMan

[Service]
Type=oneshot
ExecStart=%h/.local/bin/appman -u
EOF
    cat > "${HOME_DIR}/.config/systemd/user/nb-appimage-update.timer" <<'EOF'
# Managed by run_first.sh
[Unit]
Description=Weekly AppImage update

[Timer]
OnCalendar=weekly
RandomizedDelaySec=3h
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now nb-appimage-update.timer \
      || log_warn "Could not enable the user timer (no user session bus?). Run: systemctl --user enable --now nb-appimage-update.timer"
  fi
}

##################################################################################
# Stage: desktop configuration, user directories, MIME
##################################################################################
step_desktop_config() {
  if [ "${GUI}" != true ]; then log_info "Headless/minimal profile: desktop configuration skipped."; return 0; fi
  # Register the ~/nb directories as XDG user directories on EVERY desktop (previously GNOME only).
  have xdg-user-dirs-update || sudo dnf install -y xdg-user-dirs
  xdg-user-dirs-update --set DESKTOP "${DESKTOP_DIR}"
  xdg-user-dirs-update --set DOWNLOAD "${DOWNLOADS_DIR}"
  xdg-user-dirs-update --set DOCUMENTS "${DOCUMENTS_DIR}"
  xdg-user-dirs-update --set MUSIC "${MUSIC_DIR}"
  xdg-user-dirs-update --set PICTURES "${PICTURES_DIR}"
  xdg-user-dirs-update --set VIDEOS "${VIDEOS_DIR}"
  xdg-user-dirs-update --set PUBLICSHARE "${PUBLIC_DIR}"
  xdg-user-dirs-update --set TEMPLATES "${TEMPLATES_DIR}"

  case "${DESKTOP}" in
    "${DESKTOP_GNOME}")
      if have gsettings; then gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'; fi ;;
    "${DESKTOP_KDE}")
      if have kwriteconfig6; then
        # File indexing on a spinning disk costs a lot of I/O for little benefit.
        if [ "${SSD_PRESENT}" != true ]; then
          kwriteconfig6 --file baloofilerc --group "Basic Settings" --key "Indexing-Enabled" false
          if have balooctl6; then balooctl6 disable || true; fi
        fi
        # Low-end GPU: halve the animation duration (1 = default, 0 = none).
        if [ "${GPU_TIER}" = "low" ]; then
          kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 0.5
        fi
        # KDE's opt-in usage statistics: keep at level 0 (off). Best effort; the key may differ between versions.
        kwriteconfig6 --file PlasmaUserFeedback --group Global --key FeedbackLevel 0 || true
        # Akregator in the background (RSS fetched without opening a window)
        if [ "${SETUP_TYPE}" = "${SETUP_TYPE_FULL}" ] && pkg_installed akregator; then
          make_user_dir "${HOME_DIR}/.config/autostart"
          cat > "${HOME_DIR}/.config/autostart/org.kde.akregator-nb.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Akregator (background)
Exec=akregator --hide-mainwindow
X-GNOME-Autostart-enabled=true
EOF
        fi
      fi ;;
    *) log_info "No desktop-specific configuration for '${DESKTOP}'." ;;
  esac
}

# Runs after the application sub-scripts so their .desktop files exist. Uses the repo's helper_mimeapps.sh
# (python-based, atomic edits, clears blacklisted associations). An application that is not installed is skipped.
step_mime_defaults() {
  if [ "${GUI}" != true ]; then log_info "Headless/minimal profile: MIME defaults skipped."; return 0; fi
  local text_types=(text/plain text/markdown text/x-markdown application/json application/xml text/xml
                    application/x-shellscript text/x-shellscript text/x-python text/x-script.python
                    application/x-yaml text/x-log text/csv text/x-csrc text/x-c++src text/x-rust)
  set_default_app "${DEFAULT_EDITOR_DESKTOP}" "${text_types[@]}"
  set_default_app "${DEFAULT_BROWSER_DESKTOP}" x-scheme-handler/http x-scheme-handler/https x-scheme-handler/about text/html application/xhtml+xml
  set_default_app "${DEFAULT_VIDEO_DESKTOP}" video/mp4 video/x-matroska video/webm video/x-msvideo video/quicktime video/mpeg
  set_default_app "${DEFAULT_PDF_DESKTOP}" application/pdf
  set_default_app "${DEFAULT_MAIL_DESKTOP}" x-scheme-handler/mailto
  set_default_app "${DEFAULT_TEL_DESKTOP}" x-scheme-handler/tel
  set_default_app "${DEFAULT_GEO_DESKTOP}" x-scheme-handler/geo

  if [ "${DESKTOP}" = "${DESKTOP_KDE}" ] && have kwriteconfig6; then
    # KDE's own default-application settings (used by Dolphin, KRunner, "Open Terminal Here")
    if have "${DEFAULT_TERMINAL_KDE}"; then
      kwriteconfig6 --file kdeglobals --group General --key TerminalApplication "${DEFAULT_TERMINAL_KDE}"
    fi
    if desktop_file_exists "${DEFAULT_BROWSER_DESKTOP}"; then
      kwriteconfig6 --file kdeglobals --group General --key BrowserApplication "${DEFAULT_BROWSER_DESKTOP}"
    fi
  fi
}

##################################################################################
# Stage: applications (sub-scripts)
##################################################################################
# Order matters where noted. Each sub-script receives the exported environment (REAL_USER,
# FILENAME_TIMESTAMP, ...). run_step isolates every one, so a failing installer no longer stops the rest.
# The scripts that run under sudo are the ones that were run that way in the tested version.
run_application_steps() {
  # Brave is installed from its dnf repository by brave_browser.sh
  export CHROME_EXECUTABLE="/usr/bin/brave-browser"

  if [ "${GUI}" = true ]; then
    run_step "app:vscodium"      run_sub linux/common/vscodium.sh
    run_step "app:librewolf"     run_sub linux/common/librewolf_browser.sh
    run_step "app:brave"         run_sub linux/common/brave_browser.sh
    run_step "app:tor-browser"   run_sub linux/common/tor_browser.sh
    run_step "app:fonts"         run_sub linux/common/fonts.sh
  fi

  run_step "app:zsh"           run_sub_root linux/common/zsh.sh
  run_step "app:omz"           run_sub_root linux/common/omz.sh
  run_step "app:cli-tools"     run_sub_root linux/common/cli_tools.sh
  run_step "app:starship"      run_sub_root linux/common/starship.sh
  run_step "app:atuin"         run_sub_root linux/common/atuin.sh

  if [ "${GUI}" = true ]; then
    run_step "app:alacritty"   run_sub linux/common/alacritty_orig.sh
    run_step "app:bleachbit"   run_sub linux/common/bleachbit.sh
  fi
  # git.sh and dns.sh still take positional arguments; convert them to named options when they are next edited.
  run_step "app:git"           run_sub linux/common/git.sh "${GIT_USER_EMAIL}"
  run_step "app:syncthing"     run_sub linux/common/syncthing.sh
  run_step "app:avahi"         run_sub linux/common/avahi.sh
  if [ "${GUI}" = true ]; then
    run_step "app:mpv"         run_sub linux/common/mpv.sh
  fi
  run_step "app:dns-nextdns"   run_sub_root linux/security/dns.sh "${NEXTDNS_ID}" "${NEXTDNS_DEVICE_ID}"
  if [ "${GUI}" = true ]; then
    run_step "app:proton"      run_sub linux/security/proton_ag.sh --setup-type "${SETUP_TYPE}" --desktop "${DESKTOP}"
  fi

  run_step "app:clamav"        run_sub_root linux/security/clamav.sh \
      --pc-type="${PC_TYPE}" --real-user="${REAL_USER}" --torrent-client="${HAS_TORRENT_CLIENT}" \
      --kodi="${HAS_KODI}" --backup-dir="${SCRIPT_BACKUPS_DIR}" --timestamp="${FILENAME_TIMESTAMP}"
  # hosts.sh must run after clamav.sh
  run_step "app:hosts"         run_sub linux/security/hosts.sh
  # AppMan must run after clamav.sh (its installer is scanned before it runs)
  run_step "appimages"         step_appimages

  if [ "${SETUP_TYPE}" = "${SETUP_TYPE_FULL}" ]; then
    run_step "app:bash"          run_sub linux/common/bash.sh
    run_step "app:aws"           run_sub linux/common/aws.sh
    if [ "${GUI}" = true ]; then
      run_step "app:zoom"        run_sub linux/common/zoom.sh
      run_step "app:jetbrains"   run_sub linux/common/jetbrains_toolbox.sh
    fi
    run_step "app:docker"        run_sub linux/common/docker.sh
    run_step "app:neovim"        run_sub linux/common/neovim_lazyvim.sh
    run_step "app:i2p"           run_sub linux/security/i2p.sh
    # tmux_zellij.sh and yazi.sh must run after zsh, alacritty and neovim
    run_step "app:tmux-zellij"   run_sub linux/common/tmux_zellij.sh
    run_step "app:yazi"          run_sub linux/common/yazi.sh
    # mullvad_browser.sh must run after clamav.sh
    if [ "${GUI}" = true ]; then
      run_step "app:mullvad"     run_sub linux/common/mullvad_browser.sh
      if [ "${DESKTOP}" = "${DESKTOP_GNOME}" ]; then
        run_step "app:gsconnect" run_sub linux/common/gsconnect_kde_connect.sh
      fi
    fi
  fi
}

##################################################################################
# Security
##################################################################################
# Notifications first: later units (smartd, scrub, flatpak updates, dnf-automatic) call nb-ntfy.
step_sec_ntfy_tools() {
  if [ -z "${NTFY_TOPIC}" ]; then log_info "ntfy disabled (no topic)."; return 0; fi
  # Root-only: the file may contain an access token.
  write_root_file /etc/nb/ntfy.env 600 <<EOF
NTFY_SERVER='${NTFY_SERVER}'
NTFY_TOPIC='${NTFY_TOPIC}'
NTFY_TOKEN='${NTFY_TOKEN}'
EOF
  sudo install -m 0755 -o root -g root "${HELPER_DIR}/helper_ntfy.sh" /usr/local/bin/nb-ntfy
  sudo restorecon -F /usr/local/bin/nb-ntfy 2>/dev/null || true

  # smartd runs this with SMARTD_* environment variables describing the problem.
  write_root_file /usr/local/bin/nb-smartd-notify 755 <<'EOF'
#!/bin/bash
exec /usr/local/bin/nb-ntfy "SMART ${SMARTD_FAILTYPE:-alert} on $(hostname)" "${SMARTD_MESSAGE:-no message}" high warning
EOF
  /usr/local/bin/nb-ntfy "Setup notifications active" "run_first.sh configured ntfy on ${NEW_HOSTNAME}" low white_check_mark \
    || log_warn "Test notification could not be sent (check topic/server/token)."
}

step_sec_firewalld() {
  # Applies the per-application rules (syncthing, KDE Connect, ...) for services that are now installed.
  # Option names are the ones firewalld.sh already defines. fail2ban.sh is intentionally not run: no SSH
  # daemon is exposed. Add it after firewalld.sh if sshd is enabled.
  run_sub_root linux/security/firewalld.sh \
    --filename-timestamp "${FILENAME_TIMESTAMP}" \
    --script-backups-dir "${SCRIPT_BACKUPS_DIR}" \
    --sysupdate-code-base-dir "${SYSUPDATE_CODE_BASE_DIR}" \
    --home-lan-subnet "${HOME_LAN_SUBNET}" \
    --privacy-level "${PRIVACY_LEVEL}" \
    --desktop "${DESKTOP}" \
    --home-dir "${HOME_DIR}" \
    --real-user "${REAL_USER}"
}

# Kernel and network sysctls. Deliberately NOT set: kernel.yama.ptrace_scope=2 and disabling
# unprivileged user namespaces (both break debuggers, Flatpak and bubblewrap).
step_sec_sysctl() {
  local ptrace=""
  [ "${PRIVACY_LEVEL}" = "${PRIVACY_HOME}" ] || ptrace="kernel.yama.ptrace_scope=1"
  write_root_file /etc/sysctl.d/90-nb-hardening.conf 644 <<EOF
# Managed by run_first.sh (privacy level: ${PRIVACY_LEVEL})
# Hide kernel pointers and the kernel log from unprivileged users
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
# Restrict eBPF and harden its JIT
kernel.unprivileged_bpf_disabled=1
net.core.bpf_jit_harden=2
# No loading a new kernel at run time; no automatic TTY line-discipline module loading
kernel.kexec_load_disabled=1
dev.tty.ldisc_autoload=0
vm.unprivileged_userfaultfd=0
# Processes that change privileges (setuid) never write core dumps
fs.suid_dumpable=0
# Link and FIFO protections
fs.protected_hardlinks=1
fs.protected_symlinks=1
fs.protected_fifos=2
fs.protected_regular=2
# Network: reverse-path filtering, no redirects, SYN cookies
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv6.conf.all.accept_source_route=0
net.ipv4.tcp_syncookies=1
net.ipv4.icmp_echo_ignore_broadcasts=1
${ptrace}
EOF
  sudo sysctl --system >/dev/null
}

# Rarely used protocols and filesystems are common local-privilege-escalation entry points.
# squashfs/udf/thunderbolt are intentionally left alone (AppImage/Flatpak, optical media, docks).
step_sec_modprobe() {
  local extra=""
  if [ "${PRIVACY_LEVEL}" = "${PRIVACY_PARANOID}" ]; then
    extra=$'install firewire-core /bin/false\ninstall firewire-ohci /bin/false'
  fi
  write_root_file /etc/modprobe.d/90-nb-blacklist.conf 644 <<EOF
# Managed by run_first.sh (privacy level: ${PRIVACY_LEVEL})
install dccp /bin/false
install sctp /bin/false
install rds /bin/false
install tipc /bin/false
install cramfs /bin/false
install freevxfs /bin/false
install jffs2 /bin/false
install hfs /bin/false
install hfsplus /bin/false
${extra}
EOF
}

# A crash dump is a copy of the process memory: passwords, tokens and keys can end up on disk.
# Storage=none discards dumps; ProcessSizeMax=0 stops them from being generated at all.
# To debug a crash with a core file, delete this drop-in (and run: sudo systemctl daemon-reload).
step_sec_coredumps() {
  write_root_file /etc/systemd/coredump.conf.d/90-nb.conf 644 <<'EOF'
# Managed by run_first.sh
[Coredump]
Storage=none
ProcessSizeMax=0
EOF
}

# SSH and GPG refuse to use keys that other users can read; tightening also protects keys from other accounts.
step_sec_user_perms() {
  local d
  for d in .ssh .gnupg; do
    if [ -d "${HOME_DIR}/${d}" ]; then
      chmod 700 "${HOME_DIR}/${d}"
      find "${HOME_DIR}/${d}" -type f -exec chmod go-rwx {} +
      log_success "Permissions tightened: ~/${d}"
    fi
  done
}

# Hardening for an SSH server, applied only when sshd is enabled. First match wins in sshd, and a drop-in
# named 10-* is read before Fedora's own 50-redhat.conf, so these settings take precedence.
# Password login is only disabled when the user already has an authorized key (otherwise: lock-out).
step_sec_ssh() {
  if ! systemctl is-enabled --quiet sshd 2>/dev/null; then log_info "sshd is not enabled; nothing to harden."; return 0; fi
  local conf="/etc/ssh/sshd_config.d/10-nb-hardening.conf" auth=""
  if [ -s "${HOME_DIR}/.ssh/authorized_keys" ]; then
    auth=$'PasswordAuthentication no\nKbdInteractiveAuthentication no'
  else
    log_warn "sshd is enabled but ~/.ssh/authorized_keys is empty: password login stays ON to avoid a lock-out. Add a public key and re-run."
  fi
  write_root_file "${conf}" 644 <<EOF
# Managed by run_first.sh
PermitRootLogin no
X11Forwarding no
AllowAgentForwarding no
MaxAuthTries 3
LoginGraceTime 30
${auth}
EOF
  if sudo sshd -t; then
    sudo systemctl reload sshd
  else
    sudo rm -f "${conf}"
    log_die "sshd rejected the hardening drop-in; it was removed."
  fi
}

# Auditing: who changed accounts, sudo rules, SSH, firewall, SELinux and service definitions.
# Targeted watches only (single files or directories, never recursive trees), so the log stays small.
# Rules are generated only for paths that exist, and `-i` makes auditctl skip a rule that cannot load
# instead of aborting the whole file. Lynis is an advisory scanner: run `sudo lynis audit system` when
# needed and treat its suggestions as hints (not every one suits a desktop).
step_sec_audit() {
  sudo dnf install -y audit lynis
  local rules="# Managed by run_first.sh\n-i\n" entry path perms key
  for entry in \
    "/etc/passwd:wa:identity" "/etc/shadow:wa:identity" "/etc/group:wa:identity" "/etc/gshadow:wa:identity" \
    "/etc/sudoers:wa:sudoers" "/etc/sudoers.d/:wa:sudoers" \
    "/etc/ssh/:wa:sshd" "/etc/firewalld/:wa:firewall" "/etc/selinux/:wa:selinux" \
    "/etc/systemd/system/:wa:systemd_units" "/usr/lib/systemd/system/:wa:systemd_units" \
    "/etc/clamd.d/:wa:clamav" "/etc/freshclam.conf:wa:clamav" "/etc/fail2ban/:wa:fail2ban" \
    "/etc/dnf/:wa:package_config" "/etc/nb/:wa:nb_config" \
    "/usr/bin/sudo:x:priv_exec" "/usr/bin/su:x:priv_exec" "/usr/bin/pkexec:x:priv_exec"; do
    IFS=: read -r path perms key <<< "${entry}"
    if [ -e "${path}" ]; then rules+="-w ${path} -p ${perms} -k ${key}\n"; fi
  done
  printf '%b' "${rules}" | write_root_file /etc/audit/rules.d/90-nb.rules 640
  sudo systemctl enable --now auditd
  sudo augenrules --load || log_warn "augenrules --load failed; rules apply after reboot."
}

# Crash reporting (ABRT) can upload crash data; the countme override is in step_dnf_config.
step_sec_telemetry() {
  local unit
  while read -r unit; do
    [ -n "${unit}" ] || continue
    sudo systemctl disable --now "${unit}" 2>/dev/null || true
  done < <(systemctl list-unit-files 'abrt*' --no-legend 2>/dev/null | awk '{print $1}')
  log_success "ABRT units (if present) disabled."
}

# Unattended security updates. Kernel updates still require your reboot (reboot = never).
step_sec_auto_updates() {
  sudo dnf install -y dnf5-plugin-automatic
  local emit="stdio" command_section=""
  if [ -n "${NTFY_TOPIC}" ]; then
    emit="stdio,command"
    command_section="[command]
command_format = \"/usr/local/bin/nb-ntfy 'dnf-automatic on ${NEW_HOSTNAME}' -\"
stdin_format = \"{body}\""
  fi
  write_root_file /etc/dnf/automatic.conf 644 <<EOF
# Managed by run_first.sh - host-specific overrides of /usr/share/dnf5/dnf5-plugins/automatic.conf
[commands]
upgrade_type = ${AUTO_UPDATE_TYPE}
download_updates = yes
apply_updates = yes
reboot = never

[emitters]
emit_via = ${emit}

${command_section}
EOF
  sudo systemctl enable --now dnf5-automatic.timer
}

# System-wide Flatpaks: daily update, weekly-ish cleanup of unused runtimes, only on AC power.
step_sec_flatpak_timer() {
  local stop_post=""
  [ -z "${NTFY_TOPIC}" ] || stop_post='ExecStopPost=-/bin/sh -c '"'"'test "$$SERVICE_RESULT" = success || /usr/local/bin/nb-ntfy "Flatpak update failed" "$$(hostname)" high warning'"'"
  write_root_file /etc/systemd/system/nb-flatpak-update.service 644 <<EOF
# Managed by run_first.sh
[Unit]
Description=Update system-wide Flatpak applications
Wants=network-online.target
After=network-online.target
ConditionACPower=true

[Service]
Type=oneshot
ExecStart=/usr/bin/flatpak update --system -y --noninteractive
ExecStart=/usr/bin/flatpak uninstall --system --unused -y --noninteractive
${stop_post}
EOF
  write_root_file /etc/systemd/system/nb-flatpak-update.timer 644 <<'EOF'
# Managed by run_first.sh
[Unit]
Description=Daily Flatpak update

[Timer]
OnCalendar=daily
RandomizedDelaySec=2h
Persistent=true

[Install]
WantedBy=timers.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now nb-flatpak-update.timer
}

# Disk health: three of the target machines use spinning disks. Skipped inside VMs (no real disks).
step_sec_smartd() {
  if [ "${IS_VM}" = true ]; then log_info "Virtual machine; SMART monitoring skipped."; return 0; fi
  sudo dnf install -y smartmontools
  local mail_arg="-m root"
  [ -z "${NTFY_TOPIC}" ] || mail_arg="-m <nomail> -M exec /usr/local/bin/nb-smartd-notify"
  # -a all checks, -o on offline data collection, -S on attribute autosave, -n standby,q do not wake sleeping disks,
  # -s short self-test daily 02:00 and long self-test every Saturday 03:00, -W temperature (diff, info, critical).
  write_root_file /etc/smartd.conf 644 <<EOF
# Managed by run_first.sh
DEVICESCAN -a -o on -S on -n standby,q -s (S/../.././02|L/../../6/03) -W 4,35,50 ${mail_arg}
EOF
  sudo systemctl enable --now smartd.service
}

# A monthly scrub reads every block and verifies checksums, catching silent corruption early.
step_sec_btrfs_scrub() {
  if [ "${ROOT_FSTYPE}" != "btrfs" ]; then log_info "Root is not btrfs; scrub timer skipped."; return 0; fi
  local stop_post=""
  [ -z "${NTFY_TOPIC}" ] || stop_post='ExecStopPost=-/bin/sh -c '"'"'test "$$SERVICE_RESULT" = success || /usr/local/bin/nb-ntfy "btrfs scrub found problems" "$$(hostname)" urgent warning'"'"
  write_root_file /etc/systemd/system/nb-btrfs-scrub.service 644 <<EOF
# Managed by run_first.sh
[Unit]
Description=btrfs scrub of the root filesystem
ConditionACPower=true

[Service]
Type=oneshot
# -B wait in the foreground, -c 3 idle I/O class (does not slow the desktop)
ExecStart=/usr/bin/btrfs scrub start -B -c 3 /
${stop_post}
EOF
  write_root_file /etc/systemd/system/nb-btrfs-scrub.timer 644 <<'EOF'
# Managed by run_first.sh
[Unit]
Description=Monthly btrfs scrub

[Timer]
OnCalendar=monthly
RandomizedDelaySec=6h
Persistent=true

[Install]
WantedBy=timers.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now nb-btrfs-scrub.timer
}

# Cap the journal so it cannot fill a small SSD, and keep a month of history for troubleshooting.
step_sec_journald() {
  write_root_file /etc/systemd/journald.conf.d/90-nb.conf 644 <<'EOF'
# Managed by run_first.sh
[Journal]
SystemMaxUse=500M
MaxRetentionSec=1month
Compress=yes
EOF
  sudo systemctl restart systemd-journald
}

step_final_updates() {
  sudo flatpak update --system -y --noninteractive || log_warn "flatpak update reported a problem."
  sudo dnf upgrade --refresh -y
  sudo dnf check || log_warn "dnf check reported problems (see above)."
}

# A last snapshot of the finished state: the restore point for "everything configured".
step_final_snapshot() {
  if [ "${ROOT_FSTYPE}" != "btrfs" ]; then return 0; fi
  sudo snapper -c root create -d "run_first: setup complete" || log_warn "Final snapshot failed."
}

# Post-run report: inventory, package differences, listening sockets and failed units in one file.
step_report() {
  local out="${SCRIPT_DATA_INVENTORY}/post_run_${FILENAME_TIMESTAMP}.txt"
  write_inventory "${out}"
  {
    echo "== Listening sockets"; sudo ss -tulpn
    echo "== Failed units";      systemctl --failed --no-pager
    echo "== Errors in this boot's journal (last 50)"; sudo journalctl -p err -b --no-pager -n 50
    echo "== Packages added since the pre-run inventory"
    rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort \
      | comm -13 "${SCRIPT_DATA_INVENTORY}/packages_pre_${FILENAME_TIMESTAMP}.txt" - | head -300
  } >> "${out}" 2>&1 || true
  chmod 600 "${out}"
  log_success "Report: ${out}"
}

##################################################################################
# Verification
##################################################################################
V_PASS=0; V_FAIL=0; V_WARN=0
v_pass() { V_PASS=$((V_PASS + 1)); log_success "$1"; }
v_fail() { V_FAIL=$((V_FAIL + 1)); log_error "$1"; }
v_warn() { V_WARN=$((V_WARN + 1)); log_warn "$1"; }
# check "description" command args...   -> pass if the command succeeds, fail otherwise
check()      { local d="$1"; shift; if "$@" &>/dev/null; then v_pass "$d"; else v_fail "$d"; fi; }
# check_warn: same but only a warning (optional or reboot-dependent things)
check_warn() { local d="$1"; shift; if "$@" &>/dev/null; then v_pass "$d"; else v_warn "$d"; fi; }

sysctl_is() { [ "$(sysctl -n "$1" 2>/dev/null)" = "$2" ]; }
unit_enabled() { systemctl is-enabled --quiet "$1"; }
default_zone_is_strict() { [ "$(sudo firewall-cmd --get-default-zone)" != "FedoraWorkstation" ]; }
zone_has_no_highports() { ! sudo firewall-cmd --zone="$(sudo firewall-cmd --get-default-zone)" --list-ports | grep -q '1025-65535'; }
countme_disabled() { sudo dnf5 --dump-repo-config fedora 2>/dev/null | grep -Eiq '^countme *= *(0|false)'; }
user_unit_enabled() { systemctl --user is-enabled --quiet "$1"; }

verify_setup() {
  log_header "Verification"
  check      "Running Fedora"                              test "$(. /etc/os-release && echo "${ID}")" = fedora
  check      "Hostname is ${NEW_HOSTNAME}"                 test "$(hostnamectl --static)" = "${NEW_HOSTNAME}"
  check      "DNF drop-in present"                         test -f /etc/dnf/libdnf5.conf.d/90-nb.conf
  check_warn "countme disabled for official repos"         countme_disabled
  check      "NetworkManager privacy policy present"       test -f /etc/NetworkManager/conf.d/00-nb-privacy.conf
  check      "firewalld is running"                        systemctl is-active --quiet firewalld
  check      "Default firewalld zone is not FedoraWorkstation" default_zone_is_strict
  check      "Default zone does not open 1025-65535"       zone_has_no_highports
  check_warn "SELinux is Enforcing"                        test "$(getenforce 2>/dev/null)" = Enforcing
  if [ "${GUI}" = true ]; then
    check    "Flathub remote configured"                   bash -c 'flatpak remotes --system --columns=name | grep -qx flathub'
  fi
  if [ "${GUI}" = true ]; then
    check    "RPM Fusion free+nonfree installed"           bash -c 'rpm -q rpmfusion-free-release rpmfusion-nonfree-release'
    check    "ffmpeg (RPM Fusion) installed"               rpm -q ffmpeg
  fi

  if [ "${ROOT_FSTYPE}" = "btrfs" ]; then
    check    "snapper root config exists"                  bash -c 'sudo snapper list-configs | grep -qw root'
    check    "dnf snapshot hook present"                   test -f /etc/dnf/libdnf5-plugins/actions.d/snapper.actions
    check_warn "btrfs scrub timer enabled"                 unit_enabled nb-btrfs-scrub.timer
  fi

  # Hardware acceleration (needs a working GPU session; warnings only)
  if [ "${GUI}" = true ] && [ "${GPU_VENDORS}" != "none" ]; then
    check_warn "VA-API reports a driver (vainfo)"          vainfo
  fi
  if [ "${GUI}" = true ] && has_vendor nvidia; then
    check_warn "NVIDIA kernel module available"            modinfo -F version nvidia
    check_warn "NVIDIA driver loaded (after reboot)"       bash -c 'lsmod | grep -q "^nvidia "'
  fi
  check_warn "zram swap active (after reboot)"             bash -c 'swapon --show=NAME --noheadings | grep -q zram'
  check      "zram configuration present"                  test -f /etc/systemd/zram-generator.conf

  check      "kernel.kptr_restrict = 2"                    sysctl_is kernel.kptr_restrict 2
  check      "kernel.dmesg_restrict = 1"                   sysctl_is kernel.dmesg_restrict 1
  check      "kernel.unprivileged_bpf_disabled = 1"        bash -c '[ "$(sysctl -n kernel.unprivileged_bpf_disabled)" != 0 ]'
  check      "modprobe blacklist present"                  test -f /etc/modprobe.d/90-nb-blacklist.conf
  check      "core dumps disabled (coredump drop-in)"      test -f /etc/systemd/coredump.conf.d/90-nb.conf
  check_warn "auditd active"                               systemctl is-active --quiet auditd
  check_warn "audit rules loaded"                          bash -c 'sudo auditctl -l | grep -q identity'
  check_warn "lynis installed"                             rpm -q lynis
  if [ "${SSD_PRESENT}" = true ]; then check_warn "fstrim.timer enabled" unit_enabled fstrim.timer; fi
  if systemctl is-enabled --quiet sshd 2>/dev/null; then check "sshd hardening drop-in present" test -f /etc/ssh/sshd_config.d/10-nb-hardening.conf; fi

  check      "dnf5-automatic timer enabled"                unit_enabled dnf5-automatic.timer
  check      "Flatpak update timer enabled"                unit_enabled nb-flatpak-update.timer
  if [ "${IS_VM}" != true ]; then check_warn "smartd enabled" unit_enabled smartd.service; fi
  check_warn "ABRT services disabled"                      bash -c '! systemctl is-enabled --quiet abrtd.service'

  if [ "${PC_TYPE}" = "${PC_TYPE_LAPTOP}" ]; then
    check_warn "tuned running"                             systemctl is-active --quiet tuned.service
  fi
  if [ "${GUI}" = true ] && [ "${DESKTOP}" = "${DESKTOP_KDE}" ] && [ "${SSD_PRESENT}" != true ]; then
    check_warn "Baloo indexing disabled (HDD)"             bash -c 'grep -q "Indexing-Enabled=false" ~/.config/baloofilerc'
  fi
  check      "journald limits present"                     test -f /etc/systemd/journald.conf.d/90-nb.conf
  check      "nbupdate command installed"                  test -x "${HOME_DIR}/.local/bin/nbupdate"
  if [ "${GUI}" = true ]; then
    check_warn "AppMan installed"                          test -x "${HOME_DIR}/.local/bin/appman"
    check_warn "AppImage update timer enabled"             user_unit_enabled nb-appimage-update.timer
    # Uses the repo helper; it prints the types that do not resolve to the application.
    if desktop_file_exists "${DEFAULT_EDITOR_DESKTOP}"; then
      check_warn "Default text editor is ${DEFAULT_EDITOR_DESKTOP}"  mimeapps_check_default "${DEFAULT_EDITOR_DESKTOP}" text/plain
    fi
    if desktop_file_exists "${DEFAULT_BROWSER_DESKTOP}"; then
      check_warn "Default browser is ${DEFAULT_BROWSER_DESKTOP}"     mimeapps_check_default "${DEFAULT_BROWSER_DESKTOP}" x-scheme-handler/https
    fi
  fi

  log_header "Verification result: ${V_PASS} passed, ${V_WARN} warnings, ${V_FAIL} failed"
  [ "${V_FAIL}" -eq 0 ]
}

##################################################################################
# Main
##################################################################################
main() {
  ORIG_ARGS=("$@")        # kept so setup_logging can re-run this script under script(1)
  parse_options "$@"
  # set -x prints every command and value; it also reaches the log (so secrets can appear there).
  if [ "${TRACE}" = true ]; then set -x; fi

  preflight_root
  preflight_dirs
  setup_logging           # may replace this process with `script ... run_first.sh <same args>`
  preflight
  infer_system
  validate_user_variables
  resolve_home_network
  preflight_warnings

  if [ "${VERIFY_ONLY}" = true ]; then
    verify_setup
    return $?
  fi
  preflight_subscript_inventory

  init_state
  log_info "Machine: ${CPU_MODEL}, ${CPU_CORES} cores, ${RAM_MB} MB (${RAM_PROFILE}), SSD=${SSD_PRESENT}, type=${PC_TYPE}, desktop=${DESKTOP}"
  log_info "GPU: ${GPU_VENDORS} (tier ${GPU_TIER}, nvidia driver in use: ${NVIDIA_DRIVER}); ultra-low-voltage CPU: ${CPU_IS_ULV}; privacy=${PRIVACY_LEVEL}; setup=${SETUP_TYPE}"

  run_step "inventory"               step_inventory
  run_step "backup"                  step_backup
  run_step "reset"                   step_reset

  run_step "hostname"                step_hostname
  run_step "ethernet-rename"         step_ethernet_rename
  run_step "network-privacy"         step_network_privacy
  run_step "firewall-baseline"       step_firewall_baseline

  run_step "dnf-config"              step_dnf_config
  run_step "remove-unwanted"         step_remove_unwanted_packages
  run_step "system-upgrade"          step_system_upgrade
  if [ -f "${REBOOT_NOW_FLAG}" ]; then
    rm -f "${REBOOT_NOW_FLAG}"
    print_step_summary || true
    ntfy_send "Reboot needed" "${NEW_HOSTNAME}: reboot, then re-run run_first.sh with the same options." default warning || true
    log_warn "REBOOT NOW, then run the same command again. Completed stages will be skipped."
    return 0
  fi

  run_step "snapshots"               step_snapshots
  if [ "${GUI}" = true ]; then run_step "repos" step_repos; fi
  run_step "hw:codecs"               step_hw_codecs
  run_step "hw:gpu-video"            step_hw_gpu_video
  run_step "hw:nvidia"               step_hw_nvidia
  run_step "hw:memory"               step_hw_memory
  run_step "hw:storage"              step_hw_storage
  run_step "hw:power"                step_hw_power
  run_step "hw:firmware"             step_hw_firmware
  run_step "packages"                step_packages
  run_step "flatpak-apps"            step_flatpak_apps
  run_step "desktop-config"          step_desktop_config

  # remove_stuff.sh (work in progress) removes optional packages for the smaller setup types.
  if [ "${SETUP_TYPE}" = "${SETUP_TYPE_LIGHT}" ] || [ "${SETUP_TYPE}" = "${SETUP_TYPE_MINIMAL}" ]; then
    run_step "remove-stuff"          run_sub_optional linux/fedora/remove_stuff.sh
  fi

  run_application_steps

  run_step "shell-extras"            step_shell_extras
  run_step "mime-defaults"           step_mime_defaults
  run_step "sec:ntfy-tools"          step_sec_ntfy_tools
  run_step "sec:firewalld"           step_sec_firewalld
  run_step "sec:sysctl"              step_sec_sysctl
  run_step "sec:modprobe"            step_sec_modprobe
  run_step "sec:telemetry"           step_sec_telemetry
  run_step "sec:coredumps"           step_sec_coredumps
  run_step "sec:user-perms"          step_sec_user_perms
  run_step "sec:ssh"                 step_sec_ssh
  run_step "sec:audit"               step_sec_audit
  run_step "sec:journald"            step_sec_journald
  run_step "sec:auto-updates"        step_sec_auto_updates
  if [ "${GUI}" = true ]; then run_step "sec:flatpak-timer" step_sec_flatpak_timer; fi
  run_step "sec:smartd"              step_sec_smartd
  run_step "sec:btrfs-scrub"         step_sec_btrfs_scrub
  run_step "final-updates"           step_final_updates
  run_step "final-snapshot"          step_final_snapshot
  run_step "report"                  step_report

  local summary_rc=0 verify_rc=0
  print_step_summary || summary_rc=1
  verify_setup || verify_rc=1

  if [ "${summary_rc}" -eq 0 ]; then
    # Everything succeeded: forget the state so the next run starts fresh (as intended).
    rm -f "${STATE_FILE}"
    ntfy_send "Setup finished" "${NEW_HOSTNAME}: all stages OK (verification failures: ${V_FAIL})" default white_check_mark || true
  else
    ntfy_send "Setup finished with failures" "${NEW_HOSTNAME}: see ${LOG_FILE}" high warning || true
    log_warn "Some stages failed. Re-run the same command to retry only those (state kept in ${STATE_FILE})."
  fi
  [ ! -f "${REBOOT_END_FLAG}" ] || log_warn "Reboot recommended (kernel module / zram / MOK enrollment)."
  log_info "Log: ${LOG_FILE}   Backups: ${RUN_FIRST_CURRENT_BACKUP_DIR}   Reports: ${SCRIPT_DATA_INVENTORY}"
  [ "${summary_rc}" -eq 0 ] && [ "${verify_rc}" -eq 0 ]
}

main "$@"
exit $?

##################################################################################
# Notes
##################################################################################
# DESIGN DECISIONS AND REPLACED LOGIC
# - Orchestration: the earlier script was one long top-to-bottom file under `set -eux`, so any failure
#   (including an installer that needed a different Fedora edition) aborted everything and left a
#   half-configured system. Every stage now runs through run_step (helper_steps.sh): isolated in a subshell,
#   logged, summarized, and recorded in a state file so a re-run (or a run resumed after the reboot that
#   follows the first full upgrade) skips finished stages. When every stage succeeds the state file is
#   deleted, so the next run is a fresh one.
# - Strict mode: `set -Eeuo pipefail` plus `inherit_errexit`. The earlier `set -eux` is kept as TRACE=true
#   (set -x) while the script is being tested; set TRACE=false (or --trace false) once it is trusted.
# - Logging: output goes through script(1), a pseudo-terminal recorder, so dnf/flatpak keep colors and progress
#   bars while everything is logged. Plain `| tee` would make those tools think they are not on a terminal.
#   Fallback: tee, when script(1) is not installed.
# - Helpers: the repo's helper_logging.sh, helper_backup.sh (backup_path_parents, run as root through
#   backup_any) and helper_mimeapps.sh are used unchanged. helper_steps.sh and helper_ntfy.sh are new and follow
#   the same guard-variable pattern (HELPER_<NAME>_LOADED), define only functions with unique names, and need
#   no variables except the documented STATE_FILE.
# - Old `if [ ${EUID:-0} -ne 0 ] || [ "$(id -u)" -ne 0 ]` root test: replaced by one `id -u` check. The script must
#   NOT run as root; it calls sudo where needed, which keeps files in $HOME user-owned.
# - Python one-liner for the LAN subnet: replaced by `ip route get` + `ip route show`, which needs no Python and
#   handles VPN default routes without "via".
# - HOME_LAN_SUBNET: trusting the subnet found during installation is unsafe (the install may happen on a cafe
#   network). The detected subnet is only trusted for privacy=home, or when the active connection IS the
#   declared home connection; otherwise a TEST-NET placeholder means "trust nothing". Firewalld zones are also
#   bound per NetworkManager connection, so the zone follows the network profile.
# - Desktop detection: an unidentified desktop on a desktop/laptop is an error (as before). Only pc-type server
#   becomes the headless profile.
# - /etc/dnf/dnf.conf was overwritten before (losing Fedora defaults). A drop-in under /etc/dnf/libdnf5.conf.d/
#   is used instead; it carries max_parallel_downloads, defaultyes, color and skip_if_unavailable.
#   skip_if_unavailable in [main] applies to repos that do not set it themselves; Fedora's own repo files may
#   set it per repo, which takes precedence (acceptable). fastestmirror and deltarpm are DNF4-only options.
# - countme: per-repo `countme=1` wins over [main]; only repos.override.d is effective on DNF5.
# - Timeshift was dropped (unsupported on Fedora's btrfs layout). Snapper + libdnf5-plugin-actions replace it.
#   The actions file syntax comes from a Fedora Discussion walkthrough; verify on a VM after the first run
#   (`sudo dnf install -y nano` should create a pre/post pair visible in `sudo snapper -c root list`).
#   grub-btrfs (boot into snapshots) is not installed: it is third-party on Fedora; btrfs-assistant restores.
#   Reset never deletes snapper configs or snapshots (they are data).
# - AppImages: AppMan (user mode of AM) replaces Gear Lever. All AppImages live in APPIMAGES_DIR. The installer is
#   downloaded to this run's download directory, scanned, then run; AM_INSTALLER_REF can pin a release tag.
#   Add:    appman -i <name>   (alias nbappadd)       Update all: appman -u   (alias nbappupdate)
#   Updates run weekly from a user systemd timer and inside `nbupdate`. Whether `appman -u` ever prompts in an
#   unattended run is unverified; check `journalctl --user -u nb-appimage-update.service` after the first week.
#   Reset removes AppMan's program and config (so appman_location applies again) but never the AppImages.
# - Flatpak overrides: `sudo flatpak override --user` in the earlier version wrote root's overrides, which have no
#   effect for the real user; the ZapZap override now runs as the user and defaults to xdg-download instead of
#   all of $HOME (ZAPZAP_FILESYSTEM="home" restores the old scope). Signal's password-store override stays
#   system-wide, and Element keeps its two talk-name permissions, exactly as before.
# - VA-API/VDPAU/NVIDIA packages are chosen from detected hardware (get_gpu_vendors, get_intel_gen,
#   get_amd_gpu_class, GPU name). Maxwell-class GPUs use the 580xx legacy branch (NVIDIA security support until
#   about October 2028); Kepler cannot work on a Wayland-only desktop.
# - sysctl choices: ptrace_scope stays at Fedora's default for home desktops (debugging, strace, gdb), 1 for
#   portable/paranoid. Unprivileged user namespaces stay enabled (Flatpak, bubblewrap, Chrome sandbox).
# - Boot parameters (init_on_free=1, slab_nomerge, ...) are NOT set here: they cost performance on older CPUs and
#   are better tested per machine.
# - MEDIA_PC: the media Flatpaks are always installed for setup-type full (as before); --media-pc true adds them to
#   other setup types. It is kept for later use.
# - fail2ban.sh is not called (no exposed SSH). If sshd is enabled, run it AFTER firewalld.sh.
# - Stale TODOs closed: gparted alternative (KDE Partition Manager is preinstalled), timeshift (Snapper), ufw
#   (firewalld is the firewall), cron jobs (systemd timers), preload equivalent (none needed on Fedora).
#
# TODO (tracked)
# - Virtualization: a separate script (virt-manager + libvirt; the Boxes alternative for KDE) to run for setup-type full.
# - VSCodium and Brave telemetry/policy hardening: handled in vscodium.sh and brave_browser.sh (details pending).
# - remove_stuff.sh: work in progress; called without arguments for light and minimal setups when the file exists.
# - dns.sh and git.sh still receive positional arguments: convert to named options when next edited.
# - Pin applications to the task bar in a fixed order and group apps into folders: doable on GNOME
#   (org.gnome.shell favorite-apps); on KDE it means editing the panel applets file, which is fragile.
# - Calendar application choice; Thunderbird/Proton Mail as default mail client (set DEFAULT_MAIL_DESKTOP).
# - Fedora Server (pc-type server) runs the headless profile; split a dedicated `core` layer out if it is deployed.
# - Obsidian is an AppImage (AppMan); sync of its vault folder is configured in the Syncthing setup.
# - Not done on purpose (each needs a decision first): AIDE (baseline database must be built and protected), USBGuard
#   (a wrong policy locks out the keyboard), OpenSnitch (rules need per-machine tuning), an OpenSSH server (installing
#   one widens exposure; step_sec_ssh only hardens an sshd that is already enabled), KDE settings export (konsave via
#   pipx, or chezmoi), virtualization (separate script).
# - Entropy check (entropy_avail > 1000) is not part of Verification: kernels since 5.18 report a constant 256,
#   so the check would always warn.
# - Core dumps are disabled (coredump drop-in, fs.suid_dumpable=0). Remove the drop-in to debug with core files.
# - fstrim.timer is enabled only when an SSD is detected. auditd rules are generated for existing paths only.
#
# UNVERIFIED ITEMS (test in a Fedora 44 VM first)
# - `dnf group install multimedia` with --setopt/--exclude under DNF5.
# - `dnf swap` of mesa-va-drivers/mesa-vdpau-drivers to *-freeworld (RPM Fusion's documented method).
# - NetworkManager keys ipv4.dhcp-send-hostname / ipv6.dhcp-send-hostname in [connection] and the value stable-ssid.
# - kwriteconfig6 keys: AnimationDurationFactor, PlasmaUserFeedback/FeedbackLevel, BrowserApplication.
# - mokutil --import needs an interactive terminal; its prompt goes through the script(1) pseudo-terminal.
# - Package name util-linux-script (provides script(1) on recent Fedora); the tee fallback covers its absence.
# - `appman -i obsidian`: the name must exist in the AM catalog.

##################################################################################
# Useful Links
##################################################################################
# --- Bash strict mode ---
# https://www.baeldung.com/linux/set-command
# https://linuxize.com/post/bash-set-command/
# https://www.baeldung.com/linux/check-script-run-root
#
# --- Fedora documentation ---
# https://docs.fedoraproject.org/en-US/quick-docs/upgrading-fedora-new-release/
# https://docs.fedoraproject.org/en-US/quick-docs/switching-desktop-environments/
# https://docs.fedoraproject.org/en-US/quick-docs/systemd-understanding-and-administering/
# https://docs.fedoraproject.org/en-US/quick-docs/debug-systemd-problems/
# https://docs.fedoraproject.org/en-US/quick-docs/viewing-logs/
# https://docs.fedoraproject.org/en-US/quick-docs/kernel-overview/
# https://docs.fedoraproject.org/en-US/quick-docs/virtualization-an-overview/
# https://docs.fedoraproject.org/en-US/quick-docs/troubleshooting-wayland-problems/
# https://docs.fedoraproject.org/en-US/quick-docs/dnf/
# https://docs.fedoraproject.org/en-US/quick-docs/fedora-repositories/
# https://docs.fedoraproject.org/en-US/quick-docs/rpmfusion-setup/
# https://docs.fedoraproject.org/en-US/quick-docs/flathub-flatpak-applications/
# https://docs.fedoraproject.org/en-US/quick-docs/changing-hostname/
# https://docs.fedoraproject.org/en-US/quick-docs/installing-plugins-for-playing-movies-and-music/
# https://docs.fedoraproject.org/en-US/quick-docs/how-to-troubleshoot-sound-problems/
# https://docs.fedoraproject.org/en-US/fedora/f44/release-notes/
#
# --- DNF5 ---
# https://www.mankier.com/5/dnf5.conf                      (config options, drop-in directories)
# https://www.mankier.com/7/dnf5-changes-from-dnf4         (e.g. "remove" fails on unmatched args)
# https://www.mankier.com/8/dnf5-automatic                 (unattended updates, emitters)
# https://bugzilla.redhat.com/show_bug.cgi?id=1965813      (countme opt-out via repos.override.d)
#
# --- RPM Fusion, codecs, GPU drivers ---
# https://rpmfusion.org/Configuration
# https://rpmfusion.org/Howto/Multimedia
# https://discussion.fedoraproject.org/t/upgrading-to-fedora-44-breaks-nvidia-driver-for-older-gpus-geforce-10xx-and-older/192286
# https://nvidia.custhelp.com/app/answers/detail/a_id/5676/~/support-plan-for-maxwell%2C-pascal%2C-and-volta-series-geforce-gpus
#
# --- Firewall ---
# https://fedoramagazine.org/control-the-firewall-at-the-command-line/   (FedoraWorkstation zone opens 1025-65535)
# https://pagure.io/fedora-kde/SIG/issue/435                             (Fedora KDE has the same default)
# https://pagure.io/fesco/issue/1372
#
# --- Snapshots (btrfs) ---
# https://github.com/teejee2008/timeshift#supported-system-configurations   (Timeshift needs @ / @home layout)
# https://computingforgeeks.com/btrfs-snapshots-snapper-automatic-rollback-fedora-opensuse/
# https://discussion.fedoraproject.org/t/getting-snapper-btrfs-assistant-to-work-with-dnf5/133948/6
#
# --- Memory / power ---
# https://github.com/systemd/zram-generator/blob/main/zram-generator.conf.example
# https://discussion.fedoraproject.org/t/optimize-zram-setup-for-high-ram-systems/190868
# https://fedoraproject.org/wiki/Releases/41/ChangeSet#Make_Tuned_the_Default_Power_Profile_Management_Daemon
#
# --- Network privacy ---
# https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/blob/main/examples/nm-conf.d/30-anon.conf
# https://forum.qubes-os.org/t/anonymizing-your-mac-address/19072
#
# --- Hardening ---
# https://madaidans-insecurities.github.io/guides/linux-hardening.html
# https://wiki.archlinux.org/index.php/Security#Kernel_hardening
# https://discussion.fedoraproject.org/t/setting-some-hardening-kargs-for-all-fedora-variants/108866
#
# --- Flatpak on Fedora ---
# https://pagure.io/fesco/issue/2939
# https://discussion.fedoraproject.org/t/tutorial-how-to-replace-the-fedora-flatpak-repo-with-flathub/44320
#
# --- AppImages (AM / AppMan) ---
# https://github.com/ivan-hc/AM
# https://github.com/ivan-hc/AM/releases/tag/10.4        (non-interactive AM-INSTALLER and appman_location)
# https://github.com/ivan-hc/AppMan
#
# --- Fedora 44 changes (Plasma Login Manager, PackageKit on DNF5, Wayland-only KDE) ---
# https://discussion.fedoraproject.org/t/f44-change-proposal-packagekit-dnf5-systemwide/179013

##################################################################################
# Troubleshooting/Debugging/Testing/Commands
##################################################################################
# Where is the log?        ls -t ~/nb/nb_script_data/logs/run_first | head      (one directory per run; run_first.log inside)
# Colors in the log?       less -R <logfile>    (it records the terminal output, including color codes)
# What finished/failed?    cat ~/nb/nb_script_data/state/run_first.state
# Start completely fresh:  rm ~/nb/nb_script_data/state/run_first.state
# Before/after reports:    ls ~/nb/nb_script_data/inventory ; diff pre_run_<ts>.txt post_run_<ts>.txt
# Run only verification:   bash run_first.sh --hostname X --nextdns-id Y --verify-setup
# Syntax / lint:           bash -n run_first.sh ; shellcheck -x -P linux/common run_first.sh
# Quieter output:          --trace false   (trace prints every command and value; it also reaches the log)
#
# DNF
#   dnf5 --dump-repo-config fedora | grep -i countme      Should show countme=0
#   dnf5 repo list --all ; sudo dnf check ; sudo dnf history list
#   journalctl -u dnf5-automatic.service ; systemctl list-timers 'dnf5*' 'nb-*'
# Snapshots
#   sudo snapper -c root list ; sudo snapper -c root status 1..2 ; btrfs-assistant-gui
#   Hook did nothing? ls /etc/dnf/libdnf5-plugins/actions.d/ ; rpm -q libdnf5-plugin-actions
# AppImages (AppMan)
#   appman -i <name> ; appman -u ; ls ~/nb/AppImages ; cat ~/.config/appman/appman-config
#   systemctl --user list-timers ; journalctl --user -u nb-appimage-update.service
# GPU / video
#   vainfo ; vdpauinfo ; LIBVA_DRIVER_NAME=i965 vainfo (Sandy/Ivy Bridge) ; intel_gpu_top
#   modinfo -F version nvidia ; nvidia-smi ; journalctl -u akmods ; sudo akmods --force
#   mokutil --sb-state ; mokutil --list-enrolled | grep -i akmods
# Firewall
#   sudo firewall-cmd --get-active-zones ; sudo firewall-cmd --list-all
#   nmcli -f NAME,UUID,DEVICE,ACTIVE connection show ; nmcli -g connection.zone connection show <name>
# Network privacy
#   nmcli -f 802-11-wireless.cloned-mac-address connection show <wifi> ; ip link ; nmcli general reload
# Memory
#   zramctl ; swapon --show ; sysctl vm.swappiness vm.page-cluster ; systemctl status systemd-zram-setup@zram0
# MIME
#   xdg-mime query default text/plain ; python3 linux/commonh/helper_mimeapps.py get-default --mime-type text/plain
# Notifications
#   nb-ntfy "test" "hello" ; sudo cat /etc/nb/ntfy.env ; journalctl -u nb-btrfs-scrub.service
# Logging under script(1) behaves oddly (quoting)?  Run with RUN_FIRST_UNDER_SCRIPT=1 to bypass the re-exec and log nothing.