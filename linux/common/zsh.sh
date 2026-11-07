#!/usr/bin/env bash
#########################################################
# Useful Links
#########################################################
# zsh startup files and their order .... https://zsh.sourceforge.io/Doc/Release/Files.html
# zsh options (RCS, GLOBAL_RCS, HIST_*) . https://zsh.sourceforge.io/Doc/Release/Options.html
# zsh glob qualifiers / assoc arrays .... https://zsh.sourceforge.io/Doc/Release/Expansion.html
# Arch Wiki (best general zsh reference)  https://wiki.archlinux.org/title/Zsh
# Gentoo / Debian zsh pages ............. https://wiki.gentoo.org/wiki/Zsh , https://wiki.debian.org/Zsh
# Root must not execute user-writable rc files (compaudit complaints, privilege escalation):
#   https://github.com/zsh-users/zsh-completions/issues/680
#   https://www.zsh.org/mla/users/2019/msg00728.html
# sudoers (always_set_home, secure_path) . https://www.sudo.ws/docs/man/sudoers.man/
# systemd sandboxing options ............ https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html
# Fedora SELinux ........................ https://docs.fedoraproject.org/en-US/quick-docs/selinux-getting-started/
#
#########################################################
# Description
#########################################################
# Sets up the zsh FOUNDATION on Fedora. Other scripts add features as drop-in snippets:
#   omz.sh (Oh My Zsh + plugins)  starship.sh (prompt)  atuin.sh (history)  cli_tools.sh (fzf, zoxide, ...)
#
# This script owns:
#   * the zsh package and the login shell of the real user (and of root)
#   * the loader-style ~/.zshrc and /root/.zshrc (they source /usr/local/share/zsh-nb/conf.d snippets)
#   * the guard in /etc/zshenv that stops root from reading startup files of a foreign HOME
#   * the single update runner (nb-update-tools) and its weekly timer
#   * the "Added by nbhirud" block (aliases, torsocks) at the end of the user's .zshrc
#
# Existing zsh rc files are backed up and then REPLACED. Shell history is kept.
# Old artifacts of the previous all-in-one version (nb-zsh-update) are removed.
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
# REQUIRED HELPER FILES (in $SYSUPDATE_CODE_BASE_DIR/linux/commonh/)
#   helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh
#   get_cpu_cores.sh get_ram_size.sh get_ram_profile.sh get_ssd_present.sh get_pc_type.sh
#   get_desktop_env.sh get_distro_name.sh get_cpu_model.sh

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
BASE_PACKAGES=(zsh git curl tar util-linux-user)   # util-linux-user provides `chsh` on Fedora
ZSH_BIN="/usr/bin/zsh"                             # canonical Fedora path (the one listed in /etc/shells)
SET_ROOT_SHELL_TO_ZSH=true                         # `sudo -i` / `sudo su` then land in zsh (safe: zsh is on the root fs)
USER_HISTSIZE=50000
ROOT_HISTSIZE=10000
UPDATE_TIMER_SCHEDULE="weekly"                     # systemd OnCalendar value for nb-update-tools
NTFY_URL=""                                        # optional, e.g. https://ntfy.sh/<topic>

# Helpers are sourced from the project; the file must exist before anything else can run.
HELPER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commonh"
for _f in helper_common.sh helper_backup.sh helper_github_release.sh helper_nb_dropins.sh; do
  [[ -r "${HELPER_DIR}/${_f}" ]] || { echo "Missing helper file: ${HELPER_DIR}/${_f}" >&2; exit 1; }
  # shellcheck source=/dev/null
  source "${HELPER_DIR}/${_f}"
done
unset _f
nb_require_functions backup_path_parents backup_record nb_ensure_update_runner nb_install_conf render write_file
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
# The part above "Added by nbhirud" is regenerated by zsh.sh. Features come from snippets in
#   /usr/local/share/zsh-nb/conf.d  and  /usr/local/share/zsh-nb/conf.d-user
# (installed by omz.sh, starship.sh, atuin.sh, cli_tools.sh). Personal additions go in the block at the end.

#################################################################
# PATH
#################################################################
# typeset -U makes the array keep only the first occurrence of each entry.
# /usr/local/bin holds Starship and Atuin; ~/.local/bin holds uv, pipx and similar user installs.
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
# Snippets from both directories are merged and sourced in FILENAME order (10-, 20-, ... 90-).
# A snippet with the same name in both directories: the conf.d-user one wins.
typeset -A _nb_snippets
for _nb_f in /usr/local/share/zsh-nb/conf.d/*.zsh(N) /usr/local/share/zsh-nb/conf.d-user/*.zsh(N); do
  _nb_snippets[${_nb_f:t}]=$_nb_f
done
for _nb_f in ${(ko)_nb_snippets}; do
  source "${_nb_snippets[$_nb_f]}"
done
unset _nb_f _nb_snippets
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
# PREVIOUS: ... && uv self update && omz update -y && ...
#   `omz update` cannot work any more: Oh My Zsh lives in a root-owned shared directory. The root-owned
#   runner below updates Oh My Zsh, its plugins, Starship and Atuin in one go. The "|| true" keeps a
#   failed download from skipping the later `. torsocks on` in the chain.
alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && aws update && uv self update && (sudo /usr/local/sbin/nb-update-tools || true) && . torsocks on && fastfetch"
# alias nbupdateproton=". torsocks off && cd /home/nbhirud/nb/CodeProjects/system_update/ && sh /home/nbhirud/nb/CodeProjects/system_update/linux/security_os_level/proton_ag.sh --setup-type full --desktop kde && cd && . torsocks on"
alias nbupdateextra=". torsocks off && sh /home/nbhirud/nb/CodeProjects/system_update/linux/fedora/update_all.sh && nbupdate"

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

# shellcheck disable=SC2016
IFS= read -r -d '' TEMPLATE_ROOT_ZSHRC <<'EOF' || true
# /root/.zshrc - generated by zsh.sh on @TIMESTAMP@
# OWNED BY ROOT. Loads ONLY the root-owned snippets in /usr/local/share/zsh-nb/conf.d. It never
# sources a file from a normal user's home directory, and it never loads conf.d-user: files a normal
# user can edit must not run as root.

# sudo's secure_path on Fedora omits /usr/local/bin, where Starship lives.
typeset -U path PATH
path=(/usr/local/bin /usr/local/sbin $path)

HISTFILE="$HOME/.zsh_history"
HISTSIZE=@HISTSIZE@
SAVEHIST=@HISTSIZE@
HISTORY_IGNORE='(*password*|*passwd*|*token*|*secret*|*api_key*|*apikey*)'

for _nb_f in /usr/local/share/zsh-nb/conf.d/*.zsh(N); do
  source "$_nb_f"
done
unset _nb_f
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
    "/root/.zshrc" "/root/.zshenv" "/root/.zprofile"       # root's history is deliberately not copied
    "/etc/zshenv" "/etc/zshrc" "/etc/zprofile" "/etc/zlogin" "/etc/zlogout" "/etc/zsh" "/etc/shells"
    "${NB_ZSH_SHARED_DIR}/conf.d" "${NB_ZSH_SHARED_DIR}/conf.d-user"
    "${NB_UPDATE_RUNNER}" "/etc/systemd/system/${NB_UPDATE_UNIT}.service" "/etc/systemd/system/${NB_UPDATE_UNIT}.timer"
    # Legacy artifacts of the previous all-in-one version
    "/usr/local/sbin/nb-zsh-update" "/usr/local/lib/nb-zsh"
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
# Remove what THIS script owns, completely; nothing is "repaired in place". Other scripts own their
# own snippets and trees (omz.sh, starship.sh, ...), so those are left alone. History is kept.
reset_existing() {
  log_header "Reset"
  rm -f "${HOME_DIR}/.zshrc" "/root/.zshrc"

  # Our marked block in /etc/zshenv (the rest of the file is untouched).
  if [[ -f /etc/zshenv ]]; then
    sed -i '/^# >>> nb-zsh root guard >>>$/,/^# <<< nb-zsh root guard <<<$/d' /etc/zshenv
  fi

  # Legacy all-in-one updater (replaced by nb-update-tools).
  if systemctl list-unit-files nb-zsh-update.timer >/dev/null 2>&1; then
    systemctl disable --now nb-zsh-update.timer >/dev/null 2>&1 || true
  fi
  rm -f /usr/local/sbin/nb-zsh-update /etc/systemd/system/nb-zsh-update.service /etc/systemd/system/nb-zsh-update.timer
  rm -rf /usr/local/lib/nb-zsh

  # The runner is rewritten by nb_ensure_update_runner.
  rm -f "$NB_UPDATE_RUNNER"
  systemctl daemon-reload
  log_success "Previous zsh rc setup removed"
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
  nb_ensure_conf_dirs

  local user_rc
  user_rc="$(render "$TEMPLATE_USER_ZSHRC" TIMESTAMP="$FILENAME_TIMESTAMP" HISTSIZE="$USER_HISTSIZE")"
  write_file "${HOME_DIR}/.zshrc" "$REAL_USER" "$REAL_USER" 0644 "${user_rc}
${TEMPLATE_USER_NBBLOCK}"

  write_file "/root/.zshrc" root root 0644 "$(render "$TEMPLATE_ROOT_ZSHRC" TIMESTAMP="$FILENAME_TIMESTAMP" HISTSIZE="$ROOT_HISTSIZE")"

  # History must be private. zsh creates it 0600 itself; this also fixes an old file.
  if [[ -f "${HOME_DIR}/.zsh_history" ]]; then
    chown "${REAL_USER}:${REAL_USER}" "${HOME_DIR}/.zsh_history"
    chmod 0600 "${HOME_DIR}/.zsh_history"
  fi
  log_success ".zshrc written for ${REAL_USER} and root"
}

# A guard in /etc/zshenv (read by every zsh, before any user file): if root runs zsh with a HOME that
# is not /root (for example `sudo -E zsh`, or a sudoers setup that keeps HOME), the RCS option is
# switched off, so zsh will not read ~/.zshenv, ~/.zshrc, etc. from that home.
# Result: root can never execute startup files that a normal user can edit.
install_root_guard() {
  touch /etc/zshenv
  {
    echo '# >>> nb-zsh root guard >>>'
    echo '# Added by zsh.sh. Stops root from executing startup files of a foreign HOME.'
    echo 'if (( EUID == 0 )) && [[ "${HOME:-/root}" != "/root" ]]; then'
    echo '  unsetopt rcs'
    echo 'fi'
    echo '# <<< nb-zsh root guard <<<'
  } >> /etc/zshenv
  chown root:root /etc/zshenv
  chmod 0644 /etc/zshenv
  log_success "Root guard added to /etc/zshenv"
}

#########################################################
# Login shells
#########################################################
set_login_shells() {
  log_header "Login shells"
  # A login shell must be listed in /etc/shells or login tools may refuse it.
  if ! grep -qx "$ZSH_BIN" /etc/shells; then
    echo "$ZSH_BIN" >> /etc/shells
  fi
  # usermod changes the shell directly (no password prompt, unlike chsh).
  usermod -s "$ZSH_BIN" "$REAL_USER"
  log_success "Login shell of ${REAL_USER}: ${ZSH_BIN} (applies at the next login)"
  if [[ "$SET_ROOT_SHELL_TO_ZSH" == "true" ]]; then
    usermod -s "$ZSH_BIN" root
    log_success "Login shell of root: ${ZSH_BIN}"
  fi
}

#########################################################
# Security
#########################################################
apply_security() {
  log_header "Security"
  # SELinux: files written by a script can carry the wrong label; restorecon resets them to policy.
  if has_cmd restorecon; then
    restorecon -RF "$NB_ZSH_SHARED_DIR" "$NB_LIB_DIR" "$NB_UPDATE_RUNNER" /etc/zshenv \
      "/etc/systemd/system/${NB_UPDATE_UNIT}.service" "/etc/systemd/system/${NB_UPDATE_UNIT}.timer" 2>/dev/null || true
    log_success "SELinux labels restored"
  fi
  # No firewalld rules (nothing listens) and no ClamAV exclusions are needed here.
}

#########################################################
# Verification
#########################################################
login_shell_of() { getent passwd "$1" | cut -d: -f7; }

root_guard_blocks_foreign_home() {
  # Root with the user's HOME must NOT read startup files (RCS option off).
  [[ "$(env -i HOME="$HOME_DIR" PATH=/usr/bin:/bin TERM=dumb zsh -i -c 'print -r -- ${options[rcs]}' 2>/dev/null </dev/null | tail -n1)" == "off" ]]
}

root_shell_starts_clean() {
  local out
  out="$(HOME=/root TERM=xterm-256color zsh -i -c exit 2>&1 </dev/null)" || return 1
  ! grep -Eiq 'insecure|no such file|command not found|permission denied|parse error' <<<"$out"
}

startup_time_ok() {
  local start end ms
  start=$(date +%s%N)
  runuser -l "$REAL_USER" -c "zsh -i -c exit" >/dev/null 2>&1 </dev/null || return 1
  end=$(date +%s%N)
  ms=$(( (end - start) / 1000000 ))
  log_info "Interactive zsh startup: ${ms} ms"
  if (( ms > 1000 )); then nb_verify_warn "Startup is slower than 1 s (see Troubleshooting: profiling)"; fi
  return 0
}

verify_setup() {
  nb_verify_begin
  local zbin="$ZSH_BIN"
  check "zsh is installed" test -x "$zbin"
  check "login shell of ${REAL_USER} is zsh" test "$(login_shell_of "$REAL_USER")" = "$zbin"
  if [[ "$SET_ROOT_SHELL_TO_ZSH" == "true" ]]; then
    check "login shell of root is zsh" test "$(login_shell_of root)" = "$zbin"
  fi
  check "zsh is listed in /etc/shells" grep -qx "$zbin" /etc/shells
  check "user .zshrc passes zsh syntax check" zsh -n "${HOME_DIR}/.zshrc"
  check "root .zshrc passes zsh syntax check" zsh -n /root/.zshrc
  check "root .zshrc is root-owned" test "$(stat -c %U /root/.zshrc)" = "root"
  check "snippet directories are root-owned and locked" nb_tree_is_locked "$NB_ZSH_SHARED_DIR/conf.d" "$NB_ZSH_SHARED_DIR/conf.d-user" "$NB_LIB_DIR"
  check "user shell starts without errors" nb_user_zsh_starts_clean
  check "root shell starts without errors" root_shell_starts_clean
  check "compaudit reports no insecure directories" nb_compaudit_is_clean
  check "root ignores startup files from a foreign HOME" root_guard_blocks_foreign_home
  check "interactive startup time measured" startup_time_ok
  if [[ -f "${HOME_DIR}/.zsh_history" ]]; then
    check "history file is private (0600)" test "$(stat -c %a "${HOME_DIR}/.zsh_history")" = "600"
  fi
  check "update runner is installed (root-owned)" test -x "$NB_UPDATE_RUNNER" -a "$(stat -c %U "$NB_UPDATE_RUNNER")" = "root"
  check "update timer is enabled" systemctl is-enabled "${NB_UPDATE_UNIT}.timer"
  check "update service unit is valid" systemd-analyze verify "/etc/systemd/system/${NB_UPDATE_UNIT}.service"
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
  install_root_guard
  set_login_shells
  nb_ensure_update_runner
  apply_security
  verify_setup || true
  nb_notify "zsh.sh finished on $(hostname)"

  log_header "Done"
  log_info "Next: omz.sh, starship.sh, atuin.sh, cli_tools.sh. Log out and in (or reboot) for the new login shell."
  log_info "Backup: ${ZSH_CURRENT_BACKUP_DIR}. Compare your old ~/.zshrc there with the new one for anything personal."
}

main "$@"
exit $?

#########################################################
# Notes
#########################################################
# DESIGN DECISIONS
# * This script is the FOUNDATION only. Features (Oh My Zsh, prompt, history, tools) are drop-in
#   snippets installed by their own scripts, so each can be installed, verified or removed alone.
#   See helper_nb_dropins.sh for the snippet directories and the single update runner.
# * Root never sources a file from a user's home: a file the user can write, executed by root at the
#   next `sudo -i`, would let any process running as that user become root. /etc/zshenv additionally
#   switches RCS off when root's HOME is not /root.
# * `sudo -i` is preferred over `sudo su`. On Fedora, sudoers has always_set_home, so both end up with
#   HOME=/root and read /root/.zshrc. The old "I lose Oh My Zsh as root" came from root having no setup.
# * ZSH_BIN is /usr/bin/zsh, not `command -v zsh`: under sudo, PATH lists /usr/sbin first and
#   `command -v` returned /usr/sbin/zsh, which is not the path Fedora registers in /etc/shells.
# * torsocks: `. torsocks on` stays the default for interactive terminals. The `[[ -t 1 ]]` guard is the
#   fix for the "Tor mode activated" banner breaking `zsh -i -c ...` based tests. The earlier workaround of
#   filtering the banner in the verification was dropped: it treated the symptom and hid real output.
# * The loader merges conf.d and conf.d-user by filename so one numbering scheme orders ALL snippets,
#   even though some live in the root-visible directory and some only in the user-only one.
# * Removed from the previous version: the generated Oh My Zsh section (now omz.sh), the Starship and
#   plugin logic (starship.sh, omz.sh), the CLI aliases (cli_tools.sh), the per-tool updater (nb-zsh-update,
#   now one nb-update-tools runner with a drop-in per tool), and the agnoster SSH override.
# * NextDNS: zsh has no network identity of its own, so there is no app-level NextDNS setting.
# * Android/Termux: `pkg install zsh`; copy only the "Added by nbhirud" aliases that apply.
#
# KNOWN LIMITS
# * A hand-made ~/.zshrc is replaced (backed up first). Anything personal beyond the old
#   "Added by nbhirud" block (conda/nvm init, PATH tweaks) must be carried over from the backup.
# * An interactive zsh with piped stdout is not torified (see torsocks note).

#########################################################
# Troubleshooting/Debugging
#########################################################
# Health check:                sudo bash zsh.sh --verify-setup
# Which shell am I?            echo $SHELL ; getent passwd "$USER" | cut -d: -f7 ; ps -p $$ -o comm=
#   The login shell changes at the next login. Test immediately with:  exec zsh -l
# Which snippets load?         ls /usr/local/share/zsh-nb/conf.d /usr/local/share/zsh-nb/conf.d-user
#   Trace the loader:          zsh -ixc exit 2>&1 | grep -E 'zsh-nb/conf.d' | head -30
#   A snippet with an error only breaks itself; the message names the file and line.
# Startup is slow:             time zsh -i -c exit ; zsh -ixc exit 2>&1 | less
#   Profile: add `zmodload zsh/zprof` as the FIRST line of ~/.zshrc and `zprof` as the LAST, open a new shell.
# compaudit warnings:          compaudit ; compaudit | xargs sudo chmod g-w,o-w
# Root shell:                  sudo -i (login shell, /root/.zshrc) ; sudo -l | grep -i always_set_home
#   Guard test (must print "off"):  sudo env -i HOME=$HOME zsh -i -c 'print ${options[rcs]}'
#   Broken root shell: `su -s /bin/bash -` or rescue boot, then `usermod -s /bin/bash root`.
# Updates:                     sudo /usr/local/sbin/nb-update-tools ; systemctl list-timers nb-update-tools.timer
#   Logs:                      journalctl -u nb-update-tools.service -e
#   Run exactly like the timer: sudo systemctl start nb-update-tools.service
# SELinux:                     ls -lZ /usr/local/share/zsh-nb ; sudo restorecon -Rv /usr/local/share/zsh-nb ; sudo ausearch -m avc -ts recent
# Torsocks interfering:        nbtoroff (or `. torsocks off`). Typical victims: ping, UDP tools, some Rust/Go programs.
# Roll back:                   backups mirror real paths under ~/nb/nb_script_data/backups/zsh/zsh_<timestamp>/
#   cp -a <backup>/home/<user>/.zshrc ~/.zshrc ; sudo usermod -s /bin/bash <user>
