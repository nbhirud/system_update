#!/bin/bash
#===============================================================================
# python_setup_phase1.sh - Foundation Setup for Python Development
# Target: Fedora 44 + KDE Plasma
# Purpose: Install system-level Python tooling foundation without modifying 
#          Fedora's system Python
# Author: Generated for Nik's development environment
# Date: 2026-10-12
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# CONFIGURATION SECTION - Customize these values if needed
#-------------------------------------------------------------------------------

# Paths (matches your existing setup)
CODE_ROOT="${HOME}/nb/CodeProjects"
BACKUP_ROOT="${HOME}/nb/nb_script_backups"
SCRIPT_REPO_PATH="${HOME}/nb/SystemSetupRepos/python-env-setup"  # Your config repo

# Detection flags (auto-detected below)
FEDORA_VERSION=""
SYSTEM_ARCH=""
CPU_CORES=""
TOTAL_RAM_GB=""
GPU_INFO=""
HAS_JETBRAINS_TOOLBOX=""

# Backup timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/python_setup/${TIMESTAMP}"

# Logging
LOG_FILE="${BACKUP_DIR}/setup.log"

#-------------------------------------------------------------------------------
# UTILITY FUNCTIONS
#-------------------------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2 | tee -a "${LOG_FILE}"
}

warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" | tee -a "${LOG_FILE}"
}

info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" | tee -a "${LOG_FILE}"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep -w "${pid}")" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "${spinstr}"
        local spinstr=${temp}${spinstr%"${temp}"}
        sleep ${delay}
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should NOT be run as root. Use sudo only where prompted."
        exit 1
    fi
}

create_backup_dir() {
    mkdir -p "${BACKUP_DIR}"
    log "Backup directory created: ${BACKUP_DIR}"
}

backup_existing_config() {
    local tool_name="$1"
    local config_path="$2"
    
    if [[ -e "${config_path}" ]]; then
        local backup_path="${BACKUP_DIR}/${tool_name}_$(basename ${config_path})_${TIMESTAMP}"
        cp -r "${config_path}" "${backup_path}"
        log "Backed up ${tool_name} config: ${config_path} -> ${backup_path}"
    else
        info "No existing config found for ${tool_name}: ${config_path}"
    fi
}

detect_system_info() {
    log "=== Detecting System Information ==="
    
    # Fedora version
    FEDORA_VERSION=$(rpm -E '%{fedora}' 2>/dev/null || echo "unknown")
    log "Fedora Version: ${FEDORA_VERSION}"
    
    # Architecture
    SYSTEM_ARCH=$(uname -m)
    log "System Architecture: ${SYSTEM_ARCH}"
    
    # CPU detection
    if [[ -f /proc/cpuinfo ]]; then
        CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
        CPU_MODEL=$(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)
        log "CPU Cores: ${CPU_CORES} (${CPU_MODEL})"
    fi
    
    # RAM detection
    if command -v free &>/dev/null; then
        TOTAL_RAM_GB=$(free -g | awk '/^Mem:/ {print $2}')
        log "Total RAM: ${TOTAL_RAM_GB} GB"
        
        # RAM optimization flag
        if [[ ${TOTAL_RAM_GB} -lt 8 ]]; then
            warn "Low RAM detected (${TOTAL_RAM_GB} GB). Enabling memory-safe optimizations."
            MEMORY_OPTIMIZED=true
        elif [[ ${TOTAL_RAM_GB} -gt 16 ]]; then
            log "High RAM detected (${TOTAL_RAM_GB} GB). Will enable parallel processing features."
            MEMORY_OPTIMIZED=false
        else
            MEMORY_OPTIMIZED=false
        fi
    fi
    
    # GPU detection
    if command -v lspci &>/dev/null; then
        GPU_INFO=$(lspci | grep -i vga | head -1 | cut -d':' -f3 | xargs)
        log "GPU: ${GPU_INFO}"
        
        # Check for NVIDIA (may need additional drivers)
        if echo "${GPU_INFO}" | grep -qi nvidia; then
            warn "NVIDIA GPU detected. Ensure proprietary drivers are installed for best Python ML performance."
        fi
    fi
    
    # JetBrains Toolbox detection
    if [[ -x "/opt/jetbrains-toolbox/bin/jetbrains-toolbox" ]]; then
        HAS_JETBRAINS_TOOLBOX="true"
        PYCHARM_CONFIG="${HOME}/.config/JetBrains/PyCharm*"
        log "JetBrains Toolbox detected"
    else
        HAS_JETBRAINS_TOOLBOX="false"
        log "JetBrains Toolbox not found. PyCharm setup will be skipped or require manual installation."
    fi
    
    # Check existing Python installations
    log "=== Checking Existing Python Installations ==="
    
    SYSTEM_PYTHON=$(which python3 2>/dev/null || echo "not found")
    log "System Python: ${SYSTEM_PYTHON}"
    if [[ "${SYSTEM_PYTHON}" != "not found" ]]; then
        SYSTEM_PYTHON_VER=$(python3 --version 2>/dev/null || echo "unknown")
        log "System Python Version: ${SYSTEM_PYTHON_VER}"
    fi
    
    # Check for uv, poetry, pipx
    for cmd in uv poetry pipx; do
        if command -v ${cmd} &>/dev/null; then
            log "WARNING: ${cmd} is already installed at $(which ${cmd}). Script will skip reinstalling."
        fi
    done
    
    # Check IDEs
    for ide in vscodium code pycharm; do
        if command -v ${ide} &>/dev/null; then
            log "IDE found: ${ide} at $(which ${ide})"
        fi
    done
    
    # Check Neovim
    if command -v nvim &>/dev/null; then
        NVIM_VER=$(nvim --version | head -1)
        log "Neovim: ${NVIM_VER}"
    else
        warn "Neovim not found in PATH. LazyVim setup will be skipped."
    fi
    
    # Validate required paths exist
    mkdir -p "${CODE_ROOT}"
    mkdir -p "${BACKUP_ROOT}"
    
    log "Code root: ${CODE_ROOT}"
    log "Backup root: ${BACKUP_ROOT}"
}

verify_prerequisites() {
    log "=== Verifying Prerequisites ==="
    
    local missing_tools=()
    
    # Essential build tools (needed for some Python packages)
    for pkg in gcc gcc-c++ make cmake git curl wget tar gzip; do
        if ! rpm -q "${pkg}" &>/dev/null; then
            missing_tools+=("${pkg}")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        warn "Missing build tools: ${missing_tools[*]}"
        read -p "Would you like to install missing build tools now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Installing build tools..."
            sudo dnf groupinstall -y "Development Tools"
            sudo dnf install -y "${missing_tools[@]}"
        else
            warn "Proceeding without build tools. Some Python package installations may fail."
        fi
    fi
    
    # Check for essential CLI tools
    for tool in jq rsync; do
        if ! rpm -q "${tool}" &>/dev/null; then
            log "Installing ${tool}..."
            sudo dnf install -y "${tool}"
        fi
    done
}

configure_zsh_environment() {
    log "=== Configuring ZSH Environment ==="
    
    # Backup existing .zshrc
    backup_existing_config "zsh" "${HOME}/.zshrc"
    
    # Create backup dir for zsh config fragments
    local ZSH_BACKUP="${BACKUP_DIR}/zsh_configs"
    mkdir -p "${ZSH_BACKUP}"
    
    # Add Python environment exports to .zshrc
    cat >> "${HOME}/.zshrc" << 'EOF'

# ---------------------------------------------------------------------------
# Python Development Environment (managed by python_setup scripts)
# Do not edit manually - changes may be overwritten during updates
# ---------------------------------------------------------------------------

# Enable direnv for automatic environment activation
if [[ -e "$(command -v direnv 2>/dev/null)" ]]; then
    eval "$(direnv hook zsh)"
fi

# Add uv to PATH (installed in ~/.local/bin by default)
export PATH="${HOME}/.local/bin:${PATH}"

# Project root shortcut
alias cdcode="cd ${CODE_ROOT:-$HOME/nb/CodeProjects}"

# Python virtual environment quick activation
alias actvenv=". .venv/bin/activate"

# Show active Python environment in prompt (requires powerlevel10k or similar)
precmd_functions+=(python_env_prompt)
python_env_prompt() {
    if [[ -f .venv/bin/activate ]]; then
        PROMPT="(venv) ${PROMPT}"
    fi
}

# Disable Python bytecode cache for cleaner repos
export PYTHONDONTWRITEBYTECODE=1

# Don't use __pycache__ for imports (optional, may cause issues)
# export PYTHONNOUSERSITE=1

# Set locale for consistent encoding
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# ---------------------------------------------------------------------------
EOF
    
    # Create zsh completion for Python tools
    mkdir -p "${HOME}/.oh-my-zsh/custom/plugins/python-dev"
    
    cat > "${HOME}/.oh-my-zsh/custom/plugins/python-dev/python-dev.plugin.zsh" << 'EOF'
# Python Development Plugin for Oh My Zsh
# Provides completions and aliases for common Python tooling

# Completions for uv
if (( $+commands[uv] )); then
    compdef _uv uv
fi

# Completions for ruff
if (( $+commands[ruff] )); then
    compdef _ruff ruff
fi

# Completions for pyright
if (( $+commands[pyright] )); then
    compdef _pyright pyright
fi

# Alias for creating new Python project with template
alias newpyproject="cd ${CODE_ROOT:-$HOME/nb/CodeProjects} && mkdir -p \$1 && cd \$1 && cp -r ${SCRIPT_REPO_PATH:-$HOME/nb/SystemSetupRepos/python-env-setup/templates/project}/* ."

# Function to quickly audit Python environments
function pyaudit() {
    if [[ -f .venv/bin/pip ]]; then
        .venv/bin/pip-audit
    else
        echo "No virtual environment found. Run 'uv sync' or 'pip install -r requirements.txt' first."
    fi
}

autoload -U +X compinit && compinit
autoload -U +U bashcompinit && bashcompinit
EOF
    
    # Update .zshrc to load the plugin
    if ! grep -q "plugins=(.*python-dev" "${HOME}/.zshrc"; then
        sed -i 's/plugins=(\(.*\))/plugins=(\1 python-dev)/' "${HOME}/.zshrc"
    fi
    
    log "ZSH environment configured"
    info "Please reload your shell: exec zsh"
}

setup_direnv() {
    log "=== Setting up direnv ==="
    
    # Install direnv if not present
    if ! command -v direnv &>/dev/null; then
        log "Installing direnv via dnf..."
        sudo dnf install -y direnv
    else
        info "direnv already installed at $(which direnv)"
    fi
    
    # Backup existing .envrc files in home
    backup_existing_config "direnv" "${HOME}/.envrc"
    
    # Create global direnv stdlib (optional convenience functions)
    local DIRENV_LIB_DIR="${HOME}/.config/direnv/lib"
    mkdir -p "${DIRENV_LIB_DIR}"
    
    cat > "${DIRENV_LIB_DIR}/python-utils.sh" << 'EOF'
# direnv library for Python project automation
# Source: https://direnv.net/lib/

# Use uv as Python environment manager
use uv() {
    local python_version=${1:-""}
    local venv_path="./.venv"
    
    if [[ -z "${python_version}" ]]; then
        log "Using latest stable Python (managed by uv)"
    else
        log "Creating Python ${python_version} environment"
    fi
    
    # Create venv with uv if not exists
    if [[ ! -d "${venv_path}" ]]; then
        log "Creating uv-managed virtual environment..."
        uv venv "${venv_path}" ${python_version:+--python ${python_version}}
    fi
    
    # Activate the environment
    source "${venv_path}/bin/activate"
    
    # Export PATH to prioritize venv binaries
    export PATH="$(pwd)/.venv/bin:${PATH}"
}

# Legacy support for projects using poetry
use poetry() {
    if command -v poetry &>/dev/null; then
        log "Switching to poetry environment..."
        poetry env use python
        poetry install
        export VIRTUAL_ENV="$(poetry env info --path)"
        export PATH="${VIRTUAL_ENV}/bin:${PATH}"
    else
        log_error "poetry not found. Install with: uv tool install poetry"
    fi
}

# Standard Python venv activation
use python() {
    local python_version=${1:-python3}
    local venv_path="${1:-./.venv}"
    
    if [[ ! -d "${venv_path}" ]]; then
        log "Creating standard venv with ${python_version}..."
        python3 -m venv "${venv_path}"
    fi
    
    source "${venv_path}/bin/activate"
    export PATH="$(pwd)/.venv/bin:${PATH}"
}
EOF
    
    # Configure direnv to allow standard locations
    cat >> "${HOME}/.config/direnv/direnv.toml" << EOF
# direnv configuration
[whitelist]
prefix = ["${CODE_ROOT}", "${HOME}/.local"]

# Allow Python environment loading
[load_dotenv]
allow = true
EOF
    
    log "direnv configured with Python utilities"
    info "direnv requires 'direnv allow' on each new project's .envrc"
}

log "==============================================================================="
log "PYTHON SETUP PHASE 1 - Starting Foundation Installation"
log "==============================================================================="

# Main execution
main() {
    check_root
    create_backup_dir
    detect_system_info
    verify_prerequisites
    
    # Phase 1 sub-scripts will be called here
    # Structure: Each major component gets its own script for modularity
    
    log ""
    log "=== Executing Phase 1 Sub-modules ==="
    
    # Source helper scripts (they should be in same directory)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 1. Setup uv
    if [[ -f "${SCRIPT_DIR}/python_setup_uv.sh" ]]; then
        log "Executing uv setup..."
        source "${SCRIPT_DIR}/python_setup_uv.sh"
    else
        log_error "Missing python_setup_uv.sh script. Cannot continue."
        exit 1
    fi
    
    # 2. Setup linters and type checkers
    if [[ -f "${SCRIPT_DIR}/python_setup_linters.sh" ]]; then
        log "Executing linters setup..."
        source "${SCRIPT_DIR}/python_setup_linters.sh"
    else
        log_error "Missing python_setup_linters.sh script. Cannot continue."
        exit 1
    fi
    
    # 3. Setup direnv
    setup_direnv
    
    # 4. Configure ZSH environment
    configure_zsh_environment
    
    log ""
    log "==============================================================================="
    log "PHASE 1 COMPLETE"
    log "==============================================================================="
    log ""
    log "Installed:"
    log "  ✓ uv (Python package/environment manager)"
    log "  ✓ Ruff (linting/formatting)"
    log "  ✓ Basedpyright/Pyright (type checking)"
    log "  ✓ mypy, ty (additional type checkers)"
    log "  ✓ Pre-commit (git hooks framework)"
    log "  ✓ direnv (environment auto-loading)"
    log ""
    log "Next Steps:"
    log "  1. Reload your shell: exec zsh"
    log "  2. Verify: uv --version && ruff --version"
    log "  3. Run Phase 2 (IDE configuration) when ready"
    log "  4. Run Phase 3 (project templates & validation)"
    log ""
    log "Backup location: ${BACKUP_DIR}"
    log "Log file: ${LOG_FILE}"
}

# Only run main if this script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi