#!/usr/bin/env bash

if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run as root (or with sudo). You are running as $(whoami)"
  exit 1
fi

set -eux

NEXTDNS_ID="<YOUR_NEXTDNS_ID>"   # Replace with your NextDNS ID
NEXTDNS_DEVICE_ID="<YOUR_NEXTDNS_DEVICE_ID>" # Replace with your NextDNS device ID
CACHE_SIZE=5000                  # Aggressive cache
TTL_MIN=3600                     # Minimum TTL (1hr)
TTL_MAX=86400                    # Maximum TTL (1day)
TTL_LOCAL=3600                   # Local TTL (1hr) - Cache hosts from /etc/hosts and other sources
TTL_NEG=3600                     # Negative TTL (1hr)
BLOCKLIST_URL="https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts"
BLOCKLIST_PATH_1="/etc/dnsmasq.d/hosts.blocklist"

echo "[+] Installing required packages..."
sudo dnf install -y dnsmasq wget

# echo "[+] Stopping services..."
# sudo systemctl stop dnsmasq
# sudo systemctl stop NetworkManager
# sudo systemctl stop systemd-resolved

echo "[+] Configuring dnsmasq..."
sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
# dnsmasq configuration 
# For details about options, go to: https://dnsmasq.org/docs/dnsmasq-man.html
listen-address=127.0.0.1
port=53
# interface=lo
# bind only to the above address
bind-interfaces 
# Do not use system resolver settings from /etc/resolv.conf
no-resolv 
# Use systemd-resolved as the upstream DNS server
server=127.0.0.53 

# Avoid conflicts
# Enable code to detect DNS forwarding loops; ie the situation where a query sent to one of the upstream server eventually returns as a new query to the dnsmasq instance.
dns-loop-detect
# Don't poll /etc/resolv.conf for changes. 
no-poll

# Aggressive caching
cache-size=${CACHE_SIZE}
min-cache-ttl=${TTL_MIN}
max-cache-ttl=${TTL_MAX}
local-ttl=${TTL_LOCAL}
neg-ttl=${TTL_NEG}

# Speed optimizations
# Allow more parallel queries
dns-forward-max=150  

# Logging
log-facility=/var/log/dnsmasq.log
# Optional for debugging - disable after initial setup. Disable later for privacy
log-queries
log-debug
dumpfile=/var/log/dnsmasq_dump.log


# Blocklist
# Additional hosts file. Read the specified file as well as /etc/hosts.If a directory is given, then read all the files contained in that directory in alphabetical order. 
# Specify a directory - TODO
addn-hosts=${BLOCKLIST_PATH_1}
# addn-hosts=${BLOCKLIST_PATH_2}
# addn-hosts=${BLOCKLIST_PATH_3}
# addn-hosts=${BLOCKLIST_PATH_4}
# addn-hosts=${BLOCKLIST_PATH_5}
# addn-hosts=${BLOCKLIST_PATH_6}


# Security
# Don't forward short names
# domain-needed 
# block RFC1918 queries from the internet (Block reverse lookups for private IPs)
bogus-priv 
# Remove any MAC address information already in downstream queries before forwarding upstream. 
strip-mac
# Remove any subnet address already present in a downstream query before forwarding it upstream.
strip-subnet
#Dnsmasq can scramble the case of letters in DNS queries it sends upstream as a security feature.
do-0x20-encode
# Prevent DNS-rebinding attacks
stop-dns-rebind 
# rebind-protection

# Add DNSSEC validation (optional but recommended for security if not using DOH/DOT)
# Validate DNS replies and cache DNSSEC data
dnssec
# trust-anchor=.,19036,8,2,49aac11d7b6f6446702e542a5a17ab467475a8e0101b5dc00119e701148f325d
# even though systemd-resolved is not performing DNSSEC validation upstream, the local Dnsmasq instance is still securing  cached responses, which helps with both performance and integrity.

# Disable things not being used:
no-dhcp-interface

EOF

echo "[+] Downloading StevenBlack blocklist..."
sudo mkdir -p /etc/dnsmasq.d/
sudo wget -qO ${BLOCKLIST_PATH} ${BLOCKLIST_URL}

echo "[+] Setting up cron for weekly blocklist updates..."
sudo tee /etc/cron.weekly/update-dnsmasq-blocklist > /dev/null <<'EOF'
#!/bin/sh
wget -qO /etc/dnsmasq.d/hosts.blocklist https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
systemctl restart dnsmasq
EOF
sudo chmod +x /etc/cron.weekly/update-dnsmasq-blocklist

echo "test dnsmasq config"
dnsmasq --test
sleep 5s

echo "[+] Configuring systemd-resolved for NextDNS DoT..."
sudo tee /etc/systemd/resolved.conf > /dev/null <<EOF
[Resolve]
DNS=45.90.28.0#$NEXTDNS_DEVICE_ID-$NEXTDNS_ID.dns.nextdns.io
DNS=2a07:a8c0::#$NEXTDNS_DEVICE_ID-$NEXTDNS_ID.dns.nextdns.io
DNS=45.90.30.0#$NEXTDNS_DEVICE_ID-$NEXTDNS_ID.dns.nextdns.io
DNS=2a07:a8c1::#$NEXTDNS_DEVICE_ID-$NEXTDNS_ID.dns.nextdns.io
FallbackDNS=9.9.9.9
FallbackDNS=2620:fe::fe
FallbackDNS=149.112.112.112
FallbackDNS=2620:fe::9
DNSOverTLS=yes
Domains=~.
#DNSSEC=no
Cache=no
# ReadEtcHosts=yes
# Disables local network discovery protocols to enhance privacy and security (prevents leaks)
LLMNR=no
MulticastDNS=no
# Prevent systemd-resolved from binding to 127.0.0.53:53
DNSStubListener=no
EOF

# Simplified the below by moving it to main file above
# echo "[+] Disabling LLMNR & multicast DNS..."
# sudo mkdir -p /etc/systemd/resolved.conf.d
# sudo tee /etc/systemd/resolved.conf.d/disable-llmnr.conf > /dev/null <<EOF
# [Resolve]
# # Disables local network discovery protocols to enhance privacy and security (prevents leaks)
# LLMNR=no
# MulticastDNS=no
# # Prevent systemd-resolved from binding to 127.0.0.53:53
# DNSStubListener=no
# EOF

echo "[+] Configuring NetworkManager to use dnsmasq (and not override DNS)..."
sudo mkdir -p /etc/NetworkManager/conf.d
sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null <<EOF
[main]
dns=none
EOF

echo "[+] Enabling services..."
sudo systemctl enable --now systemd-resolved
sudo systemctl enable --now dnsmasq

echo "[+] Updating /etc/resolv.conf to use dnsmasq..."
sudo rm -f /etc/resolv.conf
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo sed -i 's/^nameserver .*/nameserver 127.0.0.1/' /run/systemd/resolve/stub-resolv.conf

# To prevent overwrites, make it immutable (optional but recommended):
# sudo chattr +i /etc/resolv.conf

echo "[+] Restarting services..."
sudo systemctl daemon-reload # Reload systemd
sudo systemctl restart dnsmasq
sudo systemctl restart NetworkManager
sudo systemctl restart systemd-resolved


# echo "[+] Hardening firewall: Blocking external DNS (UDP/53)..."
# # Block plain DNS except localhost
# sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" destination port=53 protocol="udp" drop'
# sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" destination port=53 protocol="tcp" drop'
# sudo firewall-cmd --reload

echo "[+] Setup complete!"
echo "Test with dig"
dig fedoraproject.org @127.0.0.1
sleep 5s

echo "Test with dig"
dig fedoraproject.org
sleep 5s

echo "Check NextDNS status:"
curl -s https://test.nextdns.io
sleep 5s

echo "The output should show only nameserver 127.0.0.1."
cat /etc/resolv.conf
sleep 5s

echo "test the ad-blocking"
dig doubleclick.net
sleep 5s

echo "Verify systemd-resolved configuration"
resolvectl status
sleep 5s

echo "This should not be very useful at this point, but still"
resolvectl statistics
sleep 5s

echo "check dnsmasq.service - journalctl"
journalctl -xeu dnsmasq.service
sleep 5s

echo "check dnsmasq.service - systemctl"
systemctl status dnsmasq.service
sleep 5s

echo "Confirm caching works:"
# tail -f /var/log/dnsmasq.log
tail -100 /var/log/dnsmasq.log | cat

