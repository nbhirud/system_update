#!/usr/bin/env bash
# Shared safety primitives. Source only from the entry points.
set -Eeuo pipefail
umask 077
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
BACKUP_ROOT="${HOME}/nb/nbscript_backups/python-setup"
export PATH="$HOME/.local/bin:$PATH"
log() { printf '[python-setup] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
trap 'printf "Failed at %s:%s (exit %s)\n" "${BASH_SOURCE[0]}" "$LINENO" "$?" >&2' ERR
check_user() {
 [[ $EUID -ne 0 ]] || die 'Run as your regular user, not root.'
 [[ -r /etc/os-release ]] || die 'Missing /etc/os-release.'
 source /etc/os-release
 [[ $ID == fedora ]] || die 'This setup targets Fedora.'
 [[ ${VERSION_ID:-} == 44 ]] || log "Warning: tested target is Fedora 44; detected ${VERSION_ID:-unknown}."
}
backup() {
 local src=$1 dst
 [[ -e $src || -L $src ]] || return 0
 [[ ! -L $src ]] || die "Refusing to modify symlink: $src"
 dst="$BACKUP_ROOT/$(date -u +%Y%m%dT%H%M%S)-$$/${src#"$HOME/"}"
 mkdir -p -- "$(dirname -- "$dst")"
 cp -a -- "$src" "$dst"
 log "Backup: $dst"
}
# Change a file only if its contents differ, retaining a timestamped backup.
replace_file() {
 local target=$1 staged=$2
 [[ ! -L $target ]] || die "Refusing symlink: $target"
 if [[ -f $target ]] && cmp -s -- "$target" "$staged"; then return 0; fi
 backup "$target"
 mkdir -p -- "$(dirname -- "$target")"
 install -m 600 -- "$staged" "$target"
}
