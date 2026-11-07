#!/usr/bin/env bash
#########################################################
# Useful Links
#########################################################
# Oh My Zsh repo ....................... https://github.com/ohmyzsh/ohmyzsh
# Plugin list .......................... https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins
# Customization (custom/plugins first) . https://github.com/ohmyzsh/ohmyzsh/wiki/Customization
# zsh-autosuggestions / highlighting ... https://github.com/zsh-users/zsh-autosuggestions , https://github.com/zsh-users/zsh-syntax-highlighting
# fzf-tab (needs compinit, before widget-wrapping plugins) ... https://github.com/Aloxaf/fzf-tab
# zsh-completions ...................... https://github.com/zsh-users/zsh-completions
# Why the tree is root-owned (root also loads it) ... https://github.com/zsh-users/zsh-completions/issues/680
# systemd sandboxing / SELinux ......... https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html ,
#                                        https://docs.fedoraproject.org/en-US/quick-docs/selinux-getting-started/
#
#########################################################
# Description
#########################################################
# Installs ONE shared, root-owned Oh My Zsh tree in /usr/local/share/zsh-nb/oh-my-zsh, used by the
# normal user AND root. Per-user state (caches, completion dump, history) stays in each home.
#
# It installs three drop-in snippets (see helper_nb_dropins.sh):
#   conf.d/10-omz.zsh            core: theme choice, plugin list, `source oh-my-zsh.sh`
#   conf.d/20-plugins.zsh        fzf-tab, zsh-autosuggestions (after OMZ's compinit, in the required order)
#   conf.d/90-highlighting.zsh   zsh-syntax-highlighting (must be the LAST thing sourced)
# and one updater: updaters.d/10-omz.sh (OMZ + the cloned plugins).
#
# Plugins are chosen when the shell STARTS (e.g. "docker" appears when the docker command exists), so
# installing or removing a tool needs no change here. zsh-autosuggestions and zsh-syntax-highlighting are
# bundled inside Oh My Zsh now; only fzf-tab and zsh-completions are cloned separately.
#
# Prompt: the snippet uses Starship when it is installed, else the "agnoster" theme (decided per shell start).
#
# NAMED OPTIONS
#   --verify-setup        Only run the Verification section (no changes are made).
#   --timestamp <value>   Timestamp used in backup/download directory names.
#                         Default: current time (YYYY-MM-DD_HH-MM-SS).
#   -h | --help           Show usage.
#
# SAMPLE CALLS (assuming the caller has the same variable names)
#   With all options:
#     sudo REAL_USER="$REAL_USER" bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/omz.sh" --timestamp "$FILENAME_TIMESTAMP"
#   With only mandatory options (there are none):
#     sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/omz.sh"
#   Verification only:
#     sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/omz.sh" --verify-setup
#
# REQUIRED HELPER FILES (in $SYSUPDATE_CODE_BASE_DIR/linux/commonh/)
#   helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh
#   get_*.sh system detection scripts. Run zsh.sh first.

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

HELPER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commonh"
for _f in helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh; do
  [[ -r "${HELPER_DIR}/${_f}" ]] || { echo "Missing helper file: ${HELPER_DIR}/${_f}" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "${HELPER_DIR}/${_f}"
done
unset _f
nb_require_functions backup_path_parents nb_install_conf nb_install_updater nb_ensure_update_runner render write_file
trap 'log_error "Unexpected failure at line ${LINENO}: ${BASH_COMMAND}"' ERR

# --- Script specific ---
OMZ_DIR="${NB_ZSH_SHARED_DIR}/oh-my-zsh"
OMZ_REPO_URL="https://github.com/ohmyzsh/ohmyzsh.git"
# Format: "directory-name|git-url". Cloned into OMZ's custom/plugins. (autosuggestions and
# syntax-highlighting are NOT listed: Oh My Zsh bundles them.)
EXTERNAL_PLUGINS=(
  "fzf-tab|https://github.com/Aloxaf/fzf-tab.git"
  "zsh-completions|https://github.com/zsh-users/zsh-completions.git"
)
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
# 10-omz.zsh - Oh My Zsh core. Installed by omz.sh (root-owned: re-run omz.sh to change it).
_nb_omz="@OMZ_DIR@"
[[ -r "$_nb_omz/oh-my-zsh.sh" ]] || { unset _nb_omz; return 0; }
export ZSH="$_nb_omz"; unset _nb_omz
export ZSH_CUSTOM="$ZSH/custom"
# OMZ writes caches. The shared tree is read-only for users, so caches go to the user's own cache dir.
export ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh"
[[ -d "$ZSH_CACHE_DIR/completions" ]] || mkdir -p "$ZSH_CACHE_DIR/completions"

# Prompt: Starship when installed (it draws the prompt, so OMZ's theme stays empty), otherwise agnoster.
# Decided at every shell start, so removing Starship later degrades gracefully.
if (( $+commands[starship] )); then
  ZSH_THEME=""
else
  ZSH_THEME="agnoster"
fi

# Updates are done by root (nb-update-tools). OMZ's own updater cannot write to the shared tree, and
# disabling it also stops OMZ from contacting GitHub when a shell starts.
zstyle ':omz:update' mode disabled

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
# the next shell; uninstall it and the plugin disappears. Root and low-RAM machines skip this block.
if (( EUID != 0 )) && [[ "@RAM_PROFILE@" != low ]]; then
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
# 10-omz.sh - updates Oh My Zsh and the cloned plugins. Installed by omz.sh. Owned by root.
set -Eeuo pipefail
SHARED="@SHARED@"
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

for dir in "${SHARED}/oh-my-zsh" "${SHARED}"/oh-my-zsh/custom/plugins/*; do
  if ! update_repo "$dir"; then
    echo "WARNING: could not update ${dir}" >&2
    failures=$((failures + 1))
  fi
done

# Normalize ownership/permissions (git may create group/other-writable files) and SELinux labels.
chown -R root:root "${SHARED}/oh-my-zsh"
chmod -R go-w "${SHARED}/oh-my-zsh"
if command -v restorecon >/dev/null 2>&1; then restorecon -RF "${SHARED}/oh-my-zsh" >/dev/null 2>&1 || true; fi

# Scan what was just fetched when the ClamAV daemon is running (cheap: the database is loaded).
if command -v clamdscan >/dev/null 2>&1 && systemctl is-active --quiet clamd@scan 2>/dev/null; then
  clamdscan --fdpass --infected --no-summary "${SHARED}/oh-my-zsh" || { echo "WARNING: ClamAV reported a problem" >&2; failures=$((failures + 1)); }
fi

(( failures == 0 ))
EOF

#########################################################
# Backup
#########################################################
backup_existing() {
  log_header "Backup"
  mkdir -p "$OMZ_CURRENT_BACKUP_DIR"
  local -a paths=(
    "${HOME_DIR}/.oh-my-zsh" "/root/.oh-my-zsh" "${OMZ_DIR}"
    "${HOME_DIR}/.cache/oh-my-zsh" "${HOME_DIR}"/.zcompdump*
    "${NB_CONF_COMMON_DIR}/10-omz.zsh" "${NB_CONF_COMMON_DIR}/20-plugins.zsh" "${NB_CONF_COMMON_DIR}/90-highlighting.zsh"
    "${NB_UPDATERS_DIR}/10-omz.sh"
  )
  local f
  for f in "${paths[@]}"; do backup_path_parents "$f" "$OMZ_CURRENT_BACKUP_DIR"; done
  chown -R "${REAL_USER}:${REAL_USER}" "$OMZ_BACKUP_DIR_BASE"
  chmod 0700 "$OMZ_CURRENT_BACKUP_DIR"
  log_success "Backup written to ${OMZ_CURRENT_BACKUP_DIR}"
}

#########################################################
# Reset
#########################################################
reset_existing() {
  log_header "Reset"
  rm -rf "${HOME_DIR}/.oh-my-zsh" "/root/.oh-my-zsh" "${OMZ_DIR}"
  rm -rf "${HOME_DIR}/.cache/oh-my-zsh" "/root/.cache/oh-my-zsh"
  rm -f  "${HOME_DIR}"/.zcompdump* /root/.zcompdump*
  nb_remove_conf common 10-omz.zsh
  nb_remove_conf common 20-plugins.zsh
  nb_remove_conf common 90-highlighting.zsh
  nb_remove_updater 10-omz.sh
  log_success "Previous Oh My Zsh setup removed"
}

#########################################################
# Install
#########################################################
require_zsh() {
  has_cmd zsh || log_die "zsh is not installed. Run zsh.sh first."
  has_cmd git || log_die "git is not installed. Run zsh.sh (or git.sh) first."
}

# Cloning happens inside SCRIPT_DATA_DOWNLOADS, which has on-access ClamAV scanning, so no extra
# clamscan run is needed. The scanned clone is then copied to its final place.
install_omz() {
  log_header "Oh My Zsh (shared, root-owned)"
  mkdir -p "$OMZ_CURRENT_DOWNLOADS_DIR"
  # --depth=1: only the newest commit; much smaller and faster.
  git clone --quiet --depth=1 "$OMZ_REPO_URL" "${OMZ_CURRENT_DOWNLOADS_DIR}/ohmyzsh" || log_die "Could not clone Oh My Zsh"
  nb_ensure_conf_dirs
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

  # Root owns everything, nobody else can write: the shells of ALL accounts (including root) execute
  # these files. If a normal user could modify them, they could run code as root.
  chown -R root:root "$OMZ_DIR"
  chmod -R go-w "$OMZ_DIR"
  chmod 0755 "$OMZ_DIR"
  chown -R "${REAL_USER}:${REAL_USER}" "$OMZ_DOWNLOADS_DIR_BASE"
  log_success "Oh My Zsh $(git -C "$OMZ_DIR" rev-parse --short HEAD) installed at ${OMZ_DIR}"
}

install_snippets() {
  log_header "Snippets and updater"
  nb_install_conf common 10-omz.zsh "$(render "$SNIPPET_OMZ" OMZ_DIR="$OMZ_DIR" VSCODE_BINARY="$VSCODE_BINARY" \
      BGNOTIFY_THRESHOLD="$BGNOTIFY_THRESHOLD" ENABLE_BGNOTIFY="$ENABLE_BGNOTIFY" RAM_PROFILE="$RAM_PROFILE")"
  nb_install_conf common 20-plugins.zsh "$(render "$SNIPPET_PLUGINS" AUTOSUGGEST_STRATEGY="$AUTOSUGGEST_STRATEGY" \
      AUTOSUGGEST_BUFFER_MAX="$AUTOSUGGEST_BUFFER_MAX")"
  nb_install_conf common 90-highlighting.zsh "$(render "$SNIPPET_HIGHLIGHT" HIGHLIGHTERS="$HIGHLIGHTERS")"
  nb_install_updater 10-omz.sh "$(render "$UPDATER_OMZ" SHARED="$NB_ZSH_SHARED_DIR")"
  nb_ensure_update_runner
  log_success "Snippets 10/20/90 and updater 10-omz.sh installed"
}

#########################################################
# Security
#########################################################
apply_security() {
  log_header "Security"
  if has_cmd restorecon; then
    restorecon -RF "$NB_ZSH_SHARED_DIR" "$NB_LIB_DIR" 2>/dev/null || true
    log_success "SELinux labels restored"
  fi
  chown -R root:root "$NB_ZSH_SHARED_DIR"
  chmod -R go-w "$NB_ZSH_SHARED_DIR"
}

#########################################################
# Verification
#########################################################
zsh_function_exists() {
  # zsh_function_exists <function-name>: is it defined in a fresh interactive shell of the user?
  [[ "$(runuser -l "$REAL_USER" -c "zsh -i -c 'print \${+functions[$1]}'" 2>/dev/null </dev/null | tail -n1)" == "1" ]]
}

verify_setup() {
  nb_verify_begin
  check "Oh My Zsh is present" test -f "${OMZ_DIR}/oh-my-zsh.sh"
  check "bundled plugin: zsh-autosuggestions" test -f "${OMZ_DIR}/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh"
  check "bundled plugin: zsh-syntax-highlighting" test -f "${OMZ_DIR}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh"
  local entry name
  for entry in "${EXTERNAL_PLUGINS[@]}"; do
    name="${entry%%|*}"
    check "cloned plugin present: ${name}" test -d "${OMZ_DIR}/custom/plugins/${name}"
  done
  check "shared tree is root-owned and not group/other-writable" nb_tree_is_locked "$OMZ_DIR" "$NB_CONF_COMMON_DIR"
  local f
  for f in 10-omz.zsh 20-plugins.zsh 90-highlighting.zsh; do
    check "snippet passes zsh syntax check: ${f}" zsh -n "${NB_CONF_COMMON_DIR}/${f}"
  done
  check "updater installed: 10-omz.sh" test -x "${NB_UPDATERS_DIR}/10-omz.sh"
  check "user shell starts without errors (no missing plugins)" nb_user_zsh_starts_clean
  check "compaudit reports no insecure directories" nb_compaudit_is_clean
  check "autosuggestions is active in a new shell" zsh_function_exists _zsh_autosuggest_start
  check "syntax highlighting is active in a new shell" zsh_function_exists _zsh_highlight
  if has_cmd fzf; then
    check "fzf-tab is active in a new shell" zsh_function_exists fzf-tab-complete
  fi
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

  log_header "Oh My Zsh setup"
  if [[ "$VERIFY_ONLY" == "true" ]]; then
    verify_setup || exit 1
    return
  fi

  require_fedora
  require_zsh
  nb_prepare_script_dirs "$OMZ_BACKUP_DIR_BASE" "$OMZ_DOWNLOADS_DIR_BASE"
  backup_existing
  reset_existing
  install_omz
  install_snippets
  apply_security
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
# * zsh-autosuggestions and zsh-syntax-highlighting are bundled in Oh My Zsh (verified in a fresh clone,
#   plugins/ directory). The previous version cloned them again into custom/plugins, which silently
#   shadowed the bundled copies. They are now sourced from $ZSH/plugins directly. They are NOT listed in
#   plugins=(...) because load order matters (see below).
# * Order inside one shell: 10 omz (runs compinit) -> 20 fzf-tab then autosuggestions -> 30 tools ->
#   40 prompt -> 50 atuin -> 90 syntax-highlighting. fzf-tab must come after compinit and before the
#   widget-wrapping plugins; highlighting must be last. Listing them in plugins=() would load them BEFORE
#   compinit and break that order. The previous version's second `compinit` call (slow: re-scans every
#   completion file) is gone.
# * Plugins by tool: the table in 10-omz.zsh maps a command to plugin names and is evaluated at shell
#   start. Add a line there (or re-run this script after editing the template) to support another tool.
# * Root gets the base plugins only, and no tool plugins: its shell stays small and predictable.
# * Oh My Zsh's own updater is disabled (the tree is root-owned and read-only for users). Updating is
#   done by updaters.d/10-omz.sh through nb-update-tools: `git fetch --depth=1` + `reset --hard FETCH_HEAD`.
# * Plugins considered and dropped (compared with the original script): yum (alias for dnf), pep8/autopep8
#   (obsolete), branch (the prompt shows the branch), gitignore (queries an online service on every use),
#   zsh-interactive-cd (overlaps fzf-tab), history/history-substring-search (autosuggestions + fzf/Atuin
#   cover it), safe-paste (zsh 5.1+ has bracketed paste), timer/emoji/screen (unused), thefuck.
# * bgnotify on Wayland: the plugin decides whether a command ran in the focused window with X11 tools, so
#   on Wayland it may notify even when the terminal is focused. Set ENABLE_BGNOTIFY=false then.
# * agnoster fallback: no SSH override and no right prompt (a right prompt text gets copied along with
#   terminal output).
# * Rolling back: backups mirror real paths under ~/nb/nb_script_data/backups/omz/omz_<timestamp>/.

#########################################################
# Troubleshooting/Debugging
#########################################################
# Health check:            sudo bash omz.sh --verify-setup
# Active plugins:          print -l $plugins ; ls /usr/local/share/zsh-nb/oh-my-zsh/plugins | head
# "plugin 'x' not found":  the name does not exist in this OMZ version; the filter in 10-omz.zsh normally removes it.
# Prompt is agnoster:      `command -v starship` is empty (starship.sh not run or failed). That is the designed fallback.
# Autosuggestions silent:  echo $ZSH_AUTOSUGGEST_STRATEGY ; the terminal must render a dim grey foreground.
# fzf-tab not active:      type fzf must succeed; `zle -la | grep fzf-tab`; it must be sourced BEFORE autosuggestions.
# Highlighting missing:    must be the last snippet: ls /usr/local/share/zsh-nb/conf.d (90-highlighting.zsh last).
# Slow startup:            zsh -ixc exit 2>&1 | less ; zprof (see zsh.sh Troubleshooting).
# Updating by hand:        sudo /usr/local/lib/nb/updaters.d/10-omz.sh ; journalctl -u nb-update-tools.service -e
# Permissions / SELinux:   sudo find /usr/local/share/zsh-nb \( -perm -g+w -o -perm -o+w \) ! -type l ; sudo restorecon -Rv /usr/local/share/zsh-nb
