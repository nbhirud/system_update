#!/bin/sh

# set -eux

# echo $XDG_CURRENT_DESKTOP
# echo $DESKTOP_SESSION
# echo $GDMSESSION

# TODO - Make it foolproof. Currently only tested with Gnome

desktop=""

# # If XDG_CURRENT_DESKTOP is empty (e.g. running under sudo), 
# # try to grab it from the active graphical user session.
# if [ -z "${XDG_CURRENT_DESKTOP:-}" ] && command -v loginctl >/dev/null 2>&1; then
#   # Find the active graphical session user and pull their environment if possible
#   active_uid=$(loginctl list-sessions --no-legend | awk '{print $1}' | head -n1)
#   if [ -n "$active_uid" ]; then
#     XDG_CURRENT_DESKTOP=$(loginctl show-session "$active_uid" -p XDG_CURRENT_DESKTOP --value 2>/dev/null)
#   fi
# fi


# 1. If running under sudo, extract XDG_CURRENT_DESKTOP directly from 
#    the SUDO_USER's running graphical process environment in /proc
if [ -n "${SUDO_USER:-}" ] && [ -d /proc ]; then
  for pid_dir in /proc/[0-9]*/; do
    if [ -f "${pid_dir}status" ] && [ -f "${pid_dir}environ" ]; then
      # Check if process belongs to SUDO_USER
      if grep -q "^Uid:\s*$(id -u "$SUDO_USER")" "${pid_dir}status" 2>/dev/null; then
        env_content=$(tr '\0' '\n' < "${pid_dir}environ" 2>/dev/null)
        found_de=$(echo "$env_content" | grep '^XDG_CURRENT_DESKTOP=' | cut -d'=' -f2)
        if [ -n "$found_de" ]; then
          desktop="$found_de"
          break
        fi
      fi
    fi
  done
fi


# If running under sudo, retrieve the desktop environment 
# from the real invoking user's active session environment.
if [ -z "${desktop:-}" ] && [ -n "${SUDO_USER:-}" ]; then
  desktop=$(sudo -u "$SUDO_USER" printenv XDG_CURRENT_DESKTOP 2>/dev/null)
fi

# Fallback: query loginctl for active graphical sessions if still empty
if [ -z "${desktop:-}" ] && command -v loginctl >/dev/null 2>&1; then
  for session in $(loginctl list-sessions --no-legend | awk '{print $1}'); do
    session_type=$(loginctl show-session "$session" -p Type --value 2>/dev/null)
    session_desktop=$(loginctl show-session "$session" -p XDG_CURRENT_DESKTOP --value 2>/dev/null)
    
    if [ "$session_type" = "wayland" ] || [ "$session_type" = "x11" ]; then
      if [ -n "$session_desktop" ]; then
        desktop="$session_desktop"
        break
      fi
    fi
  done
fi



# if [ "$XDG_CURRENT_DESKTOP" = "" ]
# then
#   desktop=$(echo "$XDG_DATA_DIRS" | sed 's/.*\(xfce\|kde\|gnome\).*/\1/')
# else
#   desktop=$XDG_CURRENT_DESKTOP
# fi


# if [ "$XDG_CURRENT_DESKTOP" = "" ]
# then
#   desktop=$(echo "${XDG_DATA_DIRS:-}" | sed 's/.*\(xfce\|kde\|gnome\).*/\1/')
# else
#   desktop="$XDG_CURRENT_DESKTOP"
# fi


# Final fallback to standard environment check if needed
if [ -z "${desktop:-}" ]; then
  if [ -z "${XDG_CURRENT_DESKTOP:-}" ]; then
    # desktop=$(echo "${XDG_DATA_DIRS:-}" | sed 's/.*\(xfce\|kde\|gnome\).*/\1/')
    desktop=$(echo "${XDG_DATA_DIRS:-}" | sed 's/.*\(xfce\|kde\|gnome\|mate\|cinnamon\|lxqt\|lxde\|budgie\|enlightenment\|sway\|i3\|cosmic\|hyprland\).*/\1/')
  else
    desktop="$XDG_CURRENT_DESKTOP"
  fi
fi


# desktop=${desktop,,}  # convert to lower case  # Not POSIX
# echo "$desktop"

# echo "$a" | tr '[:upper:]' '[:lower:]'  # POSIX option 1
# echo "$a" | awk '{print tolower($0)}'  # POSIX  2


# Fallback if still empty
desktop="${desktop:-unknown}"

echo "$desktop" | awk '{print tolower($0)}'


# TODO - The following gets whether the PC is a desktop or server from this file. The file also has lot of other info like DE.
# Is using this to return DE the better way?
# ROLE=$(. /etc/os-release; [ "${VARIANT_ID:-}" = server ] && echo server || echo desktop)






#################################









