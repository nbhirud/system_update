#!/usr/bin/env bash
# Use the official standalone installer; do not pipe remote code into a shell.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$HERE/lib/common.sh"
if ! command -v uv >/dev/null; then
 tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
 curl --proto '=https' --tlsv1.2 --fail --show-error --location \
   --retry 3 https://astral.sh/uv/install.sh -o "$tmp/install.sh"
 # Explicit install location and no installer edits to shell files.
 UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh "$tmp/install.sh"
else
 log "Reusing $(command -v uv); not migrating or updating an existing installation."
fi
uv --version
# Download managed CPython, without putting python/python3 wrappers on PATH.
# Latest stable is resolved by uv at execution time, not hard-coded here.
UV_PYTHON_INSTALL_BIN=0 uv python install
uv python list --only-installed
