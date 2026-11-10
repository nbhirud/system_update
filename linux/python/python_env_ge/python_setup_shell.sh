#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="$HOME/nb/nbscript_backups/python_phase1"
ZSHRC="$HOME/.zshrc"

if [ -f "$ZSHRC" ]; then
    cp "$ZSHRC" "$BACKUP_DIR/zshrc.bak.$(date +%Y%m%d_%H%M%S)"
fi

echo "==> [Sub-script] Configuring Zsh shell, direnv hooks, and global privacy/telemetry environment variables..."

if ! grep -q "# === PRIVACY & TELEMETRY HARDENING ===" "$ZSHRC"; then
    cat << 'EOF' >> "$ZSHRC"

# === PRIVACY & TELEMETRY HARDENING ===
export DO_NOT_TRACK=1
export UV_NO_PROGRESS=0
export RUFF_NO_PROGRESS=1
export TY_NO_PROGRESS=1
export SCARF_ANALYTICS=false
export HUGGINGFACE_HUB_DISABLE_TELEMETRY=1
export PIP_DISABLE_PIP_VERSION_CHECK=1

# === SHELL INTEGRATIONS ===
export PATH="$HOME/.local/bin:$PATH"

if command -v direnv &>/dev/null; then
    eval "$(direnv hook zsh)"
fi
EOF
else
    echo "    -> Telemetry & shell blocks already present in .zshrc."
fi