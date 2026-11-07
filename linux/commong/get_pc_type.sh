#!/usr/bin/env bash

# set -eux

pc_type="unknown"

# 1. Check via hostnamectl (systemd)
if command -v hostnamectl >/dev/null 2>&1; then
    chassis=$(hostnamectl chassis 2>/dev/null)
    case "$chassis" in
        laptop|notebook|portable|handheld|subnotebook)
            pc_type="laptop"
            ;;
        desktop|all-in-one)
            pc_type="desktop"
            ;;
        server|rackmount|blade)
            pc_type="server"
            ;;
    esac
fi

# 2. Fallback to DMI chassis_type numeric codes if still unknown
if [ "$pc_type" = "unknown" ] && [ -f /sys/class/dmi/id/chassis_type ]; then
    case "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" in
        3|4|5|6|7|13|15|35) 
            pc_type="desktop" 
            ;;
        8|9|10|14|21|31|32) 
            pc_type="laptop" 
            ;;
        17|23|24|28) 
            pc_type="server" 
            ;;
    esac
fi

if [ "$pc_type" = "unknown" ]; then
    # PC_TYPE="$( . /etc/os-release; [ "${VARIANT_ID:-}" = server ] && echo server || echo desktop )"   # subshell: no variable pollution
    # SC1091: parse instead of sourcing (no shell code from the file is executed). Replacing the PC_TYPE="$( . /etc/os-release; ...)" line:
    if grep -qE '^VARIANT_ID="?server"?$' /etc/os-release 2>/dev/null; then PC_TYPE_DEFAULT=server; else PC_TYPE_DEFAULT=desktop; fi
    pc_type="${pc_type:-$PC_TYPE_DEFAULT}"
fi

# 3. Final heuristic fallback: If it's headless (no framebuffer or display), force 'server'
if [ "$pc_type" = "unknown" ]; then
    if [ ! -e /sys/class/graphics/fb0 ] && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        pc_type="server"
    else
        pc_type="desktop"
    fi
fi




PC_TYPE=$(echo "$pc_type" | awk '{print tolower($0)}')
# echo "Detected PC Type: $PC_TYPE"

echo "$PC_TYPE"
