#!/usr/bin/env bash
set -euo pipefail

####################################################################
# Make this an executable - Optional
####################################################################
# #  To make it an executable, Save this as:
# ~/.local/bin/firewalld_switch_current_zone

# # Make executable:
# chmod +x ~/.local/bin/firewalld_switch_zone

# # Usage:
# firewalld_switch_current_zone home
# firewalld_switch_current_zone public
# firewalld_switch_current_zone travel
# firewalld_switch_current_zone status

####################################################################
# Check inputs and assign to variables
####################################################################

ZONE="${1:-}"
# CURRENT_INTERFACE="$(nmcli -t -f DEVICE,STATE d | grep ':connected' | cut -d: -f1 | head -n1)"
CURRENT_INTERFACE="$(nmcli -t -f DEVICE,TYPE,STATE device | awk -F: '($2=="ethernet" || $2=="wifi") && $3 ~ /^connected/ {print $1; exit}')"

if [[ -z "$ZONE" ]]; then
  echo "Usage: bash firewalld_switch_current_zone.sh {home|public|travel|status}"
  exit 1
fi

if [[ -z "$CURRENT_INTERFACE" ]]; then
  echo "No active network interface found."
  exit 1
fi

echo "[+] Using interface: $CURRENT_INTERFACE"


####################################################################
# Apply selected zone
####################################################################

case "$ZONE" in
  home|public|travel)
    echo "[+] Switching interface $CURRENT_INTERFACE to zone: $ZONE"
    # Only change the interface zone (omitting --set-default-zone keeps global defaults intact)
    # sudo firewall-cmd --set-default-zone="$ZONE"
    sudo firewall-cmd --zone="$ZONE" --change-interface="$CURRENT_INTERFACE"
    sudo firewall-cmd --reload
    firewall-cmd --get-active-zones
    ;;
  status)
    firewall-cmd --get-default-zone
    firewall-cmd --get-active-zones
    exit 0
    ;;
  *)
    echo "Invalid zone: $ZONE"
    exit 1
    ;;
esac

