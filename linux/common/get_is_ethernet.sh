#!/usr/bin/env bash


HOME_DIR=$(getent passwd "$REAL_USER" | cut -d: -f6)
NBDIR="$HOME_DIR/nb"
CODEPROJECTS_DIR="$NBDIR/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="$CODEPROJECTS_DIR/system_update"

# CONNECTION_TYPE=$(nmcli -t -f TYPE,STATE device | awk -F: '($1=="ethernet" || $1=="wifi") && $2 ~ /^connected/ { print $1; exit}')
CONNECTION_TYPE=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_connection_type.sh)

IS_ETHERNET=false
if [ "$CONNECTION_TYPE" = "ethernet" ]; then
  IS_ETHERNET=true
fi

echo "${IS_ETHERNET}"
