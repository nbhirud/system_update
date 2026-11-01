#!/bin/bash
# ==============================================================================
# Tailscale Mesh Setup: Hardened Fedora 44 with Exit Node Support
# Target: nbMain (Exit Node), nbAcer (Peer)
# Author: Lumo
# Date: 2026-06-13
# Purpose: Secure P2P mesh, Android masking via Exit Node, NextDNS integration.
# ==============================================================================

set -e


# ⚠️ Critical Pre-Flight Checklist

# Before running this, ensure you have these values ready:

#     TAILSCALE_DOMAIN_NAME: Your Tailscale domain (e.g., yourname.ts.net).
#     NEXTDNS_ID_NBMAIN: Your NextDNS profile ID for nbMain.
#     NEXTDNS_ID_NBAZER: Your NextDNS profile ID for nbAcer.

# Instructions:

#     Save the script below as setup_tailscale_mesh.sh.
#     Make it executable: chmod +x setup_tailscale_mesh.sh.
#     Run on nbMain first (it acts as the Exit Node).
#     Run on nbAcer second (standard peer).








# --- USER CONFIGURATION (MUST SET BEFORE RUNNING) ---
# Example: export TAILSCALE_DOMAIN_NAME="myname.ts.net"
# Example: export NEXTDNS_ID_NBMAIN="abc123"
export TAILSCALE_DOMAIN_NAME="${TAILSCALE_DOMAIN_NAME:-}" 
# export NEXTDNS_ID_NBMAIN="${NEXTDNS_ID_NBMAIN:-}"
# export NEXTDNS_ID_NBAZER="${NEXTDNS_ID_NBAZER:-}"
export TAILSCALE_LOGIN_METHOD="google" # Options: google, github, apple, email

# --- HARDWARE & HOSTNAME DETECTION ---
echo "🔍 Detecting system profile..."
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
HOSTNAME=$(hostname)
IS_EXIT_NODE=false

# Determine if this machine should act as an Exit Node
if [[ "$HOSTNAME" == "nbMain" ]]; then
    IS_EXIT_NODE=true
    WG_BUFFER_SIZE="1048576" # 1MB Buffer for high RAM
    LOG_LEVEL="info"
    echo "✅ Identified: $HOSTNAME (High-RAM Exit Node Candidate)"
else
    IS_EXIT_NODE=false
    WG_BUFFER_SIZE="262144" # 256KB Buffer for low RAM
    LOG_LEVEL="warning"
    echo "⚠️ Identified: $HOSTNAME (Standard Peer)"
fi

# Validate Domain
if [[ -z "$TAILSCALE_DOMAIN_NAME" ]]; then
    echo "❌ ERROR: TAILSCALE_DOMAIN_NAME is not set. Please export it before running."
    exit 1
fi

# --- DEPENDENCIES ---
echo "📦 Installing Tailscale & Security Tools..."
sudo dnf install -y tailscale firewalld nftables policycoreutils-python-utils

# --- IP FORWARDING (CRITICAL FOR EXIT NODE) ---
if $IS_EXIT_NODE; then
    echo "🌐 Enabling IPv4 Packet Forwarding for Exit Node..."
    echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-tailscale-forward.conf
    sudo sysctl -p /etc/sysctl.d/99-tailscale-forward.conf
else
    echo "ℹ️ Skipping IP forwarding (Standard Peer mode)."
fi

# --- FIREWALLD ZONE CONFIGURATION ---
echo "🛡️ Configuring Firewalld Zones..."
sudo firewall-cmd --permanent --new-zone=tailscale
sudo firewall-cmd --permanent --zone=tailscale --add-interface=tailscale0

# Allowed Services/Ports for Mesh Communication
sudo firewall-cmd --permanent --zone=tailscale --add-service=ssh
sudo firewall-cmd --permanent --zone=tailscale --add-port=8384/tcp # Syncthing
sudo firewall-cmd --permanent --zone=tailscale --add-port=1714-17646/udp # KDE Connect

# Masquerading (NAT) ONLY if acting as Exit Node
if $IS_EXIT_NODE; then
    echo "🔥 Enabling Masquerade (NAT) for Exit Node traffic..."
    sudo firewall-cmd --permanent --zone=tailscale --add-masquerade
fi

sudo firewall-cmd --reload
echo "✅ Firewall rules applied."

# --- SELINUX HARDENING ---
echo "🏛️ Securing SELinux contexts..."
sudo semanage fcontext -a -t var_lib_t "/var/lib/tailscale(/.*)?" || true
sudo restorecon -Rv /var/lib/tailscale || true

# --- SYSTEMD DAEMON TUNING ---
echo "⚙️ Applying systemd optimizations..."
sudo mkdir -p /etc/systemd/system/tailscaled.service.d
cat <<EOF | sudo tee /etc/systemd/system/tailscaled.service.d/optimization.conf
[Service]
Environment="TailscaleBufferSize=$WG_BUFFER_SIZE"
Environment="TS_DISABLE_TELEMETRY=1"
Environment="LOG_LEVEL=$LOG_LEVEL"
# DNS Config: Use system DNS (NextDNS via Router) + MagicDNS only
# No forced global resolvers to avoid conflict with Router-Proton setup
Environment="TS_DNS_CONFIG={\"resolvers\":[],\"options\":{}}"
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now tailscaled

# --- AUTHENTICATION ---
echo "🔐 Authenticating with Tailscale..."
CMD_ARGS=(
    "--login-server=https://controlplane.tailscale.com"
    "--accept-dns=false"      # Trust local router DNS (Proton/NextDNS)
    "--advertise-routes="     # No subnet routes advertised yet
    "--hostname=${HOSTNAME}-lumo"
    "--force-reauth"
)

if $IS_EXIT_NODE; then
    CMD_ARGS+=("--advertise-exit-node=true")
    echo "   🚀 Mode: EXIT NODE (Advertise enabled)"
else
    CMD_ARGS+=("--advertise-exit-node=false")
    echo "   🤝 Mode: STANDARD PEER"
fi

# Execute login
sudo tailscale up "${CMD_ARGS[@]}"

# --- POST-INSTALL VERIFICATION ---
sleep 3
echo "🔎 Validating Connection..."
if sudo tailscale status --json | grep -q '"Online":true'; then
    echo "✅ Tailscale is ONLINE."
    
    if $IS_EXIT_NODE; then
        if sudo tailscale status | grep -q "advertises exit node"; then
            echo "   ✅ Exit Node advertisement SUCCESSFUL."
            echo "   ⚠️ ACTION REQUIRED:"
            echo "      1. Go to https://login.tailscale.com/admin/machines"
            echo "      2. Find '${HOSTNAME}-lumo'"
            echo "      3. Toggle ON 'Use as Exit Node'."
        else
            echo "   ❌ Exit Node advertisement FAILED."
        fi
    fi
    
    # Test MagicDNS resolution (if peers exist)
    PEER=$(sudo tailscale status | grep -v "$HOSTNAME" | head -1 | awk '{print $1}')
    if [[ -n "$PEER" ]]; then
        echo "ℹ️ Testing ping to peer: ${PEER}"
        ping -c 2 "${PEER}" 2>/dev/null && echo "✅ Connectivity OK" || echo "⚠️ Peer offline or timeout"
    else
        echo "ℹ️ No peers online yet to test."
    fi
else
    echo "❌ Tailscale failed to connect. Check logs: journalctl -u tailscaled -f"
    exit 1
fi

echo "🎉 Setup Complete!"
echo "💡 Next Steps:"
echo "   1. If Exit Node: Enable toggle in Admin Console."
echo "   2. Update Syncthing/KDE Connect addresses to: <peer-name>.ts.net"
echo "   3. On Android: Select Exit Node -> ${HOSTNAME}-lumo in Tailscale app."




# Step-by-Step Execution Guide
# 1. Set Environment Variables

# On both machines (or just set them once locally before running):

# export TAILSCALE_DOMAIN_NAME="yourdomain.ts.net"
# export NEXTDNS_ID_NBMAIN="abc123"  # Replace with your actual IDs
# export NEXTDNS_ID_NBAZER="def456"

# 2. Run on nbMain

# ./setup_tailscale_mesh.sh

# Expected Output: "Mode: EXIT NODE". Action: Immediately go to Tailscale Admin Console, find nbMain-lumo, and toggle Use as exit node to ON.
# 3. Run on nbAcer

# ./setup_tailscale_mesh.sh

# Expected Output: "Mode: STANDARD PEER". Action: No admin console toggle needed.
# 4. Configure Android

#     Install Tailscale from Play Store/F-Droid.
#     Login.
#     Ensure MagicDNS is on (it usually is by default).
#     Go to Settings → Exit Nodes → Select nbMain-lumo.
#     Turn on Use Tailscale DNS (Optional, but recommended for privacy).
#     Open a browser, go to whatismyip.com. Verify it shows your Home IP (masked by Proton).

# 5. Update Syncthing & KDE Connect

# You must update the address to use the new .ts.net name so it works remotely.

#     Syncthing: Change device address from 192.168.x.x:8384 to nbAcer-lumo.yourdomain.ts.net:8384.
#     KDE Connect: Ensure devices are paired by hostname. It should auto-discover over the tunnel now.

# Final Verification

# Run this command on nbMain to confirm everything is locked down:

# firewall-cmd --get-active-zones

# Output should show:

#     tailscale zone containing tailscale0.
#     public (or home) zone containing your physical WiFi/Ethernet interface.
#     No overlap. This ensures local LAN discovery still works while Tailscale is active.

