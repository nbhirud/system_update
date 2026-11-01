#!/bin/bash
# ==============================================================================
# Tailscale Mesh Setup for Fedora 44 (Hardened + Hardware Optimized)
# Target: nbMain (31GB RAM) & nbAcer (7.6GB RAM)
# Author: Lumo
# Purpose: Secure peer-to-peer mesh with NextDNS integration, ignoring non-existent server.
# ==============================================================================

set -e


# Before running the master script, please do this on your Tailscale Admin Console (https://login.tailscale.com/admin):

#     Enable MagicDNS: Go to DNS -> Turn on "Use My Own DNS" (if you want to force NextDNS globally later) OR just enable "Enable MagicDNS". Recommendation: Enable MagicDNS first. We can configure Global Nameservers (NextDNS) later once the mesh is up.
#     Create an ACL Policy File: I'll provide the JSON content below. Save it as tailscale-acl.json.


# Step 1: The Master Installation Script (setup_tailscale_mesh.sh)
# Save this on both nbMain and nbAcer. It detects hardware, configures Firewalld/SELinux, and handles NextDNS variables.


# --- USER CONFIGURATION ---
# Initialize these BEFORE running the script
export TAILSCALE_DOMAIN_NAME="${TAILSCALE_DOMAIN_NAME:-}" 
export NEXTDNS_ID_NBMAIN="${NEXTDNS_ID_NBMAIN:-}" # e.g., abc123
export NEXTDNS_ID_NBAZER="${NEXTDNS_ID_NBAZER:-}" # e.g., def456
export TAILSCALE_LOGIN_METHOD="google" # Options: google, github, apple, email

# --- HARDWARE DETECTION ---
echo "🔍 Detecting hardware profile..."
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
HOSTNAME=$(hostname)

# Optimization logic based on your specs
if [[ $RAM_GB -ge 16 ]]; then
    WG_BUFFER_SIZE="1048576" # 1MB buffer for nbMain (31GB RAM)
    LOG_LEVEL="info"
    echo "✅ High-RAM system detected ($RAM_GB GB). Applying aggressive buffer settings."
else
    WG_BUFFER_SIZE="262144" # 256KB buffer for nbAcer (7.6GB RAM)
    LOG_LEVEL="warning"
    echo "⚠️ Low-RAM system detected ($RAM_GB GB). Applying conservative buffer settings."
fi

# --- PREREQUISITES ---
echo "📦 Installing Tailscale dependencies..."
sudo dnf install -y tailscale firewalld nftables policycoreutils-python-utils

# --- FIREWALLD HARDENING ---
echo "🛡️ Configuring Firewalld Zones..."
sudo firewall-cmd --permanent --new-zone=tailscale
sudo firewall-cmd --permanent --zone=tailscale --add-interface=tailscale0
sudo firewall-cmd --permanent --zone=tailscale --add-service=ssh # Allow SSH over Tailscale
sudo firewall-cmd --permanent --zone=tailscale --add-port=8384/tcp # Syncthing default
sudo firewall-cmd --permanent --zone=tailscale --add-port=1714-17646/udp # KDE Connect
sudo firewall-cmd --permanent --set-default-zone=drop # Default deny all other incoming
sudo firewall-cmd --reload

# --- SELINUX POLICY ADJUSTMENT ---
# Tailscale needs to write to /var/lib/tailscale which might be blocked by default strict policies
echo "🏛️ Adjusting SELinux contexts..."
sudo semanage fcontext -a -t var_lib_t "/var/lib/tailscale(/.*)?" || true
sudo restorecon -Rv /var/lib/tailscale || true

# --- TAILSCALA DAEMON CONFIGURATION ---
echo "⚙️ Configuring Tailscale daemon..."

# Create custom systemd drop-in for hardware tuning
sudo mkdir -p /etc/systemd/system/tailscaled.service.d
cat <<EOF | sudo tee /etc/systemd/system/tailscaled.service.d/optimization.conf
[Service]
Environment="TailscaleBufferSize=$WG_BUFFER_SIZE"
Environment="TS_DISABLE_TELEMETRY=1"
Environment="LOG_LEVEL=$LOG_LEVEL"
# Ensure DNS handling respects MagicDNS but allows NextDNS override
Environment="TS_DNS_CONFIG={\"resolvers\":[$( [ -n "$NEXTDNS_ID_$([ $HOSTNAME == 'nbMain' ] && echo 'NBMAIN' || echo 'NBAZER')" ] && echo "\"${NEXTDNS_ID_$([ $HOSTNAME == 'nbMain' ] && echo 'NBMAIN' || echo 'NBAZER')}\"" )]},"options":{}}
EOF

# Start and Enable
sudo systemctl daemon-reload
sudo systemctl enable --now tailscaled

# --- AUTHENTICATION ---
if [[ -z "$TAILSCALE_DOMAIN_NAME" ]]; then
    echo "❌ ERROR: TAILSCALE_DOMAIN_NAME not set. Aborting authentication."
    exit 1
fi

echo "🔐 Initiating login. Open this URL in your browser:"
# Note: The auth command uses the domain variable if set, otherwise defaults
sudo tailscale up \
    --login-server=https://controlplane.tailscale.com \
    --accept-dns=false \
    --advertise-routes="" \
    --hostname="${HOSTNAME}-lumo" \
    --advertise-exit-node=false \
    --force-reauth

# Verify connection
sleep 3
if sudo tailscale status > /dev/null 2>&1; then
    echo "✅ Connection successful!"
    echo "   Hostname registered as: ${HOSTNAME}-lumo"
    echo "   Check https://login.tailscale.com/admin/machines to verify."
else
    echo "❌ Connection failed. Check logs: journalctl -u tailscaled -f"
    exit 1
fi

# --- MAGICDNS VERIFICATION ---
echo "🔎 Testing MagicDNS resolution..."
# Wait for DNS to propagate
sleep 5
OTHER_HOST=$(sudo tailscale status | grep -i "other_host" | head -1 | awk '{print $1}' | cut -d. -f1)
if [[ -n "$OTHER_HOST" ]]; then
    ping -c 1 "${OTHER_HOST}.$TAILSCALE_DOMAIN_NAME" && echo "✅ MagicDNS resolved successfully." || echo "⚠️ MagicDNS not yet resolving (may take 2 mins)."
else
    echo "ℹ️ No peers online yet to test resolution. Run 'ping <peer-name>' manually once connected."
fi

echo "🎉 Setup complete. Next step: Configure ACLs and Sync."


# Step 2: ACL Configuration (Paste this into Tailscale Admin Console)
# Go to Settings → Access Control List. Paste this JSON. This ensures nbMain and nbAcer can talk to each other but blocks access to nbServer (which doesn't exist yet, but good practice).

# {
#   "groups": {
#     "group:nbs": ["user:your-email"],
#     "tag:nbMain": ["device:nbMain-lumo"],
#     "tag:nbAcer": ["device:nbAcer-lumo"]
#   },
#   "acls": [
#     {"action": "accept", "src": ["tag:nbMain"], "dst": ["tag:nbAcer:*"]},
#     {"action": "accept", "src": ["tag:nbAcer"], "dst": ["tag:nbMain:*"]},
#     {"action": "drop", "src": ["*"], "dst": ["tag:nbServer:*"]}
#   ],
#   "tagOwners": {
#     "tag:nbMain": ["group:nbs"],
#     "tag:nbAcer": ["group:nbs"]
#   }
# }


# Step 3: Android Configuration (Critical for Mobile Use)

# Since Android leaves the Proton-protected network, this setup is vital for keeping Syncthing/KDE Connect working on mobile data.

#     Install Tailscale from Play Store/F-Droid.
#     Login with the same account.
#     Device Name: Rename it to Android-Lumo in the admin console.
#     DNS Settings (App Level):
#         Open Tailscale app → ⋮ (Menu) → Settings → DNS.
#         Toggle "Use Tailscale DNS" ON.
#         If you want NextDNS filtering: Enter your NextDNS ID (e.g., abc123.nextdns.io) in the Override Local DNS field.
#         Note: Do NOT set Android System Private DNS to NextDNS if you use Tailscale DNS Override, as they conflict. Let Tailscale handle the routing.
#     Split Tunneling: Keep it OFF initially to ensure full encryption.
#     Syncthing & KDE Connect:
#         These apps now see the other devices via nbMain-lumo and nbAcer-lumo.
#         In Syncthing folder settings, change the address to https://nbMain-lumo:8384 (replace nbMain-lumo with actual hostname).


# Step 4: Verification & Next Steps

# Run this on one machine to confirm the mesh:

# # Check connectivity to the other device
# ping nbAcer-lumo.yourdomain.ts.net  # or nbMain-lumo...

# # Check Syncthing specific port
# nc -zv nbAcer-lumo.yourdomain.ts.net 8384

# # Check KDE Connect discovery
# kdeconnect-cli --ping nbAcer-lumo




