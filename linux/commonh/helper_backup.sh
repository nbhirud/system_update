#!/usr/bin/env bash
#########################################################
# helper_backup.sh
#########################################################
# Verified backups of files, directories, and command state records.
#
# FUNCTIONS:
#   backup_path <source_path> <backup_dir> <name_inside_backup_dir>
#     * Backs up a file or directory into a specific name inside <backup_dir>.
#     * Missing source: returns 0 silently (nothing to back up).
#     * Name collisions: automatically appends numeric suffixes (.1, .2, ...).
#     * Copies with `cp -a` (keeps permissions, timestamps, symlinks).
#     * Verifies directories afterwards with `diff -rq`; aborts script on mismatch.
#     * COMPATIBILITY: called with only TWO arguments (<source_path> <backup_root_dir>) it behaves
#       like backup_path_parents. Older copies of the zsh/omz/starship/atuin scripts used that form.
#       New code should call backup_path_parents explicitly.
#
#   backup_path_parents <source_path> <backup_root_dir>
#     * Copies a file or directory into <backup_root_dir> while keeping its full
#       original absolute path hierarchy (using `cp -a --parents`). Example:
#         backup_path_parents /home/me/.zshrc /backups/zsh_2026-10-29
#         -> /backups/zsh_2026-10-29/home/me/.zshrc
#       The hierarchy makes a restore unambiguous (two files named ".zshrc" cannot collide).
#     * Missing source: returns 0 silently.
#
#   backup_record <backup_root_dir> <label> <command...>
#     * Saves the stdout/stderr of a command (e.g., `getent passwd root`) into
#       <backup_root_dir>/_records/<label>.txt. A failing command does not abort the backup.
#
# REQUIREMENTS:
#   log_success and log_die (from helper_logging.sh or helper_common.sh). If neither is loaded,
#   minimal fallbacks are defined below so the helper never fails with "command not found".
#   GNU coreutils (cp --parents, diff). Run as root to back up root-owned files.
#########################################################


# Sourcing Guard Rails - uses a safety guard (HELPER_XYZ_LOADED) to prevent issues if it gets sourced multiple times.
if [[ -z "${HELPER_BACKUP_LOADED:-}" ]]; then
    HELPER_BACKUP_LOADED=1

    # Fallbacks only when the real logging functions are not loaded (never overrides them).
    if ! declare -F log_success >/dev/null 2>&1; then log_success() { echo "[✓] $*"; }; fi
    if ! declare -F log_die >/dev/null 2>&1; then log_die() { echo "[✗] $*" >&2; exit 1; }; fi

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

    backup_path() {
        # Two-argument (compatibility) form: same as backup_path_parents.
        if [[ $# -eq 2 ]]; then
            backup_path_parents "$1" "$2"
            return $?
        fi

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

    backup_record() {
        local dest_root="$1"
        local label="$2"
        shift 2

        mkdir -p "${dest_root}/_records" || return 1
        "$@" > "${dest_root}/_records/${label}.txt" 2>&1 || true
        log_success "Recorded state: ${label}"
    }

fi
