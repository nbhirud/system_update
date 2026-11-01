#!/usr/bin/env bash
#########################################################
# helper_backup.sh
#########################################################
# Verified backups of files, directories, and command state records.
#
# FUNCTIONS:
#   backup_path <source_path> <backup_dir> <name_inside_backup_dir>
#     * Backs up a file or directory into a specific name inside <backup_dir>[cite: 32].
#     * Missing source: returns 0 silently (nothing to back up)[cite: 32].
#     * Name collisions: automatically appends numeric suffixes (.1, .2, ...)[cite: 32].
#     * Copies with `cp -a` (keeps permissions, timestamps, symlinks)[cite: 32].
#     * Verifies directories afterwards with `diff -rq`; aborts script on mismatch[cite: 32].
#
#   backup_path_parents <source_path> <backup_root_dir>
#     * Copies a file or directory into <backup_root_dir> while keeping its full
#       original absolute path hierarchy (using `cp -a --parents`)[cite: 33].
#
#   backup_record <backup_root_dir> <label> <command...>
#     * Saves the stdout/stderr of a command (e.g., `getent passwd root`) into
#       <backup_root_dir>/_records/<label>.txt[cite: 33].
#
# REQUIREMENTS:
#   Requires helper_logging.sh for log_success and log_die.
#########################################################


# Sourcing Guard Rails - uses a safety guard (HELPER_XYZ_LOADED) to prevent issues if it gets sourced multiple times.
if [[ -z "${HELPER_BACKUP_LOADED:-}" ]]; then
    HELPER_BACKUP_LOADED=1

    backup_path() {
        local src="$1" backup_dir="$2" name="$3" dest n=1
        if [[ ! -e "$src" && ! -L "$src" ]]; then
            return 0
        fi
        
        mkdir -p -- "$backup_dir"
        
        # Never write into an existing destination: numeric suffixes keep earlier backups intact.
        dest="${backup_dir}/${name}"
        while [[ -e "$dest" || -L "$dest" ]]; do
            dest="${backup_dir}/${name}.${n}"
            n=$((n + 1))
        done
        
        cp -a -- "$src" "$dest" || return 1
        
        if [[ -d "$src" && ! -L "$src" ]]; then
            if ! diff -rq -- "$src" "$dest" >/dev/null 2>&1; then
                log_die "Backup verification failed for ${src} (copy at ${dest})"
            fi
        fi
        
        log_success "Backed up ${src}"
    }

    backup_path_parents() {
        local src="$1"
        local dest_root="$2"

        if [[ ! -e "$src" && ! -L "$src" ]]; then
            return 0
        fi

        mkdir -p "$dest_root" || return 1
        cp -a --parents "$src" "$dest_root" || return 1
        log_success "Backed up ${src} (with path hierarchy)"
    }

    backup_record() {
        local dest_root="$1"
        local label="$2"
        shift 2

        mkdir -p "${dest_root}/_records" || return 1
        "$@" > "${dest_root}/_records/${label}.txt" 2>&1 || true
        log_success "Recorded state: ${label}"
    }

fi
