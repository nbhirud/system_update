#!/bin/bash
# ==============================================================================
# VSCodium Pro Setup for Fedora KDE (Git/Python/Rust/Shell Focus)
# Target: Nik's Environment (Fedora, Wayland, Ruff/UV, JetBrains Nerd Font)
# ==============================================================================

set -euo pipefail

# --- Configuration ---
# Optional: Set your NextDNS ID here if you want to script firewall rules later
# export NEXTDNS_ID="your-nextdns-id" 

HOME_DIR=$(getent passwd $USER | cut -d: -f6)
NBDIR="$HOME_DIR/nb"
CODEPROJECTS_DIR="$NBDIR/CodeProjects"
# VSCODIUM_USER_DIR="$HOME/.config/VSCodium"
VSCODIUM_USER_DIR="$HOME_DIR/.config/VSCodium"
USER_CONFIG_DIR="$VSCODIUM_USER_DIR/User"
SETTINGS_FILE="$USER_CONFIG_DIR/settings.json"
KEYBINDINGS_FILE="$USER_CONFIG_DIR/keybindings.json"
SNIPPETS_DIR="$USER_CONFIG_DIR/snippets"
PRE_COMMIT_YAML_ALL="$CODEPROJECTS_DIR/.pre-commit-config_all_purpose.yaml"
PRE_COMMIT_YAML_PY="$CODEPROJECTS_DIR/.pre-commit-config_python.yaml"
PYPROJECT_TOML="$CODEPROJECTS_DIR/pyproject.toml"
GIT_TEMPLATE_DIR_ALL="$CODEPROJECTS_DIR/.nb_all_purpose_template"
GIT_TEMPLATE_DIR_PY="$CODEPROJECTS_DIR/.nb_py_uv_basic_template"

# Create Directories
mkdir -p "$USER_CONFIG_DIR" "$SNIPPETS_DIR" "$CODEPROJECTS_DIR"

###############################################################################
# Extensions list
###############################################################################

# Extensions tailored for Git, Python (Ruff/UV), Rust, Markdown
EXTENSIONS=(
    ## Python
    "ms-python.python"              # Core Python
    "ms-python.vscode-pylance"      # Python Intellisense
    "ms-python.debugpy"             # Python Debugger
    "charliermarsh.ruff"            # Ruff Linter/Formatter
    "detachhead.basedpyright"       # python languageServer - open-source alternative to Pylance
    "the0807.uv-toolkit"
    # "ms-python.black-formatter"     # Black (fallback if needed, though Ruff is preferred)
    
    # Rust
    "rust-lang.rust-analyzer"       # Rust Core


    # TOML
    "tamasfe.even-better-toml"      # TOML support (for pyproject.toml, Cargo.toml)

    # Git
    "eamodio.gitlens"               # Git Superpowers
    "mhutchie.git-graph"
    "github.vscode-github-actions"

    # Shell
    "mkhl.shfmt"
    "timonwong.shellcheck"
    "foxundermoon.shell-format"

    # Markdown
    "bierner.markdown-mermaid"      # Diagrams in Markdown
    "davidanson.vscode-markdownlint"  # Markdown Linting
    "yzhang.markdown-all-in-one"    # Markdown
    "esbenp.prettier-vscode"        # Generic Formatter

    # Quality of life
    usernamehw.errorlens
    gruntfuggly.todo-tree
    fill-labs.dependi

    # LSP
    jnoortheen.nix-ide

    # Misc
    "ms-vscode-remote.remote-ssh"   # Remote SSH
    "oderwat.indent-rainbow"        # Visual aid for indentation
    "redhat.vscode-yaml"            # YAML support
    "ms-azuretools.vscode-docker"   # Docker integration
    "editorconfig.editorconfig"

    # String Manipulation and tools
    "marclipovsky.string-manipulation"
    "qcz.text-power-tools"
    "carlocardella.vscode-texttoolbox"
    
)



###############################################################################
# HELPERS
###############################################################################


# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

log_header() {
    echo
    echo "================================================================"
    echo "$1"
    echo "================================================================"
}


require_root() { 
    if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run with sudo privileges."
    log_warn "Run as root: sudo $0" 
    exit 1
    fi
}


REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(eval echo "~$REAL_USER")"

run_user() {
    sudo -u "$REAL_USER" bash -c "$1"
}



###############################################################################
# ROOT CHECK
###############################################################################

require_root


###############################################################################
# DEVELOPMENT PACKAGES
###############################################################################

log_header "Installing development tooling"

sudo dnf install -y \
    git \
    git-lfs \
    gh \
    glab \
    jq \
    curl \
    wget \
    fd-find \
    ripgrep \
    fzf \
    bat \
    ShellCheck \
    shfmt \
    npm \
    gcc \
    make \
    cmake \
    python3 \
    python3-pip \
    python3-devel \
    python3-virtualenv \
    rustup \
    cargo \
    openssl-devel 

# dnf install -y \
        # gcc-c++ \
        # wl-clipboard \
    # xclip \
        # nodejs \
        # eza \
    # zoxide \
#     jq \ 
#     kde-cli-tools \ 
#     plasma-integration
#     plasma-workspace \ 
#     tar \ 
#     unzip \ 
#     zip 

###############################################################################
# UV + PYTHON TOOLING
###############################################################################

log_header "Installing uv + Python tooling"

curl -LsSf https://astral.sh/uv/install.sh | sh
uv self update

uv tool install pre-commit
uv tool install ruff
uv tool install basedpyright
uv tool upgrade --all

# run_user "
#     ~/.local/bin/uv tool install ruff
#     ~/.local/bin/uv tool install basedpyright
# "

# run_as_user " 
#     python3 -m pip install --user --upgrade pip 

#     python3 -m pip install --user \ 
#         ruff \ 
#         black \ 
#         isort \ 
#         mypy \ 
#         pytest \ 
#         ipython \ 
#         pynvim \ 
#         basedpyright 
# "

###############################################################################
# RUST TOOLCHAIN
###############################################################################

log_header "Configuring Rust"

run_user "
    rustup default stable
    rustup component add rustfmt clippy rust-src
"

###############################################################################
# MARKDOWN TOOLING
###############################################################################

log_header "Installing markdown tooling"

npm install -g \
    markdownlint-cli \
    prettier


###############################################################################
# 
###############################################################################


# Detect RAM
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
log_info "Detected RAM: ${TOTAL_RAM_GB}GB"

# Detect GPU for Wayland/Ozone tuning
GPU_INFO=$(lspci | grep -i vga)
HAS_NVIDIA=false
if echo "$GPU_INFO" | grep -qi "nvidia"; then
    HAS_NVIDIA=true
    log_info "NVIDIA GPU detected. Enabling specific acceleration flags."
elif echo "$GPU_INFO" | grep -qi "intel"; then
    log_info "Intel GPU detected. Using standard hardware acceleration."
fi


###############################################################################
# 
###############################################################################
log_header "Adding repository and installing VSCodium"

# --- Step 1: Install Official Repository ---
log_info "Cleaning up old third-party repo..."
sudo rm -f /etc/yum.repos.d/vscodium.repo

log_info "Adding official VSCodium repository..."
# Official repo is more reliable than the GitLab mirror
# sudo rpm --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg
sudo rpm --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
# sudo rpm --import https://download.vscodium.com/public.key

sudo tee /etc/yum.repos.d/vscodium.repo <<'EOF'
[gitlab.com_paulcarroty_vscodium_repo]
name=gitlab.com_paulcarroty_vscodium_repo
baseurl=https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/rpms/
# baseurl=https://download.vscodium.com/rpms/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
# gpgkey=https://download.vscodium.com/public.key
metadata_expire=1h
EOF

log_info "Installing VSCodium..."
sudo dnf install -y codium

###############################################################################
# Wayland / GPU/ electron / etc stuff
###############################################################################

# HARDWARE ACCELERATION & WAYLAND TUNING
# Tuning flags for Wayland and GPU acceleration

mkdir -p "$HOME/.config"
FLAGS_FILE="$HOME/.config/codium-flags.conf"

# Base Wayland & Electron optimization flags
cat << 'EOF' > "$FLAGS_FILE"
--enable-features=UseOzonePlatform
--ozone-platform=wayland
--enable-features=WaylandWindowDecorations
--disable-rendering-loop
EOF

# Detect GPU and append hardware acceleration optimization
if lspci | grep -qi 'nvidia'; then
    echo "[-] Nvidia GPU detected. Adding hardware acceleration flags..."
    cat << 'EOF' >> "$FLAGS_FILE"
--enable-vulkan
--enable-gpu-rasterization
--enable-zero-copy
EOF
else
    echo "[-] Intel/Integrated GPU detected. Optimizing for power/performance..."
    cat << 'EOF' >> "$FLAGS_FILE"
--enable-gpu-rasterization
--enable-zero-copy
EOF
fi

#########################

log "Configuring native Wayland support"

mkdir -p /etc/profile.d

cat >/etc/profile.d/codium-wayland.sh <<'EOF'
export ELECTRON_OZONE_PLATFORM_HINT=auto
EOF

mkdir -p /usr/local/share/applications
# mkdir -p /usr/share/applications

sed \
    's|^Exec=/usr/share/codium/codium %F|Exec=/usr/share/codium/codium --enable-features=UseOzonePlatform --ozone-platform=wayland %F|' \
    /usr/share/applications/codium.desktop \
    >/usr/local/share/applications/codium.desktop

log "Configuring shell environment"
cat >/etc/profile.d/editor.sh <<'EOF'
export EDITOR=codium
export VISUAL=codium
EOF

#########################
# --- Step 5: Hardware Optimization (Wayland/GPU) ---
log_info "Applying hardware optimizations..."

# # Create a desktop override for Wayland/GPU flags if not already present
# DESKTOP_OVERRIDE_DIR="$HOME/.local/share/flatpak/overrides" # Not used for RPM, but good practice
# # For RPM installed apps, we modify the .desktop file directly or use a wrapper
# # Since VSCodium is RPM, we create a local override in ~/.local/share/applications


# Create a local override for the .desktop file to inject GPU flags
LOCAL_DESKTOP_FILE="$HOME/.local/share/applications/codium.desktop"
sudo cp /usr/share/applications/codium.desktop "$LOCAL_DESKTOP_FILE"

# Inject GPU flags into the Exec line
if [ "$HAS_NVIDIA" = true ]; then
    # NVIDIA on Wayland needs specific flags to avoid flickering/black screens
    sed -i 's|^Exec=codium %F|Exec=codium --enable-features=UseOzonePlatform --ozone-platform=wayland --ignore-gpu-blocklist %F|' "$LOCAL_DESKTOP_FILE"
    log_info "Applied NVIDIA Wayland flags."
else
    # Intel/AMD standard Wayland flags
    sed -i 's|^Exec=codium %F|Exec=codium --enable-features=UseOzonePlatform --ozone-platform=wayland %F|' "$LOCAL_DESKTOP_FILE"
    log_info "Applied Intel/AMD Wayland flags."
fi



###############################################################################
# KEYBINDINGS
###############################################################################

log_header "Generating keybindings"
# Create keybindings.json (Optional: Add your favorite shortcuts)
cat > "$KEYBINDINGS_FILE" <<EOF
[
    {
        "key": "ctrl+shift+p",
        "command": "workbench.action.quickOpen"
    },
    {
        "key": "ctrl+shift+f",
        "command": "workbench.action.findInFiles"
    },
    {
        "key": "ctrl+\`",
        "command": "workbench.action.terminal.toggleTerminal"
    },
    {
        "key": "ctrl+shift+t",
        "command": "workbench.action.terminal.toggleTerminal"
    }
]
EOF

# "key": "ctrl+`",


###############################################################################
# GIT CONFIG
###############################################################################

log_header "Applying Git defaults"

run_user "
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    git config --global fetch.prune true
    git config --global core.editor codium
    git config --global core.pager 'bat --paging=always'
"


###############################################################################
# Install EXTENSIONS
###############################################################################

log_header "Installing VSCodium extensions"

for ext in "${EXTENSIONS[@]}"; do
    log_info "Installing $ext..."
    codium --install-extension "$ext" --force
    # run_user "codium --install-extension $ext || true"
done




###############################################################################
# USER SETTINGS
###############################################################################

log_header "Generating optimized settings.json"
# log_info "Configuring Privacy, Performance, and Stack-Specific Settings..."

mkdir -p "$REAL_HOME/.config/VSCodium/User"

# Create settings.json
# Note: We configure Ruff as the primary formatter/linter for Python
# cat << 'EOF' > "$SETTINGS_FILE"
cat > "$SETTINGS_FILE" <<EOF
{
    // --- Core & UI ---
    // "workbench.colorTheme": "Default Dark Modern", 
    "workbench.colorTheme": "Default Dark+",
    "workbench.iconTheme": "vscode-icons",

    "editor.fontFamily": "'JetBrains Mono Nerd Font', 'Noto Sans Mono', 'Droid Sans Mono', monospace",
    "editor.fontLigatures": true,
    "editor.fontSize": 14,
    "editor.lineHeight": 1.55,
    "editor.tabSize": 4,
    "editor.insertSpaces": true,
    "editor.detectIndentation": true,
    "editor.renderWhitespace": "selection",
    "editor.smoothScrolling": true,
    "editor.cursorSmoothCaretAnimation": "on",
    "editor.trimAutoWhitespace": true,
    "editor.inlineSuggest.enabled": true, 

    "workbench.editor.enablePreview": false,
    "workbench.activityBar.visible": true,
    // "workbench.activityBar.location": "hidden",
    "workbench.statusBar.visible": true,
    "workbench.list.smoothScrolling": true,
    "workbench.tree.indent": 18,
    "workbench.tree.renderIndentGuides": "always",
    "workbench.tree.expandMode": "singleClick",
    "workbench.statusBar.visible": true,
    "workbench.panel.opensMaximized": "never",
    "workbench.sideBar.location": "left",
    "workbench.startupEditor": "none",
    "workbench.preferredDarkColorTheme": "Default Dark+",
    "workbench.preferredLightColorTheme": "Default Light+",
    "workbench.preferredHighContrastColorTheme": "Default High Contrast",
    "workbench.preferredHighContrastLightColorTheme": "Default High Contrast Light",
    "window.titleBarStyle": "custom",  // Better integration with KDE Plasma Wayland
    "window.restoreWindows": "preserve",
    // "window.restoreWindows": "one",
    "window.restoreFullscreen": true,
    "window.newWindowDimensions": "inherit",
    "window.openFoldersInNewWindow": "on",
    "window.openWithoutArgumentsInNewWindow": "on",
    "window.menuBarVisibility": "classic",
    "window.zoomLevel": 0,
    "window.commandCenter": false,
    
    // --- Privacy & Security ---
    "telemetry.telemetryLevel": "off",
    "workbench.enableExperiments": false,
    "workbench.settings.enableNaturalLanguageSearch": false,
    "update.mode": "none",  // Handled globally by dnf
    // "update.mode": "manual",
    "security.workspace.trust.enabled": true,
    "extensions.ignoreRecommendations": false,
    "extensions.autoCheckUpdates": true,
    "extensions.autoUpdate": true, // false is more secure, but updates are important
    
    // --- Python (Ruff & UV) ---
    // "python.defaultInterpreterPath": "/usr/bin/python3",
    "python.defaultInterpreterPath": "uv",
    "python-envs.alwaysUseUv": true, // Let VS Code Python Environments extension use uv automatically
    // "python.envFile": "${workspaceFolder}/.env",
    "python.envFile": "${workspaceFolder}/.venv",
    "python.showEnvironmentSelector": true, // Optional: Show uv in status bar / explorer
    "python.terminal.activateEnvironment": true,
    "python.linting.enabled": true,
    "python.analysis.typeCheckingMode": "basic",
    "python.analysis.extraPaths": [],
    "python.analysis.diagnosticMode": "workspace",
    "python.analysis.ignore": [],
    "python.analysis.autoImportCompletions": true,
    "python.analysis.inlayHints.variableTypes": true,
    "python.analysis.inlayHints.functionReturnTypes": true,
    "python.analysis.inlayHints.callArgumentNames": "partial",
    "[python]": {
        "editor.defaultFormatter": "charliermarsh.ruff",
        "editor.formatOnSave": true,
        "editor.codeActionsOnSave": {
            "source.fixAll": "explicit",
            "source.organizeImports.ruff": "always",
            // "source.organizeImports.ruff": "explicit"
            "source.fixAll.ruff": "always"
        }
    },
    "python.linting.ruffEnabled": true,
    "python.formatting.provider": "ruff",
    "python.formatting.ruffPath": "ruff",
    "ruff.format.args": ["--config", "pyproject.toml"],
    "ruff.lint.args": [],
    // "ruff.nativeServer": "on",
    "ruff.nativeServer": true,
    // "python.languageServer": "Pylance",
    "basedpyright.analysis.typeCheckingMode": "basic",
    "basedpyright.analysis.diagnosticMode": "workspace",
    "python.languageServer": "basedpyright",
    "ruff.importStrategy": "fromEnvironment",
    "ruff.path": ["uv", "run", "ruff"], // Executes ruff via uv natively if available

    
    // --- Rust ---
    "rust-analyzer.checkOnSave.command": "clippy",
    "rust-analyzer.check.command": "clippy",
    "rust-analyzer.cargo.features": "all",
    "rust-analyzer.cargo.sysroot": "discover",
    "rust-analyzer.procMacro.enable": true,
    "[rust]": {
        "editor.defaultFormatter": "rust-lang.rust-analyzer",
        "editor.formatOnSave": true
    },
    
    // --- Git ---
    "git.enableSmartCommit": true,
    // "git.enableSmartCommit": false,
    "git.autofetch": true,
    // "git.autofetch": false // Disabled for privacy/network control
    "git.confirmSync": false,
    "git.openRepositoryInParentFolders": "always",

    "gitlens.hovers.currentLine.over": "line",
    "gitlens.currentLine.enabled": true,
    "gitlens.codeLens.enabled": true,
    "gitlens.plusFeatures.enabled": true,
    "gitlens.views.repositories.enabled": true,

    
    // --- Shell Scripting (Shellcheck + Shfmt) ---
    "[shellscript]": {
        // "editor.defaultFormatter": "foxundermoon.shell-format",
        "editor.defaultFormatter": "mkhl.shfmt",
        "editor.formatOnSave": true
    },

    // --- Markdown ---
    "markdown.preview.doubleClickToSwitchToEditor": false,
    "markdown.extension.toc.levels": "1..6",
    "markdown.extension.toc.unorderedList.marker": "-",
    "[markdown]": {
        "editor.wordWrap": "on",
        "editor.defaultFormatter": "esbenp.prettier-vscode"
        // "editor.defaultFormatter": "yzhang.markdown-all-in-one",
        "editor.quickSuggestions": true,
        //"editor.quickSuggestions": {
        //    "comments": "off",
        //    "strings": "off",
        //    "other": "on"
        //},
    },

    "markdownlint.config": {
        "MD013": false
    },

    "files.associations": {
        "*.env": "shellscript",
        "*.service": "ini",
        "*.timer": "ini"
    }
}
    
    // --- Editor Behavior ---
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.codeActionsOnSave": {
        "source.fixAll": "explicit"
        "source.organizeImports": "explicit",
        "source.fixAll.eslint": "explicit",
        "source.fixAll.ruff": "explicit"
        
    },
    
    // "files.autoSave": "onFocusChange",
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "files.insertFinalNewline": true,
    "files.trimTrailingWhitespace": true,
    "files.eol": "\\n",
    "files.encoding": "utf8",
    "search.useIgnoreFiles": true,
    "search.useGlobalIgnoreFiles": true,
    "search.followSymlinks": false,
    "search.exclude": {
        "**/.git": true,
        "**/node_modules": true,
        "**/__pycache__": true,
        "**/.venv": true,
        "**/target": true
    },
    "files.watcherExclude": {
        "**/.git/**": true,
        "**/node_modules/**": true,
        "**/__pycache__/**": true,
        "**/.venv/**": true,
        "**/target/**": true
    },
    "files.exclude": {
        "**/.DS_Store": true, 
        "**/.git": true
    },
    "explorer.confirmDelete": false,
    "explorer.compactFolders": true,
    "breadcrumbs.enabled": true,
    "editor.minimap.enabled": true,
    "editor.scrollBeyondLastLine": false,
    "editor.scrollbar.vertical": "visible",
    "editor.cursorBlinking": "smooth",
    "editor.rulers": [80, 100, 120],
    "editor.renderControlCharacters": true,
    "editor.renderLineHighlight": "line",
    "editor.guides.bracketPairs": true,
    "editor.guides.bracketPairsHorizontal": "active",
    "editor.bracketPairColorization": true,
    "editor.guides.highlightActiveIndentation": true,
    "editor.guides.highlightActiveBracketPair": true,
    "editor.guides.indentation": true,
    "editor.folding": true,
    "editor.foldingStrategy": "indentation",
    "editor.showFoldingControls": "always",
    "editor.linkedEditing": true,
    "editor.suggestOnTriggerCharacters": true,
    "editor.quickSuggestions": {"other": true, "comments": false, "strings": false},
    "editor.quickSuggestionsDelay": 100,
    "editor.suggestSelection": "first",
    "editor.tabCompletion": "on",
    "editor.wordBasedSuggestions": "off",
    "editor.acceptSuggestionOnEnter": "smart",
    "editor.suggest.snippetsPreventQuickSuggestions": false,
    "editor.parameterHints.enabled": true,
    "editor.parameterHints.cycle": true,
    "editor.codeActionsOnSave": {"source.organizeImports": "explicit"},
    
    "diffEditor.ignoreTrimWhitespace": false,
    "diffEditor.renderSideBySide": true,
    "diffEditor.renderMarginRevertIcon": true,
    "diffEditor.codeLens": true,
    "diffEditor.experimental": {"moveAction": "preserve"},
    "diffEditor.insertAsText": true,
    "diffEditor.useInlineViewWhenSpaceIsLimited": false,
    "diffEditor.hideUnchangedRegions.enabled": false,
    "diffEditor.showUnchangedRegions": false,
    "diffEditor.renderOverviewRuler": true,
    "diffEditor.renderIndicators": true,
    "diffEditor.accessibilityPageSize": 10,
    "diffEditor.accessibilitySupport": "on",
    "diffEditor.diffAlgorithm": "advanced",
    "diffEditor.experimental.advanced": true

    // --- Terminal ---
    "terminal.integrated.shell.linux": "/bin/zsh",
    "terminal.integrated.defaultProfile.linux": "zsh",
    "terminal.integrated.gpuAcceleration": "on",
    "terminal.integrated.fontFamily": "'JetBrainsMono Nerd Font'",
    "terminal.integrated.fontSize": 14,

    "chat.commandCenter.enabled": false,
    "editor.wordWrap": "on"
}
EOF


###############################################################################
# 
###############################################################################

# Optional: Create useful snippets
cat > ~/.config/VSCodium/User/snippets/python.code-snippets <<'EOF'
{
    "Python main guard": {
        "prefix": "ifmain",
        "body": [
            "if __name__ == \"__main__\":",
            "    ${1:pass}"
        ],
        "description": "Python if __name__ == \"__main__\""
    }
}
EOF

###############################################################################
# OWNERSHIP FIX
###############################################################################

chown -R "$REAL_USER:$REAL_USER" \
    "$REAL_HOME/.config/VSCodium"

###############################################################################
# Pre-commit Integration Setup
###############################################################################

echo "=== Pre-commit Hooks Setup ==="

# Install pre-commit (via pipx or uv for isolation)
if ! command -v pre-commit &> /dev/null; then
    echo "Installing pre-commit..."
    # Prefer uv if available, else pipx
    if command -v uv &> /dev/null; then
        uv tool install pre-commit
    else
        python3 -m pip install --user pipx
        pipx install pre-commit
    fi
else
    echo "pre-commit already installed."
fi

###############################################################################
# Pre-commit sample file
###############################################################################


# Create a sample .pre-commit-config.yaml (you can customize per project) - All purpose
if [ ! -f "$PRE_COMMIT_YAML_ALL" ]; then
    cat > "$PRE_COMMIT_YAML_ALL <<'EOF'
# .pre-commit-config.yaml
# Best for: Git + Python (Ruff/uv) + Rust + Markdown + Shell

# Note: Rename this file to ".pre-commit-config.yaml" before use

# # Install hooks into your current Git repo
# pre-commit install --install-hooks
# pre-commit install --hook-type pre-push  # Optional: extra checks on push
# echo "Run manually: pre-commit run --all-files"
# echo "Update hooks: pre-commit autoupdate"

repos:
  # General Git hygiene
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-toml
      - id: check-added-large-files
        args: ['--maxkb=500']

  # Python - Ruff (recommended: one tool for lint + format)
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.11.0  # Update regularly with: pre-commit autoupdate
    hooks:
      - id: ruff
        args: [--fix, --exit-non-zero-on-fix]
      - id: ruff-format

  - repo: https://github.com/astral-sh/uv-pre-commit
    rev: 0.11.16
    hooks:
      - id: uv-lock

  # Rust
  - repo: https://github.com/rust-lang/rustfmt
    rev: "1.8.0"  # or use a specific tag
    hooks:
      - id: rustfmt

  # Shell
  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: v0.10.0.1
    hooks:
      - id: shellcheck

  - repo: https://github.com/pre-commit/mirrors-shfmt
    rev: v3.11.0
    hooks:
      - id: shfmt

  # Markdown
  - repo: https://github.com/markdownlint/markdownlint
    rev: v0.14.0
    hooks:
      - id: markdownlint
        args: [--fix]
  - repo: https://github.com/executablebooks/mdformat
    rev: 0.7.22
    hooks:
      - id: mdformat
        additional_dependencies:
          - mdformat-gfm
          - mdformat-frontmatter

  # Optional: detect secrets, codespell, etc.
  # - repo: https://github.com/Yelp/detect-secrets
  #   rev: v1.5.0
  #   hooks:
  #     - id: detect-secrets
EOF
    echo "Sample .pre-commit-config.yaml created here: $PRE_COMMIT_YAML_ALL"
fi


# Create project files - Python
cat > "$PYPROJECT_TOML" <<'EOT'
[project]
name = "my-project"
version = "0.1.0"
description = "Add your description"
requires-python = ">=3.12"
dependencies = []

[project.optional-dependencies]
dev = [
    "ruff",
    "pytest",
    "pytest-cov",
]

[tool.ruff]
line-length = 100
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "I", "B", "C4", "UP"]
fixable = ["ALL"]

[tool.ruff.format]
quote-style = "double"
EOT




# Pre-commit with uv integration - Python
cat > "$PRE_COMMIT_YAML_PY" <<'EOT'

# Note: Rename this file to ".pre-commit-config.yaml" before use

repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-toml

  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.11.0
    hooks:
      - id: ruff
        args: [--fix, --exit-non-zero-on-fix]
      - id: ruff-format

  - repo: https://github.com/astral-sh/uv-pre-commit
    rev: 0.11.16   # Keep updated
    hooks:
      - id: uv-lock
EOT




###############################################################################
# Git Template Directory + pre-commit init-templatedir
###############################################################################

##################################### template 2 (All Purpose)
# This automatically copies your .pre-commit-config.yaml (and even installs the hooks) into every new repository you create with git init or clone.

# 1. Create a Git template directory
mkdir -p "$GIT_TEMPLATE_DIR_ALL"
cd "$GIT_TEMPLATE_DIR_ALL"

# 2. Set it as your global template
git config --global init.templateDir "$GIT_TEMPLATE_DIR_ALL"

# 3. Copy your preferred .pre-commit-config.yaml into the template
cp "$PRE_COMMIT_YAML_ALL" "$GIT_TEMPLATE_DIR_ALL/.pre-commit-config.yaml"   # or wherever you saved it

# 4. Let pre-commit set up the hooks in the template
pre-commit init-templatedir "$GIT_TEMPLATE_DIR_ALL"

# Now, any new repository you create (git init) or clone will automatically:
# Have a .pre-commit-config.yaml in the root
# Have the pre-commit hooks installed (.git/hooks/pre-commit etc.)

# Additional Tips
# For existing repos: Go into each one and run pre-commit install (or git init again to pull the new template).
# Per-project customization: After cloning/creating a repo, you can edit .pre-commit-config.yaml freely. It won’t be overwritten.
# Update hooks globally: pre-commit autoupdate in the template dir, then re-run pre-commit init-templatedir.
# VSCodium Integration: The pre-commit VS Code extension will detect these automatically.


##################################### template 2 (Python)

# Project Template with uv (Recommended) - Create this as a starter for new Python projects:


# Run once to create a template
mkdir -p "$GIT_TEMPLATE_DIR_PY"
cd "$GIT_TEMPLATE_DIR_PY"

uv init --name "my-project" --python 3.12
uv add --dev ruff pytest pytest-cov pre-commit

cp "$PRE_COMMIT_YAML_PY" "$GIT_TEMPLATE_DIR_PY/.pre-commit-config.yaml" 
cp "$PYPROJECT_TOML" "$GIT_TEMPLATE_DIR_PY/pyproject.toml" 

pre-commit install

cd

###############################################################################
# Set VSCodium as default handler
###############################################################################


# Associate MIME types with the local override
# Setting VSCodium as default handler for text, markdown, and scripts

VSC_MIME="codium.desktop"
xdg-mime default "$VSC_MIME" text/plain
xdg-mime default "$VSC_MIME" inode/directory
xdg-mime default "$VSC_MIME" text/markdown
xdg-mime default "$VSC_MIME" text/x-python
xdg-mime default "$VSC_MIME" text/x-script.sh
xdg-mime default "$VSC_MIME" application/x-shellscript



# --- Step 6: Final Cleanup ---
log_info "Updating desktop database..."
update-desktop-database ~/.local/share/applications > /dev/null 2>&1 || true

log_info "------------------------------------------------"
log_info "Setup Complete!"
log_info "------------------------------------------------"
log_info "Features enabled:"
log_info "  - Python: Ruff (Lint/Format), Pylance, UV support"
log_info "  - Rust: Rust Analyzer with Clippy"
log_info "  - Git: GitLens, Smart Commit, Auto-fetch"
log_info "  - Markdown: All-in-One, Mermaid, Linting"
log_info "  - Hardware: Wayland + GPU acceleration tuned"
log_info "  - Privacy: Telemetry OFF, Auto-update OFF"
log_info ""
log_info "Launch VSCodium from your application menu."
log_info "Tip: Run 'codium --list-extensions' to verify."




############################################# 
# Multihost Git (GitHub, GitLab, Codeberg)

# To make authentication and management across three separate remote targets seamless, rely on your SSH configuration (~/.ssh/config) rather than managing extension-level OAuth logins inside VSCodium. Ensure your SSH configs match your hosts:
# Host - Recommended Authentication Configuration
# GitHub - Host github.com \n User git \n IdentityFile ~/.ssh/id_ed25519_github
# GitLab - Host gitlab.com \n User git \n IdentityFile ~/.ssh/id_ed25519_gitlab
# Codeberg - Host codeberg.org \n User git \n IdentityFile ~/.ssh/id_ed25519_codeberg
# VSCodium will automatically pick up your system's SSH keys via standard agents whenever you trigger Git operations natively.


############################################# chgp
# # I would also add these to global .gitignore eventually:
# ~/.cache
# .direnv
# .venv
# __pycache__
# *.pyc
# target
# node_modules

# Implement git ssh keys and gitconfig steps at the end

############################################# gr


# echo "=== Setup Complete! ==="
# echo "Launch with: codium"
# echo "Recommended next steps:"
# echo "  1. Install uv globally if not present: curl -LsSf https://astral.sh/uv/install.sh | sh"
# echo "  2. For Rust: rustup component add rust-analyzer clippy"
# echo "  3. Open a project and let rust-analyzer + Ruff download necessary tools."


########################################


#############################################################################
# Notes:
# 4. Daily Workflow with uv

# New project: uv init && uv sync
# Add package: uv add requests
# Add dev package: uv add --dev pytest
# Sync environment: uv sync
# Run script: uv run python script.py or just uv run script.py
# Lock dependencies: uv lock
# Update everything: uv lock --upgrade

# 5. Pre-commit + uv Synergy
# The uv-pre-commit hook keeps uv.lock consistent. The updated .pre-commit-config.yaml above includes it.

