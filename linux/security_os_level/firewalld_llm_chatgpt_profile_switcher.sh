#!/usr/bin/env bash
set -euo pipefail


####################################################################
# Save this as:
~/.local/bin/fw-profile

# Make executable:
chmod +x ~/.local/bin/fw-profile

# Usage:
fw-profile home
fw-profile public
fw-profile travel
fw-profile status

# Home mode improvement (recommended)
# Relpace following:
# --add-service=kdeconnect
# with
# --add-rich-rule='rule family="ipv4" source address="192.168.0.0/16" service name="kdeconnect" accept'

# Use travel profile with VPN

####################################################################

PROFILE="${1:-}"
INTERFACE="$(nmcli -t -f DEVICE,STATE d | grep ':connected' | cut -d: -f1 | head -n1)"

if [[ -z "$PROFILE" ]]; then
  echo "Usage: fw-profile {home|public|travel|status}"
  exit 1
fi

if [[ -z "$INTERFACE" ]]; then
  echo "No active network interface found."
  exit 1
fi

echo "[+] Using interface: $INTERFACE"

# -----------------------------
# Ensure firewalld is running
# -----------------------------
sudo systemctl enable --now firewalld >/dev/null

# -----------------------------
# Create zones if missing
# -----------------------------
for z in home public travel; do
  if ! firewall-cmd --get-zones | grep -qw "$z"; then
    echo "[+] Creating zone: $z"
    sudo firewall-cmd --permanent --new-zone="$z"
  fi
done

# -----------------------------
# Reset zones (clean state)
# -----------------------------
reset_zone() {
  local zone="$1"
  sudo firewall-cmd --permanent --zone="$zone" --remove-service=ssh || true
  sudo firewall-cmd --permanent --zone="$zone" --remove-service=http || true
  sudo firewall-cmd --permanent --zone="$zone" --remove-service=https || true
  sudo firewall-cmd --permanent --zone="$zone" --remove-service=kdeconnect || true
  sudo firewall-cmd --permanent --zone="$zone" --remove-port=5232/tcp || true
  sudo firewall-cmd --permanent --zone="$zone" --remove-port=8080/tcp || true
  sudo firewall-cmd --permanent --zone="$zone" --remove-port=8443/tcp || true
  sudo firewall-cmd --permanent --zone="$zone" --remove-port=5007/tcp || true
}

for z in home public travel; do
  reset_zone "$z"
done

# -----------------------------
# HOME PROFILE (trusted LAN)
# -----------------------------
echo "[+] Configuring HOME profile..."
sudo firewall-cmd --permanent --zone=home --set-target=ACCEPT

sudo firewall-cmd --permanent --zone=home --add-service=ssh
sudo firewall-cmd --permanent --zone=home --add-service=http
sudo firewall-cmd --permanent --zone=home --add-service=https
sudo firewall-cmd --permanent --zone=home --add-service=kdeconnect

sudo firewall-cmd --permanent --zone=home --add-port=5232/tcp
sudo firewall-cmd --permanent --zone=home --add-port=8080/tcp
sudo firewall-cmd --permanent --zone=home --add-port=8443/tcp
sudo firewall-cmd --permanent --zone=home --add-port=5007/tcp

# -----------------------------
# PUBLIC PROFILE (default safe)
# -----------------------------
echo "[+] Configuring PUBLIC profile..."
sudo firewall-cmd --permanent --zone=public --set-target=DROP

sudo firewall-cmd --permanent --zone=public --add-service=http
sudo firewall-cmd --permanent --zone=public --add-service=https

# Rate-limited SSH
sudo firewall-cmd --permanent --zone=public --add-rich-rule='
rule family="ipv4"
service name="ssh"
limit value="10/m"
accept
'

# -----------------------------
# TRAVEL PROFILE (paranoid)
# -----------------------------
echo "[+] Configuring TRAVEL profile..."
sudo firewall-cmd --permanent --zone=travel --set-target=DROP

# Optional: allow DNS + DHCP implicitly via system
# Only allow outbound (default behavior)

# Allow SSH ONLY if needed (comment out if not)
# sudo firewall-cmd --permanent --zone=travel --add-rich-rule='
# rule family="ipv4"
# service name="ssh"
# limit value="5/m"
# accept
# '

# -----------------------------
# Apply selected profile
# -----------------------------
case "$PROFILE" in
  home|public|travel)
    echo "[+] Switching to profile: $PROFILE"
    sudo firewall-cmd --set-default-zone="$PROFILE"
    sudo firewall-cmd --zone="$PROFILE" --change-interface="$INTERFACE"
    ;;
  status)
    firewall-cmd --get-active-zones
    exit 0
    ;;
  *)
    echo "Invalid profile: $PROFILE"
    exit 1
    ;;
esac

# -----------------------------
# Reload firewall
# -----------------------------
echo "[+] Reloading firewall..."
sudo firewall-cmd --reload

# -----------------------------
# Show result
# -----------------------------
echo "[+] Active zones:"
firewall-cmd --get-active-zones

echo "[✓] Profile '$PROFILE' applied."