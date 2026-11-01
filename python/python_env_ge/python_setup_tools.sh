#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

echo "==> [Sub-script] Installing global Python developer tools (uv tool install)..."
if [ "$TOTAL_RAM_MB" -gt 16000 ]; then
    JOBS=$((CPU_CORES > 4 ? 4 : CPU_CORES))
else
    JOBS=2
fi
echo "    -> Using concurrency limit: $JOBS workers"

# Install ruff, ty (Astral type checker), mypy, pyright, pre-commit, pip-audit
uv tool install --force ruff
uv tool install --force ty
uv tool install --force mypy
uv tool install --force pyright
uv tool install --force pre-commit
uv tool install --force pip-audit

if ! command -v direnv &>/dev/null; then
    echo "    -> Installing direnv via Fedora DNF package manager..."
    sudo dnf install -y direnv
fi

echo "    -> Global CLI tools successfully provisioned."