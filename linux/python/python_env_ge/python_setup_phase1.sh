#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script Name: python_setup_phase1.sh
# Description: Orchestrates Phase 1 of Python developer environment setup on Fedora 44
# ==============================================================================

BACKUP_DIR="$HOME/nb/nbscript_backups/python_phase1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$BACKUP_DIR" "$HOME/nb/CodeProjects"

echo "==> [Phase 1] Analyzing system hardware capability..."
TOTAL_RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
CPU_CORES=$(nproc)
echo "    -> Detected CPU Cores: $CPU_CORES"
echo "    -> Detected Total RAM: ${TOTAL_RAM_MB}MB"

# Export hardware profiles for sub-scripts
export CPU_CORES
export TOTAL_RAM_MB

echo "==> [Phase 1] Executing modular sub-scripts..."
bash "$SCRIPT_DIR/python_setup_uv.sh"
bash "$SCRIPT_DIR/python_setup_tools.sh"
bash "$SCRIPT_DIR/python_setup_shell.sh"

echo "==> [Phase 1] Complete! System foundation and global CLI toolchain installed."

