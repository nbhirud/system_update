#!/bin/bash

# set -eux
set -euo pipefail

# 2. REAL_USER (defaults to SUDO_USER or current user)
REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"

HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"
NBDIR="$HOME_DIR/nb"

CODEPROJECTS_DIR="$NBDIR/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="$CODEPROJECTS_DIR/system_update"

RAM_MB=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_ram_size.sh)

if   [ "$RAM_MB" -lt 10000 ];  then RAM_PROFILE=low
elif [ "$RAM_MB" -lt 20000 ]; then RAM_PROFILE=mid
else                               RAM_PROFILE=high
fi

echo $RAM_PROFILE
