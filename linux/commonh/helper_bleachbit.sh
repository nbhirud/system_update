#!/usr/bin/env bash
##################################################################################
# helper_bleachbit.sh
##################################################################################
# Purpose
#   Find where custom BleachBit cleaners (CleanerML .xml files) must be placed
#   for the way BleachBit is installed on this machine.
#
#   dnf package  -> ~/.config/bleachbit/cleaners
#   flatpak      -> ~/.var/app/org.bleachbit.BleachBit/config/bleachbit/cleaners
#   neither      -> returns 1 (prints nothing); the caller should skip quietly
#
# Usage
#   source "$HELPER_DIR/helper_bleachbit.sh"
#   if dir="$(bleachbit_cleaner_dir)"; then install -D -m 0644 my.xml "$dir/my.xml"; fi
#
# Honors HOME_DIR if the caller defined it (scripts run as REAL_USER).
##################################################################################

if [ -n "${HELPER_BLEACHBIT_LOADED:-}" ]; then
  return 0
fi
HELPER_BLEACHBIT_LOADED=1

bleachbit_cleaner_dir() {
  local home="${HOME_DIR:-$HOME}"
  if rpm -q bleachbit >/dev/null 2>&1; then
    printf '%s\n' "$home/.config/bleachbit/cleaners"
  elif command -v flatpak >/dev/null 2>&1 && flatpak info org.bleachbit.BleachBit >/dev/null 2>&1; then
    printf '%s\n' "$home/.var/app/org.bleachbit.BleachBit/config/bleachbit/cleaners"
  else
    return 1
  fi
}
