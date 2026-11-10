#!/usr/bin/env bash
# Global isolated CLI tools are conveniences. Repository tools remain authoritative.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$HERE/lib/common.sh"
for tool in ruff basedpyright mypy ty pre-commit pip-audit; do
 if command -v "$tool" >/dev/null; then
   log "Reusing $tool at $(command -v "$tool")"
 else
   uv tool install "$tool"
 fi
done
# basedpyright supplies the selected Pyright-family checker. Do not install both by default.
# pytest, coverage, debugpy and HTTP test support belong in each project, not global tools.
# Poetry is an optional isolated CLI; existing Poetry and pipx installations are preserved.
if command -v poetry >/dev/null; then log "Existing Poetry preserved: $(command -v poetry)"; fi
