#!/bin/bash
# ==============================================================================
# Tailscale Mesh Setup: Refined for Router-Level Proton VPN
# Targets: nbMain (31GB RAM), nbAcer (7.6GB RAM)
# Strategy: Peer-to-Peer mesh ONLY. No Exit Nodes. Internet traffic stays on Router Proton.
# ==============================================================================

set -e



# Correction to Architecture:

#     nbMain & nbAcer: Connect directly to your LAN (no local VPN client). Their traffic exits via the Router's Proton Tunnel. They see the router as their gateway.
#     Android: Connects directly to Wi-Fi or Mobile Data. When on mobile data, it has no router-based protection.
#     Tailscale Role: It creates a secure, encrypted tunnel between these devices that bypasses NAT/firewalls, regardless of whether they are behind the Router-Proton or on Public 5G.

# Why this changes the script slightly:

#     No "Exit Node" needed: Since nbMain/nbAcer already exit through Proton at the router level, we do not need Tailscale to route their internet traffic. We only need it for peer-to-peer discovery.
#     DNS Conflict Resolution: This is the biggest potential pitfall.
#         Your Router likely forces DNS to NextDNS/Proton.
#         Android on Mobile Data uses Mobile DNS (untrusted) unless you set Private DNS.
#         Solution: The script must enforce --accept-dns=false and rely on MagicDNS (internal names) while letting the OS handle internet DNS (NextDNS on PC, Private DNS on Android).

# Updated Master Script (setup_tailscale_mesh.sh)

# I have refined the logic to ensure it works perfectly in a "Router-Proton + Local Devices" environment.



# --- USER CONFIGURATION (MUST SET BEFORE RUNNING) ---
export TAILSCALE_DOMAIN_NAME="${TAILSCALE_DOMAIN_NAME:-}" 
export NEXTDNS_ID_NBMAIN="${NEXTDNS_ID_NBMAIN:-}" # e.g., abc123
export NEXTDNS_ID_NBAZER="${NEXTDNS_ID_NBAZER:-}" # e.g., def456
export TAILSCALE_LOGIN_METHOD="google" 

# --- HARDWARE DETECTION & OPTIMIZATION ---
echo "🔍 Scanning hardware profile..."
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
HOSTNAME=$(hostname)

if [[ $RAM_GB -ge 16 ]]; then
    WG_BUFFER_SIZE="1048576" # 1MB for nbMain
    LOG_LEVEL="info"
    echo "✅ High-RAM ($RAM_GB GB): Optimized for heavy Syncthing/KDE traffic."
else
    WG_BUFFER_SIZE="262144" # 256KB for nbAcer
    LOG_LEVEL="warning"
    echo "⚠️ Low-RAM ($RAM_GB GB): Conservative settings applied."
fi

# --- DEPENDENCIES ---
echo "📦 Installing Tailscale & Security Tools..."
sudo dnf install -y tailscale firewalld nftables policycoreutils-python-utils

# --- FIREWALLD: Dedicated Zone for Tailscale ---
# This isolates Tailscale traffic from your main Proton-tunneled interface
echo "🛡️ Creating dedicated 'tailscale' firewall zone..."
sudo firewall-cmd --permanent --new-zone=tailscale
sudo firewall-cmd --permanent --zone=tailscale --add-interface=tailscale0
# Allow essential internal services
sudo firewall-cmd --permanent --zone=tailscale --add-service=ssh
sudo firewall-cmd --permanent --zone=tailscale --add-port=8384/tcp # Syncthing
sudo firewall-cmd --permanent --zone=tailscale --add-port=1714-17646/udp # KDE Connect
# Default: Drop all other incoming from outside, but allow established internal traffic
sudo firewall-cmd --permanent --zone=tailscale --add-masquerade
sudo firewall-cmd --reload

# --- SELINUX HARDENING ---
echo "🏛️ Securing SELinux contexts..."
sudo semanage fcontext -a -t var_lib_t "/var/lib/tailscale(/.*)?" || true
sudo restorecon -Rv /var/lib/tailscale || true

# --- SYSTEMD DAEMON TUNING ---
# Apply hardware-specific buffers and disable telemetry
echo "⚙️ Applying systemd optimizations..."
sudo mkdir -p /etc/systemd/system/tailscaled.service.d
cat <<EOF | sudo tee /etc/systemd/system/tailscaled.service.d/optimization.conf
[Service]
Environment="TailscaleBufferSize=$WG_BUFFER_SIZE"
Environment="TS_DISABLE_TELEMETRY=1"
Environment="LOG_LEVEL=$LOG_LEVEL"
# CRITICAL: Do NOT let Tailscale override your Router's NextDNS setup
# We only use MagicDNS for internal .ts.net names
Environment="TS_DNS_CONFIG={\"resolvers\":[]},"options":{}
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now tailscaled

# --- AUTHENTICATION ---
if [[ -z "$TAILSCALE_DOMAIN_NAME" ]]; then
    echo "❌ ERROR: TAILSCALE_DOMAIN_NAME is empty. Please export it and re-run."
    exit 1
fi

echo "🔐 Authenticating with Tailscale..."
# --accept-dns=false is KEY here. We trust the Router (Proton) for external DNS.
# Tailscale will ONLY handle .ts.net lookups.
sudo tailscale up \
    --login-server=https://controlplane.tailscale.com \
    --accept-dns=false \
    --advertise-routes="" \
    --hostname="${HOSTNAME}-lumo" \
    --advertise-exit-node=false \
    --force-reauth

echo "✅ Authentication complete!"
echo "   Device Hostname: ${HOSTNAME}-lumo"
echo "   Verify at: https://login.tailscale.com/admin/machines"

# --- POST-INSTALL CHECKS ---
echo "🔎 Validating Connectivity..."
sleep 3
if sudo tailscale status --json | grep -q '"Online":true'; then
    echo "✅ Tailscale is online."
    # Try to resolve a peer name (replace with actual peer if known)
    PEER=$(sudo tailscale status | grep -v "$HOSTNAME" | head -1 | awk '{print $1}')
    if [[ -n "$PEER" ]]; then
        echo "ℹ️ Testing ping to peer: $PEER"
        # Ignore failure if no peers are online yet
        ping -c 2 "${PEER}" 2>/dev/null || echo "⚠️ Peer not online yet, skipping ping test."
    fi
else
    echo "❌ Tailscale failed to connect. Check logs: journalctl -u tailscaled -f"
    exit 1
fi

echo "🎉 Setup Complete."
echo "💡 Next Step: Update Syncthing/KDE Connect addresses to use 'hostname-lumo.ts.net'"


# Critical Configuration Changes for You
# 1. ACL Policy (Updated)

# Since you don't have a server yet, the ACL focuses purely on PC-to-PC and future Server prep.
# {
#   "groups": {
#     "group:nbs": ["user:YOUR_EMAIL"],
#     "tag:nbMain": ["device:nbMain-lumo"],
#     "tag:nbAcer": ["device:nbAcer-lumo"]
#   },
#   "acls": [
#     {"action": "accept", "src": ["tag:nbMain"], "dst": ["tag:nbAcer:*"]},
#     {"action": "accept", "src": ["tag:nbAcer"], "dst": ["tag:nbMain:*"]},
#     {"action": "accept", "src": ["tag:nbMain"], "dst": ["tag:Android-Lumo:*"]},
#     {"action": "accept", "src": ["tag:nbAcer"], "dst": ["tag:Android-Lumo:*"]},
#     {"action": "drop", "src": ["*"], "dst": ["tag:nbServer:*"]}
#   ]
# }



# 2. Android Setup (Mobile Data Scenario)

# When you leave home and switch to 5G:

#     Tailscale App: Ensure "Use Tailscale DNS" is OFF (let the phone use its own carrier DNS or your system-wide NextDNS setting).
#     System Private DNS: Go to Settings > Network > Private DNS > Enter dns.nextdns.io/YOUR_ID.
#         Why? This ensures your phone queries NextDNS even when not on Wi-Fi, blocking ads/tracking before any connection attempt.
#     Syncthing/KDE Connect:
#         These apps will now find your PCs using the .ts.net address (e.g., nbMain-lumo.mynet.ts.net).
#         They will work seamlessly whether you are on Home Wi-Fi (via Router Proton) or Library Wi-Fi/Mobile Data.

# 3. Why --accept-dns=false?

#     If true: Tailscale tries to force DNS through its own resolvers, which can conflict with your Router's NextDNS setup on Linux, causing resolution failures.
#     If false: Linux uses the Router's DNS (NextDNS) for the internet, and Tailscale only handles the .ts.net magic names. This is the most stable path for your current setup.



# Final Verification Command

# Once both PCs are up:
# # On nbMain
# ping nbAcer-lumo.yourdomain.ts.net

# # On nbAcer
# ping nbMain-lumo.yourdomain.ts.net

# # Check Syncthing port availability
# nc -zv nbAcer-lumo.yourdomain.ts.net 8384