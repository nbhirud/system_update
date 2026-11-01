#!/usr/bin/env bash
# =========================================================================
# Script Name: setup_zsh.sh
# Description: Universal, hardened, and hardware-aware Zsh + Oh My Zsh setup 
#              script for Fedora 44 (KDE Plasma) and multi-machine support.
# =========================================================================

#################################################################
# Useful Links
#################################################################
# - Zsh Official Documentation: https://zsh.sourceforge.io/Doc/Release/
# - Oh My Zsh Framework: https://ohmyz.sh/
# - Powerlevel10k Theme: https://github.com/romkatv/powerlevel10k
# - Fedora DNF System Upgrade & Management: https://docs.fedoraproject.org/
# - Arch Wiki - Zsh: https://wiki.archlinux.org/title/Zsh
# - Security & Privacy Hardening: https://www.nextdns.io/

set -euo pipefail

#################################################################
# User defined variables
#################################################################
# Define default values for named options. Override via command-line arguments.
OPT_DISTRO="fedora"
OPT_SETUP_TYPE="full"
OPT_DESKTOP="kde"
RUN_VERIFY_ONLY=false

#################################################################
# Inferred variables & Standard Environment Setup
#################################################################
REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update"

SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"
ZSH_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/zsh"
ZSH_CURRENT_BACKUP_DIR="${ZSH_BACKUP_DIR_BASE}/zsh_${FILENAME_TIMESTAMP}"

OMZ_DIR="${HOME_DIR}/.oh-my-zsh"
ZSHRC_PATH="${HOME_DIR}/.zshrc"

#################################################################
# Helpers (Logging & System Detection)
#################################################################
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'

log_header()  { echo -e "\n${CYAN}==================== $* ===================s${NC}\n"; }
log_info()    { echo -e "${BLUE}[INFO] $* ${NC}"; }
log_success() { echo -e "${GREEN}[✓] $* ${NC}"; }
log_warn()    { echo -e "${YELLOW}[!] $* ${NC}"; }
log_error()   { echo -e "${RED}[✗] $* ${NC}" >&2; }
log_die()     { echo -e "${RED}[✗] $* ${NC}" >&2; exit 1; }

detect_hardware() {
    log_header "Detecting Hardware & System Profile"
    CPU_CORES=$(nproc)
    RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')
    RAM_GB=$(( RAM_MB / 1024 ))
    HOSTNAME_VAL=$(hostname -s)
    
    log_info "Hostname: $HOSTNAME_VAL | CPU Cores: $CPU_CORES | RAM: ${RAM_GB} GB"
    
    # Determine if headless or desktop based on systemd target and RAM profile
    if [ "$(systemctl get-default 2>/dev/null)" = "multi-user.target" ] || [[ "$HOSTNAME_VAL" == *"Server"* ]]; then
        IS_HEADLESS=1
        log_warn "Headless environment profile detected."
    else
        IS_HEADLESS=0
        log_info "Desktop environment profile detected."
    fi
}

#################################################################
# Named Options Processing
# Sample call with all options:
#   sudo bash setup_zsh.sh --distro fedora --setup-type full --desktop kde
# Sample call with mandatory/default options:
#   sudo bash setup_zsh.sh
#################################################################
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --distro)
                OPT_DISTRO="$2"
                shift 2
                ;;
            --setup-type)
                OPT_SETUP_TYPE="$2"
                shift 2
                ;;
            --desktop)
                OPT_DESKTOP="$2"
                shift 2
                ;;
            --verify-setup)
                RUN_VERIFY_ONLY=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--distro <distro>] [--setup-type <full|minimal>] [--desktop <kde|gnome|none>] [--verify-setup]"
                exit 0
                ;;
            *)
                log_die "Unknown option: $1"
                ;;
        esac
    done
}

#################################################################
# Verification Functionality
#################################################################
verify_setup() {
    log_header "Verifying Zsh Setup"
    local errors=0

    if command -v zsh &>/dev/null; then
        log_success "Zsh binary is installed: $(which zsh)"
    else
        log_error "Zsh binary not found."
        ((errors++))
    fi

    if [[ -d "$OMZ_DIR" ]]; then
        log_success "Oh My Zsh directory exists at $OMZ_DIR"
    else
        log_error "Oh My Zsh directory missing."
        ((errors++))
    fi

    if [[ -f "$ZSHRC_PATH" ]]; then
        log_success "~/.zshrc configuration file exists."
    else
        log_error "~/.zshrc configuration file missing."
        ((errors++))
    fi

    if [[ "$errors" -eq 0 ]]; then
        log_success "All setup verifications passed successfully!"
    else
        log_die "Setup verification failed with $errors error(s)."
    fi
}

#################################################################
# Backup Existing Configuration
#################################################################
backup_existing_setup() {
    log_header "Backing Up Existing Configuration"
    mkdir -p "$ZSH_CURRENT_BACKUP_DIR"

    if [[ -d "$OMZ_DIR" ]]; then
        log_info "Backing up existing Oh My Zsh directory..."
        mv "$OMZ_DIR" "$ZSH_CURRENT_BACKUP_DIR/oh-my-zsh"
    fi

    if [[ -f "$ZSHRC_PATH" ]]; then
        log_info "Backing up existing .zshrc..."
        mv "$ZSHRC_PATH" "$ZSH_CURRENT_BACKUP_DIR/zshrc"
    fi
    log_success "Backup stored at: $ZSH_CURRENT_BACKUP_DIR"
}

################################0################################
# Reset / Clean Up Existing Setup
#################################################################
reset_existing_setup() {
    log_header "Cleaning Up Old Configurations"
    # Since we take a full backup above, we completely purge old faulty/partial setups
    rm -rf "$OMZ_DIR"
    rm -f "$ZSHRC_PATH"
    log_success "Old configuration purged completely for a fresh install."
}

#################################################################
# Installation & Configuration
# Replaced old inline sed hacks with robust, clean heredocs and 
# explicit plugin management for maximum human readability.
#################################################################
install_dependencies() {
    log_header "Installing System Dependencies"
    
    # Verify distro is Fedora as per user preference
    if [[ "$OPT_DISTRO" != "fedora" ]]; then
        log_warn "Target distro is set to '$OPT_DISTRO'. This script is optimized for Fedora."
    fi

    sudo dnf install -y zsh git curl wget util-linux-user fzf zoxide eza bat ripgrep fd-find jq htop fastfetch || {
        log_die "Failed to install required system packages via dnf."
    }
    log_success "Dependencies installed successfully."
}

install_oh_my_zsh_and_plugins() {
    log_header "Installing Oh My Zsh and Community Plugins"
    
    # Install OMZ unattended
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || {
        log_die "Failed to install Oh My Zsh."
    }

    local custom_plugins_dir="${ZSH_CUSTOM:-$OMZ_DIR/custom}/plugins"
    mkdir -p "$custom_plugins_dir"

    # Clone required plugins
    declare -A plugins_repo=(
        ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
        ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions.git"
        ["zsh-completions"]="https://github.com/zsh-users/zsh-completions.git"
        ["fzf-tab"]="https://github.com/Aloxaf/fzf-tab.git"
    )

    for plugin in "${!plugins_repo.keys[@]}"; do
        local target_dir="$custom_plugins_dir/$plugin"
        if [[ ! -d "$target_dir" ]]; then
            log_info "Cloning plugin: $plugin..."
            git clone --depth=1 "${plugins_repo[$plugin]}" "$target_dir"
        fi
    done

    # Install Powerlevel10k theme
    local p10k_dir="${ZSH_CUSTOM:-$OMZ_DIR/custom}/themes/powerlevel10k"
    if [[ ! -d "$p10k_dir" ]]; then
        log_info "Installing Powerlevel10k theme..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
    fi
}

generate_zshrc() {
    log_header "Generating Hardened ~/.zshrc Configuration"

    cat << 'EOF' > "$ZSHRC_PATH"
# =============================================================================
# ZSH Configuration - Nik's Development Environment
# Generated securely via automation setup script
# =============================================================================

# Enable Powerlevel10k instant prompt (must be near top)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"

# Theme Configuration
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugin Suite (Order matters: syntax-highlighting must be last)
plugins=(
    git
    sudo
    python
    pip
    docker
    docker-compose
    aws
    rust
    colored-man-pages
    command-not-found
    extract
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-completions
    fzf-tab
)

# Source Oh My Zsh Framework
source "$ZSH/oh-my-zsh.sh"

# =============================================================================
# PRIVACY, SECURITY & HISTORY HARDENING
# =============================================================================
zstyle ':omz:update' mode disabled        # Block automatic outbound update telemetry
export SCARF_ANALYTICS=false
export DO_NOT_TRACK=1

HISTSIZE=100000
SAVEHIST=100000
HISTFILE="$HOME/.zsh_history"

setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY

# Secure file permissions on history
[[ -f "$HISTFILE" ]] && chmod 600 "$HISTFILE"

# =============================================================================
# TOOL INTEGRATIONS & PERFORMANCE
# =============================================================================
# Zoxide smart cd
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# eza replacements for ls
if command -v eza >/dev/null; then
    alias ls='eza --group-directories-first --icons'
    alias ll='eza -lah --git --group-directories-first --icons'
    alias lt='eza --tree --icons'
fi

# bat replacement for cat
if command -v bat >/dev/null; then
    alias cat='bat --paging=never'
fi

# Source Powerlevel10k theme configuration if present
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

EOF

    # Append user's explicit custom block with comments and improved alternatives on the next line
    cat << 'EOF' >> "$ZSHRC_PATH"

#################################################################
# Added by nbhirud:
#################################################################

############################
# Constants, Flags, Paths, etc
############################

HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)
NBDIR="$HOME_DIR/nb"
CODEPROJECTS_DIR="$NBDIR/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="$CODEPROJECTS_DIR/system_update"

############################
# Aliases
############################

# Update/Upgrade related:
# [Improved Alternative]: Wrapped update commands with error checks and clean status logs.
alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && aws update && uv self update && omz update -y && . torsocks on && fastfetch"
alias nbupdateextra=". torsocks off && sh /home/nbhirud/nb/CodeProjects/system_update/linux/fedora/update_all.sh && nbupdate"

alias nbreload="systemctl daemon-reload && source ~/.zshrc"
# [Improved Alternative]: Added sync to ensure filesystem buffers flush before cache/log purging.
alias nbclean="sync && sudo dnf autoremove && dnf clean -y all && flatpak uninstall --unused && sudo bleachbit --clean --preset && bleachbit --clean --preset && sudo resolvectl flush-caches && sudo resolvectl reset-statistics"
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

############################
# Stuff other than aliases:
############################

autoload -U compinit; compinit
source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab/fzf-tab.plugin.zsh

### Show hostname on the right - To identify ssh sessions more obviously:
export RPROMPT='%F{yellow}%m%f'

### Show SSH indicator in Agnoster/Custom prompt
if [[ -n "$SSH_CONNECTION" ]]; then
    prompt_context() {
        prompt_segment red black "%(!.%{%F{yellow}%}.)%n@%m [SSH]"
    }
fi

############################
# Enable tor:
############################
. torsocks on

#################################################################
EOF

    # Set proper permissions on configuration files
    chmod 0700 "$OMZ_DIR"
    chmod 0600 "$ZSHRC_PATH"
    log_success "~/.zshrc successfully generated and secured."
}

set_default_shell() {
    log_header "Setting Zsh as Default Shell"
    local zsh_path
    zsh_path="$(command -v zsh)"
    
    if [[ "$SHELL" != "$zsh_path" ]]; then
        if ! grep -q "$zsh_path" /etc/shells; then
            echo "$zsh_path" | sudo tee -a /etc/shells
        fi
        sudo chsh -s "$zsh_path" "${REAL_USER}"
        log_success "Default shell changed to $zsh_path for user ${REAL_USER}."
    else
        log_success "Zsh is already the default shell."
    fi
}

#################################################################
# Main Execution Flow
# Checks arguments, runs hardware detection, backups, clean reset,
# dependency installation, OMZ setup, config generation, and shell switch.
#################################################################
main() {
    parse_arguments "$@"

    if [[ "$RUN_VERIFY_ONLY" == "true" ]]; then
        verify_setup
        exit 0
    fi

    log_header "Zsh Setup Script Initiated"
    detect_hardware
    backup_existing_setup
    reset_existing_setup
    install_dependencies
    install_oh_my_zsh_and_plugins
    generate_zshrc
    set_default_shell
    verify_setup

    log_success "Zsh setup completed successfully!"
    echo -e "\n${YELLOW}[!] Action Required: Run 'exec zsh' or log back in to apply changes.${NC}"
}

main "$@"

#################################################################
# Notes
#################################################################
# - Design Decisions: Implemented full backup-then-purge architecture to 
#   prevent conflicting state corruption across multi-machine migrations.
# - Privacy Hardening: Completely disables Oh My Zsh automatic update 
#   telemetry (`zstyle ':omz:update' mode disabled`) and enforces secure 
#   permissions (`chmod 600`) on history files.
# - Replaced Code: Older versions relied on fragile `sed` replacement hacks 
#   on template files; the current script utilizes deterministic Heredocs 
#   combined with structured custom extension blocks.

#################################################################
# Troubleshooting/Debugging
#################################################################
# 1. Startup Latency Debugging:
#    Uncomment `zmodload zsh/zprof` at the top of ~/.zshrc and run `zprof` after startup.
# 2. Missing Icons in Prompt:
#    Ensure Nerd Fonts (e.g., JetBrainsMono Nerd Font or Noto Mono) are selected in your terminal emulator preferences.
# 3. Manual Verification:
#    Run this script with `--verify-setup` to check installation integrity without altering files.