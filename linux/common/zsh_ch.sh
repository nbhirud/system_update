#!/usr/bin/env bash
#
# Fedora Zsh + Oh My Zsh setup
# Target: Fedora 44 KDE workstations/laptops and Fedora Server.
#
# Design goals:
#   * Safe to re-run; never delete an existing Oh My Zsh installation.
#   * Back up .zshrc and existing Oh My Zsh before changing anything.
#   * Use Fedora packages for tools and Git clones only for community plugins.
#   * Disable Oh My Zsh's automatic update checks; updates remain manual.
#   * Use Starship on interactive desktop systems and a lightweight OMZ prompt
#     on headless systems. No terminal emulator or tmux configuration is done.
#   * Keep the user's personal aliases and custom settings near the end.
#
# Usage:
#   chmod +x setup_zsh.sh
#   ./setup_zsh.sh
#   ./setup_zsh.sh --setup-type minimal
#   ./setup_zsh.sh --setup-type full --desktop kde
#   ./setup_zsh.sh --no-shell-change
#   ./setup_zsh.sh --verify-setup
#
# Notes:
#   * Run as the normal user, NOT with sudo. The script invokes sudo for dnf.
#   * A new login session is needed for the default-shell change to take effect.
#   * Starship is used instead of Powerlevel10k: it is lightweight, portable,
#     actively maintained, and doesn't require a Nerd Font for basic rendering.
#   * The script does not install Docker, AWS CLI, kubectl, Tailscale, Syncthing,
#     or other large/independent tools. It enables matching OMZ plugins only
#     when the corresponding command is already installed.
#
set -Eeuo pipefail
umask 077

readonly SCRIPT_NAME="${0##*/}"
readonly USER_HOME="${HOME:?HOME is not set}"
readonly OMZ_DIR="$USER_HOME/.oh-my-zsh"
readonly ZSHRC="$USER_HOME/.zshrc"
readonly ZSH_CUSTOM_DIR="$OMZ_DIR/custom"
readonly ZSH_CUSTOM_PLUGINS="$ZSH_CUSTOM_DIR/plugins"
readonly ZSH_CUSTOM_THEMES="$ZSH_CUSTOM_DIR/themes"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

log_info()    { printf '%s[INFO]%s %s\n' "$GREEN" "$NC" "$*"; }
log_warn()    { printf '%s[WARN]%s %s\n' "$YELLOW" "$NC" "$*" >&2; }
log_error()   { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; }
log_success() { printf '%s[OK]%s %s\n' "$CYAN" "$NC" "$*"; }
log_header()  { printf '\n%s=== %s ===%s\n' "$BLUE" "$*" "$NC"; }
die()         { log_error "$*"; exit 1; }

on_error() {
    local exit_code=$?
    log_error "Command failed (exit $exit_code) at line ${BASH_LINENO[0]:-unknown}: ${BASH_COMMAND:-unknown}"
    log_error "Review the output above. Existing configuration backups are kept."
    exit "$exit_code"
}
trap on_error ERR

DISTRO="auto"
SETUP_TYPE="standard"
DESKTOP="auto"
FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
CHANGE_DEFAULT_SHELL=true
VERIFY_ONLY=false

usage() {
    cat <<'USAGE'
Fedora Zsh setup

Options:
  --distro auto|fedora       Detect distro or explicitly specify Fedora (default: auto)
  --setup-type minimal|standard|full
                             Select package/plugin profile (default: standard)
  --desktop auto|kde|gnome|none
                             Desktop integration hint (default: auto)
  --timestamp VALUE          Timestamp string used in backup directory names
  --no-shell-change          Do not change the account's login shell
  --verify-setup             Verify the existing setup without installing/changing anything
  -h, --help                 Show this help

Examples:
  ./setup_zsh.sh
  ./setup_zsh.sh --setup-type full --desktop kde
  ./setup_zsh.sh --setup-type minimal --no-shell-change
  ./setup_zsh.sh --verify-setup
USAGE
}

while (($#)); do
    case "$1" in
        --distro)
            (($# >= 2)) || die "--distro requires a value"
            DISTRO="$2"; shift 2 ;;
        --setup-type)
            (($# >= 2)) || die "--setup-type requires a value"
            SETUP_TYPE="$2"; shift 2 ;;
        --desktop)
            (($# >= 2)) || die "--desktop requires a value"
            DESKTOP="$2"; shift 2 ;;
        --timestamp)
            (($# >= 2)) || die "--timestamp requires a value"
            FILENAME_TIMESTAMP="$2"; shift 2 ;;
        --no-shell-change)
            CHANGE_DEFAULT_SHELL=false; shift ;;
        --verify-setup)
            VERIFY_ONLY=true; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            die "Unknown argument: $1 (use --help)" ;;
    esac
done

case "$SETUP_TYPE" in
    minimal|standard|full) ;;
    *) die "--setup-type must be minimal, standard, or full" ;;
esac
case "$DESKTOP" in
    auto|kde|gnome|none) ;;
    *) die "--desktop must be auto, kde, gnome, or none" ;;
esac
[[ "$FILENAME_TIMESTAMP" =~ ^[A-Za-z0-9._-]+$ ]] ||
    die "--timestamp may contain only letters, digits, dots, underscores, and hyphens"

# Avoid running as root: this script modifies a user's home directory.
(( EUID != 0 )) || die "Do not run this script with sudo or as root. Run it as your normal user."

CURRENT_USER="$(id -un)"
PASSWD_HOME="$(getent passwd "$CURRENT_USER" | cut -d: -f6)"
[[ -n "$PASSWD_HOME" && "$PASSWD_HOME" == "$USER_HOME" ]] ||
    log_warn "HOME ($USER_HOME) differs from the passwd database home ($PASSWD_HOME). Using HOME."

detect_environment() {
    local distro_id
    if [[ "$DISTRO" == "auto" ]]; then
        if [[ -r /etc/os-release ]]; then
            # shellcheck disable=SC1091
            . /etc/os-release
            distro_id="${ID:-unknown}"
            DISTRO="$distro_id"
        else
            DISTRO="unknown"
        fi
    fi
    [[ "$DISTRO" == "fedora" ]] ||
        die "This script currently supports Fedora only (detected/requested: $DISTRO)."

    if [[ "$DESKTOP" == "auto" ]]; then
        case "${XDG_CURRENT_DESKTOP:-}:${DESKTOP_SESSION:-}" in
            *KDE*|*Plasma*|*:plasma) DESKTOP="kde" ;;
            *GNOME*|*:gnome) DESKTOP="gnome" ;;
            *) DESKTOP="none" ;;
        esac
    fi

    CPU_CORES="$(nproc 2>/dev/null || printf 'unknown')"
    RAM_GB="$(
        awk '/^MemTotal:/ { printf "%d", ($2 / 1024 / 1024) + 0.5 }' /proc/meminfo 2>/dev/null ||
        printf '0'
    )"
    DEFAULT_TARGET="$(systemctl get-default 2>/dev/null || true)"
    IS_HEADLESS=false
    if [[ "$DEFAULT_TARGET" == "multi-user.target" ]] &&
       [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        IS_HEADLESS=true
    fi

    HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
    log_info "User: $CURRENT_USER"
    log_info "Host: $HOSTNAME_SHORT"
    log_info "Distro: $DISTRO | Profile: $SETUP_TYPE | Desktop: $DESKTOP"
    log_info "Hardware: ${CPU_CORES} CPU cores, approximately ${RAM_GB} GiB RAM"
    log_info "Headless profile: $IS_HEADLESS"
}

verify_setup() {
    local failed=0
    log_header "Verifying Zsh setup"

    command -v zsh >/dev/null 2>&1 || { log_error "zsh is not installed"; failed=1; }
    [[ -d "$OMZ_DIR" && -f "$OMZ_DIR/oh-my-zsh.sh" ]] ||
        { log_error "Oh My Zsh is missing or incomplete at $OMZ_DIR"; failed=1; }
    [[ -f "$ZSHRC" ]] || { log_error "$ZSHRC is missing"; failed=1; }

    if command -v zsh >/dev/null 2>&1 && [[ -f "$ZSHRC" ]]; then
        if zsh -n "$ZSHRC"; then
            log_success ".zshrc syntax check passed"
        else
            log_error ".zshrc has a syntax error"
            failed=1
        fi
    fi

    if [[ -d "$OMZ_DIR" ]]; then
        for plugin in zsh-autosuggestions zsh-syntax-highlighting zsh-completions fzf-tab; do
            [[ -d "$ZSH_CUSTOM_PLUGINS/$plugin" ]] ||
                { log_error "Community plugin missing: $plugin"; failed=1; }
        done
    fi

    local zsh_path current_login_shell
    zsh_path="$(command -v zsh 2>/dev/null || true)"
    current_login_shell="$(getent passwd "$CURRENT_USER" | cut -d: -f7)"
    if [[ -n "$zsh_path" ]]; then
        log_info "Installed Zsh: $zsh_path"
        log_info "Account login shell: ${current_login_shell:-unknown}"
        [[ "$current_login_shell" == "$zsh_path" ]] ||
            log_warn "Zsh is not the account's configured login shell (this may be intentional)."
    fi

    for cmd in git fzf zoxide eza bat rg fd jq tree htop fastfetch starship; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf '  %-12s %s\n' "$cmd" "$(command -v "$cmd")"
        else
            printf '  %-12s %s\n' "$cmd" "not installed"
        fi
    done

    if ((failed)); then
        log_error "Verification found one or more issues."
        return 1
    fi
    log_success "Core setup verification passed. Optional commands may legitimately be absent."
}

if [[ "$VERIFY_ONLY" == true ]]; then
    verify_setup
    exit $?
fi

detect_environment

# Backups are stored in the user's preferred script-data directory.
BACKUP_ROOT="$USER_HOME/nb/nb_script_data/backups/zsh"
BACKUP_DIR="$BACKUP_ROOT/zsh_$FILENAME_TIMESTAMP"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_ROOT" "$BACKUP_DIR"

backup_if_present() {
    local source_path="$1"
    local destination="$2"
    [[ -e "$source_path" || -L "$source_path" ]] || return 0
    if [[ -e "$destination" || -L "$destination" ]]; then
        log_warn "Backup destination already exists; leaving it untouched: $destination"
        return 0
    fi
    cp -a -- "$source_path" "$destination"
    log_success "Backed up $source_path -> $destination"
}

log_header "Backing up existing configuration"
backup_if_present "$ZSHRC" "$BACKUP_DIR/.zshrc"
backup_if_present "$USER_HOME/.zshrc.local" "$BACKUP_DIR/.zshrc.local"
backup_if_present "$USER_HOME/.zsh_history" "$BACKUP_DIR/.zsh_history"
if [[ -d "$OMZ_DIR" ]]; then
    backup_if_present "$OMZ_DIR" "$BACKUP_DIR/oh-my-zsh"
fi
log_info "Backup directory: $BACKUP_DIR"

# Install packages in groups. Fedora package names are not always the same as
# the executable names (for example, fd is provided by the fd-find package).
log_header "Installing Fedora packages"
BASE_PACKAGES=(zsh git curl util-linux-user)
STANDARD_PACKAGES=(wget fzf zoxide eza bat ripgrep fd-find jq tree htop fastfetch)
PACKAGES=("${BASE_PACKAGES[@]}")
if [[ "$SETUP_TYPE" != "minimal" ]]; then
    PACKAGES+=("${STANDARD_PACKAGES[@]}")
    if [[ "$IS_HEADLESS" != true ]]; then
        PACKAGES+=(starship)
    fi
fi
if [[ "$SETUP_TYPE" == "full" ]]; then
    PACKAGES+=(direnv)
fi

sudo dnf install -y "${PACKAGES[@]}"

# Oh My Zsh is cloned directly from its official repository rather than piping
# a downloaded installer into sh. Existing installations are kept intact.
log_header "Installing Oh My Zsh"
if [[ -d "$OMZ_DIR" ]]; then
    [[ -f "$OMZ_DIR/oh-my-zsh.sh" ]] ||
        die "$OMZ_DIR exists but is not a valid Oh My Zsh installation. Inspect it manually; it was not deleted."
    log_info "Oh My Zsh already exists; leaving its framework files unchanged."
else
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$OMZ_DIR"
    log_success "Oh My Zsh installed."
fi

mkdir -p "$ZSH_CUSTOM_PLUGINS" "$ZSH_CUSTOM_THEMES"
chmod 700 "$OMZ_DIR" "$ZSH_CUSTOM_DIR" "$ZSH_CUSTOM_PLUGINS" "$ZSH_CUSTOM_THEMES"

install_plugin() {
    local name="$1" repo="$2" target="$ZSH_CUSTOM_PLUGINS/$1"
    if [[ -d "$target" ]]; then
        log_info "Plugin already exists; not overwriting or updating: $name"
        return 0
    fi
    log_info "Installing community plugin: $name"
    git clone --depth=1 "$repo" "$target"
}
install_plugin zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git
install_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git
install_plugin zsh-completions https://github.com/zsh-users/zsh-completions.git
install_plugin fzf-tab https://github.com/Aloxaf/fzf-tab.git

# Prompt selection is based on session type rather than a brittle RAM threshold.
# Starship is inexpensive; low-RAM desktop systems do not need a separate prompt
# engine. Headless systems use OMZ's built-in prompt and avoid desktop-specific
# prompt setup.
if [[ "$IS_HEADLESS" == true || "$SETUP_TYPE" == "minimal" ]]; then
    USE_STARSHIP=false
else
    USE_STARSHIP=true
fi

if [[ "$USE_STARSHIP" == true ]] && ! command -v starship >/dev/null 2>&1; then
    sudo dnf install -y starship
fi
STARSHIP_CONFIG_VALUE="$USE_STARSHIP"

# Keep external integrations conditional on the tools already being present.
OMZ_PLUGINS=(git sudo)
if [[ "$SETUP_TYPE" != "minimal" ]]; then
    OMZ_PLUGINS+=(python pip dnf firewalld zsh-completions zsh-autosuggestions fzf-tab)
    command -v aws >/dev/null 2>&1 && OMZ_PLUGINS+=(aws)
    command -v docker >/dev/null 2>&1 && OMZ_PLUGINS+=(docker)
    command -v podman >/dev/null 2>&1 && OMZ_PLUGINS+=(podman)
    command -v kubectl >/dev/null 2>&1 && OMZ_PLUGINS+=(kubectl)
    command -v rustc >/dev/null 2>&1 && OMZ_PLUGINS+=(rust)
    command -v uv >/dev/null 2>&1 && OMZ_PLUGINS+=(uv)
    command -v direnv >/dev/null 2>&1 && OMZ_PLUGINS+=(direnv)
    if [[ "$SETUP_TYPE" == "full" && "$DESKTOP" != "none" ]]; then
        OMZ_PLUGINS+=(bgnotify)
    fi
    # zsh-syntax-highlighting must load last among OMZ plugins.
    OMZ_PLUGINS+=(zsh-syntax-highlighting)
fi

log_header "Writing .zshrc"
TEMP_ZSHRC="$(mktemp "$USER_HOME/.zshrc.tmp.XXXXXX")"
cleanup_temp() {
    if [[ -n "${TEMP_ZSHRC:-}" && -e "$TEMP_ZSHRC" ]]; then
        rm -f -- "$TEMP_ZSHRC"
    fi
    return 0
}
trap cleanup_temp EXIT

cat > "$TEMP_ZSHRC" <<'ZSHRC_BASE'
# =============================================================================
# Zsh configuration managed by setup_zsh.sh
# Review the source script before re-running it; it backs up this file first.
# =============================================================================

# Do not let Oh My Zsh perform automatic update checks. Update it manually with
# `omz update` when you choose to do so.
zstyle ':omz:update' mode disabled

export ZSH="$HOME/.oh-my-zsh"
export ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"
export ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ohmyzsh"
mkdir -p "$ZSH_CACHE_DIR" 2>/dev/null

# Keep user-installed commands available without repeatedly adding duplicate
# PATH entries. Do not put writable, untrusted directories before system paths.
typeset -U path PATH
path=("$HOME/.local/bin" "$HOME/bin" "$HOME/.cargo/bin" $path)
export PATH

# Keep completion definitions from zsh-completions visible before OMZ runs
# compinit. Oh My Zsh itself initializes completion; do not run compinit again.
if [[ -d "$ZSH_CUSTOM/plugins/zsh-completions/src" ]]; then
    fpath=("$ZSH_CUSTOM/plugins/zsh-completions/src" $fpath)
fi

# The installer writes this profile flag so a previously installed Starship
# cannot accidentally override the selected minimal/headless profile.
NB_ZSH_USE_STARSHIP=__USE_STARSHIP__
if [[ -o interactive && "$NB_ZSH_USE_STARSHIP" == true ]] && command -v starship >/dev/null 2>&1; then
    ZSH_THEME=""
else
    ZSH_THEME="robbyrussell"
fi

plugins=(__OMZ_PLUGINS__)

# A blank OMZ theme prevents OMZ from installing its own prompt; Starship is
# initialized immediately afterward. Headless/minimal profiles use robbyrussell.
source "$ZSH/oh-my-zsh.sh"

if [[ -o interactive ]] && [[ "$ZSH_THEME" == "" ]] && command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi

# History: immediate writes, shared between concurrent shells, and restrictive
# file permissions. Commands prefixed by a space are omitted from history.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY
setopt NO_BEEP
[[ -e "$HISTFILE" ]] && chmod 600 "$HISTFILE"

# Completion usability. fzf-tab handles selection; avoid the standard menu
# widget competing with its interface.
zstyle ':completion:*' menu no
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':fzf-tab:*' fzf-command fzf

# fzf integration: prefer fzf's built-in Zsh integration when available, then
# use common Fedora package paths as a fallback.
if command -v fzf >/dev/null 2>&1; then
    if fzf --zsh >/dev/null 2>&1; then
        eval "$(fzf --zsh)"
    else
        [[ -r /usr/share/fzf/shell/completion.zsh ]] && source /usr/share/fzf/shell/completion.zsh
        [[ -r /usr/share/fzf/shell/key-bindings.zsh ]] && source /usr/share/fzf/shell/key-bindings.zsh
        [[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
        [[ -r /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
    fi
fi

# zoxide: initialize only if the executable is installed.
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
fi

# Useful aliases only when their replacement programs are installed.
if command -v eza >/dev/null 2>&1; then
    alias ls='eza --group-directories-first'
    alias ll='eza -lah --git --group-directories-first'
    alias lt='eza --tree'
else
    alias ll='ls -lah'
    alias lt='ls -lahR'
fi
command -v bat >/dev/null 2>&1 && alias cat='bat --paging=never'
command -v rg >/dev/null 2>&1 && alias grep='rg'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -I'
alias df='df -h'
alias du='du -h'
alias ports='ss -tulpn'
command -v fastfetch >/dev/null 2>&1 && alias ff='fastfetch'

# Keep terminal defaults sane. Applications can override these per session.
export EDITOR="${EDITOR:-nvim}"
if command -v codium >/dev/null 2>&1; then
    export VISUAL="${VISUAL:-codium}"
    export VSCODE="${VSCODE:-codium}"
elif command -v code >/dev/null 2>&1; then
    export VISUAL="${VISUAL:-code}"
    export VSCODE="${VSCODE:-code}"
fi

# Disable terminal bell.
unsetopt BEEP

# =============================================================================
# PERSONAL CUSTOMIZATIONS (kept from the supplied zsh.sh)
# =============================================================================

############################
# Constants, Flags, Paths, etc
############################
NBDIR="$HOME/nb"
CODEPROJECTS_DIR="$NBDIR/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="$CODEPROJECTS_DIR/system_update"

############################
# Aliases
############################

# Update/Upgrade related:
# NOTE: These retain your existing workflow. Check each optional command (aws,
# uv, torsocks, Flatpak, BleachBit) before using them on a new machine.
alias nbupdate='. torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && aws update && uv self update && omz update && . torsocks on'
# Proton setup helper (kept as a comment; uncomment if this path/script applies):
# alias nbupdateproton=". torsocks off && cd \"$SYSUPDATE_CODE_BASE_DIR\" && sh \"$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/proton_ag.sh\" --setup-type full --desktop kde && cd \"$HOME\" && . torsocks on"
alias nbupdateextra='sh "$SYSUPDATE_CODE_BASE_DIR/linux/fedora/update_all.sh" && nbupdate'

# Fedora offline release upgrade documentation:
# https://docs.fedoraproject.org/en-US/quick-docs/upgrading-fedora-offline/

alias nbreload='systemctl daemon-reload && source ~/.zshrc'
alias nbclean='sync && sudo dnf autoremove && sudo dnf clean all && flatpak uninstall --unused && sudo bleachbit --clean --preset && bleachbit --clean --preset && sudo resolvectl flush-caches && sudo resolvectl reset-statistics'
alias nbtoron='. torsocks on'
alias nbtoroff='. torsocks off'
alias nbshutdown='nbupdateextra && nbclean && shutdown'
alias nbreboot='nbupdate && nbclean && reboot'

############################
# Alias experiments
############################
alias nbjoplinupdate='wget -O - https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh | bash'
alias nbuvupdate='uv self update'
alias gearlever='flatpak run it.mijorus.gearlever'
# Update one AppImage:
# flatpak run it.mijorus.gearlever --update <name of appimage>

############################
# Other personal settings
############################

# RPROMPT helps identify the remote host in SSH sessions.
if [[ -n "${SSH_CONNECTION:-}" ]]; then
    export RPROMPT='%F{red}[SSH]%f %F{yellow}%m%f'
else
    export RPROMPT='%F{yellow}%m%f'
fi

# Keep the requested fzf-tab plugin enabled via the OMZ plugins array above.
# Do not run compinit a second time; OMZ already initializes it.

# Torsocks note:
# Your original `. torsocks on/off` aliases are preserved above for compatibility
# with your existing shell helper. The standard torsocks command normally wraps
# a specific command (`torsocks curl ...`) rather than providing a universal
# shell-wide on/off switch. If no custom shell helper defines this behavior,
# these aliases will need adapting. The old unconditional `. torsocks on` at
# shell startup is intentionally omitted so a missing helper cannot break
# every new shell.

# Additional TODOs retained from your notes:
# - Run the old-kernel cleanup script from nbclean if desired.
# - Consider font updates, host/blocklist updates, and cron jobs separately.
# - If BleachBit fails under Wayland, follow its current documented guidance
#   rather than automatically granting root access to the graphical session.

# User-specific settings and secrets belong in .zshrc.local. Load this last so
# per-device settings can override defaults above; never commit secrets.
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# End of personal customizations.
ZSHRC_BASE

# Substitute the plugin array safely: the value is generated only from the
# script's fixed plugin names and detected command availability.
PLUGIN_LINE="plugins=(${OMZ_PLUGINS[*]})"
sed -e "s|^plugins=(__OMZ_PLUGINS__)$|$PLUGIN_LINE|" \
    -e "s|^NB_ZSH_USE_STARSHIP=__USE_STARSHIP__$|NB_ZSH_USE_STARSHIP=$STARSHIP_CONFIG_VALUE|" \
    "$TEMP_ZSHRC" > "$TEMP_ZSHRC.rendered"
mv "$TEMP_ZSHRC.rendered" "$TEMP_ZSHRC"

chmod 600 "$TEMP_ZSHRC"
if command -v zsh >/dev/null 2>&1; then
    if ! zsh -n "$TEMP_ZSHRC"; then
        die "Generated .zshrc failed its syntax check. Original file is backed up; current .zshrc was not replaced."
    fi
fi
mv -f -- "$TEMP_ZSHRC" "$ZSHRC"
TEMP_ZSHRC=""
chmod 600 "$ZSHRC"

# Change the login shell only after the new configuration has passed syntax
# validation and has been installed. chsh affects future login sessions.
if [[ "$CHANGE_DEFAULT_SHELL" == true ]]; then
    ZSH_PATH="$(command -v zsh)"
    CURRENT_LOGIN_SHELL="$(getent passwd "$CURRENT_USER" | cut -d: -f7)"
    if [[ "$CURRENT_LOGIN_SHELL" != "$ZSH_PATH" ]]; then
        if ! grep -Fxq "$ZSH_PATH" /etc/shells; then
            log_warn "$ZSH_PATH is not listed in /etc/shells; not changing the login shell."
        else
            chsh -s "$ZSH_PATH"
        fi
    else
        log_info "Zsh is already the configured login shell."
    fi
else
    log_info "Skipping login-shell change (--no-shell-change)."
fi

log_header "Final verification"
verify_setup

cat <<EOF

===============================================================================
Zsh setup finished.

Profile:       $SETUP_TYPE
Desktop:       $DESKTOP
Prompt:        $([[ "$USE_STARSHIP" == true ]] && printf 'Starship' || printf 'Oh My Zsh built-in theme')
Backup:        $BACKUP_DIR
Configuration: $ZSHRC

Next steps:
  1. Start a new terminal, or run: exec zsh
  2. Check the prompt and completion behavior.
  3. Verify: $SCRIPT_NAME --verify-setup
  4. Update Oh My Zsh manually when desired: omz update
  5. Review ~/.zshrc.local for per-device settings and secrets.

Important:
  - This script does not configure Alacritty or tmux.
  - Existing Oh My Zsh and community plugin directories were not overwritten.
  - `nbtoron` / `nbtoroff` depend on your existing torsocks shell helper; see
    the comments in the personal customization section.
===============================================================================
EOF
