#!/bin/bash

# set -eux
set -euo pipefail

# For SSD Tuning

# SSD_PRESENT=false
# ROOT_DEV=$(df / | tail -1 | awk '{print $1}')
# BACKING_DEV=$(lsblk -no pkname "$ROOT_DEV" 2>/dev/null || basename "$ROOT_DEV" | sed 's/[0-9]*$//')

# if [ -n "$BACKING_DEV" ] && [ -f "/sys/block/$BACKING_DEV/queue/rotational" ]; then
#     if [ "$(cat /sys/block/"$BACKING_DEV"/queue/rotational)" -eq 0 ]; then
#         SSD_PRESENT=true
#     fi
# elif lsblk -d -o rota | grep -q "^0$"; then
#     SSD_PRESENT=true
# fi


# 2. REAL_USER (defaults to SUDO_USER or current user)
REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"

HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"
NBDIR="$HOME_DIR/nb"

# Replacing the old SSD detection block (the one using BACKING_DEV / lsblk pkname).
# path_is_rotational PATH: true if ANY device under PATH's filesystem is rotational (HDD) or unknown.
path_is_rotational() {
    local path="$1" src stack fsuuid d
    src=$(findmnt -n -o SOURCE --target "$path" 2>/dev/null | head -n1)
    src=${src%%\[*}                              # btrfs prints /dev/xxx[/subvolume]: strip the subvolume
    [ -b "$src" ] || return 0                    # tmpfs/overlay/network/unknown: be conservative
    stack=$(lsblk -s -n -o ROTA "$src" 2>/dev/null | tr -d ' ')   # -s: this device AND everything under it
    # btrfs spanning several devices: findmnt shows only one, but sysfs lists them all
    fsuuid=$(findmnt -n -o UUID --target "$path" 2>/dev/null | head -n1)
    if [ -n "$fsuuid" ] && [ -d "/sys/fs/btrfs/$fsuuid/devices" ]; then
        for d in /sys/fs/btrfs/"$fsuuid"/devices/*; do
            stack+=$'\n'$(lsblk -s -n -o ROTA "/dev/$(basename "$d")" 2>/dev/null | tr -d ' ')
        done
    fi
    [ -n "$stack" ] || return 0
    printf '%s\n' "$stack" | grep -qx '1'
}

FAST_STORAGE=true
for p in / "$HOME_DIR" "$NBDIR" /srv; do
    if [ -e "$p" ] && path_is_rotational "$p"; then
        FAST_STORAGE=false; 
        # echo "INFO: $p is on rotational or unknown storage"
    fi
done
SSD_PRESENT=$FAST_STORAGE   # keep the old name so ONACC_PREVENT and the weekly engine keep working

echo $SSD_PRESENT # boolean