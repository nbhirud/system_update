#!/usr/bin/env bash
# =============================================================================
# python_setup_phase1.sh
# =============================================================================
# Phase 1 — System-level Python foundation for Fedora 44 (KDE)
#
# What this does:
#   1. Inventory current state (read-only checks)
#   2. Detect hardware and tune concurrency
#   3. Install uv via official standalone installer
#   4. Install managed Python interpreters (3.12 / 3.13 / 3.14)
#   5. Install global tools (ruff, pre-commit, basedpyright, mypy, ty, pip-audit)
#   6. Install direnv via dnf
#   7. Configure zsh + Oh My Zsh (PATH, direnv hook, uv completions, aliases)
#
# What this does NOT do:
#   - Touch Fedora system Python (/usr/bin/python3*)
#   - Configure VSCodium / VSCode / PyCharm / NeoVim (Phase 2)
#   - Create project templates or validation projects (Phase 3)
#   - Install Jupyter / marimo (per-project only)
#   - Install DuckDB / Valkey
#
# Usage:
#   ./python_setup_phase1.sh              # full run
#   ./python_setup_phase1.sh --checks     # inventory only
#   ./python_setup_phase1.sh --dry-run    # print plan, make no changes
#
# Designed for a fresh Fedora 44 install; safe to re-run (idempotent).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/hardware.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/checks.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/install_uv.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/install_tools.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/configure_shell.sh"

DRY_RUN=0
CHECKS_ONLY=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

  --checks     Run read-only inventory and exit
  --dry-run    Show what would be done, make no changes
  -h, --help   Show this help

EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --checks)   CHECKS_ONLY=1; shift ;;
      --dry-run)  DRY_RUN=1; shift ;;
      -h|--help)  usage; exit 0 ;;
      *)          die "Unknown option: $1" ;;
    esac
  done
}

main() {
  parse_args "$@"

  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  Python development foundation — Phase 1 (Fedora 44)         ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  ensure_dirs
  detect_hardware
  run_checks

  if (( CHECKS_ONLY )); then
    log_ok "Checks-only mode finished."
    exit 0
  fi

  if (( DRY_RUN )); then
    log_warn "DRY-RUN: would install uv, Python versions, global tools, direnv, and configure shell."
    log_warn "Re-run without --dry-run to apply."
    exit 0
  fi

  # Confirm before mutating
  echo ""
  read -r -p "Proceed with Phase 1 installs? [y/N] " ans
  case "${ans,,}" in
    y|yes) ;;
    *) log_info "Aborted by user."; exit 0 ;;
  esac

  setup_uv
  setup_tools
  configure_shell

  echo ""
  log_step "Phase 1 complete"
  cat <<EOF

Next steps:
  1. Open a new terminal (or: source ~/.zshrc)
  2. Verify:  uv --version && ruff --version && direnv version
  3. Run Phase 3 when ready:  ./python_setup_phase3.sh
  4. Phase 2 (IDE configs) will be handled by separate scripts later.

Notes:
  • System Python is untouched.
  • New projects should use:  uv init && uv python pin 3.14   (or 3.12/3.13)
  • direnv is opt-in: copy templates/envrc.tmpl → .envrc then  direnv allow
  • Global tools live under ~/.local/bin via uv tool.

EOF
}

main "$@"
