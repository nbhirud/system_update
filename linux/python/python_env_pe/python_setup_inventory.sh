#!/usr/bin/env bash
# Prints local inventory only; no installs, activation, project execution or reports written.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$HERE/lib/common.sh"
printf '\n=== OS and hardware ===\n'
cat /etc/os-release
getconf _NPROCESSORS_ONLN
free -h
printf '\n=== Executables and versions ===\n'
for c in python python3 uv poetry pipx ruff basedpyright pyright mypy ty pre-commit direnv code codium nvim zsh; do
 if command -v "$c" >/dev/null 2>&1; then
   command -v "$c"
   "$c" --version 2>&1 || true
 fi
done
printf '\n=== Fedora Python RPMs ===\n'
rpm -qa 'python3*' | sort
if command -v uv >/dev/null; then uv python list --only-installed; uv tool list; fi
if command -v pipx >/dev/null; then pipx list; fi
printf '\n=== IDE extensions (no installation) ===\n'
for c in code codium; do
 if command -v "$c" >/dev/null; then "$c" --list-extensions --show-versions || true; fi
done
printf '\n=== JetBrains Toolbox installation markers ===\n'
for d in "$HOME/.local/share/JetBrains/Toolbox" "$HOME/.config/JetBrains"; do
 [[ ! -d $d ]] || find "$d" -maxdepth 5 -type f \( -name product-info.json -o -name '*options*.xml' \) -print
done
printf '\n=== Project environment and package-manager markers (max depth 6) ===\n'
if [[ -d $HOME/nb/CodeProjects ]]; then
 find "$HOME/nb/CodeProjects" -maxdepth 6 \( -name .git -o -name node_modules \) -prune -o \
   -type f \( -name pyvenv.cfg -o -name pyproject.toml -o -name uv.lock -o -name poetry.lock -o -name .python-version -o -name requirements.txt \) -print
fi
printf '\n=== Existing optional services (not installed or started) ===\n'
for c in duckdb valkey-cli valkey-server; do command -v "$c" || true; done
printf '\n=== Config file presence (contents and secrets not printed) ===\n'
for f in "$HOME/.zshrc" "$HOME/.config/uv/uv.toml" "$HOME/.config/Code/User/settings.json" "$HOME/.config/VSCodium/User/settings.json" "$HOME/.config/nvim/init.lua"; do
 [[ ! -e $f ]] || ls -ld -- "$f"
done
