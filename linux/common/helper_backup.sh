#!/usr/bin/env bash
#########################################################
# helper_backup.sh
#########################################################
# Verified backups of files and directories.
#
# backup_path <source_path> <backup_dir> <name_inside_backup_dir>
#   * Missing source: returns 0 silently (nothing to back up).
#   * Existing destination name: a numeric suffix is added (config-mpv, config-mpv.1, ...);
#     nothing is ever overwritten or nested.
#   * Copies with `cp -a` (keeps permissions, timestamps, symlinks).
#   * Directories are verified afterwards with `diff -rq`; a mismatch aborts the script,
#     because every later "reset" step deletes originals on the assumption that the
#     backup is faithful.
#
# Example
#   backup_path "$HOME/.config/mpv" "$MPV_CURRENT_BACKUP_DIR" "config-mpv"

backup_path() {
    local src="$1" backup_dir="$2" name="$3" dest n=1
    if [[ ! -e "$src" && ! -L "$src" ]]; then
        return 0
    fi
    # Never write into an existing destination: `cp -a SRC DEST` copies INTO DEST when it is a
    # directory (DEST/<basename>), which nests the backup and breaks verification. This happens when
    # two runs share one backup directory (same FILENAME_TIMESTAMP, e.g. exported by a parent script).
    # A numeric suffix keeps every earlier backup intact.
    dest="${backup_dir}/${name}"
    while [[ -e "$dest" || -L "$dest" ]]; do
        dest="${backup_dir}/${name}.${n}"
        n=$((n + 1))
    done
    cp -a -- "$src" "$dest"
    if [[ -d "$src" && ! -L "$src" ]]; then
        if ! diff -rq -- "$src" "$dest" >/dev/null 2>&1; then
            log_die "Backup verification failed for ${src} (copy at ${dest})"
        fi
    fi
    log_success "Backed up ${src}"
}
