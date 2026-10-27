#!/usr/bin/env bash
# =============================================================================
#  proton_ag_ge.sh  --  Install Proton desktop apps on Fedora (KDE-friendly)
# =============================================================================
#  Merged replacement for the old two-script setup (proton_get_sha.sh +
#  download/install script).  Single file, named options only.
#
#  What it does
#    1. Proton VPN  : official dnf repository (the Proton-recommended route).
#    2. --setup-type full additionally installs Authenticator, Pass, Mail, Meet
#       from the RPM listed in each product's version.json, after a SHA-512
#       check taken from the SAME manifest record as the download URL.
#
#  Failure policy
#    One product failing (manifest missing, download error, hash mismatch,
#    dnf error ...) NEVER stops the others.  At the end you get a success list
#    and a failure list (log_success / log_error), also saved to files.
#    Exit status: 0 = everything requested succeeded, 1 = at least one failure,
#    2 = usage / environment problem before anything was attempted.
#
#  Why there is no `set -e`
#    errexit is silently switched off inside `if f; then` / `f || g` contexts,
#    so it gives a false sense of safety, and it contradicts "keep going when
#    one app fails".  Instead every step is checked explicitly and reports a
#    reason through fail().  We DO use `set -u` (typos in variable names become
#    errors) and `pipefail` (a failing curl in `curl | grep` is not hidden).
#    We do NOT use `set -x`: it prints every command, which is noisy and can
#    leak things into logs.
# =============================================================================

######### Usage: Version 1: all options
# PROTON_SCRIPT="$SYSUPDATE_CODE_BASE_DIR/linux/fedora/proton_ag_ge.sh"   # adjust to wherever you keep it

# proton_rc=0
# bash "$PROTON_SCRIPT" \
#   --setup-type "$SETUP_TYPE" \
#   --desktop "$DESKTOP" \
#   --filename-timestamp "$FILENAME_TIMESTAMP" \
#   --real-user "$REAL_USER" \
#   --home-dir "$HOME_DIR" \
#   --script-data-dir "$SCRIPT_DATA_DIR" \
#   --sysupdate-code-base-dir "$SYSUPDATE_CODE_BASE_DIR" \
#   --channel "$CHANNEL" \
#   --min-rollout "$MIN_ROLLOUT" \
#   || proton_rc=$?

# case "$proton_rc" in
#   0) log_success "Proton setup finished with no failures." ;;
#   1) log_warn "Proton setup finished, but some apps failed. See failed.txt and run.log in the run directory." ;;
#   *) log_error "Proton setup did not start (exit $proton_rc): bad option or environment problem." ;;
# esac

######### Usage: Version 2: only setup type and desktop
# proton_rc=0
# bash "$PROTON_SCRIPT" --setup-type "$SETUP_TYPE" --desktop "$DESKTOP" || proton_rc=$?

# =============================================================================

set -u
set -o pipefail
# Everything this script creates (downloads, logs, backups) is private to the
# user.  sudo'd commands get a normal umask via as_root() below, otherwise
# rpm/dnf could create root-owned files with odd modes.
umask 077


# -----------------------------------------------------------------------------
#  DESIGN NOTES
# -----------------------------------------------------------------------------
#  1. version.json shape (as you documented it):
#       { "Releases": [ { "CategoryName": "Stable",   <- Stable|EarlyAccess|Beta|Alpha
#                         "Version": "1.42.0",
#                         "RolloutPercentage": 1,       <- or "RolloutProportion", or absent
#                         "File": [ { "Identifier": ".rpm (Fedora/RHEL)",
#                                     "Url": "...", "Sha512CheckSum": "..." } ] } ] }
#
#  2. THE CRITICAL RULE: Url and Sha512CheckSum always come from the SAME File
#     object, in one jq pass.  Never pair a "generic latest" URL with a hash
#     looked up elsewhere: the CDN lags behind the manifest during staged
#     rollouts, which is what caused the old "checksum failed" errors.
#
#  3. Rollout gate.  Rollout values are fractions (0.05 = 5 %, 1 = 100 %).  A
#     missing field means "fully available".  Default MIN_ROLLOUT is 1, i.e. we
#     only install builds Proton has rolled out to everybody; if the newest
#     stable build is only at 20 %, we take the newest build that IS at 100 %.
#     This is the same thing Proton's staged rollout is designed to protect you
#     from (a bad build reaching everyone).  Use --min-rollout 0 to take the
#     newest build regardless.  A present-but-unparseable value counts as 0.
#
#  4. Manifest URL candidates.  Proton has moved download paths before (Pass was
#     under /PassDesktop/linux/x64/ and the deb URLs now live under
#     /pass/linux/x64/).  For Pass we therefore query every candidate and take the
#     highest version across all of them, so a stale-but-still-served old
#     manifest can never win.  Candidates that 404 are skipped silently.
#     ONLY the first Pass URL and the Authenticator/Mail/Meet URLs come from
#     your notes; the extra Pass URLs are my educated guesses (harmless if 404).
#
#  5. Proton VPN has no version.json.  The repo exposes an Apache directory
#     listing.  We extract *.rpm filename tokens (no HTML parsing) and let
#     `sort -V` choose the highest.  The old `grep .rpm` assumed exactly one
#     file in the directory.
#
#  6. What the SHA-512 does and does not give you.  Hash + URL both come from
#     proton.me over TLS, so the check catches corruption, truncated downloads
#     and CDN/rollout mismatches.  It does NOT protect against a compromised
#     proton.me (attacker controls both).  Proton's app RPMs carry no separate
#     signature we can check against an independently obtained key, so that is
#     the honest limit.  Extra layers we add: HTTPS-only + TLS1.2+, a host
#     allow-list for the download URL, an RPM sanity/arch check, an optional
#     ClamAV scan, and (VPN) an optional key-fingerprint pin.
# -----------------------------------------------------------------------------


#######################################################
# Colors and logging helpers
#######################################################
# Colors only when stdout is a terminal and NO_COLOR is not set.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  readonly GREEN=$'\033[0;32m' YELLOW=$'\033[1;33m' RED=$'\033[0;31m'
  readonly BLUE=$'\033[0;34m' CYAN=$'\033[0;36m' NC=$'\033[0m'
else
  readonly GREEN='' YELLOW='' RED='' BLUE='' CYAN='' NC=''
fi

LOG_FILE=""   # set once the run directory exists; every message is mirrored there

# Append a plain-text (no colour) copy of a message to the log file.
_to_log() { [[ -n "$LOG_FILE" ]] && printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"; return 0; }

log_step()    { printf '\n%s== %s ==%s\n' "$CYAN" "$*" "$NC"; _to_log "== $* =="; }
log_info()    { printf '%s[INFO]%s %s\n' "$BLUE" "$NC" "$*"; _to_log "[INFO] $*"; }
log_success() { printf '%s[✓]%s %s\n' "$GREEN" "$NC" "$*"; _to_log "[OK] $*"; }
log_warn()    { printf '%s[!]%s %s\n' "$YELLOW" "$NC" "$*"; _to_log "[WARN] $*"; }
log_error()   { printf '%s[✗]%s %s\n' "$RED" "$NC" "$*" >&2; _to_log "[ERROR] $*"; }
# Printing user data with %s (never inside the format string) means a '%' or
# backslash in a message can not be misinterpreted by printf.
die()         { log_error "$*"; exit 2; }

# Per-product failure plumbing.  fail() records WHY, logs it, and returns 1 so
# callers can write:   something || { fail "reason"; return 1; }
CURRENT_NAME=""; FAIL_REASON=""; LAST_OK_DETAIL=""
fail() { FAIL_REASON="$*"; log_error "$CURRENT_NAME: $*"; return 1; }

declare -a SUCCEEDED=() FAILED=()

# run_step "Display name" function args...
# Runs one product installer in isolation and files the result.
run_step() {
  CURRENT_NAME="$1"; shift
  FAIL_REASON=""; LAST_OK_DETAIL=""
  if "$@"; then
    SUCCEEDED+=("${LAST_OK_DETAIL:-$CURRENT_NAME}")
  else
    FAILED+=("$CURRENT_NAME -- ${FAIL_REASON:-unknown reason (see $LOG_FILE)}")
  fi
}

# Run a command, show its output AND append it to the log; return ITS status
# (not tee's).  Used for dnf / clamscan so failures are diagnosable later.
run_logged() { "$@" 2>&1 | tee -a "$LOG_FILE"; return "${PIPESTATUS[0]}"; }

# Run a command as root with a sane umask (see top of file).
as_root() { sudo bash -c 'umask 022; exec "$@"' _ "$@"; }


#######################################################
# Defaults (variable names kept identical to the calling script)
#######################################################
REAL_USER=""
HOME_DIR=""
SCRIPT_DATA_DIR=""
SYSUPDATE_CODE_BASE_DIR=""
SETUP_TYPE="light"
DESKTOP=""
FILENAME_TIMESTAMP=""
CHANNEL="stable"          # stable | beta | earlyaccess | alpha
MIN_ROLLOUT="1"           # fraction 0..1, see DESIGN NOTE 3
DRY_RUN=0                 # 1 = resolve and print only; no download/install
SKIP_INSTALL=0            # 1 = download + verify, but do not run dnf
SCAN_MODE="auto"          # auto = use clamscan if installed | no
VPN_KEY_FINGERPRINT=""    # optional pin for the Proton VPN repo signing key

# Download URLs must be https and on one of these hosts (extended regex).
# Edit this if Proton ever serves files from a new domain.
PROTON_ALLOWED_URL_REGEX='^https://([a-z0-9-]+\.)*(proton\.me|protonvpn\.com)/'

usage() {
  cat <<'USAGE'
Usage: proton_ag_ge.sh [options]

  -t, --setup-type light|full     light = Proton VPN only (default)
                                  full  = VPN + Authenticator, Pass, Mail, Meet
  -d, --desktop NAME              kde|gnome|...  (auto-detected if omitted)
      --filename-timestamp TS     run-directory suffix (default: now)
      --real-user USER            must be the invoking user (default: current)
      --home-dir PATH             default: home of the user
      --script-data-dir PATH      default: ~/nb/nb_script_data
      --sysupdate-code-base-dir P default: ~/nb/CodeProjects/system_update
      --channel CH                stable|beta|earlyaccess|alpha (default stable)
      --min-rollout N             0..1 (default 1 = only fully rolled-out builds)
      --vpn-key-fingerprint FPR   require this fingerprint for the VPN repo key
      --no-scan                   skip the ClamAV scan even if clamscan exists
      --dry-run                   resolve versions/URLs only; change nothing
      --skip-install              download and verify, but do not install
  -h, --help                      show this help
Both "--opt value" and "--opt=value" are accepted.
USAGE
}


#######################################################
# Argument parsing
#######################################################
parse_args() {
  # Split "--opt=value" into "--opt" "value" so both styles work.
  local -a args=(); local a
  for a in "$@"; do
    if [[ "$a" == --*=* ]]; then args+=("${a%%=*}" "${a#*=}"); else args+=("$a"); fi
  done
  set -- "${args[@]}"

  while (($#)); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --dry-run) DRY_RUN=1; shift; continue ;;
      --skip-install) SKIP_INSTALL=1; shift; continue ;;
      --no-scan) SCAN_MODE="no"; shift; continue ;;
    esac
    # Everything below takes a value.  An EMPTY value is allowed on purpose:
    # a calling script may pass --desktop "$DESKTOP" with DESKTOP unset, which
    # must mean "auto-detect", not "error".
    case "$1" in
      -t|--setup-type|-d|--desktop|--filename-timestamp|--real-user|--home-dir|--script-data-dir|\
      --sysupdate-code-base-dir|--channel|--min-rollout|--vpn-key-fingerprint) ;;
      *) die "Unknown option: $1 (see --help)" ;;
    esac
    (($# >= 2)) || die "Option $1 needs a value (see --help)"
    case "$1" in
      -t|--setup-type)            SETUP_TYPE="$2" ;;
      -d|--desktop)               DESKTOP="$2" ;;
      --filename-timestamp)       FILENAME_TIMESTAMP="$2" ;;
      --real-user)                REAL_USER="$2" ;;
      --home-dir)                 HOME_DIR="$2" ;;
      --script-data-dir)          SCRIPT_DATA_DIR="$2" ;;
      --sysupdate-code-base-dir)  SYSUPDATE_CODE_BASE_DIR="$2" ;;
      --channel)                  CHANNEL="$2" ;;
      --min-rollout)              MIN_ROLLOUT="$2" ;;
      --vpn-key-fingerprint)      VPN_KEY_FINGERPRINT="$2" ;;
      *) die "Unknown option: $1 (see --help)" ;;
    esac
    shift 2
  done
}

# Fill defaults for empty values and validate everything that ends up in a path,
# a URL or a jq filter.
resolve_settings() {
  [[ "$(id -u)" -ne 0 ]] || die "Do not run as root or with sudo; the script calls sudo only where needed (a root run would also put downloads/logs under root's ownership)."

  local me; me="$(id -un)"
  : "${REAL_USER:=$me}"
  [[ "$REAL_USER" == "$me" ]] || die "--real-user ($REAL_USER) differs from the invoking user ($me). Run the script as that user instead."

  if [[ -z "$HOME_DIR" ]]; then HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"; fi
  [[ -n "$HOME_DIR" && -d "$HOME_DIR" ]] || die "Could not determine home directory for $REAL_USER"

  NBDIR="$HOME_DIR/nb"
  : "${SCRIPT_DATA_DIR:=$NBDIR/nb_script_data}"
  : "${SYSUPDATE_CODE_BASE_DIR:=$NBDIR/CodeProjects/system_update}"
  : "${FILENAME_TIMESTAMP:=$(date +%Y-%m-%d_%H-%M-%S)}"

  SETUP_TYPE="${SETUP_TYPE,,}"; : "${SETUP_TYPE:=light}"
  CHANNEL="${CHANNEL,,}";       : "${CHANNEL:=stable}"
  : "${MIN_ROLLOUT:=1}"

  case "$SETUP_TYPE" in light|full) ;; *) die "--setup-type must be 'light' or 'full'" ;; esac
  case "$CHANNEL" in stable|beta|earlyaccess|alpha) ;; *) die "--channel must be stable|beta|earlyaccess|alpha" ;; esac
  [[ "$MIN_ROLLOUT" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "--min-rollout must be a number such as 1 or 0.5"
  [[ "$FILENAME_TIMESTAMP" =~ ^[A-Za-z0-9._-]+$ ]] || die "--filename-timestamp may contain only letters, digits, . _ -"
  [[ "$SCRIPT_DATA_DIR" == /* ]] || die "--script-data-dir must be an absolute path"
  VPN_KEY_FINGERPRINT="${VPN_KEY_FINGERPRINT^^}"; VPN_KEY_FINGERPRINT="${VPN_KEY_FINGERPRINT// /}"
  if [[ -n "$VPN_KEY_FINGERPRINT" && ! "$VPN_KEY_FINGERPRINT" =~ ^[0-9A-F]{40}$ ]]; then
    die "--vpn-key-fingerprint must be 40 hex characters"
  fi

  SCRIPT_DOWNLOADS_DIR="$SCRIPT_DATA_DIR/downloads"
  PROTON_DOWNLOADS_DIR_BASE="$SCRIPT_DOWNLOADS_DIR/proton_ag"
  PROTON_CURRENT_DOWNLOADS_DIR="$PROTON_DOWNLOADS_DIR_BASE/proton_ag_${FILENAME_TIMESTAMP}"
  SYSUPDATE_FEDORA_CODE_DIR="$SYSUPDATE_CODE_BASE_DIR/linux/fedora"
  BACKUP_DIR="$PROTON_CURRENT_DOWNLOADS_DIR/backup"
  MANIFEST_DIR="$PROTON_CURRENT_DOWNLOADS_DIR/manifests"
}


#######################################################
# Environment detection
#######################################################
normalise_desktop() {
  case "${1,,}" in
    *kde*|*plasma*) printf kde ;;
    *gnome*)        printf gnome ;;
    '')             printf unknown ;;
    *)              printf '%s' "${1,,}" ;;
  esac
}

detect_desktop() {
  local raw="$DESKTOP" helper="$SYSUPDATE_CODE_BASE_DIR/linux/common/get_desktop_env.sh"
  # 1) value from caller  2) your helper script  3) the session's own variables
  if [[ -z "$raw" && -r "$helper" ]]; then raw="$(bash "$helper" 2>/dev/null | head -n1)"; fi
  [[ -n "$raw" ]] || raw="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
  DESKTOP="$(normalise_desktop "$raw")"
}

detect_fedora_version() {
  # `rpm -E %fedora` is canonical and immune to /etc/fedora-release wording
  # (e.g. "Fedora Asahi Remix release 43" breaks `cut -d' ' -f3`).
  local from_rpm from_helper helper="$SYSUPDATE_FEDORA_CODE_DIR/get_fedora_release_version.sh"
  from_rpm="$(rpm -E %fedora 2>/dev/null)"
  [[ "$from_rpm" =~ ^[0-9]+$ ]] || from_rpm=""
  from_helper=""
  [[ -r "$helper" ]] && from_helper="$(sh "$helper" 2>/dev/null | head -n1)"
  [[ "$from_helper" =~ ^[0-9]+$ ]] || from_helper=""

  if [[ -n "$from_rpm" && -n "$from_helper" && "$from_rpm" != "$from_helper" ]]; then
    log_warn "Your helper says Fedora $from_helper but rpm says $from_rpm; trusting rpm."
  fi
  FEDORA_RELEASE_VERSION="${from_rpm:-$from_helper}"
  [[ -n "$FEDORA_RELEASE_VERSION" ]] || die "Could not determine the Fedora release number (is this Fedora?)"
}

require_tools() {
  local t missing=0
  for t in curl rpm dnf sudo sha512sum sort sed grep tee mktemp cut head tail uname getent; do
    command -v "$t" >/dev/null 2>&1 || { log_error "Required command not found: $t"; missing=1; }
  done
  ((missing == 0)) || die "Install the missing tools and re-run."
}


#######################################################
# Network + verification primitives
#######################################################
# fetch URL DEST MAX_SECONDS
# HTTPS only (also across redirects), TLS >= 1.2, retries on transient errors
# (not on 404, so probing candidate URLs stays fast).  Written to DEST.part and
# renamed on success so a half-finished download never looks complete.
fetch() {
  local url="$1" dest="$2" max="$3"
  if curl --proto '=https' --proto-redir '=https' --tlsv1.2 \
          --fail --silent --show-error --location \
          --retry 3 --retry-delay 2 --connect-timeout 15 --max-time "$max" \
          --output "$dest.part" "$url" 2>>"${LOG_FILE:-/dev/null}"; then
    mv -f -- "$dest.part" "$dest"
  else
    rm -f -- "$dest.part"; return 1
  fi
}

url_is_allowed() { [[ "$1" =~ $PROTON_ALLOWED_URL_REGEX ]]; }

# Print the safe local file name for a URL, or fail.  Query strings are
# stripped, and only a plain name ending in .rpm is accepted (no path tricks).
rpm_filename_from_url() {
  local n="${1%%[?#]*}"; n="${n##*/}"
  [[ "$n" =~ ^[A-Za-z0-9._+-]+\.rpm$ ]] || return 1
  printf '%s' "$n"
}

verify_sha512() {
  local file="$1" expected="$2" actual
  actual="$(sha512sum "$file" | cut -d' ' -f1)"
  if [[ "$actual" == "$expected" ]]; then
    log_success "$CURRENT_NAME: SHA-512 verified"
    return 0
  fi
  log_error "expected: $expected"
  log_error "actual:   $actual"
  # Rename so the bad file can never be installed by accident.
  mv -f -- "$file" "$file.REJECTED"
  fail "SHA-512 mismatch (file quarantined as $(basename "$file").REJECTED)"
  return 1
}

# Basic sanity of a downloaded RPM before root touches it.
inspect_rpm() {
  local f="$1" name arch
  name="$(rpm -qp --qf '%{NAME}' "$f" 2>/dev/null)" || { fail "file is not a readable RPM"; return 1; }
  arch="$(rpm -qp --qf '%{ARCH}' "$f" 2>/dev/null)"
  case "$arch" in
    noarch|"$(uname -m)") ;;
    *) fail "RPM architecture '$arch' does not match this machine ($(uname -m))"; return 1 ;;
  esac
  log_info "$CURRENT_NAME: package '$name', arch $arch"
  # Informational only: Proton's app RPMs may be unsigned or signed with a key
  # that is not in your keyring, so NOKEY here is expected and not an error.
  log_info "$CURRENT_NAME: rpm signature status: $(rpm --checksig "$f" 2>&1 | tail -n1)"
}

# Optional ClamAV scan.  Infected = failure.  Scanner errors (for example a
# missing signature database on a fresh install) only warn, because a broken
# scanner must not block installs; the SHA-512 check already passed.
scan_file() {
  [[ "$SCAN_MODE" == "no" ]] && return 0
  if ! command -v clamscan >/dev/null 2>&1; then
    log_info "$CURRENT_NAME: clamscan not installed; skipping AV scan"
    return 0
  fi
  log_info "$CURRENT_NAME: scanning with ClamAV (loading signatures can take a while)"
  run_logged as_root clamscan --no-summary --infected "$1"
  case $? in
    0) log_success "$CURRENT_NAME: ClamAV found nothing"; return 0 ;;
    1) fail "ClamAV reports the file as INFECTED"; return 1 ;;
    *) log_warn "$CURRENT_NAME: clamscan could not run properly (exit $?); continuing"; return 0 ;;
  esac
}


#######################################################
# Manifest handling (version.json)
#######################################################
# select_rpm_rows MANIFEST -> prints "version<TAB>url<TAB>sha512" for EVERY File
# entry that satisfies all of:
#   * CategoryName equals $CHANNEL (case-insensitive)
#   * rollout >= $MIN_ROLLOUT  (RolloutPercentage, else RolloutProportion,
#     else 1 when neither exists; unparseable counts as 0)
#   * Url is https and ends in .rpm, and Identifier (if present) mentions rpm
#   * architecture suits this machine (x86_64 hosts skip arm builds)
#   * Sha512CheckSum is a valid 128-hex digest
# Url and hash are read from the same File object -- DESIGN NOTE 2.
select_rpm_rows() {
  jq -r --arg chan "$CHANNEL" --arg min "$MIN_ROLLOUT" --arg arch "$(uname -m)" '
    def roll:
      (.RolloutPercentage // .RolloutProportion) as $r
      | if $r == null then 1 else ($r | try tonumber catch 0) end;
    def isrpm:
      ((.Url // "") | test("\\.rpm([?#].*)?$"; "i"))
      and (((.Identifier // "rpm") | test("rpm"; "i")));
    def archok:
      (.Url // "") as $u
      | if   $arch == "x86_64"  then ($u | test("aarch64|arm64|armv[0-9]"; "i") | not)
        elif $arch == "aarch64" then ($u | test("aarch64|arm64"; "i"))
        else true end;

    .Releases[]?
    | select(((.CategoryName // "") | ascii_downcase) == $chan)
    | select(roll >= ($min | tonumber))
    | . as $rel
    | ($rel.File // [])[]
    | select(isrpm and archok)
    | select((.Url // "") | test("^https://"; "i"))
    | select((.Sha512CheckSum // "") | test("^[A-Fa-f0-9]{128}$"))
    | [ (($rel.Version // "") | tostring), .Url, (.Sha512CheckSum | ascii_downcase) ]
    | @tsv
  ' "$1"
}

# resolve_latest_rpm KEY URL...
# Downloads every candidate manifest, collects all qualifying rows and keeps the
# highest version (sort -V).  Sets RESOLVED_VERSION / _URL / _SHA.  Results are
# returned in globals rather than printed so log messages cannot be swallowed
# by $(...) command substitution.
RESOLVED_VERSION=""; RESOLVED_URL=""; RESOLVED_SHA=""
resolve_latest_rpm() {
  local key="$1"; shift
  local url mf rows all="" best i=0
  RESOLVED_VERSION=""; RESOLVED_URL=""; RESOLVED_SHA=""

  for url in "$@"; do
    i=$((i + 1))
    mf="$MANIFEST_DIR/${key}_version_${i}.json"
    if ! fetch "$url" "$mf" 120; then
      log_info "$CURRENT_NAME: manifest not available at $url"
      continue
    fi
    if ! jq -e '(.Releases | type == "array") and (.Releases | length > 0)' "$mf" >/dev/null 2>&1; then
      log_warn "$CURRENT_NAME: $url is not a valid manifest; ignoring"
      continue
    fi
    if ! rows="$(select_rpm_rows "$mf")"; then
      log_warn "$CURRENT_NAME: could not parse $mf; ignoring"
      continue
    fi
    [[ -n "$rows" ]] && all+="$rows"$'\n'
    log_info "$CURRENT_NAME: manifest ok: $url"
  done

  best="$(printf '%s' "$all" | sed '/^$/d' | sort -V -t $'\t' -k1,1 | tail -n1)"
  [[ -n "$best" ]] || return 1
  IFS=$'\t' read -r RESOLVED_VERSION RESOLVED_URL RESOLVED_SHA <<<"$best"
  [[ -n "$RESOLVED_VERSION" && -n "$RESOLVED_URL" && -n "$RESOLVED_SHA" ]]
}

manifest_urls_for() {
  case "$1" in
    ProtonAuthenticator) printf '%s\n' "https://proton.me/download/authenticator/linux/version.json" ;;
    ProtonPass)          printf '%s\n' \
                           "https://proton.me/download/PassDesktop/linux/x64/version.json" \
                           "https://proton.me/download/pass/linux/x64/version.json" \
                           "https://proton.me/download/pass/linux/version.json" ;;
    ProtonMail)          printf '%s\n' "https://proton.me/download/mail/linux/version.json" ;;
    ProtonMeet)          printf '%s\n' "https://proton.me/download/meet/linux/version.json" ;;
    *) return 1 ;;
  esac
}


#######################################################
# Backups (before anything is modified)
#######################################################
# Copies existing Proton repo definitions/keys and records which Proton packages
# are installed, so a half-broken previous setup can be inspected or restored.
backup_existing_state() {
  log_step "Backing up existing Proton state"
  mkdir -p "$BACKUP_DIR"
  local f found=0
  shopt -s nullglob
  for f in /etc/yum.repos.d/*[Pp]roton*.repo /etc/pki/rpm-gpg/*[Pp]roton*; do
    cp -a -- "$f" "$BACKUP_DIR/" && { log_info "backed up $f"; found=1; }
  done
  shopt -u nullglob
  ((found)) || log_info "no existing Proton repo/key files found (fresh system?)"
  rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | grep -i proton | sort \
    >"$BACKUP_DIR/installed_proton_packages.txt"
  log_info "package inventory: $BACKUP_DIR/installed_proton_packages.txt"
  # Has the installed repo package been tampered with / hand-edited?
  local pkg=protonvpn-stable-release
  if rpm -q "$pkg" >/dev/null 2>&1 && ! rpm -V "$pkg" >/dev/null 2>&1; then
    log_warn "$pkg is installed but its files differ from the package (hand-edited?). Originals are saved in $BACKUP_DIR; inspect with: rpm -V $pkg"
  fi
}


#######################################################
# Proton VPN (dnf repository method)
#######################################################
install_proton_vpn() {
  local root="https://repo.protonvpn.com/fedora-${FEDORA_RELEASE_VERSION}-stable"
  local base="$root/protonvpn-stable-release"
  local index="$MANIFEST_DIR/protonvpn_index.html" rpm_name

  log_step "Proton VPN"
  fetch "$base/" "$index" 120 \
    || { fail "cannot read $base/ (does Proton publish a repo for Fedora $FEDORA_RELEASE_VERSION yet?)"; return 1; }

  # Token extraction + version sort; see DESIGN NOTE 5.  The strict pattern
  # also guarantees the name is safe to use as a file name.
  rpm_name="$(grep -oE 'protonvpn-stable-release-[0-9][0-9.]*-[0-9]+\.noarch\.rpm' "$index" | sort -Vu | tail -n1)"
  [[ -n "$rpm_name" ]] || { fail "no protonvpn-stable-release RPM found in the repo index"; return 1; }
  log_info "bootstrap package: $rpm_name"

  if ((DRY_RUN)); then
    LAST_OK_DETAIL="Proton VPN repo package $rpm_name (dry-run, nothing downloaded)"
    return 0
  fi

  local rpm_file="$PROTON_CURRENT_DOWNLOADS_DIR/$rpm_name" key_file="$PROTON_CURRENT_DOWNLOADS_DIR/protonvpn_public_key.asc"
  fetch "$base/$rpm_name" "$rpm_file" 300 || { fail "download of $rpm_name failed"; return 1; }
  inspect_rpm "$rpm_file" || return 1

  # --- repository signing key ------------------------------------------------
  # The bootstrap RPM ships the repo definition + key, so it is the trust anchor.
  # Fetching the key from the same host adds little; what DOES add real value is
  # comparing its fingerprint with the one on Proton's support page (a different
  # site).  Pass it with --vpn-key-fingerprint to make that comparison automatic.
  if fetch "$root/public_key.asc" "$key_file" 60; then
    local fpr=""
    if command -v gpg >/dev/null 2>&1; then
      fpr="$(gpg --batch --no-tty --show-keys --with-colons "$key_file" 2>/dev/null | sed -n 's/^fpr:::::::::\([0-9A-F]*\):$/\1/p' | head -n1)"
    fi
    if [[ -n "$fpr" ]]; then
      log_info "repo signing key fingerprint: $fpr"
      log_info "compare with Proton's page: https://protonvpn.com/support/official-linux-vpn-fedora"
      if [[ -n "$VPN_KEY_FINGERPRINT" && "$fpr" != "$VPN_KEY_FINGERPRINT" ]]; then
        fail "repo key fingerprint $fpr does not match the pinned $VPN_KEY_FINGERPRINT"; return 1
      fi
    elif [[ -n "$VPN_KEY_FINGERPRINT" ]]; then
      fail "a fingerprint pin was given but the key fingerprint could not be read (is gpg installed?)"; return 1
    fi

    # Verify the bootstrap RPM's signature against that key using a THROWAWAY
    # rpm database, so your system keyring is untouched.
    local scratch out; scratch="$(mktemp -d "$PROTON_CURRENT_DOWNLOADS_DIR/rpmdb.XXXXXX")"
    if rpm --dbpath "$scratch" --import "$key_file" >>"$LOG_FILE" 2>&1; then
      if out="$(rpm --dbpath "$scratch" --checksig "$rpm_file" 2>&1)"; then
        log_success "bootstrap RPM signature OK ($out)"
      elif grep -qiE 'NOT OK|BAD' <<<"$out"; then
        fail "bootstrap RPM signature check FAILED: $out"; rm -rf -- "$scratch"; return 1
      else
        log_warn "bootstrap RPM could not be fully verified: $out"
      fi
    else
      log_warn "could not import the key into a scratch rpm db; skipping signature check"
    fi
    rm -rf -- "$scratch"
  else
    [[ -z "$VPN_KEY_FINGERPRINT" ]] || { fail "could not fetch the repo key to check the pinned fingerprint"; return 1; }
    log_warn "could not fetch $root/public_key.asc; skipping key checks"
  fi

  scan_file "$rpm_file" || return 1
  if ((SKIP_INSTALL)); then LAST_OK_DETAIL="Proton VPN repo package downloaded (skip-install)"; return 0; fi

  run_logged as_root dnf install -y "$rpm_file" || { fail "installing the repository package failed"; return 1; }
  # dnf auto-imports the repo key (-y) the first time it is used.  On a
  # security-focused box you can instead run it once without -y and compare.
  run_logged as_root dnf install -y proton-vpn-gnome-desktop \
    || { fail "installing proton-vpn-gnome-desktop failed"; return 1; }

  # Tray icon support.  Proton officially supports only GNOME; the GUI is GTK.
  case "$DESKTOP" in
    gnome)
      run_logged as_root dnf install -y libappindicator-gtk3 gnome-shell-extension-appindicator gnome-extensions-app \
        || log_warn "tray-icon packages failed to install (non-fatal)"
      log_warn "GNOME: enable 'AppIndicator and KStatusNotifierItem Support' in the Extensions app before opening Proton VPN."
      ;;
    *)
      # Plasma supports StatusNotifierItem natively.  libappindicator-gtk3 is a
      # small precaution for GTK apps; failure is harmless.
      run_logged as_root dnf install -y libappindicator-gtk3 \
        || log_warn "libappindicator-gtk3 not installed (non-fatal)"
      ;;
  esac
  LAST_OK_DETAIL="Proton VPN (repo package $rpm_name + proton-vpn-gnome-desktop)"
}


#######################################################
# Generic installer for apps that publish version.json
#######################################################
# install_proton_app KEY "Display name"
install_proton_app() {
  local key="$1" name="$2" dest rpm_name version url sha
  local -a urls
  log_step "$name"

  mapfile -t urls < <(manifest_urls_for "$key")
  resolve_latest_rpm "$key" "${urls[@]}" \
    || { fail "no usable manifest, or no '$CHANNEL' RPM with rollout >= $MIN_ROLLOUT in any of them (see the log; --min-rollout 0 also allows partially rolled-out builds)"; return 1; }
  version="$RESOLVED_VERSION"; url="$RESOLVED_URL"; sha="$RESOLVED_SHA"

  url_is_allowed "$url" || { fail "download URL is not on an allowed Proton host: $url"; return 1; }
  rpm_name="$(rpm_filename_from_url "$url")" || { fail "unexpected file name in URL: $url"; return 1; }
  log_info "selected $name $version"
  log_info "  url:    $url"
  log_info "  sha512: $sha"

  if ((DRY_RUN)); then
    LAST_OK_DETAIL="$name $version (dry-run, nothing downloaded)"
    return 0
  fi

  dest="$PROTON_CURRENT_DOWNLOADS_DIR/$rpm_name"
  fetch "$url" "$dest" 900 || { fail "download failed: $url"; return 1; }
  verify_sha512 "$dest" "$sha" || return 1
  inspect_rpm "$dest" || return 1
  scan_file "$dest" || return 1

  if ((SKIP_INSTALL)); then
    LAST_OK_DETAIL="$name $version downloaded and verified (skip-install): $dest"
    return 0
  fi

  # dnf (not bare rpm) so dependencies are resolved from Fedora's repos.
  # Local files are not GPG-checked by dnf by default, which is why the
  # SHA-512 / scan steps above happen first.
  run_logged as_root dnf install -y "$dest" || { fail "dnf install failed (see log)"; return 1; }
  LAST_OK_DETAIL="$name $version"
}


#######################################################
# Main
#######################################################
main() {
  parse_args "$@"
  resolve_settings
  require_tools
  detect_desktop
  detect_fedora_version

  # Fresh run directory; the log file is created first so everything after this
  # point is recorded.
  mkdir -p "$PROTON_CURRENT_DOWNLOADS_DIR" "$MANIFEST_DIR" \
    || die "Cannot create $PROTON_CURRENT_DOWNLOADS_DIR"
  LOG_FILE="$PROTON_CURRENT_DOWNLOADS_DIR/run.log"
  : >"$LOG_FILE"

  log_info "user=$REAL_USER desktop=$DESKTOP fedora=$FEDORA_RELEASE_VERSION setup=$SETUP_TYPE channel=$CHANNEL min-rollout=$MIN_ROLLOUT dry-run=$DRY_RUN"
  log_info "run directory: $PROTON_CURRENT_DOWNLOADS_DIR"

  if ! command -v jq >/dev/null 2>&1; then
    ((DRY_RUN)) && die "jq is required (sudo dnf install jq)"
    log_warn "jq not found; installing it from Fedora's repositories"
    as_root dnf install -y jq >>"$LOG_FILE" 2>&1 || die "Could not install jq"
  fi

  if ! ((DRY_RUN)); then
    sudo -v || die "sudo authentication failed; nothing was changed."
    backup_existing_state
  fi

  run_step "Proton VPN" install_proton_vpn
  if [[ "$SETUP_TYPE" == "full" ]]; then
    run_step "Proton Authenticator" install_proton_app ProtonAuthenticator "Proton Authenticator"
    run_step "Proton Pass"          install_proton_app ProtonPass          "Proton Pass"
    run_step "Proton Mail"          install_proton_app ProtonMail          "Proton Mail"
    run_step "Proton Meet"          install_proton_app ProtonMeet          "Proton Meet"
  fi

  # ---- Summary: what worked, what did not ------------------------------------
  log_step "Summary"
  local item
  : >"$PROTON_CURRENT_DOWNLOADS_DIR/success.txt"; : >"$PROTON_CURRENT_DOWNLOADS_DIR/failed.txt"
  if ((${#SUCCEEDED[@]})); then
    log_success "Succeeded (${#SUCCEEDED[@]}):"
    for item in "${SUCCEEDED[@]}"; do
      log_success "  $item"; printf '%s\n' "$item" >>"$PROTON_CURRENT_DOWNLOADS_DIR/success.txt"
    done
  fi
  if ((${#FAILED[@]})); then
    log_error "Failed (${#FAILED[@]}):"
    for item in "${FAILED[@]}"; do
      log_error "  $item"; printf '%s\n' "$item" >>"$PROTON_CURRENT_DOWNLOADS_DIR/failed.txt"
    done
  fi
  log_info "Full log:   $LOG_FILE"
  log_info "Downloads/manifests kept in: $PROTON_CURRENT_DOWNLOADS_DIR"

  ((${#FAILED[@]} == 0))   # exit status: 0 only if nothing failed -> becomes 1 otherwise
}

# Run main only when executed, not when sourced (lets you test functions).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
  exit $?
fi



# #####################################################################################
# #####################################################################################
# # Multiple versions below used for writing the above final version
# #####################################################################################
# #####################################################################################



# #!/usr/bin/env bash
# #!/bin/sh

# set -eux

# # set -Eeuo pipefail
# # IFS=$'\n\t'
# # umask 077

# # Install Proton desktop apps on Fedora using Proton's version.json metadata.
# # Download URLs and SHA-512 values are selected from the SAME release/file record.


# #####################################################################################
# # # Do not run as root

# # # ################# The following isn't POSIX compliant because EUID is undefined in POSIX
# # # # https://www.baeldung.com/linux/check-script-run-root
# # # if [ ${EUID:-0} -eq 0 ] || [ "$(id -u)" -eq 0 ]; then
# # #   echo "[-] Do not run as root (or with sudo)."
# # #   exit 1
# # # else
# # #     echo "You are running as $(whoami)"
# # # fi

# # # ################# The following isn't POSIX compliant because EUID is undefined in POSIX. This is a shorter version of above
# # # # bool function to test if the user is root or not
# # # is_user_root () { [ "${EUID:-$(id -u)}" -eq 0 ]; }

# # # ################# The following is POSIX compliant
# # # bool function to test if the user is root or not (POSIX only)
# # is_user_root ()
# # {
# #     [ "$(id -u)" -eq 0 ]
# # }

# # REAL_USER="${SUDO_USER:-$USER}"
# # HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# # NBDIR="$HOME_DIR/nb"
# # SYSUPDATE_CODE_BASE_DIR="$NBDIR/CodeProjects/system_update"

# # SCRIPT_DATA_DIR="${NBDIR}/nb_script_data"
# # FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"


# # # DO NOT initialize these here. Pass them instead while calling this script
# # SETUP_TYPE=""
# # DESKTOP=""


# # if [[ -z $1 ]];
# # then 
# #     echo "SETUP_TYPE not provided. Assuming light installation."
# #     SETUP_TYPE="light"

# # else
# #   SETUP_TYPE=$1
# #   echo "SETUP_TYPE = $SETUP_TYPE"

# #   if [ "$SETUP_TYPE" = "full" ];
# #   then 
# #       echo "Installing all ProtonAG stuff."
      
# #   elif [ "$SETUP_TYPE" = "light" ];
# #   then
# #       echo "Only installing ProtonVPN"

# #   fi

# # fi

# # if [[ -z $2 ]];
# # then
# #   echo "DESKTOP not provided. Identifying."
# #   DESKTOP=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_desktop_env.sh)

# # else 
# #   DESKTOP=$2
# # fi

# # echo "The current DESKTOP is $DESKTOP."


# # sleep 5s

# # # ################# The following is example usage of POSIX compliant function above
# # # if is_user_root; then
# # #     echo 'You are the almighty root!'
# # #     # You can do whatever you need...
# # # else
# # #     echo 'You are just an ordinary user.' >&2
# # #     exit 1
# # # fi

# # if ! is_user_root; then
# # 	echo "You are running as $(whoami)"
# # else
# #   echo "[-] Do not run as root (or with sudo)."
# #   exit 1
# # fi

# # ################################################
# # # TODO - implement the following:
# # # 
# # # 1. ProtonPass versions json had "RolloutPercentage" as 0.05. So the wget ProtonPass.rpm kept getting the 0.95 percent rpm, but the SHA script kept returning SHA of 0.05 percent rpm as it was the latest version. So Strategy should be to first find the latest version, and return the corresponding "Url" and "Sha512CheckSum" for the *.rpm URL. Use this returned URL to download the rpm file:
# #   # "Releases": [
# #   #   {
# #   #     "CategoryName": "Stable",
# #   #     "Version": "1.35.0",
# #   #     "ReleaseDate": "2026-03-09T10:47:04Z",
# #   #     "RolloutPercentage": 0.05,
# #   #     "File": [
# # #
# # #
# # # 2. Somethimes, the latest version will have "CategoryName" as something other than "Stable". Skip those non-stable versions while fetching SHA:
# #   # "Releases": [
# #   #   {
# #   #     "CategoryName": "Stable",
# # #
# # #
# # ################################################

# # echo "************************ Setting literals and constants ************************"



# # CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects"
# # SYSUPDATE_SEC_CODE_DIR="$CODE_BASE_DIR/system_update/linux/security_os_level/"
# # SYSUPDATE_FEDORA_CODE_DIR="$CODE_BASE_DIR/system_update/linux/fedora/"

# # SCRIPT_DOWNLOADS_DIR="${SCRIPT_DATA_DIR}/downloads"

# # PROTON_DOWNLOADS_DIR_BASE="${SCRIPT_DOWNLOADS_DIR}/proton_ag"
# # PROTON_CURRENT_DOWNLOADS_DIR="${PROTON_DOWNLOADS_DIR_BASE}/proton_ag_${FILENAME_TIMESTAMP}"

# # FEDORA_RELEASE_VERSION=$(sh "${SYSUPDATE_FEDORA_CODE_DIR}"/get_fedora_release_version.sh)

# # mkdir -p "${PROTON_CURRENT_DOWNLOADS_DIR}"
# # chown "${REAL_USER}":"${REAL_USER}" "${PROTON_DOWNLOADS_DIR_BASE}" "${PROTON_CURRENT_DOWNLOADS_DIR}"

# # cd "$PROTON_CURRENT_DOWNLOADS_DIR" || exit
# #####################################################################################


# #######################################################
# # Colors and Helpers
# #######################################################

# # Colors for terminal output
# readonly GREEN='\033[0;32m'
# readonly YELLOW='\033[1;33m'
# readonly RED='\033[0;31m'
# readonly NC='\033[0m' # No Color
# readonly BLUE='\033[0;34m'
# readonly CYAN='\033[0;36m'

# log_step()    { echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${NC}"; }
# log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
# log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
# log_warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
# log_error()   { echo -e "${RED}[✗]${NC} $*" >&2; }
# # die()  { err "$*"; exit 1; }
# die()  { printf "${RED}\n[ERROR] %s\n${NC}" "$*" >&2; exit 1; }

# # die() { echo "[-] $*" >&2; exit 1; }
# info() { echo "[*] $*"; }
# ok()   { echo "[+] $*"; }




# [[ "$(id -u)" -ne 0 ]] || die "Do not run this script as root or with sudo; it invokes sudo only for installation."

# # bool function to test if the user is root or not (POSIX only)
# # is_user_root ()
# # {
# #     [ "$(id -u)" -eq 0 ]
# # }


# # -----------------------------------------------------------------------------
# #  DESIGN NOTES  (read these once, they explain every odd-looking decision)
# # -----------------------------------------------------------------------------
# #  1. Proton publishes a machine-readable manifest ("version.json") for most
# #     desktop products. Shape:
# #
# #       { "Releases": [
# #           { "CategoryName": "Stable",          <- Stable | EarlyAccess | Beta | Alpha
# #             "Version": "1.42.0",
# #             "ReleaseDate": "2026-10-07T10:26:40Z",
# #             "RolloutPercentage": 1,            <- OR "RolloutProportion" (Mail uses this)
# #             "File": [
# #               { "Identifier": ".deb (Ubuntu/Debian)", "Url": "...", "Sha512CheckSum": "..." },
# #               { "Identifier": ".rpm (Fedora/RHEL)",   "Url": "...", "Sha512CheckSum": "..." }
# #             ] },
# #           ...
# #       ] }
# #
# #     Note the two rollout key spellings and the fact that Identifier is absent
# #     in older records. Both are handled.
# #
# #  2. *** THE CRITICAL RULE ***
# #     Never pair a "generic latest" download URL with a separately-looked-up
# #     checksum. The generic paths (e.g. .../ProtonPass.rpm) are served by a CDN
# #     that deliberately lags the newest manifest entry while a release is only
# #     partially rolled out (RolloutPercentage 0.05 / 0.2 / 0.5 ...). That lag is
# #     exactly what produced the old "Checksum verification failed" errors.
# #
# #     => Url AND Sha512CheckSum are always taken from the SAME release record,
# #        in a single jq pass. Mismatch becomes structurally impossible.
# #
# #  3. Proton VPN has NO version.json (both plausible endpoints 404). Its repo
# #     exposes a plain Apache index listing instead. Do NOT parse HTML tags --
# #     extract the *.rpm tokens and let `sort -V` pick the highest version.
# #
# #     The old script did `grep ".rpm"` + string surgery, which silently assumed
# #     the directory held exactly ONE rpm. As of Oct 2026 it holds three
# #     (1.0.3, 1.0.4, 1.0.5), so the extracted filename became garbage.
# #     Token extraction + version sort is immune to that.
# #
# #  4. Rollout gate semantics: `//` in jq only falls through on null/false, so
# #     RolloutPercentage: 0 correctly evaluates to 0 (not to the fallback).
# #     A release is considered "generally available" when its rollout >= MIN_ROLLOUT
# #     (default 1 = 100%). If nothing qualifies, the script retries with 0 and warns.
# #


# REAL_USER="${SUDO_USER:-$USER}"
# # REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
# HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# NBDIR="$HOME_DIR/nb"
# SYSUPDATE_CODE_BASE_DIR="$NBDIR/CodeProjects/system_update"

# SCRIPT_DATA_DIR="${NBDIR}/nb_script_data"


# # Named options replace the previous positional SETUP_TYPE/DESKTOP arguments.
# SETUP_TYPE="light"
# DESKTOP=""
# FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"


# HOME_DIR_EXPLICIT=0
# SCRIPT_DATA_DIR_EXPLICIT=0
# SYSUPDATE_CODE_BASE_DIR_EXPLICIT=0

# CHANNEL="stable" # stable|beta|earlyaccess|alpha
# MIN_ROLLOUT=-1 # 0-9




# usage() {
#   # log_info "Usage: $0 [--setup-type light|full] [--desktop gnome|kde|...]"
#   cat <<'USAGE'
# Usage:
#   proton_ag.sh [--setup-type light|full] 
#                [--desktop NAME]
#                [--filename-timestamp TIMESTAMP] 
#                [--home-dir PATH]
#                [--real-user USER] 
#                [--script-data-dir PATH]
#                [--sysupdate-code-base-dir PATH]
#                [--channel stable|beta|earlyaccess|alpha]
#                [--min-rollout 0-9]

# Defaults:
#   --setup-type light     Install Proton VPN only
#   --desktop kde|gnome    Detected by get_desktop_env.sh when available
#   --filename-timestamp   Current date/time
#   --real-user            SUDO_USER or current user
#   --channel              stable
#   --min-rollout          -1
# USAGE
# }




# # Parse named options
# # while (($#)); do
# while [ "$#" -gt 0 ]; do
#   case "$1" in
#     -t|--setup-type)
#       SETUP_TYPE="$2"
#       shift 2
#       ;;
#     -d|--desktop)
#       DESKTOP="$2"
#       shift 2
#       ;;
#     --filename-timestamp)
#       FILENAME_TIMESTAMP="$2"
#       shift 2
#       ;;
#     --home-dir)
#       HOME_DIR="$2"
#       HOME_DIR_EXPLICIT=1
#       shift 2
#       ;;
#     --real-user)
#       REAL_USER="$2";
#       shift 2
#       ;;
#     --script-data-dir)
#       SCRIPT_DATA_DIR="$2";
#       SCRIPT_DATA_DIR_EXPLICIT=1;
#       shift 2
#       ;;
#     --sysupdate-code-base-dir)
#       SYSUPDATE_CODE_BASE_DIR="$2"
#       SYSUPDATE_CODE_BASE_DIR_EXPLICIT=1
#       shift 2
#       ;;
#     --channel)
#       CHANNEL="$2"
#       shift 2
#       ;;
#     --min-rollout)
#       MIN_ROLLOUT="$2"
#       shift 2
#       ;;
#     -h|--help)
#       usage
#       exit 0
#       ;;
#     -h|--help)
#       exit 0
#       ;;
#     *)
#       log_error "Unknown option: $1" >&2
#       exit 1
#       ;;
#   esac
# done




# # Handle setup type defaults and validation
# if [ -z "$SETUP_TYPE" ]; then
#     log_warn "SETUP_TYPE not provided. Assuming light installation."
#     SETUP_TYPE="light"
# else
#   log_info "SETUP_TYPE = $SETUP_TYPE"
#   if [ "$SETUP_TYPE" = "full" ]; then 
#       log_info "Installing all ProtonAG stuff."
#   elif [ "$SETUP_TYPE" = "light" ]; then
#       log_info "Only installing ProtonVPN"
#   else 
#       log_error "--setup-type must be 'light' or 'full'"
#       exit 1
#   fi
# fi


# if (( HOME_DIR_EXPLICIT == 0 )); then
#   HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"
# fi


# [[ -n "$HOME_DIR" ]] || die "Could not determine home directory for user: $REAL_USER"

# if (( SCRIPT_DATA_DIR_EXPLICIT == 0 )); 
# then 
#     SCRIPT_DATA_DIR="$HOME_DIR/nb/nb_script_data"; 
# fi

# if (( SYSUPDATE_CODE_BASE_DIR_EXPLICIT == 0 )); 
# then 
#     SYSUPDATE_CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects/system_update"; 
# fi



# # detect_desktop() {
# #   if [ -z "$DESKTOP" ]; then
# #     # Prefer the shared helper if the system_update tree is present.
# #     _helper="$HOME_DIR/nb/CodeProjects/system_update/linux/common/get_desktop_env.sh"
# #     if [ -f "$_helper" ]; then
# #       DESKTOP=$(sh "$_helper" 2>/dev/null || true)
# #     fi
# #   fi
# #   if [ -z "${DESKTOP:-}" ]; then
# #     case "${XDG_CURRENT_DESKTOP:-}" in
# #       *KDE*|*Plasma*) DESKTOP=kde ;;
# #       *GNOME*)        DESKTOP=gnome ;;
# #       *)              DESKTOP=unknown ;;
# #     esac
# #   fi
# #   # Normalise to lowercase so comparisons are predictable.
# #   DESKTOP=$(printf '%s' "$DESKTOP" | tr '[:upper:]' '[:lower:]')
# # }


# # Handle desktop detection if not provided
# if [ -z "$DESKTOP" ]; then
#   log_warn "DESKTOP not provided. Identifying."
#   DESKTOP=$(bash "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_desktop_env.sh)
# fi








# log_info "The current DESKTOP is $DESKTOP."
# sleep 5s

# if ! is_user_root; then
# 	log_info "You are running as $(whoami)"
# else
#   log_error "Do not run as root (or with sudo)."
#   exit 1
# fi

# # require_tools() {
# #   for _t in curl jq sha512sum sort grep sed dnf; do
# #     command -v "$_t" >/dev/null 2>&1 || die "missing required tool: $_t"
# #   done
# #   command -v sudo >/dev/null 2>&1 || die "missing required tool: sudo"
# # }

# command -v sudo >/dev/null || die "Required command not found: sudo"
# command -v curl >/dev/null || die "Required command not found: curl"
# command -v jq >/dev/null || die "Required command not found: jq"
# command -v sha512sum >/dev/null || die "Required command not found: sha512sum"
# command -v sort >/dev/null || die "Required command not found: sort"
# command -v dnf >/dev/null || die "This installer requires Fedora's dnf."

# log_info "************************ Setting literals and constants ************************"

# CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects"
# # SYSUPDATE_SEC_CODE_DIR="$CODE_BASE_DIR/system_update/linux/security_os_level/"
# SYSUPDATE_FEDORA_CODE_DIR="$CODE_BASE_DIR/system_update/linux/fedora/"

# SCRIPT_DOWNLOADS_DIR="${SCRIPT_DATA_DIR}/downloads"
# PROTON_DOWNLOADS_DIR_BASE="${SCRIPT_DOWNLOADS_DIR}/proton_ag"
# PROTON_CURRENT_DOWNLOADS_DIR="${PROTON_DOWNLOADS_DIR_BASE}/proton_ag_${FILENAME_TIMESTAMP}"


# # # Fedora version (robust)
# # FEDORA_RELEASE_VERSION=$(rpm -E %fedora 2>/dev/null || \
# #     grep -oP 'Fedora release \K[0-9]+' /etc/fedora-release 2>/dev/null || \
# #     cut -d' ' -f3 /etc/fedora-release)
# # [ -n "$FEDORA_RELEASE_VERSION" ] || die "Could not determine Fedora version"
# # info "Fedora $FEDORA_RELEASE_VERSION"

# FEDORA_RELEASE_VERSION=$(sh "${SYSUPDATE_FEDORA_CODE_DIR}"/get_fedora_release_version.sh)

# # # Determine the Fedora release number.
# # #
# # # `rpm -E %fedora` is the canonical way and is immune to the /etc/fedora-release
# # # wording changes that break `cut -d' ' -f 3` on derivatives -- e.g. "Fedora
# # # Asahi Remix release 43" yields "Remix" with the naive approach and a 404 URL.
# # detect_fedora_version() {
# #   _v=$(rpm -E %fedora 2>/dev/null || true)
# #   case "$_v" in
# #     ''|'%fedora')
# #       # Fallback: grab the first integer that follows the word "release".
# #       _v=$(sed -n 's/.*release[[:space:]]\{1,\}\([0-9][0-9]*\).*/\1/p' \
# #              /etc/fedora-release 2>/dev/null | head -n 1 || true)
# #       ;;
# #   esac
# #   [ -n "$_v" ] || die "cannot determine the Fedora release number"
# #   printf '%s' "$_v"
# # }
# # FEDORA_RELEASE_VERSION=$(detect_fedora_version)



# mkdir -p "${PROTON_CURRENT_DOWNLOADS_DIR}"
# # chown "${REAL_USER}":"${REAL_USER}" "${PROTON_DOWNLOADS_DIR_BASE}" "${PROTON_CURRENT_DOWNLOADS_DIR}"

# # Ensure the download directory belongs to the intended desktop user.
# sudo install -d -o "$REAL_USER" -g "$(id -gn "$REAL_USER")" "$PROTON_DOWNLOADS_DIR_BASE" "$PROTON_CURRENT_DOWNLOADS_DIR"


# cd "$PROTON_CURRENT_DOWNLOADS_DIR" || exit

# # Embedded function replacing the separate proton_get_sha.sh script
# get_proton_release_info() {
#     local json_path="$1"
#     local json_filename="$2"

#     jq -r '
#       .Releases
#       | map(select(.CategoryName == "Stable"))
#       | sort_by(.Version | split(".") | map(try tonumber catch 0))
#       | last
#       | .File[]
#       | select(.Identifier? | test("\\.rpm"; "i") or (.Url | test("\\.rpm$"; "i")))
#       | "\(.Url) \(.Sha512CheckSum)"
#     ' "$json_path/$json_filename"
# }

# log_info "************************ Installing proton stuff ************************"



# ################################################

# # #####################################################################################


# # echo "************************ Installing proton stuff ************************"
# # ########################## ProtonVPN ###################################################################

# # ########################## ProtonVPN - Following is an implementation of the OFFICIAL way: 
# # # echo "************************ Installing ProtonVPN ************************"
# # # # https://protonvpn.com/support/official-linux-vpn-fedora/
# # # # Download the package that contains the repository configuration and keys required to install the Proton VPN app
# # # wget "https://repo.protonvpn.com/fedora-$(cat /etc/fedora-release | cut -d' ' -f 3)-stable/protonvpn-stable-release/protonvpn-stable-release-1.0.3-1.noarch.rpm"
# # # # Install the Proton VPN repository containing the app
# # # sudo dnf install -y ./protonvpn-stable-release-1.0.3-1.noarch.rpm && sudo dnf check-update --refresh 
# # # # Install the app and accept an OpenPGP key.
# # # sudo dnf install -y proton-vpn-gnome-desktop 
# # # # Enable GNOME desktop tray icons
# # # sudo dnf install -y libappindicator-gtk3 gnome-shell-extension-appindicator gnome-extensions-app
# # # echo "************************ TODO: Open the Extensions app and ensure that AppIndicator and KStatusNotifierItem Support is toggled on before opening the app ************************"


# # ########################## ProtonVPN - Following is an implementation in a slightly better way: 
# # # We fetch the filename to download instead of hardcoding it so that we always have the latest version.

# # PROTON_VPN_BASE_URL="https://repo.protonvpn.com/fedora-$FEDORA_RELEASE_VERSION-stable/protonvpn-stable-release"
# # page="$(curl "$PROTON_VPN_BASE_URL/")"

# # line=$(echo "$page" | grep ".rpm")
# # # echo "########### line = $line ###########"
# # # Sample line:
# # # <a href="protonvpn-stable-release-1.0.3-1.noarch.rpm">protonvpn-stable-release-1.0.3-1.noarch.rpm</a>        03-Apr-2025 09:24                7765

# # # get text (filename) between double quotes (from the <a> tag)
# # FILENAME=${line#*\"}
# # FILENAME=${FILENAME%\"*}
# # FILENAME=${FILENAME%\"*}
# # FILENAME=${FILENAME%\"*}

# # # echo "URL for downloading ProtonVPN = $PROTON_VPN_BASE_URL/$FILENAME"

# # # # Download the package that contains the repository configuration and keys required to install the Proton VPN app
# # wget "$PROTON_VPN_BASE_URL/$FILENAME"

# # ############ Everything below this is same as the OFFICIAL way above

# # # Install the Proton VPN repository containing the app
# # sudo dnf install -y ./"$FILENAME" # && sudo dnf check-update --refresh 

# # # Install the app and accept an OpenPGP key. Just installing the above RPM doesn't complete the setup.
# # sudo dnf install -y proton-vpn-gnome-desktop 

# # if [ "$DESKTOP" = "gnome" ]
# # then
# #   # Enable GNOME desktop tray icons
# #   sudo dnf install -y libappindicator-gtk3 gnome-shell-extension-appindicator # gnome-extensions-app
# #   echo "************************ TODO: Open the Extensions app and ensure that AppIndicator and KStatusNotifierItem Support is toggled on before opening the app ************************"
# # fi

# # ########################## ProtonVPN cli ###################################################################
# # # https://protonvpn.com/support/linux-cli
# # # Optional installation if need arises
# # # sudo dnf install -y proton-vpn-cli
# # #####################################################################################

# ########################## ProtonVPN ###################################################################


# # install_proton_vpn() {
# #   local fedora_version base_url listing filename
# #   fedora_version="$(rpm -E %fedora)"
# #   [[ "$fedora_version" =~ ^[0-9]+$ ]] || die "Could not determine Fedora release version"
# #   base_url="https://repo.protonvpn.com/fedora-${fedora_version}-stable/protonvpn-stable-release"

# #   # Proton VPN's repository-bootstrap RPM does not currently use the same
# #   # version.json scheme as the desktop apps, so the repository index is the fallback.
# #   log_info "Finding the current Proton VPN repository-bootstrap RPM"
# #   listing="$(curl --fail --location --silent --show-error --retry 3 \
# #     --connect-timeout 15 --max-time 120 "$base_url/")"
# #   filename="$(printf '%s' "$listing" |
# #     grep -oE 'protonvpn-stable-release-[^"<>[:space:]]+\.rpm' |
# #     sort -Vu | tail -n 1)"
# #   [[ -n "$filename" ]] || die "Could not find a Proton VPN repository RPM in $base_url/"
# #   curl --fail --location --silent --show-error --retry 3 --retry-delay 1 \
# #     --connect-timeout 15 --max-time 300 "$base_url/$filename" -o "$filename"

# #   log_info "Installing Proton VPN repository package: $filename"
# #   sudo dnf install -y "./$filename"
# #   sudo dnf install -y proton-vpn-gnome-desktop

# #   if [[ "${DESKTOP,,}" == *gnome* ]]; then
# #     sudo dnf install -y libappindicator-gtk3 gnome-shell-extension-appindicator
# #     printf '%s\n' "If required, enable AppIndicator and KStatusNotifierItem Support in GNOME Extensions."
# #   fi
# # }

# ################################################



# # # install_protonvpn
# # #
# # # Proton VPN is the odd one out: no version.json exists, so we resolve the
# # # bootstrap repository RPM from the Apache index listing.
# # #
# # # The bootstrap RPM carries the repo definition + signing key. There is no
# # # published SHA-512 for it, so integrity rests on TLS plus dnf's own handling;
# # # --verify-signatures additionally GPG-checks it against the key published in
# # # the same repo root. Be clear-eyed about what that buys you: it defends against
# # # transport corruption and MITM, NOT against a compromised origin (the key and
# # # the package come from the same host).
# # #
# # # Once the repo is configured, dnf owns version management -- no scraping.
# # install_protonvpn() {
# #   _root="https://repo.protonvpn.com/fedora-${FEDORA_RELEASE_VERSION}-stable"
# #   _base="$_root/protonvpn-stable-release"

# #   if [ "$DRY_RUN" = 1 ]; then
# #     log "protonvpn: would resolve bootstrap RPM from $_base/"
# #     printf '    %-16s %-10s %s\n' "protonvpn" "(index)" "$_base/"
# #     return 0
# #   fi

# #   log "protonvpn: reading repo index $_base/"
# #   _page=$(curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 -o - "$_base/" || true)
# #   if [ -z "$_page" ]; then
# #     fail_product "protonvpn" "repo index unreachable"
# #     return 1
# #   fi

# #   # Extract every *.rpm TOKEN from the listing, de-duplicate, and let version
# #   # sort pick the newest. Deliberately not parsing href="" attributes: the
# #   # token itself survives markup changes, whereas attribute quoting does not.
# #   # This is the fix for the old `grep ".rpm"` bug, which assumed a single match.
# #   _rpm=$(printf '%s\n' "$_page" \
# #            | grep -oE '[[:alnum:]_.+-]+\.rpm' \
# #            | sort -u -V \
# #            | tail -n 1)

# #   if [ -z "$_rpm" ]; then
# #     fail_product "protonvpn" "no .rpm token found in repo index"
# #     return 1
# #   fi
# #   log "protonvpn: bootstrap package = $_rpm"

# #   if ! curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 \
# #             -o "$DL_DIR/$_rpm" "$_base/$_rpm"; then
# #     fail_product "protonvpn" "bootstrap download failed"
# #     return 1
# #   fi

# #   # --- optional GPG verification of the bootstrap RPM -------------------------
# #   if [ "$VERIFY_SIGNATURES" = 1 ]; then
# #     log "protonvpn: importing repo signing key and verifying $_rpm"
# #     if curl -fsSL --proto '=https' --tlsv1.2 -o "$DL_DIR/protonvpn-public_key.asc" \
# #             "$_root/public_key.asc"; then
# #       # rpm --import writes to the system rpm keyring -- which is exactly what
# #       # dnf does anyway the first time it installs from this repo.
# #       sudo rpm --import "$DL_DIR/protonvpn-public_key.asc"
# #       if ! rpm --checksig "$DL_DIR/$_rpm" >/dev/null 2>&1; then
# #         fail_product "protonvpn" "GPG signature check failed"
# #         return 1
# #       fi
# #       ok "protonvpn: signature verified"
# #     else
# #       warn "protonvpn: could not fetch public_key.asc; skipping signature check"
# #     fi
# #   fi

# #   if [ "$SKIP_INSTALL" = 1 ]; then
# #     log "protonvpn: --skip-install set; artefact left at $DL_DIR/$_rpm"
# #     return 0
# #   fi

# #   # --- install repo, then the app --------------------------------------------
# #   log "protonvpn: installing repository definition"
# #   if ! sudo dnf install -y "$DL_DIR/$_rpm"; then
# #     fail_product "protonvpn" "repository RPM install failed"
# #     return 1
# #   fi

# #   log "protonvpn: installing proton-vpn-gnome-desktop (provides GUI + CLI)"
# #   if ! sudo dnf install -y proton-vpn-gnome-desktop; then
# #     fail_product "protonvpn" "app install failed"
# #     return 1
# #   fi

# #   # Tray icon plumbing differs per desktop.
# #   if [ "$DESKTOP" = "gnome" ]; then
# #     sudo dnf install -y libappindicator-gtk3 gnome-shell-extension-appindicator || true
# #     warn "GNOME: open the Extensions app and enable 'AppIndicator and KStatusNotifierItem Support'"
# #   else
# #     log "KDE: StatusNotifierItem support is built into Plasma; no extension needed"
# #   fi

# #   # Optional, mutually exclusive with the GUI app:
# #   #   sudo dnf install -y proton-vpn-cli
# #   ok "protonvpn: installed"
# # }




# ################################################




# # # ---------- Proton VPN (repo method — still the official & best way) ----------
# # info "Installing Proton VPN repository + app"
# # PROTON_VPN_BASE="https://repo.protonvpn.com/fedora-${FEDORA_RELEASE_VERSION}-stable/protonvpn-stable-release"

# # # Discover the newest release RPM without fragile HTML scraping
# # RELEASE_RPM=$(curl -fsSL "$PROTON_VPN_BASE/" | \
# #     grep -oE 'protonvpn-stable-release-[0-9.-]+noarch\.rpm' | sort -V | tail -n1)

# # [ -n "$RELEASE_RPM" ] || die "Could not find protonvpn-stable-release RPM in $PROTON_VPN_BASE"

# # curl -fsSL -o "$RELEASE_RPM" "$PROTON_VPN_BASE/$RELEASE_RPM"
# # sudo dnf install -y "./$RELEASE_RPM"
# # sudo dnf install -y proton-vpn-gnome-desktop   # or proton-vpn-gtk-app if you prefer the newer one

# # if [ "$DESKTOP" = "gnome" ]; then
# #     sudo dnf install -y libappindicator-gtk3 gnome-shell-extension-appindicator || true
# #     info "TODO: enable AppIndicator extension in GNOME Extensions app"
# # fi

# # # Optional CLI
# # # sudo dnf install -y proton-vpn-cli





# ################################################


# log_info "************************ Installing ProtonVPN ************************"
# PROTON_VPN_BASE_URL="https://repo.protonvpn.com/fedora-$FEDORA_RELEASE_VERSION-stable/protonvpn-stable-release"

# FILENAME=$(curl -s "$PROTON_VPN_BASE_URL/" \
#   | grep -oE 'protonvpn-stable-release-[0-9.-]+\.noarch\.rpm' \
#   | sort -V \
#   | tail -n 1)

# if [ -z "$FILENAME" ]; then
#   log_error "ERROR: Could not determine latest ProtonVPN release package filename." >&2
#   exit 1
# fi

# wget "$PROTON_VPN_BASE_URL/$FILENAME"

# sudo dnf install -y ./"$FILENAME" 
# sudo dnf install -y proton-vpn-gnome-desktop 

# if [ "$DESKTOP" = "gnome" ]
# then
#   sudo dnf install -y libappindicator-gtk3 gnome-shell-extension-appindicator
#   log_warn "************************ TODO: Open the Extensions app and ensure that AppIndicator and KStatusNotifierItem Support is toggled on before opening the app ************************"
# fi

# if [ "$SETUP_TYPE" = "full" ]; then 

#   # Generic helper function for installing applications that utilize version.json
#   install_proton_app() {
#     local app_name="$1"
#     local json_filename="$2"
#     local json_url="$3"

#     log_info "************************ Installing $app_name ************************"
#     wget -O "$json_filename" "$json_url"

#     local release_info
#     release_info=$(get_proton_release_info "$PROTON_CURRENT_DOWNLOADS_DIR" "$json_filename")

#     local rpm_url
#     rpm_url=$(echo "$release_info" | awk '{print $1}')
#     local expected_sha
#     expected_sha=$(echo "$release_info" | awk '{print $2}')

#     expected_sha="${expected_sha%\"}"
#     expected_sha="${expected_sha#\"}"

#     if [ -z "$rpm_url" ] || [ -z "$expected_sha" ]; then
#       log_error "ERROR: Failed to parse release info for $app_name from JSON." >&2
#       exit 1
#     fi

#     local rpm_filename
#     rpm_filename=$(basename "$rpm_url")

#     wget "$rpm_url"

#     if echo "$expected_sha $rpm_filename" | sha512sum --check --status -; then
#       log_success "$app_name - Checksum verification passed. Proceeding with installation..."
#       sudo dnf install -y "$rpm_filename"
#     else
#       local calculated_sha
#       calculated_sha=$(sha512sum "$rpm_filename" | awk '{print $1}')
#       log_error "Calculated SHA512sum of *.rpm file: $calculated_sha did not match SHA512sum from json file: $expected_sha" >&2
#       log_error "ERROR: $app_name - Checksum verification failed." >&2
#       exit 1
#     fi
#   }



# ########################################



# # # Download an official version.json, select the newest Stable release with an RPM,
# # # and emit the URL and SHA from that exact File object. RolloutPercentage and
# # # RolloutProportion are deliberately not filters: they can be absent or fractional.
# # get_stable_rpm_metadata() {
# #   local json_url="$1" json_file="$2" metadata version url checksum
# #   log_info "Fetching release metadata: $json_url" >&2
# #   curl --fail --location --silent --show-error --retry 3 --retry-delay 1 \
# #     --connect-timeout 15 --max-time 120 "$json_url" -o "$json_file"
# #   jq -e '.Releases | type == "array" and length > 0' "$json_file" >/dev/null ||
# #     die "Invalid or empty Releases array in $json_file"

# #   metadata="$(
# #     jq -r '
# #       .Releases[]
# #       | select((.CategoryName // "" | ascii_downcase) == "stable")
# #       | . as $release
# #       | ($release.File // [])[]
# #       | select(
# #           ((.Identifier // "" | ascii_downcase | contains("rpm")))
# #           or ((.Url // "") | test("\\.rpm([?#].*)?$"; "i"))
# #         )
# #       | select((.Url // "") | test("^https://"; "i"))
# #       | select((.Sha512CheckSum // "") | test("^[A-Fa-f0-9]{128}$"))
# #       | [$release.Version // "", .Url, .Sha512CheckSum] | @tsv
# #     ' "$json_file" | sort -V -k1,1 | tail -n 1
# #   )"
# #   [[ -n "$metadata" ]] || die "No Stable RPM URL with a valid SHA-512 checksum found in $json_file"

# #   IFS=$'\t' read -r version url checksum <<< "$metadata"
# #   [[ -n "$version" && -n "$url" && -n "$checksum" ]] ||
# #     die "Could not parse selected release metadata in $json_file"
# #   printf '%s\t%s\t%s\n' "$version" "$url" "$checksum"
# # }

# # download_verify_install() {
# #   local app="$1" version_json_url="$2" json_file="$3"
# #   local version url checksum filename

# #   log_info "Resolving latest Stable $app RPM"
# #   IFS=$'\t' read -r version url checksum < <(get_stable_rpm_metadata "$version_json_url" "$json_file")
# #   filename="${url##*/}"
# #   filename="${filename%%\?*}"
# #   [[ "$filename" == *.rpm && "$filename" != */* ]] ||
# #     die "$app: unsafe or unexpected RPM filename derived from URL: $filename"

# #   log_info "$app selected version $version; RPM: $filename"
# #   curl --fail --location --silent --show-error --retry 3 --retry-delay 1 \
# #     --connect-timeout 15 --max-time 600 "$url" -o "$filename"

# #   # Verify before handing the downloaded package to dnf. A mismatch aborts.
# #   printf '%s  %s\n' "$checksum" "$filename" | sha512sum --check --status - ||
# #     die "$app SHA-512 verification FAILED for $filename; refusing to install"
# #   log_info "$app SHA-512 verification passed; installing"
# #   sudo dnf install -y "./$filename"
# # }





# #####################################






# # # ===========================================================================
# # #  SECTION 4 -- release resolution
# # # =============================================================================

# # # resolve_release MANIFEST CHANNEL MIN_ROLLOUT
# # #
# # # Prints one TSV line:  <version>\t<url>\t<sha512>
# # # Prints nothing and returns 0 if no release matches.
# # #
# # # Selection predicate, applied in order:
# # #   a) CategoryName matches CHANNEL (case-insensitive)
# # #   b) rollout gate >= MIN_ROLLOUT, where the gate is RolloutPercentage if
# # #      present, else RolloutProportion, else 1 (absent == fully available)
# # #   c) the release actually carries an RPM artefact
# # #   d) newest by ReleaseDate wins
# # #
# # # Artefact matching accepts EITHER a matching Identifier (fast path) OR a Url
# # # ending in .rpm (fallback, for older records that omit Identifier).
# # resolve_release() {
# #   jq -r --arg chan "$2" --argjson min "$3" '
# #     def roll:  ((.RolloutPercentage // .RolloutProportion // 1) | tonumber);
# #     def isrpm: (((.Identifier // "") | test("rpm"; "i"))
# #                 or ((.Url // "") | test("\\.rpm$"; "i")));

# #     [ .Releases[]
# #       | select(((.CategoryName // "") | ascii_downcase) == $chan)
# #       | select(roll >= $min)
# #       | select(any(.File[]?; isrpm))
# #       | { ver:  .Version,
# #           date: (.ReleaseDate // ""),
# #           file: ([ .File[] | select(isrpm) ] | .[0]) }
# #     ]
# #     | sort_by(.date) | reverse
# #     | if length == 0 then empty
# #       else .[0] | [ .ver, .file.Url, .file.Sha512CheckSum ] | @tsv
# #       end
# #   ' "$1"
# # }

# # # =============================================================================
# # #  SECTION 5 -- installers
# # # =============================================================================

# # # install_from_version_json KEY MANIFEST_URL
# # install_from_version_json() {
# #   _key=$1
# #   _manifest_url=$2
# #   _manifest="$DL_DIR/${_key}_version.json"

# #   log "$_key: fetching manifest $_manifest_url"
# #   if ! curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 \
# #             -o "$_manifest" "$_manifest_url"; then
# #     fail_product "$_key" "manifest unreachable"
# #     return 1
# #   fi

# #   _row=$(resolve_release "$_manifest" "$CHANNEL" "$MIN_ROLLOUT" || true)

# #   if [ -z "$_row" ]; then
# #     # Nothing fully rolled out -- fall back to the newest release regardless of
# #     # rollout state, but say so loudly. This is the "slow rollout in progress"
# #     # case, not the normal path.
# #     warn "$_key: no '$CHANNEL' release with rollout >= $MIN_ROLLOUT; falling back to rollout >= 0"
# #     _row=$(resolve_release "$_manifest" "$CHANNEL" 0 || true)
# #   fi

# #   if [ -z "$_row" ]; then
# #     fail_product "$_key" "no '$CHANNEL' release carrying an RPM in manifest"
# #     return 1
# #   fi

# #   _ver=$(printf '%s' "$_row" | cut -f1)
# #   _url=$(printf '%s' "$_row" | cut -f2)
# #   _sha=$(printf '%s' "$_row" | cut -f3)
# #   # Strip any query string before deriving the local filename.
# #   _rpm=$(basename "${_url%%\?*}")

# #   printf '    %-16s %-10s %s\n' "$_key" "$_ver" "$_url"

# #   if [ "$DRY_RUN" = 1 ]; then
# #     return 0
# #   fi

# #   # --- download ---------------------------------------------------------------
# #   log "$_key: downloading $_rpm"
# #   if ! curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 \
# #             -o "$DL_DIR/$_rpm" "$_url"; then
# #     fail_product "$_key" "download failed"
# #     return 1
# #   fi

# #   # --- verify -----------------------------------------------------------------
# #   # Two spaces between digest and filename is the canonical sha512sum format.
# #   # --status suppresses output; we only care about the exit code.
# #   if ! printf '%s  %s\n' "$_sha" "$DL_DIR/$_rpm" | sha512sum --check --status -; then
# #     warn "$_key: SHA-512 MISMATCH for $_rpm"
# #     warn "  expected: $_sha"
# #     warn "  actual:   $(sha512sum "$DL_DIR/$_rpm" | cut -d' ' -f1)"
# #     fail_product "$_key" "checksum verification failed"
# #     return 1
# #   fi
# #   ok "$_key: SHA-512 verified ($_ver)"

# #   # --- install ----------------------------------------------------------------
# #   if [ "$SKIP_INSTALL" = 1 ]; then
# #     log "$_key: --skip-install set; artefact left at $DL_DIR/$_rpm"
# #     return 0
# #   fi

# #   log "$_key: installing $_rpm"
# #   if ! sudo dnf install -y "$DL_DIR/$_rpm"; then
# #     fail_product "$_key" "dnf install failed"
# #     return 1
# #   fi
# #   ok "$_key: installed"
# # }






# ########################################3




# # # ---------- helpers ----------
# # die() { echo "[-] $*" >&2; exit 1; }
# # info() { echo "[*] $*"; }
# # ok()   { echo "[+] $*"; }

# # is_user_root() { [ "$(id -u)" -eq 0 ]; }

# # # Prefer Stable, then highest Version. Prefer full rollout when present.
# # # Returns: "URL|SHA512" for the .rpm of the chosen release
# # get_stable_rpm_info() {
# #     json_file="$1"
# #     # Prefer CategoryName == "Stable". Among those, take the first (newest).
# #     # Fall back to any release that has an .rpm if no Stable exists.
# #     result=$(jq -r '
# #         (.Releases // []) as $r
# #         | ($r | map(select(.CategoryName == "Stable")) | .[0] // $r[0]) as $rel
# #         | ($rel.File // [])[]
# #         | select(.Url | test("\\.rpm$"; "i"))
# #         | "\(.Url)|\(.Sha512CheckSum)"
# #     ' "$json_file" | head -n1)

# #     [ -n "$result" ] || die "No RPM entry found in $json_file"
# #     echo "$result"
# # }

# # download_and_verify() {
# #     url="$1"
# #     expected_sha="$2"
# #     outfile="$3"

# #     info "Downloading $(basename "$outfile") ..."
# #     curl -fsSL -o "$outfile" "$url" || die "Download failed: $url"

# #     actual=$(sha512sum "$outfile" | awk '{print $1}')
# #     if [ "$actual" = "$expected_sha" ]; then
# #         ok "SHA512 OK for $(basename "$outfile")"
# #     else
# #         echo "Expected: $expected_sha" >&2
# #         echo "Actual:   $actual" >&2
# #         die "Checksum mismatch for $outfile"
# #     fi
# # }



# ####################################################




#   ######################### ProtonAuthenticator ###################################################
#   install_proton_app "ProtonAuthenticator" "ProtonAuthenticator_version.json" "https://proton.me/download/authenticator/linux/version.json"

#   ######################### ProtonPass ##########################################################
#   install_proton_app "ProtonPass" "ProtonPass_version.json" "https://proton.me/download/PassDesktop/linux/x64/version.json"

#   ######################### ProtonMail ##########################################################
#   install_proton_app "ProtonMail" "ProtonMail_version.json" "https://proton.me/download/mail/linux/version.json"

#   ######################### ProtonMeet ##########################################################
#   log_info "************************ Installing ProtonMeet ************************"
#   # wget https://proton.me/download/meet/linux/1.0.8/ProtonMeet-desktop.rpm
#   # sudo dnf install -y ./ProtonMeet-desktop.rpm
#   # log_info "Note: TODO: Check if Proton has made available the SHA for ProtonMeet rpm yet."
#   install_proton_app "Proton Meet" "ProtonMeet_version.json" "https://proton.me/download/meet/linux/version.json"
  

# fi


# # install_proton_vpn

# # if [[ "$SETUP_TYPE" == "full" ]]; then
# #   download_verify_install "Proton Authenticator" \
# #     "https://proton.me/download/authenticator/linux/version.json" \
# #     "ProtonAuthenticator_version.json"

# #   download_verify_install "Proton Pass" \
# #     "https://proton.me/download/pass/linux/version.json" \
# #     "ProtonPass_version.json"

# #   download_verify_install "Proton Mail" \
# #     "https://proton.me/download/mail/linux/version.json" \
# #     "ProtonMail_version.json"

# #   # Meet now has a version.json endpoint; this replaces the old hard-coded version.
# #   download_verify_install "Proton Meet" \
# #     "https://proton.me/download/meet/linux/version.json" \
# #     "ProtonMeet_version.json"
# # fi



# ###############################################




# #   printf '\n%s\n' "--- resolving releases ---"

# #   # The catalogue: KEY|KIND|MANIFEST_OR_INDEX_URL
# #   #
# #   # KIND=json    -> resolve Url + Sha512CheckSum from the manifest (preferred)
# #   # KIND=listing -> resolve a filename from an Apache index (VPN only)
# #   #
# #   # NOTE: meet's version.json could not be confirmed by inspection at the time
# #   # of writing (the endpoint did not return a readable body, unlike Mail's which
# #   # is known-good). If it turns out not to exist, the meet entry will fail
# #   # cleanly and report itself -- run with --dry-run to check before trusting it.
# #   while IFS='|' read -r _key _kind _url; do
# #     [ -n "$_key" ] || continue
# #     product_selected "$_key" || continue

# #     case "$_kind" in
# #       json)    install_from_version_json "$_key" "$_url" || true ;;
# #       listing) install_protonvpn || true ;;
# #       *)       warn "unknown catalogue kind '$_kind' for $_key" ;;
# #     esac
# #   done <<EOF
# # vpn|listing|https://repo.protonvpn.com/fedora-${FEDORA_RELEASE_VERSION}-stable/protonvpn-stable-release/
# # pass|json|https://proton.me/download/PassDesktop/linux/x64/version.json
# # authenticator|json|https://proton.me/download/authenticator/linux/version.json
# # mail|json|https://proton.me/download/mail/linux/version.json
# # meet|json|https://proton.me/download/meet/linux/version.json
# # EOF

# #   printf '\n%s\n' "--- summary ---"
# #   if [ -n "$FAILURES" ]; then
# #     warn "failed products:$FAILURES"
# #     warn "artefacts and manifests retained in $DL_DIR"
# #     exit 1
# #   fi
# #   ok "all selected products processed successfully"
# #   log "artefacts retained in $DL_DIR"
# # }




# # ################################################




# # if [ "$SETUP_TYPE" = "full" ];
# # then 

# #   ######################### ProtonAuthenticator ###################################################################
# #   echo "************************ Installing ProtonAuthenticator ************************"
# #   # https://proton.me/support/set-up-proton-authenticator-linux
# #   # Download the RPM file.
# #   wget https://proton.me/download/authenticator/linux/ProtonAuthenticator.rpm
# #   # Download the json with SHA
# #   JSON_ProtonAuthenticator="ProtonAuthenticator_version.json"
# #   wget -O $JSON_ProtonAuthenticator https://proton.me/download/authenticator/linux/version.json
# #   # Get SHA from JSON
# #   SHA_ProtonAuthenticator=$(sh "$SYSUPDATE_SEC_CODE_DIR"/proton_get_sha.sh "$PROTON_CURRENT_DOWNLOADS_DIR" $JSON_ProtonAuthenticator)
# #   # Remove any leading or trailing quotes
# #   SHA_ProtonAuthenticator=${SHA_ProtonAuthenticator%\"} # Remove a single quote from the end
# #   SHA_ProtonAuthenticator=${SHA_ProtonAuthenticator#\"} # Remove a single quote from the beginning
# #   # Confirm the package's integrity
# #   # echo "$SHA_ProtonAuthenticator" ProtonAuthenticator.rpm | sha512sum --check -
  
# #   if echo "$SHA_ProtonAuthenticator" ProtonAuthenticator.rpm | sha512sum --check --status -; then
# #     echo "ProtonAuthenticator - Checksum verification passed. Proceeding with installation..."
# #     # Install it
# #     sudo dnf install -y ProtonAuthenticator.rpm
# #   else
# #     # Calculate *.rpm file's SHA for debugging:
# #     SHA_CALCULATED_PROTAUTH=$(sha512sum ProtonAuthenticator.rpm)
# #     echo "Calculated SHA512sum of *.rpm file: $SHA_CALCULATED_PROTAUTH did not match SHA512sum from json file: $SHA_ProtonAuthenticator" 
# #     echo "ERROR: ProtonAuthenticator - Checksum verification failed." >&2
# #     # exit 1
# #   fi
# # ################################################


# # # ---- Authenticator ----
# # info "Proton Authenticator"
# # JSON_AUTH="ProtonAuthenticator_version.json"
# # curl -fsSL -o "$JSON_AUTH" "https://proton.me/download/authenticator/linux/version.json"
# # AUTH_INFO=$(get_stable_rpm_info "$JSON_AUTH")
# # AUTH_URL="${AUTH_INFO%%|*}"
# # AUTH_SHA="${AUTH_INFO##*|}"
# # download_and_verify "$AUTH_URL" "$AUTH_SHA" "ProtonAuthenticator.rpm"
# # sudo dnf install -y ./ProtonAuthenticator.rpm


# # ################################################
# #   ######################### ProtonPass ###################################################################
# #   echo "************************ Installing ProtonPass ************************"
# #   # https://proton.me/support/set-up-proton-pass-linux
# #   # Download the RPM file.
# #   wget https://proton.me/download/PassDesktop/linux/x64/ProtonPass.rpm
# #   # Download the json with SHA
# #   JSON_ProtonPass="ProtonPass_version.json"
# #   wget -O $JSON_ProtonPass https://proton.me/download/PassDesktop/linux/x64/version.json
# #   # Get SHA from JSON
# #   SHA_ProtonPass=$(sh "$SYSUPDATE_SEC_CODE_DIR"/proton_get_sha.sh "$PROTON_CURRENT_DOWNLOADS_DIR" $JSON_ProtonPass)
# #   # Remove any leading or trailing quotes
# #   SHA_ProtonPass=${SHA_ProtonPass%\"} # Remove a single quote from the end
# #   SHA_ProtonPass=${SHA_ProtonPass#\"} # Remove a single quote from the beginning
# #   # Confirm the package's integrity
# #   # echo "$SHA_ProtonPass ProtonPass.rpm" | sha512sum --check -
  
# #   if echo "$SHA_ProtonPass ProtonPass.rpm" | sha512sum --check --status -; then
# #     echo "ProtonPass - Checksum verification passed. Proceeding with installation..."
# #     # Install it
# #     # sudo rpm -i --force ProtonPass.rpm # OFFICIAL way, but RedHat seems to discourage this usage
# #     sudo dnf install -y ProtonPass.rpm
# #   else
# #     # Calculate *.rpm file's SHA for debugging:
# #     SHA_CALCULATED_PROTPASS=$(sha512sum ProtonPass.rpm)
# #     echo "Calculated SHA512sum of *.rpm file: $SHA_CALCULATED_PROTPASS did not match SHA512sum from json file: $SHA_ProtonPass" 
# #     echo "ERROR: ProtonPass - Checksum verification failed." >&2
# #     # exit 1
# #   fi

# # ################################################



# # # ---- Pass ----
# # info "Proton Pass"
# # JSON_PASS="ProtonPass_version.json"
# # curl -fsSL -o "$JSON_PASS" "https://proton.me/download/PassDesktop/linux/x64/version.json"
# # # Note: path changed over time; the version.json above is the current one
# # PASS_INFO=$(get_stable_rpm_info "$JSON_PASS")
# # PASS_URL="${PASS_INFO%%|*}"
# # PASS_SHA="${PASS_INFO##*|}"
# # download_and_verify "$PASS_URL" "$PASS_SHA" "ProtonPass.rpm"
# # sudo dnf install -y ./ProtonPass.rpm

# # ################################################


# #   ######################### ProtonMail ###################################################################

# #   # TODO:
# #   # The download of rpm is returning ("CategoryName": "EarlyAccess",), the second item in list and 
# #   # proton_get_sha.sh is returning SHA of ("CategoryName": "Alpha",), the first item in list. 
# #   # However, we need to install the 3rd one ("CategoryName": "Stable",)
# #   # Right now, ProtonMail only installs if the first item in json and the downloaded rpm are same

# #   echo "************************ Installing ProtonMail ************************"
# #   # https://proton.me/support/set-up-proton-mail-linux
# #   # Download the RPM file.
# #   wget https://proton.me/download/mail/linux/ProtonMail-desktop-beta.rpm
# #   # Download the json with SHA
# #   JSON_ProtonMail="ProtonMail_version.json"
# #   wget -O ProtonMail_version.json https://proton.me/download/mail/linux/version.json
# #   # Get SHA from JSON
# #   SHA_ProtonMail=$(sh "$SYSUPDATE_SEC_CODE_DIR"/proton_get_sha.sh "$PROTON_CURRENT_DOWNLOADS_DIR" $JSON_ProtonMail)
# #   # Remove any leading or trailing quotes from the variable
# #   SHA_ProtonMail=${SHA_ProtonMail%\"} # Remove a single quote from the end
# #   SHA_ProtonMail=${SHA_ProtonMail#\"} # Remove a single quote from the beginning
# #   # check the RPM file's integrity
# #   # echo "$SHA_ProtonMail ProtonMail-desktop-beta.rpm" | sha512sum --check -

# #   if echo "$SHA_ProtonMail ProtonMail-desktop-beta.rpm" | sha512sum --check --status -; then
# #       echo "ProtonMail - Checksum verification passed. Proceeding with installation..."
# #       # Install it
# #       sudo dnf install -y ./ProtonMail-desktop-beta.rpm
# #   else
# #       # Calculate *.rpm file's SHA for debugging:
# #       SHA_CALCULATED_PROTMAIL=$(sha512sum ProtonMail-desktop-beta.rpm)
# #       echo "Calculated SHA512sum of *.rpm file: $SHA_CALCULATED_PROTMAIL did not match SHA512sum from json file: $SHA_ProtonMail" 
# #       echo "ERROR: ProtonMail - Checksum verification failed." >&2
# #       # exit 1
# #   fi



# # ################################################

# # # ---- Mail ----
# # info "Proton Mail"
# # JSON_MAIL="ProtonMail_version.json"
# # curl -fsSL -o "$JSON_MAIL" "https://proton.me/download/mail/linux/version.json"
# # MAIL_INFO=$(get_stable_rpm_info "$JSON_MAIL")
# # MAIL_URL="${MAIL_INFO%%|*}"
# # MAIL_SHA="${MAIL_INFO##*|}"
# # download_and_verify "$MAIL_URL" "$MAIL_SHA" "ProtonMail-desktop.rpm"
# # sudo dnf install -y ./ProtonMail-desktop.rpm

# # ################################################




# # # echo "************************ Installing Proton Calendar ************************"
# # # https://proton.me/calendar/download - this just downloads ProtonMail app which has a calendar section too.
# # # https://proton.me/download/mail/linux/1.13.4/ProtonMail-desktop-beta.rpm

# #   ######################### ProtonMeet ###################################################################
# #   echo "************************ Installing ProtonMeet ************************"
# #   # https://proton.me/meet/download
# #   # Download the RPM file.
# #   wget https://proton.me/download/meet/linux/1.0.8/ProtonMeet-desktop.rpm
# #   # Install it
# #   sudo dnf install -y ./ProtonMeet-desktop.rpm
# #   echo "Note: TODO: Check if Proton has made available the SHA for ProtonMeet rpm yet. Also, there is no good way to automate getting the latest rpm"
# #   # SHA availavle now - https://proton.me/download/meet/linux/version.json - TODO
# # fi



# # ################################################

# # # ---- Meet ----
# # info "Proton Meet"
# # JSON_MEET="ProtonMeet_version.json"
# # curl -fsSL -o "$JSON_MEET" "https://proton.me/download/meet/linux/version.json"
# # MEET_INFO=$(get_stable_rpm_info "$JSON_MEET")
# # MEET_URL="${MEET_INFO%%|*}"
# # MEET_SHA="${MEET_INFO##*|}"
# # download_and_verify "$MEET_URL" "$MEET_SHA" "ProtonMeet-desktop.rpm"
# # sudo dnf install -y ./ProtonMeet-desktop.rpm



# ################################################


# log_success "Proton setup completed successfully."



# ################################################################################################
# # linux/security_os_level/proton_get_sha.sh
# ################################################################################################

# #!/bin/sh

# # set -eux

# JSON_PATH=$1
# JSON_FILENAME=$2

# # JSON_PATH="/home/nbhirud/nb/Downloads/ProtonAG/proton_ag_downloads_2026-03-09_11-05-41"
# # JSON_FILENAME="ProtonPass_version.json"

# # jq '.Releases[0].File' $JSON_PATH/$JSON_FILENAME | jq length

# # latest_file=$(jq '.Releases[0].File' $JSON_PATH/$JSON_FILENAME)
# # echo $latest_file

# distro_count=$(jq '.Releases[0].File' "$JSON_PATH"/"$JSON_FILENAME" | jq length)

# ################### new ###################################
# ##exit # TODO remove after completing the below new code
# #
# #i_stable=0
# #distro_count=$(jq '.Releases[${i_stable}].File' "$JSON_PATH"/"$JSON_FILENAME" | jq length)
# #release_count=$(jq '.Releases' "$JSON_PATH"/"$JSON_FILENAME" | jq length)
# #
# ## echo $release_count
# #
# ## i=0
# ## while [ $i -lt "$release_count" ]
# ## do
# ##     # URL=$(jq ".Releases[0].File[$i].Url" "$JSON_PATH"/"$JSON_FILENAME")
# ##     CategoryName=$(jq ".Releases[$i].CategoryName" "$JSON_PATH"/"$JSON_FILENAME")
# ##     if echo "$CategoryName" | grep -q "Stable" ;
# ##     then
# ##         i_stable=$i
# ##     fi
# ##     i=$(( $i + 1 ))
# ## done
# #
# #distro_count=$(jq '.Releases[i_stable].File' "$JSON_PATH"/"$JSON_FILENAME" | jq length)
# ##################### /new ################################
# # echo $distro_count

# i=0
# while [ $i -lt "$distro_count" ]; do
#   URL=$(jq ".Releases[0].File[$i].Url" "$JSON_PATH"/"$JSON_FILENAME")

#   # if grep -q foo file.txt; then
#   #     echo "file.txt contains foo"

#   if echo "$URL" | grep -q ".rpm"; then
#     # echo $i
#     # echo "$URL found it"
#     Sha512CheckSum=$(jq ".Releases[0].File[$i].Sha512CheckSum" "$JSON_PATH"/"$JSON_FILENAME")
#     echo "$Sha512CheckSum"
#   fi

#   i=$(($i + 1))
# done
# ################################################################################################

