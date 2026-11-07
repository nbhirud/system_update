#!/bin/bash

set -eux


# Sets a firewalld zone to a connection such that whenever connected to that wifi/ethernet connection, the PC automatically switches to the assigned zone 
# Needs to be set only once when a new wifi/ethernet connection is added

# Usage:
# sh firewalld_assign_connections.sh "Wired connection 1" home


# Assign command-line arguments to variables
CONNECTION_NAME="${1:-}"
ZONE="${2:-}"

# Check if both arguments were provided
if [ -z "$CONNECTION_NAME" ] || [ -z "$ZONE" ]; then
    echo "Usage: $0 <CONNECTION_NAME> <ZONE>"
    echo "Example: $0 \"Wired connection 1\" home"
    exit 1
fi

#############################
# To programmatically set the Firewall zone for a connection profile using the terminal, you use nmcli connection modify with the connection.zone property.
# Target: NetworkManager connection profile (e.g., "Wired connection 1").
# How it works: It writes the zone setting directly into NetworkManager's profile configuration. When you connect using that profile, NetworkManager tells firewalld to place the interface into that zone.
# Why use it: On Fedora, NetworkManager manages your network stack. Binding the zone at the profile level ensures that your preferences follow that specific connection, even if the underlying hardware interface name changes.
# Verification: Run nmcli -f connection.zone connection show "CONNECTION_NAME" to confirm the zone is bound to the profile.
sudo nmcli connection modify "$CONNECTION_NAME" connection.zone "$ZONE"

# Verify it was set:
nmcli -f connection.zone connection show "$CONNECTION_NAME"

# ############################# Optional (redundant)
# # Target: Raw network interface name (e.g., eth0, enp3s0).
# # How it works: It tells firewalld directly to bind a specific kernel interface name to a zone, storing it in firewalld's own config files.
# # The Catch: firewall-cmd expects a physical or virtual interface name, not a NetworkManager connection profile name like "Wired connection 1". Furthermore, if NetworkManager recreates or renames interfaces, this mapping can become decoupled or desynchronized.
# # Verification: Run firewall-cmd --get-active-zones to check which interfaces are currently mapped to which zones.

# NETWORK_INTERFACE=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v conn="$CONNECTION_NAME" '$1==conn {print $2; exit}')
# firewall-cmd --permanent --zone="$ZONE" --add-interface="$NETWORK_INTERFACE"

# # Verify
# firewall-cmd --get-active-zones

# #############################

