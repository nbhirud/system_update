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
# Installs the Starship prompt from the OFFICIAL RELEASE binary (static musl build) and configures it from
# the built-in "catppuccin-powerline" preset, patched for this setup:
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
# helper_github_release.sh. If the install fails, the snippets fall back to the agnoster theme by themselves.
#
# Installs: /usr/local/bin/starship, ~/.config/starship.toml, /usr/local/share/zsh-nb/starship-root.toml,
# conf.d/40-starship.zsh, updaters.d/20-starship.sh
#
# NAMED OPTIONS
#   --verify-setup        Only run the Verification section (no changes are made).
#   --timestamp <value>   Timestamp used in backup/download directory names.
#                         Default: current time (YYYY-MM-DD_HH-MM-SS).
#   -h | --help           Show usage.
#
# SAMPLE CALLS (assuming the caller has the same variable names)
#   With all options:
#     sudo REAL_USER="$REAL_USER" bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/starship.sh" --timestamp "$FILENAME_TIMESTAMP"
#   With only mandatory options (there are none):
#     sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/starship.sh"
#   Verification only:
#     sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/starship.sh" --verify-setup
#
# REQUIRED HELPER FILES (in $SYSUPDATE_CODE_BASE_DIR/linux/common/)
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
STARSHIP_REPO="starship/starship"
STARSHIP_BIN="/usr/local/bin/starship"
STARSHIP_ASSET_TEMPLATE="starship-@TRIPLE@.tar.gz"
RELEASE_MIN_AGE_DAYS=3                   # adopt a release only when it is at least this old (0 disables)
STARSHIP_PRESET="catppuccin-powerline"   # built into the binary: `starship preset --list`
STARSHIP_PALETTE="catppuccin_mocha"      # catppuccin_mocha|catppuccin_frappe|catppuccin_macchiato|catppuccin_latte|ayu_mirage|ayu_dark|ayu_light
USER_STARSHIP_CONFIG="${HOME_DIR}/.config/starship.toml"
ROOT_STARSHIP_CONFIG="${NB_ZSH_SHARED_DIR}/starship-root.toml"
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
  # Spinning disks make directory scans slower: give Starship more time before it gives up on a module.
  if [[ "$SSD_PRESENT" == "true" ]]; then STARSHIP_SCAN_TIMEOUT="30"; else STARSHIP_SCAN_TIMEOUT="60"; fi
}

#########################################################
# Templates
#########################################################
# shellcheck disable=SC2016
IFS= read -r -d '' SNIPPET_STARSHIP <<'EOF' || true
# 40-starship.zsh - Starship prompt. Installed by starship.sh (root-owned: re-run starship.sh to change it).
# Without the binary nothing happens: 10-omz.zsh then selects the agnoster theme by itself.
(( $+commands[starship] )) || return 0
# Root uses its own root-owned config (red, "#" prompt character).
(( EUID == 0 )) && export STARSHIP_CONFIG="@ROOT_CONFIG@"
eval "$(starship init zsh)"
EOF

IFS= read -r -d '' ROOT_TOML <<'EOF' || true
"$schema" = 'https://starship.rs/config-schema.json'
# Generated by starship.sh on @TIMESTAMP@. Root-owned config used only by root's shell.
add_newline = false
command_timeout = 500
format = "$username$hostname$directory$character"

[username]
show_always = true
style_user = "bold red"
style_root = "bold red"
format = "[$user]($style)"

[hostname]
ssh_only = false
format = "[@$hostname]($style) "
style = "bold red"

[character]
success_symbol = "[#](bold red)"
error_symbol = "[#](bold red)"
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
# 20-starship.sh - updates the Starship release binary. Installed by starship.sh. Owned by root.
set -Eeuo pipefail
# shellcheck source=/dev/null
source /usr/local/lib/nb/helper_github_release.sh

BIN="@BIN@"
if rpm -q starship >/dev/null 2>&1; then echo "starship is managed by dnf; skipping"; exit 0; fi
[[ -x "$BIN" ]] || { echo "starship is not installed here; skipping"; exit 0; }

current="$("$BIN" --version | awk 'NR==1 {print $2}')"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rc=0
nb_install_github_binary "@REPO@" "@ASSET@" starship "$BIN" "@DAYS@" "$work" "$current" || rc=$?
if (( rc == 10 )); then exit 0; fi
if (( rc != 0 )); then echo "WARNING: starship update failed" >&2; exit 1; fi
command -v restorecon >/dev/null 2>&1 && restorecon -F "$BIN" >/dev/null 2>&1 || true
echo "starship updated ${current} -> ${NB_INSTALLED_TAG}"
EOF

#########################################################
# Backup
#########################################################
backup_existing() {
  log_header "Backup"
  mkdir -p "$STARSHIP_CURRENT_BACKUP_DIR"
  local -a paths=(
    "$STARSHIP_BIN" "$USER_STARSHIP_CONFIG" "/root/.config/starship.toml" "$ROOT_STARSHIP_CONFIG"
    "${NB_CONF_COMMON_DIR}/40-starship.zsh" "${NB_UPDATERS_DIR}/20-starship.sh"
    "${HOME_DIR}/.cache/starship"
  )
  local f
  for f in "${paths[@]}"; do backup_path_parents "$f" "$STARSHIP_CURRENT_BACKUP_DIR"; done
  backup_record "$STARSHIP_CURRENT_BACKUP_DIR" "installed_packages" rpm -q starship
  chown -R "${REAL_USER}:${REAL_USER}" "$STARSHIP_BACKUP_DIR_BASE"
  chmod 0700 "$STARSHIP_CURRENT_BACKUP_DIR"
  log_success "Backup written to ${STARSHIP_CURRENT_BACKUP_DIR}"
}

#########################################################
# Reset
#########################################################
reset_existing() {
  log_header "Reset"
  # A binary owned by a dnf package is left to dnf (e.g. a COPR package installed earlier).
  if rpm -q starship >/dev/null 2>&1; then
    log_warn "starship is installed from an RPM; removing it so the verified release binary is used"
    dnf remove -y starship >/dev/null 2>&1 || log_warn "Could not remove the starship RPM"
  fi
  rm -f "$STARSHIP_BIN" "$USER_STARSHIP_CONFIG" "/root/.config/starship.toml" "$ROOT_STARSHIP_CONFIG"
  rm -rf "${HOME_DIR}/.cache/starship"
  nb_remove_conf common 40-starship.zsh
  nb_remove_updater 20-starship.sh
  log_success "Previous Starship setup removed"
}

#########################################################
# Install
#########################################################
install_starship() {
  log_header "Starship binary"
  mkdir -p "$STARSHIP_CURRENT_DOWNLOADS_DIR"
  # Downloads go to SCRIPT_DATA_DOWNLOADS, which has on-access ClamAV scanning (no extra clamscan needed).
  local rc=0
  nb_install_github_binary "$STARSHIP_REPO" "$STARSHIP_ASSET_TEMPLATE" starship "$STARSHIP_BIN" \
      "$RELEASE_MIN_AGE_DAYS" "$STARSHIP_CURRENT_DOWNLOADS_DIR" "" || rc=$?
  chown -R "${REAL_USER}:${REAL_USER}" "$STARSHIP_DOWNLOADS_DIR_BASE"
  [[ $rc -eq 0 ]] || return 1
  has_cmd restorecon && restorecon -F "$STARSHIP_BIN" 2>/dev/null || true
  "$STARSHIP_BIN" --version | head -n1
}

# A functional test: render a prompt with the given config, and require no warnings on stderr.
config_renders_cleanly() {
  local cfg="$1" err
  err="$(STARSHIP_CONFIG="$cfg" "$STARSHIP_BIN" prompt 2>&1 >/dev/null)" || return 1
  [[ -z "$err" ]]
}

write_configs() {
  log_header "Configuration"
  nb_ensure_conf_dirs
  install -d -o "$REAL_USER" -g "$REAL_USER" -m 0755 "${HOME_DIR}/.config"
  local tmp_dir; tmp_dir="$(mktemp -d)"
  local raw="${tmp_dir}/preset.toml" patched="${tmp_dir}/patched.toml"
  # Produced by the installed binary: always matches its version and needs no extra download.
  if "$STARSHIP_BIN" preset "$STARSHIP_PRESET" -o "$raw" 2>/dev/null; then
    if python3 "${HELPER_DIR}/helper_starship_patch.py" "$raw" "$patched" "$STARSHIP_PALETTE" "$STARSHIP_CMD_TIMEOUT" "$STARSHIP_SCAN_TIMEOUT" \
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

  write_file "$ROOT_STARSHIP_CONFIG" root root 0644 "$(render "$ROOT_TOML" TIMESTAMP="$FILENAME_TIMESTAMP")"
}

install_snippet() {
  log_header "Snippet and updater"
  nb_install_conf common 40-starship.zsh "$(render "$SNIPPET_STARSHIP" ROOT_CONFIG="$ROOT_STARSHIP_CONFIG")"
  nb_install_updater 20-starship.sh "$(render "$UPDATER_STARSHIP" BIN="$STARSHIP_BIN" REPO="$STARSHIP_REPO" \
      ASSET="$STARSHIP_ASSET_TEMPLATE" DAYS="$RELEASE_MIN_AGE_DAYS")"
  nb_ensure_update_runner
  log_success "Snippet 40-starship.zsh and updater 20-starship.sh installed"
}

#########################################################
# Security
#########################################################
apply_security() {
  log_header "Security"
  if has_cmd restorecon; then
    restorecon -RF "$NB_ZSH_SHARED_DIR" "$NB_LIB_DIR" 2>/dev/null || true
    [[ ! -x "$STARSHIP_BIN" ]] || restorecon -F "$STARSHIP_BIN" 2>/dev/null || true
    log_success "SELinux labels restored"
  fi
  # Starship sends no telemetry and listens on no port: no firewalld/ClamAV rules are needed.
}

#########################################################
# Verification
#########################################################
verify_setup() {
  nb_verify_begin
  if [[ -x "$STARSHIP_BIN" ]]; then
    check "starship binary is root-owned" test "$(stat -c %U "$STARSHIP_BIN")" = "root"
    check "starship binary is not group/other-writable" test -z "$(find "$STARSHIP_BIN" -perm /022)"
    check "starship runs" "$STARSHIP_BIN" --version
    check "user config renders without warnings" config_renders_cleanly "$USER_STARSHIP_CONFIG"
    check "user config uses palette ${STARSHIP_PALETTE}" grep -q "^palette = '${STARSHIP_PALETTE}'" "$USER_STARSHIP_CONFIG"
    check "root config renders without warnings" config_renders_cleanly "$ROOT_STARSHIP_CONFIG"
    check "root config is root-owned" test "$(stat -c %U "$ROOT_STARSHIP_CONFIG")" = "root"
  else
    nb_verify_warn "Starship is not installed: the agnoster fallback theme is active"
  fi
  check "user config exists and is owned by ${REAL_USER}" test "$(stat -c %U "$USER_STARSHIP_CONFIG")" = "$REAL_USER"
  check "snippet passes zsh syntax check" zsh -n "${NB_CONF_COMMON_DIR}/40-starship.zsh"
  check "updater installed: 20-starship.sh" test -x "${NB_UPDATERS_DIR}/20-starship.sh"
  check "user shell starts without errors" nb_user_zsh_starts_clean
  nb_verify_end
}

#########################################################
# Main
#########################################################
main() {
  nb_require_root "$0" "$@"
  nb_parse_common_options "$@"
  nb_reject_remaining_args
  infer_variables

  log_header "Starship setup"
  if [[ "$VERIFY_ONLY" == "true" ]]; then
    verify_setup || exit 1
    return
  fi

  require_fedora
  nb_prepare_script_dirs "$STARSHIP_BACKUP_DIR_BASE" "$STARSHIP_DOWNLOADS_DIR_BASE"
  backup_existing
  reset_existing
  if install_starship; then
    write_configs
    install_snippet
    apply_security
    verify_setup || true
    nb_notify "starship.sh finished on $(hostname)"
    log_header "Done"
    log_info "Open a new terminal (a Nerd Font is required for the glyphs). Backup: ${STARSHIP_CURRENT_BACKUP_DIR}"
  else
    # Not fatal for the shell: with no binary the zsh snippets select the agnoster theme.
    install_snippet
    log_error "Starship could not be installed (download, checksum or cooldown problem). Shells use agnoster instead."
    log_error "Re-run later: sudo bash starship.sh   (details: helper_github_release.sh warnings above)"
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
# * Install source: official release binary, not COPR and not `curl | sh`. Trust comparison: the release
#   binary is built by upstream CI (one party to trust); a COPR adds a third-party packager plus an extra
#   repository able to ship packages; `curl | sh` runs an unverified script as root. Fedora's repos have no
#   starship package. The checksum files come from the same GitHub project, so they protect against
#   corruption and post-upload tampering, not a compromised upstream; the cooldown (RELEASE_MIN_AGE_DAYS)
#   reduces that exposure. Starship publishes no signatures that this script could verify.
# * Config source: `starship preset catppuccin-powerline` (built into the binary, always matches its
#   version) instead of a hard-coded copy or a download of the website file. It is patched by
#   helper_starship_patch.py, which rebuilds the `format` and edits a few module sections using the preset's
#   own glyphs. If a patch marker is missing (the preset changed upstream) the script falls back to the
#   unmodified preset, and if that fails to the minimal config. Every candidate is validated by parsing the
#   TOML and rendering a prompt with no warnings.
# * Why "tags" for optional segments: with continuous powerline arrows, a hidden segment leaves arrows of the
#   wrong colors behind (the unmodified preset shows a stack of thin arrows outside git repos). Each optional
#   group is wrapped in ( ... ), which Starship omits entirely when every module inside is empty, and has its
#   own arrow caps.
# * Palettes: catppuccin_mocha is the default. The preset also defines catppuccin_frappe/macchiato/latte and
#   ayu_mirage/ayu_dark/ayu_light; exactly one is active via `palette = '...'`. Change the variable at the top
#   and re-run, or edit the line in ~/.config/starship.toml (changes apply to the next prompt).
# * Command duration: shown for the PREVIOUS command at the end of the next prompt (Starship cannot print it
#   on the command's own line without a right prompt, which would be copied along with terminal output).
# * Sharing with bash: ~/.config/starship.toml is shell independent; bash.sh only needs
#   `eval "$(starship init bash)"`. Termux: `pkg install starship` and sync the toml (Syncthing).
# * Starship sends no telemetry. The `starship preset` and `prompt` commands make no network requests.

#########################################################
# Troubleshooting/Debugging
#########################################################
# Health check:             sudo bash starship.sh --verify-setup
# Explain the prompt:       starship explain ; starship timings ; starship config
# Verbose log:              STARSHIP_LOG=trace starship prompt
# Slow in a huge repo:      raise scan_timeout/command_timeout at the top of ~/.config/starship.toml, or set
#                           `disabled = true` under [git_status].
# Broken symbols/boxes:     the terminal font must be a Nerd Font (fonts.sh), e.g. JetBrainsMono Nerd Font.
# Prompt is agnoster:       `command -v starship` is empty: run this script again and read the warnings.
# AWS/cloud segment:        shows only with AWS_PROFILE / AWS_REGION set: `AWS_PROFILE=dev zsh -ic ''` to test.
#                           Enable gcloud/azure/kubernetes yourself under their [section]; they are always-on by nature.
# Switch palette:           sed -i "s/^palette = .*/palette = 'ayu_dark'/" ~/.config/starship.toml
# Update by hand:           sudo /usr/local/lib/nb/updaters.d/20-starship.sh ; journalctl -u nb-update-tools.service -e
# Cooldown skipped warning: the GitHub API was unreachable (rate limit/proxy): the installer used the latest
#                           release without the cooldown. Re-run later or lower RELEASE_MIN_AGE_DAYS to 0.
# Roll back:                backups mirror real paths under ~/nb/nb_script_data/backups/starship/starship_<timestamp>/
