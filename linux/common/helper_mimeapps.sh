#!/usr/bin/env bash
#########################################################
# helper_mimeapps.sh
#########################################################
# Shell wrappers around helper_mimeapps.py (see that file for the why and the details).
#
# REQUIRES: python3, helper_logging.sh
#
# mimeapps_set_default <desktop_id> <mime_type>...
#     Makes <desktop_id> the only default for the types in ~/.config/mimeapps.list,
#     un-blacklists it, and cleans the same types from the deprecated
#     ~/.local/share/applications/mimeapps.list.
# mimeapps_forget <mime_type>...
#     Drops the types from [Default Applications] in both files (reset step).
# mimeapps_check_default <desktop_id> <mime_type>...
#     Returns 0 when all types resolve to <desktop_id>; prints failing types otherwise.
#
# Both file locations honour XDG_CONFIG_HOME / XDG_DATA_HOME.

_MIMEAPPS_PY="$(dirname "${BASH_SOURCE[0]}")/helper_mimeapps.py"
_mimeapps_main_file()       { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"; }
_mimeapps_deprecated_file() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/applications/mimeapps.list"; }

mimeapps_set_default() {
    local desktop_id="$1"; shift
    python3 "$_MIMEAPPS_PY" set-default --desktop-id "$desktop_id" --mime-types "$@" \
        --file "$(_mimeapps_main_file)" --clean-file "$(_mimeapps_deprecated_file)"
}

mimeapps_forget() {
    python3 "$_MIMEAPPS_PY" forget --mime-types "$@" \
        --file "$(_mimeapps_main_file)" --file "$(_mimeapps_deprecated_file)"
}

mimeapps_check_default() {
    local desktop_id="$1"; shift
    python3 "$_MIMEAPPS_PY" check --desktop-id "$desktop_id" --mime-types "$@" \
        --file "$(_mimeapps_main_file)" --file "$(_mimeapps_deprecated_file)"
}
