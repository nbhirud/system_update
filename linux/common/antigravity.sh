#!/usr/bin/env bash
##################################################################################
# Overview and Usage
##################################################################################
# Installs Google Antigravity (CLI `agy`, IDE, and 2.x desktop app) and runs every
# one of them ONLY inside a bubblewrap (bwrap) jail, so the agent can write nothing
# on the machine except inside PROJECTS_DIR. Not ~/.bashrc, not ~/.zshrc, not ~/.ssh.
#
# Why a jail and not Antigravity's own settings? Antigravity's built-in controls
# (terminal sandbox, "workspace only" permissions, deny rules) live INSIDE the agent
# process: they are policy, not an OS boundary. The model can ask to bypass the
# sandbox, and --dangerously-skip-permissions auto-approves that request
# (google-antigravity/antigravity-cli issue #36). A bwrap jail is built by the kernel
# BEFORE the app starts, so nothing the agent does can undo it.
#
# Jail rules (every launch):
#   * the whole machine is invisible or read-only, except PROJECTS_DIR (read-write)
#   * $HOME inside is NOT your home: your dotfiles, ~/.ssh, browser profiles are absent
#   * ALL state (login token, settings, history) lives in PROJECTS_DIR/.agy-state, so
#     PROJECTS_DIR is literally the only writable place on the host
#   * NO D-Bus, NO systemd-user socket, NO keyring, NO ssh-agent, NO runtime dir.
#     (A read-only mount does not stop connecting to a socket, and the session bus
#     can start arbitrary commands OUTSIDE the jail, so these must be absent.)
#     GUI mode gets exactly one socket: the Wayland display.
#   * environment is cleared (no SSH_AUTH_SOCK, cloud keys, tokens)
#   * git hooks and git config of existing projects are read-only
#
# Sample calls (assuming the caller uses the same variable names):
#   (a) all options:
#       bash antigravity.sh --real-user "$REAL_USER" --filename-timestamp "$FILENAME_TIMESTAMP" \
#            --projects-dir "$CODEPROJECTS_DIR/nbAntigravity" --cli-version 1.5.12 --cli-sha256 <64-hex> \
#            --app-source <https-url|/path/Antigravity.tar.gz> --ide-source <https-url|/path/IDE.tar.gz>
#   (b) mandatory only (nothing is mandatory; every option has a default):
#       bash antigravity.sh
#   (c) verification only:
#       bash antigravity.sh --verify-setup
#   (d) refresh binaries only (used by the systemd timer; keeps login and settings):
#       bash antigravity.sh --update
#
# Daily use after setup:
#   agy-jail new Play01                       create ${PROJECTS_DIR}/Play01
#   cd "${PROJECTS_DIR}/Play01" && agy-jail   terminal agent (CLI)
#   agy-jail ide [folder]                     Antigravity IDE   (also in the KDE menu)
#   agy-jail app                              Antigravity 2.x desktop app
#   agy-jail selftest | audit | doctor | open-url | shell | print | help

set -euo pipefail

##################################################################################
# User defined variables
##################################################################################
# Standard variables (identical across all my setup scripts).
REAL_USER="${REAL_USER:-${SUDO_USER:-${USER:-$(id -un)}}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update"
COMMON_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/common"
GETTER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commong"
HELPER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commonh"
SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"
SCRIPT_DATA_LOGS="${SCRIPT_DATA}/logs"
PROJECTS_DIR="${PROJECTS_DIR:-${CODEPROJECTS_DIR}/nbAntigravity}"   # the ONE writable directory

# Where things get installed (all inside the home directory, no root needed).
AGY_REPO="google-antigravity/antigravity-cli"            # official CLI release repo
DOWNLOAD_PAGE="https://antigravity.google/download"      # official page listing the 2.x tarballs
AGY_INSTALL_DIR="${HOME_DIR}/.local/opt/agy-jail"        # bin/ (CLI), app/, ide/, shims/ (all read-only in the jail)
AGY_LAUNCHER="${HOME_DIR}/.local/bin/agy-jail"
AGY_CONF_DIR="${HOME_DIR}/.config/agy-jail"
AGY_CONF_FILE="${AGY_CONF_DIR}/agy-jail.conf"
SYSTEMD_USER_DIR="${HOME_DIR}/.config/systemd/user"
BLEACHBIT_CLEANER_DIR="${HOME_DIR}/.config/bleachbit/cleaners"
DESKTOP_DIR="${HOME_DIR}/.local/share/applications"

ORIG_ARGS=("$@")                                   # original command line, reused when re-executing
SCRIPT_PATH="$(realpath -e -- "$0")"               # absolute path of this script (used by the systemd unit)
OPT_CLI_VERSION=""; OPT_CLI_SHA256=""; OPT_APP_SOURCE=""; OPT_IDE_SOURCE=""
MODE="setup"                                       # setup | verify | update

##################################################################################
# Named Options processing
##################################################################################
usage() { sed -n '/^# Overview and Usage/,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' | sed '1d'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --real-user)          REAL_USER="$2"; shift 2 ;;
    --filename-timestamp) FILENAME_TIMESTAMP="$2"; shift 2 ;;
    --projects-dir)       PROJECTS_DIR="$2"; shift 2 ;;
    --cli-version)        OPT_CLI_VERSION="$2"; shift 2 ;;
    --cli-sha256)         OPT_CLI_SHA256="$2"; shift 2 ;;
    --app-source)         OPT_APP_SOURCE="$2"; shift 2 ;;
    --ide-source)         OPT_IDE_SOURCE="$2"; shift 2 ;;
    --verify-setup)       MODE="verify"; shift ;;
    --update)             MODE="update"; shift ;;
    -h|--help)            usage; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

# Options may have changed REAL_USER / FILENAME_TIMESTAMP / PROJECTS_DIR, so recompute
# everything derived from them in ONE place (no drift between the two definitions).
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"; CODEPROJECTS_DIR="${NBDIR}/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update"
GETTER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commong"; HELPER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commonh"
SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"; SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"; SCRIPT_DATA_LOGS="${SCRIPT_DATA}/logs"
ANTIGRAVITY_CURRENT_DOWNLOADS_DIR="${SCRIPT_DATA_DOWNLOADS}/antigravity/antigravity_${FILENAME_TIMESTAMP}"
ANTIGRAVITY_CURRENT_BACKUP_DIR="${SCRIPT_DATA_BACKUPS}/antigravity/antigravity_${FILENAME_TIMESTAMP}"
ANTIGRAVITY_CURRENT_LOG_DIR="${SCRIPT_DATA_LOGS}/antigravity/antigravity_${FILENAME_TIMESTAMP}"
AGY_INSTALL_DIR="${HOME_DIR}/.local/opt/agy-jail"; AGY_LAUNCHER="${HOME_DIR}/.local/bin/agy-jail"
AGY_CONF_DIR="${HOME_DIR}/.config/agy-jail"; AGY_CONF_FILE="${AGY_CONF_DIR}/agy-jail.conf"
SYSTEMD_USER_DIR="${HOME_DIR}/.config/systemd/user"
BLEACHBIT_CLEANER_DIR="${HOME_DIR}/.config/bleachbit/cleaners"; DESKTOP_DIR="${HOME_DIR}/.local/share/applications"
AGY_STATE_DIR="${PROJECTS_DIR}/.agy-state"          # login, settings, history: INSIDE the one writable directory

##################################################################################
# Helpers
##################################################################################
for h in helper_logging.sh helper_backup.sh helper_download.sh helper_github.sh helper_run_as_user.sh helper_fonts.sh; do
  [ -r "${HELPER_DIR}/${h}" ] || { echo "Missing helper ${HELPER_DIR}/${h}" >&2; exit 1; }
  # shellcheck disable=SC1090
  . "${HELPER_DIR}/${h}"
done

# If started with sudo, re-run as the real user: everything here is per-user, and a
# root-owned file inside a user-writable tree is a classic privilege-escalation trap.
export REAL_USER FILENAME_TIMESTAMP
ensure_real_user "${ORIG_ARGS[@]}"

# Colored terminal output AND a log file: under a terminal, re-run the whole script
# inside util-linux `script`, which gives the child a real pty (colors survive) while
# copying everything to the log. From another script or systemd the caller captures output.
mkdir -p "$ANTIGRAVITY_CURRENT_LOG_DIR"
LOG_FILE="${ANTIGRAVITY_CURRENT_LOG_DIR}/antigravity_${MODE}.log"
if [ -t 1 ] && [ -z "${ANTIGRAVITY_LOGGING:-}" ] && command -v script >/dev/null 2>&1; then
  export ANTIGRAVITY_LOGGING=1
  exec script -qefc "$(printf '%q ' "$SCRIPT_PATH" "${ORIG_ARGS[@]}")" "$LOG_FILE"
fi

[ "$(id -u)" -ne 0 ] || log_die "Run as a normal user (this installs per-user files)."
umask 077   # new files default to private; shared-readable bits are set explicitly where needed

# Reads one getter from GETTER_DIR; prints its result, or the fallback ($2) if missing.
get() { if [ -r "${GETTER_DIR}/$1.sh" ]; then sh "${GETTER_DIR}/$1.sh" 2>/dev/null || echo "${2:-}"; else echo "${2:-}"; fi; }

detect_arch() {   # prints: x64 | arm64   (CLI asset suffix)
  case "$(uname -m)" in x86_64|amd64) echo x64 ;; aarch64|arm64) echo arm64 ;; *) log_die "Unsupported CPU: $(uname -m)" ;; esac
}

# Prints the SHA-256 GitHub shows for a CLI release asset. The release has no .sha256
# file, but GitHub publishes a digest per asset on the release page; scraping that page
# avoids the REST API's tight anonymous rate limit.
github_asset_digest() {
  local tag="$1" asset="$2"
  curl -fsSL --proto '=https' --tlsv1.2 --retry 3 "https://github.com/${AGY_REPO}/releases/expanded_assets/${tag}" \
    | tr -d '\n' | grep -oE "digest for ${asset}\"[^>]*value=\"sha256:[0-9a-f]{64}" \
    | grep -oE '[0-9a-f]{64}$' | head -1 || true
}

# Explicit ClamAV scan (even if the downloads dir is on-access scanned, in case that
# service is down). clamscan exit codes: 0 clean, 1 infected, 2 error.
scan_file() {
  local f="$1" rc
  if command -v clamscan >/dev/null 2>&1; then
    set +e; clamscan --no-summary "$f"; rc=$?; set -e
    [ "$rc" -ne 1 ] || { rm -f "$f"; log_die "ClamAV flagged $(basename "$f") as infected."; }
    [ "$rc" -eq 0 ] || log_warn "ClamAV returned status ${rc} (scanner error) for $(basename "$f")."
  else
    log_warn "clamscan not installed; skipped malware scan of $(basename "$f")."
  fi
}

# Safe tar extraction: Python's "data" filter refuses absolute paths, '..' traversal,
# links pointing outside the destination and setuid bits. Fallback for old Pythons.
safe_extract() {
  python3 - "$1" "$2" <<'PY'
import sys, tarfile
archive, dest = sys.argv[1:3]
with tarfile.open(archive, "r:*") as t:
    try:
        t.extractall(dest, filter="data")
    except TypeError:                      # Python without extraction filters
        for m in t.getmembers():
            parts = m.name.split("/")
            if m.name.startswith("/") or ".." in parts or m.islnk() or \
               (m.issym() and (m.linkname.startswith("/") or ".." in m.linkname.split("/"))):
                sys.exit("unsafe archive member: " + m.name)
        t.extractall(dest)
PY
}

# ---------------------------- CLI (agy) --------------------------------------
# Download + verify + scan + install the CLI binary. Atomic: the new binary replaces the
# old one only after every check passed.
install_cli_binary() {
  local tag asset url dest expected actual tmpdir
  tag="${OPT_CLI_VERSION:-$(github_latest_tag "$AGY_REPO")}"
  [ -n "$tag" ] || log_die "Could not determine the latest CLI release tag."
  asset="agy_cli_linux_$(detect_arch).tar.gz"
  url="https://github.com/${AGY_REPO}/releases/download/${tag}/${asset}"
  mkdir -p "$ANTIGRAVITY_CURRENT_DOWNLOADS_DIR"; chmod 700 "$ANTIGRAVITY_CURRENT_DOWNLOADS_DIR"
  dest="${ANTIGRAVITY_CURRENT_DOWNLOADS_DIR}/${asset}"
  log_info "Downloading CLI ${asset} (${tag})"
  download_file "$url" "$dest"
  expected="${OPT_CLI_SHA256:-$(github_asset_digest "$tag" "$asset")}"
  [ -n "$expected" ] || log_die "No SHA-256 digest found on the release page. Re-run with --cli-sha256 <hex>."
  actual="$(sha256sum "$dest" | cut -d' ' -f1)"
  [ "$expected" = "$actual" ] || log_die "SHA-256 mismatch! expected ${expected}, got ${actual}."
  log_success "CLI SHA-256 verified: ${actual}"
  scan_file "$dest"
  tmpdir="$(mktemp -d "${ANTIGRAVITY_CURRENT_DOWNLOADS_DIR}/extract.XXXXXX")"
  # Extract ONLY the one member we expect (no other path can be written).
  tar -xzf "$dest" -C "$tmpdir" --no-same-owner antigravity || log_die "Tarball layout changed: no 'antigravity' binary."
  chmod 755 "${tmpdir}/antigravity"
  "${tmpdir}/antigravity" --version >/dev/null 2>&1 || log_die "New CLI binary does not run on this system."
  mkdir -p "${AGY_INSTALL_DIR}/bin"
  # Installed as `agy` but OFF $PATH: typing `agy` can never start an UNCONFINED agent.
  mv -f "${tmpdir}/antigravity" "${AGY_INSTALL_DIR}/bin/agy.new"; mv -f "${AGY_INSTALL_DIR}/bin/agy.new" "${AGY_INSTALL_DIR}/bin/agy"
  rm -rf "$tmpdir"
  log_success "Installed CLI agy $("${AGY_INSTALL_DIR}/bin/agy" --version 2>/dev/null | head -1)"
}

# ---------------------------- GUI (app / ide) --------------------------------
# Google ships the 2.x desktop app and IDE for Linux as tarballs only (the old RPM repo
# is a legacy 1.x IDE and has signature checking switched off, so it is NOT used).
# The download page references a main-*.js bundle that contains the tarball URLs.
gui_discover_url() {   # $1 = app | ide ; prints newest matching https URL, or nothing
  local kind="$1" plat page all b u re
  case "$(uname -m)" in x86_64|amd64) plat=linux-x64 ;; aarch64|arm64) plat=linux-arm ;; *) return 1 ;; esac
  page="$(curl -fsSL --compressed --proto '=https' --tlsv1.2 --retry 3 "$DOWNLOAD_PAGE" 2>/dev/null || true)"
  all="$page"
  while IFS= read -r b; do
    case "$b" in http*) u="$b" ;; /*) u="https://antigravity.google${b}" ;; *) u="https://antigravity.google/${b}" ;; esac
    all+=$'\n'"$(curl -fsSL --compressed --proto '=https' --tlsv1.2 --retry 3 "$u" 2>/dev/null || true)"
  done < <(printf '%s' "$page" | grep -oE '(src|href)="[^"]*main-[^"]+\.js"' | sed -E 's/^(src|href)="//; s/"$//')
  all="${all//\\\//\/}"                                      # JS strings may escape slashes
  if [ "$kind" = ide ]; then re="https://[^\"' \\\\]+/stable/[^\"' \\\\]+/${plat}/Antigravity(%20| )IDE\\.tar\\.gz"
  else                       re="https://[^\"' \\\\]+/antigravity-hub/[^\"' \\\\]+/${plat}/Antigravity\\.tar\\.gz"; fi
  printf '%s' "$all" | grep -oE "$re" | sort -uV | tail -1
}
gui_version_from_url() { sed -E 's#.*/(antigravity-hub|stable)/([^/-]+)[^/]*/.*#\2#' <<<"$1"; }

# Install one GUI product. $2 = optional source override (https URL or local tarball path).
install_gui() {
  local kind="$1" src="${2:-}" url="" ver="${3:-}" archive tmpdir top exe
  if [ -z "$src" ]; then
    log_info "Looking up the current Antigravity ${kind} download"
    url="$(gui_discover_url "$kind")"
    [ -n "$url" ] || log_die "Could not find the ${kind} download link (the page layout may have changed). Download the Linux tarball from ${DOWNLOAD_PAGE} and re-run with --${kind}-source <file-or-url>."
    ver="$(gui_version_from_url "$url")"
  fi
  mkdir -p "$ANTIGRAVITY_CURRENT_DOWNLOADS_DIR"; chmod 700 "$ANTIGRAVITY_CURRENT_DOWNLOADS_DIR"
  archive="${ANTIGRAVITY_CURRENT_DOWNLOADS_DIR}/antigravity-${kind}.tar.gz"
  case "${src:-$url}" in
    https://*) log_info "Downloading ${kind} (${ver:-custom source})"; download_file "${src:-$url}" "$archive" ;;
    /*)        [ -f "$src" ] || log_die "No such file: $src"; cp -- "$src" "$archive" ;;
    *)         log_die "--${kind}-source must be an https:// URL or an absolute file path." ;;
  esac
  # Google publishes no checksum for these tarballs: integrity rests on HTTPS to Google's
  # CDN plus the scan. The digest is recorded so later changes are visible.
  log_info "${kind} tarball SHA-256: $(sha256sum "$archive" | cut -d' ' -f1)"
  scan_file "$archive"
  tmpdir="$(mktemp -d "${ANTIGRAVITY_CURRENT_DOWNLOADS_DIR}/gui-${kind}.XXXXXX")"
  safe_extract "$archive" "$tmpdir"
  top="$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -1)"
  [ -n "$top" ] || log_die "Unexpected archive layout (no top-level directory)."
  exe="$(find "$top" -maxdepth 1 -type f \( -name antigravity -o -name antigravity-ide \) -perm /111 | head -1)"
  [ -n "$exe" ] || log_die "No Antigravity executable in the ${kind} archive."
  rm -rf "${AGY_INSTALL_DIR}/${kind}.new"; mkdir -p "${AGY_INSTALL_DIR}/${kind}.new" "${AGY_INSTALL_DIR}/versions"
  mv "$top" "${AGY_INSTALL_DIR}/${kind}.new/"
  rm -rf "${AGY_INSTALL_DIR:?}/${kind}"; mv "${AGY_INSTALL_DIR}/${kind}.new" "${AGY_INSTALL_DIR}/${kind}"
  printf '%s\n' "${ver:-custom}" > "${AGY_INSTALL_DIR}/versions/${kind}"
  rm -rf "$tmpdir"
  log_success "Installed Antigravity ${kind} ${ver:-custom}"
}

# Best-effort wrapper: a failing GUI download must never abort the CLI install.
# The subshell contains log_die's `exit`.
try_install_gui() {
  local kind="$1" src="${2:-}" ver="${3:-}" rc=0
  # A plain subshell (NOT inside if/||/&&) keeps `set -e` active, so any failing step aborts
  # this install; `set +e` around it stops that abort from reaching the CLI install.
  set +e; ( set -e; install_gui "$kind" "$src" "$ver" ); rc=$?; set -e
  [ "$rc" -eq 0 ] || log_warn "Antigravity ${kind} NOT installed (see message above). The CLI is unaffected."
}

# --update: refresh whatever is installed, only when a newer release exists.
update_only() {
  local latest current kind url newv
  latest="${OPT_CLI_VERSION:-$(github_latest_tag "$AGY_REPO")}"
  current="$("${AGY_INSTALL_DIR}/bin/agy" --version 2>/dev/null | head -1 || true)"
  if [ "$latest" != "$current" ]; then log_info "CLI ${current:-none} -> ${latest}"; install_cli_binary; else log_info "CLI ${current} is current."; fi
  for kind in app ide; do
    [ -d "${AGY_INSTALL_DIR}/${kind}" ] || continue
    url="$(gui_discover_url "$kind" || true)"; [ -n "$url" ] || { log_warn "Could not look up ${kind} updates."; continue; }
    newv="$(gui_version_from_url "$url")"
    if [ "$newv" != "$(cat "${AGY_INSTALL_DIR}/versions/${kind}" 2>/dev/null || true)" ]; then try_install_gui "$kind" "$url" "$newv"; else log_info "${kind} ${newv} is current."; fi
  done
}

##################################################################################
# Inferred variables
##################################################################################
DISTRO="$(get get_distro_name unknown)"
RAM_MB="$(get get_ram_size 8192)"; case "$RAM_MB" in ""|*[!0-9]*) RAM_MB=8192 ;; esac
RAM_PROFILE="$(get get_ram_profile mid)"
GPU_TIER="$(get get_gpu_tier mid)"
DESKTOP="$(get get_desktop_env unknown)"

# RAM-aware sizing: /tmp and the CLI's throwaway home are RAM disks; the Go runtime of
# the CLI gets a soft heap limit on small machines; the GUI's V8 heap scales with RAM.
case "$RAM_PROFILE" in
  low)  TMP_SIZE_MB=256;  HOME_SIZE_MB=128; GOMEMLIMIT_VALUE="900MiB" ;;
  high) TMP_SIZE_MB=4096; HOME_SIZE_MB=512; GOMEMLIMIT_VALUE="" ;;
  *)    TMP_SIZE_MB=1024; HOME_SIZE_MB=256; GOMEMLIMIT_VALUE="" ;;
esac
if   [ "$RAM_MB" -lt 8192 ];  then GUI_V8_HEAP_MB=2048
elif [ "$RAM_MB" -lt 32768 ]; then GUI_V8_HEAP_MB=4096
else                               GUI_V8_HEAP_MB=8192; fi
# GPU: weak/legacy GPUs (get_gpu_tier = low) get software rendering and NO /dev/dri in the
# jail (fewer glitches, smaller kernel attack surface). Others get hardware acceleration.
if [ "$GPU_TIER" = low ]; then GUI_USE_GPU=0; else GUI_USE_GPU=1; fi

if [ "$MODE" = update ]; then update_only; exit 0; fi

##################################################################################
# Backup
##################################################################################
# Back up everything this script will touch, plus places where an older manual setup
# (the official install.sh, desktop app, earlier jail scripts) may have written.
do_backup() {
  log_header "Backing up existing files to ${ANTIGRAVITY_CURRENT_BACKUP_DIR}"
  mkdir -p "$ANTIGRAVITY_CURRENT_BACKUP_DIR"; chmod 700 "$ANTIGRAVITY_CURRENT_BACKUP_DIR"
  local p n=0
  for p in "$AGY_INSTALL_DIR" "$AGY_LAUNCHER" "$AGY_CONF_DIR" "$AGY_STATE_DIR" \
           "${SYSTEMD_USER_DIR}/agy-jail-update.service" "${SYSTEMD_USER_DIR}/agy-jail-update.timer" \
           "${BLEACHBIT_CLEANER_DIR}/agy_jail.xml" "${DESKTOP_DIR}/agy-jail-ide.desktop" "${DESKTOP_DIR}/agy-jail-app.desktop" \
           "${HOME_DIR}/.local/bin/agy" "${HOME_DIR}/.gemini" "${HOME_DIR}/.config/antigravity" \
           "${HOME_DIR}/.config/Antigravity" "${HOME_DIR}/.config/Antigravity IDE" "${HOME_DIR}/.antigravity-ide" \
           "${HOME_DIR}/.bashrc" "${HOME_DIR}/.profile" "${HOME_DIR}/.zshrc"; do
    if [ -e "$p" ] || [ -L "$p" ]; then n=$((n+1)); backup_path "$p" "$ANTIGRAVITY_CURRENT_BACKUP_DIR" "item${n}_$(basename "$p")"; fi
  done
  log_info "Backed up ${n} item(s). (The backup may contain old login tokens: it is mode 700.)"
}

##################################################################################
# Reset
##################################################################################
# Fresh start: remove only what THIS script owns. Never ~/.gemini, rc files, etc.
do_reset() {
  log_header "Removing previous agy-jail setup (backed up above)"
  systemctl --user disable --now agy-jail-update.timer >/dev/null 2>&1 || true
  rm -rf "$AGY_INSTALL_DIR" "$AGY_LAUNCHER" "$AGY_CONF_DIR" "$AGY_STATE_DIR" \
         "${SYSTEMD_USER_DIR}/agy-jail-update.service" "${SYSTEMD_USER_DIR}/agy-jail-update.timer" \
         "${BLEACHBIT_CLEANER_DIR}/agy_jail.xml" "${DESKTOP_DIR}/agy-jail-ide.desktop" "${DESKTOP_DIR}/agy-jail-app.desktop"
}

##################################################################################
# Security
##################################################################################
# Nothing needs firewalld/SELinux changes: bwrap runs as the user, the jail shares the
# host network, and SELinux treats it like any other user process (Flatpak does the same).
# Optional egress control: OpenSnitch rules on the binaries under ${AGY_INSTALL_DIR} (see Notes).
# Syncthing/backup tools must NOT sync PROJECTS_DIR/.agy-state (it holds login tokens):
write_sync_ignores() {
  local f="${PROJECTS_DIR}/.stignore"
  grep -qxF '.agy-state' "$f" 2>/dev/null || printf '// agy-jail: login tokens, never sync\n.agy-state\n' >> "$f"
}

##################################################################################
# Verification
##################################################################################
PASS=0; FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then log_success "$d"; PASS=$((PASS+1)); else log_error "FAILED: $d"; FAIL=$((FAIL+1)); fi; }
verify_setup() {
  log_header "Verification"
  check "bubblewrap installed"                       command -v bwrap
  check "CLI binary present and runs"                "${AGY_INSTALL_DIR}/bin/agy" --version
  check "launcher installed and executable"          test -x "$AGY_LAUNCHER"
  check "launcher config present"                    test -r "$AGY_CONF_FILE"
  check "projects dir exists"                        test -d "$PROJECTS_DIR"
  check "state dir is private (700)"                 test "$(stat -c %a "$AGY_STATE_DIR")" = 700
  check "CLI settings.json is valid JSON"            python3 -m json.tool "${AGY_STATE_DIR}/gemini/antigravity-cli/settings.json"
  check "xdg-open shim installed"                    test -x "${AGY_INSTALL_DIR}/shims/xdg-open"
  check "unprivileged user namespaces work"          unshare -Ur true
  check "BleachBit cleaner is valid XML"             python3 -c "import xml.dom.minidom,sys;xml.dom.minidom.parse(sys.argv[1])" "${BLEACHBIT_CLEANER_DIR}/agy_jail.xml"
  check "auto-update timer enabled"                  systemctl --user is-enabled agy-jail-update.timer
  local k
  for k in app ide; do
    if [ -d "${AGY_INSTALL_DIR}/${k}" ]; then
      check "${k}: executable present"               bash -c 'test -n "$(find "$1" -maxdepth 2 -type f \( -name antigravity -o -name antigravity-ide \) -perm /111 -print -quit)"' _ "${AGY_INSTALL_DIR}/${k}"
      check "${k}: menu entry present"               test -r "${DESKTOP_DIR}/agy-jail-${k}.desktop"
    else
      log_warn "${k}: not installed (re-run with --${k}-source <file-or-url> if auto-discovery failed)"
    fi
  done
  case ":$PATH:" in *":${HOME_DIR}/.local/bin:"*) log_success "\$HOME/.local/bin is on PATH" ;; *) log_warn "\$HOME/.local/bin is not on PATH; use ${AGY_LAUNCHER}" ;; esac
  [ -e "${HOME_DIR}/.local/bin/agy" ] && log_warn "An UNCONFINED ${HOME_DIR}/.local/bin/agy exists (official installer). Never run it; use agy-jail."
  command -v getenforce >/dev/null 2>&1 && log_info "SELinux: $(getenforce)"
  log_info "Running the confinement self-test (CLI and GUI profiles)..."
  if "$AGY_LAUNCHER" selftest; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
  log_info "Verification: ${PASS} passed, ${FAIL} failed."
  [ "$FAIL" -eq 0 ]
}
if [ "$MODE" = verify ]; then verify_setup; exit $?; fi

##################################################################################
# main setup
##################################################################################
log_header "Antigravity jail setup (user: ${REAL_USER}, RAM: ${RAM_PROFILE}/${RAM_MB}MB, GPU tier: ${GPU_TIER}, desktop: ${DESKTOP})"

for t in curl tar sha256sum realpath python3 findmnt; do
  command -v "$t" >/dev/null 2>&1 || log_die "Required tool missing: $t"
done
if ! command -v bwrap >/dev/null 2>&1; then
  if [ "$DISTRO" = fedora ]; then log_info "Installing bubblewrap (needs sudo)"; sudo dnf install -y bubblewrap
  else log_die "bubblewrap (bwrap) is not installed; install it with your package manager."; fi
fi
unshare -Ur true 2>/dev/null || log_die "Unprivileged user namespaces are disabled (user.max_user_namespaces=0?); bwrap cannot work."

do_backup
do_reset

# --- projects dir + jail state (state lives INSIDE the one writable directory) ----
[ ! -L "$PROJECTS_DIR" ] || log_die "PROJECTS_DIR must not be a symbolic link."
mkdir -p "$PROJECTS_DIR"; chmod 700 "$PROJECTS_DIR"
case "$(realpath -e "$PROJECTS_DIR")/" in "${HOME_DIR}"/?*) ;; *) log_die "PROJECTS_DIR must be inside ${HOME_DIR}." ;; esac
mkdir -p "$AGY_STATE_DIR"/{gemini/antigravity-cli,antigravity-config,gui-home,run}
chmod 700 "$AGY_STATE_DIR" "$AGY_STATE_DIR"/{gemini,antigravity-config,gui-home,run}
write_sync_ignores

# --- binaries ----------------------------------------------------------------
install_cli_binary
try_install_gui app "$OPT_APP_SOURCE"
try_install_gui ide "$OPT_IDE_SOURCE"

# --- xdg-open shim: the jail has no browser, so links are parked for YOU to open ---
mkdir -p "${AGY_INSTALL_DIR}/shims"
cat > "${AGY_INSTALL_DIR}/shims/xdg-open" <<'EOF'
#!/bin/sh
# agy-jail replacement for xdg-open. The jail cannot (and must not) start host programs,
# so the requested link is parked in a file. YOU open it from the host:  agy-jail open-url
url="${1:-}"
mkdir -p /run/agy 2>/dev/null
printf '%s\n' "$url" > /run/agy/last-url.txt 2>/dev/null
printf '\n[agy-jail] The app asked to open a link. Open it yourself with:  agy-jail open-url\n[agy-jail] %s\n\n' "$url" >&2
exit 0
EOF
chmod 755 "${AGY_INSTALL_DIR}/shims" "${AGY_INSTALL_DIR}/shims/xdg-open"

# --- CLI settings -------------------------------------------------------------
# Keys per the official permissions page (agentMode, permissions deny/ask/allow) plus
# community-documented telemetry keys (check /config after first login: the telemetry
# switch can also be an account-level setting).
#  * agentMode "" = "default" mode: asks to review every edit/command (the CLI otherwise
#    starts in `auto`, which is too permissive for a first week; Shift+Tab switches later).
#  * deny: sudo/su and direct writes to git hooks/config (the jail already blocks them).
#  * ask : writes to files that run on YOUR side later (see audit) trigger a prompt.
cat > "${AGY_STATE_DIR}/gemini/antigravity-cli/settings.json" <<'EOF'
{
  "agentMode": "",
  "enableTelemetry": false,
  "showFeedbackSurvey": false,
  "permissions": {
    "deny": [
      "command(sudo)",
      "command(su)",
      "write_file(.git/hooks)",
      "write_file(.git/config)"
    ],
    "ask": [
      "write_file(.envrc)",
      "write_file(.vscode/)",
      "write_file(.idea/)",
      "write_file(.husky/)",
      "write_file(.devcontainer/)",
      "write_file(.pre-commit-config.yaml)"
    ]
  }
}
EOF

# --- global agent rules (auto-loaded from ~/.gemini/GEMINI.md per the Rules docs) ----
cat > "${AGY_STATE_DIR}/gemini/GEMINI.md" <<'EOF'
# Global rules (written by agy-jail)

You run inside a filesystem jail. Only the projects directory is writable; everything else
is read-only or absent, and there is no access to the host's D-Bus, SSH keys or browser.

- Work only inside the current project folder.
- Ask before creating or changing files that run automatically on the user's machine later:
  .git/hooks, .git/config, .envrc, .vscode/tasks.json, .devcontainer, .husky, Makefile
  targets, package.json lifecycle scripts (postinstall etc.).
- Never create symbolic links or hard links that point outside the project folder.
- Ask before downloading and executing anything, and before installing system packages.
- Keep changes small and explain what you changed.
EOF
chmod 600 "${AGY_STATE_DIR}/gemini/antigravity-cli/settings.json" "${AGY_STATE_DIR}/gemini/GEMINI.md"

# --- IDE settings (VS Code fork): telemetry off, no in-app updater, my fonts -----------
# The IDE cannot write to its read-only install dir, so in-app updates are disabled; the
# systemd timer updates it. Directory name per community guides (unverified).
FONT_CODE="$(first_installed_font "JetBrainsMono Nerd Font" "JetBrains Mono" "Noto Sans Mono" monospace || true)"; FONT_CODE="${FONT_CODE:-monospace}"
FONT_TERM="$(first_installed_font "NotoMono Nerd Font" "UbuntuMono Nerd Font" "Noto Sans Mono" monospace || true)"; FONT_TERM="${FONT_TERM:-monospace}"
IDE_USER_DIR="${AGY_STATE_DIR}/gui-home/.config/Antigravity IDE/User"
mkdir -p "$IDE_USER_DIR"
cat > "${IDE_USER_DIR}/settings.json" <<EOF
{
  "telemetry.telemetryLevel": "off",
  "update.mode": "none",
  "extensions.autoUpdate": false,
  "security.workspace.trust.enabled": true,
  "security.workspace.trust.untrustedFiles": "prompt",
  "task.allowAutomaticTasks": "off",
  "git.autofetch": false,
  "editor.fontFamily": "'${FONT_CODE}', monospace",
  "terminal.integrated.fontFamily": "'${FONT_TERM}', monospace"
}
EOF
find "${AGY_STATE_DIR}/gui-home" -type d -exec chmod 700 {} +

# --- jail's git config (read-only inside the jail) ------------------------------------
# The commit identity is copied from the host's global git config at setup time (it is
# runtime data, not stored in this script). Keys/credentials are NOT copied.
GIT_NAME="$(git config --global --get user.name 2>/dev/null || true)"
GIT_MAIL="$(git config --global --get user.email 2>/dev/null || true)"
{
  echo "# Git config used INSIDE agy-jail only (your real ~/.gitconfig is invisible there)."
  if [ -n "$GIT_NAME" ] && [ -n "$GIT_MAIL" ]; then printf '[user]\n\tname = %s\n\temail = %s\n' "$GIT_NAME" "$GIT_MAIL"; fi
  printf '[init]\n\tdefaultBranch = main\n[safe]\n\tdirectory = *\n'
} > "${AGY_STATE_DIR}/gitconfig"
chmod 644 "${AGY_STATE_DIR}/gitconfig"

# --- launcher config ------------------------------------------------------------------
mkdir -p "$AGY_CONF_DIR"; chmod 700 "$AGY_CONF_DIR"
cat > "$AGY_CONF_FILE" <<EOF
# agy-jail configuration (sourced by the launcher; rewritten by the setup script).
# The agent may write ONLY inside PROJECTS_DIR (login/settings live in PROJECTS_DIR/.agy-state).
PROJECTS_DIR="${PROJECTS_DIR}"
INSTALL_DIR="${AGY_INSTALL_DIR}"
TMP_SIZE_BYTES=$((TMP_SIZE_MB * 1024 * 1024))     # RAM-backed /tmp inside the jail
HOME_SIZE_BYTES=$((HOME_SIZE_MB * 1024 * 1024))   # RAM-backed throwaway \$HOME for the CLI
GOMEMLIMIT_VALUE="${GOMEMLIMIT_VALUE}"            # soft Go heap limit (low-RAM machines only)
GUI_V8_HEAP_MB=${GUI_V8_HEAP_MB}                  # Electron JS heap limit for the IDE/app
GUI_USE_GPU=${GUI_USE_GPU}                        # 1 = expose /dev/dri; 0 = software rendering (set 0 if the window is black)
# Extra flags for the IDE/app. If the app says "No usable sandbox!", Chromium's own sandbox
# cannot nest inside the jail: use  GUI_EXTRA_ARGS=( --no-sandbox )  (the jail stays the real wall).
GUI_EXTRA_ARGS=()
# 1 = make each project's .git/config read-only inside the jail (recommended, see Notes).
PROTECT_GIT_CONFIG=1
# Extra host paths the agent may READ, e.g.  EXTRA_RO=( "\$HOME/.cargo" "\$HOME/.rustup" )
EXTRA_RO=()
# Host environment variables to pass in (the jail starts EMPTY). Example: PASS_ENV=( GEMINI_API_KEY )
PASS_ENV=()
EOF
chmod 600 "$AGY_CONF_FILE"

# --- the launcher itself --------------------------------------------------------------
mkdir -p "$(dirname "$AGY_LAUNCHER")"
cat > "$AGY_LAUNCHER" <<'LAUNCHER_EOF'
#!/usr/bin/env bash
# agy-jail: run Google Antigravity (CLI, IDE, desktop app) inside a bubblewrap jail.
# The agent can WRITE only inside PROJECTS_DIR. Everything else is invisible or read-only.
#   agy-jail [agy args]     terminal agent in the current project (cwd must be inside PROJECTS_DIR)
#   agy-jail ide [folder]   Antigravity IDE            agy-jail app    Antigravity 2.x desktop app
#   agy-jail new NAME       create PROJECTS_DIR/NAME   agy-jail shell  jailed bash (see what the agent sees)
#   agy-jail selftest       prove the confinement      agy-jail audit  files that could run code on YOUR side
#   agy-jail open-url       open the last link the jailed app tried to open (you confirm)
#   agy-jail doctor         system diagnosis           agy-jail print  show the bwrap command line
set -euo pipefail
shopt -s nullglob
umask 077

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/agy-jail/agy-jail.conf"
[ -r "$CONF" ] || { echo "agy-jail: missing $CONF (re-run the setup script)" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONF"
die() { echo "agy-jail: $*" >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || die "do not run as root"
command -v bwrap >/dev/null || die "bubblewrap missing (sudo dnf install bubblewrap)"

PROJECTS_REAL="$(realpath -e -- "$PROJECTS_DIR")"
JAIL_STATE="$PROJECTS_REAL/.agy-state"
UID_NOW="$(id -u)"

# True when $1 is inside a real (non-dot) project directory under PROJECTS_DIR.
in_projects() { case "$1/" in "$PROJECTS_REAL"/.*) return 1 ;; "$PROJECTS_REAL"/?*) return 0 ;; esac; return 1; }

# Refuse to start if something is mounted below PROJECTS_DIR: bwrap binds recursively, so
# a mounted disk or share there would silently become writable for the agent.
check_no_nested_mounts() {
  local m
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    case "$m" in "$PROJECTS_REAL"/*) die "nested mount inside the projects dir: $m (unmount it first)" ;; esac
  done < <(findmnt -rn -o TARGET 2>/dev/null)
}

# Locate the GUI executable inside INSTALL_DIR/<kind> (works across updates).
gui_exe() { find "$INSTALL_DIR/$1" -maxdepth 2 -type f \( -name antigravity -o -name antigravity-ide \) -perm /111 -print -quit 2>/dev/null; }

# Build the bwrap command line into the array BW.   $1 = cli|gui   $2 = workdir   $3 = app|ide (gui only)
build_bwrap() {
  local mode="$1" workdir="$2" kind="${3:-}" d p v g sock wl
  BW=( bwrap
    --unshare-all --share-net          # new user/pid/ipc/uts/cgroup namespaces; network stays (the agent must reach Google)
    --die-with-parent                  # jail dies if this launcher dies
    --new-session                      # blocks terminal-injection (TIOCSTI) escapes
    --cap-drop ALL --hostname agy-jail
    --clearenv )

  # System: read-only. Merged-/usr distros expose /bin etc. as symlinks.
  for d in bin sbin lib lib64; do
    if [ -L "/$d" ]; then BW+=( --symlink "$(readlink "/$d")" "/$d" )
    elif [ -d "/$d" ]; then BW+=( --ro-bind "/$d" "/$d" ); fi
  done
  BW+=( --ro-bind /usr /usr --proc /proc --dev /dev
        --size "$TMP_SIZE_BYTES" --tmpfs /tmp --dir /var --tmpfs /var/tmp
        --dir "/run/user/$UID_NOW" --chmod 0700 "/run/user/$UID_NOW" )

  # Only the /etc entries needed for DNS, TLS, users, fonts and the dynamic linker.
  for p in hosts nsswitch.conf resolv.conf passwd group localtime os-release ssl pki ca-certificates \
           crypto-policies alternatives ld.so.cache ld.so.conf ld.so.conf.d gai.conf protocols services fonts; do
    [ -e "/etc/$p" ] && BW+=( --ro-bind "/etc/$p" "/etc/$p" )
  done

  # HOME. CLI: empty RAM disk, nothing persists except the two state dirs below.
  #       GUI: a persistent private home (Electron writes to many unpredictable paths).
  if [ "$mode" = gui ]; then BW+=( --bind "$JAIL_STATE/gui-home" "$HOME" )
  else                       BW+=( --size "$HOME_SIZE_BYTES" --tmpfs "$HOME" ); fi
  BW+=( --bind "$JAIL_STATE/gemini" "$HOME/.gemini"
        --bind "$JAIL_STATE/antigravity-config" "$HOME/.config/antigravity"
        --ro-bind "$JAIL_STATE/gitconfig" "$HOME/.gitconfig"
        --bind "$JAIL_STATE/run" /run/agy )

  # The ONE writable project area.
  BW+=( --bind "$PROJECTS_REAL" "$PROJECTS_REAL" )
  # Git hooks and git config can make git run commands on YOUR side later (hooks, core.fsmonitor,
  # core.sshCommand, aliases starting with !), so for existing repos they are read-only.
  # Commits/branches/checkouts still work; `git config`, `git remote add`, `push -u` fail inside.
  for g in "$PROJECTS_REAL"/*/.git/hooks; do [ -d "$g" ] && BW+=( --ro-bind "$g" "$g" ); done
  if [ "${PROTECT_GIT_CONFIG:-1}" = 1 ]; then
    for g in "$PROJECTS_REAL"/*/.git/config; do [ -f "$g" ] && BW+=( --ro-bind "$g" "$g" ); done
  fi

  # Programs (read-only) and the xdg-open shim.
  BW+=( --ro-bind "$INSTALL_DIR/shims" /opt/agy-shims )
  if [ "$mode" = cli ]; then BW+=( --ro-bind "$INSTALL_DIR/bin" /opt/agy )
  elif [ -n "$kind" ];  then BW+=( --ro-bind "$INSTALL_DIR/$kind" "/opt/agy-$kind" ); fi
  for p in "${EXTRA_RO[@]}"; do [ -e "$p" ] && BW+=( --ro-bind "$p" "$p" ); done

  if [ "$mode" = gui ]; then
    BW+=( --ro-bind-try /sys /sys --tmpfs /dev/shm )            # Chromium reads /sys for GPU/hardware info
    [ "$GUI_USE_GPU" = 1 ] && BW+=( --dev-bind-try /dev/dri /dev/dri )
    # Fonts you installed per-user (read-only, non-sensitive).
    BW+=( --ro-bind-try "$HOME/.local/share/fonts" "$HOME/.local/share/fonts" )
    # The ONLY socket that enters the jail: the Wayland display.
    wl="${WAYLAND_DISPLAY:-}"
    if [ -n "$wl" ]; then
      case "$wl" in /*) sock="$wl" ;; *) sock="${XDG_RUNTIME_DIR:-/run/user/$UID_NOW}/$wl" ;; esac
      [ -S "$sock" ] || die "Wayland socket not found: $sock"
      BW+=( --bind "$sock" "/run/user/$UID_NOW/$(basename "$sock")"
            --setenv WAYLAND_DISPLAY "$(basename "$sock")" --setenv XDG_SESSION_TYPE wayland )
    elif [ -z "${AGY_JAIL_SELFTEST:-}" ]; then die "GUI mode needs a Wayland session (WAYLAND_DISPLAY is not set)."; fi
    BW+=( --setenv ELECTRON_OZONE_PLATFORM_HINT auto )
    [ -n "${XDG_CURRENT_DESKTOP:-}" ] && BW+=( --setenv XDG_CURRENT_DESKTOP "$XDG_CURRENT_DESKTOP" )
  fi

  # Make the (RAM-backed) root read-only; the mounts above keep their own flags.
  BW+=( --remount-ro / )

  # Minimal environment.
  BW+=( --setenv HOME "$HOME" --setenv USER "${USER:-user}" --setenv LOGNAME "${USER:-user}"
        --setenv SHELL /bin/bash --setenv PATH /opt/agy-shims:/opt/agy:/usr/local/bin:/usr/bin:/bin
        --setenv BROWSER /opt/agy-shims/xdg-open
        --setenv TMPDIR /tmp --setenv XDG_RUNTIME_DIR "/run/user/$UID_NOW" )
  for v in TERM COLORTERM LANG LC_ALL LC_CTYPE TZ "${PASS_ENV[@]}"; do
    [ -n "${!v:-}" ] && BW+=( --setenv "$v" "${!v}")
  done
  [ -n "${GOMEMLIMIT_VALUE:-}" ] && [ "$mode" = cli ] && BW+=( --setenv GOMEMLIMIT "$GOMEMLIMIT_VALUE" )
  BW+=( --chdir "$workdir" )
}

need_project_cwd() {
  CWD_REAL="$(realpath -e -- "$PWD")"
  in_projects "$CWD_REAL" || {
    echo "agy-jail: refusing to start: $PWD is not inside a project under" >&2
    echo "          $PROJECTS_REAL" >&2
    echo "          Create one with:  agy-jail new <name>   then cd into it." >&2
    exit 1; }
}

# GUI start: validate folder arguments (must be inside a project), then exec the app.
run_gui() {
  local kind="$1" exe rel a args=() workdir
  shift
  [ -d "$INSTALL_DIR/$kind" ] || die "Antigravity $kind is not installed (re-run the setup script)."
  exe="$(gui_exe "$kind")"; [ -n "$exe" ] || die "No $kind executable found under $INSTALL_DIR/$kind"
  rel="${exe#"$INSTALL_DIR/$kind"}"
  for a in "$@"; do
    case "$a" in -*) ;; *) if [ -e "$a" ]; then in_projects "$(realpath -e -- "$a")" || die "refusing to open '$a': it is outside $PROJECTS_REAL"; fi ;; esac
  done
  workdir="$PROJECTS_REAL"; if in_projects "$(realpath -e -- "$PWD")"; then workdir="$(realpath -e -- "$PWD")"; fi
  check_no_nested_mounts
  build_bwrap gui "$workdir" "$kind"
  # --password-store=basic: no keyring in the jail, so tokens go to the jail's private files.
  args=( --password-store=basic --ozone-platform-hint=auto "--js-flags=--max-old-space-size=${GUI_V8_HEAP_MB}" )
  [ "$GUI_USE_GPU" = 1 ] || args+=( --disable-gpu )
  exec "${BW[@]}" "/opt/agy-$kind$rel" "${args[@]}" "${GUI_EXTRA_ARGS[@]}" "$@"
}

cmd="${1:-}"
case "$cmd" in
  new)
    name="${2:?usage: agy-jail new NAME}"
    case "$name" in */*|.*|"") die "NAME must be a simple folder name (no slash, no leading dot)" ;; esac
    mkdir -p "$PROJECTS_REAL/$name"
    [ -e "$PROJECTS_REAL/$name/README.md" ] || printf '# %s\n\nCreated for use with Antigravity inside agy-jail.\n' "$name" > "$PROJECTS_REAL/$name/README.md"
    echo "Created $PROJECTS_REAL/$name"
    echo "Next:  cd \"$PROJECTS_REAL/$name\" && agy-jail        (or: agy-jail ide \"$PROJECTS_REAL/$name\")"
    ;;
  ide) shift; run_gui ide "$@" ;;
  app) shift; run_gui app "$@" ;;
  shell)
    need_project_cwd; check_no_nested_mounts; build_bwrap cli "$CWD_REAL"
    exec "${BW[@]}" /bin/bash --norc --noprofile -i
    ;;
  print)
    need_project_cwd; build_bwrap cli "$CWD_REAL"; printf '%q ' "${BW[@]}" /opt/agy/agy; echo
    ;;
  open-url)
    f="$JAIL_STATE/run/last-url.txt"
    [ -s "$f" ] || die "no link has been requested by the jailed app"
    url="$(head -n1 "$f")"
    # Only plain https links, no whitespace/control characters, so a hostile app cannot make
    # you launch anything but a web page.
    re='^https://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+$'
    [[ "$url" =~ $re ]] || die "refusing to open a suspicious link: $(printf '%q' "$url")"
    echo "The jailed app wants to open:"; echo "  $url"
    read -r -p "Open it in your default browser? [y/N] " ans
    [ "$ans" = y ] && { xdg-open "$url" >/dev/null 2>&1 & disown; }
    ;;
  doctor)
    echo "kernel        : $(uname -r) ($(uname -m))"; echo "bwrap         : $(bwrap --version)"
    echo "user ns       : $(unshare -Ur true 2>&1 && echo ok || echo FAILED) (max: $(sysctl -n user.max_user_namespaces 2>/dev/null || echo ?))"
    echo "SELinux       : $(command -v getenforce >/dev/null && getenforce || echo n/a)"
    echo "session       : ${XDG_SESSION_TYPE:-?} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-none}"
    echo "projects dir  : $PROJECTS_REAL"; echo "state dir     : $JAIL_STATE"
    echo "CLI           : $("$INSTALL_DIR/bin/agy" --version 2>/dev/null | head -1)"
    for k in app ide; do echo "$k            : $(cat "$INSTALL_DIR/versions/$k" 2>/dev/null || echo 'not installed')"; done
    echo "GPU in jail   : $([ "$GUI_USE_GPU" = 1 ] && echo yes || echo 'no (software rendering)')"
    echo "SELinux denials (if something fails):  sudo ausearch -m avc -ts recent | grep -i bwrap"
    ;;
  audit)
    echo "Scanning $PROJECTS_REAL for things that could act on YOUR side later..."
    found=0
    for proj in "$PROJECTS_REAL"/*/; do
      for h in "$proj".git/hooks/*; do case "$h" in *.sample) ;; *) echo "REVIEW git hook:   $h"; found=1 ;; esac; done
      if [ -f "$proj.git/config" ] && grep -qE 'hooksPath|fsmonitor|sshCommand|editor|pager|!' "$proj.git/config"; then
        echo "REVIEW git config: ${proj}.git/config"; grep -nE 'hooksPath|fsmonitor|sshCommand|editor|pager|!' "$proj.git/config" | sed 's/^/    /'; found=1
      fi
      for f in .envrc .vscode/tasks.json .vscode/settings.json .vscode/launch.json .idea/workspace.xml .husky .pre-commit-config.yaml .devcontainer/devcontainer.json; do
        [ -e "$proj$f" ] && { echo "REVIEW auto-run:   $proj$f"; found=1; }
      done
    done
    # Symlinks leading outside PROJECTS_DIR: if YOU (or a host tool) write through one, a file
    # outside the jail changes. Inside the jail such a link cannot reach anything.
    while IFS= read -r l; do
      t="$(readlink -m -- "$l")"
      case "$t/" in "$PROJECTS_REAL"/*) ;; *) echo "REVIEW symlink leaves projects dir: $l -> $(readlink "$l")"; found=1 ;; esac
    done < <(find "$PROJECTS_REAL" -xdev -type l -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null)
    # Hard links: writing to one name changes every name of the same file.
    while IFS= read -r l; do echo "REVIEW hard-linked file: $l"; found=1
    done < <(find "$PROJECTS_REAL" -xdev -type f -links +1 -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | head -20)
    [ "$found" -eq 1 ] || echo "Nothing suspicious found."
    ;;
  selftest)
    mkdir -p "$PROJECTS_REAL/.agy-selftest"; probe="agy-jail-selftest-$$"
    canary="$HOME/.agy-canary-$$"; printf 'HOST\n' > "$canary"
    real_files=( "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.gitconfig" "$canary" )
    before="$(sha256sum "${real_files[@]}" 2>/dev/null || true)"
    rc=0; export AGY_JAIL_SELFTEST=1
    for m in cli gui; do
      echo "=== profile: $m"
      CWD_REAL="$PROJECTS_REAL/.agy-selftest"; build_bwrap "$m" "$CWD_REAL"
      set +e
      "${BW[@]}" /bin/bash -c '
        ok=0; uid=$(id -u)
        try_write() { if ( : > "$1" ) 2>/dev/null; then echo "  LEAK (writable): $1"; ok=1; else echo "  ok (blocked):    $1"; fi; }
        try_gone()  { if [ -e "$1" ]; then echo "  LEAK (visible):  $1"; ok=1; else echo "  ok (invisible):  $1"; fi; }
        echo "Writes that must FAIL:"
        for t in /usr/'"$probe"' /etc/'"$probe"' /var/'"$probe"' /opt/'"$probe"' /opt/agy-shims/'"$probe"' /home/'"$probe"' /run/'"$probe"'; do try_write "$t"; done
        echo "Real-home items that must be INVISIBLE:"
        for t in "$HOME/.ssh" "$HOME/.gnupg" "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.config/BraveSoftware" "$HOME/.mozilla" "$HOME/Documents" "$HOME/Downloads"; do try_gone "$t"; done
        echo "Sockets that must NOT exist (read-only mounts do not stop connecting to them):"
        for t in /run/user/$uid/bus /run/user/$uid/systemd /run/user/$uid/gnupg /run/user/$uid/keyring /run/dbus /var/run/docker.sock /run/docker.sock; do try_gone "$t"; done
        echo "Attempt to overwrite a real-home canary (must only hit the jail copy):"
        printf "PWNED\n" > "$HOME/'"$(basename "$canary")"'" 2>/dev/null; echo "  done"
        echo "Write that must SUCCEED:"
        if ( : > "$PWD/'"$probe"'" ) 2>/dev/null; then echo "  ok (writable):   $PWD"; rm -f "$PWD/'"$probe"'"; else echo "  BROKEN: cannot write inside the project"; ok=1; fi
        echo "Environment leak check:"
        if env | grep -qE "SSH_AUTH_SOCK|AWS_|TOKEN|SECRET|DBUS_SESSION|GPG_AGENT"; then echo "  LEAK: sensitive variable present"; ok=1; else echo "  ok: no sensitive variables"; fi
        echo "xdg-open shim parks links instead of launching anything:"
        xdg-open https://example.invalid/x 2>/dev/null; if [ "$(cat /run/agy/last-url.txt 2>/dev/null)" = "https://example.invalid/x" ]; then echo "  ok"; else echo "  BROKEN shim"; ok=1; fi
        echo "Info:"
        unshare -Ur true 2>/dev/null && echo "  nested user namespaces work (agy built-in sandbox / Chromium sandbox can start)" || echo "  nested namespaces unavailable (agy falls back to asking before commands)"
        getent hosts github.com >/dev/null 2>&1 && echo "  DNS works" || echo "  DNS lookup failed (is the network up?)"
        exit $ok
      '
      [ $? -eq 0 ] || rc=1
      set -e
    done
    rm -f "$JAIL_STATE/run/last-url.txt"; rmdir "$PROJECTS_REAL/.agy-selftest" 2>/dev/null || true
    after="$(sha256sum "${real_files[@]}" 2>/dev/null || true)"; rm -f "$canary"
    [ "$before" = "$after" ] && echo "Host check: real ~/.bashrc ~/.zshrc ~/.profile ~/.gitconfig and the canary are unchanged" || { echo "Host check: A REAL FILE CHANGED"; rc=1; }
    [ ! -e "$HOME/$probe" ] || { echo "Host check: probe file leaked to host"; rc=1; }
    [ "$rc" -eq 0 ] && echo "SELFTEST PASSED" || echo "SELFTEST FAILED"
    exit "$rc"
    ;;
  help|-h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' ;;
  *)
    need_project_cwd; check_no_nested_mounts; build_bwrap cli "$CWD_REAL"
    exec "${BW[@]}" /opt/agy/agy "$@"
    ;;
esac
LAUNCHER_EOF
chmod 755 "$AGY_LAUNCHER"

# --- KDE/Freedesktop menu entries (no MIME defaults on purpose: see Notes) ----------------
mkdir -p "$DESKTOP_DIR"
IDE_ICON="$(find "${AGY_INSTALL_DIR}/ide" -maxdepth 6 -name code.png -print -quit 2>/dev/null || true)"
write_desktop() {   # $1 kind  $2 name  $3 icon
  [ -d "${AGY_INSTALL_DIR}/$1" ] || return 0
  cat > "${DESKTOP_DIR}/agy-jail-$1.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$2 (jailed)
Comment=$2, confined to ${PROJECTS_DIR}
Exec=${AGY_LAUNCHER} $1 %F
Icon=${3:-applications-development}
Terminal=false
Categories=Development;IDE;
StartupNotify=true
StartupWMClass=${4:-Antigravity}
EOF
  chmod 644 "${DESKTOP_DIR}/agy-jail-$1.desktop"
}
write_desktop ide "Antigravity IDE" "$IDE_ICON" antigravity-ide
write_desktop app "Antigravity" "" Antigravity
update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
case "${DESKTOP,,}" in *kde*|*plasma*) command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true ;; esac

# --- BleachBit cleaner: logs/crashes/caches only (never login or history) ------------------
mkdir -p "$BLEACHBIT_CLEANER_DIR"
cat > "${BLEACHBIT_CLEANER_DIR}/agy_jail.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<cleaner id="agy_jail">
  <label>Antigravity (jail)</label>
  <description>Logs, crash reports and caches of the confined Antigravity CLI, IDE and app</description>
  <option id="logs">
    <label>Logs and crash reports</label>
    <description>Delete log files and crash dumps (keeps login, settings and conversations)</description>
    <action command="delete" search="walk.files" path="${AGY_STATE_DIR}/gemini/antigravity-cli/log"/>
    <action command="delete" search="walk.files" path="${AGY_STATE_DIR}/gemini/antigravity-cli/crashes"/>
    <action command="delete" search="walk.all" path="${AGY_STATE_DIR}/gui-home/.config/Antigravity IDE/logs"/>
    <action command="delete" search="walk.all" path="${AGY_STATE_DIR}/gui-home/.config/Antigravity/logs"/>
    <action command="delete" search="walk.all" path="${AGY_STATE_DIR}/gui-home/.config/Antigravity/Crashpad"/>
  </option>
  <option id="cache">
    <label>Cache and GPU shaders</label>
    <description>Delete cached data without touching login sessions or settings</description>
    <action command="delete" search="walk.all" path="${AGY_STATE_DIR}/gemini/antigravity-cli/cache"/>
    <action command="delete" search="walk.all" path="${AGY_STATE_DIR}/gui-home/.cache"/>
    <action command="delete" search="walk.all" path="${AGY_STATE_DIR}/gui-home/.config/Antigravity IDE/Cache"/>
    <action command="delete" search="walk.all" path="${AGY_STATE_DIR}/gui-home/.config/Antigravity IDE/CachedData"/>
    <action command="delete" search="walk.all" path="${AGY_STATE_DIR}/gui-home/.config/Antigravity IDE/GPUCache"/>
    <action command="delete" search="walk.all" path="${AGY_STATE_DIR}/gui-home/.config/Antigravity/Cache"/>
    <action command="delete" search="walk.all" path="${AGY_STATE_DIR}/gui-home/.config/Antigravity/GPUCache"/>
  </option>
</cleaner>
EOF

# --- weekly auto-update (systemd user timer, sandboxed) -------------------------------------
mkdir -p "$SYSTEMD_USER_DIR"
cat > "${SYSTEMD_USER_DIR}/agy-jail-update.service" <<EOF
[Unit]
Description=Update the Antigravity binaries used by agy-jail
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bash ${SCRIPT_PATH} --update --real-user ${REAL_USER} --projects-dir ${PROJECTS_DIR}
# Sandbox the updater itself: it may only write its own install, data and log dirs.
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=${AGY_INSTALL_DIR} ${SCRIPT_DATA}
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
LockPersonality=true
RestrictNamespaces=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
SystemCallArchitectures=native
EOF
cat > "${SYSTEMD_USER_DIR}/agy-jail-update.timer" <<'EOF'
[Unit]
Description=Weekly check for new Antigravity releases

[Timer]
OnCalendar=weekly
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
if systemctl --user daemon-reload 2>/dev/null; then
  systemctl --user enable --now agy-jail-update.timer || log_warn "Could not enable the update timer."
else
  log_warn "No systemd user session here; enable later: systemctl --user enable --now agy-jail-update.timer"
fi

log_success "Setup finished."
verify_setup || log_warn "Some verification checks failed; read the log: ${LOG_FILE}"

cat <<EOF

Next steps:
  agy-jail new Play01
  cd "${PROJECTS_DIR}/Play01" && agy-jail          # terminal agent
  agy-jail ide "${PROJECTS_DIR}/Play01"            # IDE (or the 'Antigravity IDE (jailed)' menu entry)
First launch: sign in with your Google account. If no browser opens, run:  agy-jail open-url
In the IDE/app set  Settings > General > Global Permissions > Permission Preset = Default  (never Turbo).
EOF

##################################################################################
# Notes
##################################################################################
# * Threat model. Protects against: the agent (or a prompt-injected web page / README it
#   read) modifying files outside PROJECTS_DIR, reading ~/.ssh, ~/.gnupg, browser profiles,
#   shell history or other machines' credentials, and reaching the desktop's D-Bus/systemd.
#   Does NOT protect against: the agent destroying PROJECTS_DIR itself (use git + backups),
#   or sending project contents to Google or any host (the network is open; the agent must
#   reach Google). For egress control add OpenSnitch rules for the binaries in
#   ${AGY_INSTALL_DIR} (bin/agy, ide/*, app/*), which are fixed, checksummed paths.
# * Why NOT a read-only bind of "/" (several community scripts do this, plus binding all of
#   $XDG_RUNTIME_DIR): read-only mounts do not stop connect() to a unix socket, so the session
#   D-Bus and systemd --user stay reachable, and either can start arbitrary commands OUTSIDE
#   the jail. Verified with a socket test. Here nothing of /run/user is mounted except the
#   Wayland socket (GUI mode only), and $HOME is replaced, not merely masked.
# * Writable on the host: PROJECTS_DIR only. Login/settings/history live in
#   PROJECTS_DIR/.agy-state (700, excluded from Syncthing via .stignore). Because every
#   project's agent can read that directory, tokens are exposed to all of them: use one
#   Google account that you are comfortable giving to the agent.
# * Poisoned-project escape. Files the agent writes can run on YOUR side later (git hooks,
#   git config such as core.fsmonitor, .envrc, .vscode/tasks.json, package.json scripts,
#   Makefiles). .git/hooks and .git/config of existing repos are read-only in the jail
#   (PROTECT_GIT_CONFIG=0 to allow `git remote add` inside), the CLI's settings.json makes
#   writes to the other vectors ask first, and `agy-jail audit` lists them plus symlinks that
#   leave the projects dir and hard-linked files. Open projects on the host in VSCodium /
#   PyCharm in Restricted/Safe mode and review before running anything.
# * No D-Bus => no keyring, no portals, no browser launch. The CLI falls back to a file-based
#   secret store (observed in its log); the GUI uses --password-store=basic; links are parked
#   by the xdg-open shim and opened by you with `agy-jail open-url` (https only, you confirm).
#   Not available in the jail as a consequence: voice mode (no audio sockets) and the browser
#   subagent (no Chrome in the jail's /usr).
# * The CLI's `remote-control` feature can expose a session to a browser via Google; the jail
#   still confines it, but do not enable it casually.
# * GUI uncertainties (this could not be tested against the real apps): Chromium's own sandbox
#   may not nest inside the jail (add --no-sandbox via GUI_EXTRA_ARGS; the jail is the wall),
#   the IDE settings directory name is from community guides, and the 2.x tarball URL discovery
#   scrapes Google's download page (fallback: --app-source/--ide-source with a file or URL).
#   Google publishes no checksums for these tarballs: integrity = HTTPS + ClamAV only.
# * The old RPM repo (us-central1-yum.pkg.dev/.../antigravity-rpm) is NOT used: it only holds the
#   legacy 1.x IDE and is configured with gpgcheck=0 (no signature verification).
# * Environment is cleared; resource profile: RAM_PROFILE sizes the tmpfs mounts and the Go heap
#   limit, RAM sizes the Electron V8 heap, GPU_TIER low disables GPU rendering in the jail.
# * DNS/NextDNS: the jail shares the host network, so lookups go through systemd-resolved to
#   your NextDNS profile with the host's device ID. These apps have no per-app DNS setting, so
#   no app-level device ID is configured.
# * MIME: no file-type defaults are registered on purpose. The jailed IDE can only open files
#   inside PROJECTS_DIR, so making it the default editor for text files would just break links.
# * Ideas taken from the other scripts: Wayland-socket-only GUI jail, state inside the
#   workspace, hard-link and nested-mount checks, Python tarfile "data" filter, --password-store,
#   canary self-test, doctor/print commands, KDE menu entries, global rules file, deny rules in
#   settings.json, Electron flags by RAM/GPU, BleachBit paths, git identity copy, .stignore.
# * Logging: a re-exec under `script` keeps terminal colors (plain `tee` makes stdout a pipe).
# * Re-running the full setup backs up then wipes everything (fresh start): sign in again.
#   Updates use --update, which keeps your login.
#
##################################################################################
# Useful Links
##################################################################################
# https://antigravity.google/docs/sandbox                              Terminal sandbox (scope and limits)
# https://antigravity.google/docs/permissions                          Permission engine, CLI settings.json rules
# https://antigravity.google/docs/rules                                AGENTS.md / GEMINI.md rule files
# https://antigravity.google/download                                  Official 2.x tarballs
# https://github.com/google-antigravity/antigravity-cli/issues/36      Sandbox bypass with --dangerously-skip-permissions
# https://github.com/google-antigravity/antigravity-cli/releases       Official CLI release assets
# https://linuxcapable.com/how-to-install-google-antigravity-on-fedora-linux/   Fedora install paths, legacy RPM note
# https://github.com/containers/bubblewrap                             bubblewrap
# https://man.archlinux.org/man/bwrap.1                                bwrap options
# https://wiki.archlinux.org/title/Bubblewrap                          Arch Wiki: bubblewrap
# https://docs.flatpak.org/en/latest/sandbox-permissions.html          Flatpak: same approach, filtered D-Bus
# https://www.freedesktop.org/software/systemd/man/systemd.exec.html   systemd sandboxing options
# https://docs.python.org/3/library/tarfile.html#extraction-filters    tarfile "data" filter
#
##################################################################################
# Troubleshooting/Debugging/Testing/Commands
##################################################################################
# agy-jail selftest                  re-run the confinement proof (CLI and GUI profiles)
# agy-jail doctor                    kernel, bwrap, user namespaces, SELinux, versions
# agy-jail shell                     see exactly what the agent sees (ls -la ~; ls /run)
# agy-jail audit                     list auto-run files, escaping symlinks, hard links
# agy-jail open-url                  open the link the jailed app wanted to open (sign-in)
# bash antigravity.sh --verify-setup full check of the install
# bash antigravity.sh --update       refresh binaries now (the timer does it weekly)
# systemctl --user list-timers agy-jail-update.timer ; journalctl --user -u agy-jail-update
# "refusing to start"                cd into ${PROJECTS_DIR}/<project> first
# "nested mount inside projects dir" something is mounted under PROJECTS_DIR; unmount it
# "No permissions to create new namespace"  sysctl user.max_user_namespaces must be > 0;
#                                    Ubuntu 24.04+ AppArmor may restrict userns for bwrap
# bwrap: loopback ... Permission denied     SELinux: sudo ausearch -m avc -ts recent | grep -i bwrap
# IDE/app: "No usable sandbox!"      set GUI_EXTRA_ARGS=( --no-sandbox ) in ${AGY_CONF_FILE}
# IDE/app: black or flickering window set GUI_USE_GPU=0 in ${AGY_CONF_FILE}
# Tool missing inside the jail       it only sees /usr; add paths to EXTRA_RO in ${AGY_CONF_FILE}
# git push fails inside the jail     expected (no keys): push from your normal terminal
# Agent state/logs                   ${AGY_STATE_DIR}/gemini/antigravity-cli/log/
# Uninstall                          systemctl --user disable --now agy-jail-update.timer;
#                                    rm -rf ${AGY_INSTALL_DIR} ${AGY_LAUNCHER} ${AGY_CONF_DIR} ${AGY_STATE_DIR} \
#                                           ${DESKTOP_DIR}/agy-jail-*.desktop