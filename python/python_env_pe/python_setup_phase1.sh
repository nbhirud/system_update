#!/usr/bin/env bash
# Default is read-only inventory. Only --apply performs installation/configuration.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$HERE/lib/common.sh"
check_user
case ${1:---audit} in
 --audit) bash "$ROOT/python_setup_inventory.sh" ;;
 --apply)
   bash "$ROOT/python_setup_inventory.sh"
   command -v flock >/dev/null || die 'flock (util-linux) is required.'
   mkdir -p "$HOME/.cache/python-setup"
   exec 9>"$HOME/.cache/python-setup/setup.lock"
   flock -n 9 || die 'Another setup is running.'
   # No system Python package, alternative, symlink or site-package is changed.
   sudo dnf install -y curl ca-certificates git direnv zsh
   bash "$ROOT/python_setup_uv.sh"
   bash "$ROOT/python_setup_tools.sh"
   bash "$ROOT/python_setup_shell.sh"
   log 'Phase 1 complete. Open a new zsh session. IDE configuration is deferred to phase 2.'
   ;;
 *) die 'Usage: bash python_setup_phase1.sh [--audit|--apply]' ;;
esac
