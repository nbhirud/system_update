#!/usr/bin/env bash

# ($1=="ethernet" || $1=="wifi"): Filters out internal virtual devices, loops, and bridges.
# $2 ~ /^connected/: Safely handles variants like connected, connected (external), etc.
# CONNECTION_TYPE will either be ethernet or wifi

CONNECTION_TYPE=$(nmcli -t -f TYPE,STATE device | awk -F: '($1=="ethernet" || $1=="wifi") && $2 ~ /^connected/ { print $1; exit}')

echo "${CONNECTION_TYPE}"
