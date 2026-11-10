#!/usr/bin/env bash
# Add one owned zsh fragment, preserving Oh My Zsh/plugins and existing uv config.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$HERE/lib/common.sh"
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
cat > "$tmp/python-dev.zsh" <<'ZSH'
# Managed by python-development-setup. Project-local interpreter takes precedence.
# No aliases for python, python3 or pip; Fedora's defaults remain intact.
typeset -U path
path+=("$HOME/.local/bin")
export PATH
# Poetry honors .venv for new environments. Existing external envs are not migrated.
export POETRY_VIRTUALENVS_IN_PROJECT=true
# Require pip to run inside a venv. Use uv pip or the project's python -m pip.
export PIP_REQUIRE_VIRTUALENV=true
export PIP_DISABLE_PIP_VERSION_CHECK=1
# Do not overwrite project interpreter selection with UV_PYTHON or an absolute venv path.
# Conservative resource limits, recalculated per machine and interactive session.
_python_dev_cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
_python_dev_mem=$(awk '/MemTotal/ {print int($2/1048576)}' /proc/meminfo)
_python_dev_jobs=$(( _python_dev_mem / 2 ))
(( _python_dev_jobs >= 1 )) || _python_dev_jobs=1
(( _python_dev_jobs <= _python_dev_cpus )) || _python_dev_jobs=$_python_dev_cpus
(( _python_dev_jobs <= 8 )) || _python_dev_jobs=8
export UV_CONCURRENT_BUILDS=${UV_CONCURRENT_BUILDS:-$_python_dev_jobs}
export UV_CONCURRENT_INSTALLS=${UV_CONCURRENT_INSTALLS:-$_python_dev_jobs}
export UV_CONCURRENT_DOWNLOADS=${UV_CONCURRENT_DOWNLOADS:-8}
unset _python_dev_cpus _python_dev_mem _python_dev_jobs
# direnv requires explicit approval per .envrc; no allow rules are installed.
if (( $+commands[direnv] )); then
 if (( ! ${precmd_functions[(Ie)_direnv_hook]} )); then
   eval "$(direnv hook zsh)"
 fi
fi
ZSH
replace_file "$HOME/.config/python-dev/shell.zsh" "$tmp/python-dev.zsh"
[[ ! -L $HOME/.zshrc ]] || die 'Refusing symlinked .zshrc; source the fragment manually.'
source_line='[[ ! -r "$HOME/.config/python-dev/shell.zsh" ]] || source "$HOME/.config/python-dev/shell.zsh"'
if ! grep -Fqx "$source_line" "$HOME/.zshrc" 2>/dev/null; then
 backup "$HOME/.zshrc"
 printf '\n# Python development foundation (after Oh My Zsh)\n%s\n' "$source_line" >> "$HOME/.zshrc"
fi
log 'No fictional blanket telemetry environment variables or network blocks installed.'
log 'VS Code/VSCodium/JetBrains/extension privacy is intentionally reserved for phase 2.'
