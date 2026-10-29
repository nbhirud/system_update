#!/usr/bin/env bash
#########################################################
# helper_fonts.sh
#########################################################
# Font lookup through fontconfig.
#
# first_installed_font <family>...
#   Prints the first family name (from the arguments) that fontconfig reports as
#   installed, or nothing if none is. Always returns 0.
#   Example:  UI_FONT="$(first_installed_font "NotoSans Nerd Font" "Noto Sans")"
#
# Notes
#   * `fc-list : family` prints comma-separated alias lists such as
#     "NotoSans Nerd Font,NotoSans NF"; the list is split into one family per line so an
#     exact match on any alias works.
#   * The list is captured into a variable first and searched with a here-string. That
#     avoids the pipefail + `grep -q` SIGPIPE false negative described in helper_array.sh.

first_installed_font() {
    command -v fc-list >/dev/null 2>&1 || return 0
    local families family
    families="$(fc-list -f '%{family}\n' 2>/dev/null | tr ',' '\n' || true)"
    for family in "$@"; do
        if grep -Fxq -- "$family" <<<"$families"; then
            printf '%s\n' "$family"
            return 0
        fi
    done
    return 0
}
