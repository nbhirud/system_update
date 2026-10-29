#!/usr/bin/env bash
#########################################################
# helper_array.sh
#########################################################
# Small list utilities.
#
# array_contains <needle> <item>...
#   Returns 0 when <needle> is exactly equal to one of the items, 1 otherwise.
#   Example:  array_contains "mpv" "${installed[@]}" && echo "already there"
#
# Why a function instead of "printf '%s\n' list | grep -Fxq needle"?
#   With `set -o pipefail`, "cmd | grep -q" can report FAILURE even though grep found
#   the match: grep -q exits at the first hit, the left side then receives SIGPIPE and
#   pipefail reports that. A plain loop has no pipe, so no such race exists.

array_contains() {
    local needle="$1" item
    shift
    for item in "$@"; do
        if [[ "$item" == "$needle" ]]; then
            return 0
        fi
    done
    return 1
}

# array_join_space <item>...
#   Prints the items joined by single spaces (for log messages and key=value files).
#   Needed because "${array[*]}" joins with the FIRST CHARACTER OF IFS, and the setup scripts
#   set IFS to newline/tab for safe word splitting: "${array[*]}" would then print one item per line.
array_join_space() {
    local IFS=' '
    printf '%s' "$*"
}
