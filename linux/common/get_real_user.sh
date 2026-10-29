#!/usr/bin/env bash

echo "************************ Identify the real user (non root) running the script/logged in ************************"

# Get the actual user's home when runing a script with sudo
# USER_HOME=$(eval echo ~${SUDO_USER})
# echo ${USER_HOME}
# Avoiding eval (https://mywiki.wooledge.org/BashFAQ/048), below is a better way: 
# USER_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)


# Note: In shell scripting, all variables are global by default within the current script process, regardless of whether they are defined inside an if block, a loop, or a code section. Thats why we haven't declared REAL_USER before using it in the if-else block

# 1. Check SUDO_USER first, but make sure it isn't 'root'
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    REAL_USER="$SUDO_USER"
# 2. Fall back to the owner of the controlling terminal (tty)
elif [ -t 0 ] && [ -n "$(logname 2>/dev/null)" ] && [ "$(logname)" != "root" ]; then
    REAL_USER="$(logname)"
# 3. Fall back to the active desktop/graphical session user (UID >= 1000)
else
    REAL_USER=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | while read -r u; do id -u "$u" &>/dev/null && [ "$(id -u "$u")" -ge 1000 ] && echo "$u" && break; done)
fi

# Fallback to current user if all checks fail
REAL_USER="${REAL_USER:-$USER}"

echo "${REAL_USER}"
