#!/bin/sh
# Prints the distribution release number (VERSION_ID), e.g. "44" on Fedora 44. Prints 0 if unknown.
# Test override: OS_RELEASE_FILE=/path/to/fake/os-release
file="${OS_RELEASE_FILE:-/etc/os-release}"
[ -r "$file" ] || { echo 0; exit 0; }
# shellcheck source=/dev/null
( . "$file"; echo "${VERSION_ID:-0}" )
