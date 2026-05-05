#!/usr/bin/env bash
set -euo pipefail

####################################################################

# Create file (Create dispatcher script)
sudo nano /etc/NetworkManager/dispatcher.d/99-firewall-profile

# Make executable
sudo chmod +x /etc/NetworkManager/dispatcher.d/99-firewall-profile

# Move your fw-profile script (important)
# Dispatcher runs as root, so it cannot access your home directory reliably.
sudo cp ~/.local/bin/fw-profile /usr/local/bin/fw-profile
sudo chmod +x /usr/local/bin/fw-profile

# Restart NetworkManager
sudo systemctl restart NetworkManager

# Test
nmcli radio wifi off
nmcli radio wifi on

# Check
fw-profile status

#### Privacy upgrades doable:

# Default unknown networks → travel
PROFILE="travel"

# Avoid SSID spoofing risk. SSID names can be faked.
nmcli -t -f active,ssid,bssid dev wifi
# Then match BSSID (router MAC) instead of SSID.

# Lock KDE Connect to home only
# Already happens automatically via profile separation.

# VPN handling
# VPN → force travel OR public

# Ethernet networks
# This script only handles WiFi. If you use Ethernet, Add detection via:
nmcli -t -f DEVICE,TYPE,STATE dev


####################################################################

# INTERFACE="$1"
ACTION="$2"

# Only care about WiFi connect events
if [[ "$ACTION" != "up" && "$ACTION" != "vpn-up" ]]; then
  exit 0
fi

# Get SSID (WiFi only)
SSID="$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2 || true)"

# Path to your script
FW_PROFILE="$HOME/.local/bin/fw-profile"

# Fallback if run as root (dispatcher runs as root)
if [[ ! -x "$FW_PROFILE" ]]; then
  FW_PROFILE="/usr/local/bin/fw-profile"
fi

echo "[FW] Detected SSID: $SSID"

# -----------------------------
# CONFIGURE YOUR NETWORKS HERE
# -----------------------------

# HOME_SSID="YourHomeWiFi"
TRUSTED_SSIDS=("YourHomeWiFi" "PhoneHotspot")
SEMI_TRUSTED_SSIDS=("WorkWiFi")

# -----------------------------
# Decide profile
# -----------------------------
PROFILE="travel"   # default paranoid

for s in "${TRUSTED_SSIDS[@]}"; do
  if [[ "$SSID" == "$s" ]]; then
    PROFILE="home"
    break
  fi
done

for s in "${SEMI_TRUSTED_SSIDS[@]}"; do
  if [[ "$SSID" == "$s" ]]; then
    PROFILE="public"
    break
  fi
done

echo "[FW] Switching to profile: $PROFILE"

# -----------------------------
# Apply profile
# -----------------------------
"$FW_PROFILE" "$PROFILE"