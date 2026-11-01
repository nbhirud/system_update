#!/bin/bash
# ==============================================================================
# Tailscale Setup for nbMain (Exit Node Configuration)
# Role: Acts as the secure internet gateway for Android/Mobile devices.
# Hardware: High-RAM (31GB) - Optimized for traffic forwarding.
# ==============================================================================

set -e



# The New Strategy:

#     nbMain becomes the Exit Node: It has high RAM (31GB) and is always online behind Proton VPN at home. It acts as your secure gateway.
#     Android Routes ALL Traffic via nbMain: When you enable Tailscale on Android, it connects to nbMain, and nbMain sends your traffic out through the Router's Proton VPN.
#     Result: Websites see nbMain's home IP (masked by Proton), not your public library/mobile IP. You get the best of both worlds: Proton anonymity + Tailscale flexibility.

# ⚠️ Crucial Pre-requisites Before We Run the Script

# To make this work, nbMain must allow forwarding traffic. This requires a tiny tweak in two places:

#     Router Level: Your router must have "NAT Loopback" or "Hairpin NAT" enabled (usually default). If you are at home and trying to access a service hosted on nbMain via its own Tailscale IP, it might fail if the router blocks this.
#     Tailscale Admin Console: You must explicitly approve nbMain as an Exit Node.

# Step 1: Update the Master Script (setup_tailscale_mesh.sh)

# I have modified the script for nbMain to advertise itself as an exit node. nbAcer remains just a peer.

# Run this script ONLY on nbMain.



export TAILSCALE_DOMAIN_NAME="${TAILSCALE_DOMAIN_NAME:-}" 
export NEXTDNS_ID_NBMAIN="${NEXTDNS_ID_NBMAIN:-}" 

# --- HARDWARE DETECTION ---
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
HOSTNAME=$(hostname)

echo "🔍 Detected $HOSTNAME ($RAM_GB GB RAM). Configuring as EXIT NODE."
WG_BUFFER_SIZE="1048576" # 1MB Buffer
LOG_LEVEL="info"

# --- DEPENDENCIES & FIREWALL ---
echo "📦 Installing packages..."
sudo dnf install -y tailscale firewalld nftables policycoreutils-python-utils

# Enable IP Forwarding (CRITICAL for Exit Node functionality)
echo "🌐 Enabling IPv4 Packet Forwarding..."
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-tailscale-forward.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale-forward.conf

# --- FIREWALLD ZONE CONFIGURATION ---
echo "🛡️ Configuring Firewall Zones for Exit Node..."
sudo firewall-cmd --permanent --new-zone=tailscale
sudo firewall-cmd --permanent --zone=tailscale --add-interface=tailscale0
sudo firewall-cmd --permanent --zone=tailscale --add-service=ssh
sudo firewall-cmd --permanent --zone=tailscale --add-port=8384/tcp # Syncthing
sudo firewall-cmd --permanent --zone=tailscale --add-port=1714-17646/udp # KDE Connect

# Allow masquerading (NAT) for outbound traffic from Tailscale clients
# This redirects traffic from Tailscale IPs to the Router-Proton interface
sudo firewall-cmd --permanent --zone=tailscale --add-masquerade
sudo firewall-cmd --reload

# --- SELINUX ---
echo "🏛️ Securing SELinux..."
sudo semanage fcontext -a -t var_lib_t "/var/lib/tailscale(/.*)?" || true
sudo restorecon -Rv /var/lib/tailscale || true

# --- SYSTEMD DAEMON TUNING ---
sudo mkdir -p /etc/systemd/system/tailscaled.service.d
cat <<EOF | sudo tee /etc/systemd/system/tailscaled.service.d/optimization.conf
[Service]
Environment="TailscaleBufferSize=$WG_BUFFER_SIZE"
Environment="TS_DISABLE_TELEMETRY=1"
Environment="LOG_LEVEL=$LOG_LEVEL"
# DNS config: Only handle .ts.net names. Let system handle rest.
Environment="TS_DNS_CONFIG={\"resolvers\":[],\"options\":{}}"
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now tailscaled

# --- AUTHENTICATION AS EXIT NODE ---
echo "🔐 Authenticating as Exit Node..."
# Key flag: --advertise-exit-node=true
sudo tailscale up \
    --login-server=https://controlplane.tailscale.com \
    --accept-dns=false \
    --advertise-routes="" \
    --hostname="${HOSTNAME}-lumo" \
    --advertise-exit-node=true \
    --force-reauth

# --- VERIFICATION ---
sleep 3
if sudo tailscale status --json | grep -q '"Online":true'; then
    echo "✅ Tailscale Online."
    echo "🔥 Advertised Exit Node status: CHECKING..."
    if sudo tailscale status | grep -q "advertises exit node"; then
        echo "   ✅ Exit Node advertisement SUCCESSFUL."
        echo "   ⚠️ IMPORTANT: Go to https://login.tailscale.com/admin/machines"
        echo "      Find 'nbMain-lumo' and toggle ON 'Use as Exit Node'."
    else
        echo "   ❌ Exit Node advertisement FAILED. Check logs."
    fi
else
    echo "❌ Connection failed."
fi


Note: nbAcer runs the previous version of the script (with --advertise-exit-node=false).
Step 2: The Critical Admin Console Step

You must do this manually in the Tailscale web console; the script cannot do it automatically.

    Go to https://login.tailscale.com/admin/machines.
    Find the device named nbMain-lumo.
    Look for the toggle labeled "Use as exit node".
    Toggle it ON.
        If you skip this, Android will connect but will NOT route traffic.



Step 3: Android Configuration for Masking
Now, configure your phone to use this new gateway.

    Install/Update Tailscale App.
    Login to your account.
    Connect to the mesh.
    Activate Exit Node:
        Tap the Tailscale app icon.
        Tap the menu (three dots or gear icon).
        Select "Exit Node".
        Select nbMain-lumo.
    Verify Masking:
        Open Chrome/Firefox on your Android.
        Go to whatismyip.com.
        You should see the IP address of your Home Internet Connection (masked by Proton), NOT your Library/Mobile ISP IP.



Updated ACL Policy (For Safety)
Update your ACLs in the Admin Console to ensure nbMain can forward traffic to nbServer tags when you eventually set it up, and allow Android full internet access via nbMain.
{
  "groups": {
    "group:nbs": ["user:YOUR_EMAIL"],
    "tag:nbMain": ["device:nbMain-lumo"],
    "tag:nbAcer": ["device:nbAcer-lumo"],
    "tag:android": ["device:Android-Lumo"]
  },
  "acls": [
    {"action": "accept", "src": ["tag:android"], "dst": ["tag:nbMain:*"]},
    {"action": "accept", "src": ["tag:android"], "dst": ["tag:nbAcer:*"]},
    {"action": "accept", "src": ["tag:android"], "dst": ["*:*"]}, // Allow exit node traffic
    {"action": "accept", "src": ["tag:nbMain"], "dst": ["tag:nbAcer:*"]},
    {"action": "drop", "src": ["*"], "dst": ["tag:nbServer:*"]}
  ]
}

