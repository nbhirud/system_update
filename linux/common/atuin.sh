#!/usr/bin/env bash
#########################################################
# Useful Links
#########################################################
# Atuin docs / config reference ......... https://docs.atuin.sh/ , https://docs.atuin.sh/cli/configuration/config/
# Atuin releases ........................ https://github.com/atuinsh/atuin/releases
# Import / history format ............... https://docs.atuin.sh/cli/guide/import/
# GitHub release asset digests .......... https://github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets/
# SQLite online backup API (python) ..... https://docs.python.org/3/library/sqlite3.html#sqlite3.Connection.backup
#
#########################################################
# Description
#########################################################
# Installs Atuin (searchable shell history in a local SQLite database) for YOUR USER from the official release binary
# into ~/.local/bin, configured for LOCAL USE ONLY:
#   * sync is never configured (auto_sync = false; no `atuin register` / `atuin login`): history stays on this PC
#   * update_check stays at Atuin's default (a version check against api.atuin.sh at most once an hour;
#     no history or commands are sent)
#   * the AI-related subcommands (`atuin ai`, `atuin mcp`, ...) are never invoked or configured
#   * secrets_filter on, plus extra history_filter patterns for passwords/tokens/keys
#   * database directory 0700, database files 0600
# One database per user, shared by that user's zsh AND bash (the same file). Nothing is shared with root.
# zsh keeps writing ~/.zsh_history too: it is the plain-text fallback and the easiest portable export.
#
# SEARCH BEHAVIOR (what the keys do)
#   Ctrl-R ...... opens Atuin's search over ALL history (filter_mode = "global")
#   Up arrow .... also searches ALL history, newest first (filter_mode_shell_up_key_binding = "global").
#                 An earlier version limited Up to the CURRENT session ("session"): in a fresh terminal or after a
#                 reboot the session is empty, so Up showed nothing. "directory" (only commands run in the current
#                 folder) is a good alternative if you want Up to be context-aware.
#
# On a fresh Atuin database the existing zsh/bash history is imported once.
#
# MOVING HISTORY TO A NEW PC
#   1. Old PC:  nb-atuin-backup           (consistent copy of the database + a text export, mode 0600)
#   2. New PC:  bash atuin.sh --restore-db /path/to/history_<time>.db
#   Without a database copy, the setup imports ~/.zsh_history automatically (commands and times only).
#   History contains secrets: encrypt copies that leave the machine (age/gpg).
#
# This script needs NO root: started with sudo it re-runs itself as your user.
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
#     bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/atuin.sh" \
#          --restore-db "$HOME/atuin_history_backup.db" --timestamp "$FILENAME_TIMESTAMP"
#   With only mandatory options (there are none):
#     bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/atuin.sh"
#   Verification only:
#     bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/atuin.sh" --verify-setup
#
# REQUIRED HELPER FILES (helpers in $HELPER_DIR = $SYSUPDATE_CODE_BASE_DIR/linux/commonh/, getters in $GETTERS_DIR = .../linux/commong/)
#   helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh
#   get_*.sh system detection scripts. The snippet (50) loads after the tools snippet (30, fzf), so Atuin keeps
#   Ctrl-R and the Up arrow.

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

# Where the helper_*.sh files and the get_*.sh detection scripts live (overridable from the environment).
HELPER_DIR="${HELPER_DIR:-${SYSUPDATE_CODE_BASE_DIR}/linux/commonh}"     # helper_*.sh / helper_*.py
GETTERS_DIR="${GETTERS_DIR:-${SYSUPDATE_CODE_BASE_DIR}/linux/commong}"   # get_*.sh system detection scripts
for _f in helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh; do
  [[ -r "${HELPER_DIR}/${_f}" ]] || { echo "Missing helper file: ${HELPER_DIR}/${_f}" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "${HELPER_DIR}/${_f}"
done
unset _f
nb_require_functions backup_path_parents nb_install_github_binary nb_mkdir nb_install_conf nb_remove_conf nb_install_updater nb_remove_updater nb_ensure_update_runner render write_file nb_zsh_function_exists
trap 'log_error "Unexpected failure at line ${LINENO}: ${BASH_COMMAND}"' ERR

# --- Script specific ---
ATUIN_REPO="atuinsh/atuin"
ATUIN_BIN="${HOME_DIR}/.local/bin/atuin"
ATUIN_ASSET_TEMPLATE="atuin-@TRIPLE@.tar.gz"
RELEASE_MIN_AGE_DAYS=3                  # adopt a release only when it is at least this old (0 disables)
ATUIN_CONFIG_FILE="${HOME_DIR}/.config/atuin/config.toml"
ATUIN_HISTORY_BACKUP_DIR="${SCRIPT_DATA_BACKUPS}/atuin_history"   # where nb-atuin-backup writes
ATUIN_HISTORY_BACKUPS_KEEP=10
BACKUP_TOOL="${HOME_DIR}/.local/bin/nb-atuin-backup"
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
# Up arrow: all history, newest first. "session" (current terminal only) shows NOTHING in a fresh terminal.
# Other values: "directory" (commands run in the current folder), "host", "workspace".
filter_mode_shell_up_key_binding = "global"
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
# 50-atuin.zsh - Atuin shell history. Installed by atuin.sh.
# Must load after 30-tools.zsh (fzf) so Atuin keeps Ctrl-R; zsh's own history file keeps being written.
(( $+commands[atuin] )) || return 0
eval "$(atuin init zsh)"
alias nbatuinbackup='nb-atuin-backup'
EOF

# shellcheck disable=SC2016
IFS= read -r -d '' BACKUP_SCRIPT <<'EOF' || true
#!/usr/bin/env bash
# nb-atuin-backup - consistent copy of the Atuin database + a text export. Installed by atuin.sh.
# Usage: nb-atuin-backup [output_dir]
set -Eeuo pipefail
ATUIN="@ATUIN_BIN@"
OUT_DIR="${1:-@OUT_DIR@}"
KEEP=@KEEP@

db="$("$ATUIN" info | awk -F': ' '/^client db path:/ {print $2}')"
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
ATUIN_SESSION=export "$ATUIN" history list --format "{time}\t{duration}\t{exit}\t{directory}\t{command}" \
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
# 30-atuin.sh - updates the Atuin release binary. Installed by atuin.sh; runs as you.
set -Eeuo pipefail
# shellcheck source=/dev/null
source "@LIB@/helper_github_release.sh"

BIN="@BIN@"
if rpm -q atuin >/dev/null 2>&1; then echo "atuin is managed by dnf; skipping"; exit 0; fi
[[ -x "$BIN" ]] || { echo "atuin is not installed at ${BIN}; skipping"; exit 0; }

current="$("$BIN" --version | awk 'NR==1 {print $2}')"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rc=0
nb_install_github_binary "@REPO@" "@ASSET@" atuin "$BIN" "@DAYS@" "$work" "$current" || rc=$?
if (( rc == 10 )); then exit 0; fi
if (( rc != 0 )); then echo "WARNING: atuin update failed" >&2; exit 1; fi
echo "atuin updated ${current} -> ${NB_INSTALLED_TAG}"
EOF

#########################################################
# Helpers
#########################################################
# Ask Atuin where its data lives instead of hard-coding it: the default location differs between versions.
detect_atuin_paths() {
  ATUIN_DB_PATH="$("$ATUIN_BIN" info 2>/dev/null | awk -F': ' '/^client db path:/ {print $2}')"
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
    "${NB_ZSH_CONF_DIR}/50-atuin.zsh" "${NB_UPDATERS_DIR}/30-atuin.sh"
    # The history itself (both possible default locations); it is KEPT in place, this is the safety copy.
    "${HOME_DIR}/.local/share/atuin" "${HOME_DIR}/.atuin"
  )
  local f
  for f in "${paths[@]}"; do backup_path_parents "$f" "$ATUIN_CURRENT_BACKUP_DIR"; done
  chmod 0700 "$ATUIN_CURRENT_BACKUP_DIR"
  log_success "Backup written to ${ATUIN_CURRENT_BACKUP_DIR}"
}

#########################################################
# Reset
#########################################################
# The history database is USER DATA and is never deleted here; only what this script installs is removed.
reset_existing() {
  log_header "Reset"
  rm -f "$ATUIN_BIN" "$ATUIN_CONFIG_FILE" "$BACKUP_TOOL"
  nb_remove_conf 50-atuin.zsh
  nb_remove_updater 30-atuin.sh
  if rpm -q atuin >/dev/null 2>&1; then
    log_warn "atuin is also installed as an RPM; remove it with: sudo dnf remove atuin"
  fi
  if [[ -e /usr/local/bin/atuin ]]; then
    log_warn "A system-wide /usr/local/bin/atuin exists (earlier setup). zsh.sh removes it; or: sudo rm /usr/local/bin/atuin"
  fi
  log_success "Previous Atuin setup removed (history database kept)"
}

#########################################################
# Install
#########################################################
install_atuin() {
  log_header "Atuin binary (~/.local/bin)"
  mkdir -p "$ATUIN_CURRENT_DOWNLOADS_DIR"
  nb_mkdir 0755 "${HOME_DIR}/.local/bin"
  # Downloads go to SCRIPT_DATA_DOWNLOADS, which has on-access ClamAV scanning (no extra clamscan needed).
  local rc=0
  nb_install_github_binary "$ATUIN_REPO" "$ATUIN_ASSET_TEMPLATE" atuin "$ATUIN_BIN" \
      "$RELEASE_MIN_AGE_DAYS" "$ATUIN_CURRENT_DOWNLOADS_DIR" "" || rc=$?
  [[ $rc -eq 0 ]] || log_die "Atuin could not be installed (download, checksum or cooldown problem)"
  "$ATUIN_BIN" --version
}

write_config() {
  log_header "Configuration (local only)"
  nb_mkdir 0755 "${HOME_DIR}/.config" "${HOME_DIR}/.config/atuin"
  write_file "$ATUIN_CONFIG_FILE" "$REAL_USER" "$REAL_USER" 0644 "$(render "$CONFIG_TOML" TIMESTAMP="$FILENAME_TIMESTAMP")"
  log_success "Config written: sync off, secrets filter on, Up arrow searches all history"
}

# Private data: directory 0700, database files 0600.
lock_down_data() {
  detect_atuin_paths
  nb_mkdir 0700 "$ATUIN_DATA_DIR"
  local f
  for f in "$ATUIN_DATA_DIR"/*; do
    [[ -f "$f" ]] || continue
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
  nb_mkdir 0700 "$ATUIN_DATA_DIR"
  if [[ -f "$ATUIN_DB_PATH" ]]; then
    cp -a "$ATUIN_DB_PATH" "${ATUIN_CURRENT_BACKUP_DIR}/history.db.before_restore"
    log_info "Existing database saved to ${ATUIN_CURRENT_BACKUP_DIR}/history.db.before_restore"
  fi
  rm -f "${ATUIN_DB_PATH}-wal" "${ATUIN_DB_PATH}-shm"
  cp "$RESTORE_DB_PATH" "$ATUIN_DB_PATH"
  chmod 0600 "$ATUIN_DB_PATH"
  log_success "Database restored from ${RESTORE_DB_PATH}"
}

history_entry_count() {
  # `|| true`: with pipefail, a failing atuin (e.g. no database yet) must count as "0 entries", not abort.
  ATUIN_SESSION=count "$ATUIN_BIN" history list --cmd-only 2>/dev/null | wc -l || true
}

# Import existing shell history once, only into an EMPTY database (re-importing would duplicate entries).
initial_import() {
  local count; count="$(history_entry_count)"
  if [[ "$count" -gt 0 ]]; then
    log_info "Atuin already has ${count} entries; skipping the first-time import"
    return 0
  fi
  if [[ -f "${HOME_DIR}/.zsh_history" ]]; then
    HISTFILE="${HOME_DIR}/.zsh_history" "$ATUIN_BIN" import zsh >/dev/null 2>&1 \
      && log_success "Imported ~/.zsh_history" || log_warn "Importing ~/.zsh_history failed (not fatal)"
  fi
  if [[ -f "${HOME_DIR}/.bash_history" ]]; then
    "$ATUIN_BIN" import bash >/dev/null 2>&1 \
      && log_success "Imported ~/.bash_history" || log_warn "Importing ~/.bash_history failed (not fatal)"
  fi
  log_info "Entries now: $(history_entry_count)"
}

install_support_files() {
  log_header "Snippet, updater and backup tool"
  nb_install_conf 50-atuin.zsh "$SNIPPET_ATUIN"
  nb_install_updater 30-atuin.sh "$(render "$UPDATER_ATUIN" LIB="$NB_USER_LIB_DIR" BIN="$ATUIN_BIN" REPO="$ATUIN_REPO" \
      ASSET="$ATUIN_ASSET_TEMPLATE" DAYS="$RELEASE_MIN_AGE_DAYS")"
  write_file "$BACKUP_TOOL" "$REAL_USER" "$REAL_USER" 0755 "$(render "$BACKUP_SCRIPT" ATUIN_BIN="$ATUIN_BIN" \
      OUT_DIR="$ATUIN_HISTORY_BACKUP_DIR" KEEP="$ATUIN_HISTORY_BACKUPS_KEEP")"
  nb_mkdir 0700 "$ATUIN_HISTORY_BACKUP_DIR"
  nb_ensure_update_runner
  log_success "Snippet 50-atuin.zsh, updater 30-atuin.sh and nb-atuin-backup installed"
}

#########################################################
# Verification
#########################################################
verify_setup() {
  nb_verify_begin
  check "atuin binary is owned by ${REAL_USER}" test "$(stat -c %U "$ATUIN_BIN")" = "$REAL_USER"
  check "atuin binary is not group/other-writable" test -z "$(find "$ATUIN_BIN" -perm /022)"
  check "atuin runs" "$ATUIN_BIN" --version
  check "config disables sync (auto_sync = false)" grep -q '^auto_sync = false' "$ATUIN_CONFIG_FILE"
  check "config enables the secrets filter" grep -q '^secrets_filter = true' "$ATUIN_CONFIG_FILE"
  check "config has no sync server override" bash -c "! grep -q '^sync_address' '$ATUIN_CONFIG_FILE'"
  check "Up arrow searches all history (not just the session)" grep -q '^filter_mode_shell_up_key_binding = "global"' "$ATUIN_CONFIG_FILE"
  detect_atuin_paths
  check "no sync login exists (no session file)" test ! -e "${ATUIN_DATA_DIR}/session"
  check "data directory is 0700" test "$(stat -c %a "$ATUIN_DATA_DIR")" = "700"
  if [[ -f "$ATUIN_DB_PATH" ]]; then
    check "history database is 0600" test "$(stat -c %a "$ATUIN_DB_PATH")" = "600"
    check "history database is healthy" python3 -c "import sqlite3,sys;sys.exit(0 if sqlite3.connect(sys.argv[1]).execute('pragma integrity_check').fetchone()[0]=='ok' else 1)" "$ATUIN_DB_PATH"
  else
    nb_verify_warn "No history database yet (it is created by the first command in a new shell)"
  fi
  check "snippet passes zsh syntax check" zsh -n "${NB_ZSH_CONF_DIR}/50-atuin.zsh"
  check "user shell starts without errors" nb_user_zsh_starts_clean
  check "Atuin is active in a new shell" nb_zsh_function_exists _atuin_preexec
  check "updater installed: 30-atuin.sh" test -x "${NB_UPDATERS_DIR}/30-atuin.sh"
  check "backup tool installed" test -x "$BACKUP_TOOL"
  nb_verify_end
}

#########################################################
# Main
#########################################################
main() {
  nb_require_user "$0" "$@"
  nb_parse_common_options "$@"
  parse_script_options
  infer_variables

  log_header "Atuin setup"
  if [[ "$VERIFY_ONLY" == "true" ]]; then
    verify_setup || exit 1
    return
  fi

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
    nb_mkdir 0700 "$ATUIN_DATA_DIR"
    initial_import
  fi
  install_support_files
  lock_down_data
  verify_setup || true
  nb_notify "atuin.sh finished on $(hostname)"
  log_header "Done"
  log_info "Open a new terminal: Ctrl-R and the Up arrow open the Atuin search. Try: nb-atuin-backup. Backup: ${ATUIN_CURRENT_BACKUP_DIR}"
}

main "$@"
exit $?

#########################################################
# Notes
#########################################################
# * "Up shows nothing after a reboot": the earlier config set filter_mode_shell_up_key_binding = "session", which
#   limits the Up arrow to commands of the CURRENT terminal session. A new terminal (or a reboot) has none yet, so
#   Up showed nothing while Ctrl-R (global) still found everything. It is "global" now. This had nothing to do with
#   sharing between root and user.
# * What Atuin adds over the alternatives (they do different jobs): fzf-tab replaces the TAB completion menu and
#   knows nothing about history. zsh-autosuggestions shows ONE grey suggestion from history while you type. fzf's
#   Ctrl-R is a fuzzy search over the plain command list. Atuin stores each command with its directory, exit code,
#   duration and session, so it can answer "what did I run in THIS folder", "what succeeded", "how long did it take",
#   and it shares one database between zsh and bash. For a single offline PC that is a modest gain over fzf Ctrl-R;
#   remove it if you do not use those filters (delete ~/.config/zsh/conf.d/50-atuin.zsh and ~/.local/bin/atuin).
# * Offline = local only: no sync account is ever created, and `update_check` stays at Atuin's default
#   (hourly version check to api.atuin.sh, no history sent). To make it fully silent, set update_check = false in
#   ~/.config/atuin/config.toml.
# * Atuin also ships AI-related subcommands. They are separate commands that must be invoked on purpose; this setup
#   never configures or calls them.
# * Data location is detected with `atuin info` (one tested version used ~/.atuin/data, others ~/.local/share/atuin),
#   never hard-coded. The directory also holds a `key` file that Atuin creates even without sync: it is only used for
#   encrypted sync and is locked down like the rest.
# * One database per user, shared by zsh and bash. A bash setup only needs `eval "$(atuin init bash)"` plus
#   bash-preexec or ble.sh (Atuin requires one of them for bash). Root has no Atuin (and no zsh setup at all).
# * Reset keeps the history database. The first-time import runs only into an EMPTY database; importing the same
#   history twice would create duplicate entries.
# * Exporting: Atuin has no `export` command. Options: the lossless database copy (nb-atuin-backup uses the SQLite
#   online backup API, safe while shells run), the text export it writes next to it, or ~/.zsh_history.
# * Ctrl-R: fzf (30-tools) also binds it; Atuin's snippet loads later (50) and takes over Ctrl-R and Up. To keep the
#   Up arrow for zsh's own history, change the init line to: eval "$(atuin init zsh --disable-up-arrow)".
# * Install source: official release binary with SHA-256 sidecar + GitHub's digest cross-check and a release cooldown
#   (see starship.sh Notes for the trust comparison). Atuin ships no signatures this script could verify.
# * Removing Atuin: delete ~/.config/zsh/conf.d/50-atuin.zsh, ~/.local/share/nb/updaters.d/30-atuin.sh,
#   ~/.local/bin/atuin and ~/.local/bin/nb-atuin-backup. Your history database stays until you delete its directory.

#########################################################
# Troubleshooting/Debugging
#########################################################
# Health check:             bash atuin.sh --verify-setup
# Where is my data?         atuin info
# Is Atuin working?         atuin doctor ; atuin stats ; atuin search --limit 5
# Up/Ctrl-R show nothing:   `atuin search --limit 5` lists entries? Then check the config: grep filter_mode ~/.config/atuin/config.toml
#                           (Up must say "global"). No entries at all: `atuin stats`, then restore from nb-atuin-backup.
# Ctrl-R opens nothing:     `type _atuin_preexec` in zsh must print a function; check `ls ~/.config/zsh/conf.d`.
# Up-arrow annoys you:      use `--disable-up-arrow` in ~/.config/zsh/conf.d/50-atuin.zsh.
# History shows twice:      the first-time import ran into a non-empty DB; restore a copy from nb-atuin-backup.
# Back up now:              nb-atuin-backup          (writes to ~/nb/nb_script_data/backups/atuin_history, mode 0600)
# Restore on a new PC:      bash atuin.sh --restore-db /path/to/history_<time>.db
# Import plain history:     HISTFILE=~/.zsh_history atuin import zsh ; atuin import bash
# Export as text:           ATUIN_SESSION=x atuin history list --format "{time}\t{exit}\t{command}"
# Prove nothing is synced:  atuin status should say you are not logged in; no `session` file next to the database.
# Update by hand:           nb-update-tools   (or ~/.local/share/nb/updaters.d/30-atuin.sh)
# Database errors:          python3: PRAGMA integrity_check; restore from a backup copy if it is not "ok".
# Roll back:                backups mirror real paths under ~/nb/nb_script_data/backups/atuin/atuin_<timestamp>/
