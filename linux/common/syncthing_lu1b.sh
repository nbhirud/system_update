#!/bin/bash
#===============================================================================
# wireguard-syncthing-setup.sh
# Purpose: Set up WireGuard mesh network for secure Syncthing GUI access
# Author: Generated for Nik's privacy-first multi-machine stack
# Date: 2025-11-20
# Requires: sudo, Fedora Kernel headers, NextDNS integration variable
#===============================================================================

set -euo pipefail



# Here's your SSH Tunnel + WireGuard setup guide for secure remote Syncthing GUI access. Both methods keep the management interface closed to public networks while maintaining your privacy-first stack.
# Quick Comparison
# Method	Setup Time	Reusability	Best For
# SSH Tunnel	2 minutes	One-time command	Ad-hoc remote access
# WireGuard Peer	15 minutes	Persistent network	Daily multi-device workflow
# Method 1: SSH Tunnel (Quick Start)

# This requires no additional services—just SSH on the Syncthing host.
# 1. Host Side (Syncthing Machine)

# Ensure SSH is running on your Syncthing host:

# sudo dnf install openssh-server
# sudo systemctl enable --now sshd
# sudo firewall-cmd --add-service=ssh --permanent
# sudo firewall-cmd --reload

# 2. Client Side (Your Laptop/Tablet/Phone)

# From the device you want to access Syncthing GUI from:

# # Create persistent SSH tunnel
# ssh -N -L 8384:127.0.0.1:8384 \
#     -i ~/.ssh/id_ed25519 \          # Your private key path
#     -o "IdentitiesOnly=yes" \        # Force specific key
#     -o "ServerAliveInterval=60" \    # Keep connection alive
#     nik@SYNCTHING_HOST_IP            # Replace with actual IP/hostname

# 3. Access via Browser

# Once the tunnel is active, open:

# https://127.0.0.1:8384

# LibreWolf will trust it automatically if you imported the CA in the previous script.
# Method 2: WireGuard Persistent Mesh Network (Recommended for You)

# Given your stack (Tor, I2p, Proton VPN, privacy focus), WireGuard fits perfectly—it creates an encrypted peer-to-peer tunnel across all your devices.

# Below is a complete, automated setup script tailored for your Fedora + NextDNS configuration.

# Save as wireguard-syncthing-setup.sh.



#-------------------------------------------------------------------------------
# CONFIGURATION - Initialize NEXTDNS_ID before running
#-------------------------------------------------------------------------------
NEXTDNS_ID="${NEXTDNS_ID:-}"       # Your NextDNS UUID (optional)

# WireGuard Network Configuration
WG_NETWORK="10.66.66.0/24"         # Private WG subnet
HOST_PRIVATE_KEY=""                # Auto-generated below
HOST_PUBLIC_KEY=""                 # Auto-generated below
HOST_PORT="51820"                  # UDP port for WireGuard
HOST_LAN_IP="$(ip route get 1.1.1.1 | awk '{print $7}')"  # Auto-detect LAN IP

# Peer Device Info (Add each peer separately)
PEER_NAME=""                       # e.g., "laptop-nik", "android-phone"
PEER_PUBLIC_KEY=""                 # From wg genkey | wg pubkey
PEER_ALLOWED_IPS="10.66.66.2"      # Unique IP per peer
PEER_ENDPOINT=""                   # Public IP:port or DynDNS endpoint

# Installation Paths
SYSTEMD_DIR="/etc/systemd/system"
WIREGUARD_CONF_DIR="/etc/wireguard"
LOG_FILE="/var/log/wg-setup.log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
log_error()   { echo -e "${RED}[✗]${NC} $*" >&2; }

#-------------------------------------------------------------------------------
# HARDWARE DETECTION & OPTIMIZATION
#-------------------------------------------------------------------------------
detect_hardware() {
    log_info "Detecting system resources..."
    
    TOTAL_RAM_GB=$(free -g | awk '/^Mem:/ {print $2}')
    CPU_CORES=$(nproc)
    
    if [[ $TOTAL_RAM_GB -gt 12 ]]; then
        log_info "High RAM detected (${TOTAL_RAM_GB}GB) - enabling full caching"
    elif [[ $TOTAL_RAM_GB -lt 8 ]]; then
        log_warn "Low RAM (${TOTAL_RAM_GB}GB). Consider disabling unnecessary WG peers."
    fi
    
    # Check if Intel GPU (you mentioned GTX 960M or Intel integrated)
    if lspci | grep -i nvidia &>/dev/null; then
        log_info "NVIDIA GPU present - WireGuard uses CPU only, noted"
    fi
    
    log_info "CPU cores: ${CPU_CORES}, RAM: ${TOTAL_RAM_GB}GB"
}

#-------------------------------------------------------------------------------
# PRE-FLIGHT CHECKS
#-------------------------------------------------------------------------------
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Kernel modules
    if ! modprobe wireguard &>/dev/null; then
        log_info "Installing WireGuard kernel module..."
        sudo dnf install -y wireguard-tools iproute-tc
    fi
    
    # Required tools
    if ! command -v wg &>/dev/null; then
        log_error "WireGuard tool 'wg' not found. Run: sudo dnf install wireguard-tools"
        exit 1
    fi
    
    # SELinux check
    if sestatus 2>/dev/null | grep -q "Enabled"; then
        log_info "SELinux detected - will configure appropriate contexts"
    fi
}

#-------------------------------------------------------------------------------
# GENERATE KEYPAIR FOR HOST
#-------------------------------------------------------------------------------
generate_host_keypair() {
    if [[ -z "$HOST_PRIVATE_KEY" ]] || [[ -z "$HOST_PUBLIC_KEY" ]]; then
        log_info "Generating WireGuard keypair for host..."
        
        PRIVATE_KEY_PATH="${WIREGUARD_CONF_DIR}/private.key"
        mkdir -p "${WIREGUARD_CONF_DIR}"
        chmod 700 "${WIREGUARD_CONF_DIR}"
        
        # Generate private key
        umask 077
        wg genkey > "${PRIVATE_KEY_PATH}"
        chmod 600 "${PRIVATE_KEY_PATH}"
        
        # Generate public key
        wg pubkey < "${PRIVATE_KEY_PATH}" > "${WIREGUARD_CONF_DIR}/public.key"
        chmod 644 "${WIREGUARD_CONF_DIR}/public.key"
        
        export HOST_PRIVATE_KEY=$(cat "${PRIVATE_KEY_PATH}")
        export HOST_PUBLIC_KEY=$(cat "${WIREGUARD_CONF_DIR}/public.key")
        
        log_success "Keypair generated. Save public key for peer config:"
        log_info "${HOST_PUBLIC_KEY}"
    fi
}

#-------------------------------------------------------------------------------
# CREATE HOST CONFIG
#-------------------------------------------------------------------------------
create_host_config() {
    local PEER_NAME="${1:-peer}"
    local PEER_PK="${2:-}"
    local PEER_IP="${3:-10.66.66.$RANDOM}"
    local PEER_EP="${4:-}"
    
    log_info "Creating WireGuard host configuration..."
    
    cat > "${WIREGUARD_CONF_DIR}/wg0.conf" <<EOF
# WireGuard Interface - Secure Syncthing GUI Access
# File: /etc/wireguard/wg0.conf
# Security: Restricted permissions, no telemetry

[Interface]
PrivateKey = ${HOST_PRIVATE_KEY}
Address = 10.66.66.1/24
ListenPort = ${HOST_PORT}
MTU = 1420                          # Optimized MTU for most networks
PostUp = firewall-cmd --add-port=${HOST_PORT}/udp --permanent && firewall-cmd --reload
PostDown = firewall-cmd --remove-port=${HOST_PORT}/udp --permanent && firewall-cmd --reload
PreUp = ip link set dev wg0 down 2>/dev/null || true
PreDown = ip link set dev wg0 down 2>/dev/null || true

# NAT forwarding if you want peers to access LAN resources
# PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
# PostUp = iptables -t nat -A POSTROUTING -s ${WG_NETWORK} -o eth0 -j MASQUERADE
# PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
# PostDown = iptables -t nat -D POSTROUTING -s ${WG_NETWORK} -o eth0 -j MASQUERADE

# DNS settings - respects your NextDNS preference
# dns_servers="${NEXTDNS_ID}"       # Uncomment if configured in OS

[Peer]
PublicKey = ${PEER_PK}
AllowedIPs = ${PEER_IP}/32
Endpoint = ${PEER_EP}                # Optional: IP:port for active connections
PersistentKeepalive = 25             # Keep NAT holes open every 25s
EOF

    chmod 600 "${WIREGUARD_CONF_DIR}/wg0.conf"
    
    # SELinux context
    if command -v semanage &>/dev/null; then
        semanage fcontext -a -t etc_t "/etc/wireguard(/.*)?" 2>/dev/null || true
        restorecon -Rv "${WIREGUARD_CONF_DIR}" 2>/dev/null || true
    fi
}

#-------------------------------------------------------------------------------
# CREATE PEER CONFIG TEMPLATE
#-------------------------------------------------------------------------------
create_peer_config_template() {
    log_info "Creating peer configuration template..."
    
    cat > "${WIREGUARD_CONF_DIR}/peer-template.conf" <<EOF
# WireGuard Peer Configuration Template
# Save as: ~/wg-peer-${PEER_NAME}.conf
# Copy to peer device and import via wg-quick

[Interface]
PrivateKey = $(wg genkey)           # Generate on peer device!
Address = ${PEER_ALLOWED_IPS}/32
ListenPort = 51821                  # Different from host port to avoid conflicts
MTU = 1420
# DNS: Use your NextDNS at client level or default
# DNS = 10.66.66.1                  # Point to host if you want custom DNS

[Peer]
# Host (Syncthing machine) public key
PublicKey = ${HOST_PUBLIC_KEY}
AllowedIPs = 10.66.66.1/32          # Only host over WG
Endpoint = YOUR_PUBLIC_IP:${HOST_PORT}  # Set your external IP/DNS here
PersistentKeepalive = 25
EOF

    chmod 600 "${WIREGUARD_CONF_DIR}/peer-template.conf"
    
    log_info "Template saved to ${WIREGUARD_CONF_DIR}/peer-template.conf"
    log_info "Generate your peer private key: wg genkey"
    log_info "Send public key back for final host config update"
}

#-------------------------------------------------------------------------------
# SYSTEMD SERVICE SETUP
#-------------------------------------------------------------------------------
create_systemd_service() {
    log_info "Creating systemd service for auto-start..."
    
    cat > "${SYSTEMD_DIR}/wg-quick@wg0.service" <<EOF
[Unit]
Description=WireGuard interface wg0
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/wg-quick up wg0
ExecStop=/usr/bin/wg-quick down wg0
TimeoutSec=0

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable wg-quick@wg0
    log_success "Systemd service enabled - starts on boot"
}

#-------------------------------------------------------------------------------
# FIREWALL CONFIGURATION
#-------------------------------------------------------------------------------
configure_firewall() {
    log_info "Configuring firewalld rules..."
    
    # Open WireGuard port (UDP required)
    if ! firewall-cmd --query-port=${HOST_PORT}/udp &>/dev/null; then
        firewall-cmd --add-port=${HOST_PORT}/udp --permanent
        log_info "Open firewall port ${HOST_PORT}/udp for WireGuard"
    fi
    
    # Ensure Syncthing sync port remains open
    if ! firewall-cmd --query-port=22000/tcp &>/dev/null; then
        firewall-cmd --add-port=22000/tcp --permanent
        log_info "Open firewall port 22000/tcp for Syncthing"
    fi
    
    # Block GUI port externally (default from earlier script)
    if firewall-cmd --query-port=8384/tcp &>/dev/null; then
        log_info "Ensuring GUI port 8384/tcp is NOT exposed externally"
    fi
    
    firewall-cmd --reload
    log_success "Firewall configuration complete"
}

#-------------------------------------------------------------------------------
# ANDROID CLIENT SETUP GUIDE
#-------------------------------------------------------------------------------
generate_android_guide() {
    log_info "Android peer configuration guide:"
    
    cat <<EOF
=============================================================
ANDROID WIREGUARD SETUP
=============================================================

1. Install "WireGuard" app from F-Droid (FOSS) or Play Store

2. Import peer configuration:
   - Open WireGuard app → "+" → "Import tunnel(s) from file"
   - Copy content from peer-template.conf

3. Modify BEFORE importing:
   - PrivateKey: Generate fresh on Android (app does this)
   - Endpoint: Set to YOUR_PUBLIC_IP:51820 (or your DynDNS)

4. Get Android's public key from app after import
5. Send to host, add as new [Peer] section in wg0.conf

6. Connect toggle in WireGuard app

7. Access Syncthing GUI:
   - Browser URL: https://10.66.66.1:8384
   
NOTE: LibreWolf on Linux will trust the cert if you imported CA
On Android, use Firefox/FDroid + accept self-signed once
=============================================================
EOF
}

#-------------------------------------------------------------------------------
# SUMMARY AND NEXT STEPS
#-------------------------------------------------------------------------------
print_summary() {
    clear
    echo ""
    echo "=============================================="
    echo "  WireGuard Network Setup Complete"
    echo "=============================================="
    echo ""
    echo "Host Configuration:"
    echo "  Interface IP:      10.66.66.1/24"
    echo "  Listening Port:    ${HOST_PORT}/udp"
    echo "  Public Key:        ${HOST_PUBLIC_KEY}"
    echo "  Config Location:   ${WIREGUARD_CONF_DIR}/wg0.conf"
    echo ""
    echo "Next Steps:"
    echo "  1. Activate interface: systemctl start wg-quick@wg0"
    echo "  2. Generate peer config: ./create_peer_config_for_laptop.sh"
    echo "  3. Import CA on peer devices for cert trust"
    echo ""
    echo "Access Pattern:"
    echo "  From Peer Device: https://10.66.66.1:8384"
    echo "  From Browser:     LibreWolf/LibreOffice/etc"
    echo ""
    log_info "To add another peer, run this script again with different PEER_NAME"
    echo ""
}

#-------------------------------------------------------------------------------
# MAIN EXECUTION
#-------------------------------------------------------------------------------
main() {
    case "${1:-setup}" in
        setup)
            check_prerequisites
            detect_hardware
            generate_host_keypair
            create_host_config "${PEER_NAME:-first-peer}" "${PEER_PUBLIC_KEY:-}" "${PEER_ALLOWED_IPS:-}" "${PEER_ENDPOINT:-}"
            create_peer_config_template
            create_systemd_service
            configure_firewall
            generate_android_guide
            print_summary
            ;;
        add-peer)
            echo "Usage: Provide PEER_NAME, PEER_PUBLIC_KEY, PEER_ALLOWED_IPS, PEER_ENDPOINT"
            echo "Example: PEER_NAME=laptop-nik PEER_PUBLIC_KEY='xxx' PEER_ALLOWED_IPS='10.66.66.2' PEER_ENDPOINT='your.ddns.net:51820'"
            ;;
        *)
            echo "Unknown option: ${1}"
            exit 1
            ;;
    esac
}

main "$@"


# Implementation Workflow
# Step 1: Run Initial Script on Syncthing Host

# # Set your NextDNS ID first
# export NEXTDNS_ID="YOUR_NEXTDNS_UUID"

# # Make executable and run
# chmod +x wireguard-syncthing-setup.sh
# ./wireguard-syncthing-setup.sh

# Step 2: Configure Each Peer Device

# On each additional PC/laptop/phone:

# # Generate peer private/public key
# wg genkey | tee /tmp/peer_private.key | wg pubkey

# # Send public key to host
# echo "MY_PEER_PUBLIC_KEY"  # Copy output

# Then on host, edit /etc/wireguard/wg0.conf to add the peer:

# [Peer]
# PublicKey = PEER_GENERATED_PUBLIC_KEY
# AllowedIPs = 10.66.66.2/32          # Unique per peer
# PersistentKeepalive = 25

# Step 3: Activate WireGuard

# # On host
# sudo systemctl enable --now wg-quick@wg0

# # Verify status
# sudo wg show

# # Check routing
# ip addr show wg0

# Step 4: Access Syncthing GUI from Any Peer

# Once WireGuard is connected on any device:

# https://10.66.66.1:8384

# No browser warnings if you imported the CA on each peer device.
# Hardware-Specific Notes for Your Machines
# Machine	Recommendation
# Dell XPS 15 9550	Primary Syncthing host (best specs)
# OptiPlex 790	WireGuard peer node
# Aspire TC-885	WireGuard peer node
# All machines	Enable wg-quick@wg0.service

# If running less than 8GB RAM on any peer:

#     Reduce MTU to 1400
#     Increase PersistentKeepalive to 60 (slightly higher overhead but less data)

# Security Advantages Over Direct Exposure
# Metric	Direct Exposed GUI	WireGuard Tunnel
# Attack Surface	Entire LAN accessible	Encrypted mesh only
# Traffic Visibility	Plain TCP (even with HTTPS)	End-to-end encrypted
# Privacy Leak	Let's Encrypt contact	Zero external contacts
# NAT Traversal	Requires port forwarding	Automatic keepalives
# Multi-device Sync	Complex	Native
# Want Me To Add?

# Do you need any of these additions to the setup?

#     Automated peer registration script — Add new peers without manual editing
#     iOS/macOS configuration profiles — For Apple device integration
#     Fail2ban integration — Block brute-force attempts on WireGuard port
#     Log analysis script — Monitor WG connections and Syncthing activity
#     Backup/restore procedure — Snapshot WireGuard configs before changes

# Which would help most with your workflow?