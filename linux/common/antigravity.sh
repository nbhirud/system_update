#!/usr/bin/env bash
##################################################################################
# Overview and Usage
##################################################################################
# Installs Google's Antigravity CLI (binary name: agy) and runs it ONLY inside a
# bubblewrap (bwrap) jail, so the agent can write nothing on the machine except
# inside PROJECTS_DIR. Not ~/.bashrc, not ~/.zshrc, not ~/.ssh, nothing else.
#
# Why a jail and not Antigravity's own settings? Antigravity's built-in controls
# (terminal sandbox, "workspace only" file permissions) live INSIDE the agent
# process and are policy, not an OS boundary: the model itself can ask to bypass
# the sandbox, and with --dangerously-skip-permissions that request is auto-approved
# (google-antigravity/antigravity-cli issue #36). A bubblewrap jail is created by
# the kernel BEFORE agy starts, so nothing the agent does can undo it.
#
# What this script does:
#   1. Downloads the official agy release from GitHub, verifies its SHA-256 digest,
#      scans it with ClamAV, installs it WITHOUT touching ~/.bashrc / ~/.profile
#      (the official install.sh edits them; this script does not).
#   2. Creates a private persistent state area for the jail (login, settings, history).
#   3. Writes the launcher `agy-jail` (the ONLY way you should start the agent).
#   4. Writes telemetry opt-out settings, a BleachBit cleaner, a weekly auto-update
#      systemd user timer, and runs a self-test proving the confinement works.
#
# Sample calls (assuming the caller uses the same variable names):
#   (a) all options:
#       bash antigravity.sh --real-user "$REAL_USER" --filename-timestamp "$FILENAME_TIMESTAMP" \
#            --projects-dir "$CODEPROJECTS_DIR/nbAntigravity" --version 1.5.9 --sha256 <64-hex>
#   (b) mandatory only (nothing is mandatory; every option has a sensible default):
#       bash antigravity.sh
#   (c) verification only:
#       bash antigravity.sh --verify-setup
#   (d) refresh the agy binary only (used by the systemd timer; keeps login/settings):
#       bash antigravity.sh --update
#
# After setup, daily use:
#   agy-jail new Play01        # create ${PROJECTS_DIR}/Play01
#   cd "${PROJECTS_DIR}/Play01" && agy-jail     # start the agent, confined
#   agy-jail selftest | audit | shell | help

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

# Per-package directories (package = antigravity).
ANTIGRAVITY_DOWNLOADS_DIR_BASE="${SCRIPT_DATA_DOWNLOADS}/antigravity"
ANTIGRAVITY_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/antigravity"
ANTIGRAVITY_LOG_DIR_BASE="${SCRIPT_DATA_LOGS}/antigravity"
ANTIGRAVITY_CURRENT_DOWNLOADS_DIR="${ANTIGRAVITY_DOWNLOADS_DIR_BASE}/antigravity_${FILENAME_TIMESTAMP}"
ANTIGRAVITY_CURRENT_BACKUP_DIR="${ANTIGRAVITY_BACKUP_DIR_BASE}/antigravity_${FILENAME_TIMESTAMP}"
ANTIGRAVITY_CURRENT_LOG_DIR="${ANTIGRAVITY_LOG_DIR_BASE}/antigravity_${FILENAME_TIMESTAMP}"

# The one directory the agent may write to. Overridable with --projects-dir.
PROJECTS_DIR="${PROJECTS_DIR:-${CODEPROJECTS_DIR}/nbAntigravity}"

# Where things get installed (all inside the user's home, no root needed).
AGY_REPO="google-antigravity/antigravity-cli"            # official release repo
AGY_INSTALL_DIR="${HOME_DIR}/.local/opt/agy-jail"        # holds bin/agy (read-only inside the jail)
AGY_LAUNCHER="${HOME_DIR}/.local/bin/agy-jail"           # the confined launcher
AGY_CONF_DIR="${HOME_DIR}/.config/agy-jail"              # launcher config (sourced by the launcher)
AGY_CONF_FILE="${AGY_CONF_DIR}/agy-jail.conf"
AGY_STATE_DIR="${SCRIPT_DATA}/antigravity/state"         # jail's persistent state: login, settings, history
SYSTEMD_USER_DIR="${HOME_DIR}/.config/systemd/user"
BLEACHBIT_CLEANER_DIR="${HOME_DIR}/.config/bleachbit/cleaners"

ORIG_ARGS=("$@")                                   # original command line, used when re-executing
SCRIPT_PATH="$(realpath -e -- "$0")"               # absolute path of this script (used by the systemd unit)

# Optional overrides via named options.
OPT_VERSION=""      # --version: release tag; default = latest
OPT_SHA256=""       # --sha256 : expected digest if it cannot be auto-detected
MODE="setup"        # setup | verify | update

##################################################################################
# Named Options processing
##################################################################################
usage() { sed -n '/^# Overview and Usage/,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' | sed '1d'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --real-user)          REAL_USER="$2"; shift 2 ;;
    --filename-timestamp) FILENAME_TIMESTAMP="$2"; shift 2 ;;
    --projects-dir)       PROJECTS_DIR="$2"; shift 2 ;;
    --version)            OPT_VERSION="$2"; shift 2 ;;
    --sha256)             OPT_SHA256="$2"; shift 2 ;;
    --verify-setup)       MODE="verify"; shift ;;
    --update)             MODE="update"; shift ;;
    -h|--help)            usage; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

# Options may have changed REAL_USER / FILENAME_TIMESTAMP / PROJECTS_DIR, so
# recompute every variable derived from them (single place, no drift).
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update"
COMMON_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/common"
GETTER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commong"
HELPER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commonh"
SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"; SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"; SCRIPT_DATA_LOGS="${SCRIPT_DATA}/logs"
ANTIGRAVITY_CURRENT_DOWNLOADS_DIR="${SCRIPT_DATA_DOWNLOADS}/antigravity/antigravity_${FILENAME_TIMESTAMP}"
ANTIGRAVITY_CURRENT_BACKUP_DIR="${SCRIPT_DATA_BACKUPS}/antigravity/antigravity_${FILENAME_TIMESTAMP}"
ANTIGRAVITY_CURRENT_LOG_DIR="${SCRIPT_DATA_LOGS}/antigravity/antigravity_${FILENAME_TIMESTAMP}"
AGY_INSTALL_DIR="${HOME_DIR}/.local/opt/agy-jail"
AGY_LAUNCHER="${HOME_DIR}/.local/bin/agy-jail"
AGY_CONF_DIR="${HOME_DIR}/.config/agy-jail"; AGY_CONF_FILE="${AGY_CONF_DIR}/agy-jail.conf"
AGY_STATE_DIR="${SCRIPT_DATA}/antigravity/state"
SYSTEMD_USER_DIR="${HOME_DIR}/.config/systemd/user"
BLEACHBIT_CLEANER_DIR="${HOME_DIR}/.config/bleachbit/cleaners"

##################################################################################
# Helpers
##################################################################################
# Reusable helpers live in HELPER_DIR (see header of each file).
for h in helper_logging.sh helper_backup.sh helper_download.sh helper_github.sh helper_run_as_user.sh; do
  [ -r "${HELPER_DIR}/${h}" ] || { echo "Missing helper ${HELPER_DIR}/${h}" >&2; exit 1; }
  # shellcheck disable=SC1090
  . "${HELPER_DIR}/${h}"
done

# If started with sudo, re-run as the real user: everything installed here is
# per-user and must never be root-owned (a root-owned file inside a user-writable
# tree is a classic privilege-escalation trap).
# Exported so that every re-exec (sudo -> user, script logging) shares one timestamp/user.
export REAL_USER FILENAME_TIMESTAMP
ensure_real_user "${ORIG_ARGS[@]}"

# Colored terminal output AND a log file: when stdout is a terminal, re-run the
# whole script under util-linux `script`, which gives the child a real pty (so
# colors survive) while copying everything to the log. When called from another
# script or systemd (no tty) the caller is responsible for capturing output.
mkdir -p "$ANTIGRAVITY_CURRENT_LOG_DIR"
LOG_FILE="${ANTIGRAVITY_CURRENT_LOG_DIR}/antigravity_${MODE}.log"
if [ -t 1 ] && [ -z "${ANTIGRAVITY_LOGGING:-}" ] && command -v script >/dev/null 2>&1; then
  export ANTIGRAVITY_LOGGING=1
  exec script -qefc "$(printf '%q ' "$SCRIPT_PATH" "${ORIG_ARGS[@]}")" "$LOG_FILE"
fi

[ "$(id -u)" -ne 0 ] || log_die "Run as a normal user (this installs per-user files)."

# Reads one getter from GETTER_DIR; prints the result; falls back to $2 if missing.
get() { if [ -r "${GETTER_DIR}/$1.sh" ]; then sh "${GETTER_DIR}/$1.sh" 2>/dev/null || echo "${2:-}"; else echo "${2:-}"; fi; }

# Detect the release asset for this CPU. glibc builds (not *_musl) because
# Fedora and every mainstream desktop distro is glibc.
detect_asset() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "agy_cli_linux_x64.tar.gz" ;;
    aarch64|arm64) echo "agy_cli_linux_arm64.tar.gz" ;;
    *) log_die "Unsupported CPU architecture: $(uname -m)" ;;
  esac
}

# Prints the SHA-256 GitHub shows for a release asset. The release has no
# .sha256 file, but GitHub publishes a digest per asset on the release page.
# Scraping the HTML avoids the REST API's tight anonymous rate limit.
github_asset_digest() {
  local tag="$1" asset="$2"
  curl -fsSL --proto '=https' --tlsv1.2 --retry 3 \
    "https://github.com/${AGY_REPO}/releases/expanded_assets/${tag}" \
    | tr -d '\n' | grep -oE "digest for ${asset}\"[^>]*value=\"sha256:[0-9a-f]{64}" \
    | grep -oE '[0-9a-f]{64}$' | head -1 || true
}

# Download + verify + scan + install the agy binary into AGY_INSTALL_DIR/bin.
# Atomic: the new binary is moved over the old one only after every check passed.
install_agy_binary() {
  local tag asset url dest expected actual tmpdir
  tag="${OPT_VERSION:-$(github_latest_tag "$AGY_REPO")}"
  [ -n "$tag" ] || log_die "Could not determine the latest release tag."
  asset="$(detect_asset)"
  url="https://github.com/${AGY_REPO}/releases/download/${tag}/${asset}"
  mkdir -p "$ANTIGRAVITY_CURRENT_DOWNLOADS_DIR"; chmod 700 "$ANTIGRAVITY_CURRENT_DOWNLOADS_DIR"
  dest="${ANTIGRAVITY_CURRENT_DOWNLOADS_DIR}/${asset}"
  log_info "Downloading ${asset} (${tag})"
  download_file "$url" "$dest"

  expected="${OPT_SHA256:-$(github_asset_digest "$tag" "$asset")}"
  [ -n "$expected" ] || log_die "No SHA-256 digest found on the release page. Re-run with --sha256 <hex>."
  actual="$(sha256sum "$dest" | cut -d' ' -f1)"
  [ "$expected" = "$actual" ] || log_die "SHA-256 mismatch! expected ${expected}, got ${actual}. Download deleted."
  log_success "SHA-256 verified: ${actual}"

  # Explicit scan even though the downloads dir may be on-access scanned
  # (in case that service is down). clamscan exit codes: 0 clean, 1 infected, 2 error.
  if command -v clamscan >/dev/null 2>&1; then
    set +e; clamscan --no-summary "$dest"; local rc=$?; set -e
    [ "$rc" -ne 1 ] || { rm -f "$dest"; log_die "ClamAV flagged the download as infected."; }
    [ "$rc" -eq 0 ] || log_warn "ClamAV scan returned status ${rc} (scanner error); continuing on checksum alone."
  else
    log_warn "clamscan not installed; skipped malware scan (checksum still verified)."
  fi

  tmpdir="$(mktemp -d "${ANTIGRAVITY_CURRENT_DOWNLOADS_DIR}/extract.XXXXXX")"
  tar -xzf "$dest" -C "$tmpdir"
  [ -f "${tmpdir}/antigravity" ] || log_die "Tarball layout changed: no 'antigravity' binary inside."
  chmod 755 "${tmpdir}/antigravity"
  "${tmpdir}/antigravity" --version >/dev/null 2>&1 || log_die "New binary does not run on this system."
  mkdir -p "${AGY_INSTALL_DIR}/bin"
  # The raw binary is deliberately named agy (what the jail executes) and lives
  # off $PATH, so typing `agy` can never start an UNCONFINED agent by accident.
  mv -f "${tmpdir}/antigravity" "${AGY_INSTALL_DIR}/bin/agy.new"
  mv -f "${AGY_INSTALL_DIR}/bin/agy.new" "${AGY_INSTALL_DIR}/bin/agy"
  rm -rf "$tmpdir"
  log_success "Installed agy $("${AGY_INSTALL_DIR}/bin/agy" --version 2>/dev/null | head -1)"
}

# --update: only refresh the binary when a newer release exists.
update_only() {
  local latest current
  latest="${OPT_VERSION:-$(github_latest_tag "$AGY_REPO")}"
  current="$("${AGY_INSTALL_DIR}/bin/agy" --version 2>/dev/null | head -1 || true)"
  if [ "$latest" = "$current" ]; then log_info "agy ${current} is already the latest."; return 0; fi
  log_info "Updating agy ${current:-none} -> ${latest}"
  install_agy_binary
}

##################################################################################
# Inferred variables
##################################################################################
DISTRO="$(get get_distro_name unknown)"
RAM_PROFILE="$(get get_ram_profile mid)"

# RAM-aware sizing. /tmp and the jail's home are RAM-backed (tmpfs); the Go
# runtime inside agy gets a soft memory limit on small machines so the agent
# cannot starve the desktop. Big machines get roomy scratch space.
case "$RAM_PROFILE" in
  low)  TMP_SIZE_MB=256;  HOME_SIZE_MB=128; GOMEMLIMIT_VALUE="900MiB" ;;
  high) TMP_SIZE_MB=4096; HOME_SIZE_MB=512; GOMEMLIMIT_VALUE="" ;;
  *)    TMP_SIZE_MB=1024; HOME_SIZE_MB=256; GOMEMLIMIT_VALUE="" ;;
esac

if [ "$MODE" = update ]; then update_only; exit 0; fi

##################################################################################
# Backup
##################################################################################
# Back up everything this script will touch, plus places where an older manual
# setup (the official install.sh, the Antigravity desktop app) may have written.
do_backup() {
  log_header "Backing up existing files to ${ANTIGRAVITY_CURRENT_BACKUP_DIR}"
  mkdir -p "$ANTIGRAVITY_CURRENT_BACKUP_DIR"; chmod 700 "$ANTIGRAVITY_CURRENT_BACKUP_DIR"
  local p n=0
  for p in "$AGY_INSTALL_DIR" "$AGY_LAUNCHER" "$AGY_CONF_DIR" "$AGY_STATE_DIR" \
           "${SYSTEMD_USER_DIR}/agy-jail-update.service" "${SYSTEMD_USER_DIR}/agy-jail-update.timer" \
           "${BLEACHBIT_CLEANER_DIR}/agy_jail.xml" \
           "${HOME_DIR}/.local/bin/agy" "${HOME_DIR}/.gemini" "${HOME_DIR}/.config/antigravity" \
           "${HOME_DIR}/.bashrc" "${HOME_DIR}/.profile" "${HOME_DIR}/.zshrc"; do
    if [ -e "$p" ] || [ -L "$p" ]; then
      n=$((n+1)); backup_path "$p" "$ANTIGRAVITY_CURRENT_BACKUP_DIR" "item${n}_$(basename "$p")"
    fi
  done
  # Record what each backup item was (names above are numbered).
  log_info "Backed up ${n} item(s)."
}

##################################################################################
# Reset
##################################################################################
# Fresh start: remove only what THIS script owns (never ~/.gemini, rc files, etc.).
do_reset() {
  log_header "Removing previous agy-jail setup (backed up above)"
  systemctl --user disable --now agy-jail-update.timer >/dev/null 2>&1 || true
  rm -rf "$AGY_INSTALL_DIR" "$AGY_LAUNCHER" "$AGY_CONF_DIR" "$AGY_STATE_DIR" \
         "${SYSTEMD_USER_DIR}/agy-jail-update.service" "${SYSTEMD_USER_DIR}/agy-jail-update.timer" \
         "${BLEACHBIT_CLEANER_DIR}/agy_jail.xml"
}

##################################################################################
# Security
##################################################################################
# Nothing needs firewalld/SELinux changes: bwrap runs as the user, the jail shares
# the host network, and SELinux treats it like any other user process.
# Optional: OpenSnitch can allow-list ${AGY_INSTALL_DIR}/bin/agy (see Notes).

##################################################################################
# Verification
##################################################################################
PASS=0; FAIL=0
check() { # check "description" command...
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then log_success "$d"; PASS=$((PASS+1)); else log_error "FAILED: $d"; FAIL=$((FAIL+1)); fi
}
verify_setup() {
  log_header "Verification"
  check "bubblewrap installed"                         command -v bwrap
  check "agy binary present and runs"                  "${AGY_INSTALL_DIR}/bin/agy" --version
  check "launcher installed and executable"            test -x "$AGY_LAUNCHER"
  check "launcher config present"                      test -r "$AGY_CONF_FILE"
  check "projects dir exists"                          test -d "$PROJECTS_DIR"
  check "state dir is private (700)"                   test "$(stat -c %a "$AGY_STATE_DIR")" = 700
  check "settings.json is valid JSON"                  python3 -m json.tool "${AGY_STATE_DIR}/gemini/antigravity-cli/settings.json"
  check "unprivileged user namespaces work"            unshare -Ur true
  check "BleachBit cleaner is valid XML"               python3 -c "import xml.dom.minidom,sys;xml.dom.minidom.parse(sys.argv[1])" "${BLEACHBIT_CLEANER_DIR}/agy_jail.xml"
  check "auto-update timer enabled"                    systemctl --user is-enabled agy-jail-update.timer
  case ":$PATH:" in *":${HOME_DIR}/.local/bin:"*) log_success "~/.local/bin is on PATH" ;; *) log_warn "~/.local/bin is not on PATH; use the full path ${AGY_LAUNCHER}" ;; esac
  [ -e "${HOME_DIR}/.local/bin/agy" ] && log_warn "An UNCONFINED ${HOME_DIR}/.local/bin/agy exists (official installer). Never run it; use agy-jail."
  command -v getenforce >/dev/null 2>&1 && log_info "SELinux: $(getenforce)"
  log_info "Running the confinement self-test..."
  if "$AGY_LAUNCHER" selftest; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
  log_info "Verification: ${PASS} passed, ${FAIL} failed."
  [ "$FAIL" -eq 0 ]
}
if [ "$MODE" = verify ]; then verify_setup; exit $?; fi

##################################################################################
# main setup
##################################################################################
log_header "Antigravity CLI jail setup (user: ${REAL_USER}, RAM profile: ${RAM_PROFILE})"

# --- prerequisites ---------------------------------------------------------
for t in curl tar sha256sum realpath python3; do
  command -v "$t" >/dev/null 2>&1 || log_die "Required tool missing: $t"
done
if ! command -v bwrap >/dev/null 2>&1; then
  # Flatpak depends on bubblewrap, so on Fedora Workstation it is normally already there.
  if [ "$DISTRO" = fedora ]; then
    log_info "Installing bubblewrap (needs sudo)"; sudo dnf install -y bubblewrap
  else
    log_die "bubblewrap (bwrap) is not installed; install it with your package manager."
  fi
fi
unshare -Ur true 2>/dev/null || log_die "Unprivileged user namespaces are disabled (kernel.unprivileged_userns_clone / user.max_user_namespaces); bwrap cannot work."

do_backup
do_reset

# --- projects dir + jail state --------------------------------------------
mkdir -p "$PROJECTS_DIR"; chmod 700 "$PROJECTS_DIR"
mkdir -p "$AGY_STATE_DIR"/{gemini/antigravity-cli,antigravity-config}
chmod 700 "$AGY_STATE_DIR" "$AGY_STATE_DIR"/{gemini,antigravity-config}

# --- binary -----------------------------------------------------------------
install_agy_binary

# --- settings: telemetry off (conversation history stays local) -------------
# Keys per community-documented settings; Antigravity "sparse-persists" and may
# rewrite the file, and Google also keeps an account-level toggle (/config in the
# TUI). Check it after first login. Permission prompts are deliberately left at
# their defaults: the jail is the safety net, the prompts are your second layer.
cat > "${AGY_STATE_DIR}/gemini/antigravity-cli/settings.json" <<'EOF'
{
  "enableTelemetry": false,
  "showFeedbackSurvey": false
}
EOF
chmod 600 "${AGY_STATE_DIR}/gemini/antigravity-cli/settings.json"

# --- jail's git config (read-only inside the jail) --------------------------
cat > "${AGY_STATE_DIR}/gitconfig" <<'EOF'
# Git configuration used INSIDE the agy-jail only (your real ~/.gitconfig is
# invisible there). Edit this file on the host to give the agent a commit identity:
#   [user]
#       name  = Agent
#       email = agent@localhost
[init]
    defaultBranch = main
[safe]
    directory = *
EOF
chmod 644 "${AGY_STATE_DIR}/gitconfig"

# --- launcher config --------------------------------------------------------
mkdir -p "$AGY_CONF_DIR"; chmod 700 "$AGY_CONF_DIR"
cat > "$AGY_CONF_FILE" <<EOF
# agy-jail configuration (sourced by the launcher; rewritten by the setup script).
# The agent may write ONLY inside PROJECTS_DIR (plus the private state dirs below).
PROJECTS_DIR="${PROJECTS_DIR}"
JAIL_STATE="${AGY_STATE_DIR}"
REAL_BIN_DIR="${AGY_INSTALL_DIR}/bin"
TMP_SIZE_BYTES=$((TMP_SIZE_MB * 1024 * 1024))     # RAM-backed /tmp inside the jail
HOME_SIZE_BYTES=$((HOME_SIZE_MB * 1024 * 1024))   # RAM-backed throwaway \$HOME inside the jail
GOMEMLIMIT_VALUE="${GOMEMLIMIT_VALUE}"            # soft Go heap limit (set on low-RAM machines)
# 1 = make each project's .git/config read-only inside the jail (recommended, see Notes).
PROTECT_GIT_CONFIG=1
# Extra host paths the agent may READ (e.g. a Rust toolchain or Node install):
#   EXTRA_RO=( "\$HOME/.cargo" "\$HOME/.rustup" )
EXTRA_RO=()
# Environment variables to pass in (the jail starts with an EMPTY environment so
# SSH_AUTH_SOCK, AWS_*, tokens etc. never leak). Example: PASS_ENV=( GEMINI_API_KEY )
PASS_ENV=()
EOF
chmod 600 "$AGY_CONF_FILE"

# --- the launcher itself ----------------------------------------------------
mkdir -p "$(dirname "$AGY_LAUNCHER")"
cat > "$AGY_LAUNCHER" <<'LAUNCHER_EOF'
#!/usr/bin/env bash
# agy-jail: run Google Antigravity CLI inside a bubblewrap jail.
# The agent can WRITE only inside PROJECTS_DIR (and its own private login/history
# state). Everything else is invisible (your real home) or read-only (system).
#   agy-jail [agy args]     start the agent in the current project (cwd must be inside PROJECTS_DIR)
#   agy-jail new NAME       create PROJECTS_DIR/NAME and print the next steps
#   agy-jail shell          jailed bash, to see exactly what the agent sees
#   agy-jail selftest       prove the confinement works
#   agy-jail audit          list project files that could run code on YOUR side later
set -euo pipefail
shopt -s nullglob

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/agy-jail/agy-jail.conf"
[ -r "$CONF" ] || { echo "agy-jail: missing $CONF (re-run the setup script)" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONF"
[ "$(id -u)" -ne 0 ] || { echo "agy-jail: do not run as root" >&2; exit 1; }
command -v bwrap >/dev/null || { echo "agy-jail: bubblewrap missing (sudo dnf install bubblewrap)" >&2; exit 1; }

PROJECTS_REAL="$(realpath -e -- "$PROJECTS_DIR")"

# True when $1 is a directory strictly INSIDE the projects dir.
in_projects() { case "$1/" in "$PROJECTS_REAL"/?*) return 0 ;; esac; return 1; }

# Build the bwrap command line into the array BW.
build_bwrap() {
  local workdir="$1" d p v g
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
        --size "$TMP_SIZE_BYTES" --tmpfs /tmp
        --dir /var --tmpfs /var/tmp
        --dir "/run/user/$(id -u)" --chmod 0700 "/run/user/$(id -u)" )

  # Only the /etc entries needed for DNS, TLS, users and the dynamic linker.
  for p in hosts nsswitch.conf resolv.conf passwd group localtime os-release \
           ssl pki ca-certificates crypto-policies alternatives ld.so.cache ld.so.conf ld.so.conf.d \
           gai.conf protocols services; do
    [ -e "/etc/$p" ] && BW+=( --ro-bind "/etc/$p" "/etc/$p" )
  done

  # $HOME inside the jail is an empty RAM disk. Only agy's own state is persistent.
  BW+=( --size "$HOME_SIZE_BYTES" --tmpfs "$HOME"
        --bind "$JAIL_STATE/gemini" "$HOME/.gemini"
        --bind "$JAIL_STATE/antigravity-config" "$HOME/.config/antigravity"
        --ro-bind "$JAIL_STATE/gitconfig" "$HOME/.gitconfig" )

  # The ONE writable project area.
  BW+=( --bind "$PROJECTS_REAL" "$PROJECTS_REAL" )
  # Git hooks and git config can make git run arbitrary commands on YOUR side later
  # (hooks, core.fsmonitor, core.sshCommand, aliases starting with !), so for every
  # existing repo they are read-only. Commits, branches and checkouts still work;
  # only `git config`, `git remote add` and `push -u` fail inside the jail.
  for g in "$PROJECTS_REAL"/*/.git/hooks; do [ -d "$g" ] && BW+=( --ro-bind "$g" "$g" ); done
  if [ "${PROTECT_GIT_CONFIG:-1}" = 1 ]; then
    for g in "$PROJECTS_REAL"/*/.git/config; do [ -f "$g" ] && BW+=( --ro-bind "$g" "$g" ); done
  fi

  # agy binary, read-only, on PATH inside the jail.
  BW+=( --ro-bind "$REAL_BIN_DIR" /opt/agy )
  for p in "${EXTRA_RO[@]}"; do [ -e "$p" ] && BW+=( --ro-bind "$p" "$p" ); done

  # Make the (RAM-backed) root itself read-only; the mounts above keep their own flags.
  BW+=( --remount-ro / )

  # Minimal environment.
  BW+=( --setenv HOME "$HOME" --setenv USER "${USER:-user}" --setenv LOGNAME "${USER:-user}"
        --setenv SHELL /bin/bash --setenv PATH /opt/agy:/usr/local/bin:/usr/bin:/bin
        --setenv TMPDIR /tmp --setenv XDG_RUNTIME_DIR "/run/user/$(id -u)" )
  for v in TERM COLORTERM LANG LC_ALL LC_CTYPE TZ "${PASS_ENV[@]}"; do
    [ -n "${!v:-}" ] && BW+=( --setenv "$v" "${!v}")
  done
  [ -n "${GOMEMLIMIT_VALUE:-}" ] && BW+=( --setenv GOMEMLIMIT "$GOMEMLIMIT_VALUE" )
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

cmd="${1:-}"
case "$cmd" in
  new)
    name="${2:?usage: agy-jail new NAME}"
    case "$name" in */*|.*|"") echo "agy-jail: NAME must be a simple folder name" >&2; exit 1 ;; esac
    mkdir -p "$PROJECTS_REAL/$name"
    echo "Created $PROJECTS_REAL/$name"
    echo "Next:  cd \"$PROJECTS_REAL/$name\" && agy-jail"
    ;;
  shell)
    need_project_cwd; build_bwrap "$CWD_REAL"
    exec "${BW[@]}" /bin/bash --norc --noprofile -i
    ;;
  audit)
    echo "Scanning $PROJECTS_REAL for files that could execute on YOUR side later..."
    found=0
    for proj in "$PROJECTS_REAL"/*/; do
      for h in "$proj".git/hooks/*; do
        case "$h" in *.sample) ;; *) echo "REVIEW git hook:   $h"; found=1 ;; esac
      done
      if [ -f "$proj.git/config" ] && grep -nE 'hooksPath|fsmonitor|sshCommand|editor|pager|^[[:space:]]*(alias|credential).*!|helper *= *!' "$proj.git/config" >/dev/null 2>&1; then
        echo "REVIEW git config:  ${proj}.git/config"; grep -nE 'hooksPath|fsmonitor|sshCommand|editor|pager|!' "$proj.git/config" | sed 's/^/    /'; found=1
      fi
      for f in .envrc .vscode/tasks.json .vscode/settings.json .vscode/launch.json .idea/workspace.xml .husky .pre-commit-config.yaml .devcontainer/devcontainer.json; do
        [ -e "$proj$f" ] && { echo "REVIEW auto-run:   $proj$f"; found=1; }
      done
    done
    [ "$found" -eq 1 ] || echo "Nothing suspicious found."
    ;;
  selftest)
    mkdir -p "$PROJECTS_REAL/.agy-selftest"; probe="agy-jail-selftest-$$"
    real_files=( "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.gitconfig" )
    before="$(sha256sum "${real_files[@]}" 2>/dev/null || true)"
    CWD_REAL="$PROJECTS_REAL/.agy-selftest"; build_bwrap "$CWD_REAL"
    set +e
    "${BW[@]}" /bin/bash -c '
      ok=0
      try_write()  { if ( : > "$1" ) 2>/dev/null; then echo "  LEAK (writable): $1"; ok=1; else echo "  ok (blocked):    $1"; fi; }
      try_read()   { if [ -e "$1" ]; then echo "  LEAK (visible):  $1"; ok=1; else echo "  ok (invisible):  $1"; fi; }
      echo "Writes that must FAIL:"
      for t in /usr/'"$probe"' /etc/'"$probe"' /var/'"$probe"' /opt/'"$probe"' /opt/agy/'"$probe"' /home/'"$probe"' /run/'"$probe"'; do try_write "$t"; done
      echo "Real-home items that must be INVISIBLE:"
      for t in "$HOME/.ssh" "$HOME/.gnupg" "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.config/BraveSoftware" "$HOME/Documents" "$HOME/Downloads"; do try_read "$t"; done
      echo "Write that must SUCCEED:"
      if ( : > "$PWD/'"$probe"'" ) 2>/dev/null; then echo "  ok (writable):   $PWD"; rm -f "$PWD/'"$probe"'"; else echo "  BROKEN: cannot write inside the project"; ok=1; fi
      echo "Environment leak check:"
      if env | grep -qE "SSH_AUTH_SOCK|AWS_|TOKEN|SECRET|DBUS_SESSION"; then echo "  LEAK: sensitive variable present"; ok=1; else echo "  ok: no sensitive variables"; fi
      echo "Info:"
      unshare -Ur true 2>/dev/null && echo "  nested user namespaces work (agy built-in sandbox can start)" || echo "  nested namespaces unavailable (agy will fall back to asking before commands)"
      getent hosts antigravity.google >/dev/null 2>&1 && echo "  DNS works" || echo "  DNS lookup failed (is the network up?)"
      exit $ok
    '
    inside=$?
    set -e
    rmdir "$PROJECTS_REAL/.agy-selftest" 2>/dev/null || true
    after="$(sha256sum "${real_files[@]}" 2>/dev/null || true)"
    rc=0
    [ "$inside" -eq 0 ] || rc=1
    [ "$before" = "$after" ] && echo "Host check: real ~/.bashrc ~/.zshrc ~/.profile ~/.gitconfig unchanged" || { echo "Host check: A REAL DOTFILE CHANGED"; rc=1; }
    [ ! -e "$HOME/$probe" ] && [ ! -e "$(dirname "$PROJECTS_REAL")/$probe" ] || { echo "Host check: probe file leaked to host"; rc=1; }
    [ "$rc" -eq 0 ] && echo "SELFTEST PASSED" || echo "SELFTEST FAILED"
    exit "$rc"
    ;;
  help|-h|--help)
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    need_project_cwd; build_bwrap "$CWD_REAL"
    exec "${BW[@]}" /opt/agy/agy "$@"
    ;;
esac
LAUNCHER_EOF
chmod 755 "$AGY_LAUNCHER"

# --- BleachBit cleaner: logs/crashes/caches only (never login or history) ----
mkdir -p "$BLEACHBIT_CLEANER_DIR"
cat > "${BLEACHBIT_CLEANER_DIR}/agy_jail.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<cleaner id="agy_jail">
  <label>Antigravity CLI (jail)</label>
  <description>Logs, crash reports and caches of the confined Antigravity CLI</description>
  <option id="logs">
    <label>Logs and crash reports</label>
    <description>Delete agy log files and crash dumps (keeps login, settings and conversations)</description>
    <action command="delete" search="walk.files" path="${AGY_STATE_DIR}/gemini/antigravity-cli/log"/>
    <action command="delete" search="walk.files" path="${AGY_STATE_DIR}/gemini/antigravity-cli/crashes"/>
    <action command="delete" search="file" path="${AGY_STATE_DIR}/gemini/antigravity-cli/cli.log"/>
  </option>
  <option id="cache">
    <label>Cache</label>
    <description>Delete agy cached data</description>
    <action command="delete" search="walk.all" path="${AGY_STATE_DIR}/gemini/antigravity-cli/cache"/>
  </option>
</cleaner>
EOF

# --- weekly auto-update (systemd user timer, sandboxed) ---------------------
mkdir -p "$SYSTEMD_USER_DIR"
cat > "${SYSTEMD_USER_DIR}/agy-jail-update.service" <<EOF
[Unit]
Description=Update the Antigravity CLI binary used by agy-jail
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
Description=Weekly check for a new Antigravity CLI release

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
  cd "${PROJECTS_DIR}/Play01" && agy-jail
First launch: sign in with your Google account (copy the URL it prints into your browser).
EOF

##################################################################################
# Notes
##################################################################################
# * Threat model. Protects against: the agent (or a prompt-injected web page / README
#   it read) modifying files outside PROJECTS_DIR, reading ~/.ssh, ~/.gnupg, browser
#   profiles, shell history, or other projects. Does NOT protect against: the agent
#   destroying or corrupting PROJECTS_DIR itself (use git + backups), or sending
#   project contents to Google/any host (the network is open; the agent must reach
#   Google). Use OpenSnitch/firewall rules for egress control (Notes below).
# * Why bubblewrap and not Antigravity's own sandbox: see Overview. The same class
#   of design is used by Flatpak. bwrap is already installed on Fedora Workstation.
# * Writable on the host: PROJECTS_DIR and the two private state dirs under
#   AGY_STATE_DIR (agy's ~/.gemini and ~/.config/antigravity). Everything else the
#   agent writes lands in RAM disks that vanish when it exits.
# * Poisoned-project escape. Files the agent writes in a project can run on YOUR side
#   later: git hooks, git config (core.fsmonitor, aliases starting with !), .envrc
#   (direnv), .vscode/tasks.json, package.json scripts, Makefiles. The launcher makes
#   .git/hooks and .git/config read-only for existing repos (set PROTECT_GIT_CONFIG=0
#   in the conf to allow `git remote add` etc.; do the git config on the host instead);
#   `agy-jail audit` flags the rest. Open
#   projects in VSCodium/PyCharm in Restricted/Safe mode and review before running.
# * No D-Bus session bus and no keyring are exposed: bus access lets a process start
#   systemd user units outside the jail. agy falls back to a file-based secret store
#   inside the jail's private state (verified: log shows "Using file-based secret
#   storage"). Do not sync AGY_STATE_DIR with Syncthing (it holds your login token).
# * Environment is cleared: SSH_AUTH_SOCK, cloud credentials and tokens never enter.
# * Resource profile: RAM_PROFILE from get_ram_profile sizes the tmpfs mounts and
#   sets GOMEMLIMIT on low-RAM machines. CPU/GPU tuning is irrelevant for a TUI agent.
# * DNS/NextDNS: the jail shares the host network, so queries go through
#   systemd-resolved to your NextDNS profile with the host's device ID. agy has no
#   per-app DNS setting, so no app-level ID is configured.
# * Do not combine the jail with --dangerously-skip-permissions lightly: inside the
#   jail the blast radius is limited to the project, but the agent can still delete it.
# * Logging: replaced the usual `tee` redirect with a re-exec under `script` so
#   terminal colors survive (tee makes stdout a pipe and many tools drop colors).
# * The official installer (curl | bash) was replaced by a verified GitHub release
#   download because that installer appends to ~/.bashrc and ~/.profile.
# * Re-running the full setup backs up then wipes the jail state (fresh start, as
#   designed), so you must sign in again. Updates use --update, which keeps state.
# * Not covered: the Antigravity IDE and 2.0 desktop app (Electron GUIs need Wayland,
#   GPU and D-Bus holes in the jail; separate design).
#
##################################################################################
# Useful Links
##################################################################################
# https://antigravity.google/docs/sandbox                              Antigravity terminal sandbox (scope and limits)
# https://antigravity.google/docs/permissions                          Antigravity permission model
# https://github.com/google-antigravity/antigravity-cli/issues/36      Sandbox bypass with --dangerously-skip-permissions
# https://github.com/google-antigravity/antigravity-cli/releases       Official release assets
# https://github.com/containers/bubblewrap                             bubblewrap
# https://man.archlinux.org/man/bwrap.1                                bwrap options reference
# https://wiki.archlinux.org/title/Bubblewrap                          Arch Wiki: bubblewrap
# https://docs.flatpak.org/en/latest/sandbox-permissions.html          How Flatpak uses the same approach
# https://www.freedesktop.org/software/systemd/man/systemd.exec.html   systemd sandboxing options
# https://github.com/maximebories/antigravity-telemetry-guard          Documented telemetry setting keys
#
##################################################################################
# Troubleshooting/Debugging/Testing/Commands
##################################################################################
# agy-jail selftest                  re-run the confinement proof
# agy-jail shell                     see exactly what the agent sees (ls -la ~; ls /)
# agy-jail audit                     list auto-run files in projects
# bash antigravity.sh --verify-setup full check of the install
# bash antigravity.sh --update       refresh binary now (timer does it weekly)
# systemctl --user list-timers agy-jail-update.timer ; journalctl --user -u agy-jail-update
# "agy-jail: refusing to start"      cd into ${PROJECTS_DIR}/<project> first
# "No permissions to create new namespace"   sysctl user.max_user_namespaces (must be >0);
#                                    on Ubuntu 24.04+ AppArmor may restrict userns for bwrap
# A tool is missing inside the jail  the jail only sees /usr; add paths to EXTRA_RO in ${AGY_CONF_FILE}
# Login URL does not open            expected (no browser in the jail): copy the printed URL to your browser
# Check agy's own logs               ${AGY_STATE_DIR}/gemini/antigravity-cli/log/
# Uninstall                          systemctl --user disable --now agy-jail-update.timer; rm -rf ${AGY_INSTALL_DIR} ${AGY_LAUNCHER} ${AGY_CONF_DIR} ${AGY_STATE_DIR}