#!/usr/bin/env bash
#########################################################
# Useful Links
#########################################################
# zsh itself
#   Startup files and their order ........ https://zsh.sourceforge.io/Doc/Release/Files.html
#   Options (RCS, GLOBAL_RCS, HIST_*) .... https://zsh.sourceforge.io/Doc/Release/Options.html
#   Arch Wiki (best general zsh reference) https://wiki.archlinux.org/title/Zsh
#   Gentoo / Debian zsh pages ............ https://wiki.gentoo.org/wiki/Zsh , https://wiki.debian.org/Zsh
# Oh My Zsh (OMZ)
#   Repo / plugin list / customization ... https://github.com/ohmyzsh/ohmyzsh ,
#                                          https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins ,
#                                          https://github.com/ohmyzsh/ohmyzsh/wiki/Customization
# Prompt
#   Starship guide / config / releases ... https://starship.rs/guide/ , https://starship.rs/config/ ,
#                                          https://github.com/starship/starship/releases
#   Why Powerlevel10k is not used ........ https://github.com/romkatv/powerlevel10k/issues/2690 ("life support")
# External plugins
#   zsh-autosuggestions .................. https://github.com/zsh-users/zsh-autosuggestions
#   zsh-syntax-highlighting (load LAST) .. https://github.com/zsh-users/zsh-syntax-highlighting
#   fzf-tab .............................. https://github.com/Aloxaf/fzf-tab
#   zsh-completions ...................... https://github.com/zsh-users/zsh-completions
# CLI tools
#   fzf shell integration ................ https://github.com/junegunn/fzf#setting-up-shell-integration
#   zoxide / eza / direnv ................ https://github.com/ajeetdsouza/zoxide , https://github.com/eza-community/eza , https://direnv.net/
# Root shell & security reasoning
#   Root executing user-owned zshrc is risky (compaudit complaints):
#                                          https://github.com/zsh-users/zsh-completions/issues/680
#   zsh-users thread on tainted rc files . https://www.zsh.org/mla/users/2019/msg00728.html
#   sudoers (always_set_home, secure_path) https://www.sudo.ws/docs/man/sudoers.man/
#   SELinux on Fedora .................... https://docs.fedoraproject.org/en-US/quick-docs/selinux-getting-started/
#   systemd sandboxing options ........... https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html
#
#########################################################
# Description
#########################################################
# Sets up, for the latest Fedora (KDE):
#   * zsh as the login shell of the real user (and of root, see SET_ROOT_SHELL_TO_ZSH)
#   * ONE shared, root-owned Oh My Zsh + plugin tree in /usr/local/share/zsh-nb used by
#     BOTH the normal user and root. Root never reads files from a user's home directory.
#   * Starship prompt on every machine. If Starship cannot be installed, the generated
#     .zshrc falls back to the OMZ "agnoster" theme automatically (also at runtime, so
#     removing starship later also degrades gracefully).
#   * Productivity CLI tools (fzf zoxide eza bat ripgrep fd direnv fastfetch) on machines
#     whose RAM profile is listed in CLI_TOOLS_PROFILES.
#   * A root-owned updater (nb-zsh-update) + weekly systemd timer for everything that is
#     not a dnf package (OMZ, plugins, and Starship when it was not installed from dnf).
#
# Run as root (it re-runs itself with sudo when needed). Existing zsh setups are backed up
# and then REMOVED; the script always starts fresh and never patches an old setup.
#
# NAMED OPTIONS
#   --verify-setup        Only run the Verification section (no changes are made).
#   --timestamp <value>   Timestamp used in backup/download directory names.
#                         Default: current time (YYYY-MM-DD_HH-MM-SS).
#   -h | --help           Show usage.
#
# ENVIRONMENT (optional)
#   REAL_USER             The normal user to configure. Default: the user who ran sudo.
#   FILENAME_TIMESTAMP    Same as --timestamp.
#   SYSUPDATE_CODE_BASE_DIR  Location of the system_update project.
#
# SAMPLE CALLS (assuming the caller has the same variable names)
#   With all options:
#     sudo REAL_USER="$REAL_USER" bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/zsh.sh" \
#          --timestamp "$FILENAME_TIMESTAMP"
#   With only mandatory options (there are none):
#     sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/zsh.sh"
#   Verification only:
#     sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/zsh.sh" --verify-setup
#
# REQUIRED HELPER FILES (in $SYSUPDATE_CODE_BASE_DIR/linux/common/)
#   helper_backup.sh, helper_github_release.sh
#   get_cpu_cores.sh get_ram_size.sh get_ram_profile.sh get_ssd_present.sh get_pc_type.sh
#   get_desktop_env.sh get_distro_name.sh get_cpu_model.sh

# -E: ERR trap is inherited by functions.  -e: exit on error.  -u: unset variable is an error.
# -o pipefail: a pipeline fails if ANY command in it fails (not just the last).
set -Eeuo pipefail

#########################################################
# Logging
#########################################################
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'

log_header() { echo -e "\n${CYAN}==================== $* ====================${NC}\n"; }
log_info() { echo -e "${BLUE}[INFO] $* ${NC}"; }
log_success() { echo -e "${GREEN}[✓] $* ${NC}"; }
log_warn() { echo -e "${YELLOW}[!] $* ${NC}"; }
log_error() { echo -e "${RED}[✗] $* ${NC}" >&2; }
log_die() { echo -e "${RED}[✗] $* ${NC}" >&2; exit 1; }

# When any command fails unexpectedly, say where, then let set -e stop the script.
trap 'log_error "Unexpected failure at line ${LINENO}: ${BASH_COMMAND}"' ERR

#########################################################
# Privilege check
#########################################################
# Everything below writes to /usr/local, /etc and /root, so root is required.
# sudo resets the environment, so the few variables that matter are passed explicitly.
if [[ ${EUID} -ne 0 ]]; then
  log_info "Root privileges required. Re-running with sudo."
  exec sudo --preserve-env=REAL_USER,FILENAME_TIMESTAMP,SYSUPDATE_CODE_BASE_DIR bash "$0" "$@"
fi

# sudo resets PATH to its secure_path, which on Fedora does not include /usr/local/bin (where
# Starship, AWS CLI v2 and similar tools live). Add it so detection with `command -v` works.
export PATH="/usr/local/sbin:/usr/local/bin:${PATH}"

#########################################################
# User defined variables
#########################################################
# --- Standard directories (same on all machines) ---
# ${VAR:-default} means "use VAR if it is set and non-empty, otherwise the default".
REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"                          # Path for all code projects
SYSUPDATE_CODE_BASE_DIR="${SYSUPDATE_CODE_BASE_DIR:-${CODEPROJECTS_DIR}/system_update}"  # Linux setup project
SCRIPT_DATA="${NBDIR}/nb_script_data"                             # Base dir for all stuff created by scripts
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"                  # On-access ClamAV scanning is enabled here
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"
ZSH_DOWNLOADS_DIR_BASE="${SCRIPT_DATA_DOWNLOADS}/zsh"
ZSH_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/zsh"
# The *_CURRENT_* directories contain the timestamp, which may be changed by --timestamp,
# so they are computed in infer_variables() after option processing.

# --- Install locations (root-owned, outside every home directory on purpose) ---
ZSH_SHARED_DIR="/usr/local/share/zsh-nb"            # Everything shared by user and root lives here
OMZ_DIR="${ZSH_SHARED_DIR}/oh-my-zsh"               # Oh My Zsh clone (ZSH variable points here)
NB_ZSH_LIB_DIR="/usr/local/lib/nb-zsh"              # Helpers needed by the root-run updater
UPDATER_PATH="/usr/local/sbin/nb-zsh-update"        # Manual + timer driven updater
STARSHIP_BIN="/usr/local/bin/starship"
ROOT_STARSHIP_CONFIG="${ZSH_SHARED_DIR}/starship-root.toml"
USER_STARSHIP_CONFIG="${HOME_DIR}/.config/starship.toml"
UPDATE_UNIT_NAME="nb-zsh-update"
UPDATE_TIMER_SCHEDULE="weekly"                      # systemd OnCalendar value

# --- What to install ---
BASE_PACKAGES=(zsh git curl tar util-linux-user)    # util-linux-user provides `chsh` on Fedora
CLI_TOOLS_PACKAGES=(fzf zoxide eza bat ripgrep fd-find direnv fastfetch)
CLI_TOOLS_PROFILES="mid high"                       # RAM profiles that get the CLI tools
OMZ_REPO_URL="https://github.com/ohmyzsh/ohmyzsh.git"
# Format: "directory-name|git-url". These are cloned into OMZ's custom/plugins directory.
EXTERNAL_PLUGINS=(
  "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions.git"
  "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting.git"
  "fzf-tab|https://github.com/Aloxaf/fzf-tab.git"
  "zsh-completions|https://github.com/zsh-users/zsh-completions.git"
)
STARSHIP_REPO="starship/starship"

# --- Behavior ---
SET_ROOT_SHELL_TO_ZSH=true       # `sudo su` / `sudo -i` then land in zsh. Safe: zsh lives on the root filesystem.
ENABLE_BGNOTIFY=true             # Desktop notification when a long command finishes (KDE + kdialog only)
BGNOTIFY_THRESHOLD=30            # Seconds a command must run before a notification is sent
VSCODE_BINARY="codium"           # Value of $VSCODE for the OMZ vscode plugin (code | code-insiders | codium | cursor)
NTFY_URL=""                      # Optional: e.g. https://ntfy.sh/<your-topic>. If set, a completion message is sent.

#########################################################
# Inferred variables
#########################################################
# Filled in by infer_variables(); declared here so the full list is visible in one place.
CPU_CORES="" RAM_MB="" RAM_PROFILE="" SSD_PRESENT="" PC_TYPE="" DESKTOP="" DISTRO="" CPU_MODEL=""
ZSH_CURRENT_BACKUP_DIR="" ZSH_CURRENT_DOWNLOADS_DIR="" STARSHIP_CURRENT_DOWNLOADS_DIR=""
ZSH_BIN="" INSTALL_CLI_TOOLS="false"
STARSHIP_OK="false"              # Set to true only after Starship is installed AND runs
OMZ_PLUGINS_LIST=""              # Final space separated OMZ plugin list (only plugins that exist)
STARSHIP_FORMAT="" STARSHIP_SCAN_TIMEOUT="" STARSHIP_CMD_TIMEOUT=""
AUTOSUGGEST_STRATEGY="" AUTOSUGGEST_BUFFER_MAX="" HIGHLIGHTERS=""
VERIFY_ONLY="false"

infer_variables() {
  local common="${SYSUPDATE_CODE_BASE_DIR}/linux/common"
  [[ -d "$common" ]] || log_die "Helper directory not found: ${common} (set SYSUPDATE_CODE_BASE_DIR)"

  # Reuse the tried-and-tested detection scripts instead of re-implementing them here.
  CPU_CORES=$(sh "${common}/get_cpu_cores.sh")
  RAM_MB=$(sh "${common}/get_ram_size.sh")
  RAM_PROFILE=$(sh "${common}/get_ram_profile.sh")     # low | mid | high
  SSD_PRESENT=$(sh "${common}/get_ssd_present.sh")     # true | false
  PC_TYPE=$(sh "${common}/get_pc_type.sh")             # laptop | desktop | server
  DESKTOP=$(sh "${common}/get_desktop_env.sh")         # kde | gnome | ...
  DISTRO=$(sh "${common}/get_distro_name.sh")          # fedora | ...
  CPU_MODEL=$(sh "${common}/get_cpu_model.sh")

  ZSH_CURRENT_BACKUP_DIR="${ZSH_BACKUP_DIR_BASE}/zsh_${FILENAME_TIMESTAMP}"
  ZSH_CURRENT_DOWNLOADS_DIR="${ZSH_DOWNLOADS_DIR_BASE}/zsh_${FILENAME_TIMESTAMP}"
  STARSHIP_CURRENT_DOWNLOADS_DIR="${SCRIPT_DATA_DOWNLOADS}/starship/starship_${FILENAME_TIMESTAMP}"

  # Do the CLI tools get installed on this machine? (word match against the profile list)
  INSTALL_CLI_TOOLS="false"
  local p
  for p in ${CLI_TOOLS_PROFILES}; do
    if [[ "$p" == "$RAM_PROFILE" ]]; then
      INSTALL_CLI_TOOLS="true"
    fi
  done

  # Hardware-dependent tuning. Low-RAM machines get the cheapest settings:
  #  * autosuggestions: "history" only (the "completion" strategy runs the completion
  #    system on every keystroke, which is what makes old machines feel laggy)
  #  * syntax highlighting: only the "main" highlighter
  #  * Starship: fewer modules (every module that detects a language scans files)
  if [[ "$RAM_PROFILE" == "low" ]]; then
    AUTOSUGGEST_STRATEGY="history"
    AUTOSUGGEST_BUFFER_MAX="20"
    HIGHLIGHTERS="main"
    STARSHIP_FORMAT='$username$directory$git_branch$git_status$status$line_break$character'
  else
    AUTOSUGGEST_STRATEGY="history completion match_prev_cmd"
    AUTOSUGGEST_BUFFER_MAX="50"
    HIGHLIGHTERS="main brackets pattern cursor"
    STARSHIP_FORMAT='$username$directory$git_branch$git_status$python$rust$docker_context$aws$status$line_break$character'
  fi
  STARSHIP_CMD_TIMEOUT="500"
  # Spinning disks make directory scans slower, so give Starship more time before it gives up.
  if [[ "$SSD_PRESENT" == "true" ]]; then STARSHIP_SCAN_TIMEOUT="30"; else STARSHIP_SCAN_TIMEOUT="60"; fi
}

#########################################################
# Named Options processing
#########################################################
usage() {
  # Print the "NAMED OPTIONS" part of the header comment of this file.
  sed -n '/^# NAMED OPTIONS/,/^# REQUIRED HELPER FILES/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

parse_options() {
  # `$#` is the number of remaining arguments; `shift` drops the first one.
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verify-setup)
        VERIFY_ONLY="true"
        shift
        ;;
      --timestamp)
        [[ $# -ge 2 ]] || log_die "--timestamp requires a value"
        FILENAME_TIMESTAMP="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_die "Unknown option: $1 (try --help)"
        ;;
    esac
  done
}

#########################################################
# Helpers
#########################################################
# Reusable helpers live in separate files (helper_<functionality>.sh); the ones below are
# specific to this script.

load_helpers() {
  local f
  for f in helper_backup.sh helper_github_release.sh; do
    [[ -r "${SYSUPDATE_CODE_BASE_DIR}/linux/common/${f}" ]] \
      || log_die "Missing helper file: ${SYSUPDATE_CODE_BASE_DIR}/linux/common/${f}"
    # shellcheck source=/dev/null
    source "${SYSUPDATE_CODE_BASE_DIR}/linux/common/${f}"
  done
}

# True if a command exists for root.
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# True if a command exists in the REAL USER's login environment (e.g. ~/.local/bin/uv),
# which root's PATH would not contain. `runuser -l` starts a login shell for that user.
user_has_cmd() { runuser -l "$REAL_USER" -c "command -v '$1'" >/dev/null 2>&1; }

require_fedora() {
  [[ "$DISTRO" == "fedora" ]] || log_die "This part is Fedora specific (dnf). Detected distro: ${DISTRO}"
}

is_kde() { [[ "$DESKTOP" == "kde" ]]; }

# Replace @KEY@ placeholders in a template. Usage: render "$TEMPLATE" KEY=value KEY2=value2
# Plain bash string replacement is used instead of sed so that values containing
# slashes, dollar signs or ampersands cannot break anything.
render() {
  local out="$1"; shift
  local kv
  for kv in "$@"; do
    out="${out//@${kv%%=*}@/${kv#*=}}"
  done
  printf '%s' "$out"
}

# Write a file atomically with explicit ownership and mode:
#   write_file <path> <owner> <group> <mode> <content>
# The content goes to a temporary file in the SAME directory first, then `mv` swaps it in,
# so a crash can never leave a half-written .zshrc behind.
write_file() {
  local path="$1" owner="$2" group="$3" mode="$4" content="$5" tmp
  tmp="$(mktemp "${path}.XXXXXX")"
  printf '%s\n' "$content" > "$tmp"
  chown "${owner}:${group}" "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$path"
}

# Bash 5.2 gives "&" a special meaning in replacement strings. Switch that off if supported.
shopt -u patsub_replacement 2>/dev/null || true

# Directories under the user's nb folder must belong to the user even though this script runs as
# root and may be the one creating them.
prepare_script_dirs() {
  local d
  for d in "$SCRIPT_DATA" "$SCRIPT_DATA_DOWNLOADS" "$SCRIPT_DATA_BACKUPS" "$ZSH_DOWNLOADS_DIR_BASE" "$ZSH_BACKUP_DIR_BASE"; do
    install -d -o "$REAL_USER" -g "$REAL_USER" -m 0755 "$d"
  done
}

#########################################################
# Backup
#########################################################
# Everything this script touches is copied to ZSH_CURRENT_BACKUP_DIR first. That includes
# locations used by older, hand-made setups (other plugin managers, p10k config, old
# backups of .zshrc, etc.). Root's history files are deliberately NOT copied: they can
# contain secrets and a backup directory under the user's home would expose them.
backup_existing() {
  log_header "Backup"
  mkdir -p "$ZSH_CURRENT_BACKUP_DIR"

  local -a paths=(
    # --- User files ---
    "${HOME_DIR}/.zshrc" "${HOME_DIR}/.zshenv" "${HOME_DIR}/.zprofile" "${HOME_DIR}/.zlogin" "${HOME_DIR}/.zlogout"
    "${HOME_DIR}/.zsh_history"            # history is KEPT in place; the copy is only a safety net
    "${HOME_DIR}/.oh-my-zsh" "${HOME_DIR}/.zsh" "${HOME_DIR}/.config/zsh" "${HOME_DIR}/.p10k.zsh"
    "${HOME_DIR}/.config/starship.toml"
    # --- Leftovers of other plugin managers / older setups ---
    "${HOME_DIR}/.zplug" "${HOME_DIR}/.zinit" "${HOME_DIR}/.local/share/zinit" "${HOME_DIR}/.antigen" "${HOME_DIR}/.zim"
    "${HOME_DIR}/.local/share/zsh"
    # --- Root files (history excluded) ---
    "/root/.zshrc" "/root/.zshenv" "/root/.zprofile" "/root/.oh-my-zsh" "/root/.config/starship.toml"
    # --- System files this script modifies or owns ---
    "/etc/zshenv" "/etc/zshrc" "/etc/zprofile" "/etc/zlogin" "/etc/zlogout" "/etc/zsh" "/etc/shells"
    "${ZSH_SHARED_DIR}" "${NB_ZSH_LIB_DIR}" "${UPDATER_PATH}" "${STARSHIP_BIN}"
    "/etc/systemd/system/${UPDATE_UNIT_NAME}.service" "/etc/systemd/system/${UPDATE_UNIT_NAME}.timer"
  )

  # Old timestamped backups made by the previous scripts (e.g. .zshrc_nbbkp_<time>).
  local f
  for f in "${HOME_DIR}"/.zshrc_nbbkp_* "${HOME_DIR}"/.zshrc.pre-oh-my-zsh*; do
    if [[ -e "$f" ]]; then paths+=("$f"); fi
  done

  for f in "${paths[@]}"; do
    backup_path "$f" "$ZSH_CURRENT_BACKUP_DIR"
  done

  # Non-file state: which login shell each account has right now.
  backup_record "$ZSH_CURRENT_BACKUP_DIR" "passwd_entries" getent passwd root "$REAL_USER"
  backup_record "$ZSH_CURRENT_BACKUP_DIR" "installed_packages" rpm -q zsh starship git

  # The backup directory belongs to the real user but is private to them (mode 0700).
  chown -R "${REAL_USER}:${REAL_USER}" "$ZSH_BACKUP_DIR_BASE"
  chmod 0700 "$ZSH_CURRENT_BACKUP_DIR"
  log_success "Backup written to ${ZSH_CURRENT_BACKUP_DIR}"
}

#########################################################
# Reset
#########################################################
# Remove every previous setup completely. Nothing is "repaired in place". All of it was
# backed up above. The shell history (~/.zsh_history) is user data and is kept.
reset_existing() {
  log_header "Reset"

  # OMZ in the user's and root's home (old layout) and the shared tree (previous run of this script).
  rm -rf "${HOME_DIR}/.oh-my-zsh" "/root/.oh-my-zsh" "${ZSH_SHARED_DIR}" "${NB_ZSH_LIB_DIR}"
  rm -rf "${HOME_DIR}/.cache/oh-my-zsh" "/root/.cache/oh-my-zsh"
  rm -f  "${HOME_DIR}"/.zcompdump* /root/.zcompdump*

  # Config files that will be regenerated.
  rm -f "${HOME_DIR}/.zshrc" "/root/.zshrc" "${USER_STARSHIP_CONFIG}" "/root/.config/starship.toml"

  # Updater, units, and Starship (but only when Starship is NOT owned by a dnf package).
  if systemctl list-unit-files "${UPDATE_UNIT_NAME}.timer" >/dev/null 2>&1; then
    systemctl disable --now "${UPDATE_UNIT_NAME}.timer" >/dev/null 2>&1 || true
  fi
  rm -f "/etc/systemd/system/${UPDATE_UNIT_NAME}.service" "/etc/systemd/system/${UPDATE_UNIT_NAME}.timer" "${UPDATER_PATH}"
  if ! rpm -q starship >/dev/null 2>&1; then
    rm -f "${STARSHIP_BIN}"
  fi

  # Remove our marked block from /etc/zshenv (the rest of the file is left alone).
  if [[ -f /etc/zshenv ]]; then
    sed -i '/^# >>> nb-zsh root guard >>>$/,/^# <<< nb-zsh root guard <<<$/d' /etc/zshenv
  fi
  systemctl daemon-reload
  log_success "Previous zsh setup removed"
}

#########################################################
# Packages
#########################################################
install_packages() {
  log_header "Packages"
  require_fedora

  # Packages are installed ONE BY ONE: a single unavailable package would otherwise abort the
  # whole transaction, and the failure message would not say which package was the problem.
  local pkg
  for pkg in "${BASE_PACKAGES[@]}"; do
    if dnf install -y "$pkg" >/dev/null 2>&1; then
      log_success "dnf: ${pkg}"
    else
      log_die "Required package could not be installed: ${pkg}"
    fi
  done

  ZSH_BIN="$(command -v zsh)"
  [[ -x "$ZSH_BIN" ]] || log_die "zsh not found after installation"

  if [[ "$INSTALL_CLI_TOOLS" == "true" ]]; then
    log_info "RAM profile '${RAM_PROFILE}': installing productivity CLI tools"
    for pkg in "${CLI_TOOLS_PACKAGES[@]}"; do
      if dnf install -y "$pkg" >/dev/null 2>&1; then
        log_success "dnf: ${pkg}"
      else
        log_warn "Optional package not available, skipped: ${pkg}"
      fi
    done
  else
    log_info "RAM profile '${RAM_PROFILE}': CLI tools skipped (keeps the shell light on this machine)"
  fi
}

#########################################################
# Shared Oh My Zsh
#########################################################
# Cloning happens inside SCRIPT_DATA_DOWNLOADS, a directory with on-access ClamAV scanning,
# so no extra clamscan run is needed. The scanned clone is then copied to its final place.
install_shared_omz() {
  log_header "Oh My Zsh (shared, root-owned)"
  mkdir -p "$ZSH_CURRENT_DOWNLOADS_DIR"

  # `git clone --depth=1` fetches only the newest commit: much smaller and faster.
  git clone --quiet --depth=1 "$OMZ_REPO_URL" "${ZSH_CURRENT_DOWNLOADS_DIR}/ohmyzsh" \
    || log_die "Could not clone Oh My Zsh"

  mkdir -p "$ZSH_SHARED_DIR"
  cp -a "${ZSH_CURRENT_DOWNLOADS_DIR}/ohmyzsh" "$OMZ_DIR"

  local entry name url
  for entry in "${EXTERNAL_PLUGINS[@]}"; do
    name="${entry%%|*}"   # text before the first "|"
    url="${entry#*|}"     # text after the first "|"
    if git clone --quiet --depth=1 "$url" "${ZSH_CURRENT_DOWNLOADS_DIR}/${name}"; then
      mkdir -p "${OMZ_DIR}/custom/plugins"
      cp -a "${ZSH_CURRENT_DOWNLOADS_DIR}/${name}" "${OMZ_DIR}/custom/plugins/${name}"
      log_success "plugin: ${name} ($(git -C "${OMZ_DIR}/custom/plugins/${name}" rev-parse --short HEAD))"
    else
      log_warn "Could not clone plugin ${name}; the generated .zshrc skips missing plugins"
    fi
  done

  # Ownership and permissions: root owns everything, nobody else can write.
  # Why: the shell of every user (and root) executes these files. If a normal user could modify
  # them, that user could run code as root the next time root starts zsh.
  chown -R root:root "$ZSH_SHARED_DIR"
  chmod -R go-w "$ZSH_SHARED_DIR"
  chmod 0755 "$ZSH_SHARED_DIR"
  chown -R "${REAL_USER}:${REAL_USER}" "${ZSH_DOWNLOADS_DIR_BASE}"
  log_success "Oh My Zsh installed at ${OMZ_DIR}"
}

# Keep only plugin names that actually exist in this OMZ version. OMZ prints a warning on every
# shell start for a missing plugin, so filtering here avoids permanent noise.
build_plugin_list() {
  local -a wanted=(git sudo colored-man-pages command-not-found)
  if [[ "$DISTRO" == "fedora" ]]; then wanted+=(dnf); fi

  if [[ "$RAM_PROFILE" != "low" ]]; then
    wanted+=(python pip ssh)
    if has_cmd firewall-cmd; then wanted+=(firewalld); fi
    if user_has_cmd uv; then wanted+=(uv); fi
    if user_has_cmd gh; then wanted+=(gh); fi
    if has_cmd docker; then wanted+=(docker docker-compose); fi
    if has_cmd podman; then wanted+=(podman); fi
    if user_has_cmd aws; then wanted+=(aws); fi
    if has_cmd kubectl; then wanted+=(kubectl); fi
    if has_cmd helm; then wanted+=(helm); fi
    if user_has_cmd cargo || user_has_cmd rustup; then wanted+=(rust); fi
    if has_cmd psql; then wanted+=(postgres); fi
    if has_cmd tailscale; then wanted+=(tailscale); fi
    if user_has_cmd "$VSCODE_BINARY"; then wanted+=(vscode); fi
    # bgnotify needs a desktop notifier. On KDE that is kdialog. Not useful on servers.
    if [[ "$ENABLE_BGNOTIFY" == "true" && "$PC_TYPE" != "server" ]] && is_kde && has_cmd kdialog; then
      wanted+=(bgnotify)
    fi
  fi

  local p
  OMZ_PLUGINS_LIST=""
  for p in "${wanted[@]}"; do
    if [[ -d "${OMZ_DIR}/plugins/${p}" ]]; then
      OMZ_PLUGINS_LIST+="${p} "
    else
      log_warn "OMZ plugin not found in this version, skipped: ${p}"
    fi
  done
  OMZ_PLUGINS_LIST="${OMZ_PLUGINS_LIST% }"   # trim the trailing space
  log_info "OMZ plugins: ${OMZ_PLUGINS_LIST}"
}

#########################################################
# Starship
#########################################################
# Order of attempts: 1) dnf package (updated by the normal system update),
#                    2) official release binary with SHA-256 verification (updated by nb-zsh-update).
# Returns non-zero if neither works; the caller then continues with the agnoster fallback.
install_starship() {
  log_header "Starship prompt"

  # Command substitution instead of a pipe into `grep -q`: with `pipefail`, grep exiting early can
  # make the left side die from SIGPIPE and the pipeline report failure even though it matched.
  if [[ -n "$(dnf repoquery --quiet starship 2>/dev/null)" ]]; then
    if dnf install -y starship >/dev/null 2>&1; then
      log_success "Starship installed from dnf"
      return 0
    fi
    log_warn "dnf install of starship failed; trying the release binary"
  fi

  local tag triple asset
  tag="$(github_latest_tag "$STARSHIP_REPO")" || { log_warn "Could not determine the latest Starship release"; return 1; }
  triple="$(rust_musl_triple)" || { log_warn "Unsupported CPU architecture: $(uname -m)"; return 1; }
  asset="starship-${triple}.tar.gz"

  github_download_verified "$STARSHIP_REPO" "$tag" "$asset" "$STARSHIP_CURRENT_DOWNLOADS_DIR" \
    || { log_warn "Starship download or checksum verification failed"; return 1; }

  tar -xzf "${STARSHIP_CURRENT_DOWNLOADS_DIR}/${asset}" -C "$STARSHIP_CURRENT_DOWNLOADS_DIR" starship \
    || { log_warn "Could not extract Starship"; return 1; }

  # `install` copies and sets owner/mode in one step. Files in /usr/local/bin must be root-owned.
  install -o root -g root -m 0755 "${STARSHIP_CURRENT_DOWNLOADS_DIR}/starship" "$STARSHIP_BIN" \
    || return 1
  chown -R "${REAL_USER}:${REAL_USER}" "${SCRIPT_DATA_DOWNLOADS}/starship"
  log_success "Starship ${tag} installed from the official release (checksum verified)"
}

starship_works() {
  # A real functional test: ask Starship to render a prompt with an empty config.
  has_cmd starship && STARSHIP_CONFIG=/dev/null starship prompt >/dev/null 2>&1
}

#########################################################
# Configuration files
#########################################################

# ---------- Templates -------------------------------------------------------
# Single-quoted heredocs (<<'EOF') keep every $ and \ literal, so zsh code can be written
# naturally. @KEY@ markers are filled in by render().

# shellcheck disable=SC2016  # the $ signs below are zsh/TOML syntax, not bash expansions
IFS= read -r -d '' TEMPLATE_USER_ZSHRC <<'EOF' || true
# ~/.zshrc - generated by zsh.sh on @TIMESTAMP@
# Machine profile when generated: RAM=@RAM_PROFILE@  PC=@PC_TYPE@  desktop=@DESKTOP@  starship=@STARSHIP_OK@
# Everything above the "Added by nbhirud" block is regenerated by zsh.sh. Put personal
# additions in the "Added by nbhirud" block at the end or re-run the script after changing it.

#################################################################
# PATH
#################################################################
# typeset -U makes the array keep only the first occurrence of each entry.
# /usr/local/bin holds Starship; ~/.local/bin holds uv, pipx and similar user installs.
typeset -U path PATH
path=("$HOME/.local/bin" "$HOME/bin" /usr/local/bin $path)

#################################################################
# Oh My Zsh (shared, root-owned copy: nobody can edit it without sudo)
#################################################################
export ZSH="@ZSH_DIR@"
export ZSH_CUSTOM="$ZSH/custom"
# OMZ writes caches. The shared tree is read-only for users, so caches go to the user's own cache dir.
export ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh"
[[ -d "$ZSH_CACHE_DIR/completions" ]] || mkdir -p "$ZSH_CACHE_DIR/completions"

# Prompt: Starship if it is installed, otherwise the OMZ "agnoster" theme. Decided at every
# shell start, so uninstalling Starship later degrades gracefully instead of breaking the prompt.
if (( $+commands[starship] )); then
  ZSH_THEME=""
else
  ZSH_THEME="agnoster"
fi

# Updates are done by /usr/local/sbin/nb-zsh-update (root). OMZ's own updater cannot write to the
# shared tree, and disabling it also stops OMZ from contacting GitHub on shell start.
zstyle ':omz:update' mode disabled

ENABLE_CORRECTION="true"
COMPLETION_WAITING_DOTS="true"

# History. OMZ sets the sharing/dedup options (SHARE_HISTORY, HIST_IGNORE_SPACE, ...).
# A command typed with a leading space is not saved. HISTORY_IGNORE additionally drops
# lines that look like they contain secrets.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
HISTORY_IGNORE='(*password*|*passwd*|*token*|*secret*|*api_key*|*apikey*)'

# Extra completion definitions (zsh-completions). Must be in fpath BEFORE compinit runs inside OMZ.
fpath+=("$ZSH_CUSTOM/plugins/zsh-completions/src")

VSCODE=@VSCODE_BINARY@          # used by the OMZ vscode plugin
bgnotify_threshold=@BGNOTIFY_THRESHOLD@

plugins=(@PLUGINS@)

# Tuning chosen for this machine's RAM profile
ZSH_AUTOSUGGEST_STRATEGY=(@AUTOSUGGEST_STRATEGY@)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=@AUTOSUGGEST_BUFFER_MAX@
ZSH_HIGHLIGHT_HIGHLIGHTERS=(@HIGHLIGHTERS@)
ZSH_HIGHLIGHT_MAXLENGTH=300

source "$ZSH/oh-my-zsh.sh"

#################################################################
# External plugins - sourced here (after OMZ ran compinit) in the order their docs require:
#   fzf-tab first, then autosuggestions; syntax highlighting is sourced at the very end of this file.
#################################################################
_nb_source() { [[ -r "$1" ]] && source "$1"; }

if (( $+commands[fzf] )); then
  # fzf-tab replaces the completion menu with fzf. These two zstyles are recommended by its README.
  zstyle ':completion:*' menu no
  zstyle ':completion:*:descriptions' format '[%d]'
  _nb_source "$ZSH_CUSTOM/plugins/fzf-tab/fzf-tab.plugin.zsh"
fi
_nb_source "$ZSH_CUSTOM/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"

#################################################################
# CLI tool integrations (each one only if the tool is installed)
#################################################################
if (( $+commands[fzf] )); then
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
  if (( $+commands[fd] )); then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  fi
  # `fzf --zsh` (fzf >= 0.48) prints the key bindings: Ctrl-R history, Ctrl-T files, Alt-C cd.
  source <(fzf --zsh 2>/dev/null) 2>/dev/null
fi
(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"    # `z <partial-dir-name>` jumps to frequent dirs
(( $+commands[direnv] )) && eval "$(direnv hook zsh)"    # per-directory environments (.envrc, needs `direnv allow`)

if (( $+commands[eza] )); then
  alias ls='eza --group-directories-first'
  alias ll='eza -lah --git --group-directories-first'
  alias lt='eza --tree --level=2'
fi
(( $+commands[bat] )) && alias bcat='bat --paging=never'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -I'
alias ports='ss -tulpn'
(( $+commands[fastfetch] )) && alias ff='fastfetch'

#################################################################
# Prompt
#################################################################
if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
else
  # --- agnoster fallback only ---
  # Show the hostname on the right to identify SSH sessions more obviously.
  export RPROMPT='%F{yellow}%m%f'
  # Mark SSH sessions in the agnoster prompt. (Previously noted as "not working?": the likely
  # cause is that agnoster only calls prompt_context for non-default users; see Notes in zsh.sh.)
  if [[ -n "$SSH_CONNECTION" ]]; then
    prompt_context() {
      prompt_segment red black "%(!.%{%F{yellow}%}.)%n@%m [SSH]"
    }
  fi
fi
EOF

IFS= read -r -d '' TEMPLATE_USER_ZSHRC_NBBLOCK <<'EOF' || true

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
# ORIGINAL (kept for reference): ... && uv self update && omz update -y && ...
#   `omz update` cannot work any more: Oh My Zsh now lives in a root-owned shared directory, so a
#   normal user cannot pull into it. The replacement below runs the root-owned updater, which also
#   updates the plugins and (when not installed from dnf) Starship. The "|| true" keeps a failed
#   download from skipping the later `. torsocks on` in the chain.
alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && aws update && uv self update && (sudo /usr/local/sbin/nb-zsh-update || true) && . torsocks on && fastfetch"
# alias nbupdateproton=". torsocks off && cd /home/nbhirud/nb/CodeProjects/system_update/ && sh /home/nbhirud/nb/CodeProjects/system_update/linux/security_os_level/proton_ag.sh --setup-type full --desktop kde && cd && . torsocks on"
alias nbupdateextra=". torsocks off && sh /home/nbhirud/nb/CodeProjects/system_update/linux/fedora/update_all.sh && nbupdate"

# https://docs.fedoraproject.org/en-US/quick-docs/upgrading-fedora-offline/
# alias nbdistu="sudo sudo dnf upgrade --refresh -y && sudo sudo dnf system-upgrade download --releasever=43 -y"
alias nbreload="systemctl daemon-reload && source ~/.zshrc"
# Possible improvement (not active): `exec zsh` replaces the running shell with a fresh one, which
# re-reads every startup file cleanly, whereas `source ~/.zshrc` re-runs it inside the old shell
# (hooks and aliases get registered twice). Also, `systemctl daemon-reload` is only needed after
# editing unit files, not for zsh changes:
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
# Stuff other than aliases:
############################

# REPLACED: these two lines ran compinit a second time (slow: it rescans every completion file) and
# loaded fzf-tab after the other plugins. The generated section above now sources fzf-tab right
# after OMZ's single compinit run, which is the order the fzf-tab README requires.
# autoload -U compinit; compinit
# source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab/fzf-tab.plugin.zsh

# MOVED: the RPROMPT hostname and the SSH marker for agnoster now live in the "Prompt" section above
# (only used when Starship is missing). Starship shows the hostname via its own config.


############################
# Enable tor:
############################

# . torsocks on
# The guard prevents an error on every new shell on a machine where torsocks is not installed.
# if (( $+commands[torsocks] )); then
#   . torsocks on
# fi

# Only activate torsocks if a true interactive terminal is attached (skips scripts and test runs)
# torsocks only activates when a human opens a genuine interactive terminal window
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


#################################################################
# Syntax highlighting MUST be the last thing sourced (its README requires it: it wraps widgets
# that other plugins define, so anything loaded after it would not be highlighted).
#################################################################
_nb_source "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
EOF

# shellcheck disable=SC2016
IFS= read -r -d '' TEMPLATE_ROOT_ZSHRC <<'EOF' || true
# /root/.zshrc - generated by zsh.sh on @TIMESTAMP@
# OWNED BY ROOT. Loads the shared, root-owned Oh My Zsh tree. It deliberately does NOT source
# any file from a normal user's home directory: such files are writable by that user, so
# sourcing them as root would hand that user root privileges.

# sudo's secure_path on Fedora omits /usr/local/bin, where Starship lives.
typeset -U path PATH
path=(/usr/local/bin /usr/local/sbin $path)

export ZSH="@ZSH_DIR@"
export ZSH_CUSTOM="$ZSH/custom"
export ZSH_CACHE_DIR="/root/.cache/oh-my-zsh"
[[ -d "$ZSH_CACHE_DIR/completions" ]] || mkdir -p "$ZSH_CACHE_DIR/completions"

ZSH_THEME=""
zstyle ':omz:update' mode disabled
fpath+=("$ZSH_CUSTOM/plugins/zsh-completions/src")
plugins=(git sudo colored-man-pages)

HISTFILE="/root/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
HISTORY_IGNORE='(*password*|*passwd*|*token*|*secret*|*api_key*|*apikey*)'

ZSH_AUTOSUGGEST_STRATEGY=(history)
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main)

source "$ZSH/oh-my-zsh.sh"

_nb_source() { [[ -r "$1" ]] && source "$1"; }
_nb_source "$ZSH_CUSTOM/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"

alias ll='ls -lah --color=auto'
alias rm='rm -I'
alias cp='cp -i'
alias mv='mv -i'

# Root uses its own Starship config (red, with a "#" prompt character), also root-owned.
if (( $+commands[starship] )); then
  export STARSHIP_CONFIG="@ROOT_STARSHIP_CONFIG@"
  eval "$(starship init zsh)"
else
  PROMPT='%B%F{red}%n@%m%f %F{cyan}%~%f %F{red}#%f%b '
fi

_nb_source "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
EOF

IFS= read -r -d '' TEMPLATE_STARSHIP_USER <<'EOF' || true
"$schema" = 'https://starship.rs/config-schema.json'
# Generated by zsh.sh on @TIMESTAMP@ for RAM profile "@RAM_PROFILE@".
# The same file works for bash and zsh; only the init line in the shell's rc file differs.
# Starship sends no telemetry.

add_newline = true
command_timeout = @CMD_TIMEOUT@
scan_timeout = @SCAN_TIMEOUT@

format = "@FORMAT@"
# right_format is rendered by zsh (bash ignores it unless extra tooling is used).
right_format = "$cmd_duration$hostname"

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"

[directory]
truncation_length = 3
truncate_to_repo = true

[username]
# Shown only for root or in an SSH session.
show_always = false
style_user = "bold yellow"
style_root = "bold red"
format = "[$user]($style) "

[hostname]
# Always shown (on the right) so every terminal says which machine it is; SSH sessions get a marker.
ssh_only = false
ssh_symbol = "SSH:"
format = "[$ssh_symbol$hostname]($style)"
style = "bold yellow"

[cmd_duration]
min_time = 3000
format = "[$duration]($style) "
style = "yellow"

[status]
disabled = false
format = "[$status]($style) "
style = "bold red"
EOF

IFS= read -r -d '' TEMPLATE_STARSHIP_ROOT <<'EOF' || true
"$schema" = 'https://starship.rs/config-schema.json'
# Generated by zsh.sh on @TIMESTAMP@. Root-owned config used only by root's shell.
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

# ---------- Writers ---------------------------------------------------------
write_configs() {
  log_header "Configuration files"

  # Starship configs (the user's file is theirs to edit; root's file is root-owned).
  install -d -o "$REAL_USER" -g "$REAL_USER" -m 0755 "${HOME_DIR}/.config"
  write_file "$USER_STARSHIP_CONFIG" "$REAL_USER" "$REAL_USER" 0644 "$(render "$TEMPLATE_STARSHIP_USER" \
      TIMESTAMP="$FILENAME_TIMESTAMP" RAM_PROFILE="$RAM_PROFILE" CMD_TIMEOUT="$STARSHIP_CMD_TIMEOUT" \
      SCAN_TIMEOUT="$STARSHIP_SCAN_TIMEOUT" FORMAT="$STARSHIP_FORMAT")"
  write_file "$ROOT_STARSHIP_CONFIG" root root 0644 "$(render "$TEMPLATE_STARSHIP_ROOT" TIMESTAMP="$FILENAME_TIMESTAMP")"

  # User's .zshrc = generated part + the personal block (aliases etc.).
  local user_rc
  user_rc="$(render "$TEMPLATE_USER_ZSHRC" \
      TIMESTAMP="$FILENAME_TIMESTAMP" RAM_PROFILE="$RAM_PROFILE" PC_TYPE="$PC_TYPE" DESKTOP="$DESKTOP" \
      STARSHIP_OK="$STARSHIP_OK" ZSH_DIR="$OMZ_DIR" VSCODE_BINARY="$VSCODE_BINARY" \
      BGNOTIFY_THRESHOLD="$BGNOTIFY_THRESHOLD" PLUGINS="$OMZ_PLUGINS_LIST" \
      AUTOSUGGEST_STRATEGY="$AUTOSUGGEST_STRATEGY" AUTOSUGGEST_BUFFER_MAX="$AUTOSUGGEST_BUFFER_MAX" \
      HIGHLIGHTERS="$HIGHLIGHTERS")"
  write_file "${HOME_DIR}/.zshrc" "$REAL_USER" "$REAL_USER" 0644 "${user_rc}${TEMPLATE_USER_ZSHRC_NBBLOCK}"

  # Root's .zshrc: root-owned and not writable by anyone else.
  write_file "/root/.zshrc" root root 0644 "$(render "$TEMPLATE_ROOT_ZSHRC" \
      TIMESTAMP="$FILENAME_TIMESTAMP" ZSH_DIR="$OMZ_DIR" ROOT_STARSHIP_CONFIG="$ROOT_STARSHIP_CONFIG")"

  # The history file must be private. zsh creates it 0600 itself; this also fixes an old one.
  if [[ -f "${HOME_DIR}/.zsh_history" ]]; then
    chown "${REAL_USER}:${REAL_USER}" "${HOME_DIR}/.zsh_history"
    chmod 0600 "${HOME_DIR}/.zsh_history"
  fi
  log_success "Configuration files written"
}

# A guard in /etc/zshenv (read by every zsh, before any user file): if root runs zsh with a HOME
# that is not /root (for example `sudo -E zsh`, or a sudoers setup that keeps HOME), the RCS
# option is switched off, so zsh will not read ~/.zshenv, ~/.zshrc, etc. from that home.
# Result: root can never execute startup files that a normal user can edit.
install_root_guard() {
  local marker_start='# >>> nb-zsh root guard >>>'
  local marker_end='# <<< nb-zsh root guard <<<'
  touch /etc/zshenv
  {
    echo "${marker_start}"
    echo '# Added by zsh.sh. Removes root'"'"'s exposure to user-writable startup files.'
    echo 'if (( EUID == 0 )) && [[ "${HOME:-/root}" != "/root" ]]; then'
    echo '  unsetopt rcs'
    echo 'fi'
    echo "${marker_end}"
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

  # A login shell must be listed in /etc/shells or login tools may refuse it. The zsh package
  # normally adds itself; this covers the case where it did not.
  if ! grep -qx "$ZSH_BIN" /etc/shells; then
    echo "$ZSH_BIN" >> /etc/shells
  fi

  # usermod changes the shell directly (no password prompt, unlike chsh).
  usermod -s "$ZSH_BIN" "$REAL_USER"
  log_success "Login shell of ${REAL_USER}: ${ZSH_BIN} (takes effect at the next login)"

  if [[ "$SET_ROOT_SHELL_TO_ZSH" == "true" ]]; then
    usermod -s "$ZSH_BIN" root
    log_success "Login shell of root: ${ZSH_BIN}"
  fi
}

#########################################################
# Updater
#########################################################
# Everything that is NOT a dnf package (OMZ, plugins, Starship from a release) is updated by a
# root-owned script. It is installed under /usr/local, NOT run from the user's home: a root
# service must never execute a file that a normal user can modify.
install_updater() {
  log_header "Updater (manual command + weekly timer)"

  install -d -o root -g root -m 0755 "$NB_ZSH_LIB_DIR"
  install -o root -g root -m 0644 "${SYSUPDATE_CODE_BASE_DIR}/linux/common/helper_github_release.sh" \
    "${NB_ZSH_LIB_DIR}/helper_github_release.sh"

  local updater
  updater="$(render "$UPDATER_TEMPLATE" ZSH_SHARED_DIR="$ZSH_SHARED_DIR" NB_ZSH_LIB_DIR="$NB_ZSH_LIB_DIR" \
      STARSHIP_BIN="$STARSHIP_BIN" STARSHIP_REPO="$STARSHIP_REPO")"
  write_file "$UPDATER_PATH" root root 0755 "$updater"

  # --- systemd service: sandboxed, because it runs as root and talks to the internet ---
  cat > "/etc/systemd/system/${UPDATE_UNIT_NAME}.service" <<EOF
[Unit]
Description=Update Oh My Zsh, zsh plugins and Starship (nb-zsh)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=${UPDATER_PATH}
# Sandboxing: the updater can only write to the two places it needs.
ProtectSystem=strict
ReadWritePaths=${ZSH_SHARED_DIR} /usr/local/bin
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
Nice=10
IOSchedulingClass=idle
EOF

  cat > "/etc/systemd/system/${UPDATE_UNIT_NAME}.timer" <<EOF
[Unit]
Description=Weekly nb-zsh update

[Timer]
OnCalendar=${UPDATE_TIMER_SCHEDULE}
# Persistent=true: if the PC was off at the scheduled time, run at the next boot.
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF
  chown root:root "/etc/systemd/system/${UPDATE_UNIT_NAME}".{service,timer}
  chmod 0644 "/etc/systemd/system/${UPDATE_UNIT_NAME}".{service,timer}

  systemctl daemon-reload
  systemctl enable --now "${UPDATE_UNIT_NAME}.timer" >/dev/null
  log_success "Timer enabled. Manual update: sudo ${UPDATER_PATH}"
}

# shellcheck disable=SC2016
IFS= read -r -d '' UPDATER_TEMPLATE <<'EOF' || true
#!/usr/bin/env bash
# nb-zsh-update - updates the shared Oh My Zsh tree, its plugins and (if not from dnf) Starship.
# Installed by zsh.sh. Owned by root. Run manually with: sudo /usr/local/sbin/nb-zsh-update
set -Eeuo pipefail

SHARED="@ZSH_SHARED_DIR@"
STARSHIP_BIN="@STARSHIP_BIN@"
STARSHIP_REPO="@STARSHIP_REPO@"
# shellcheck source=/dev/null
source "@NB_ZSH_LIB_DIR@/helper_github_release.sh"

log() { echo "[nb-zsh-update] $*"; }
failures=0

# Shallow repos: fetch only the newest commit of the current branch, then move the working tree to it.
update_repo() {
  local dir="$1" branch
  [[ -d "${dir}/.git" ]] || return 0
  branch="$(git -C "$dir" symbolic-ref --short HEAD)" || return 1
  git -C "$dir" fetch --quiet --depth=1 origin "$branch" || return 1
  git -C "$dir" reset --hard --quiet FETCH_HEAD || return 1
  log "updated $(basename "$dir") -> $(git -C "$dir" rev-parse --short HEAD)"
}

for dir in "${SHARED}/oh-my-zsh" "${SHARED}"/oh-my-zsh/custom/plugins/*; do
  if ! update_repo "$dir"; then
    log "WARNING: could not update ${dir}"
    failures=$((failures + 1))
  fi
done

# Starship: skip when a dnf package owns it (dnf updates it with the rest of the system).
if rpm -q starship >/dev/null 2>&1; then
  log "starship is managed by dnf; skipping"
elif [[ -x "$STARSHIP_BIN" ]]; then
  update_starship() {
    local tag current triple asset tmp
    tag="$(github_latest_tag "$STARSHIP_REPO")" || return 1
    current="$("$STARSHIP_BIN" --version | awk 'NR==1 {print $2}')"
    if [[ "v${current}" == "$tag" ]]; then log "starship ${current} is current"; return 0; fi
    triple="$(rust_musl_triple)" || return 1
    asset="starship-${triple}.tar.gz"
    tmp="$(mktemp -d)"
    github_download_verified "$STARSHIP_REPO" "$tag" "$asset" "$tmp" || return 1
    tar -xzf "${tmp}/${asset}" -C "$tmp" starship || return 1
    # Install next to the target, then rename: replacing a running binary in place can fail.
    install -o root -g root -m 0755 "${tmp}/starship" "${STARSHIP_BIN}.new" || return 1
    mv -f "${STARSHIP_BIN}.new" "$STARSHIP_BIN"
    rm -rf "$tmp"
    log "starship updated ${current} -> ${tag}"
  }
  if ! update_starship; then
    log "WARNING: starship update failed"
    failures=$((failures + 1))
  fi
fi

# Normalize ownership/permissions after the update (git may have created group/other-writable files).
chown -R root:root "$SHARED"
chmod -R go-w "$SHARED"
if command -v restorecon >/dev/null 2>&1; then restorecon -RF "$SHARED" >/dev/null 2>&1 || true; fi

# Scan what was just fetched when the ClamAV daemon is available (cheap: the database is already loaded).
if command -v clamdscan >/dev/null 2>&1 && systemctl is-active --quiet clamd@scan 2>/dev/null; then
  clamdscan --fdpass --infected --no-summary "$SHARED" || { log "WARNING: ClamAV reported a problem"; failures=$((failures + 1)); }
fi

if (( failures > 0 )); then log "finished with ${failures} problem(s)"; exit 1; fi
log "finished OK"
EOF

#########################################################
# Security
#########################################################
apply_security() {
  log_header "Security"

  # SELinux: files copied from another place can carry the wrong label. restorecon resets
  # each path to the default label defined by policy.
  if has_cmd restorecon; then
    restorecon -RF "$ZSH_SHARED_DIR" "$NB_ZSH_LIB_DIR" "$UPDATER_PATH" /etc/zshenv \
      /etc/systemd/system/${UPDATE_UNIT_NAME}.service /etc/systemd/system/${UPDATE_UNIT_NAME}.timer 2>/dev/null || true
    if [[ -x "$STARSHIP_BIN" ]]; then restorecon -F "$STARSHIP_BIN" 2>/dev/null || true; fi
    log_success "SELinux labels restored"
  fi

  # Final permission sweep of the shared tree.
  chown -R root:root "$ZSH_SHARED_DIR" "$NB_ZSH_LIB_DIR"
  chmod -R go-w "$ZSH_SHARED_DIR" "$NB_ZSH_LIB_DIR"

  # No firewalld rules are needed (nothing here listens on a port). ClamAV: downloads happen in
  # the on-access scanned directory, and the updater scans via clamd when it is running.
}

#########################################################
# Verification
#########################################################
VERIFY_PASS=0
VERIFY_FAIL=0
VERIFY_WARN=0

# check "<description>" <command...>   -> counts and prints pass/fail.
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    log_success "$desc"; VERIFY_PASS=$((VERIFY_PASS + 1))
  else
    log_error "$desc"; VERIFY_FAIL=$((VERIFY_FAIL + 1))
  fi
}

# Anything in the shared tree that group/other can write is a problem. `find ... -print -quit`
# prints the first offender, and `test -z` then requires that nothing was printed.
shared_tree_is_locked() {
  [[ -z "$(find "$ZSH_SHARED_DIR" "$NB_ZSH_LIB_DIR" \( -perm -g+w -o -perm -o+w \) ! -type l -print -quit)" ]] \
    && [[ "$(stat -c %U "$OMZ_DIR")" == "root" ]]
}

login_shell_of() { getent passwd "$1" | cut -d: -f7; }

user_zsh_starts_clean() {
  # Start an interactive zsh as the real user and require that it prints nothing alarming.
  local out
  out="$(runuser -l "$REAL_USER" -c "TERM=xterm-256color zsh -i -c exit" 2>&1 </dev/null)" || return 1
  ! grep -Eiq 'insecure|no such file|command not found|permission denied|parse error|not found:' <<<"$out"
}

# compaudit_is_clean() {
#   local out
#   out="$(runuser -l "$REAL_USER" -c "zsh -i -c 'autoload -Uz compaudit; compaudit'" 2>/dev/null </dev/null)" || true
#   [[ -z "$out" ]]
# }

compaudit_is_clean() {
  local out
  out="$(runuser -l "$REAL_USER" -c "zsh -i -c 'autoload -Uz compaudit; compaudit'" 2>/dev/null </dev/null)" || true
  # Filter out the torsocks startup banner and blank lines so they don't false-trigger failures
  out="$(grep -v "Tor mode activated" <<< "$out" | grep -v "^[[:space:]]*$" || true)"
  [[ -z "$out" ]]
}

root_uses_shared_omz() {
  [[ "$(HOME=/root TERM=xterm-256color zsh -i -c 'print -r -- $ZSH' 2>/dev/null </dev/null | tail -n1)" == "$OMZ_DIR" ]]
}

root_guard_blocks_foreign_home() {
  # Root with the user's HOME must NOT read startup files (RCS option off).
  [[ "$(env -i HOME="$HOME_DIR" PATH=/usr/bin:/bin TERM=dumb zsh -i -c 'print -r -- ${options[rcs]}' 2>/dev/null </dev/null | tail -n1)" == "off" ]]
}

startup_time_ok() {
  local start end ms
  start=$(date +%s%N)
  runuser -l "$REAL_USER" -c "zsh -i -c exit" >/dev/null 2>&1 </dev/null || return 1
  end=$(date +%s%N)
  ms=$(( (end - start) / 1000000 ))
  log_info "Interactive zsh startup: ${ms} ms"
  if (( ms > 1000 )); then
    log_warn "Startup is slower than 1 s (see Troubleshooting: profiling)"
    VERIFY_WARN=$((VERIFY_WARN + 1))
  fi
  return 0
}

verify_setup() {
  log_header "Verification"
  VERIFY_PASS=0; VERIFY_FAIL=0; VERIFY_WARN=0
  local zbin; zbin="$(command -v zsh || true)"

  check "zsh is installed" test -x "${zbin:-/nonexistent}"
  check "login shell of ${REAL_USER} is zsh" test "$(login_shell_of "$REAL_USER")" = "$zbin"
  if [[ "$SET_ROOT_SHELL_TO_ZSH" == "true" ]]; then
    check "login shell of root is zsh" test "$(login_shell_of root)" = "$zbin"
  fi
  check "zsh is listed in /etc/shells" grep -qx "$zbin" /etc/shells

  check "Oh My Zsh is present" test -f "${OMZ_DIR}/oh-my-zsh.sh"
  local entry name
  for entry in "${EXTERNAL_PLUGINS[@]}"; do
    name="${entry%%|*}"
    check "plugin present: ${name}" test -d "${OMZ_DIR}/custom/plugins/${name}"
  done
  check "shared tree is root-owned and not group/other-writable" shared_tree_is_locked

  if has_cmd starship; then
    check "starship runs and renders a prompt" starship_works
  else
    log_warn "Starship is not installed: the agnoster fallback theme is active"
    VERIFY_WARN=$((VERIFY_WARN + 1))
  fi
  check "user starship.toml exists" test -f "$USER_STARSHIP_CONFIG"
  check "root starship config exists" test -f "$ROOT_STARSHIP_CONFIG"

  check "user .zshrc passes zsh syntax check" zsh -n "${HOME_DIR}/.zshrc"
  check "root .zshrc passes zsh syntax check" zsh -n /root/.zshrc
  check "root .zshrc is root-owned" test "$(stat -c %U /root/.zshrc)" = "root"
  check "user shell starts without errors" user_zsh_starts_clean
  check "compaudit reports no insecure directories" compaudit_is_clean
  check "root shell loads the shared Oh My Zsh" root_uses_shared_omz
  check "root ignores startup files from a foreign HOME" root_guard_blocks_foreign_home
  check "interactive startup time measured" startup_time_ok

  if [[ -f "${HOME_DIR}/.zsh_history" ]]; then
    check "history file is private (0600)" test "$(stat -c %a "${HOME_DIR}/.zsh_history")" = "600"
  fi

  check "update timer is enabled" systemctl is-enabled "${UPDATE_UNIT_NAME}.timer"
  check "update script is root-owned and executable" test -x "$UPDATER_PATH" -a "$(stat -c %U "$UPDATER_PATH")" = "root"
  check "update service unit is valid" systemd-analyze verify "/etc/systemd/system/${UPDATE_UNIT_NAME}.service"

  log_info "Passed: ${VERIFY_PASS}  Failed: ${VERIFY_FAIL}  Warnings: ${VERIFY_WARN}"
  if (( VERIFY_FAIL > 0 )); then
    log_error "Verification failed. See Troubleshooting at the bottom of this script."
    return 1
  fi
  log_success "Verification passed"
}

#########################################################
# Main
#########################################################
notify_done() {
  # Optional ntfy notification (the user already runs ntfy for script completion messages).
  if [[ -n "$NTFY_URL" ]] && has_cmd curl; then
    curl -fsS -m 10 -d "zsh setup finished on $(hostname) (starship: ${STARSHIP_OK})" "$NTFY_URL" >/dev/null 2>&1 || true
  fi
}

main() {
  parse_options "$@"
  [[ "$REAL_USER" != "root" ]] || log_die "REAL_USER resolved to root. Run via sudo from your normal account or set REAL_USER."
  id "$REAL_USER" >/dev/null 2>&1 || log_die "User not found: ${REAL_USER}"
  load_helpers
  infer_variables

  log_header "zsh setup"
  log_info "User=${REAL_USER}  Distro=${DISTRO}  Desktop=${DESKTOP}  PC=${PC_TYPE}  RAM=${RAM_MB}MB (${RAM_PROFILE})  CPU=${CPU_CORES}x ${CPU_MODEL}  SSD=${SSD_PRESENT}"

  if [[ "$VERIFY_ONLY" == "true" ]]; then
    verify_setup
    return
  fi

  require_fedora
  prepare_script_dirs
  backup_existing
  reset_existing
  install_packages
  install_shared_omz

  # Starship: any failure here is not fatal, the generated .zshrc falls back to agnoster.
  if install_starship && starship_works; then
    STARSHIP_OK="true"
  else
    STARSHIP_OK="false"
    log_warn "Starship is unavailable. Falling back to the agnoster theme (needs a Nerd/Powerline font)."
  fi

  build_plugin_list
  write_configs
  install_root_guard
  set_login_shells
  install_updater
  apply_security
  verify_setup || true     # report problems but still finish with the summary below
  notify_done

  log_header "Done"
  log_info "Log out and back in (or reboot) so the new login shell applies. Backup: ${ZSH_CURRENT_BACKUP_DIR}"
  log_info "Compare your old ~/.zshrc in the backup with the new one to carry over anything personal."
}

main "$@"
exit $?

#########################################################
# Notes
#########################################################
# DESIGN DECISIONS
# * Starship everywhere, agnoster fallback. Powerlevel10k was dropped: the author stopped
#   maintaining it (see Useful Links). The fallback is decided inside the generated .zshrc with
#   `(( $+commands[starship] ))`, so it also works if Starship disappears later.
# * One shared, root-owned Oh My Zsh tree instead of one copy per account. Root and the user load
#   the same code, and neither can be modified without sudo. Per-user state (caches, history,
#   completion dump) stays in each account's home.
# * Root does NOT source the user's .zshrc. Reason: a file the user can write, executed by root
#   at the next `sudo -i`, lets any process running as that user obtain root (add one line to
#   .zshrc and wait). It also triggers compaudit "insecure directories" warnings. /etc/zshenv
#   additionally switches the RCS option off when root's HOME is not /root (see install_root_guard).
# * `sudo -i` is preferred over `sudo su`. On Fedora, sudoers has always_set_home, so both end up
#   with HOME=/root and read /root/.zshrc. The old complaint "I lose Oh My Zsh as root" came from
#   root having no zsh setup of its own.
# * OMZ is cloned with git instead of piping install.sh to sh. The installer rewrites ~/.zshrc,
#   may change the shell and installs into the home directory, none of which fits a shared setup.
# * zsh-autosuggestions, fzf-tab and zsh-syntax-highlighting are sourced by the .zshrc rather
#   than listed in plugins=(...): that gives the exact order their documentation requires
#   (after compinit; fzf-tab before the widget-wrapping plugins; highlighting last) and avoids a
#   second compinit.
# * OMZ's auto-update is disabled (`zstyle ':omz:update' mode disabled`): the shared tree is not
#   writable by users, and it stops OMZ from contacting GitHub every time a shell starts.
# * Plugin selection is dynamic: docker, aws, uv, gh, kubectl, ... are added only when the tool exists
#   on this machine at generation time. Re-run the script after installing a new tool.
# * Plugins considered and dropped (compared with the previous script):
#     yum (alias for dnf), pep8/autopep8 (obsolete), branch (Starship shows the branch),
#     gitignore (queries an online service on every use), zsh-interactive-cd (overlaps fzf-tab),
#     history/history-substring-search (autosuggestions + fzf Ctrl-R cover it), safe-paste
#     (zsh 5.1+ has bracketed paste built in), timer/emoji/screen (unused), thefuck.
# * Atuin (database-backed history) was not added: fzf's Ctrl-R plus a 50000-line history covers the
#   need without a separate database or a sync server.
# * COMPLETION: the earlier script ran compinit a second time and sourced fzf-tab afterwards. The
#   first compinit is OMZ's own; the second one re-scanned all completion files on every shell
#   start. It was replaced by sourcing fzf-tab right after OMZ.
# * The agnoster SSH marker ("not working?" in the old notes): agnoster only calls prompt_context
#   for non-default users or when SSH_CLIENT is set. Tools that set SSH_CONNECTION but not
#   SSH_CLIENT (some sshd configs) therefore showed nothing. It remains only as a fallback.
# * NextDNS: zsh has no network identity of its own, so there is no app-level NextDNS setting.
# * Torsocks: `. torsocks on` stays the default for every interactive shell, as before, now guarded
#   by a check that torsocks exists. The update script is run via sudo and is not torified; `nbupdate`
#   turns torsocks off first anyway.
# * Android/Termux: `pkg install zsh starship` then copy ~/.config/starship.toml (Syncthing works
#   well for that single file). Termux has no root-owned shared tree, so use a plain Oh My Zsh
#   clone in $HOME there.
# * Sharing the Starship config with bash: the file is shell independent. Bash only needs
#   `eval "$(starship init bash)"` at the end of ~/.bashrc. Nothing else is shared on purpose.
# * Not tested end-to-end on a live Fedora 44 system when this script was written. Run
#   `--verify-setup` after the first run and read any failure line.
#
# KNOWN LIMITS
# * A hand-made ~/.zshrc is replaced (backed up first). Anything personal beyond the old
#   "Added by nbhirud" block (PATH tweaks, conda/nvm init, ...) has to be carried over from the backup.
# * bgnotify on Wayland: the plugin decides whether a command ran in the focused window with X11
#   tools, so on Wayland it may notify even when the terminal is focused. Set ENABLE_BGNOTIFY=false
#   at the top of this script if that is annoying.
# * Running zsh as root with a foreign HOME gets NO startup files by design (RCS off).

#########################################################
# Troubleshooting/Debugging
#########################################################
# Is everything healthy?
#   sudo bash zsh.sh --verify-setup
#
# Which shell am I (and which does the system think I use)?
#   echo $SHELL ; getent passwd "$USER" | cut -d: -f7 ; ps -p $$ -o comm=
#   The login shell changes only at the next login. Test immediately with:  exec zsh -l
#
# Startup is slow
#   time zsh -i -c exit                              # total startup time
#   zsh -ixc exit 2>&1 | less                        # trace everything zsh runs at startup
#   Profile: add `zmodload zsh/zprof` as the FIRST line of ~/.zshrc and run `zprof` as the
#   LAST line, start a new shell, read the table, then remove both lines.
#   Typical causes: slow tool init (nvm, conda, pyenv), too many plugins, a second compinit.
#
# "compinit: insecure directories" / completion warnings
#   compaudit                                        # lists the offending directories
#   compaudit | xargs sudo chmod g-w,o-w             # remove group/other write bits
#   The shared tree is root-owned, so warnings usually point to a directory in your own setup.
#
# Prompt problems
#   starship explain ; starship config ; starship timings
#   STARSHIP_LOG=trace starship prompt               # verbose log of what each module does
#   Slow in a huge repo: raise scan_timeout/command_timeout in ~/.config/starship.toml or disable
#   git_status for that repo type.
#   Broken symbols/boxes: the terminal font must be a Nerd Font (e.g. JetBrainsMono Nerd Font).
#   Fallback active? `ZSH_THEME` is "agnoster" when `command -v starship` is empty.
#
# Root shell
#   sudo -i            # root login shell, reads /root/.zshrc
#   sudo -s            # root shell using your SHELL, HOME is /root on Fedora
#   sudo -l | grep -i always_set_home   # confirm sudoers resets HOME
#   If root's shell is broken: `su -s /bin/bash -` or boot to rescue; restore with `usermod -s /bin/bash root`.
#   Test the guard: sudo env -i HOME=$HOME zsh -i -c 'print ${options[rcs]}'   # must print "off"
#
# Updates
#   sudo /usr/local/sbin/nb-zsh-update               # run now
#   systemctl list-timers nb-zsh-update.timer       # next run
#   journalctl -u nb-zsh-update.service -e           # what happened
#   sudo systemctl start nb-zsh-update.service       # run the service exactly as the timer does
#   Starship installed by dnf is skipped by the updater on purpose (dnf updates it).
#
# SELinux
#   ls -lZ /usr/local/share/zsh-nb /usr/local/sbin/nb-zsh-update
#   sudo restorecon -Rv /usr/local/share/zsh-nb /usr/local/sbin /usr/local/bin/starship
#   sudo ausearch -m avc -ts recent                  # recent denials
#
# Plugins
#   print -l $plugins                                # active OMZ plugins
#   ls /usr/local/share/zsh-nb/oh-my-zsh/plugins     # plugins available in this OMZ version
#   `[oh-my-zsh] plugin 'x' not found`: the name does not exist in this version; remove it from plugins=(...).
#   Autosuggestions not showing: check `echo $ZSH_AUTOSUGGEST_STRATEGY`, and that the terminal supports
#   a grey (dim) foreground color.
#   fzf-tab not active: `type fzf` must succeed and fzf-tab must be sourced BEFORE autosuggestions.
#
# History
#   fc -l -20 ; echo $HISTFILE ; ls -l ~/.zsh_history   # must be mode 600
#   A command with a leading space is intentionally not saved.
#
# Torsocks interfering
#   nbtoroff (or `. torsocks off`) in the current shell; then retry the failing command.
#   Typical victims: ping, UDP tools, tools that open raw sockets, some Rust/Go programs.
#
# Roll back to the previous state
#   Backups: ~/nb/nb_script_data/backups/zsh/zsh_<timestamp>/   (paths mirror the real file system)
#   cp -a <backup>/home/<user>/.zshrc ~/.zshrc
#   (The backup tree is owned by your user so you can read it. When restoring a ROOT-owned file such as
#   /etc/zshenv, copy it with sudo and `sudo chown root:root` it afterwards.)
#   sudo usermod -s /bin/bash <user>                  # switch the login shell back
