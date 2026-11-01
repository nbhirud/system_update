#!/usr/bin/env bash
set -euo pipefail

echo "==> [Sub-script] Installing uv via official standalone installer..."
if command -v uv &>/dev/null; then
    echo "    -> uv is already installed. Updating to latest stable version..."
    uv self update || true
else
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

export PATH="$HOME/.local/bin:$PATH"

echo "==> [Sub-script] Configuring uv project environment defaults..."
mkdir -p "$HOME/.config/uv"
cat << 'EOF' > "$HOME/.config/uv/uv.toml"
# Global uv configuration defaults
compile-bytecode = true
preview = true
link-mode = "copy"
EOF

echo "    -> uv version: $(uv --version)"