#!/usr/bin/env bash
# =============================================================================
# setup_zsh.sh — Universal, hardware-aware, hardened Zsh + Oh My Zsh
# Target: Fedora 44 (KDE / headless) across nbMain / nbAcer / nbXPS / nbLenovo / nbServer
# Author style: nbhirud conventions
# =============================================================================
#
# Useful Links
#   https://ohmyz.sh
#   https://github.com/romkatv/powerlevel10k
#   https://starship.rs
#   https://github.com/zsh-users/zsh-autosuggestions
#   https://github.com/zsh-users/zsh-syntax-highlighting
#   https://github.com/Aloxaf/fzf-tab
#   https://github.com/ajeetdsouza/zoxide
#
# Usage (named options only):
#   ./setup_zsh.sh
#   ./setup_zsh.sh --verify-setup
#   ./setup_zsh.sh --theme starship          # force Starship
#   ./setup_zsh.sh --theme p10k             # force Powerlevel10k
#   ./setup_zsh.sh --vi-mode false          # disable vi-mode
#   ./setup_zsh.sh --minimal                # force low-resource profile
#

# chmod +x setup_zsh.sh
# ./setup_zsh.sh                  # auto-detects hardware + theme
# ./setup_zsh.sh --theme starship # force Starship everywhere
# ./setup_zsh.sh --minimal        # force low-resource profile
# ./setup_zsh.sh --verify-setup   # dry check


# =============================================================================

set -euo pipefail

#########################################################
# User-defined / defaults
#########################################################

THEME_ENGINE="auto"          # auto | starship | p10k
ENABLE_VI_MODE=true
MINIMAL_MODE=false
VERIFY_ONLY=false

#########################################################
# Inferred / standard paths (nb conventions)
#########################################################

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR=$(getent passwd "$REAL_USER" | cut -d: -f6)
NBDIR="$HOME_DIR/nb"
CODEPROJECTS_DIR="$NBDIR/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="$CODEPROJECTS_DIR/system_update"
SCRIPT_DATA="$NBDIR/nb_script_data"
SCRIPT_BACKUPS_DIR="$NBDIR/nb_script_backups"
FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
ZSH_BKP_DIR="$SCRIPT_BACKUPS_DIR/ZSH_BKP_$FILENAME_TIMESTAMP"

#########################################################
# Logging helpers
#########################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
log_warn()    { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
log_error()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
log_success() { printf "${CYAN}[OK]${NC}    %s\n" "$*"; }
log_header()  { printf "\n${BLUE}=== %s ===${NC}\n" "$*"; }

#########################################################
# Option parsing (named only)
#########################################################

while [[ $# -gt 0 ]]; do
  case "$1" in
    --theme)        THEME_ENGINE="$2"; shift 2 ;;
    --vi-mode)      ENABLE_VI_MODE="$2"; shift 2 ;;
    --minimal)      MINIMAL_MODE=true; shift ;;
    --verify-setup) VERIFY_ONLY=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--theme auto|starship|p10k] [--vi-mode true|false] [--minimal] [--verify-setup]"
      exit 0
      ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

#########################################################
# Hardware / environment detection
#########################################################

detect_hardware() {
  log_header "Hardware Detection"

  HOSTNAME_VAL=$(hostname -s)
  CPU_CORES=$(nproc)
  RAM_GIB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  GPU_INFO=$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | head -3 || echo "unknown")

  IS_HEADLESS=0
  if [[ "$(systemctl get-default 2>/dev/null)" == "multi-user.target" ]] || \
     [[ "$HOSTNAME_VAL" == *"Server"* ]]; then
    IS_HEADLESS=1
  fi

  log_info "Hostname : $HOSTNAME_VAL"
  log_info "CPU cores: $CPU_CORES"
  log_info "RAM      : ${RAM_GIB} GiB"
  log_info "GPU      : $GPU_INFO"
  log_info "Headless : $IS_HEADLESS"

  # Theme decision
  if [[ "$THEME_ENGINE" == "auto" ]]; then
    if [[ $IS_HEADLESS -eq 1 || $RAM_GIB -le 6 || "$MINIMAL_MODE" == "true" ]]; then
      THEME_ENGINE="starship"
    else
      THEME_ENGINE="p10k"
    fi
  fi
  log_info "Theme engine selected: $THEME_ENGINE"

  # Resource flags
  if [[ $RAM_GIB -le 6 || $CPU_CORES -lt 4 || "$MINIMAL_MODE" == "true" ]]; then
    MEMORY_EFFICIENT=true
    MINIMAL_PLUGIN_MODE=true
  else
    MEMORY_EFFICIENT=false
    MINIMAL_PLUGIN_MODE=false
  fi

  export HOSTNAME_VAL CPU_CORES RAM_GIB GPU_INFO IS_HEADLESS
  export THEME_ENGINE MEMORY_EFFICIENT MINIMAL_PLUGIN_MODE
}

#########################################################
# Backup existing configuration
#########################################################

backup_existing() {
  log_header "Backup"

  mkdir -p "$ZSH_BKP_DIR"
  chown -R "$REAL_USER:$REAL_USER" "$SCRIPT_BACKUPS_DIR" 2>/dev/null || true

  if [[ -d "$HOME_DIR/.oh-my-zsh" ]]; then
    log_info "Backing up existing Oh My Zsh → $ZSH_BKP_DIR/OMZ"
    mv "$HOME_DIR/.oh-my-zsh" "$ZSH_BKP_DIR/OMZ"
  fi

  if [[ -f "$HOME_DIR/.zshrc" ]]; then
    log_info "Backing up .zshrc → $ZSH_BKP_DIR/.zshrc"
    cp "$HOME_DIR/.zshrc" "$ZSH_BKP_DIR/.zshrc"
  fi

  if [[ -f "$HOME_DIR/.p10k.zsh" ]]; then
    cp "$HOME_DIR/.p10k.zsh" "$ZSH_BKP_DIR/.p10k.zsh" || true
  fi

  log_success "Backup complete: $ZSH_BKP_DIR"
}

#########################################################
# Package installation
#########################################################

install_packages() {
  log_header "Packages (dnf)"

  local pkgs=(
    zsh git curl wget util-linux-user
    fzf bat eza fd-find ripgrep zoxide
    jq tree htop fastfetch
  )

  # Optional but high-value
  command -v lazygit >/dev/null 2>&1 || pkgs+=(lazygit)

  log_info "Installing: ${pkgs[*]}"
  sudo dnf install -y "${pkgs[@]}" || log_warn "Some packages failed; continuing"

  # Starship (always install as fallback / low-resource option)
  if ! command -v starship >/dev/null 2>&1; then
    log_info "Installing Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y --bin-dir "$HOME_DIR/.local/bin"
  fi

  log_success "Packages done"
}

#########################################################
# Oh My Zsh + plugins
#########################################################

install_omz_and_plugins() {
  log_header "Oh My Zsh + plugins"

  local OMZ_DIR="$HOME_DIR/.oh-my-zsh"
  local CUSTOM="$OMZ_DIR/custom"

  if [[ ! -d "$OMZ_DIR" ]]; then
    log_info "Installing Oh My Zsh (unattended)..."
    sudo -u "$REAL_USER" env RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    log_info "Oh My Zsh already present"
  fi

  mkdir -p "$CUSTOM/plugins" "$CUSTOM/themes"

  clone_plugin() {
    local name="$1" repo="$2"
    local dest="$CUSTOM/plugins/$name"
    if [[ -d "$dest" ]]; then
      log_info "Plugin $name exists — updating"
      sudo -u "$REAL_USER" git -C "$dest" pull --quiet || true
    else
      log_info "Cloning $name"
      sudo -u "$REAL_USER" git clone --depth=1 "$repo" "$dest"
    fi
  }

  # Always
  clone_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git
  clone_plugin zsh-autosuggestions    https://github.com/zsh-users/zsh-autosuggestions.git
  clone_plugin zsh-completions        https://github.com/zsh-users/zsh-completions.git
  clone_plugin fzf-tab                https://github.com/Aloxaf/fzf-tab.git

  # Optional / higher resource
  if [[ "$MINIMAL_PLUGIN_MODE" == "false" ]]; then
    clone_plugin you-should-use https://github.com/MichaelAquilina/zsh-you-should-use.git
  fi

  # Powerlevel10k only when selected
  if [[ "$THEME_ENGINE" == "p10k" ]]; then
    local P10K="$CUSTOM/themes/powerlevel10k"
    if [[ ! -d "$P10K" ]]; then
      sudo -u "$REAL_USER" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K"
    fi
  fi

  chown -R "$REAL_USER:$REAL_USER" "$OMZ_DIR"
  log_success "Plugins ready"
}

#########################################################
# Write ~/.zshrc
#########################################################

write_zshrc() {
  log_header "Writing ~/.zshrc"

  local ZSHRC="$HOME_DIR/.zshrc"

  # Conditional plugin list (only include docker/aws/kubectl if binary exists)
  local extra_plugins=""
  command -v docker   >/dev/null 2>&1 && extra_plugins+=" docker docker-compose"
  command -v podman   >/dev/null 2>&1 && extra_plugins+=" podman"
  command -v kubectl  >/dev/null 2>&1 && extra_plugins+=" kubectl"
  command -v aws      >/dev/null 2>&1 && extra_plugins+=" aws"

  sudo -u "$REAL_USER" tee "$ZSHRC" > /dev/null << ZSHRC_EOF
# =============================================================================
# ~/.zshrc — generated by setup_zsh.sh
# Machine: $HOSTNAME_VAL | RAM: ${RAM_GIB} GiB | Theme: $THEME_ENGINE
# =============================================================================

# Instant prompt (P10k only)
$( [[ "$THEME_ENGINE" == "p10k" ]] && cat << 'P10K_TOP'
if [[ -r "\${XDG_CACHE_HOME:-\$HOME/.cache}/p10k-instant-prompt-\${(%):-%n}.zsh" ]]; then
  source "\${XDG_CACHE_HOME:-\$HOME/.cache}/p10k-instant-prompt-\${(%):-%n}.zsh"
fi
P10K_TOP
)

export ZSH="\$HOME/.oh-my-zsh"

# Theme
$( if [[ "$THEME_ENGINE" == "p10k" ]]; then
     echo 'ZSH_THEME="powerlevel10k/powerlevel10k"'
   else
     echo 'ZSH_THEME=""   # Starship owns the prompt'
   fi
)

# Plugins (syntax-highlighting MUST be last)
plugins=(
  git
  sudo
  colored-man-pages
  command-not-found
  extract
  history
  history-substring-search
  fzf
  zoxide
  zsh-completions
  zsh-autosuggestions
  fzf-tab
$extra_plugins
  zsh-syntax-highlighting
)

source "\$ZSH/oh-my-zsh.sh"

# -----------------------------------------------------------------------------
# History (privacy + usability)
# -----------------------------------------------------------------------------
HISTSIZE=50000
SAVEHIST=50000
HISTFILE="\$HOME/.zsh_history"
setopt HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS
setopt HIST_VERIFY SHARE_HISTORY INC_APPEND_HISTORY
[[ -f "\$HISTFILE" ]] && chmod 600 "\$HISTFILE"

# -----------------------------------------------------------------------------
# Privacy / telemetry
# -----------------------------------------------------------------------------
zstyle ':omz:update' mode disabled
export DO_NOT_TRACK=1
export SCARF_ANALYTICS=false
umask 077

# -----------------------------------------------------------------------------
# NextDNS / Tailscale stubs (set real values in ~/.zshrc.local)
# -----------------------------------------------------------------------------
# export NEXTDNS_ID=""          # per-app / per-device unique ID preferred
# export TAILSCALE_ROUTER=""

# -----------------------------------------------------------------------------
# Environment
# -----------------------------------------------------------------------------
export EDITOR="nvim"
export VISUAL="nvim"
export PATH="\$HOME/.local/bin:\$PATH"
export PYTHONDONTWRITEBYTECODE=1
export AWS_PAGER=""

# fzf + fd
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="\$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

# -----------------------------------------------------------------------------
# Aliases (modern tools)
# -----------------------------------------------------------------------------
if command -v eza >/dev/null; then
  alias ls='eza --group-directories-first --icons'
  alias ll='eza -lah --git --group-directories-first --icons'
  alias lt='eza --tree --level=2 --icons'
fi
command -v bat >/dev/null && alias cat='bat --paging=never'
alias grep='rg'
alias df='df -h'
alias du='du -h'
alias ports='ss -tulpn'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Safer defaults
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -I'

# Git
alias gs='git status -sb'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias glog='git log --oneline --graph --decorate --all'

# Docker / Podman (only if present)
command -v docker >/dev/null && {
  alias d='docker'
  alias dc='docker compose'
  alias dps='docker ps --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}"'
}
command -v podman >/dev/null && alias p='podman'

# -----------------------------------------------------------------------------
# Completions + zoxide
# -----------------------------------------------------------------------------
autoload -Uz compinit
if [[ -n \${ZDOTDIR:-\$HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

eval "\$(zoxide init zsh)"

# -----------------------------------------------------------------------------
# Prompt
# -----------------------------------------------------------------------------
$( if [[ "$THEME_ENGINE" == "starship" ]]; then
     echo 'eval "$(starship init zsh)"'
   else
     echo '[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh'
   fi
)

# -----------------------------------------------------------------------------
# Vi-mode (optional)
# -----------------------------------------------------------------------------
$( if [[ "$ENABLE_VI_MODE" == "true" ]]; then
cat << 'VIMODE'
bindkey -v
export KEYTIMEOUT=1
# Restore useful emacs bindings
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line
bindkey '^R' fzf-history-widget
bindkey '^W' backward-kill-word
bindkey '^?' backward-delete-char
# Cursor shape
function zle-keymap-select {
  case \$KEYMAP in
    vicmd)      print -n '\e[2 q';;  # block
    viins|main) print -n '\e[6 q';;  # beam
  esac
}
zle -N zle-keymap-select
function zle-line-init { print -n '\e[6 q'; }
zle -N zle-line-init
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey -M vicmd 'v' edit-command-line
VIMODE
else
  echo 'bindkey -e'
fi
)

# -----------------------------------------------------------------------------
# Machine-specific tweaks
# -----------------------------------------------------------------------------
case "\$(hostname -s)" in
  nbMain)   export MAKEFLAGS="-j\$(nproc)" ;;
  nbAcer)   export MAKEFLAGS="-j6" ;;
  nbXPS)    export MAKEFLAGS="-j8" ;;
  nbLenovo) export MAKEFLAGS="-j3"; export FZF_DEFAULT_OPTS="\$FZF_DEFAULT_OPTS --height 30%" ;;
  nbServer) export MAKEFLAGS="-j2"
            alias logs='sudo journalctl -f'
            alias services='systemctl list-units --type=service --state=running'
            ;;
esac

# -----------------------------------------------------------------------------
# Local overrides (secrets, NextDNS IDs, per-machine paths)
# -----------------------------------------------------------------------------
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# =============================================================================
# Custom block kept from your original setup (improved suggestions commented)
# =============================================================================

#################################################################
# Added by nbhirud:
#################################################################

############################
# Constants, Flags, Paths, etc
############################

HOME_DIR=\$(getent passwd \$USER | cut -d: -f6)
NBDIR="\$HOME_DIR/nb"
CODEPROJECTS_DIR="\$NBDIR/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="\$CODEPROJECTS_DIR/system_update"

############################
# Aliases
############################

# Application shortcuts:
# alias codium="flatpak run com.vscodium.codium "

# Update / Upgrade related:
# Better version (safer, no forced torsocks toggle if not needed):
# alias nbupdate='sudo dnf upgrade --refresh -y && flatpak update -y && command -v aws >/dev/null && aws --version >/dev/null; command -v uv >/dev/null && uv self update; omz update 2>/dev/null; fastfetch'
alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && aws update && uv self update && omz update -y && . torsocks on && fastfetch"

# alias nbupdateproton=". torsocks off && cd /home/nbhirud/nb/CodeProjects/system_update/ && sh /home/nbhirud/nb/CodeProjects/system_update/linux/security/proton_ag.sh --setup-type full --desktop kde && cd && . torsocks on"
alias nbupdateextra=". torsocks off && sh /home/nbhirud/nb/CodeProjects/system_update/linux/fedora/update_all.sh && nbupdate"

# https://docs.fedoraproject.org/en-US/quick-docs/upgrading-fedora-offline/
# alias nbdistu="sudo sudo dnf upgrade --refresh -y && sudo sudo dnf system-upgrade download --releasever=43 -y"
alias nbreload="systemctl daemon-reload && source ~/.zshrc"

# Better clean (bleachbit + resolvectl still fine; consider adding old-kernel cleanup later)
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

autoload -U compinit; compinit
source \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab/fzf-tab.plugin.zsh

### Show hostname on the right - To identify ssh sessions more obviously:
export RPROMPT='%F{yellow}%m%f'

### Show SSH indicator in Agnoster prompt (not working?)
if [[ -n "\$SSH_CONNECTION" ]]; then
    prompt_context() {
        prompt_segment red black "%(!.%{%F{yellow}%}.)%n@%m [SSH]"
    }
fi

############################
# Enable tor:
############################

. torsocks on

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

ZSHRC_EOF

  chown "$REAL_USER:$REAL_USER" "$ZSHRC"
  chmod 600 "$ZSHRC"
  log_success "~/.zshrc written"
}

#########################################################
# Set default shell
#########################################################

set_default_shell() {
  log_header "Default shell"

  local ZSH_PATH
  ZSH_PATH=$(command -v zsh)

  if [[ "$SHELL" == "$ZSH_PATH" ]]; then
    log_success "zsh already default"
    return
  fi

  if ! grep -q "$ZSH_PATH" /etc/shells; then
    echo "$ZSH_PATH" | sudo tee -a /etc/shells
  fi

  sudo chsh -s "$ZSH_PATH" "$REAL_USER"
  log_success "Default shell → $ZSH_PATH (takes effect on next login)"
}

#########################################################
# Verify
#########################################################

verify_setup() {
  log_header "Verification"
  command -v zsh     >/dev/null && log_success "zsh present"     || log_error "zsh missing"
  [[ -d "$HOME_DIR/.oh-my-zsh" ]] && log_success "Oh My Zsh present" || log_error "Oh My Zsh missing"
  command -v starship >/dev/null && log_success "starship present" || log_warn  "starship missing"
  [[ -f "$HOME_DIR/.zshrc" ]] && log_success ".zshrc present" || log_error ".zshrc missing"
  echo
  log_info "Run: exec zsh   (or log out/in)"
  [[ "$THEME_ENGINE" == "p10k" ]] && log_info "Then run: p10k configure"
}

#########################################################
# Main
#########################################################

main() {
  log_header "Zsh setup starting"
  log_info "User: $REAL_USER | Host: $(hostname) | Date: $(date)"

  detect_hardware

  if [[ "$VERIFY_ONLY" == "true" ]]; then
    verify_setup
    exit 0
  fi

  backup_existing
  install_packages
  install_omz_and_plugins
  write_zshrc
  set_default_shell
  verify_setup

  log_header "Done"
  cat << EOF

Next steps:
  1. exec zsh          # or log out / in
  2. [[ p10k ]] → p10k configure
  3. Put secrets / NextDNS IDs in ~/.zshrc.local
  4. Test:  sysinfo  (add the function later if you want) or just open a new terminal

Notes / Troubleshooting
  - Slow startup?  Temporarily comment plugins or switch to --theme starship
  - Icons missing?  Confirm Nerd Font (JetBrainsMono / Noto / Ubuntu Mono) is selected in Alacritty / Konsole
  - History privacy: commands starting with a space are never recorded
  - OMZ updates:  alias omz-upgrade is available once you source the new .zshrc
  - Syncthing: sync ~/.zshrc + ~/.zshrc.local (exclude .zsh_history)

EOF
}

main "$@"