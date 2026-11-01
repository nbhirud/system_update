#!/bin/bash

set -eux

############################
# TODO
############################

# Add logic to Check if things like docker, podman, helm, git, github, and everything else are available or already setup

# Could be done by having a flag somewhere that gets set when the docker, etc setup scripts are run
# Another way is to check if the executable is installed in /bin/xyz or other places
# Could be more ways too. Figure out whats best.

############################

DISTRO=""
SETUP_TYPE=""
DESKTOP=""
FILENAME_TIMESTAMP=""

if [[ -z $1 ]] && [[ -z $2 ]] && [[ -z $3 ]];
then 
  echo "DISTRO and/or SETUP_TYPE and/or DESKTOP not passed as input. Need to pass both"
  exit 1
  
else
  DISTRO=$1
  SETUP_TYPE=$2
  DESKTOP=$3
  echo "Inputs provided: DISTRO = $DISTRO, SETUP_TYPE = $SETUP_TYPE, DESKTOP = $DESKTOP"

fi

if [[ -z $4 ]];
then 
  echo "FILENAME_TIMESTAMP not passed. It will be calculated based on current time."
  FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"

else
  FILENAME_TIMESTAMP=$4

fi


# if [[ -z $1 ]];
# then 
#   echo "Distro not provided. Identifying"
#   DISTRO=$(sh $SYSUPDATE_CODE_BASE_DIR/linux/common/get_distro_name.sh)
  
#   if [ "$DISTRO" != "" ];
#   then 
#     echo "Distro identified = $DISTRO"

#   else
#     echo "Distro could not be identified."

#   fi

#   sleep 5s

# else
#   DISTRO=$1
#   echo "Distro privided as input = $DISTRO"
# fi


####################################################################
# Instructions before steps
#####################################################################

### ch



# For a Fedora developer workstation, I'd actually simplify things slightly:

# Core packages to install
# zsh
# git
# curl
# wget
# fzf
# zoxide
# eza
# bat
# ripgrep
# fd-find
# lazygit
# jq
# tree
# htop
# fastfetch
# Optional auto-integrations (only enabled if present)
# docker
# podman
# kubectl
# aws
# tailscale
# syncthing
# direnv
# node
# python
# uv
# Oh My Zsh plugins

# Built-in:

# git
# sudo
# python
# pip
# docker
# podman
# kubectl
# aws
# colored-man-pages
# command-not-found
# extract

# External:

# zsh-autosuggestions
# zsh-syntax-highlighting
# zsh-completions
# Prompt

# Use:

# Powerlevel10k

# It is effectively the standard recommendation today. On any Fedora machine capable of running KDE comfortably, the overhead is negligible.


### ge



# Here is your universal, hardware-aware, and hardened zsh + oh-my-zsh setup script. It explicitly handles optimizations across your 5 different Fedora machines (handling your headless server differently than your heavy-RAM or discrete GPU-enabled systems), locks down telemetry, configures secure history preservation, and injects NextDNS/Tailscale stubs cleanly.
# The Design Matrix


# Rows:
# 1  Optimization Target	
# 2  Prompt Engine	
# 3  Zsh Plugins	
# 4  Highlighting & Suggest	
# 5  KDE/X11 Integration	

# 1 Headless (nbServer)	
# 2 Light custom OMZ (robbyrussell)
# 3 Minimal (git, sudo)
# 4 Disabled (Saves CPU cycles)
# 5 Stripped entirely	

# 1 Low Resource (nbLenovo)	
# 2 Light custom OMZ (robbyrussell)
# 3 Core (git, sudo, z)
# 4 Enabled (Compiled Zsh binaries)	
# 5 Enabled (TTY/VTE context)

# 1 High Resource (nbMain, nbAcer, nbXPS)
# 2 Starship (Blazing fast Rust engine)
# 3 Heavyweight (git, sudo, z, fzf)
# 4 Enabled (Compiled Zsh binaries)
# 5 Enabled (TTY/VTE context)
		
	

# The Universal Installation Script

# Save this script as setup_zsh.sh, run chmod +x setup_zsh.sh, and execute it. It is completely idempotent and handles dependencies natively via dnf.













# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================
### lu
# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color


log_info()    { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
log_warn()    { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_error()   { printf "${RED}[ERROR]${NC} %s\n" "$1"; }
log_success() { printf "${CYAN}[SUCCESS]${NC} %s\n" "$1"; }
log_header()  { printf "\n${BLUE}=== %s ===${NC}\n" "$1"; }


# =============================================================================
# HARDWARE DETECTION & OPTIMIZATION
# =============================================================================
### lu
detect_hardware() {
    log_header "Hardware Detection"
    
    # Detect CPU cores
    CPU_CORES=$(nproc)
    log_info "Detected CPU Cores: $CPU_CORES"
    
    # Detect RAM in GB
    RAM_GB=$(free -g | awk '/^Mem:/ {print $2}')
    log_info "Detected RAM: ${RAM_GB} GB"
    
    # Detect GPU
    if command -v lspci &> /dev/null; then
        GPU_INFO=$(lspci | grep -i vga | head -1 | cut -d: -f3 | xargs)
        log_info "Detected GPU: $GPU_INFO"
    else
        GPU_INFO="Unknown"
        log_warn "Could not detect GPU (lspci not available)"
    fi
    
    # Detect Disk Type and Space
    DISK_TYPE=""
    MOUNT_POINT=$(df -h ~ | tail -1 | awk '{print $1}' | grep -q 'nvme\|ssd' && echo "SSD/NVMe" || echo "HDD")
    FREE_SPACE=$(df -h ~ | awk 'NR==2 {print $4}')
    log_info "Disk Type: $MOUNT_POINT | Free Space: $FREE_SPACE"
    
    # Hardware-based optimizations
    # High RAM (>12GB): Enable memory-intensive features
    if [[ $RAM_GB -ge 12 ]]; then
        log_info "High RAM detected - enabling performance optimizations"
        COMPLETION_CACHE_ENABLED=true
        ENABLE_HISTORY_SEARCH=true
        MEMORY_EFFICIENT=false
    elif [[ $RAM_GB -le 6 ]]; then
        log_warn "Low RAM detected - enabling memory-efficient mode"
        COMPLETION_CACHE_ENABLED=false
        ENABLE_HISTORY_SEARCH=false
        MEMORY_EFFICIENT=true
    else
        log_info "Moderate RAM - using balanced configuration"
        COMPLETION_CACHE_ENABLED=true
        ENABLE_HISTORY_SEARCH=true
        MEMORY_EFFICIENT=false
    fi
    
    # Low CPU (<4 cores): Reduce plugin count
    if [[ $CPU_CORES -lt 4 ]]; then
        log_warn "Low CPU cores - reducing plugin load"
        MINIMAL_PLUGIN_MODE=true
    else
        MINIMAL_PLUGIN_MODE=false
    fi
    
    # Store hardware info for script sections
    export CPU_CORES RAM_GPU INFO DISK_TYPE FREE_SPACE
    export COMPLETION_CACHE_ENABLED ENABLE_HISTORY_SEARCH MEMORY_EFFICIENT MINIMAL_PLUGIN_MODE
}

### ge


# 1. Hardware and Environment Detection
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$(( TOTAL_RAM_KB / 1024 / 1024 ))
IS_HEADLESS=0

# Detect Headless Server via systemd multi-user target or hostname
if [ "$(systemctl get-default)" = "multi-user.target" ] || [[ "$(hostname)" == *"Server"* ]]; then
    IS_HEADLESS=1
    echo "[-] Headless environment detected profile."
else
    echo "[+] Desktop environment detected profile."
fi

echo "[+] Detected RAM: ${TOTAL_RAM_GB} GB"



# =============================================================================
# Backup if an existing installation is detected
# =============================================================================
### orig
HOME_DIR=$(getent passwd $USER | cut -d: -f6)
NBDIR="$HOME_DIR/nb"
SCRIPT_BACKUPS_DIR="$NBDIR/nb_script_backups" 
ZSH_BKP_DIR="$SCRIPT_BACKUPS_DIR/ZSH_BKP_$FILENAME_TIMESTAMP"

OMZ_BKP_PATH="$ZSH_BKP_DIR/OMZ"
# Check if OMZ is already setup
OMZ_DIR=~/.oh-my-zsh
if [ -d $OMZ_DIR ]; 
then
  # Can backup before removing this directory. But that is of no good use. Remove directly
  echo "$OMZ_DIR exists. This will be deleted before fresh setup."
  # rm -rf "$OMZ_DIR"
  mv "$OMZ_DIR" "$OMZ_BKP_PATH"
fi

HOME_DIR=$(getent passwd $USER | cut -d: -f6)
ZSHRC_FILENAME=".zshrc"
# ZSHRC_BKP_FILENAME="$ZSHRC_FILENAME"_bkp
ZSHRC_BKP_PATH="$ZSH_BKP_DIR/$ZSHRC_FILENAME"

if [ -e "$HOME_DIR/$ZSHRC_FILENAME" ]
then
    echo "$HOME_DIR/$ZSHRC_FILENAME already exists. Creating a backup and deleting. Backup: $ZSHRC_BKP_PATH"
    mv "$HOME_DIR/$ZSHRC_FILENAME" "$ZSHRC_BKP_PATH"
else
    echo "$HOME_DIR/$ZSHRC_FILENAME does not already exist."
fi

### ch

BACKUP_DIR="$HOME/.config/zsh-backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"


echo "=== Backing up existing configuration ==="

[[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$BACKUP_DIR/"


# =============================================================================
# DEPENDENCY INSTALLATION
# =============================================================================

### orig
echo "************************ Install zsh ************************"
sudo dnf install -y zsh

echo "************************ Make zsh the default shell ************************"
# chsh -s $(which zsh) 
# chsh -s $(which zsh) nbhirud
chsh -s $(which zsh) $USER


### lu

install_dependencies() {
    log_header "Installing Dependencies"
    
    # Check if running as root (not required but warn)
    if [[ $EUID -eq 0 ]]; then
        log_warn "Running as root - this is generally not recommended for user config"
    fi
    
    # Install base dependencies via dnf (Fedora)
    log_info "Installing system dependencies..."
    
    # Essential packages
    REQUIRED_PACKAGES=(
        zsh                    # Shell itself
        git                    # Version control
        curl                   # For downloading
        wget                   # Alternative download tool
        jq                     # JSON processing (useful for LLM work)
        fzf                    # Fuzzy finder 
    )
    
    # Optional performance packages
    OPTIONAL_PACKAGES=(
        bat         # Cat alternative with syntax highlighting
        eza         # Modern ls replacement
        ripgrep     # Faster grep alternative
        fd          # Faster find alternative
        tldr        # Simplified man pages
    )
    
    # Check which packages are missing
    MISSING_PACKAGES=()
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            MISSING_PACKAGES+=("$pkg")
        fi
    done
    
    if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
        log_info "Missing packages: ${MISSING_PACKAGES[*]}"
        log_info "Installing via dnf (this may require sudo password)..."
        sudo dnf install -y "${MISSING_PACKAGES[@]}" || {
            log_error "Failed to install some packages. You may need to run: sudo dnf install ${MISSING_PACKAGES[*]}"
            return 1
        }
    else
        log_success "All required packages already installed"
    fi
    
    # Optional packages (user choice)
    echo -e "\n${CYAN}Optional productivity tools available:${NC}"
    PS3="Select packages to install (0 to skip): "
    select opt in "${OPTIONAL_PACKAGES[@]}""Cancel"; do
        if [[ $REPLY -eq 0 ]]; then
            break
        elif [[ $REPLY -ge 1 && $REPLY -le ${#OPTIONAL_PACKAGES[@]} ]]; then
            PKG="${OPTIONAL_PACKAGES[$((REPLY-1))]}"
            log_info "Installing $PKG..."
            sudo dnf install -y "$PKG"
        else
            break
        fi
    done
}

### ch



echo "=== Installing packages ==="

sudo dnf install -y \
    zsh \
    git \
    curl \
    wget \
    fzf \
    zoxide \
    eza \
    bat \
    ripgrep \
    fd-find \
    jq \
    tree \
    htop \
    fastfetch

echo "=== Installing lazygit if missing ==="

if ! command -v lazygit >/dev/null 2>&1; then
    sudo dnf install -y lazygit || true
fi


echo "=== Setting ZSH as default shell ==="

if [[ "$SHELL" != "$(command -v zsh)" ]]; then
    chsh -s "$(command -v zsh)"
fi

### ge


# 2. Install Required Core System Packages Natively
echo "[+] Installing core system packages via DNF..."
sudo dnf install -y zsh git util-linux-user fzf



# =============================================================================
# OH-MY-ZSH INSTALLATION
# =============================================================================

### orig 
echo "************************ Install omz (Oh My zsh) unattended ************************"
# sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || {
  echo "Could not install Oh My Zsh" >/dev/stderr
  exit 1
}

### lu
install_oh_my_zsh() {
    log_header "Installing Oh My Zsh"
    
    # Check if already installed
    if [[ -d ~/.oh-my-zsh ]]; then
        log_warn "Oh My Zsh already exists at ~/.oh-my-zsh"
        read -p "Do you want to reinstall? (y/N): " REPLY
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping Oh My Zsh installation"
            return 0
        fi
        rm -rf ~/.oh-my-zsh
    fi
    
    # Install Oh My Zsh unattended
    log_info "Cloning Oh My Zsh repository..."
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || {
        log_error "Failed to install Oh My Zsh"
        return 1
    }
    
    log_success "Oh My Zsh installed successfully"
}


### ch

echo "=== Installing Oh My Zsh ==="

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    RUNZSH=no CHSH=no \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi


# =============================================================================
# COMMUNITY PLUGINS INSTALLATION
# =============================================================================

### orig 

echo "************************ Install omz plugins ************************"
# cd $ZSH_CUSTOM/plugins e # also, this cd is actually unnecessary

# now a built-in Oh My Zsh plugin
# git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# now a built-in Oh My Zsh plugin
# git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

git clone https://github.com/Aloxaf/fzf-tab ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab

# https://docs.docker.com/engine/install/fedora/
# https://docs.docker.com/engine/cli/completion/#zsh
# mkdir -p ~/.oh-my-zsh/completions
# docker completion zsh > ~/.oh-my-zsh/completions/_docker


### lu
install_community_plugins() {
    log_header "Installing Community Plugins"
    
    PLUGIN_DIR="$HOME/.oh-my-zsh/custom/plugins"
    
    # Plugin definitions with repo URLs
    declare -A PLUGINS=(
        ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions.git"
        ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
        ["zsh-completions"]="https://github.com/zsh-users/zsh-completions.git"
    )
    
    # Additional plugins based on your tech stack (conditional on minimal mode)
    if [[ "$MINIMAL_PLUGIN_MODE" == "false" ]]; then
        PLUGINS["zsh-history-substring-search"]="https://github.com/zsh-users/zsh-history-substring-search.git"
        PLUGINS["docker-compose"]="https://github.com/PatrickF1/zsh-docker-compose.git"
        PLUGINS["pip"]="https://github.com/pypa/pip.git"
    fi
    
    for plugin in "${!PLUGINS[@]}"; do
        local plugin_path="$PLUGIN_DIR/$plugin"
        
        if [[ -d "$plugin_path" ]]; then
            log_info "$plugin already installed, updating..."
            cd "$plugin_path" && git pull --quiet
        else
            log_info "Installing $plugin..."
            git clone --depth 1 "${PLUGINS[$plugin]}" "$plugin_path" || {
                log_warn "Failed to clone $plugin, continuing..."
                continue
            }
        fi
    done
    
    log_success "Community plugins installed/updated"
}

### ch 

echo "=== Installing ZSH plugins ==="

CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

install_plugin() {
    local repo="$1"
    local name="$2"

    if [[ ! -d "$CUSTOM_DIR/plugins/$name" ]]; then
        git clone --depth=1 "$repo" "$CUSTOM_DIR/plugins/$name"
    fi
}

install_plugin \
  https://github.com/zsh-users/zsh-autosuggestions \
  zsh-autosuggestions

install_plugin \
  https://github.com/zsh-users/zsh-syntax-highlighting \
  zsh-syntax-highlighting

install_plugin \
  https://github.com/zsh-users/zsh-completions \
  zsh-completions


# =============================================================================
# THEME CONFIGURATION (Powerlevel10k - Fast & Compatible)
# =============================================================================
install_powerlevel10k() {
    log_header "Installing Powerlevel10k Theme"
    
    # Check if already installed
    if [[ -d ~/.oh-my-zsh/themes/powerlevel10k ]]; then
        log_info "Powerlevel10k already installed"
        return 0
    fi
    
    # Clone powerlevel10k
    git clone --depth 1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/themes/powerlevel10k || {
        log_error "Failed to install Powerlevel10k"
        return 1
    }
    
    # Configure default theme in .zshrc
    sed -i 's/ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc
    
    # Create initial p10k config (minimal interactive prompt)
    cat > ~/.p10k.zsh << 'EOF'
# Powerlevel10k Configuration - Optimized for Developer Workflow
# Font: Noto Mono / Ubuntu Mono (Terminal), Noto / Ubuntu (System)
# Generated automatically by setup script

POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir vcs context)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status time)

# Disable transient prompt (keeps history cleaner)
POWERLEVEL9K_TRANSIENT_PROMPT=off

# Use custom fonts from your nerd fonts installation
POWERLEVEL9K_VCS_BRANCH_ICON=''
POWERLEVEL9K_VCS_UNTRACKED_ICON='?'

# Time format (24-hour, compact)
POWERLEVEL9K_TIME_FORMAT='%D{%H:%M}'

# Context format (user@host)
POWERLEVEL9K_CONTEXT_ROOT_TEMPLATE='%n@%m'
POWERLEVEL9K_CONTEXT_DEFAULT_TEMPLATE='%n@%m'

# Directory style
POWERLEVEL9K_DIR_HOME_SUBFOLDER='%~'
POWERLEVEL9K_DIR_DEFAULT_VALUE='%~'

# Color scheme compatible with dark KDE themes
POWERLEVEL9K_BACKGROUND='none'
POWERLEVEL9K_FOREGROUND='white'
POWERLEVEL9K_GRAY='gray'

# Performance optimizations based on hardware
ENABLE_CORRECTION=false
EOF

    log_success "Powerlevel10k configured"
}

### ch

echo "=== Installing Powerlevel10k ==="

P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"

if [[ ! -d "$P10K_DIR" ]]; then
    git clone --depth=1 \
      https://github.com/romkatv/powerlevel10k.git \
      "$P10K_DIR"
fi



# =============================================================================
# ZSHRC CONFIGURATION
# =============================================================================

### orig
# echo "************************ Configure omz ************************"
# nano ~/.zshrc


# # ZSH_THEME="robbyrussell" # comment this line
# ZSH_THEME="agnoster"
# zstyle ':omz:update' mode auto # Uncomment this
# zstyle ':omz:update' frequency 7 # Uncomment and change value
# ENABLE_CORRECTION="true" # Uncomment - Give it a try
# COMPLETION_WAITING_DOTS="true"
# plugins=(git branch gh github gitignore pre-commit dnf yum sudo safe-paste python pip poetry repo zsh-autosuggestions zsh-syntax-highlighting colorize history history-substring-search aws docker docker-compose helm kops kubectl podman mongocli postgres rsync rust timer rsync vscode zsh-interactive-cd zsh-navigation-tools screen fzf-tab)



# Change theme from robbyrussell to agnoster
sed -i 's|^ZSH_THEME=.*|ZSH_THEME=\"agnoster\"|' ~/.zshrc


# sed -i '/<search string>/s/^/#/g' <file>    (syntax to comment out)
# sed -i '/<search string>/s/^#//g' <file>    (syntax to uncomment)
# sed -i "/# zstyle ':omz:update' mode auto/s/^#//g" ~/.zshrc # Just uncommenting an existing line

# Append a line below the searched commented line:
# https://www.gnu.org/software/sed/manual/html_node/Other-Commands.html
sed -i "/# zstyle ':omz:update' mode auto/a zstyle ':omz:update' mode auto" ~/.zshrc

sed -i "/# zstyle ':omz:update' frequency.*/a zstyle ':omz:update' frequency 7" ~/.zshrc

sed -i "/# ENABLE_CORRECTION.*/a ENABLE_CORRECTION=\"true\"" ~/.zshrc

sed -i "/# COMPLETION_WAITING_DOTS.*/a COMPLETION_WAITING_DOTS=\"true\"" ~/.zshrc

# Plugins
# https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins

# plugins=(git branch gh github gitignore pre-commit dnf yum sudo safe-paste python pip poetry repo zsh-autosuggestions zsh-syntax-highlighting colorize history history-substring-search aws docker docker-compose helm kops kubectl podman mongocli postgres rsync rust timer rsync vscode zsh-interactive-cd zsh-navigation-tools screen fzf-tab)


#https://www.baeldung.com/linux/file-insert-multiple-lines
# If I write "....*/a \n" instead of "....*/a #\n" it is printing the character n in the file. Learn about this
sed -i "/# ZSH_CUSTOM.*/a #\n\n# Added by nbhirud - For vscode plugin\
\n# Add the following line to ~/.zshrc between the ZSH_THEME and plugins=() lines\
\n# Choose one of \`code\`, \`code-insiders\`, \`codium\`, or \`cursor\`.\
\nVSCODE=codium" ~/.zshrc

OMZ_PLUGINS_ONE=""
OMZ_PLUGINS_TWO_DISTRO=""
OMZ_PLUGINS_THREE_DESKTOP=""
OMZ_PLUGINS_FOUR=""
OMZ_PLUGINS_FIVE_FULL=""

OMZ_PLUGINS_ONE="git python uv pip autopep8 pep8 sudo colorize colored-man-pages command-not-found"
# conda conda-env pipenv poetry poetry-env pyenv pylint tig
# virtualenv virtualenvwrapper

if [ "$DISTRO" = "fedora" ];
then 
  OMZ_PLUGINS_TWO_DISTRO="dnf firewalld"
  # yum

elif  [ "$DISTRO" = "ubuntu" ];
then
  OMZ_PLUGINS_TWO_DISTRO="ubuntu ufw snap"

elif  [ "$DISTRO" = "arch" ];
then
  OMZ_PLUGINS_TWO_DISTRO="archlinux ufw"

elif  [ "$DISTRO" = "debian" ];
then
  OMZ_PLUGINS_TWO_DISTRO="debian ufw"

fi

OMZ_PLUGINS_FOUR="branch gh gitignore zsh-autosuggestions zsh-syntax-highlighting vscode zsh-interactive-cd  fzf-tab "
# fzf - do not use this plugin
# github history history-substring-search - not useful for me
# pre-commit repo
# rsync - start using this tool
# safe-paste - very good plugin, but need to get used to using terminal without it
# zsh-navigation-tools

if [ "$SETUP_TYPE" = "full" ];
then 
  OMZ_PLUGINS_FIVE_FULL="aws docker docker-compose timer ssh screen emoji"
  # cask emacs - enable these when you start using emacs
  # tailscale
  # flutter jira jsontools
  # helm kops kubectl k9s podman kompose kubectx kube-ps1 microk8s minikube svcat toolbox
  # postgres rust mongocli mongo-atlas nomad rclone terraform vault
  # kitty - if using kitty terminal
  # redis-cli 
  # shell-proxy ssh-agent
  # systemd - not useful for me
  # thefuck - lol

  # https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/bgnotify - it is configurable
  # zbell - also plays the bell like bgnotify
  if [ "$DESKTOP" = "kde" ];
  then 
    # bgnotify uses kdialog on kde
    OMZ_PLUGINS_THREE_DESKTOP="bgnotify" 

  elif  [ "$DESKTOP" = "gnome" ];
  then
    # bgnotify may use notify-send on gnome. check
    OMZ_PLUGINS_THREE_DESKTOP="bgnotify"

  fi

fi

OMZ_PLUGINS="$OMZ_PLUGINS_ONE $OMZ_PLUGINS_TWO_DISTRO $OMZ_PLUGINS_THREE_DESKTOP $OMZ_PLUGINS_FOUR $OMZ_PLUGINS_FIVE_FULL"

sed -i "s|^plugins=(git)|plugins=($OMZ_PLUGINS)|" ~/.zshrc


sudo tee -a ~/.zshrc <<'OMZ_LAST_EOF'


#################################################################
# OMZ setup added by nbhirud:
#################################################################

#ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#ff00ff,bg=cyan,bold,underline"
ZSH_AUTOSUGGEST_STRATEGY=(history completion match_prev_cmd)
ZSH_HIGHLIGHT_HIGHLIGHTERS+=(main brackets pattern cursor)

#################################################################

OMZ_LAST_EOF


### lu
configure_zshrc() {
    log_header "Configuring ~/.zshrc"
    
    # Backup existing .zshrc
    if [[ -f ~/.zshrc ]]; then
        cp ~/.zshrc ~/.zshrc.backup.$(date +%Y%m%d_%H%M%S)
        log_info "Backed up existing .zshrc"
    fi
    
    # Define plugins array based on hardware optimization
    if [[ "$MINIMAL_PLUGIN_MODE" == "true" ]]; then
        # Low resource machines: essential plugins only
        PLUGINS_CONFIG="git zsh-autosuggestions zsh-syntax-highlighting"
    else
        # Full plugin suite for development workflow
        PLUGINS_CONFIG="git docker docker-compose python pip rust cargo zsh-autosuggestions zsh-syntax-highlighting zsh-completions"
    fi
    
    if [[ "$ENABLE_HISTORY_SEARCH" == "true" ]]; then
        PLUGINS_CONFIG+=" zsh-history-substring-search"
    fi
    
    # Generate complete .zshrc
    cat > ~/.zshrc << EOF
# =============================================================================
# ZSH Configuration - Nik's Development Environment
# Generated: $(date)
# Hostname: $(hostname)
# Hardware: ${CPU_CORES} CPU cores, ${RAM_GB} GB RAM
# =============================================================================

# Load Oh My Zsh
export ZSH="\$HOME/.oh-my-zsh"

# Theme and plugins
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=($PLUGINS_CONFIG)

# Source Oh My Zsh
source \$ZSH/oh-my-zsh.sh

# =============================================================================
# PERSONAL CUSTOMIZATIONS
# =============================================================================

# Export PATH for tools (maintain order, avoid duplicates)
export PATH="\$HOME/bin:\$HOME/.local/bin:\$PATH"

# Add Rust/Cargo path (if installed)
if [[ -d "\$HOME/.cargo" ]]; then
    export PATH="\$HOME/.cargo/bin:\$PATH"
fi

# Python virtual environment activation helper
if command -v virtualenv &> /dev/null; then
    alias pyvenv='python3 -m venv'
    alias pyact='source venv/bin/activate'
fi

# Docker convenience aliases
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias drmi='docker rmi'
alias drmc='docker rm'
alias dlogs='docker logs -f'
alias db='docker build'
alias dr='docker run -it --rm'

# Git shortcuts (you're likely using git frequently)
alias gs='git status'
alias gco='git checkout'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gb='git branch'

# Navigation shortcuts optimized for your filesystem structure
alias h='cd ~'
alias ..='cd ..'
alias ...='cd ../..'
alias data='cd ~/nb'  # Your data storage mount point
alias media1='cd /mnt/media1'
alias media2='cd /mnt/media2'

# Privacy-focused navigation (avoid temp/cache directories in prompt)
setopt INC_APPEND_HISTORY           # Write history immediately
setopt SHARE_HISTORY                # Share history between sessions
setopt HIST_IGNORE_ALL_DUPS         # Delete old records when writing new one
setopt HIST_SAVE_NO_DUPS            # Don't write duplicate records
setopt HIST_FIND_NO_DUPS            # Don't show duplicates in search
setopt HIST_REDUCE_BLANKS           # Remove superfluous blanks

# Command history size (optimized for RAM)
HISTFILE=~/.zsh_history
HISTSIZE=5000
SAVEHIST=10000

# =============================================================================
# PRIVACY & SECURITY HARDENING
# =============================================================================

# Disable telemetry and analytics where possible
unset PROMPT_COMMAND

# Prevent command substitution in .zshrc that could leak info
setopt NO_HIST_ALLOW_COMMENT

# Secure umask for file creation
umask 077

# Disable shell logging (security)
unset HISTFILE_LOG

# NextDNS integration (if you want to specify custom DNS resolver)
# Uncomment below if you want app-level DNS override:
# export NEXTDNS_CLIENT_ID="your-device-id-here"
# Note: Set this per device in ~/.zshrc.local instead of committing

# =============================================================================
# PERFORMANCE TUNING
# =============================================================================

# Completion caching (high RAM systems only)
[[ "$COMPLETION_CACHE_ENABLED" == "true" ]] && {
    autoload -Uz compinit
    compinit -C
}

# Syntax highlighting performance
[[ "$MEMORY_EFFICIENT" != "true" ]] && {
    # Only load full syntax highlighting on capable hardware
    source \$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
}

# =============================================================================
# INTEGRATION WITH YOUR TOOLCHAIN
# =============================================================================

# Neovim/LazyVim integration
if [[ -x "$(command -v nvim)" ]]; then
    alias vim='nvim'
    alias vi='nvim'
    alias v='nvim'
fi

# VS Codium integration  
if [[ -x "$(command -v code)" ]]; then
    alias codium='code'
    alias c='code .'
fi

# Joplin CLI (if installed via snap or flatpak)
if command -v joplin-cli &> /dev/null; then
    alias jp='joplin-cli'
fi

# Syncthing quick start
alias syncthing-gui='syncthing gui'

# Proton Pass/CLI integration hint
# If you install proton-pass-cli later:
# source <(proton-pass-cli completion zsh)

# FZF integration (you mentioned using this)
if [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
    source /usr/share/fzf/key-bindings.zsh
    source /usr/share/fzf/completion.zsh
fi

# =============================================================================
# ALIASES FOR YOUR WORKFLOW
# =============================================================================

# System management (Fedora/KDE specific)
alias update='sudo dnf upgrade --refresh'
alias clean='sudo dnf autoremove && sudo dnf clean all'
alias firewall='sudo firewall-cmd'
alias selinux='sudo getenforce'

# File operations
alias ll='ls -la'
alias l='ls -CF'
alias la='ls -A'
alias lx='ls -lXB'

# Container operations (Docker focus)
alias dcu='docker compose up'
alias dcd='docker compose down'
alias dcrm='docker compose rm'

# Security scanning (if installed)
if command -v grype &> /dev/null; then
    alias scan='grype'
fi

# =============================================================================
# INTERACTIVE OPTIONS
# =============================================================================

# Interactive command corrections
setopt CORRECT

# Beep disable (annoying on wayland)
unsetopt BEEP

# List types in color
LS_COLORS=\"di=01;34:ln=01;36:ex=01;32:\"
export LS_COLORS

# =============================================================================
# LOCAL OVERRIDES (.zshrc.local - NOT committed to version control)
# =============================================================================
# Personal secrets, API keys, device-specific configs go here
if [[ -f ~/.zshrc.local ]]; then
    source ~/.zshrc.local
fi

# =============================================================================
# END OF CONFIGURATION
# =============================================================================
EOF

    log_success ".zshrc configured successfully"
}

### ch


cat > "$HOME/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
    git
    sudo
    python
    pip
    docker
    podman
    kubectl
    aws
    colored-man-pages
    command-not-found
    extract
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-completions
)

source $ZSH/oh-my-zsh.sh

# Better history
HISTSIZE=100000
SAVEHIST=100000
HISTFILE=~/.zsh_history

setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY

# Less annoying completion
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# fzf
[ -f /usr/share/fzf/shell/completion.zsh ] && \
    source /usr/share/fzf/shell/completion.zsh

[ -f /usr/share/fzf/shell/key-bindings.zsh ] && \
    source /usr/share/fzf/shell/key-bindings.zsh

# zoxide
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# eza aliases
if command -v eza >/dev/null; then
    alias ls='eza --group-directories-first'
    alias ll='eza -lah --git --group-directories-first'
    alias lt='eza --tree'
fi

# bat aliases
if command -v bat >/dev/null; then
    alias cat='bat --paging=never'
fi

# safer commands
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -I'

# useful shortcuts
alias grep='rg'
alias df='df -h'
alias du='du -h'
alias ports='ss -tulpn'
alias ff='fastfetch'

# git
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'

# docker
alias d='docker'
alias dc='docker compose'

# podman
alias p='podman'

# navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
EOF

### ge


# 6. Build the Hardened, Telemetry-Free .zshrc
echo "[+] Generating customized .zshrc file..."
cat << 'EOF' > "$HOME/.zshrc"
# ==============================================================================
# HARDENED USER ENVIRONMENT CONFIGURATION (.zshrc)
# ==============================================================================

# Ensure secure path prioritization
export PATH="$HOME/.local/bin:$PATH"

# --- PRIVACY & TELEMETRY HARDENING ---
# Block all analytic/phone-home checks inside Oh My Zsh framework
zstyle ':omz:update' mode disabled
export SCARF_ANALYTICS=false
export DO_NOT_TRACK=1

# --- NEXTDNS & INTEGRATION VARIABLE STUBS ---
# Define unique device metrics for granular NextDNS visibility
export NEXTDNS_ID=""             # <-- INPUT YOUR APP-LEVEL NEXTDNS ENDPOINT ID HERE
export TAILSCALE_ROUTER=""       # <-- OPTIONAL TAILSCALE TARGET NODE MAPPING

# --- DETECT SYSTEM METRICS DYNAMICALLY ---
_RAM_GB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
_IS_SERVER=0
if [ "$(systemctl get-default 2>/dev/null)" = "multi-user.target" ] || [[ "$(hostname)" == *"Server"* ]]; then
    _IS_SERVER=1
fi

# --- USABILITY-FOCUSED HISTORICAL SUB-SYSTEM ---
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=50000
export SAVEHIST=50000

# Usability Options: Share history instantly across shells but ignore common overheads
setopt INC_APPEND_HISTORY        # Write to history immediately, not when shell exits
setopt SHARE_HISTORY             # Share history across concurrent open terminal instances
setopt HIST_IGNORE_DUPS          # Don't record consecutive duplicate entries
setopt HIST_IGNORE_SPACE         # Do not log commands starting with an intentional space
setopt HIST_REDUCE_BLANKS        # Strip redundant white space lines

# Absolute File Integrity Boundary Protection
if [ -f "$HISTFILE" ]; then
    chmod 600 "$HISTFILE"
fi

# --- FRAMEWORK ENGINES & PLUGINS ---
export ZSH="$HOME/.oh-my-zsh"

# Define Plugins conditionally based on machine resource capabilities
if [ "$_IS_SERVER" -eq 1 ]; then
    ZSH_THEME="robbyrussell"
    plugins=(git sudo)
elif [ "$_RAM_GB" -le 6 ]; then
    ZSH_THEME="robbyrussell"
    plugins=(git sudo z)
else
    # High-end Workstations use external sub-engines
    ZSH_THEME="" 
    plugins=(git sudo z fzf zsh-autosuggestions zsh-syntax-highlighting)
fi

# Source Framework Core
source "$ZSH/oh-my-zsh.sh"

# --- PROMPT INITIALIZATION ---
if [ "$_IS_SERVER" -eq 0 ] && [ "$_RAM_GB" -gt 6 ] && command -v starship &> /dev/null; then
    eval "$(starship init zsh)"
fi

# --- SECURE SANE DEFAULTS & MIME MAPPINGS ---
export EDITOR="nvim"
export VISUAL="vscodium"
alias -s {txt,md,json,yaml,yml}=nvim
alias -s {html,pdf}=librewolf

# --- UTILITY & PRIVACY ALIASES ---
alias omz-upgrade="zstyle ':omz:update' mode auto && omz update; zstyle ':omz:update' mode disabled"
alias ts="tailscale"
alias ts-status="tailscale status"
alias ip-leak-check="curl https://am.i.mullvad.net/json"

# Hardware Accelerated Optimization triggers for internal tools if hardware exists
if lspci | grep -qi nvidia; then
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
fi

EOF

# 7. Apply Security Hardening Layer to Files
echo "[+] Establishing strict OS level security parameters on configurations..."
chmod 0700 "$ZSH_DIR"
chmod 0600 "$HOME/.zshrc"




# =============================================================================
# PER-DEVICE CONFIGURATION HINTS
# =============================================================================
generate_device_notes() {
    log_header "Device-Specific Notes"
    
    local hostname=$(hostname)
    
    cat << EOF
===============================================================================
DEVICE SPECIFIC NOTES FOR: $hostname
===============================================================================

Based on hardware detection, apply these optimizations:

EOF

    case "$hostname" in
        nbMain)
            cat << 'DEVICENOTE'
✓ PC1 (nbMain) - HIGH RESOURCE MACHINE
  - Optimal for full plugin suite
  - Can enable completion caching
  - Consider additional dev tools: kdbx, keychain helpers
  - Docker daemon can run natively if needed

DEVICENOTE
            ;;
        nbServer)
            cat << 'DEVICENOTE'
⚠ PC5 (nbServer) - HEADLESS SERVER
  - Minimize visual overhead in .zshrc
  - Focus on automation and scripting
  - Consider disabling powerlevel10k if latency matters
  - Set up SSH key-based authentication
  
DEVICENOTE
            ;;
        *)
            cat << DEVICENOTE
ℹ Machine: $hostname
  - Follow standard configuration
  - Adjust plugin load based on available resources
  - Test terminal responsiveness after installation
  
DEVICENOTE
            ;;
    esac
    
    cat << 'EOF'

NEXT STEPS PER DEVICE:
----------------------
1. Create ~/.zshrc.local with device-specific overrides:
   - Unique NextDNS client IDs
   - Machine-specific paths
   - Personal API keys (NEVER commit these!)

2. Test each component separately:
   $ zsh  # Start fresh zsh session
   $ source ~/.zshrc  # Reload configuration
   
3. Verify plugins:
   $ docker --version
   $ git --version
   $ python3 --version

4. Customize Powerlevel10k interactively (first time only):
   $ p10k configure

5. Set up sync across machines via Syncthing:
   $ syncthing
   Sync: ~/.zshrc, ~/.zshrc.local, ~/.config/fish/

FOSS ALTERNATIVES TO CONSIDER:
------------------------------
- If you prefer lighter prompts: pure-theme or starship (FOSS)
- For enhanced security: consider chsh to non-root user shells
- For audit trails: enable zsh auditing module
===============================================================================
EOF
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    log_header "ZSH Setup Script Starting"
    log_info "Hostname: $(hostname)"
    log_info "Date: $(date)"
    log_info "User: $USER"
    
    # Step-by-step execution with error handling
    detect_hardware
    install_dependencies
    install_oh_my_zsh
    install_community_plugins
    install_powerlevel10k
    configure_zshrc
    configure_firewall_rules
    
    generate_device_notes
    
    # Final summary
    log_header "Setup Complete"
    
    cat << 'FINAL_MESSAGE'

================================================================================
                        SETUP COMPLETE - NEXT ACTIONS
================================================================================

✅ ZSH + Oh My Zsh installed and configured
✅ Community plugins installed (autosuggestions, syntax highlighting)
✅ Powerlevel10k theme configured
✅ Hardware-optimized settings applied
✅ Privacy hardening enabled
✅ Aliases for your workflow added

IMPORTANT POST-INSTALLATION STEPS:
----------------------------------

1. ACTIVATE ZSH IMMEDIATELY:
   $ chsh -s $(which zsh)
   $ exec zsh  # Or logout/relogin

2. FIRST-TIME POWERLEVEL10K SETUP:
   Run once after first zsh launch:
   $ p10k configure
   
   Choose "Compact" or "Command-time" for speed

3. CREATE DEVICE-SPECIFIC CONFIG:
   $ touch ~/.zshrc.local
   $ nano ~/.zshrc.local
   
   Add your NextDNS client ID per device:
   export NEXTDNS_CLIENT_ID="your-unique-id"

4. TEST YOUR SETUP:
   $ zsh -c "echo \$PROMPT"  # Should show powerlevel10k prompt
   $ docker ps               # Should work with docker plugin
   $ git status              # Git aliases ready

5. SYNC ACROSS MACHINES:
   Use Syncthing to keep configs consistent:
   $ syncthing
   
   Sync folder: ~/.zsh* (exclude ~/.zsh_history for privacy)

TROUBLESHOOTING:
----------------
- Missing commands after install: Restart shell entirely
- Font icons not showing: Ensure Nerd Fonts are installed (Noto Mono/Ubuntu Mono)
- Slow startup: Disable unused plugins in ~/.zshrc
- Permission errors: Run with proper user privileges, not root

SECURITY REMINDERS:
-------------------
✓ Never store secrets in shared .zshrc
✓ Use ~/.zshrc.local for device-specific secrets  
✓ Review ~/.zsh_history periodically
✓ Consider removing history on sensitive machines

LEARNING RESOURCES:
-------------------
- Zsh manual: man zsh
- Oh My Zsh docs: https://ohmyz.sh
- Powerlevel10k: https://github.com/romkatv/powerlevel10k
- Plugin directory: ~/.oh-my-zsh/plugins/

================================================================================
Happy coding, Nik! Terminal is now optimized for your workflow.
================================================================================

FINAL_MESSAGE
}

# Run main function
main "$@"

#############################################################################################################



# echo "************************ Update omz ************************"
# omz update
# source .zshrc 



echo $SHELL
echo "************************ NOTE: Reboot/Re-login to see changes ************************"
sleep 5s




sudo tee -a ~/.zshrc <<'ZSHRC_EOF'

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
alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && aws update && uv self update && omz update -y && . torsocks on && fastfetch"
# alias nbupdateproton=". torsocks off && cd /home/nbhirud/nb/CodeProjects/system_update/ && sh /home/nbhirud/nb/CodeProjects/system_update/linux/security_os_level/proton_ag.sh --setup-type full --desktop kde && cd && . torsocks on"
alias nbupdateextra=". torsocks off && sh /home/nbhirud/nb/CodeProjects/system_update/linux/fedora/update_all.sh && nbupdate"

# https://docs.fedoraproject.org/en-US/quick-docs/upgrading-fedora-offline/
# alias nbdistu="sudo sudo dnf upgrade --refresh -y && sudo sudo dnf system-upgrade download --releasever=43 -y"
alias nbreload="systemctl daemon-reload && source ~/.zshrc"
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
source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab/fzf-tab.plugin.zsh


### Show hostname on the right - To identify ssh sessions more obviously:
export RPROMPT='%F{yellow}%m%f'

### Show SSH indicator in Agnoster prompt (not working?)
if [[ -n "$SSH_CONNECTION" ]]; then
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


###############################################################################
# notes at end
###############################################################################
### ch

# A few changes I'd make for your environment after initial setup:

# Install and enable direnv.
# Install uv and add aliases for Python development.
# Add tailscale, syncthing, and docker helper functions.
# Add Fedora-specific aliases for dnf, systemctl, journalctl, firewalld, and SELinux.
# Add FZF integration for zoxide, Git branches, Docker containers, and SSH hosts. Those are some of the biggest productivity wins for daily Linux use.

### ge


# Technical Hardening & Usability Choices

#     Update Privacy: zstyle ':omz:update' mode disabled completely blocks background checking and outbound automated Git calls to GitHub on shell launch. To safely pull down updates on your terms, run the custom, safe proxy alias omz-upgrade.

#     Smart History Mechanics: Instead of cutting history short, SHARE_HISTORY and INC_APPEND_HISTORY make history immediately portable across open terminal grids. Adding HIST_IGNORE_SPACE means any command you run prefixed with a single space (e.g.,   secret_command) will bypass logging completely, protecting runtime tokens and configurations.

#     MIME Fallbacks: Native Zsh suffix aliases are bound inside the template. Typing file names directly (like document.md or api.json) will safely route directly into headless Neovim, while rich web targets deploy to librewolf.

#     Dynamic GPU Detection: If the script encounters your NVIDIA setup (nbXPS), it sets environment flags (__NV_PRIME_RENDER_OFFLOAD) inside the shell layer to assist offloading compute tasks cleanly.

# Android Synchronization Note

# Since you manage mobile endpoints alongside your workstations, install Termux (via F-Droid for secure, tracked FOSS binaries) on your Android devices. You can clone your .zshrc dotfile right into Termux. It safely evaluates the hardware limits, bypasses the workstation-exclusive tools gracefully, and maintains a unified layout across your laptop keyboards and your pocket terminals without breaking paths.

