#!/usr/bin/env bash
#########################################################
# Useful Links
#########################################################
# zsh startup files and their order .... https://zsh.sourceforge.io/Doc/Release/Files.html
# zsh options (HIST_*) .................. https://zsh.sourceforge.io/Doc/Release/Options.html
# Arch Wiki (best general zsh reference)  https://wiki.archlinux.org/title/Zsh
# Gentoo / Debian zsh pages ............. https://wiki.gentoo.org/wiki/Zsh , https://wiki.debian.org/Zsh
# Fedora: shells and usermod ............ https://docs.fedoraproject.org/en-US/fedora/latest/
#
#########################################################
# Description
#########################################################
# Sets up the zsh FOUNDATION for the real user on Fedora, the plain per-user way. Other scripts add features as
# drop-in snippets in ~/.config/zsh/conf.d:
#   omz.sh (Oh My Zsh + plugins)  cli_tools.sh (fzf, zoxide, ...)  starship.sh (prompt)  atuin.sh (history)
#
# This script owns:
#   * the zsh package and the user's login shell
#   * ~/.zshrc: PATH, history settings, a loader for the snippets, and the "Added by nbhirud" block
#     (aliases, torsocks)
#   * ~/.config/zsh/conf.d (the snippet directory) and ~/.local/bin/nb-update-tools (the update runner)
#
# ROOT IS LEFT ALONE: root's login shell is bash (restored if an earlier version of this setup had changed it),
# and nothing is configured for root. This script also REMOVES the root-related pieces of the earlier shared
# setup, after backing them up: the root-owned /usr/local/share/zsh-nb tree, the /etc/zshenv guard, /root/.zshrc,
# the root-run update runner/timer, and system-wide copies of starship and atuin (those are installed per user now).
#
# Existing ~/.zshrc is backed up and then REPLACED. Shell history is kept.
#
# NAMED OPTIONS
#   --verify-setup        Only run the Verification section (no changes are made).
#   --timestamp <value>   Timestamp used in backup/download directory names.
#                         Default: current time (YYYY-MM-DD_HH-MM-SS).
#   -h | --help           Show usage.
#
# SAMPLE CALLS (assuming the caller has the same variable names)
#   With all options:
#     sudo REAL_USER="$REAL_USER" bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/zsh.sh" --timestamp "$FILENAME_TIMESTAMP"
#   With only mandatory options (there are none):
#     sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/zsh.sh"
#   Verification only:
#     sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/zsh.sh" --verify-setup
#
# REQUIRED HELPER FILES (helpers in $HELPER_DIR = $SYSUPDATE_CODE_BASE_DIR/linux/commonh/, getters in $GETTERS_DIR = .../linux/commong/)
#   helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh
#   get_cpu_cores.sh get_ram_size.sh get_ram_profile.sh get_ssd_present.sh get_pc_type.sh
#   get_desktop_env.sh get_distro_name.sh get_cpu_model.sh
#
# Needs root only for dnf and usermod (it re-runs itself through sudo).

# -E: ERR trap inherited by functions. -e: exit on error. -u: unset variable is an error.
# -o pipefail: a pipeline fails if ANY command in it fails.
set -Eeuo pipefail

#########################################################
# User defined variables
#########################################################
# --- Standard directories (same on all machines) ---
REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${SYSUPDATE_CODE_BASE_DIR:-${CODEPROJECTS_DIR}/system_update}"
SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"
ZSH_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/zsh"

# --- Script specific ---
# python3 is used by omz/starship/atuin (release-date check, TOML patching, Atuin backup); it is preinstalled on Fedora
# Workstation but not guaranteed on minimal installs. util-linux-user (chsh) is not needed: usermod changes the shell.
BASE_PACKAGES=(zsh git curl tar python3)
ZSH_BIN="/usr/bin/zsh"                             # canonical Fedora path (the one listed in /etc/shells)
ROOT_SHELL="/bin/bash"                             # root's login shell (Fedora's default)
USER_HISTSIZE=50000
NTFY_URL=""                                        # optional, e.g. https://ntfy.sh/<topic>

# Helpers are sourced from the project; the file must exist before anything else can run.
# Where the helper_*.sh files and the get_*.sh detection scripts live (overridable from the environment).
HELPER_DIR="${HELPER_DIR:-${SYSUPDATE_CODE_BASE_DIR}/linux/commonh}"     # helper_*.sh / helper_*.py
GETTERS_DIR="${GETTERS_DIR:-${SYSUPDATE_CODE_BASE_DIR}/linux/commong}"   # get_*.sh system detection scripts
for _f in helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh; do
  [[ -r "${HELPER_DIR}/${_f}" ]] || { echo "Missing helper file: ${HELPER_DIR}/${_f}" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "${HELPER_DIR}/${_f}"
done
unset _f
nb_require_functions backup_path_parents backup_record nb_ensure_update_runner nb_mkdir nb_ensure_conf_dirs render write_file
trap 'log_error "Unexpected failure at line ${LINENO}: ${BASH_COMMAND}"' ERR

#########################################################
# Inferred variables
#########################################################
ZSH_CURRENT_BACKUP_DIR=""
infer_variables() {
  nb_infer_system
  ZSH_CURRENT_BACKUP_DIR="${ZSH_BACKUP_DIR_BASE}/zsh_${FILENAME_TIMESTAMP}"
}

#########################################################
# Templates
#########################################################
# Single-quoted heredocs keep every $ and \ literal, so zsh code reads naturally.
# @KEY@ markers are filled in by render().

# shellcheck disable=SC2016  # the $ signs below are zsh syntax, not bash expansions
IFS= read -r -d '' TEMPLATE_USER_ZSHRC <<'EOF' || true
# ~/.zshrc - generated by zsh.sh on @TIMESTAMP@
# The part above "Added by nbhirud" is regenerated by zsh.sh. Features come from the snippets in
#   ~/.config/zsh/conf.d
# (installed by omz.sh, cli_tools.sh, starship.sh, atuin.sh). Personal additions go in the block at the end.

#################################################################
# PATH
#################################################################
# typeset -U makes the array keep only the first occurrence of each entry.
# ~/.local/bin holds starship, atuin, uv, pipx and similar per-user installs.
typeset -U path PATH
path=("$HOME/.local/bin" "$HOME/bin" /usr/local/bin $path)

#################################################################
# History (zsh keeps writing it even when Atuin is installed: it is the plain-text fallback)
#################################################################
HISTFILE="$HOME/.zsh_history"
HISTSIZE=@HISTSIZE@
SAVEHIST=@HISTSIZE@
# Lines that look like they contain secrets are not saved. A command typed with a leading space is
# not saved either (Oh My Zsh enables HIST_IGNORE_SPACE).
HISTORY_IGNORE='(*password*|*passwd*|*token*|*secret*|*api_key*|*apikey*)'

#################################################################
# Snippet loader
#################################################################
# Every file in ~/.config/zsh/conf.d is sourced in FILENAME order (10-, 20-, ... 90-).
# A snippet with an error only breaks itself; zsh names the file and line.
for _nb_f in "$HOME"/.config/zsh/conf.d/*.zsh(N); do
  source "$_nb_f"
done
unset _nb_f
EOF

IFS= read -r -d '' TEMPLATE_USER_NBBLOCK <<'EOF' || true

#################################################################
# Added by nbhirud:
#################################################################

############################
# Constants, Flags, Paths, etc
############################

HOME_DIR=$(getent passwd $USER | cut -d: -f6)
NBDIR="$HOME_DIR/nb"
CODEPROJECTS_DIR="$NBDIR/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="$CODEPROJECTS_DIR/system_update"


############################
# Aliases
############################

# Application shortcuts:
# alias codium="flatpak run com.vscodium.codium "

# Update/Upgrade related:
# alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && sudo freshclam && omz update -y && . torsocks on && fastfetch"
# freshclam is a service now
# nb-update-tools updates what `omz update` and dnf do not cover: the cloned zsh plugins (fzf-tab, zsh-completions)
# and the per-user starship and atuin binaries. It runs as you (no sudo); "|| true" keeps a failed download
# from skipping the later `. torsocks on` in the chain.
alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && fastfetch && . torsocks on"
# alias nbupdateproton=". torsocks off && cd /home/nbhirud/nb/CodeProjects/system_update/ && sh /home/nbhirud/nb/CodeProjects/system_update/linux/security/proton_ag.sh --setup-type full --desktop kde && cd && . torsocks on"
alias nbupdateextra=". torsocks off && sh /home/nbhirud/nb/CodeProjects/system_update/linux/fedora/update_all.sh && aws update && uv self update && omz update -y && (nb-update-tools || true) && nbupdate"

# https://docs.fedoraproject.org/en-US/quick-docs/upgrading-fedora-offline/
# alias nbdistu="sudo sudo dnf upgrade --refresh -y && sudo sudo dnf system-upgrade download --releasever=43 -y"
alias nbreload="systemctl daemon-reload && source ~/.zshrc"
# Possible improvement (not active): `exec zsh` replaces the running shell with a fresh one, which
# re-reads every startup file cleanly, whereas `source ~/.zshrc` re-runs it inside the old shell
# (hooks get registered twice). `systemctl daemon-reload` is only needed after editing unit files.
# alias nbreload="exec zsh"
alias nbclean="sync && sudo dnf autoremove && dnf clean -y all && yum clean -y all && flatpak uninstall --unused && sudo bleachbit --clean --preset && bleachbit --clean --preset && sudo resolvectl flush-caches && sudo resolvectl reset-statistics"
alias nbtoron=". torsocks on"
alias nbtoroff=". torsocks off"
alias nbshutdown="nbupdateextra && nbclean && shutdown"
alias nbreboot="nbupdate && nbclean && reboot"


############################
# Alias experiments
############################

alias nbjoplinupdate="wget -O - https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh | bash"
alias nbuvupdate="uv self update"

alias gearlever='flatpak run it.mijorus.gearlever'
# flatpak run it.mijorus.gearlever --update <name of appimage> # updates 1 appimage at a time

############################
# PATH:
############################

export PATH="$HOME/.npm-global/bin:$PATH"

############################
# Enable tor:
############################

# . torsocks on
# if (( $+commands[torsocks] )); then
#   . torsocks on
# fi
# Only activate torsocks when a real terminal is attached (stdout is a TTY). Scripts, tests and
# `zsh -i -c ...` with captured output skip it, so the "Tor mode activated" banner cannot pollute
# their output. Trade-off: an interactive shell whose stdout is piped is NOT torified.
if (( $+commands[torsocks] )) && [[ -t 1 ]]; then
  . torsocks on
fi


############################
# TODO:
############################

# aws update - run only if aws is setup (full setup)
# Add to nbclean - clean old kernels script invocation
# Add to nbUpdate? - update fonts - invocation from this repo dir - use linux/common/git_repo_update_checker.sh maybe?
# Add to nbReboot - update hosts
# Add to nbReboot - update dnsmasq blocklists
# Or maybe most of these just need to be cron jobs? (linux/common/cron_jobs.sh)

# TODO - Edit nbclean for cosmic
# sudo bleachbit doesn'tt work idirectly on cosmic. it blames wayland. Surround it with commands as follows to use xwayland
# https://docs.bleachbit.org/doc/frequently-asked-questions.html
# https://wiki.archlinux.org/title/Running_GUI_applications_as_root
# xhost si:localuser:root && sudo bleachbit --clean --preset && xhost -si:localuser:root
EOF

#########################################################
# Backup
#########################################################
backup_existing() {
  log_header "Backup"
  mkdir -p "$ZSH_CURRENT_BACKUP_DIR"
  local -a paths=(
    "${HOME_DIR}/.zshrc" "${HOME_DIR}/.zshenv" "${HOME_DIR}/.zprofile" "${HOME_DIR}/.zlogin" "${HOME_DIR}/.zlogout"
    "${HOME_DIR}/.zsh_history"          # history is KEPT in place; the copy is only a safety net
    "${HOME_DIR}/.zsh" "${HOME_DIR}/.config/zsh" "${HOME_DIR}/.p10k.zsh"
    # --- root-related pieces of the earlier shared setup (removed below). The shared Oh My Zsh clone is
    # not backed up: it is a plain git clone with no personal data and is reinstalled by omz.sh. ---
    "/root/.zshrc" "/etc/zshenv" "/etc/shells"
    "/usr/local/share/zsh-nb/conf.d" "/usr/local/share/zsh-nb/conf.d-user" "/usr/local/share/zsh-nb/starship-root.toml"
    "/usr/local/lib/nb" "/usr/local/lib/nb-zsh" "/usr/local/sbin/nb-update-tools" "/usr/local/sbin/nb-zsh-update"
    "/etc/systemd/system/nb-update-tools.service" "/etc/systemd/system/nb-update-tools.timer"
    "/etc/systemd/system/nb-zsh-update.service" "/etc/systemd/system/nb-zsh-update.timer"
  )
  local f
  for f in "${HOME_DIR}"/.zshrc_nbbkp_* "${HOME_DIR}"/.zshrc.pre-oh-my-zsh*; do
    if [[ -e "$f" ]]; then paths+=("$f"); fi
  done
  for f in "${paths[@]}"; do backup_path_parents "$f" "$ZSH_CURRENT_BACKUP_DIR"; done

  backup_record "$ZSH_CURRENT_BACKUP_DIR" "passwd_entries" getent passwd root "$REAL_USER"
  backup_record "$ZSH_CURRENT_BACKUP_DIR" "installed_packages" rpm -q zsh

  # Private to the real user (mode 0700). Restoring root-owned files needs sudo + chown root:root.
  chown -R "${REAL_USER}:${REAL_USER}" "$ZSH_BACKUP_DIR_BASE"
  chmod 0700 "$ZSH_CURRENT_BACKUP_DIR"
  log_success "Backup written to ${ZSH_CURRENT_BACKUP_DIR}"
}

#########################################################
# Reset
#########################################################
# Removes what THIS script owns, and the root-related leftovers of the earlier shared setup. Per-user
# pieces of the other scripts (Oh My Zsh, starship, atuin) are removed by their own scripts. History is kept.
reset_existing() {
  log_header "Reset"
  rm -f "${HOME_DIR}/.zshrc" "${HOME_DIR}"/.zcompdump*

  # --- Leftovers of the shared root-owned setup ---
  local unit
  for unit in nb-update-tools nb-zsh-update; do
    if systemctl list-unit-files "${unit}.timer" >/dev/null 2>&1; then
      systemctl disable --now "${unit}.timer" >/dev/null 2>&1 || true
    fi
    rm -f "/etc/systemd/system/${unit}.service" "/etc/systemd/system/${unit}.timer"
  done
  systemctl daemon-reload
  rm -rf /usr/local/share/zsh-nb /usr/local/lib/nb /usr/local/lib/nb-zsh
  rm -f /usr/local/sbin/nb-update-tools /usr/local/sbin/nb-zsh-update

  # Our marked block in /etc/zshenv (the rest of the file is untouched).
  if [[ -f /etc/zshenv ]]; then
    sed -i '/^# >>> nb-zsh root guard >>>$/,/^# <<< nb-zsh root guard <<<$/d' /etc/zshenv
  fi
  # Root's rc only when this setup generated it.
  if [[ -f /root/.zshrc ]] && grep -q 'generated by zsh.sh' /root/.zshrc; then
    rm -f /root/.zshrc /root/.cache/oh-my-zsh/* 2>/dev/null || true
  fi
  # System-wide copies installed by the earlier version of these scripts (not by a package). They are
  # installed per user now, in ~/.local/bin.
  local bin
  for bin in starship atuin nb-atuin-backup; do
    if [[ -e "/usr/local/bin/${bin}" ]] && ! rpm -qf "/usr/local/bin/${bin}" >/dev/null 2>&1; then
      rm -f "/usr/local/bin/${bin}"
      log_info "Removed system-wide /usr/local/bin/${bin} (installed per user now)"
    fi
  done

  # Root goes back to a plain bash login shell if an earlier version made it zsh.
  if [[ "$(getent passwd root | cut -d: -f7)" == */zsh ]]; then
    usermod -s "$ROOT_SHELL" root
    log_info "Root login shell restored to ${ROOT_SHELL}"
  fi
  log_success "Previous zsh setup removed"
}

#########################################################
# Packages
#########################################################
install_packages() {
  log_header "Packages"
  require_fedora
  local pkg
  # One by one: a single unavailable package would otherwise abort the whole transaction, and
  # the message would not say which package was the problem.
  for pkg in "${BASE_PACKAGES[@]}"; do
    if dnf install -y "$pkg" >/dev/null 2>&1; then
      log_success "dnf: ${pkg}"
    else
      log_die "Required package could not be installed: ${pkg}"
    fi
  done
  [[ -x "$ZSH_BIN" ]] || ZSH_BIN="$(command -v zsh)"
  [[ -x "$ZSH_BIN" ]] || log_die "zsh not found after installation"
}

#########################################################
# Configuration files
#########################################################
write_rc_files() {
  log_header "Shell startup files"
  nb_ensure_conf_dirs   # ~/.config/zsh/conf.d, ~/.local/bin, ~/.local/share/nb (all owned by the user)

  local user_rc
  user_rc="$(render "$TEMPLATE_USER_ZSHRC" TIMESTAMP="$FILENAME_TIMESTAMP" HISTSIZE="$USER_HISTSIZE")"
  write_file "${HOME_DIR}/.zshrc" "$REAL_USER" "$REAL_USER" 0644 "${user_rc}
${TEMPLATE_USER_NBBLOCK}"

  # History must be private. zsh creates it 0600 itself; this also fixes an old file.
  if [[ -f "${HOME_DIR}/.zsh_history" ]]; then
    chown "${REAL_USER}:${REAL_USER}" "${HOME_DIR}/.zsh_history"
    chmod 0600 "${HOME_DIR}/.zsh_history"
  fi
  nb_ensure_update_runner
  log_success ".zshrc written for ${REAL_USER}; snippet directory and nb-update-tools ready"
}

#########################################################
# Login shells
#########################################################
set_login_shells() {
  log_header "Login shell"
  # A login shell must be listed in /etc/shells or login tools may refuse it.
  if ! grep -qx "$ZSH_BIN" /etc/shells; then
    echo "$ZSH_BIN" >> /etc/shells
  fi
  # usermod changes the shell directly (no password prompt, unlike chsh).
  usermod -s "$ZSH_BIN" "$REAL_USER"
  log_success "Login shell of ${REAL_USER}: ${ZSH_BIN} (applies at the next login)"
}

#########################################################
# Verification
#########################################################
login_shell_of() { getent passwd "$1" | cut -d: -f7; }

startup_time_ok() {
  local start end ms
  start=$(date +%s%N)
  nb_run_as_real_user "zsh -i -c exit" >/dev/null 2>&1 </dev/null || return 1
  end=$(date +%s%N)
  ms=$(( (end - start) / 1000000 ))
  log_info "Interactive zsh startup: ${ms} ms"
  if (( ms > 1000 )); then nb_verify_warn "Startup is slower than 1 s (see Troubleshooting: profiling)"; fi
  return 0
}

verify_setup() {
  nb_verify_begin
  check "zsh is installed" test -x "$ZSH_BIN"
  check "login shell of ${REAL_USER} is zsh" test "$(login_shell_of "$REAL_USER")" = "$ZSH_BIN"
  check "root's login shell is not zsh (plain bash)" bash -c "[[ \"\$(getent passwd root | cut -d: -f7)\" != */zsh ]]"
  check "zsh is listed in /etc/shells" grep -qx "$ZSH_BIN" /etc/shells
  check "user .zshrc passes zsh syntax check" zsh -n "${HOME_DIR}/.zshrc"
  check "user .zshrc is owned by ${REAL_USER}" test "$(stat -c %U "${HOME_DIR}/.zshrc")" = "$REAL_USER"
  check "snippet directory is owned by ${REAL_USER}" test "$(stat -c %U "$NB_ZSH_CONF_DIR")" = "$REAL_USER"
  check "update runner is installed and owned by ${REAL_USER}" test -x "$NB_UPDATE_RUNNER" -a "$(stat -c %U "$NB_UPDATE_RUNNER")" = "$REAL_USER"
  check "user shell starts without errors" nb_user_zsh_starts_clean
  check "compaudit reports no insecure directories" nb_compaudit_is_clean
  check "interactive startup time measured" startup_time_ok
  if [[ -f "${HOME_DIR}/.zsh_history" ]]; then
    check "history file is private (0600)" test "$(stat -c %a "${HOME_DIR}/.zsh_history")" = "600"
  fi
  # The root-related leftovers of the earlier shared setup must be gone.
  check "no shared root-owned tree (/usr/local/share/zsh-nb)" test ! -e /usr/local/share/zsh-nb
  check "no root update runner or timer" bash -c "! ls /usr/local/sbin/nb-update-tools /etc/systemd/system/nb-update-tools.* /etc/systemd/system/nb-zsh-update.* >/dev/null 2>&1"
  check "no root guard in /etc/zshenv" bash -c "! grep -qs 'nb-zsh root guard' /etc/zshenv"
  check "no /root/.zshrc generated by this setup" bash -c "! grep -qs 'generated by zsh.sh' /root/.zshrc"
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

  log_header "zsh setup"
  if [[ "$VERIFY_ONLY" == "true" ]]; then
    verify_setup || exit 1
    return
  fi

  require_fedora
  nb_prepare_script_dirs "$ZSH_BACKUP_DIR_BASE"
  backup_existing
  reset_existing
  install_packages
  write_rc_files
  set_login_shells
  verify_setup || true
  nb_notify "zsh.sh finished on $(hostname)"

  log_header "Done"
  log_info "Next: omz.sh, cli_tools.sh, starship.sh, atuin.sh. Log out and in (or reboot) for the new login shell."
  log_info "Backup: ${ZSH_CURRENT_BACKUP_DIR}. Compare your old ~/.zshrc there with the new one for anything personal."
}

main "$@"
exit $?

#########################################################
# Notes
#########################################################
# DESIGN DECISIONS
# * Plain per-user setup. An earlier version built one shared, root-owned Oh My Zsh tree used by both the user and
#   root (plus a root .zshrc, an /etc/zshenv guard, a root-run update timer and system-wide binaries). In daily use
#   that was more hassle than value, so it is gone: everything lives in the user's home and is owned by the user,
#   `omz update` works again, and no step needs sudo except installing packages.
# * Root: plain bash, nothing configured. `sudo -i` / `sudo su` give a bash root shell. Careful with `sudo -s`: it
#   starts the shell named by YOUR $SHELL (zsh) as root with HOME=/root, and with no /root/.zshrc zsh offers its
#   first-run setup wizard. Use `sudo -i`, or press q at the wizard, or create an empty /root/.zshrc.
# * This script still REMOVES the old root-related pieces (after backing them up) so a machine that ran the shared
#   version ends up clean. It is the only script that needs root for that; run it first.
# * Snippets: ~/.config/zsh/conf.d/NN-name.zsh, one per script, sourced in name order by ~/.zshrc. Delete a file
#   to remove that feature; re-run its script to restore it. Numbers: 10 omz, 20 plugins, 30 tools, 40 prompt,
#   50 atuin, 90 syntax-highlighting (always last).
# * ZSH_BIN is /usr/bin/zsh, not `command -v zsh`: under sudo, PATH lists /usr/sbin first and `command -v` returned
#   /usr/sbin/zsh, which is not the path Fedora registers in /etc/shells.
# * torsocks: `. torsocks on` stays the default for interactive terminals. The `[[ -t 1 ]]` guard keeps its banner
#   out of `zsh -i -c ...` based tests and scripts.
# * Updates: `nbupdate` runs `omz update -y` (Oh My Zsh itself) and `nb-update-tools` (cloned plugins, starship,
#   atuin; no sudo). There is no timer.
# * NextDNS: zsh has no network identity of its own, so there is no app-level NextDNS setting.
# * Android/Termux: `pkg install zsh`; copy only the "Added by nbhirud" aliases that apply.
#
# KNOWN LIMITS
# * A hand-made ~/.zshrc is replaced (backed up first). Anything personal beyond the "Added by nbhirud" block
#   (conda/nvm init, PATH tweaks) must be carried over from the backup.
# * An interactive zsh with piped stdout is not torified (see torsocks note).

#########################################################
# Troubleshooting/Debugging
#########################################################
# Health check:                sudo bash zsh.sh --verify-setup
# Which shell am I?            echo $SHELL ; getent passwd "$USER" | cut -d: -f7 ; ps -p $$ -o comm=
#   The login shell changes at the next login. Test immediately with:  exec zsh -l
# Which snippets load?         ls ~/.config/zsh/conf.d ; trace: zsh -ixc exit 2>&1 | grep 'zsh/conf.d' | head -30
#   A snippet with an error only breaks itself; the message names the file and line.
# Startup is slow:             time zsh -i -c exit ; zsh -ixc exit 2>&1 | less
#   Profile: add `zmodload zsh/zprof` as the FIRST line of ~/.zshrc and `zprof` as the LAST, open a new shell.
# compaudit warnings:          compaudit ; compaudit | xargs chmod g-w,o-w
# Root shell:                  sudo -i (bash). `sudo -s` starts zsh as root: see the Notes (first-run wizard).
# Updates:                     nb-update-tools (no sudo) ; omz update
# Torsocks interfering:        nbtoroff (or `. torsocks off`). Typical victims: ping, UDP tools, some Rust/Go programs.
# Roll back:                   backups mirror real paths under ~/nb/nb_script_data/backups/zsh/zsh_<timestamp>/
#   cp -a <backup>/home/<user>/.zshrc ~/.zshrc ; sudo usermod -s /bin/bash <user>
