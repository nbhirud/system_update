#!/usr/bin/env bash
#########################################################
# helper_version_compare.sh
#########################################################
# version_ge <version_a> <version_b>
#   Returns 0 when version_a >= version_b (natural version ordering, e.g. 0.41.0 >= 0.38).
#   Leading "v" is ignored ("v0.41.0" == "0.41.0").
#
# How it works: `sort -V` sorts version strings naturally. Printing B then A and taking
# the first line after sorting gives the smaller of the two; if that equals B, then A >= B.

version_ge() {
    local a="${1#v}" b="${2#v}"
    [[ "$(printf '%s\n%s\n' "$b" "$a" | sort -V | head -n1)" == "$b" ]]
}
