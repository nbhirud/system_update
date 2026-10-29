#!/usr/bin/env bash
#########################################################
# helper_run_as_user.sh
#########################################################
# Make sure a user-level setup script runs as the real (non-root) user.
#
# ensure_real_user "$@"
#   REQUIRES: REAL_USER and HOME_DIR to be set (see the standard variable block).
#   * Already running as the real user: returns immediately.
#   * Running as root because the script was started with sudo: re-executes the
#     script as REAL_USER, so files created in the home directory get the right
#     owner instead of root. HOME, USER and LOGNAME are corrected explicitly because
#     `runuser -u` keeps the caller's environment (which would still say root).
#   * Running as root without a different real user: aborts.
#
# Why: user-level configuration (dotfiles, ~/.local/bin) created by root is owned by
# root; the desktop session then cannot update or delete it.

ensure_real_user() {
    if [[ "$(id -un)" == "$REAL_USER" ]]; then
        return 0
    fi
    if [[ $EUID -ne 0 ]]; then
        log_die "Running as '$(id -un)' but REAL_USER is '${REAL_USER}'. Run as ${REAL_USER}."
    fi
    if [[ "$REAL_USER" == "root" ]]; then
        log_die "Run this script as a normal user (or via sudo from one); not as a direct root login."
    fi
    local uid
    uid="$(id -u "$REAL_USER")"
    log_info "Re-running as ${REAL_USER} (script started as root via sudo)"
    exec runuser -u "$REAL_USER" -- env \
        HOME="$HOME_DIR" USER="$REAL_USER" LOGNAME="$REAL_USER" \
        REAL_USER="$REAL_USER" FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-}" \
        XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}" \
        "$0" "$@"
}
