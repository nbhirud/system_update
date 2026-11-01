#!/usr/bin/env bash
# Creates a NEW self-contained starter; never modifies existing repositories.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$HERE/lib/common.sh"
check_user
[[ $# -eq 2 && $1 == --create ]] || die 'Usage: bash python_setup_phase3.sh --create project-name'
[[ $2 =~ ^[a-z][a-z0-9_-]*$ ]] || die 'Use a lowercase project name, beginning with a letter.'
command -v uv >/dev/null || die 'Run phase 1 --apply first.'
command -v git >/dev/null || die 'git is required.'
# --isolated prevents any inherited uv config from changing starter creation.
# Bootstrap helper uses Fedora stdlib only; it never installs into Fedora Python.
/usr/bin/python3 "$ROOT/lib/create_project.py" "$2"
