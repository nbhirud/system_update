#!/usr/bin/env bash
#########################################################
# Useful Links
#########################################################
# fzf (shell integration, `fzf --zsh`) .. https://github.com/junegunn/fzf#setting-up-shell-integration
# zoxide ................................ https://github.com/ajeetdsouza/zoxide
# eza / bat / ripgrep / fd .............. https://github.com/eza-community/eza , https://github.com/sharkdp/bat ,
#                                         https://github.com/BurntSushi/ripgrep , https://github.com/sharkdp/fd
# direnv ................................ https://direnv.net/
# fastfetch ............................. https://github.com/fastfetch-cli/fastfetch
# Fedora packages (dnf) ................. https://packages.fedoraproject.org/
#
#########################################################
# Description
#########################################################
# Installs the everyday CLI tools used by the shell, yazi, neovim and tmux setups, ONLY on machines whose
# RAM profile is listed in CLI_TOOLS_PROFILES (default: mid and high). On low-RAM machines the script does
# nothing but report that, and removes a snippet left by an earlier run.
#
#   fzf (fuzzy finder, Ctrl-T / Alt-C bindings, Ctrl-R until Atuin takes it over)   zoxide (`z` jumps)
#   eza (ls)   bat (cat with syntax highlighting)   ripgrep   fd-find   direnv   fastfetch
#
# Installs the drop-in snippet ~/.config/zsh/conf.d/30-tools.zsh (owned by you): integrations are activated only for
# tools that exist when the shell starts, so removing a tool never breaks the shell. All packages come from dnf
# (updated by the normal system update), so no updater is needed.
# Needs root only for dnf (it re-runs itself through sudo); the snippet is written for your user.
#
# NAMED OPTIONS
#   --verify-setup        Only run the Verification section (no changes are made).
#   --timestamp <value>   Timestamp used in backup/download directory names.
#                         Default: current time (YYYY-MM-DD_HH-MM-SS).
#   -h | --help           Show usage.
#
# SAMPLE CALLS (assuming the caller has the same variable names)
#   With all options:
#     sudo REAL_USER="$REAL_USER" bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/cli_tools.sh" --timestamp "$FILENAME_TIMESTAMP"
#   With only mandatory options (there are none):
#     sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/cli_tools.sh"
#   Verification only:
#     sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/cli_tools.sh" --verify-setup
#
# REQUIRED HELPER FILES (helpers in $HELPER_DIR = $SYSUPDATE_CODE_BASE_DIR/linux/commonh/, getters in $GETTERS_DIR = .../linux/commong/)
#   helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh
#   get_*.sh system detection scripts. Run zsh.sh first (the snippet needs its loader).

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
CLITOOLS_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/cli_tools"

# Where the helper_*.sh files and the get_*.sh detection scripts live (overridable from the environment).
HELPER_DIR="${HELPER_DIR:-${SYSUPDATE_CODE_BASE_DIR}/linux/commonh}"     # helper_*.sh / helper_*.py
GETTERS_DIR="${GETTERS_DIR:-${SYSUPDATE_CODE_BASE_DIR}/linux/commong}"   # get_*.sh system detection scripts
for _f in helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh; do
  [[ -r "${HELPER_DIR}/${_f}" ]] || { echo "Missing helper file: ${HELPER_DIR}/${_f}" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "${HELPER_DIR}/${_f}"
done
unset _f
nb_require_functions backup_path_parents nb_mkdir nb_install_conf nb_remove_conf render write_file
trap 'log_error "Unexpected failure at line ${LINENO}: ${BASH_COMMAND}"' ERR

# --- Script specific ---
CLI_TOOLS_PACKAGES=(fzf zoxide eza bat ripgrep fd-find direnv fastfetch)
CLI_TOOLS_PROFILES="mid high"      # RAM profiles that get the tools
NTFY_URL=""                        # optional, e.g. https://ntfy.sh/<topic>

#########################################################
# Inferred variables
#########################################################
CLITOOLS_CURRENT_BACKUP_DIR=""
INSTALL_CLI_TOOLS="false"
infer_variables() {
  nb_infer_system
  CLITOOLS_CURRENT_BACKUP_DIR="${CLITOOLS_BACKUP_DIR_BASE}/cli_tools_${FILENAME_TIMESTAMP}"
  local p
  for p in ${CLI_TOOLS_PROFILES}; do
    if [[ "$p" == "$RAM_PROFILE" ]]; then INSTALL_CLI_TOOLS="true"; fi
  done
}

#########################################################
# Templates
#########################################################
# shellcheck disable=SC2016  # the $ signs below are zsh syntax
IFS= read -r -d '' SNIPPET_TOOLS <<'EOF' || true
# 30-tools.zsh - CLI tool integrations. Installed by cli_tools.sh (re-run it to regenerate; edit freely if you prefer).
# Every block is guarded: a tool that is not installed is simply skipped.

if (( $+commands[fzf] )); then
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
  if (( $+commands[fd] )); then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  fi
  # `fzf --zsh` (fzf >= 0.48) prints the key bindings: Ctrl-R history, Ctrl-T files, Alt-C cd.
  # Atuin (50-atuin.zsh) loads later and takes over Ctrl-R when installed.
  source <(fzf --zsh 2>/dev/null) 2>/dev/null
fi

(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"    # `z <partial-dir-name>` jumps to frequent directories
# direnv loads .envrc files from the directory you enter (each needs `direnv allow` once).
(( $+commands[direnv] )) && eval "$(direnv hook zsh)"

# `ls` is deliberately NOT aliased to eza: eza's flags differ from GNU ls (eza -t takes a field name, so
# `ls -ltra` fails with "Option --time has no 'ra' setting"). Muscle-memory commands keep working; the
# eza views get their own names.
if (( $+commands[eza] )); then
  alias ll='eza -lah --git --group-directories-first'
  alias llt='eza -lah --git --sort=modified'          # like `ls -ltra`: oldest first, newest last
  alias lt='eza --tree --level=2'
fi
(( $+commands[bat] )) && alias bcat='bat --paging=never'
(( $+commands[fastfetch] )) && alias ff='fastfetch'

# Safer defaults for interactive use: ask before overwriting; one prompt for bulk deletes.
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -I'
alias ports='ss -tulpn'
EOF

#########################################################
# Backup
#########################################################
backup_existing() {
  log_header "Backup"
  mkdir -p "$CLITOOLS_CURRENT_BACKUP_DIR"
  backup_path_parents "${NB_ZSH_CONF_DIR}/30-tools.zsh" "$CLITOOLS_CURRENT_BACKUP_DIR"
  backup_record "$CLITOOLS_CURRENT_BACKUP_DIR" "installed_packages" rpm -q "${CLI_TOOLS_PACKAGES[@]}"
  chown -R "${REAL_USER}:${REAL_USER}" "$CLITOOLS_BACKUP_DIR_BASE"
  chmod 0700 "$CLITOOLS_CURRENT_BACKUP_DIR"
  log_success "Backup written to ${CLITOOLS_CURRENT_BACKUP_DIR}"
}

#########################################################
# Reset
#########################################################
# Only the snippet is removed and rewritten. The packages are the system's own (dnf) and stay installed.
reset_existing() {
  log_header "Reset"
  nb_remove_conf 30-tools.zsh
  log_success "Previous tools snippet removed"
}

#########################################################
# Install
#########################################################
install_packages() {
  log_header "Packages"
  local pkg
  # One by one: a single unavailable package would otherwise abort the whole transaction.
  for pkg in "${CLI_TOOLS_PACKAGES[@]}"; do
    if dnf install -y "$pkg" >/dev/null 2>&1; then
      log_success "dnf: ${pkg}"
    else
      log_warn "Package not available, skipped: ${pkg}"
    fi
  done
}

install_snippet() {
  nb_install_conf 30-tools.zsh "$SNIPPET_TOOLS"
  log_success "Snippet 30-tools.zsh installed"
}

#########################################################
# Verification
#########################################################
verify_setup() {
  nb_verify_begin
  if [[ "$INSTALL_CLI_TOOLS" != "true" ]]; then
    log_info "RAM profile '${RAM_PROFILE}' is not in CLI_TOOLS_PROFILES: nothing to verify"
    check "no tools snippet is installed on this low-RAM profile" test ! -e "${NB_ZSH_CONF_DIR}/30-tools.zsh"
    nb_verify_end
    return
  fi
  local cmds=(fzf zoxide eza bat rg fd direnv fastfetch) c
  for c in "${cmds[@]}"; do
    if has_cmd "$c"; then log_success "installed: ${c}"; VERIFY_PASS=$((VERIFY_PASS + 1)); else nb_verify_warn "not installed: ${c}"; fi
  done
  if has_cmd fzf && ! fzf --zsh >/dev/null 2>&1; then
    nb_verify_warn "fzf is older than 0.48: shell key bindings are skipped"
  fi
  check "snippet is installed and owned by ${REAL_USER}" test "$(stat -c %U "${NB_ZSH_CONF_DIR}/30-tools.zsh")" = "$REAL_USER"
  check "snippet passes zsh syntax check" zsh -n "${NB_ZSH_CONF_DIR}/30-tools.zsh"
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

  log_header "CLI tools setup"
  if [[ "$VERIFY_ONLY" == "true" ]]; then
    verify_setup || exit 1
    return
  fi

  require_fedora
  nb_prepare_script_dirs "$CLITOOLS_BACKUP_DIR_BASE"
  backup_existing
  reset_existing
  if [[ "$INSTALL_CLI_TOOLS" == "true" ]]; then
    log_info "RAM profile '${RAM_PROFILE}': installing productivity CLI tools"
    install_packages
    install_snippet
  else
    log_info "RAM profile '${RAM_PROFILE}': CLI tools skipped (keeps the shell light on this machine)"
  fi
  verify_setup || true
  nb_notify "cli_tools.sh finished on $(hostname)"
  log_header "Done"
  log_info "Open a new terminal. Backup: ${CLITOOLS_CURRENT_BACKUP_DIR}"
}

main "$@"
exit $?

#########################################################
# Notes
#########################################################
# * Why these tools: fzf/zoxide/eza/bat/ripgrep/fd are used by the shell, yazi, neovim (LazyVim) and tmux
#   setups too, so they are installed once, here, early in the run order. fastfetch is used by `nbupdate`.
# * Gating: only the RAM profiles in CLI_TOOLS_PROFILES install them; the detection comes from
#   get_ram_profile.sh, never a hard-coded machine name.
# * Moved here from the old all-in-one zsh script: the fzf/zoxide/direnv integration and the eza/bat aliases.
#   Their old position inside a generated .zshrc made them impossible to change without regenerating it.
# * Atuin (atuin.sh) is not a dnf package here; it has its own script. fzf's Ctrl-R remains the history search
#   until Atuin is installed.
# * Packages are NOT removed by Reset: they are normal system packages other things may depend on.
# * Only your user gets these integrations; root stays plain bash.
# * `ls` is NOT aliased to eza (an earlier version did): eza's -t means --time=FIELD, so the common
#   `ls -ltra` broke. Use `ll` (long, git, dirs first), `llt` (sorted by modified time, newest last), `lt` (tree).
#   Oh My Zsh also defines ll/la/l as plain `ls` aliases; the snippet loads after it, so ours win.
# * Aliases that change behavior (cp -i, mv -i, rm -I) apply to interactive shells only; scripts
#   are unaffected because aliases are not expanded in non-interactive shells.

#########################################################
# Troubleshooting/Debugging
#########################################################
# Health check:        sudo bash cli_tools.sh --verify-setup
# Which tools exist:   for c in fzf zoxide eza bat rg fd direnv fastfetch; do command -v $c || echo "missing: $c"; done
# fzf key bindings:    fzf --version (needs >= 0.48 for `fzf --zsh`); `bindkey | grep fzf`
# `z` does nothing:    zoxide learns as you `cd`; try `cd` into a few directories first, then `zoxide query -l`.
# direnv not loading:  `direnv status`; each .envrc needs `direnv allow` once.
# Alias in the way:    run the real command with a backslash: \ls, \rm. `alias` lists everything.
# eza flag errors:     eza is not a drop-in for ls (-t, -S differ); `ls` stays GNU. See `ll`, `llt`, `lt`.
# Missing package:     dnf search <name> ; names on Fedora: fd-find (command fd), ripgrep (command rg).
# Roll back:           backups mirror real paths under ~/nb/nb_script_data/backups/cli_tools/cli_tools_<timestamp>/
