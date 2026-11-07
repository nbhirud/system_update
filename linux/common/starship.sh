#!/usr/bin/env bash
#########################################################
# Useful Links
#########################################################
# Starship guide / config reference ..... https://starship.rs/guide/ , https://starship.rs/config/
# Presets (catppuccin-powerline) ........ https://starship.rs/presets/catppuccin-powerline
# Releases .............................. https://github.com/starship/starship/releases
# GitHub release asset digests .......... https://github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets/
# Catppuccin palettes ................... https://catppuccin.com/palette
# Ayu colors (other palettes) ........... https://github.com/ayu-theme/ayu-colors
# Why not Powerlevel10k (maintenance) ... https://github.com/romkatv/powerlevel10k/issues/2690
# Nerd Fonts (glyphs used by the preset)  https://www.nerdfonts.com/
#
#########################################################
# Description
#########################################################
# Installs the Starship prompt for YOUR USER from the OFFICIAL RELEASE binary (static musl build) into
# ~/.local/bin/starship, and configures it from the built-in "catppuccin-powerline" preset, patched for this setup:
#   * single line; powerline segments: OS/user -> directory, then OPTIONAL tags that only appear when relevant:
#       git (inside a repo), languages (python, rust, node, ...), cloud/dev (docker context, terraform,
#       AWS_PROFILE / AWS_REGION when those environment variables are set), and the duration of the last command
#   * AWS is shown only when you are actually "in" AWS (AWS_PROFILE/AWS_REGION set), never just because a
#     config file exists. gcloud/azure/kubernetes stay off for the same reason (always-on by nature).
#   * command duration after EVERY command (min_time = 0), at the END of the prompt (no right prompt, so
#     terminal copy/paste stays clean)
#   * username/hostname only for root or SSH sessions
#   * no desktop notifications from Starship (bgnotify does that)
# Palette: catppuccin_mocha (change STARSHIP_PALETTE below, or the `palette = ` line in the toml).
#
# Safety of the download: HTTPS only, SHA-256 sidecar + GitHub's upload digest cross-check, and a release
# cooldown (RELEASE_MIN_AGE_DAYS) so a brand-new bad release is not adopted immediately. See
# helper_github_release.sh. If the install fails, the zsh snippets fall back to the agnoster theme by themselves.
#
# Installs (all in your home, no root): ~/.local/bin/starship, ~/.config/starship.toml,
# ~/.config/zsh/conf.d/40-starship.zsh, updater 20-starship.sh (run by nb-update-tools).
# Started with sudo it re-runs itself as your user.
#
# NAMED OPTIONS
#   --verify-setup        Only run the Verification section (no changes are made).
#   --timestamp <value>   Timestamp used in backup/download directory names.
#                         Default: current time (YYYY-MM-DD_HH-MM-SS).
#   -h | --help           Show usage.
#
# SAMPLE CALLS (assuming the caller has the same variable names)
#   With all options:
#     bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/starship.sh" --timestamp "$FILENAME_TIMESTAMP"
#   With only mandatory options (there are none):
#     bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/starship.sh"
#   Verification only:
#     bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/starship.sh" --verify-setup
#
# REQUIRED HELPER FILES (helpers in $HELPER_DIR = $SYSUPDATE_CODE_BASE_DIR/linux/commonh/, getters in $GETTERS_DIR = .../linux/commong/)
#   helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh helper_starship_patch.py
#   get_*.sh system detection scripts. A Nerd Font (fonts.sh) is needed for the glyphs.

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
STARSHIP_DOWNLOADS_DIR_BASE="${SCRIPT_DATA_DOWNLOADS}/starship"
STARSHIP_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/starship"

# Where the helper_*.sh files and the get_*.sh detection scripts live (overridable from the environment).
HELPER_DIR="${HELPER_DIR:-${SYSUPDATE_CODE_BASE_DIR}/linux/commonh}"     # helper_*.sh / helper_*.py
GETTERS_DIR="${GETTERS_DIR:-${SYSUPDATE_CODE_BASE_DIR}/linux/commong}"   # get_*.sh system detection scripts
for _f in helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh; do
  [[ -r "${HELPER_DIR}/${_f}" ]] || { echo "Missing helper file: ${HELPER_DIR}/${_f}" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "${HELPER_DIR}/${_f}"
done
unset _f
nb_require_functions backup_path_parents nb_install_github_binary nb_mkdir nb_install_conf nb_remove_conf nb_install_updater nb_remove_updater nb_ensure_update_runner render write_file
trap 'log_error "Unexpected failure at line ${LINENO}: ${BASH_COMMAND}"' ERR

# --- Script specific ---
STARSHIP_REPO="starship/starship"
STARSHIP_BIN="${HOME_DIR}/.local/bin/starship"
STARSHIP_ASSET_TEMPLATE="starship-@TRIPLE@.tar.gz"
RELEASE_MIN_AGE_DAYS=3                   # adopt a release only when it is at least this old (0 disables)
STARSHIP_PRESET="catppuccin-powerline"   # built into the binary: `starship preset --list`
STARSHIP_PALETTE="catppuccin_mocha"      # catppuccin_mocha|catppuccin_frappe|catppuccin_macchiato|catppuccin_latte|ayu_mirage|ayu_dark|ayu_light
USER_STARSHIP_CONFIG="${HOME_DIR}/.config/starship.toml"
NTFY_URL=""                              # optional, e.g. https://ntfy.sh/<topic>

#########################################################
# Inferred variables
#########################################################
STARSHIP_CURRENT_BACKUP_DIR="" STARSHIP_CURRENT_DOWNLOADS_DIR=""
STARSHIP_SCAN_TIMEOUT="" STARSHIP_CMD_TIMEOUT=""
infer_variables() {
  nb_infer_system
  STARSHIP_CURRENT_BACKUP_DIR="${STARSHIP_BACKUP_DIR_BASE}/starship_${FILENAME_TIMESTAMP}"
  STARSHIP_CURRENT_DOWNLOADS_DIR="${STARSHIP_DOWNLOADS_DIR_BASE}/starship_${FILENAME_TIMESTAMP}"
  STARSHIP_CMD_TIMEOUT="500"
  # scan_timeout = how long Starship may spend listing the CURRENT directory to look for trigger files (go.mod,
  # requirements.txt, ...). Its default (30 ms) is too tight for a big or cold-cache directory such as ~ on an
  # older PC: it then prints "[WARN] Scanning current directory timed out" on every prompt. The limit only matters
  # in slow directories (a normal one is listed in about a millisecond), where the prompt can take up to this long.
  # get_ssd_present is false when ANY spinning disk exists, so it errs on the generous side.
  # if [[ "$SSD_PRESENT" == "true" ]]; then STARSHIP_SCAN_TIMEOUT="30"; else STARSHIP_SCAN_TIMEOUT="60"; fi
  if [[ "$SSD_PRESENT" == "true" ]]; then STARSHIP_SCAN_TIMEOUT="100"; else STARSHIP_SCAN_TIMEOUT="300"; fi
}

#########################################################
# Templates
#########################################################
# shellcheck disable=SC2016
IFS= read -r -d '' SNIPPET_STARSHIP <<'EOF' || true
# 40-starship.zsh - Starship prompt. Installed by starship.sh.
# Without the binary nothing happens: 10-omz.zsh then selects the agnoster theme by itself.
(( $+commands[starship] )) || return 0
eval "$(starship init zsh)"
EOF

# Fallback used only if the preset cannot be produced at all: plain, but still informative.
IFS= read -r -d '' FALLBACK_TOML <<'EOF' || true
"$schema" = 'https://starship.rs/config-schema.json'
# Generated by starship.sh on @TIMESTAMP@ (built-in preset unavailable: minimal fallback config).
command_timeout = @CMD_TIMEOUT@
scan_timeout = @SCAN_TIMEOUT@
format = "$username$hostname$directory$git_branch$git_status$python$cmd_duration$character"

[cmd_duration]
min_time = 0
show_milliseconds = true
show_notifications = false

[hostname]
ssh_only = true
EOF

# shellcheck disable=SC2016
IFS= read -r -d '' UPDATER_STARSHIP <<'EOF' || true
#!/usr/bin/env bash
# 20-starship.sh - updates the Starship release binary. Installed by starship.sh; runs as you.
set -Eeuo pipefail
# shellcheck source=/dev/null
source "@LIB@/helper_github_release.sh"

BIN="@BIN@"
if rpm -q starship >/dev/null 2>&1; then echo "starship is managed by dnf; skipping"; exit 0; fi
[[ -x "$BIN" ]] || { echo "starship is not installed at ${BIN}; skipping"; exit 0; }

current="$("$BIN" --version | awk 'NR==1 {print $2}')"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rc=0
nb_install_github_binary "@REPO@" "@ASSET@" starship "$BIN" "@DAYS@" "$work" "$current" || rc=$?
if (( rc == 10 )); then exit 0; fi
if (( rc != 0 )); then echo "WARNING: starship update failed" >&2; exit 1; fi
echo "starship updated ${current} -> ${NB_INSTALLED_TAG}"
EOF

#########################################################
# Backup
#########################################################
backup_existing() {
  log_header "Backup"
  mkdir -p "$STARSHIP_CURRENT_BACKUP_DIR"
  local -a paths=(
    "$STARSHIP_BIN" "$USER_STARSHIP_CONFIG"
    "${NB_ZSH_CONF_DIR}/40-starship.zsh" "${NB_UPDATERS_DIR}/20-starship.sh"
    "${HOME_DIR}/.cache/starship"
  )
  local f
  for f in "${paths[@]}"; do backup_path_parents "$f" "$STARSHIP_CURRENT_BACKUP_DIR"; done
  backup_record "$STARSHIP_CURRENT_BACKUP_DIR" "installed_packages" rpm -q starship
  chmod 0700 "$STARSHIP_CURRENT_BACKUP_DIR"
  log_success "Backup written to ${STARSHIP_CURRENT_BACKUP_DIR}"
}

#########################################################
# Reset
#########################################################
reset_existing() {
  log_header "Reset"
  rm -f "$STARSHIP_BIN" "$USER_STARSHIP_CONFIG"
  rm -rf "${HOME_DIR}/.cache/starship"
  nb_remove_conf 40-starship.zsh
  nb_remove_updater 20-starship.sh
  # Copies outside ~/.local/bin cannot be removed without root; say so instead of failing.
  if rpm -q starship >/dev/null 2>&1; then
    log_warn "starship is also installed as an RPM; remove it with: sudo dnf remove starship"
  fi
  if [[ -e /usr/local/bin/starship ]]; then
    log_warn "A system-wide /usr/local/bin/starship exists (earlier setup). zsh.sh removes it; or: sudo rm /usr/local/bin/starship"
  fi
  log_success "Previous Starship setup removed"
}

#########################################################
# Install
#########################################################
install_starship() {
  log_header "Starship binary (~/.local/bin)"
  mkdir -p "$STARSHIP_CURRENT_DOWNLOADS_DIR"
  nb_mkdir 0755 "${HOME_DIR}/.local/bin"
  # Downloads go to SCRIPT_DATA_DOWNLOADS, which has on-access ClamAV scanning (no extra clamscan needed).
  local rc=0
  nb_install_github_binary "$STARSHIP_REPO" "$STARSHIP_ASSET_TEMPLATE" starship "$STARSHIP_BIN" \
      "$RELEASE_MIN_AGE_DAYS" "$STARSHIP_CURRENT_DOWNLOADS_DIR" "" || rc=$?
  [[ $rc -eq 0 ]] || return 1
  "$STARSHIP_BIN" --version | head -n1
}

# A functional test: render a prompt with the given config, and require no warnings on stderr.
config_renders_cleanly() {
  local cfg="$1" err
  err="$(STARSHIP_CONFIG="$cfg" "$STARSHIP_BIN" prompt 2>&1 >/dev/null)" || return 1
  [[ -z "$err" ]]
}

# helper_starship_patch.py is a helper file: look in the helper directory first, then the older locations
# (linux/common next to the scripts), so it is found wherever it was left. Prints a path even when not found,
# so the failure shows up as a normal patch failure (and the script falls back to the unmodified preset).
locate_patch_helper() {
  local d
  for d in "$HELPER_DIR" "${SYSUPDATE_CODE_BASE_DIR}/linux/common" "$(dirname "${BASH_SOURCE[0]}")"; do
    if [[ -r "${d}/helper_starship_patch.py" ]]; then printf '%s\n' "${d}/helper_starship_patch.py"; return 0; fi
  done
  printf '%s\n' "${HELPER_DIR}/helper_starship_patch.py"
}

write_configs() {
  log_header "Configuration"
  nb_mkdir 0755 "${HOME_DIR}/.config"
  local tmp_dir; tmp_dir="$(mktemp -d)"
  local raw="${tmp_dir}/preset.toml" patched="${tmp_dir}/patched.toml"
  # Produced by the installed binary: always matches its version and needs no extra download.
  if "$STARSHIP_BIN" preset "$STARSHIP_PRESET" -o "$raw" 2>/dev/null; then
    if python3 "$(locate_patch_helper)" "$raw" "$patched" "$STARSHIP_PALETTE" "$STARSHIP_CMD_TIMEOUT" "$STARSHIP_SCAN_TIMEOUT" \
       && python3 -c 'import sys,tomllib;tomllib.load(open(sys.argv[1],"rb"))' "$patched" \
       && config_renders_cleanly "$patched"; then
      write_file "$USER_STARSHIP_CONFIG" "$REAL_USER" "$REAL_USER" 0644 "$(cat "$patched")"
      log_success "Config: ${STARSHIP_PRESET} preset, palette ${STARSHIP_PALETTE}, patched for this setup"
    elif config_renders_cleanly "$raw"; then
      log_warn "Patching failed or the patched config did not validate; using the UNMODIFIED preset"
      write_file "$USER_STARSHIP_CONFIG" "$REAL_USER" "$REAL_USER" 0644 "$(cat "$raw")"
    else
      log_warn "The preset itself did not validate; using the minimal fallback config"
      write_file "$USER_STARSHIP_CONFIG" "$REAL_USER" "$REAL_USER" 0644 "$(render "$FALLBACK_TOML" \
        TIMESTAMP="$FILENAME_TIMESTAMP" CMD_TIMEOUT="$STARSHIP_CMD_TIMEOUT" SCAN_TIMEOUT="$STARSHIP_SCAN_TIMEOUT")"
    fi
  else
    log_warn "Could not generate the preset; using the minimal fallback config"
    write_file "$USER_STARSHIP_CONFIG" "$REAL_USER" "$REAL_USER" 0644 "$(render "$FALLBACK_TOML" \
      TIMESTAMP="$FILENAME_TIMESTAMP" CMD_TIMEOUT="$STARSHIP_CMD_TIMEOUT" SCAN_TIMEOUT="$STARSHIP_SCAN_TIMEOUT")"
  fi
  rm -rf "$tmp_dir"
}

install_snippet() {
  log_header "Snippet and updater"
  nb_install_conf 40-starship.zsh "$SNIPPET_STARSHIP"
  nb_install_updater 20-starship.sh "$(render "$UPDATER_STARSHIP" LIB="$NB_USER_LIB_DIR" BIN="$STARSHIP_BIN" \
      REPO="$STARSHIP_REPO" ASSET="$STARSHIP_ASSET_TEMPLATE" DAYS="$RELEASE_MIN_AGE_DAYS")"
  nb_ensure_update_runner
  log_success "Snippet 40-starship.zsh and updater 20-starship.sh installed"
}

#########################################################
# Verification
#########################################################
starship_resolves_to_user_copy() {
  # In a fresh login shell of the user, `starship` must be the per-user binary, not an old system-wide one.
  [[ "$(nb_run_as_real_user "zsh -i -c 'command -v starship'" 2>/dev/null </dev/null | tail -n1)" == "$STARSHIP_BIN" ]]
}

verify_setup() {
  nb_verify_begin
  if [[ -x "$STARSHIP_BIN" ]]; then
    check "starship binary is owned by ${REAL_USER}" test "$(stat -c %U "$STARSHIP_BIN")" = "$REAL_USER"
    check "starship binary is not group/other-writable" test -z "$(find "$STARSHIP_BIN" -perm /022)"
    check "starship runs" "$STARSHIP_BIN" --version
    check "config renders without warnings" config_renders_cleanly "$USER_STARSHIP_CONFIG"
    check "config uses palette ${STARSHIP_PALETTE}" grep -q "^palette = '${STARSHIP_PALETTE}'" "$USER_STARSHIP_CONFIG"
    check "a new shell resolves starship to ${STARSHIP_BIN}" starship_resolves_to_user_copy
  else
    nb_verify_warn "Starship is not installed: the agnoster fallback theme is active"
  fi
  if [[ -e /usr/local/bin/starship ]]; then
    nb_verify_warn "an old system-wide /usr/local/bin/starship still exists (run zsh.sh, or sudo rm it)"
  fi
  check "config exists and is owned by ${REAL_USER}" test "$(stat -c %U "$USER_STARSHIP_CONFIG")" = "$REAL_USER"
  check "snippet passes zsh syntax check" zsh -n "${NB_ZSH_CONF_DIR}/40-starship.zsh"
  check "updater installed: 20-starship.sh" test -x "${NB_UPDATERS_DIR}/20-starship.sh"
  check "user shell starts without errors" nb_user_zsh_starts_clean
  nb_verify_end
}

#########################################################
# Main
#########################################################
main() {
  nb_require_user "$0" "$@"
  nb_parse_common_options "$@"
  nb_reject_remaining_args
  infer_variables

  log_header "Starship setup"
  if [[ "$VERIFY_ONLY" == "true" ]]; then
    verify_setup || exit 1
    return
  fi

  nb_prepare_script_dirs "$STARSHIP_BACKUP_DIR_BASE" "$STARSHIP_DOWNLOADS_DIR_BASE"
  backup_existing
  reset_existing
  if install_starship; then
    write_configs
    install_snippet
    verify_setup || true
    nb_notify "starship.sh finished on $(hostname)"
    log_header "Done"
    log_info "Open a new terminal (a Nerd Font is required for the glyphs). Backup: ${STARSHIP_CURRENT_BACKUP_DIR}"
  else
    # Not fatal for the shell: with no binary the zsh snippets select the agnoster theme.
    install_snippet
    log_error "Starship could not be installed (download, checksum or cooldown problem). Shells use agnoster instead."
    log_error "Re-run later: bash starship.sh   (details: helper_github_release.sh warnings above)"
    nb_notify "starship.sh FAILED on $(hostname)"
    trap - ERR   # the failure was reported above; do not print a second, misleading "Unexpected failure"
    return 1
  fi
}

main "$@"
exit $?

#########################################################
# Notes
#########################################################
# * Per-user install in ~/.local/bin: no root, no system-wide files, nothing shared with root (an earlier version
#   installed to /usr/local/bin and gave root its own config; that was dropped). Root's prompt is plain bash.
# * Install source: official release binary, not COPR and not `curl | sh`. The release binary is built by upstream CI
#   (one party to trust); a COPR adds a third-party packager plus an extra repository; `curl | sh` runs an unverified
#   script. Fedora's repos have no starship package. The checksum files come from the same GitHub project, so they
#   protect against corruption and post-upload tampering, not a compromised upstream; the cooldown
#   (RELEASE_MIN_AGE_DAYS) reduces that exposure. Starship publishes no signatures this script could verify.
# * Config source: `starship preset catppuccin-powerline` (built into the binary, always matches its version) instead
#   of a hard-coded copy or a download of the website file. It is patched by helper_starship_patch.py, which rebuilds
#   the `format` and edits a few module sections using the preset's own glyphs. If a patch marker is missing (the
#   preset changed upstream) the script falls back to the unmodified preset, and if that fails to the minimal config.
#   Every candidate is validated by parsing the TOML and rendering a prompt with no warnings.
# * Why "tags" for optional segments: with continuous powerline arrows, a hidden segment leaves arrows of the wrong
#   colors behind. Each optional group is wrapped in ( ... ), which Starship omits entirely when every module inside is
#   empty, and has its own arrow caps.
# * Go/Python tags: they appear when the directory has trigger files (go.mod, requirements.txt, ...). That is by design.
# * Palettes: catppuccin_mocha is the default. The preset also defines catppuccin_frappe/macchiato/latte and
#   ayu_mirage/ayu_dark/ayu_light; exactly one is active via `palette = '...'`.
# * Command duration: shown for the PREVIOUS command at the end of the next prompt.
# * Sharing with bash: ~/.config/starship.toml is shell independent; bash.sh only needs
#   `eval "$(starship init bash)"`. Termux: `pkg install starship` and sync the toml (Syncthing).
# * Starship sends no telemetry. The `starship preset` and `prompt` commands make no network requests.

#########################################################
# Troubleshooting/Debugging
#########################################################
# Health check:             bash starship.sh --verify-setup
# Explain the prompt:       starship explain ; starship timings ; starship config
# Verbose log:              STARSHIP_LOG=trace starship prompt
# "Scanning current directory timed out" warning: raise scan_timeout at the top of ~/.config/starship.toml
#                           (sed -i 's/^scan_timeout = .*/scan_timeout = 500/' ~/.config/starship.toml). A huge or cold-cache
#                           directory (often ~) is the usual cause; check `ls -A ~ | wc -l`. To hide ALL Starship warnings
#                           instead: export STARSHIP_LOG=error (also hides config warnings, so use it sparingly).
# Slow in a huge repo:      raise command_timeout, or set `disabled = true` under [git_status].
# Broken symbols/boxes:     the terminal font must be a Nerd Font (fonts.sh), e.g. JetBrainsMono Nerd Font.
# Prompt is agnoster:       `command -v starship` is empty: run this script again and read the warnings.
# Old system-wide copy:     `which -a starship`; the per-user one (~/.local/bin) wins because ~/.zshrc puts it first.
# AWS/cloud segment:        shows only with AWS_PROFILE / AWS_REGION set: `AWS_PROFILE=dev zsh -ic ''` to test.
# Switch palette:           sed -i "s/^palette = .*/palette = 'ayu_dark'/" ~/.config/starship.toml
# Update by hand:           nb-update-tools   (or ~/.local/share/nb/updaters.d/20-starship.sh)
# Cooldown skipped warning: the GitHub API was unreachable (rate limit/proxy): the installer used the latest
#                           release without the cooldown. Re-run later or set RELEASE_MIN_AGE_DAYS=0.
# Roll back:                backups mirror real paths under ~/nb/nb_script_data/backups/starship/starship_<timestamp>/
