#!/usr/bin/env bash

set -euo pipefail

# Ensure script is executed with root privileges
if [[ $EUID -ne 0 ]]; then
    echo "[!] Error: This script must be run as root (or with sudo)." >&2
    exit 1
fi

# Detect calling user when running via sudo to configure their local profile
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

echo "=== [1/5] Installing i2pd via Official COPR ==="
# Enable official COPR repo specified by i2pd documentation
dnf copr enable -y supervillain/i2pd
dnf install -y i2pd
# flatpak install flathub website.i2pd.i2pd

echo "=== [2/5] Configuring i2pd Daemon (Privacy & Local Binding) ==="
I2PD_CONF="/etc/i2pd/i2pd.conf"

# Backup default config if not already backed up
if [[ -f "$I2PD_CONF" && ! -f "${I2PD_CONF}.bak" ]]; then
    cp "$I2PD_CONF" "${I2PD_CONF}.bak"
fi

# Write hardened configuration
# Binds services strictly to 127.0.0.1 for local isolation

cat << 'I2PD_EOF' > "$I2PD_CONF"
# --- Hardened i2pd Configuration ---

# Enables routing over both IPv4 and IPv6 networks
ipv4 = true
ipv6 = true

# Web Console (Browser management interface)
[http]
enabled = true
address = 127.0.0.1
port = 7070
auth = false

# Outbound HTTP Proxy (for browsing .i2p sites)
[httpproxy]
enabled = true
address = 127.0.0.1
port = 4444

# Outbound SOCKS Proxy
[socksproxy]
enabled = true
address = 127.0.0.1
port = 4447

# SAM Bridge (API interface required by qBittorrent)
[sam]
enabled = true
address = 127.0.0.1
port = 7656

# Bandwidth and transport settings
# [limits]
# ntcp2.enabled = true

# The following port, if not set, changes every time system reboots. Makes it difficult to add to firewall rules.
[ntcp2]
enabled = true
port = 16922

I2PD_EOF



# Enable and start i2pd systemd daemon
systemctl enable --now i2pd

# Verification check: Ensure i2pd service started successfully
if systemctl is-active --quiet i2pd; then
    echo "[✓] i2pd daemon is active and running."
else
    echo "[!] Warning: i2pd failed to start. Check 'systemctl status i2pd'." >&2
fi

echo "=== [3/5] Security Hardening (Firewalld & SELinux) ==="
# Ensure loopback traffic (127.0.0.1) is explicitly trusted by Firewalld
firewall-cmd --permanent --zone=trusted --add-interface=lo 2>/dev/null || true
firewall-cmd --reload

# Allow local network/daemon connections under SELinux boolean rules
setsebool -P nis_enabled 1 2>/dev/null || true

#############################################################

# echo "=== [4/5] Automating qBittorrent Configuration ==="
# QBT_DIR="${TARGET_HOME}/.config/qBittorrent"
# QBT_CONF="${QBT_DIR}/qBittorrent.conf"

# mkdir -p "$QBT_DIR"

# # Inject or update SAM Bridge settings in qBittorrent's configuration file
# if [[ ! -f "$QBT_CONF" ]]; then
#     cat << 'EOF' > "$QBT_CONF"
# [Preferences]
# Bittorrent\I2P\Address=127.0.0.1
# Bittorrent\I2P\Enabled=true
# Bittorrent\I2P\Port=7656
# Bittorrent\I2P\InboundQuantity=3
# Bittorrent\I2P\OutboundQuantity=3
# Bittorrent\I2P\MixedMode=true
# EOF
# else
#     # Remove old I2P keys if present and append updated SAM parameters
#     sed -i '/Bittorrent\\I2P/d' "$QBT_CONF"
#     cat << 'EOF' >> "$QBT_CONF"
# Bittorrent\I2P\Address=127.0.0.1
# Bittorrent\I2P\Enabled=true
# Bittorrent\I2P\Port=7656
# Bittorrent\I2P\InboundQuantity=3
# Bittorrent\I2P\OutboundQuantity=3
# Bittorrent\I2P\MixedMode=true
# EOF
# fi

# # Reset directory ownership back to the non-root target user
# chown -R "${TARGET_USER}:" "$QBT_DIR"

#############################################################

# sudo firewall-cmd --get-active-zones 
# # Assuming your active zone is public:

sudo firewall-cmd --permanent --zone=public --add-port=16922/tcp
sudo firewall-cmd --permanent --zone=public --add-port=16922/udp

# Note: We have harcoded this port, so IGNORE the explaination below:
# This port changes, so automated this identification below after explaination
# 16922 is not a universal/fixed i2pd port. In your setup, it is the port i2pd selected/configured for its I2P transport. 
# It can differ between installations and can potentially change.
# | Port    | Purpose                                            |              Your PC     |
# | ------- | -------------------------------------------------- | -----------------------: |
# | `7656`  | SAM interface for applications such as qBittorrent |        **Fixed/default** |
# | `7070`  | Web console                                        |   **Configured/default** |
# | `4447`  | SOCKS proxy                                        |   **Configured/default** |
# | `16922` | I2P network transport                              | **Your instance's port** | This one varies

# # To identify this port, 
# sudo ss -lntup | grep i2pd
# # In your output:
# udp ... 0.0.0.0:16922 ... i2pd-daemon
# tcp ... 0.0.0.0:16922 ... i2pd-daemon
# # Therefore:
# I2P transport port = 16922

# # If you want a stable port, You can explicitly configure one, which is useful if you eventually want router port forwarding. For example:
# port = 16922
# in /etc/i2pd/i2pd.conf.

# I2P_PORT=$(sudo ss -H -lntup |
#     awk '$0 ~ /i2pd-daemon/ && $0 ~ /0\.0\.0\.0:/ {
#         n=split($5,a,":"); print a[n]; exit
#     }')

# sudo firewall-cmd --permanent --zone=public --add-port="$I2P_PORT"/tcp
# sudo firewall-cmd --permanent --zone=public --add-port="$I2P_PORT"/udp

sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --zone=public --list-ports

#############################################################

echo "=== [5/5] How to Verify the Setup ==="
echo "1. Web Console: http://127.0.0.1:7070 - verify router integrated tunnel status."
echo "2. qBittorrent Settings: Open qBittorrent -> Tools -> Options -> Connection."
echo "   Verify 'I2P' is checked with Host: 127.0.0.1 and Port: 7656."
echo "3. Verification Step: Add an .i2p magnet link or tracker torrent in qBittorrent."
echo "   In the Bottom Panel under 'General', check if an I2P info hash / SAM status gets created."






#############################################################
#############################################################
# Testing
#############################################################
#############################################################

# i2pd web console
# http://127.0.0.1:7070


# systemctl status i2pd

# systemctl status i2pd.service
# journalctl -xeu i2pd.service

# ss -tulpn | grep 7656

# sudo nano /etc/i2pd/i2pd.conf




# # QBittorrent
# # Tools → Options → Connection
# # It will have:
# Enable I2P
# Host: 127.0.0.1
# Port: 7656
# Mixed mode: OFF
# Enable I2P Peer Exchange (I2P PeX): ON
# # Change to
# | qBittorrent I2P option | Setting     |
# | ---------------------- | ----------- |
# | Enable I2P             | **ON**      |
# | Host                   | `127.0.0.1` |
# | Port                   | `7656`      |
# | Mixed mode             | **OFF**     |
# | I2P PeX                | **ON**      |




# Test the SAM connection
# Before testing qBittorrent, verify the port:
# # sudo dnf install nmap-ncat
# nc -vz 127.0.0.1 7656
# Expected:
# Connection to 127.0.0.1 7656 port [tcp/*] succeeded!


# You want the router to eventually show healthy connectivity rather than immediately testing qBittorrent and concluding that it doesn't work.
# I2P is fundamentally different from Tor: routers maintain long-lived tunnels, and the network needs time to establish routing information
# # Go to: http://127.0.0.1:7070


# sudo journalctl -u i2pd --since "10 minutes ago" --no-pager



# curl -s http://127.0.0.1:7070 | grep -iE 'transports|tunnels|exploratory|network|reachable' | head -30

# sudo grep -vE '^\s*(#|$)' /etc/i2pd/tunnels.conf 2>/dev/null

# sudo ss -lntup | grep i2pd

# sudo firewall-cmd --get-active-zones

# sudo firewall-cmd --permanent --zone=public --add-port=16922/tcp
# sudo firewall-cmd --permanent --zone=public --add-port=16922/udp
# sudo firewall-cmd --reload

# sudo firewall-cmd --zone=public --list-ports


# # You should see a connection involving: 127.0.0.1:7656
# sudo ss -ntp | grep 7656
# watch -n 1 'sudo ss -ntp | grep 7656'


# # You should see i2pd's actual I2P transport traffic.
# sudo tcpdump -ni lo port 7656


# Look for an explicitly configured port:
# sudo grep -RniE '^[[:space:]]*(port|ipv4|ipv6|ntcp2|ssu2)' \
#     /etc/i2pd/

# Also check the main configuration:
# sudo grep -nE '^[[:space:]]*port[[:space:]]*=' /etc/i2pd/i2pd.conf

