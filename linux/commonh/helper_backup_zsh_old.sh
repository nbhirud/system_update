#!/usr/bin/env bash
#########################################################
# helper_backup.sh - reusable "backup anything before touching it" helper
#########################################################
#
# WHAT IT DOES
#   backup_path <source_path> <backup_root_dir>
#     Copies a file or a whole directory into <backup_root_dir>, KEEPING its full
#     original path underneath it. Example:
#       backup_path /home/me/.zshrc /backups/zsh_2026-10-29
#       -> /backups/zsh_2026-10-29/home/me/.zshrc
#     Keeping the full path means a restore is unambiguous (nothing named
#     ".zshrc" from two different users can collide) and nothing needs a manifest.
#
#   backup_record <backup_root_dir> <label> <command...>
#     Saves the output of a command (for example `getent passwd root`) to
#     <backup_root_dir>/_records/<label>.txt. Useful for state that is not a file,
#     such as a user's login shell, which lives in /etc/passwd.
#
# HOW IT WORKS
#   `cp -a` preserves ownership, permissions, timestamps and symlinks.
#   `--parents` recreates the source's directory path under the destination.
#   Missing sources are silently skipped (returns 0), because "nothing to back up"
#   is a normal situation on a fresh machine.
#
# USAGE
#   source /path/to/helper_backup.sh
#   backup_path "/etc/shells" "$MY_BACKUP_DIR"
#   backup_record "$MY_BACKUP_DIR" "passwd_entries" getent passwd root
#
# REQUIREMENTS
#   GNU coreutils (cp --parents). Run as root to back up root-owned files.

backup_path() {
  local src="$1"
  local dest_root="$2"

  # -e is false for a dangling symlink, so also test -L (is a symlink).
  if [[ ! -e "$src" && ! -L "$src" ]]; then
    return 0
  fi

  mkdir -p "$dest_root"
  # "|| return 1": inside functions that may be called from an `if`, `set -e` is
  # not active, so failures must be passed on explicitly.
  cp -a --parents "$src" "$dest_root" || return 1
}

backup_record() {
  local dest_root="$1"
  local label="$2"
  shift 2

  mkdir -p "${dest_root}/_records"
  # The command's own failure must not abort a backup, so errors are tolerated;
  # an empty record file simply means the command had nothing to say.
  "$@" > "${dest_root}/_records/${label}.txt" 2>&1 || true
}
