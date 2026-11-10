#!/usr/bin/env bash
# Explicit opt-in for EXISTING repositories. Never rewrites lockfiles or converts managers.
# Review/trust the repository first: installing dependencies may execute build backends.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$HERE/lib/common.sh"
[[ $# -ge 1 && $# -le 2 ]] || die 'Usage: python_project_bootstrap.sh /path/to/repo [python-version]'
cd -- "$1"
[[ ! -L .venv ]] || die 'Refusing a symlinked .venv.'
unset VIRTUAL_ENV CONDA_PREFIX UV_PROJECT_ENVIRONMENT UV_PYTHON
if [[ -f uv.lock && -f poetry.lock ]]; then
 die 'Both uv.lock and poetry.lock exist. Select the authoritative manager manually.'
elif [[ -f uv.lock ]]; then
 uv sync --locked
elif [[ -f poetry.lock ]]; then
 command -v poetry >/dev/null || die 'Poetry required: install explicitly with uv tool install poetry.'
 export POETRY_VIRTUALENVS_IN_PROJECT=true
 # Do not silently reuse/migrate an external Poetry environment.
 existing=$(poetry env info --path 2>/dev/null || true)
 [[ -z $existing || $existing == "$PWD/.venv" ]] || die "External Poetry env exists: $existing. Migrate deliberately."
 if [[ $# -eq 2 ]]; then
   UV_PYTHON_INSTALL_BIN=0 uv python install "$2"
   poetry env use "$(uv python find --managed-python "$2")"
 fi
 poetry install
 [[ -x .venv/bin/python ]] || die 'Poetry did not create .venv. Check project interpreter settings.'
elif [[ -f requirements.txt ]]; then
 # Requirements alone do not declare a Python version. Never guess for existing code.
 version=${2:-}
 if [[ -z $version && -f .python-version ]]; then version=$(cat .python-version); fi
 if [[ ! -d .venv ]]; then
   [[ -n $version ]] || die 'Specify the project Python version, or add a reviewed .python-version.'
   UV_PYTHON_INSTALL_BIN=0 uv python install "$version"
   uv venv --python "$version" .venv
 fi
 uv pip install --python .venv/bin/python -r requirements.txt
 log 'requirements-dev files are not guessed; install the project-documented files explicitly.'
elif [[ -f pyproject.toml ]]; then
 die 'No lockfile. Review the project manager and its bootstrap instructions; not guessing.'
else
 die 'No recognized dependency manifest found.'
fi
log 'No hooks, .envrc, notebook dependencies or IDE files installed into this existing repo.'
