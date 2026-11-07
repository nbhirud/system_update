#!/usr/bin/env bash
#########################################################
# Useful Links
#########################################################
# Oh My Zsh repo ....................... https://github.com/ohmyzsh/ohmyzsh
# Plugin list .......................... https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins
# Customization (custom/plugins first) . https://github.com/ohmyzsh/ohmyzsh/wiki/Customization
# Update settings (mode, frequency) .... https://github.com/ohmyzsh/ohmyzsh#getting-updates
# zsh-autosuggestions / highlighting ... https://github.com/zsh-users/zsh-autosuggestions , https://github.com/zsh-users/zsh-syntax-highlighting
# fzf-tab (needs compinit, before widget-wrapping plugins) ... https://github.com/Aloxaf/fzf-tab
# zsh-completions ...................... https://github.com/zsh-users/zsh-completions
#
#########################################################
# Description
#########################################################
# Installs Oh My Zsh the normal per-user way: a git clone in ~/.oh-my-zsh, owned by you. `omz update` works, and
# Oh My Zsh's own auto-update is on (OMZ_UPDATE_MODE below).
#
# It installs three drop-in snippets in ~/.config/zsh/conf.d (sourced by ~/.zshrc, see zsh.sh):
#   10-omz.zsh            core: theme choice, plugin list, update settings, `source oh-my-zsh.sh`
#   20-plugins.zsh        fzf-tab, zsh-autosuggestions (after OMZ's compinit, in the required order)
#   90-highlighting.zsh   zsh-syntax-highlighting (must be the LAST thing sourced)
# and one updater: updater 10-omz-plugins.sh for the cloned plugins (`omz update` does not update those).
#
# Plugins are chosen when the shell STARTS (e.g. "docker" appears when the docker command exists), so installing or
# removing a tool needs no change here. zsh-autosuggestions and zsh-syntax-highlighting are bundled inside Oh My Zsh;
# only fzf-tab and zsh-completions are cloned separately into ~/.oh-my-zsh/custom/plugins.
#
# Prompt: the snippet uses Starship when it is installed, else the "agnoster" theme (decided per shell start).
#
# This script needs NO root: started with sudo it re-runs itself as your user.
#
# NAMED OPTIONS
#   --verify-setup        Only run the Verification section (no changes are made).
#   --timestamp <value>   Timestamp used in backup/download directory names.
#                         Default: current time (YYYY-MM-DD_HH-MM-SS).
#   -h | --help           Show usage.
#
# SAMPLE CALLS (assuming the caller has the same variable names)
#   With all options:
#     bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/omz.sh" --timestamp "$FILENAME_TIMESTAMP"
#   With only mandatory options (there are none):
#     bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/omz.sh"
#   Verification only:
#     bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/omz.sh" --verify-setup
#
# REQUIRED HELPER FILES (helpers in $HELPER_DIR = $SYSUPDATE_CODE_BASE_DIR/linux/commonh/, getters in $GETTERS_DIR = .../linux/commong/)
#   helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh
#   get_*.sh system detection scripts. Run zsh.sh first (zsh, git and the .zshrc loader).

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
OMZ_DOWNLOADS_DIR_BASE="${SCRIPT_DATA_DOWNLOADS}/omz"
OMZ_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/omz"

# Where the helper_*.sh files and the get_*.sh detection scripts live (overridable from the environment).
HELPER_DIR="${HELPER_DIR:-${SYSUPDATE_CODE_BASE_DIR}/linux/commonh}"     # helper_*.sh / helper_*.py
GETTERS_DIR="${GETTERS_DIR:-${SYSUPDATE_CODE_BASE_DIR}/linux/commong}"   # get_*.sh system detection scripts
for _f in helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh; do
  [[ -r "${HELPER_DIR}/${_f}" ]] || { echo "Missing helper file: ${HELPER_DIR}/${_f}" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "${HELPER_DIR}/${_f}"
done
unset _f
nb_require_functions backup_path_parents nb_mkdir nb_install_conf nb_remove_conf nb_install_updater nb_remove_updater nb_ensure_update_runner render write_file nb_zsh_function_exists
trap 'log_error "Unexpected failure at line ${LINENO}: ${BASH_COMMAND}"' ERR

# --- Script specific ---
OMZ_DIR="${HOME_DIR}/.oh-my-zsh"
OMZ_REPO_URL="https://github.com/ohmyzsh/ohmyzsh.git"
# Format: "directory-name|git-url". Cloned into ~/.oh-my-zsh/custom/plugins. (autosuggestions and
# syntax-highlighting are NOT listed: Oh My Zsh bundles them.)
EXTERNAL_PLUGINS=(
  "fzf-tab|https://github.com/Aloxaf/fzf-tab.git"
  "zsh-completions|https://github.com/zsh-users/zsh-completions.git"
)
OMZ_UPDATE_MODE="auto"       # auto = update silently every OMZ_UPDATE_FREQUENCY days | reminder | disabled
OMZ_UPDATE_FREQUENCY=7       # days between automatic update checks (contacts GitHub when it runs)
VSCODE_BINARY="codium"       # value of $VSCODE for the OMZ vscode plugin (code | code-insiders | codium | cursor)
ENABLE_BGNOTIFY=true         # desktop notification when a long command finishes (KDE + kdialog only)
BGNOTIFY_THRESHOLD=30        # seconds a command must run before a notification is sent
NTFY_URL=""                  # optional, e.g. https://ntfy.sh/<topic>

#########################################################
# Inferred variables
#########################################################
OMZ_CURRENT_BACKUP_DIR="" OMZ_CURRENT_DOWNLOADS_DIR=""
AUTOSUGGEST_STRATEGY="" AUTOSUGGEST_BUFFER_MAX="" HIGHLIGHTERS=""

infer_variables() {
  nb_infer_system
  OMZ_CURRENT_BACKUP_DIR="${OMZ_BACKUP_DIR_BASE}/omz_${FILENAME_TIMESTAMP}"
  OMZ_CURRENT_DOWNLOADS_DIR="${OMZ_DOWNLOADS_DIR_BASE}/omz_${FILENAME_TIMESTAMP}"
  # Low-RAM machines get the cheapest settings: the "completion" autosuggest strategy runs the
  # completion system on every keystroke (that is what makes old machines feel laggy), and each
  # extra highlighter adds work per keystroke.
  if [[ "$RAM_PROFILE" == "low" ]]; then
    AUTOSUGGEST_STRATEGY="history"; AUTOSUGGEST_BUFFER_MAX="20"; HIGHLIGHTERS="main"
  else
    AUTOSUGGEST_STRATEGY="history completion match_prev_cmd"; AUTOSUGGEST_BUFFER_MAX="50"
    HIGHLIGHTERS="main brackets pattern cursor"
  fi
}

#########################################################
# Templates
#########################################################
# shellcheck disable=SC2016  # the $ signs below are zsh syntax, not bash expansions
IFS= read -r -d '' SNIPPET_OMZ <<'EOF' || true
# 10-omz.zsh - Oh My Zsh core. Installed by omz.sh (re-run omz.sh to regenerate; edit freely if you prefer).
export ZSH="$HOME/.oh-my-zsh"
[[ -r "$ZSH/oh-my-zsh.sh" ]] || { unset ZSH; return 0; }
export ZSH_CUSTOM="$ZSH/custom"

# Prompt: Starship when installed (it draws the prompt, so OMZ's theme stays empty), otherwise agnoster.
# Decided at every shell start, so removing Starship later degrades gracefully.
if (( $+commands[starship] )); then
  ZSH_THEME=""
else
  ZSH_THEME="agnoster"
fi

# Oh My Zsh's own updater: `omz update` works, and this checks automatically.
zstyle ':omz:update' mode @OMZ_UPDATE_MODE@
zstyle ':omz:update' frequency @OMZ_UPDATE_FREQUENCY@

ENABLE_CORRECTION="true"
COMPLETION_WAITING_DOTS="true"

# Extra completion definitions (zsh-completions); must be in fpath BEFORE compinit runs inside OMZ.
fpath+=("$ZSH_CUSTOM/plugins/zsh-completions/src")

VSCODE=@VSCODE_BINARY@          # used by the OMZ vscode plugin
bgnotify_threshold=@BGNOTIFY_THRESHOLD@

# Base plugins (always).
plugins=(git sudo colored-man-pages command-not-found)
(( $+commands[dnf] )) && plugins+=(dnf)

# Tool plugins: added only when the tool exists NOW. Install docker later and its plugin appears in
# the next shell; uninstall it and the plugin disappears. Low-RAM machines skip this block.
if [[ "@RAM_PROFILE@" != low ]]; then
  typeset -A _nb_tool_plugins=(
    python3       "python pip"
    firewall-cmd  firewalld
    uv            uv
    gh            gh
    docker        "docker docker-compose"
    podman        podman
    aws           aws
    kubectl       kubectl
    helm          helm
    cargo         rust
    psql          postgres
    tailscale     tailscale
    $VSCODE       vscode
  )
  for _nb_tool _nb_plug in ${(kv)_nb_tool_plugins}; do
    (( $+commands[$_nb_tool] )) && plugins+=( ${=_nb_plug} )
  done
  plugins+=(ssh)
  # bgnotify needs a desktop notifier: kdialog on KDE. Not useful on servers (no display).
  if [[ "@ENABLE_BGNOTIFY@" == true ]] && (( $+commands[kdialog] )) \
     && [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" && "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]]; then
    plugins+=(bgnotify)
  fi
  unset _nb_tool_plugins _nb_tool _nb_plug
fi

# Keep only plugins that exist in this OMZ version: OMZ prints a warning on EVERY shell start for a
# missing plugin. (u) removes duplicates.
_nb_ok=()
for _nb_p in ${(u)plugins}; do
  [[ -d "$ZSH/plugins/$_nb_p" || -d "$ZSH_CUSTOM/plugins/$_nb_p" ]] && _nb_ok+=($_nb_p)
done
plugins=($_nb_ok)
unset _nb_ok _nb_p

source "$ZSH/oh-my-zsh.sh"
EOF

# shellcheck disable=SC2016
IFS= read -r -d '' SNIPPET_PLUGINS <<'EOF' || true
# 20-plugins.zsh - plugins that must load AFTER OMZ ran compinit. Installed by omz.sh.
[[ -n "${ZSH:-}" && -r "$ZSH/oh-my-zsh.sh" ]] || return 0

# Order matters: fzf-tab first (it must wrap completion before widget-wrapping plugins), then
# autosuggestions. syntax-highlighting is loaded last, by 90-highlighting.zsh.
ZSH_AUTOSUGGEST_STRATEGY=(@AUTOSUGGEST_STRATEGY@)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=@AUTOSUGGEST_BUFFER_MAX@

if (( $+commands[fzf] )) && [[ -r "$ZSH_CUSTOM/plugins/fzf-tab/fzf-tab.plugin.zsh" ]]; then
  # fzf-tab replaces the completion menu with fzf; these two zstyles are recommended by its README.
  zstyle ':completion:*' menu no
  zstyle ':completion:*:descriptions' format '[%d]'
  source "$ZSH_CUSTOM/plugins/fzf-tab/fzf-tab.plugin.zsh"
fi

# Bundled with Oh My Zsh (no separate clone).
[[ -r "$ZSH/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh" ]] \
  && source "$ZSH/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh"
EOF

# shellcheck disable=SC2016
IFS= read -r -d '' SNIPPET_HIGHLIGHT <<'EOF' || true
# 90-highlighting.zsh - zsh-syntax-highlighting. Installed by omz.sh.
# It MUST be the last thing sourced: it wraps widgets that other plugins define, so anything loaded
# after it would not be highlighted (its README requires this).
[[ -n "${ZSH:-}" && -r "$ZSH/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh" ]] || return 0
ZSH_HIGHLIGHT_HIGHLIGHTERS=(@HIGHLIGHTERS@)
ZSH_HIGHLIGHT_MAXLENGTH=300
source "$ZSH/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh"
EOF

# shellcheck disable=SC2016
IFS= read -r -d '' UPDATER_OMZ <<'EOF' || true
#!/usr/bin/env bash
# 10-omz-plugins.sh - updates the plugins CLONED into ~/.oh-my-zsh/custom/plugins (fzf-tab, zsh-completions).
# Oh My Zsh itself is updated by `omz update` / its auto-update, not here. Installed by omz.sh; runs as you.
set -Eeuo pipefail
PLUGINS="@OMZ_DIR@/custom/plugins"
failures=0

# Shallow repos: fetch only the newest commit of the current branch, then move the tree to it.
update_repo() {
  local dir="$1" branch
  [[ -d "${dir}/.git" ]] || return 0
  branch="$(git -C "$dir" symbolic-ref --short HEAD)" || return 1
  git -C "$dir" fetch --quiet --depth=1 origin "$branch" || return 1
  git -C "$dir" reset --hard --quiet FETCH_HEAD || return 1
  echo "updated $(basename "$dir") -> $(git -C "$dir" rev-parse --short HEAD)"
}

[[ -d "$PLUGINS" ]] || { echo "no custom plugins directory; skipping"; exit 0; }
for dir in "$PLUGINS"/*; do
  if ! update_repo "$dir"; then
    echo "WARNING: could not update ${dir}" >&2
    failures=$((failures + 1))
  fi
done
(( failures == 0 ))
EOF

#########################################################
# Backup
#########################################################
backup_existing() {
  log_header "Backup"
  mkdir -p "$OMZ_CURRENT_BACKUP_DIR"
  local -a paths=(
    "${OMZ_DIR}" "${HOME_DIR}/.cache/oh-my-zsh" "${HOME_DIR}"/.zcompdump*
    "${NB_ZSH_CONF_DIR}/10-omz.zsh" "${NB_ZSH_CONF_DIR}/20-plugins.zsh" "${NB_ZSH_CONF_DIR}/90-highlighting.zsh"
    "${NB_UPDATERS_DIR}/10-omz-plugins.sh"
  )
  local f
  for f in "${paths[@]}"; do backup_path_parents "$f" "$OMZ_CURRENT_BACKUP_DIR"; done
  chmod 0700 "$OMZ_CURRENT_BACKUP_DIR"
  log_success "Backup written to ${OMZ_CURRENT_BACKUP_DIR}"
}

#########################################################
# Reset
#########################################################
reset_existing() {
  log_header "Reset"
  rm -rf "${OMZ_DIR}" "${HOME_DIR}/.cache/oh-my-zsh"
  rm -f  "${HOME_DIR}"/.zcompdump*
  nb_remove_conf 10-omz.zsh
  nb_remove_conf 20-plugins.zsh
  nb_remove_conf 90-highlighting.zsh
  nb_remove_updater 10-omz-plugins.sh
  nb_remove_updater 10-omz.sh   # the updater of the earlier shared setup (it ran as root)
  log_success "Previous Oh My Zsh setup removed"
}

#########################################################
# Install
#########################################################
require_tools() {
  has_cmd zsh || log_die "zsh is not installed. Run zsh.sh first."
  has_cmd git || log_die "git is not installed. Run zsh.sh (or git.sh) first."
}

# Cloning happens inside SCRIPT_DATA_DOWNLOADS, which has on-access ClamAV scanning, so no extra
# clamscan run is needed. The scanned clone is then copied to its final place.
install_omz() {
  log_header "Oh My Zsh (~/.oh-my-zsh)"
  mkdir -p "$OMZ_CURRENT_DOWNLOADS_DIR"
  # --depth=1: only the newest commit (what the official installer does too); `omz update` works with it.
  git clone --quiet --depth=1 "$OMZ_REPO_URL" "${OMZ_CURRENT_DOWNLOADS_DIR}/ohmyzsh" || log_die "Could not clone Oh My Zsh"
  cp -a "${OMZ_CURRENT_DOWNLOADS_DIR}/ohmyzsh" "$OMZ_DIR"

  local entry name url
  mkdir -p "${OMZ_DIR}/custom/plugins"
  for entry in "${EXTERNAL_PLUGINS[@]}"; do
    name="${entry%%|*}"
    url="${entry#*|}"
    if git clone --quiet --depth=1 "$url" "${OMZ_CURRENT_DOWNLOADS_DIR}/${name}"; then
      cp -a "${OMZ_CURRENT_DOWNLOADS_DIR}/${name}" "${OMZ_DIR}/custom/plugins/${name}"
      log_success "plugin: ${name} ($(git -C "${OMZ_DIR}/custom/plugins/${name}" rev-parse --short HEAD))"
    else
      log_warn "Could not clone ${name}; the snippets skip it when missing"
    fi
  done
  # Plain user-owned directories: group/other must not be able to write (zsh's compaudit checks this).
  chmod -R go-w "$OMZ_DIR"
  log_success "Oh My Zsh $(git -C "$OMZ_DIR" rev-parse --short HEAD) installed at ${OMZ_DIR}"
}

install_snippets() {
  log_header "Snippets and updater"
  nb_install_conf 10-omz.zsh "$(render "$SNIPPET_OMZ" OMZ_UPDATE_MODE="$OMZ_UPDATE_MODE" OMZ_UPDATE_FREQUENCY="$OMZ_UPDATE_FREQUENCY" \
      VSCODE_BINARY="$VSCODE_BINARY" BGNOTIFY_THRESHOLD="$BGNOTIFY_THRESHOLD" ENABLE_BGNOTIFY="$ENABLE_BGNOTIFY" RAM_PROFILE="$RAM_PROFILE")"
  nb_install_conf 20-plugins.zsh "$(render "$SNIPPET_PLUGINS" AUTOSUGGEST_STRATEGY="$AUTOSUGGEST_STRATEGY" \
      AUTOSUGGEST_BUFFER_MAX="$AUTOSUGGEST_BUFFER_MAX")"
  nb_install_conf 90-highlighting.zsh "$(render "$SNIPPET_HIGHLIGHT" HIGHLIGHTERS="$HIGHLIGHTERS")"
  nb_install_updater 10-omz-plugins.sh "$(render "$UPDATER_OMZ" OMZ_DIR="$OMZ_DIR")"
  nb_ensure_update_runner
  log_success "Snippets 10/20/90 and updater 10-omz-plugins.sh installed"
}

#########################################################
# Verification
#########################################################
verify_setup() {
  nb_verify_begin
  check "Oh My Zsh is present" test -f "${OMZ_DIR}/oh-my-zsh.sh"
  check "Oh My Zsh is a git clone owned by ${REAL_USER}" test "$(stat -c %U "${OMZ_DIR}/.git")" = "$REAL_USER"
  check "bundled plugin: zsh-autosuggestions" test -f "${OMZ_DIR}/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh"
  check "bundled plugin: zsh-syntax-highlighting" test -f "${OMZ_DIR}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh"
  local entry name
  for entry in "${EXTERNAL_PLUGINS[@]}"; do
    name="${entry%%|*}"
    check "cloned plugin present: ${name}" test -d "${OMZ_DIR}/custom/plugins/${name}"
  done
  check "no group/other-writable files in ~/.oh-my-zsh" test -z "$(find "$OMZ_DIR" \( -perm -g+w -o -perm -o+w \) ! -type l -print -quit)"
  local f
  for f in 10-omz.zsh 20-plugins.zsh 90-highlighting.zsh; do
    check "snippet passes zsh syntax check: ${f}" zsh -n "${NB_ZSH_CONF_DIR}/${f}"
  done
  check "updater installed: 10-omz-plugins.sh" test -x "${NB_UPDATERS_DIR}/10-omz-plugins.sh"
  check "user shell starts without errors (no missing plugins)" nb_user_zsh_starts_clean
  check "compaudit reports no insecure directories" nb_compaudit_is_clean
  check "the omz command exists in a new shell (omz update works)" nb_zsh_function_exists omz
  check "autosuggestions is active in a new shell" nb_zsh_function_exists _zsh_autosuggest_start
  check "syntax highlighting is active in a new shell" nb_zsh_function_exists _zsh_highlight
  if has_cmd fzf; then
    check "fzf-tab is active in a new shell" nb_zsh_function_exists fzf-tab-complete
  fi
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

  log_header "Oh My Zsh setup"
  if [[ "$VERIFY_ONLY" == "true" ]]; then
    verify_setup || exit 1
    return
  fi

  require_tools
  nb_prepare_script_dirs "$OMZ_BACKUP_DIR_BASE" "$OMZ_DOWNLOADS_DIR_BASE"
  backup_existing
  reset_existing
  install_omz
  install_snippets
  verify_setup || true
  nb_notify "omz.sh finished on $(hostname)"
  log_header "Done"
  log_info "Open a new terminal. Backup: ${OMZ_CURRENT_BACKUP_DIR}"
}

main "$@"
exit $?

#########################################################
# Notes
#########################################################
# * Normal per-user install: ~/.oh-my-zsh owned by you, so `omz update` works. An earlier version used one shared
#   root-owned tree for the user and root; that was more hassle than value and is gone (zsh.sh removes the old tree).
# * Auto-update: `zstyle ':omz:update' mode auto` + `frequency 7` (set by OMZ_UPDATE_MODE / OMZ_UPDATE_FREQUENCY) make
#   Oh My Zsh update itself every 7 days when a shell starts; that contacts GitHub. Use `reminder` to be asked
#   instead, or `disabled` for none. `nbupdate` also runs `omz update -y`.
# * Cloned plugins (fzf-tab, zsh-completions) are not touched by `omz update`; nb-update-tools updates them.
# * zsh-autosuggestions and zsh-syntax-highlighting are bundled in Oh My Zsh (verified in a fresh clone). They are
#   sourced from $ZSH/plugins directly and are NOT listed in plugins=(...) because load order matters (below).
# * Order inside one shell: 10 omz (runs compinit) -> 20 fzf-tab then autosuggestions -> 30 tools -> 40 prompt ->
#   50 atuin -> 90 syntax-highlighting. fzf-tab must come after compinit and before the widget-wrapping plugins;
#   highlighting must be last. Listing them in plugins=() would load them BEFORE compinit and break that order.
# * Plugins by tool: the table in 10-omz.zsh maps a command to plugin names and is evaluated at shell start. Add a
#   line there to support another tool (the file is yours; re-running omz.sh regenerates it).
# * Plugins considered and dropped (compared with the original script): yum (alias for dnf), pep8/autopep8
#   (obsolete), branch (the prompt shows the branch), gitignore (queries an online service on every use),
#   zsh-interactive-cd (overlaps fzf-tab), history/history-substring-search (autosuggestions + fzf/Atuin cover it),
#   safe-paste (zsh 5.1+ has bracketed paste), timer/emoji/screen (unused), thefuck.
# * bgnotify on Wayland: the plugin decides whether a command ran in the focused window with X11 tools, so on
#   Wayland it may notify even when the terminal is focused. Set ENABLE_BGNOTIFY=false then.
# * agnoster fallback: no SSH override and no right prompt (right-prompt text gets copied with terminal output).
# * Rolling back: backups mirror real paths under ~/nb/nb_script_data/backups/omz/omz_<timestamp>/.

#########################################################
# Troubleshooting/Debugging
#########################################################
# Health check:            bash omz.sh --verify-setup
# Update Oh My Zsh:        omz update           (also: nbupdate)
# Active plugins:          print -l $plugins ; ls ~/.oh-my-zsh/plugins | head
# "plugin 'x' not found":  the name does not exist in this OMZ version; the filter in 10-omz.zsh normally removes it.
# Prompt is agnoster:      `command -v starship` is empty (starship.sh not run or failed). That is the designed fallback.
# Autosuggestions silent:  echo $ZSH_AUTOSUGGEST_STRATEGY ; the terminal must render a dim grey foreground.
# fzf-tab not active:      type fzf must succeed; `zle -la | grep fzf-tab`; it must be sourced BEFORE autosuggestions.
# Highlighting missing:    must be the last snippet: ls ~/.config/zsh/conf.d (90-highlighting.zsh last).
# Slow startup:            zsh -ixc exit 2>&1 | less ; zprof (see zsh.sh Troubleshooting).
# Update cloned plugins:   nb-update-tools   (or ~/.local/share/nb/updaters.d/10-omz-plugins.sh)
# compaudit warnings:      compaudit | xargs chmod g-w,o-w
