#!/usr/bin/env bash
#########################################################
# helper_common.sh - shared prelude for the nb setup scripts (zsh.sh, omz.sh, starship.sh, ...)
#########################################################
#
# WHAT IT PROVIDES
#   Logging ................ log_header/info/success/warn/error/die (colored)
#   nb_require_root ........ re-run the calling script through sudo when not root (scripts that need dnf/usermod)
#   nb_require_user ........ re-run the calling script AS the real user when started as root (scripts that
#                            only touch the user's home: omz, starship, atuin). They need no sudo at all.
#   nb_mkdir / nb_run_as_real_user  privilege-agnostic helpers: the same code works as root (via sudo) or as the user
#   nb_infer_system ........ sets CPU_CORES RAM_MB RAM_PROFILE SSD_PRESENT PC_TYPE DESKTOP DISTRO CPU_MODEL
#                            by calling the tested get_*.sh scripts (never re-implemented here)
#   nb_prepare_script_dirs . creates the user's nb_script_data tree with correct ownership
#   nb_parse_common_options  handles --verify-setup, --timestamp, --help; leftovers go to NB_REMAINING_ARGS
#   has_cmd / user_has_cmd . command detection for root / for the real user's login environment
#   render / write_file .... placeholder templating and atomic file writes with owner and mode
#   check / nb_verify_*  ... tiny test framework used by every "Verification" section
#   nb_user_zsh_starts_clean  shared verification: an interactive zsh starts with no errors
#   nb_notify .............. optional ntfy message when NTFY_URL is set
#
# EXPECTED CALLER VARIABLES (defined in each script's "User defined variables" section)
#   REAL_USER HOME_DIR SYSUPDATE_CODE_BASE_DIR SCRIPT_DATA SCRIPT_DATA_DOWNLOADS SCRIPT_DATA_BACKUPS
#   FILENAME_TIMESTAMP, and optionally HELPER_DIR (helper_*.sh, default .../linux/commonh) and
#   GETTERS_DIR (get_*.sh, default .../linux/commong)
#
# USAGE
#   source "${HELPER_DIR}/helper_common.sh"      # HELPER_DIR defaults to ${SYSUPDATE_CODE_BASE_DIR}/linux/commonh
#   nb_require_root "$0" "$@"
#   nb_parse_common_options "$@"

#########################################################
# Logging
#########################################################
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'

log_header() { echo -e "\n${CYAN}==================== $* ====================${NC}\n"; }
log_info() { echo -e "${BLUE}[INFO] $* ${NC}"; }
log_success() { echo -e "${GREEN}[✓] $* ${NC}"; }
log_warn() { echo -e "${YELLOW}[!] $* ${NC}"; }
log_error() { echo -e "${RED}[✗] $* ${NC}" >&2; }
log_die() { echo -e "${RED}[✗] $* ${NC}" >&2; exit 1; }

# sudo resets PATH to its secure_path, which on Fedora omits /usr/local/bin (Starship, Atuin and
# AWS CLI v2 live there) and lists /usr/sbin before /usr/bin. Normalize so `command -v` is reliable.
# ~/.local/bin (per-user tools such as starship and atuin) comes first.
export PATH="${HOME_DIR:-$HOME}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:${PATH}"

# Bash 5.2 gives "&" a special meaning in replacement strings; switch that off if supported.
shopt -u patsub_replacement 2>/dev/null || true

#########################################################
# Privilege handling
#########################################################
# nb_require_root "$0" "$@"  - the calling script's path and arguments, so it can be re-run.
nb_require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    log_info "Root privileges required. Re-running with sudo."
    # sudo resets the environment, so the few variables that matter are passed explicitly.
    exec sudo --preserve-env=REAL_USER,FILENAME_TIMESTAMP,SYSUPDATE_CODE_BASE_DIR,HELPER_DIR,GETTERS_DIR bash "$@"
  fi
  [[ "$REAL_USER" != "root" ]] || log_die "REAL_USER resolved to root. Run via sudo from your normal account or set REAL_USER."
  id "$REAL_USER" >/dev/null 2>&1 || log_die "User not found: ${REAL_USER}"
}

# nb_require_user "$0" "$@"  - for scripts that need NO root. Started with sudo (e.g. by an orchestrator
# that runs everything through sudo), they re-run themselves as the real user so every file they create
# belongs to that user. Started as the user, they just continue.
nb_require_user() {
  if [[ ${EUID} -eq 0 ]]; then
    [[ "$REAL_USER" != "root" ]] || log_die "REAL_USER resolved to root. Run via sudo from your normal account or set REAL_USER."
    id "$REAL_USER" >/dev/null 2>&1 || log_die "User not found: ${REAL_USER}"
    log_info "This script needs no root: continuing as ${REAL_USER}."
    exec runuser -u "$REAL_USER" -- env HOME="$HOME_DIR" REAL_USER="$REAL_USER" FILENAME_TIMESTAMP="$FILENAME_TIMESTAMP" \
      SYSUPDATE_CODE_BASE_DIR="$SYSUPDATE_CODE_BASE_DIR" HELPER_DIR="${HELPER_DIR:-}" GETTERS_DIR="${GETTERS_DIR:-}" bash "$@"
  fi
  [[ "$REAL_USER" == "$(id -un)" ]] || log_die "REAL_USER (${REAL_USER}) is not the current user ($(id -un))."
}

#########################################################
# Helper preflight
#########################################################
# A stale copy of a helper file (older than the script using it) fails with a cryptic
# "command not found" deep inside a run. Check the needed functions up front instead.
nb_require_functions() {
  local f
  for f in "$@"; do
    declare -F "$f" >/dev/null 2>&1 || log_die "Helper function '${f}' is missing. A helper_*.sh file in ${HELPER_DIR:-${SYSUPDATE_CODE_BASE_DIR}/linux/commonh} is outdated: copy the latest helper files there and re-run."
  done
}

#########################################################
# Option handling
#########################################################
VERIFY_ONLY="false"
NB_REMAINING_ARGS=()
NB_SCRIPT_PATH=""

# Prints the "NAMED OPTIONS" block of the calling script's header comment.
nb_usage() {
  sed -n '/^# NAMED OPTIONS/,/^# SAMPLE CALLS/p' "$NB_SCRIPT_PATH" | sed '$d' | sed 's/^# \{0,1\}//'
}

# Handles the options every script shares; anything else is kept in NB_REMAINING_ARGS.
nb_parse_common_options() {
  NB_SCRIPT_PATH="${NB_SCRIPT_PATH:-$0}"
  NB_REMAINING_ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verify-setup) VERIFY_ONLY="true"; shift ;;
      --timestamp)
        [[ $# -ge 2 ]] || log_die "--timestamp requires a value"
        FILENAME_TIMESTAMP="$2"; shift 2 ;;
      -h|--help) nb_usage; exit 0 ;;
      *) NB_REMAINING_ARGS+=("$1"); shift ;;
    esac
  done
}

# For scripts without options of their own: anything left over is an error.
nb_reject_remaining_args() {
  if [[ ${#NB_REMAINING_ARGS[@]} -gt 0 ]]; then
    log_die "Unknown option: ${NB_REMAINING_ARGS[0]} (try --help)"
  fi
}

#########################################################
# System detection and directories
#########################################################
CPU_CORES="" RAM_MB="" RAM_PROFILE="" SSD_PRESENT="" PC_TYPE="" DESKTOP="" DISTRO="" CPU_MODEL=""

nb_infer_system() {
  # The get_*.sh detection scripts live in GETTERS_DIR (default: $SYSUPDATE_CODE_BASE_DIR/linux/commong).
  local common="${GETTERS_DIR:-${SYSUPDATE_CODE_BASE_DIR}/linux/commong}" g
  [[ -d "$common" ]] || log_die "Detection scripts directory not found: ${common} (set GETTERS_DIR or SYSUPDATE_CODE_BASE_DIR)"
  for g in get_cpu_cores get_ram_size get_ram_profile get_ssd_present get_pc_type get_desktop_env get_distro_name get_cpu_model; do
    [[ -r "${common}/${g}.sh" ]] || log_die "Missing detection script: ${common}/${g}.sh (set GETTERS_DIR if the get_*.sh files are elsewhere)"
  done
  CPU_CORES=$(sh "${common}/get_cpu_cores.sh")
  RAM_MB=$(sh "${common}/get_ram_size.sh")
  RAM_PROFILE=$(sh "${common}/get_ram_profile.sh")     # low | mid | high
  SSD_PRESENT=$(sh "${common}/get_ssd_present.sh")     # true | false
  PC_TYPE=$(sh "${common}/get_pc_type.sh")             # laptop | desktop | server
  DESKTOP=$(sh "${common}/get_desktop_env.sh")         # kde | gnome | ...
  DISTRO=$(sh "${common}/get_distro_name.sh")          # fedora | ...
  CPU_MODEL=$(sh "${common}/get_cpu_model.sh")
  log_info "User=${REAL_USER}  Distro=${DISTRO}  Desktop=${DESKTOP}  PC=${PC_TYPE}  RAM=${RAM_MB}MB (${RAM_PROFILE})  CPU=${CPU_CORES}x ${CPU_MODEL}  SSD=${SSD_PRESENT}"
}

# nb_mkdir <mode> <dir>...  creates directories OWNED BY THE REAL USER, including any missing parents.
# As root it creates them through `runuser` (so parents are not left root-owned, which `install -d -o`
# would do); as the user it is a plain mkdir. The leaf directory then gets the requested mode.
nb_mkdir() {
  local mode="$1" d; shift
  for d in "$@"; do
    if [[ ${EUID} -eq 0 ]]; then runuser -u "$REAL_USER" -- mkdir -p "$d"; else mkdir -p "$d"; fi
    chmod "$mode" "$d"
  done
}

# Directories under the user's nb folder must belong to the user even when the script runs as root.
nb_prepare_script_dirs() {
  nb_mkdir 0755 "$SCRIPT_DATA" "$SCRIPT_DATA_DOWNLOADS" "$SCRIPT_DATA_BACKUPS" "$@"
}

# nb_run_as_real_user "<shell command>"  - run a command line as the real user (login shell when started as root).
nb_run_as_real_user() {
  if [[ ${EUID} -eq 0 ]]; then runuser -l "$REAL_USER" -c "$1"; else bash -c "$1"; fi
}

#########################################################
# Small utilities
#########################################################
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# True if a command exists in the real user's LOGIN environment (e.g. ~/.local/bin/uv).
user_has_cmd() { nb_run_as_real_user "command -v '$1'" >/dev/null 2>&1; }

require_fedora() {
  [[ "$DISTRO" == "fedora" ]] || log_die "This part is Fedora specific (dnf). Detected distro: ${DISTRO}"
}

is_kde() { [[ "$DESKTOP" == "kde" ]]; }

# render "<template>" KEY=value ...   replaces @KEY@ markers. Plain bash replacement (not sed), so
# values containing slashes, dollars or ampersands cannot break anything.
render() {
  local out="$1"; shift
  local kv
  for kv in "$@"; do
    out="${out//@${kv%%=*}@/${kv#*=}}"
  done
  printf '%s' "$out"
}

# write_file <path> <owner> <group> <mode> <content>
# Written to a temporary file in the SAME directory, then renamed: a crash can never leave a
# half-written file behind.
write_file() {
  local path="$1" owner="$2" group="$3" mode="$4" content="$5" tmp
  tmp="$(mktemp "${path}.XXXXXX")"
  printf '%s\n' "$content" > "$tmp"
  # Only root can give a file to somebody else; a normal user already owns what they create.
  if [[ ${EUID} -eq 0 ]]; then chown "${owner}:${group}" "$tmp"; fi
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$path"
}

# Optional ntfy notification (NTFY_URL e.g. https://ntfy.sh/<topic>).
nb_notify() {
  if [[ -n "${NTFY_URL:-}" ]] && has_cmd curl; then
    curl -fsS -m 10 -d "$1" "$NTFY_URL" >/dev/null 2>&1 || true
  fi
}

#########################################################
# Verification framework
#########################################################
VERIFY_PASS=0
VERIFY_FAIL=0
VERIFY_WARN=0

nb_verify_begin() { VERIFY_PASS=0; VERIFY_FAIL=0; VERIFY_WARN=0; log_header "Verification"; }

# check "<description>" <command...>   counts and prints pass/fail.
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    log_success "$desc"; VERIFY_PASS=$((VERIFY_PASS + 1))
  else
    log_error "$desc"; VERIFY_FAIL=$((VERIFY_FAIL + 1))
  fi
}

nb_verify_warn() { log_warn "$1"; VERIFY_WARN=$((VERIFY_WARN + 1)); }

nb_verify_end() {
  log_info "Passed: ${VERIFY_PASS}  Failed: ${VERIFY_FAIL}  Warnings: ${VERIFY_WARN}"
  if (( VERIFY_FAIL > 0 )); then
    log_error "Verification failed. See Troubleshooting at the bottom of the script."
    return 1
  fi
  log_success "Verification passed"
}

# An interactive zsh for the real user must start without errors. Output is captured, so the
# `-t 1` guard in .zshrc keeps torsocks (and its banner) out of this test.
nb_user_zsh_starts_clean() {
  local out
  out="$(nb_run_as_real_user "TERM=xterm-256color zsh -i -c exit" 2>&1 </dev/null)" || return 1
  ! grep -Eiq 'insecure|no such file|command not found|permission denied|parse error|not found:|plugin .* not found' <<<"$out"
}

nb_compaudit_is_clean() {
  local out
  out="$(nb_run_as_real_user "zsh -i -c 'autoload -Uz compaudit; compaudit'" 2>/dev/null </dev/null)" || true
  [[ -z "$out" ]]
}

# nb_zsh_function_exists <function>: is it defined in a fresh interactive zsh of the real user?
nb_zsh_function_exists() {
  [[ "$(nb_run_as_real_user "zsh -i -c 'print \${+functions[$1]}'" 2>/dev/null </dev/null | tail -n1)" == "1" ]]
}

# A path (and everything under it) must be root-owned and not writable by group/other.
nb_tree_is_locked() {
  local p
  for p in "$@"; do
    [[ -e "$p" ]] || continue
    [[ -z "$(find "$p" \( -perm -g+w -o -perm -o+w \) ! -type l -print -quit)" ]] || return 1
    [[ "$(stat -c %U "$p")" == "root" ]] || return 1
  done
}
