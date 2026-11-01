#!/usr/bin/env bash
#########################################################
# Useful Links
#########################################################
# Atuin docs / config reference ......... https://docs.atuin.sh/ , https://docs.atuin.sh/cli/configuration/config/
# Atuin releases ........................ https://github.com/atuinsh/atuin/releases
# Import / history format ............... https://docs.atuin.sh/cli/guide/import/
# GitHub release asset digests .......... https://github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets/
# SQLite online backup API (python) ..... https://docs.python.org/3/library/sqlite3.html#sqlite3.Connection.backup
# Why root must not share the history DB  https://github.com/zsh-users/zsh-completions/issues/680 (same trust reasoning)
#
#########################################################
# Description
#########################################################
# Installs Atuin (searchable shell history in a local SQLite database) from the official release binary
# and configures it for LOCAL USE ONLY:
#   * sync is never configured (auto_sync = false; no `atuin register` / `atuin login`): history stays on this PC
#   * update_check stays at Atuin's default (a version check against api.atuin.sh at most once an hour;
#     no history or commands are sent)
#   * the AI-related subcommands (`atuin ai`, `atuin mcp`, ...) are never invoked or configured
#   * secrets_filter on, plus extra history_filter patterns for passwords/tokens/keys
#   * database directory 0700, database files 0600
# Scope: one database PER USER, shared by that user's zsh AND bash (same file). Root gets NO Atuin: the
# snippet lives in conf.d-user, which root never loads. Sharing a database between your user and root would
# either expose root's commands (often containing secrets) to your user, or let anything running as your user
# plant history entries that root then runs.
# zsh keeps writing ~/.zsh_history too: it is the plain-text fallback and the easiest portable export.
#
# On a fresh Atuin database the existing zsh/bash history is imported once.
#
# MOVING HISTORY TO A NEW PC
#   1. Old PC:  nb-atuin-backup           (consistent copy of the database + a text export, mode 0600)
#   2. New PC:  sudo bash atuin.sh --restore-db /path/to/history_<time>.db
#   Without a database copy, the setup imports ~/.zsh_history automatically (commands and times only).
#   History contains secrets: encrypt copies that leave the machine (age/gpg).
#
# NAMED OPTIONS
#   --restore-db <path>   Restore a database copy made by nb-atuin-backup (an existing database is backed
#                         up first). Skips the automatic first-time import.
#   --verify-setup        Only run the Verification section (no changes are made).
#   --timestamp <value>   Timestamp used in backup/download directory names.
#                         Default: current time (YYYY-MM-DD_HH-MM-SS).
#   -h | --help           Show usage.
#
# SAMPLE CALLS (assuming the caller has the same variable names)
#   With all options:
#     sudo REAL_USER="$REAL_USER" bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/atuin.sh" \
#          --restore-db "$HOME/atuin_history_backup.db" --timestamp "$FILENAME_TIMESTAMP"
#   With only mandatory options (there are none):
#     sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/atuin.sh"
#   Verification only:
#     sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/atuin.sh" --verify-setup
#
# REQUIRED HELPER FILES (in $SYSUPDATE_CODE_BASE_DIR/linux/common/)
#   helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh
#   get_*.sh system detection scripts. Initialize AFTER fzf (cli_tools.sh): both bind Ctrl-R; Atuin's snippet
#   (50) loads after the tools snippet (30), so Atuin wins Ctrl-R and Up-arrow.

set -Eeuo pipefail

#########################################################
# User defined variables
#########################################################
REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${SYSUPDATE_CODE_BASE_DIR:-${CODEPROJECTS_DIR}/system_update}"
SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"
ATUIN_DOWNLOADS_DIR_BASE="${SCRIPT_DATA_DOWNLOADS}/atuin"
ATUIN_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/atuin"

HELPER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/common"
for _f in helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh; do
  [[ -r "${HELPER_DIR}/${_f}" ]] || { echo "Missing helper file: ${HELPER_DIR}/${_f}" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "${HELPER_DIR}/${_f}"
done
unset _f
nb_require_functions backup_path_parents nb_install_github_binary nb_install_conf nb_install_updater nb_ensure_update_runner render write_file
trap 'log_error "Unexpected failure at line ${LINENO}: ${BASH_COMMAND}"' ERR

# --- Script specific ---
ATUIN_REPO="atuinsh/atuin"
ATUIN_BIN="/usr/local/bin/atuin"
ATUIN_ASSET_TEMPLATE="atuin-@TRIPLE@.tar.gz"
RELEASE_MIN_AGE_DAYS=3                  # adopt a release only when it is at least this old (0 disables)
ATUIN_CONFIG_FILE="${HOME_DIR}/.config/atuin/config.toml"
ATUIN_HISTORY_BACKUP_DIR="${SCRIPT_DATA_BACKUPS}/atuin_history"   # where nb-atuin-backup writes
ATUIN_HISTORY_BACKUPS_KEEP=10
BACKUP_TOOL="/usr/local/bin/nb-atuin-backup"
NTFY_URL=""                             # optional, e.g. https://ntfy.sh/<topic>

# Option values
RESTORE_DB_PATH=""

#########################################################
# Inferred variables
#########################################################
ATUIN_CURRENT_BACKUP_DIR="" ATUIN_CURRENT_DOWNLOADS_DIR=""
ATUIN_DB_PATH="" ATUIN_DATA_DIR=""

infer_variables() {
  nb_infer_system
  ATUIN_CURRENT_BACKUP_DIR="${ATUIN_BACKUP_DIR_BASE}/atuin_${FILENAME_TIMESTAMP}"
  ATUIN_CURRENT_DOWNLOADS_DIR="${ATUIN_DOWNLOADS_DIR_BASE}/atuin_${FILENAME_TIMESTAMP}"
}

#########################################################
# Named Options processing
#########################################################
parse_script_options() {
  local i=0
  while [[ $i -lt ${#NB_REMAINING_ARGS[@]} ]]; do
    case "${NB_REMAINING_ARGS[$i]}" in
      --restore-db)
        i=$((i + 1))
        [[ $i -lt ${#NB_REMAINING_ARGS[@]} ]] || log_die "--restore-db requires a path"
        RESTORE_DB_PATH="${NB_REMAINING_ARGS[$i]}"
        ;;
      *) log_die "Unknown option: ${NB_REMAINING_ARGS[$i]} (try --help)" ;;
    esac
    i=$((i + 1))
  done
}

#########################################################
# Templates
#########################################################
IFS= read -r -d '' CONFIG_TOML <<'EOF' || true
# Atuin client config - generated by atuin.sh on @TIMESTAMP@.
# LOCAL USE ONLY: history never leaves this machine.

# Sync is never configured. Do not run `atuin register` or `atuin login`.
auto_sync = false
# Atuin's default: a version check against api.atuin.sh at most once an hour. No history is sent.
update_check = true

search_mode = "fuzzy"
filter_mode = "global"                          # Ctrl-R searches all history (zsh + bash)
filter_mode_shell_up_key_binding = "session"    # Up-arrow walks the CURRENT session's commands
style = "compact"
inline_height = 20
show_preview = true
enter_accept = false                            # Enter puts the command on the prompt; press Enter again to run

# Never store lines that look like they contain secrets (a safety net, not a guarantee).
secrets_filter = true
history_filter = ["(?i)(password|passwd|token|secret|api[_-]?key)"]
store_failed = true
EOF

# shellcheck disable=SC2016
IFS= read -r -d '' SNIPPET_ATUIN <<'EOF' || true
# 50-atuin.zsh - Atuin shell history. Installed by atuin.sh. Lives in conf.d-user: ROOT NEVER LOADS IT.
# Must load after 30-tools.zsh (fzf) so Atuin keeps Ctrl-R; ZSH's own history file keeps being written.
(( EUID == 0 )) && return 0
(( $+commands[atuin] )) || return 0
eval "$(atuin init zsh)"
alias nbatuinbackup='nb-atuin-backup'
EOF

# shellcheck disable=SC2016
IFS= read -r -d '' BACKUP_SCRIPT <<'EOF' || true
#!/usr/bin/env bash
# nb-atuin-backup - consistent copy of the Atuin database + a text export. Installed by atuin.sh (root-owned).
# Usage: nb-atuin-backup [output_dir]        Run as your normal user, not as root.
set -Eeuo pipefail
OUT_DIR="${1:-@OUT_DIR@}"
KEEP=@KEEP@

db="$(atuin info | awk -F': ' '/^client db path:/ {print $2}')"
[[ -f "$db" ]] || { echo "Atuin database not found: ${db:-unknown}" >&2; exit 1; }
ts="$(date +%Y-%m-%d_%H-%M-%S)"
install -d -m 0700 "$OUT_DIR"
umask 077

# SQLite's online backup API gives a consistent copy even while shells are writing to the database
# (a plain `cp` of a live database can capture a half-written state).
python3 - "$db" "${OUT_DIR}/history_${ts}.db" <<'PY'
import sqlite3, sys
src = sqlite3.connect(sys.argv[1]); dst = sqlite3.connect(sys.argv[2])
src.backup(dst); dst.close(); src.close()
PY

# Text export: time, duration, exit code, directory, command (tab separated; multi-line commands are not
# representable here, the .db copy is the lossless one). ATUIN_SESSION is required by `history list`.
ATUIN_SESSION=export atuin history list --format "{time}\t{duration}\t{exit}\t{directory}\t{command}" \
  > "${OUT_DIR}/history_${ts}.tsv"

# Keep only the newest KEEP copies of each kind.
for ext in db tsv; do
  ls -1t "${OUT_DIR}"/history_*."${ext}" 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f --
done
echo "Backup written: ${OUT_DIR}/history_${ts}.db (+ .tsv). Encrypt before storing it anywhere off this PC."
EOF

# shellcheck disable=SC2016
IFS= read -r -d '' UPDATER_ATUIN <<'EOF' || true
#!/usr/bin/env bash
# 30-atuin.sh - updates the Atuin release binary. Installed by atuin.sh. Owned by root.
set -Eeuo pipefail
# shellcheck source=/dev/null
source /usr/local/lib/nb/helper_github_release.sh

BIN="@BIN@"
if rpm -q atuin >/dev/null 2>&1; then echo "atuin is managed by dnf; skipping"; exit 0; fi
[[ -x "$BIN" ]] || { echo "atuin is not installed here; skipping"; exit 0; }

current="$("$BIN" --version | awk 'NR==1 {print $2}')"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rc=0
nb_install_github_binary "@REPO@" "@ASSET@" atuin "$BIN" "@DAYS@" "$work" "$current" || rc=$?
if (( rc == 10 )); then exit 0; fi
if (( rc != 0 )); then echo "WARNING: atuin update failed" >&2; exit 1; fi
command -v restorecon >/dev/null 2>&1 && restorecon -F "$BIN" >/dev/null 2>&1 || true
echo "atuin updated ${current} -> ${NB_INSTALLED_TAG}"
EOF

#########################################################
# Helpers
#########################################################
# Run a command as the real user with their HOME (sudo/runuser do not always set it as expected).
as_user() { runuser -u "$REAL_USER" -- env HOME="$HOME_DIR" "$@"; }

# Ask Atuin where its data lives instead of hard-coding it: the default location differs between versions.
detect_atuin_paths() {
  ATUIN_DB_PATH="$(as_user "$ATUIN_BIN" info 2>/dev/null | awk -F': ' '/^client db path:/ {print $2}')"
  [[ -n "$ATUIN_DB_PATH" ]] || log_die "Could not determine Atuin's database path (atuin info)"
  ATUIN_DATA_DIR="$(dirname "$ATUIN_DB_PATH")"
}

#########################################################
# Backup
#########################################################
backup_existing() {
  log_header "Backup"
  mkdir -p "$ATUIN_CURRENT_BACKUP_DIR"
  local -a paths=(
    "$ATUIN_BIN" "$ATUIN_CONFIG_FILE" "$BACKUP_TOOL"
    "${NB_CONF_USER_DIR}/50-atuin.zsh" "${NB_UPDATERS_DIR}/30-atuin.sh"
    # The history itself (both possible default locations); it is KEPT in place, this is the safety copy.
    "${HOME_DIR}/.local/share/atuin" "${HOME_DIR}/.atuin"
  )
  local f
  for f in "${paths[@]}"; do backup_path_parents "$f" "$ATUIN_CURRENT_BACKUP_DIR"; done
  chown -R "${REAL_USER}:${REAL_USER}" "$ATUIN_BACKUP_DIR_BASE"
  chmod 0700 "$ATUIN_CURRENT_BACKUP_DIR"
  log_success "Backup written to ${ATUIN_CURRENT_BACKUP_DIR}"
}

#########################################################
# Reset
#########################################################
# The history database is USER DATA and is never deleted here; only what this script installs is removed.
reset_existing() {
  log_header "Reset"
  if rpm -q atuin >/dev/null 2>&1; then
    log_warn "atuin is installed from an RPM; removing it so the verified release binary is used"
    dnf remove -y atuin >/dev/null 2>&1 || log_warn "Could not remove the atuin RPM"
  fi
  rm -f "$ATUIN_BIN" "$ATUIN_CONFIG_FILE" "$BACKUP_TOOL"
  nb_remove_conf user 50-atuin.zsh
  nb_remove_updater 30-atuin.sh
  log_success "Previous Atuin setup removed (history database kept)"
}

#########################################################
# Install
#########################################################
install_atuin() {
  log_header "Atuin binary"
  mkdir -p "$ATUIN_CURRENT_DOWNLOADS_DIR"
  # Downloads go to SCRIPT_DATA_DOWNLOADS, which has on-access ClamAV scanning (no extra clamscan needed).
  local rc=0
  nb_install_github_binary "$ATUIN_REPO" "$ATUIN_ASSET_TEMPLATE" atuin "$ATUIN_BIN" \
      "$RELEASE_MIN_AGE_DAYS" "$ATUIN_CURRENT_DOWNLOADS_DIR" "" || rc=$?
  chown -R "${REAL_USER}:${REAL_USER}" "$ATUIN_DOWNLOADS_DIR_BASE"
  [[ $rc -eq 0 ]] || log_die "Atuin could not be installed (download, checksum or cooldown problem)"
  has_cmd restorecon && restorecon -F "$ATUIN_BIN" 2>/dev/null || true
  "$ATUIN_BIN" --version
}

write_config() {
  log_header "Configuration (local only)"
  install -d -o "$REAL_USER" -g "$REAL_USER" -m 0755 "${HOME_DIR}/.config" "${HOME_DIR}/.config/atuin"
  write_file "$ATUIN_CONFIG_FILE" "$REAL_USER" "$REAL_USER" 0644 "$(render "$CONFIG_TOML" TIMESTAMP="$FILENAME_TIMESTAMP")"
  log_success "Config written: sync off, secrets filter on"
}

# Private data: directory 0700, database files 0600.
lock_down_data() {
  detect_atuin_paths
  install -d -o "$REAL_USER" -g "$REAL_USER" -m 0700 "$ATUIN_DATA_DIR"
  local f
  for f in "$ATUIN_DATA_DIR"/*; do
    [[ -f "$f" ]] || continue
    chown "${REAL_USER}:${REAL_USER}" "$f"
    chmod 0600 "$f"
  done
}

restore_db() {
  [[ -f "$RESTORE_DB_PATH" ]] || log_die "Database copy not found: ${RESTORE_DB_PATH}"
  python3 - "$RESTORE_DB_PATH" <<'PY' || log_die "The file is not a healthy SQLite database: ${RESTORE_DB_PATH}"
import sqlite3, sys
c = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
ok = c.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
has_table = c.execute("SELECT count(*) FROM sqlite_master WHERE name='history'").fetchone()[0] == 1
sys.exit(0 if ok and has_table else 1)
PY
  detect_atuin_paths
  install -d -o "$REAL_USER" -g "$REAL_USER" -m 0700 "$ATUIN_DATA_DIR"
  if [[ -f "$ATUIN_DB_PATH" ]]; then
    cp -a "$ATUIN_DB_PATH" "${ATUIN_CURRENT_BACKUP_DIR}/history.db.before_restore"
    log_info "Existing database saved to ${ATUIN_CURRENT_BACKUP_DIR}/history.db.before_restore"
  fi
  rm -f "${ATUIN_DB_PATH}-wal" "${ATUIN_DB_PATH}-shm"
  cp "$RESTORE_DB_PATH" "$ATUIN_DB_PATH"
  chown "${REAL_USER}:${REAL_USER}" "$ATUIN_DB_PATH"
  chmod 0600 "$ATUIN_DB_PATH"
  log_success "Database restored from ${RESTORE_DB_PATH}"
}

history_entry_count() {
  # `|| true`: with pipefail, a failing atuin (e.g. no database yet) must count as "0 entries", not abort.
  as_user env ATUIN_SESSION=count "$ATUIN_BIN" history list --cmd-only 2>/dev/null | wc -l || true
}

# Import existing shell history once, only into an EMPTY database (re-importing would duplicate entries).
initial_import() {
  local count; count="$(history_entry_count)"
  if [[ "$count" -gt 0 ]]; then
    log_info "Atuin already has ${count} entries; skipping the first-time import"
    return 0
  fi
  if [[ -f "${HOME_DIR}/.zsh_history" ]]; then
    as_user env HISTFILE="${HOME_DIR}/.zsh_history" "$ATUIN_BIN" import zsh >/dev/null 2>&1 \
      && log_success "Imported ~/.zsh_history" || log_warn "Importing ~/.zsh_history failed (not fatal)"
  fi
  if [[ -f "${HOME_DIR}/.bash_history" ]]; then
    as_user "$ATUIN_BIN" import bash >/dev/null 2>&1 \
      && log_success "Imported ~/.bash_history" || log_warn "Importing ~/.bash_history failed (not fatal)"
  fi
  log_info "Entries now: $(history_entry_count)"
}

install_support_files() {
  log_header "Snippet, updater and backup tool"
  nb_install_conf user 50-atuin.zsh "$SNIPPET_ATUIN"
  nb_install_updater 30-atuin.sh "$(render "$UPDATER_ATUIN" BIN="$ATUIN_BIN" REPO="$ATUIN_REPO" \
      ASSET="$ATUIN_ASSET_TEMPLATE" DAYS="$RELEASE_MIN_AGE_DAYS")"
  write_file "$BACKUP_TOOL" root root 0755 "$(render "$BACKUP_SCRIPT" OUT_DIR="$ATUIN_HISTORY_BACKUP_DIR" KEEP="$ATUIN_HISTORY_BACKUPS_KEEP")"
  install -d -o "$REAL_USER" -g "$REAL_USER" -m 0700 "$ATUIN_HISTORY_BACKUP_DIR"
  nb_ensure_update_runner
  log_success "Snippet 50-atuin.zsh (user only), updater 30-atuin.sh and nb-atuin-backup installed"
}

#########################################################
# Security
#########################################################
apply_security() {
  log_header "Security"
  if has_cmd restorecon; then
    restorecon -RF "$NB_ZSH_SHARED_DIR" "$NB_LIB_DIR" "$BACKUP_TOOL" 2>/dev/null || true
    [[ ! -x "$ATUIN_BIN" ]] || restorecon -F "$ATUIN_BIN" 2>/dev/null || true
    log_success "SELinux labels restored"
  fi
  lock_down_data
  # Atuin listens on no port in client mode, so no firewalld rule is needed. The history database is not
  # excluded from ClamAV: it is plain data and contains no executable content.
}

#########################################################
# Verification
#########################################################
zsh_function_as() {
  # zsh_function_as <user|root> <function>: is the function defined in a fresh interactive shell?
  local who="$1" fn="$2" out
  if [[ "$who" == "root" ]]; then
    out="$(HOME=/root zsh -i -c "print \${+functions[$fn]}" 2>/dev/null </dev/null | tail -n1)"
  else
    out="$(runuser -l "$REAL_USER" -c "zsh -i -c 'print \${+functions[$fn]}'" 2>/dev/null </dev/null | tail -n1)"
  fi
  [[ "$out" == "1" ]]
}

zsh_function_absent_for_root() { ! zsh_function_as root _atuin_preexec; }

verify_setup() {
  nb_verify_begin
  check "atuin binary is root-owned" test "$(stat -c %U "$ATUIN_BIN")" = "root"
  check "atuin binary is not group/other-writable" test -z "$(find "$ATUIN_BIN" -perm /022)"
  check "atuin runs" "$ATUIN_BIN" --version
  check "config disables sync (auto_sync = false)" grep -q '^auto_sync = false' "$ATUIN_CONFIG_FILE"
  check "config enables the secrets filter" grep -q '^secrets_filter = true' "$ATUIN_CONFIG_FILE"
  check "config has no sync server override" bash -c "! grep -q '^sync_address' '$ATUIN_CONFIG_FILE'"
  detect_atuin_paths
  check "no sync login exists (no session file)" test ! -e "${ATUIN_DATA_DIR}/session"
  check "data directory is 0700" test "$(stat -c %a "$ATUIN_DATA_DIR")" = "700"
  if [[ -f "$ATUIN_DB_PATH" ]]; then
    check "history database is 0600" test "$(stat -c %a "$ATUIN_DB_PATH")" = "600"
    check "history database is healthy" python3 -c "import sqlite3,sys;sys.exit(0 if sqlite3.connect(sys.argv[1]).execute('pragma integrity_check').fetchone()[0]=='ok' else 1)" "$ATUIN_DB_PATH"
  else
    nb_verify_warn "No history database yet (it is created by the first command in a new shell)"
  fi
  check "snippet is in the user-only directory" test -f "${NB_CONF_USER_DIR}/50-atuin.zsh"
  check "snippet is NOT in the root-visible directory" test ! -e "${NB_CONF_COMMON_DIR}/50-atuin.zsh"
  check "snippet passes zsh syntax check" zsh -n "${NB_CONF_USER_DIR}/50-atuin.zsh"
  check "user shell starts without errors" nb_user_zsh_starts_clean
  check "Atuin is active in the user's new shell" zsh_function_as user _atuin_preexec
  check "Atuin is NOT loaded in root's shell" zsh_function_absent_for_root
  check "updater installed: 30-atuin.sh" test -x "${NB_UPDATERS_DIR}/30-atuin.sh"
  check "backup tool installed (root-owned)" test -x "$BACKUP_TOOL" -a "$(stat -c %U "$BACKUP_TOOL")" = "root"
  nb_verify_end
}

#########################################################
# Main
#########################################################
main() {
  nb_require_root "$0" "$@"
  nb_parse_common_options "$@"
  parse_script_options
  infer_variables

  log_header "Atuin setup"
  if [[ "$VERIFY_ONLY" == "true" ]]; then
    verify_setup || exit 1
    return
  fi

  require_fedora
  nb_prepare_script_dirs "$ATUIN_BACKUP_DIR_BASE" "$ATUIN_DOWNLOADS_DIR_BASE" "$ATUIN_HISTORY_BACKUP_DIR"
  chmod 0700 "$ATUIN_HISTORY_BACKUP_DIR"
  backup_existing
  reset_existing
  install_atuin
  write_config
  if [[ -n "$RESTORE_DB_PATH" ]]; then
    restore_db
  else
    detect_atuin_paths
    install -d -o "$REAL_USER" -g "$REAL_USER" -m 0700 "$ATUIN_DATA_DIR"
    initial_import
  fi
  install_support_files
  apply_security
  verify_setup || true
  nb_notify "atuin.sh finished on $(hostname)"
  log_header "Done"
  log_info "Open a new terminal: Ctrl-R opens the Atuin search. Try: nb-atuin-backup. Backup: ${ATUIN_CURRENT_BACKUP_DIR}"
}

main "$@"
exit $?

#########################################################
# Notes
#########################################################
# * Offline = local only: no sync account is ever created, and `update_check` stays at Atuin's default
#   (hourly version check to api.atuin.sh, no history sent). To make it fully silent, set update_check = false
#   in ~/.config/atuin/config.toml; the weekly nb-update-tools run still updates the binary.
# * Atuin also ships AI-related subcommands. They are separate commands that must be invoked on purpose; this
#   setup never configures or calls them.
# * Data location is detected with `atuin info` (this version used ~/.atuin/data in testing, other versions
#   used ~/.local/share/atuin), never hard-coded. The directory also holds a `key` file that Atuin creates even
#   without sync: it is only used for encrypted sync and is locked down like the rest.
# * One database per user, shared by zsh and bash (the same file). A bash setup only needs
#   `eval "$(atuin init bash)"` plus bash-preexec or ble.sh (Atuin requires one of them for bash).
# * Root has no Atuin by design (see Description). Root's history stays in /root/.zsh_history.
# * Reset keeps the history database. The first-time import runs only into an EMPTY database; importing the
#   same history twice would create duplicate entries.
# * Exporting: Atuin has no `export` command. Options: the lossless database copy (nb-atuin-backup uses the
#   SQLite online backup API, safe while shells run), the text export it writes next to it, or ~/.zsh_history
#   which zsh keeps writing.
# * Ctrl-R: fzf (30-tools) also binds it; Atuin's snippet loads later (50) and takes over Ctrl-R and Up.
#   To keep the Up-arrow for zsh's own history, change the init line to: eval "$(atuin init zsh --disable-up-arrow)".
# * Install source: official release binary with SHA-256 sidecar + GitHub's digest cross-check and a release
#   cooldown (see starship.sh Notes for the trust comparison). Atuin ships no signatures this script could verify.
# * Removing Atuin: delete conf.d-user/50-atuin.zsh, updaters.d/30-atuin.sh, /usr/local/bin/atuin and
#   /usr/local/bin/nb-atuin-backup. Your history database stays until you delete the data directory.

#########################################################
# Troubleshooting/Debugging
#########################################################
# Health check:             sudo bash atuin.sh --verify-setup
# Where is my data?         atuin info
# Is Atuin working?         atuin doctor ; atuin stats ; atuin search --limit 5
# Ctrl-R opens nothing:     `type _atuin_preexec` in zsh must print a function; check `ls /usr/local/share/zsh-nb/conf.d-user`.
# Up-arrow annoys you:      use `--disable-up-arrow` in the snippet (root-owned: edit in atuin.sh and re-run).
# History shows twice:      the first-time import ran into a non-empty DB; restore a copy from nb-atuin-backup.
# Back up now:              nb-atuin-backup          (writes to ~/nb/nb_script_data/backups/atuin_history, mode 0600)
# Restore on a new PC:      sudo bash atuin.sh --restore-db /path/to/history_<time>.db
# Import plain history:     HISTFILE=~/.zsh_history atuin import zsh ; atuin import bash
# Export as text:           ATUIN_SESSION=x atuin history list --format "{time}\t{exit}\t{command}"
# Prove nothing is synced:  atuin status should say you are not logged in; no `session` file next to the database.
# Network check:            sudo strace -f -e trace=connect -p $(pgrep -n atuin) (only the hourly update check should appear)
# Update by hand:           sudo /usr/local/lib/nb/updaters.d/30-atuin.sh ; journalctl -u nb-update-tools.service -e
# Database errors:          sqlite3/python: PRAGMA integrity_check; restore from a backup copy if it is not "ok".
# Roll back:                backups mirror real paths under ~/nb/nb_script_data/backups/atuin/atuin_<timestamp>/
