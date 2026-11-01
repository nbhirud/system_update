#!/usr/bin/env bash
# =============================================================================
# ZSH + OH-MY-ZSH SETUP SCRIPT
# Author: Generated for nbhirud
# Machines: nbMain, nbAcer, nbXPS, nbLenovo, nbServer (Fedora 44)
# =============================================================================
# What this script does:
#   1. Detects hostname + hardware (CPU cores, RAM, GPU)
#   2. Installs zsh, oh-my-zsh, plugins
#   3. Installs Starship (low-end) or Powerlevel10k (high-end) based on RAM
#   4. Writes a fully configured ~/.zshrc
#   5. Sets zsh as default shell
#   6. Optionally enables vi-mode
# =============================================================================

set -euo pipefail









# Claude responded: One last thing on vi-mode — since you use neovim heavily, vi-mode in zsh feels natural (navigate command history, edit long commands in normal mode).One last thing on vi-mode — since you use neovim heavily, vi-mode in zsh feels natural (navigate command history, edit long commands in normal mode). The downside is a small learning curve and Ctrl+C / Ctrl+A muscle memory breaks. I'd recommend yes, but I'll make it easy to toggle off with one variable.
# Now writing the script.Ran 2 commands, viewed a file, created a fileRan 2 commands, viewed a file, created a fileHere's what the script does and the decisions made:
# Theme logic (RAM-based):
# MachineRAMThemenbServer (AMD A4)14 GiBStarship ← wait, see notenbLenovo (i3)5.6 GiBStarshipnbAcer (i5-8400)7.6 GiBPowerlevel10knbXPS (i7)15 GiBPowerlevel10knbMain (i5-2400)31 GiBPowerlevel10k

# Note on nbServer: It has 14 GiB RAM so the script will select P10k — but since it's headless, you'll want to set THEME_ENGINE="starship" override in ~/.zshrc.local on that machine. I'll add a machine-specific override note if you want.

# Plugins installed on all machines:

# zsh-syntax-highlighting, zsh-autosuggestions, zsh-completions, zsh-fzf-history-search, you-should-use
# OMZ built-ins: git, docker, docker-compose, python, rust, aws, fzf, zoxide, sudo, colored-man-pages, and more

# Vi-mode: Enabled with ENABLE_VI_MODE=true at the top — flip to false to switch back. Cursor changes shape (beam in insert, block in normal) and emacs shortcuts (Ctrl+A/E/R/W) are restored so you don't lose muscle memory.

# Run it:
# sudo bash setup_zsh.sh
# exec zsh        # reload
# p10k configure  # only on high-end machines














# =============================================================================
# USER CONFIGURATION — Edit these before running
# =============================================================================

# Enable vi-mode keybindings? (true/false)
# Recommended if you use neovim. ESC enters normal mode in the terminal.
# In normal mode: h/l move cursor, b/w jump words, / searches history
# Ctrl+[ also acts as ESC. Set to false to keep emacs-style (Ctrl+A, Ctrl+E)
ENABLE_VI_MODE=true

# Your username (defaults to current user)
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(eval echo "~$TARGET_USER")

# =============================================================================
# COLORS & HELPERS
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*" >&2; exit 1; }
section() { echo -e "\n${CYAN}=== $* ===${NC}"; }

# =============================================================================
# HARDWARE DETECTION
# =============================================================================

section "Detecting hardware"

HOSTNAME_VAL=$(hostname -s)
CPU_CORES=$(nproc)
# RAM in GiB (integer)
RAM_GIB=$(awk '/MemTotal/ { printf "%d", $2/1024/1024 }' /proc/meminfo)
# GPU detection
GPU_INFO=$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | head -3 || echo "unknown")

info "Hostname : $HOSTNAME_VAL"
info "CPU cores: $CPU_CORES"
info "RAM      : ${RAM_GIB} GiB"
info "GPU      : $GPU_INFO"

# =============================================================================
# THEME SELECTION BASED ON HARDWARE
# Low-end: <= 6 GiB RAM  → Starship  (Rust binary, ~5ms prompt, zero zsh overhead)
# High-end: > 6 GiB RAM  → Powerlevel10k (richest info, instant prompt feature)
#
# Machine breakdown:
#   nbServer  (2 GiB AMD A4)  → Starship
#   nbLenovo  (5 GiB i3)      → Starship
#   nbAcer    (7 GiB i5-8400) → Powerlevel10k  (borderline, more RAM wins)
#   nbMain    (31 GiB i5)     → Powerlevel10k
#   nbXPS     (15 GiB i7)     → Powerlevel10k
# =============================================================================

if [[ $RAM_GIB -le 6 ]]; then
    THEME_ENGINE="starship"
    info "Theme: Starship (low-RAM machine: ${RAM_GIB} GiB)"
else
    THEME_ENGINE="p10k"
    info "Theme: Powerlevel10k (sufficient RAM: ${RAM_GIB} GiB)"
fi

# =============================================================================
# ROOT CHECK
# =============================================================================

if [[ $EUID -ne 0 ]]; then
    warn "Not running as root. Package installs may fail."
    warn "Re-run with: sudo bash $0"
    warn "Continuing anyway (assuming packages already installed or sudo available)..."
    SUDO_CMD="sudo"
else
    SUDO_CMD=""
fi

# =============================================================================
# STEP 1: INSTALL PACKAGES
# =============================================================================

section "Installing packages"

# Core packages needed regardless of machine
PACKAGES=(
    zsh
    git
    curl
    wget
    util-linux-user   # needed for chsh on Fedora
    fzf               # fuzzy finder — integrates with zsh history and file search
    bat               # better cat (syntax highlighting) — aliased as 'cat'
    eza               # modern ls replacement (successor to exa)
    fd-find           # faster 'find', used by fzf
    ripgrep           # faster 'grep', aliased as 'rg'
    zoxide            # smarter 'cd' that learns your directories
    starship          # prompt for low-end (also installed on high-end as fallback)
)

info "Installing core packages via dnf..."
$SUDO_CMD dnf install -y "${PACKAGES[@]}" 2>/dev/null || warn "Some packages may have failed; continuing..."

success "Packages done"

# =============================================================================
# STEP 2: INSTALL OH-MY-ZSH
# =============================================================================

section "Installing Oh-My-Zsh"

OMZ_DIR="$TARGET_HOME/.oh-my-zsh"

if [[ -d "$OMZ_DIR" ]]; then
    warn "oh-my-zsh already exists at $OMZ_DIR — skipping install"
else
    info "Downloading and installing oh-my-zsh..."
    # RUNZSH=no prevents it from launching zsh immediately
    # CHSH=no we handle chsh ourselves below
    # KEEP_ZSHRC=yes prevents overwriting if .zshrc exists
    sudo -u "$TARGET_USER" sh -c \
        'RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
         sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
    success "oh-my-zsh installed"
fi

OMZ_CUSTOM="$OMZ_DIR/custom"

# =============================================================================
# STEP 3: INSTALL PLUGINS
# =============================================================================

section "Installing zsh plugins"

# Helper: clone a plugin if not already present
clone_plugin() {
    local name="$1"
    local repo="$2"
    local dest="$OMZ_CUSTOM/plugins/$name"
    if [[ -d "$dest" ]]; then
        info "Plugin '$name' already exists — skipping"
    else
        info "Cloning $name..."
        sudo -u "$TARGET_USER" git clone --depth=1 "$repo" "$dest"
        success "Plugin '$name' installed"
    fi
}

# --- Essential plugins (all machines) ---

# Syntax highlighting: colors commands as you type (red=invalid, green=valid)
clone_plugin "zsh-syntax-highlighting" \
    "https://github.com/zsh-users/zsh-syntax-highlighting.git"

# Autosuggestions: ghost-text completions from history, press → to accept
clone_plugin "zsh-autosuggestions" \
    "https://github.com/zsh-users/zsh-autosuggestions.git"

# Completions: additional completion definitions not in zsh base
clone_plugin "zsh-completions" \
    "https://github.com/zsh-users/zsh-completions.git"

# History search: Ctrl+R fuzzy search with fzf, much better than default
clone_plugin "zsh-fzf-history-search" \
    "https://github.com/joshskidmore/zsh-fzf-history-search.git"

# you-should-use: reminds you when you have an alias for a command you just ran
clone_plugin "you-should-use" \
    "https://github.com/MichaelAquilina/zsh-you-should-use.git"

# --- Powerlevel10k theme (high-end machines only) ---
if [[ "$THEME_ENGINE" == "p10k" ]]; then
    P10K_DIR="$OMZ_CUSTOM/themes/powerlevel10k"
    if [[ -d "$P10K_DIR" ]]; then
        info "Powerlevel10k already exists — skipping"
    else
        info "Cloning Powerlevel10k..."
        sudo -u "$TARGET_USER" git clone --depth=1 \
            "https://github.com/romkatv/powerlevel10k.git" "$P10K_DIR"
        success "Powerlevel10k installed"
    fi
fi

# =============================================================================
# STEP 4: INSTALL STARSHIP (for low-end; also as fallback on others)
# =============================================================================

section "Installing Starship prompt"

if command -v starship &>/dev/null; then
    success "Starship already installed: $(starship --version)"
else
    # dnf install above should have handled it; this is a fallback
    info "Installing Starship via official installer..."
    sudo -u "$TARGET_USER" sh -c \
        'curl -sS https://starship.rs/install.sh | sh -s -- -y'
    success "Starship installed"
fi

# Write Starship config (used on all machines; only active on low-end)
STARSHIP_CONFIG_DIR="$TARGET_HOME/.config"
sudo -u "$TARGET_USER" mkdir -p "$STARSHIP_CONFIG_DIR"

STARSHIP_CONFIG="$STARSHIP_CONFIG_DIR/starship.toml"
if [[ ! -f "$STARSHIP_CONFIG" ]]; then
    info "Writing Starship config..."
    sudo -u "$TARGET_USER" tee "$STARSHIP_CONFIG" > /dev/null << 'STARSHIP_TOML'
# Starship configuration
# Optimized for low-RAM machines: minimal overhead, useful info

# Timeout for commands (ms) — lower = faster prompt on slow machines
command_timeout = 500

# Overall format: what shows on the left side of the prompt
format = """
$username$hostname$directory$git_branch$git_status$python$rust$docker_context$jobs$status
$character"""

[username]
show_always = false   # Only shows when SSH or root
style_user = "bold green"
style_root = "bold red"
format = "[$user]($style)@"

[hostname]
ssh_only = true       # Only show hostname over SSH
style = "bold yellow"
format = "[$hostname]($style) "

[directory]
truncation_length = 3
truncate_to_repo = true
style = "bold blue"
format = "[$path]($style)[$read_only]($read_only_style) "

[git_branch]
style = "bold purple"
format = "[$symbol$branch]($style) "

[git_status]
format = '([\[$all_status$ahead_behind\]]($style) )'
style = "bold red"

[python]
format = '[${symbol}${pyenv_prefix}(${version} )(\($virtualenv\) )]($style)'
symbol = "🐍 "
style = "bold yellow"

[rust]
format = "[$symbol($version )]($style)"
symbol = "🦀 "
style = "bold red"

[docker_context]
format = "[$symbol$context]($style) "
symbol = "🐳 "
style = "bold blue"
only_with_files = true

[jobs]
symbol = "⚙ "
style = "bold blue"

[status]
disabled = false
style = "bold red"
format = "[$symbol$status]($style) "

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
vimcmd_symbol = "[❮](bold green)"   # Shows in vi-mode normal mode
STARSHIP_TOML
    success "Starship config written to $STARSHIP_CONFIG"
fi

# =============================================================================
# STEP 5: ZOXIDE INIT (smart cd)
# =============================================================================
# zoxide replaces cd — learns which dirs you visit most and jumps to them
# Usage: z foo   → jumps to most frecent dir matching 'foo'
#        zi foo  → interactive selection with fzf

# =============================================================================
# STEP 6: WRITE ~/.zshrc
# =============================================================================

section "Writing ~/.zshrc"

ZSHRC="$TARGET_HOME/.zshrc"

# Backup existing .zshrc if it exists
if [[ -f "$ZSHRC" ]]; then
    BACKUP="$ZSHRC.bak.$(date +%Y%m%d_%H%M%S)"
    sudo -u "$TARGET_USER" cp "$ZSHRC" "$BACKUP"
    warn "Existing .zshrc backed up to $BACKUP"
fi

# Write new .zshrc
sudo -u "$TARGET_USER" tee "$ZSHRC" > /dev/null << ZSHRC_EOF
# =============================================================================
# ~/.zshrc — ZSH Configuration
# Machine: $HOSTNAME_VAL | RAM: ${RAM_GIB}GiB | Cores: $CPU_CORES
# Theme: $THEME_ENGINE
# Generated by setup_zsh.sh
# =============================================================================

# =============================================================================
# PERFORMANCE: Profiling (uncomment to debug slow startup)
# zmodload zsh/zprof
# =============================================================================

# =============================================================================
# OH-MY-ZSH CORE SETUP
# =============================================================================

export ZSH="\$HOME/.oh-my-zsh"

# --- Theme ---
# Powerlevel10k instant prompt: renders prompt before zsh fully loads
# Must be near the very top of .zshrc
$(if [[ "$THEME_ENGINE" == "p10k" ]]; then
cat << 'P10K_INSTANT'
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
ZSH_THEME="powerlevel10k/powerlevel10k"
P10K_INSTANT
else
cat << 'STARSHIP_THEME'
ZSH_THEME=""   # Empty = no OMZ theme; Starship handles prompt
STARSHIP_THEME
fi)

# =============================================================================
# OH-MY-ZSH PLUGINS
# The order matters: syntax-highlighting MUST be last among these
# =============================================================================

plugins=(
    # --- Core zsh ---
    git                     # git aliases (gst, gco, gp, gl, etc.) and prompt info
    history                 # adds 'h' alias for history, 'hsi' for grep history
    history-substring-search # Up/Down arrow searches history by current input
    colored-man-pages       # colorizes man pages
    command-not-found       # suggests package to install for unknown commands
    sudo                    # double-tap ESC to prepend sudo to current command
    copypath                # copies current dir path to clipboard
    copyfile                # copies file contents to clipboard
    dirhistory              # Alt+Left/Right to navigate dir history

    # --- Developer tools ---
    git-extras              # extra git commands
    docker                  # docker aliases and completions
    docker-compose          # docker-compose aliases
    python                  # python/pip aliases
    pip                     # pip completions
    virtualenv              # shows active virtualenv in prompt
    rust                    # rust/cargo completions
    aws                     # aws-cli completions and prompt info

    # --- System/tools ---
    fzf                     # fzf keybindings: Ctrl+T (files), Ctrl+R (history), Alt+C (dirs)
    zoxide                  # smarter cd — 'z' command learns your dirs

    # --- Custom plugins (cloned to ~/.oh-my-zsh/custom/plugins/) ---
    zsh-completions         # extra completions for many tools
    zsh-autosuggestions     # ghost-text suggestions from history (→ to accept)
    you-should-use          # reminds you of aliases you forgot you have
    zsh-fzf-history-search  # Ctrl+R → fzf history picker
    zsh-syntax-highlighting # MUST be last: colors commands as you type
)

# Load oh-my-zsh
source "\$ZSH/oh-my-zsh.sh"

# =============================================================================
# HISTORY SETTINGS (using oh-my-zsh defaults with minor tweaks)
# =============================================================================

HISTSIZE=50000          # lines kept in memory
SAVEHIST=50000          # lines saved to disk
HISTFILE="\$HOME/.zsh_history"

setopt HIST_IGNORE_DUPS     # don't record duplicates
setopt HIST_IGNORE_SPACE    # lines starting with space are not recorded
setopt HIST_REDUCE_BLANKS   # remove extra blanks from history entries
setopt HIST_VERIFY          # show history expansion before executing
# NOTE: Append-on-exit is OMZ default (INC_APPEND_HISTORY not set)
# Change to setopt SHARE_HISTORY if you want live sharing across terminals

# =============================================================================
# VI-MODE CONFIGURATION
# =============================================================================

$(if [[ "$ENABLE_VI_MODE" == "true" ]]; then
cat << 'VIMODE'
# vi-mode is already loaded via oh-my-zsh plugins if you add 'vi-mode'
# We configure it manually for more control:
bindkey -v                          # Enable vi keybindings
export KEYTIMEOUT=1                 # 10ms delay for ESC (default 400ms is too slow)

# Restore useful emacs bindings that vi-mode removes:
bindkey '^A' beginning-of-line      # Ctrl+A → start of line
bindkey '^E' end-of-line            # Ctrl+E → end of line
bindkey '^R' fzf-history-widget     # Ctrl+R → fzf history search
bindkey '^P' up-history             # Ctrl+P → prev history
bindkey '^N' down-history           # Ctrl+N → next history
bindkey '^?' backward-delete-char   # Backspace works in normal mode
bindkey '^H' backward-delete-char
bindkey '^W' backward-kill-word     # Ctrl+W → delete word

# Show mode indicator in prompt (works with Starship's vimcmd_symbol too)
function zle-keymap-select() {
    case $KEYMAP in
        vicmd)      print -n '\e[2 q';;   # block cursor in normal mode
        viins|main) print -n '\e[6 q';;   # beam cursor in insert mode
    esac
    zle reset-prompt
}
zle -N zle-keymap-select

# Start with beam cursor
function zle-line-init() { print -n '\e[6 q'; }
zle -N zle-line-init

# Edit command in $EDITOR (Ctrl+X Ctrl+E or 'v' in normal mode)
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey -M vicmd 'v' edit-command-line
VIMODE
else
cat << 'NOVIMODE'
# Emacs-style keybindings (vi-mode disabled)
bindkey -e
NOVIMODE
fi)

# =============================================================================
# ENVIRONMENT
# =============================================================================

# Editor
export EDITOR="nvim"
export VISUAL="nvim"

# Pager: use bat instead of less (syntax highlighting in man pages, etc)
export PAGER="less"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"  # colorized man pages via bat

# XDG base dirs (many tools respect these)
export XDG_CONFIG_HOME="\$HOME/.config"
export XDG_DATA_HOME="\$HOME/.local/share"
export XDG_CACHE_HOME="\$HOME/.cache"

# Go (if installed later)
export GOPATH="\$HOME/go"
export PATH="\$PATH:\$GOPATH/bin"

# Rust / Cargo
[[ -f "\$HOME/.cargo/env" ]] && source "\$HOME/.cargo/env"

# Local binaries
export PATH="\$HOME/.local/bin:\$PATH"

# Python: don't write .pyc files everywhere, cleaner dirs
export PYTHONDONTWRITEBYTECODE=1

# AWS CLI: disable pager by default (annoying in scripts)
export AWS_PAGER=""

# fzf: use fd instead of find (faster, respects .gitignore)
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="\$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
# fzf appearance
export FZF_DEFAULT_OPTS='
    --height 40%
    --layout=reverse
    --border
    --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8
    --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc
    --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8
'

# =============================================================================
# ALIASES
# =============================================================================

# --- File listing (eza replaces ls) ---
# eza: modern ls with colors, icons, git status
alias ls='eza --icons --group-directories-first'
alias ll='eza -lah --icons --group-directories-first --git'
alias lt='eza --tree --level=2 --icons'
alias lta='eza --tree --level=3 --icons --all'

# --- Better defaults ---
alias cat='bat --paging=never'           # bat: syntax-highlighted cat
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -sh'
alias free='free -h'
alias diff='diff --color=auto'
alias ip='ip --color=auto'
alias mkdir='mkdir -pv'                  # make parent dirs, verbose
alias cp='cp -iv'                        # interactive + verbose
alias mv='mv -iv'
alias rm='rm -iv'                        # safer rm

# --- Navigation ---
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
# zoxide 'z' is auto-setup by OMZ plugin; 'zi' = interactive fzf picker

# --- Editors ---
alias v='nvim'
alias vi='nvim'
alias vim='nvim'
alias sv='sudo nvim'

# --- System ---
alias reload='source ~/.zshrc && echo "zshrc reloaded"'
alias zshrc='nvim ~/.zshrc'
alias ports='ss -tulpn'
alias psg='ps aux | grep -v grep | grep'  # e.g. psg firefox
alias myip='curl -s ifconfig.me'
alias localip="ip route get 1 | awk '{print \$7}' | head -1"

# --- Package management (Fedora/DNF) ---
alias dnfi='sudo dnf install'
alias dnfr='sudo dnf remove'
alias dnfu='sudo dnf upgrade'
alias dnfs='dnf search'
alias dnfin='dnf info'

# --- Docker ---
alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dimg='docker images'
alias dlogs='docker logs -f'
alias dexec='docker exec -it'
alias dprune='docker system prune -af'

# --- Git extras ---
alias glog='git log --oneline --graph --decorate --all'
alias gst='git status -sb'
alias gdiff='git diff --stat'

# --- Python ---
alias py='python3'
alias pip='pip3'
alias venv='python3 -m venv .venv && source .venv/bin/activate'
alias activate='source .venv/bin/activate'

# --- Networking ---
alias ping='ping -c 5'
alias flushdns='sudo resolvectl flush-caches && echo "DNS cache flushed"'
alias dnsstatus='resolvectl status'

# --- Misc ---
alias h='history | tail -50'
alias c='clear'
alias q='exit'
alias top='htop 2>/dev/null || top'

# =============================================================================
# FUNCTIONS
# =============================================================================

# mkcd: make directory and cd into it in one command
mkcd() { mkdir -p "\$1" && cd "\$1"; }

# extract: universal archive extractor
extract() {
    if [[ -f "\$1" ]]; then
        case "\$1" in
            *.tar.bz2) tar xjf "\$1"    ;;
            *.tar.gz)  tar xzf "\$1"    ;;
            *.tar.xz)  tar xJf "\$1"    ;;
            *.bz2)     bunzip2 "\$1"    ;;
            *.rar)     unrar x "\$1"    ;;
            *.gz)      gunzip "\$1"     ;;
            *.tar)     tar xf "\$1"     ;;
            *.tbz2)    tar xjf "\$1"    ;;
            *.tgz)     tar xzf "\$1"    ;;
            *.zip)     unzip "\$1"      ;;
            *.Z)       uncompress "\$1" ;;
            *.7z)      7z x "\$1"       ;;
            *)         echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# up N: go up N directories  (e.g. 'up 3' == cd ../../..)
up() {
    local count="\${1:-1}"
    local path=""
    for i in \$(seq 1 \$count); do path="../\$path"; done
    cd "\$path"
}

# fcd: fzf-powered cd — interactively pick directory to jump to
fcd() {
    local dir
    dir=\$(fd --type d --hidden --exclude .git 2>/dev/null | fzf --preview 'eza --tree --level=2 --icons {}') && cd "\$dir"
}

# fkill: fzf-powered process killer
fkill() {
    local pid
    pid=\$(ps aux | fzf --header='Select process to kill' | awk '{print \$2}')
    [[ -n "\$pid" ]] && kill -9 "\$pid" && echo "Killed PID \$pid"
}

# fe: fzf-powered file open in editor
fe() {
    local file
    file=\$(fzf --preview 'bat --color=always --style=numbers {}') && \${EDITOR:-nvim} "\$file"
}

# backup: quick timestamped backup of a file
backup() { cp "\$1" "\${1}.bak.\$(date +%Y%m%d_%H%M%S)"; echo "Backed up \$1"; }

# sysinfo: quick system summary
sysinfo() {
    echo "Hostname  : \$(hostname)"
    echo "OS        : \$(cat /etc/fedora-release 2>/dev/null || uname -o)"
    echo "Kernel    : \$(uname -r)"
    echo "CPU       : \$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
    echo "Cores     : \$(nproc)"
    echo "RAM       : \$(free -h | awk '/^Mem/{print \$2}')"
    echo "Disk /    : \$(df -h / | awk 'NR==2{print \$3 "/" \$2 " (" \$5 " used)"}')"
    echo "Uptime    : \$(uptime -p)"
    echo "Shell     : \$SHELL"
}

# docker-shell: quick exec into a running container
dsh() { docker exec -it "\${1}" /bin/bash 2>/dev/null || docker exec -it "\${1}" /bin/sh; }

# =============================================================================
# COMPLETIONS SETUP
# =============================================================================

# Load completions (including from zsh-completions plugin)
autoload -Uz compinit
# Refresh completion cache once per day (speeds up startup on repeat launches)
if [[ -n "\${ZDOTDIR:-\$HOME}/.zcompdump"(#qN.mh+24) ]]; then
    compinit
else
    compinit -C
fi

# Completion styling
zstyle ':completion:*' menu select                   # arrow-key navigation
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' # case-insensitive
zstyle ':completion:*' list-colors "\${(s.:.)LS_COLORS}"
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{red}No matches%f'
zstyle ':completion::complete:*' gain-privileges 1   # complete sudo commands

# =============================================================================
# ZOXIDE INIT (smarter cd)
# Must come after compinit
# =============================================================================
eval "\$(zoxide init zsh)"

# =============================================================================
# PROMPT (Starship or Powerlevel10k)
# =============================================================================

$(if [[ "$THEME_ENGINE" == "starship" ]]; then
cat << 'STARSHIP_INIT'
# Starship prompt — fast Rust binary, minimal overhead
# Config: ~/.config/starship.toml
eval "$(starship init zsh)"
STARSHIP_INIT
else
cat << 'P10K_INIT'
# Powerlevel10k config file — run 'p10k configure' to regenerate interactively
# The wizard sets up icons, git info, timing, etc.
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
P10K_INIT
fi)

# =============================================================================
# MACHINE-SPECIFIC SETTINGS (auto-detected by hostname)
# =============================================================================

case "\$(hostname -s)" in
    nbMain)
        # Dell OptiPlex 790 | i5-2400 | 31 GiB RAM | Intel Sandy Bridge GPU
        # Nothing special needed — P10k already selected, RAM is plentiful
        ;;
    nbAcer)
        # Acer Aspire | i5-8400 | 7.62 GiB RAM | Intel UHD 630
        # Slightly conservative: limit background jobs
        export MAKEFLAGS="-j6"
        ;;
    nbXPS)
        # Dell XPS 15 | i7-6700HQ | 15 GiB | NVIDIA GTX 960M + Intel HD 530
        export MAKEFLAGS="-j8"
        # NVIDIA DRM (relevant for CUDA tools in dev work)
        ;;
    nbLenovo)
        # Lenovo 300 | i3-6100U | 5.64 GiB | Intel HD 520
        # Low RAM: limit parallel jobs, use conservative settings
        export MAKEFLAGS="-j3"
        # Disable features that use RAM in fzf
        export FZF_DEFAULT_OPTS="\$FZF_DEFAULT_OPTS --height 30%"
        ;;
    nbServer)
        # HP Compaq | AMD A4 | 14 GiB | Headless server
        # No GUI tools needed; server-focused aliases
        alias logs='sudo journalctl -f'
        alias services='systemctl list-units --type=service --state=running'
        alias ports='ss -tulpn'
        export MAKEFLAGS="-j2"
        ;;
esac

# =============================================================================
# LOCAL OVERRIDES
# Anything in ~/.zshrc.local is sourced last — machine-specific tweaks
# that you don't want tracked in version control
# =============================================================================
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# =============================================================================
# DEBUG: Uncomment to see startup time breakdown
# zprof
# =============================================================================
ZSHRC_EOF

success "~/.zshrc written"

# =============================================================================
# STEP 7: SET ZSH AS DEFAULT SHELL
# =============================================================================

section "Setting zsh as default shell"

ZSH_PATH=$(which zsh)

if [[ "$SHELL" == "$ZSH_PATH" ]]; then
    success "zsh is already the default shell"
else
    info "Changing default shell to $ZSH_PATH for $TARGET_USER..."
    # chsh requires zsh to be in /etc/shells
    if ! grep -q "$ZSH_PATH" /etc/shells; then
        echo "$ZSH_PATH" | $SUDO_CMD tee -a /etc/shells
        info "Added $ZSH_PATH to /etc/shells"
    fi
    $SUDO_CMD chsh -s "$ZSH_PATH" "$TARGET_USER"
    success "Default shell changed to $ZSH_PATH (takes effect on next login)"
fi

# =============================================================================
# STEP 8: POWERLEVEL10K NOTICE
# =============================================================================

if [[ "$THEME_ENGINE" == "p10k" ]]; then
    section "Powerlevel10k setup"
    warn "After reloading zsh, run:  p10k configure"
    warn "This launches an interactive wizard to configure your prompt visuals."
    warn "Prerequisites: Install a Nerd Font in your terminal (you already have them)."
    warn "Recommended: JetBrainsMono Nerd Font or Noto Mono for your terminal."
fi

# =============================================================================
# DONE
# =============================================================================

section "Summary"

echo ""
echo -e "  Machine    : ${GREEN}$HOSTNAME_VAL${NC}"
echo -e "  RAM        : ${GREEN}${RAM_GIB} GiB${NC}"
echo -e "  Theme      : ${GREEN}$THEME_ENGINE${NC}"
echo -e "  Vi-mode    : ${GREEN}$ENABLE_VI_MODE${NC}"
echo -e "  Shell      : ${GREEN}$(which zsh)${NC}"
echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Log out and back in (or run: exec zsh)"
[[ "$THEME_ENGINE" == "p10k" ]] && \
echo "  2. Run 'p10k configure' to set up your prompt visually"
echo "  3. Edit ~/.zshrc.local for machine-specific tweaks"
echo "  4. Run 'sysinfo' to verify your environment"
echo ""
EOF