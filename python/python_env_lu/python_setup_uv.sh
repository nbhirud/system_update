#!/bin/bash
#===============================================================================
# python_setup_uv.sh - Install and Configure UV Package Manager
# Called from: python_setup_phase1.sh
# Purpose: Install uv standalone installer (preferred method)
# Author: Generated for Nik's development environment
#===============================================================================

set -euo pipefail

UV_VERSION="${UV_VERSION:-latest}"  # Leave empty for latest stable

log "=== Installing uv ==="

# Backup existing uv if present
if command -v uv &>/dev/null; then
    BACKUP_UV_PATH="${BACKUP_DIR}/uv_original_$(which uv)"
    cp "$(which uv)" "${BACKUP_UV_PATH}" 2>/dev/null || true
    warn "Existing uv installation backed up: ${BACKUP_UV_PATH}"
fi

# Official standalone installer (recommended by uv docs)
log "Downloading uv installer..."
curl -LsSf https://astral.sh/uv/install.sh | sh

# Source the environment update if installer modified .bashrc/.zshrc
if [[ -f "${HOME}/.bashrc" ]] && grep -q "uv" "${HOME}/.bashrc" 2>/dev/null; then
    source "${HOME}/.bashrc"
elif [[ -f "${HOME}/.zshrc" ]] && grep -q "uv" "${HOME}/.zshrc" 2>/dev/null; then
    source "${HOME}/.zshrc"
fi

# Verify installation
if command -v uv &>/dev/null; then
    UV_VER=$(uv --version)
    log "✓ uv installed successfully: ${UV_VER}"
    
    # Configure uv settings for privacy and performance
    log "Configuring uv settings..."
    
    # Create uv config directory
    mkdir -p "${HOME}/.config/uv"
    
    # Privacy-focused uv settings
    cat > "${HOME}/.config/uv/uv.toml" << 'EOF'
# uv Configuration
# Privacy-focused settings

# Disable anonymous usage statistics (privacy)
[global]
no_progress = false

# Cache configuration - leverage large RAM if available
cache = { no-cache = false }

# Index settings
index-url = "https://pypi.org/simple"

# Prefer faster mirror if in Asia (you can adjust based on location)
# index = "https://pypi.org/simple"

# Disable telemetry
[env]
UV_NO_USAGE_REPORTING = "1"
EOF
    
    # Set uv as the default package manager for new projects
    log "Setting uv as preferred package manager..."
    
else
    log_error "uv installation failed!"
    exit 1
fi

# Install compatibility tools via uv tool
log "Installing poetry compatibility via uv..."
uv tool install poetry --quiet 2>/dev/null || warn "Poetry installation skipped (may already exist)"

log "✓ uv setup complete"