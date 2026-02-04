#!/usr/bin/env bash

# Run as root check
# https://www.baeldung.com/linux/check-script-run-root
if [ ${EUID:-0} -ne 0 ] || [ "$(id -u)" -ne 0 ]; then
  echo "[-] Please run as root (or with sudo). You are running as $(whoami)"
  exit 1
else
  echo "You are running as $(whoami)"
fi

set -eux

# NEXTDNS_ID="<YOUR_NEXTDNS_ID>"   # Replace with your NextDNS ID
# NEXTDNS_DEVICE_ID="<YOUR_NEXTDNS_DEVICE_ID>" # Replace with your NextDNS device ID to uniquely identify the device

NEXTDNS_ID=""  
NEXTDNS_DEVICE_ID=""

if [$NEXTDNS_DEVICE_ID -eq ""] || [$NEXTDNS_ID -eq ""]; then
  echo "Please set NextDNS details and run again"
  exit 1
fi

echo "Configuring systemd-resolved for NextDNS DoT..."
sudo tee /etc/systemd/resolved.conf >/dev/null <<EOF
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
Cache=yes
# ReadEtcHosts=yes
# Disables local network discovery protocols to enhance privacy and security (prevents leaks)
LLMNR=no
MulticastDNS=no
# Prevent systemd-resolved from binding to 127.0.0.53:53
# DNSStubListener=no
EOF

echo "Enabling services..."
sudo systemctl enable --now systemd-resolved

echo "Restarting services..."
sudo systemctl daemon-reload # Reload systemd
sudo systemctl restart NetworkManager
sudo systemctl restart systemd-resolved

echo "########## DNS-over-HTTPS ##########"
echo "https://dns.nextdns.io/$NEXTDNS_ID/${NEXTDNS_DEVICE_ID}_Firefox"
echo "https://dns.nextdns.io/$NEXTDNS_ID/${NEXTDNS_DEVICE_ID}_Brave"
echo "https://dns.nextdns.io/$NEXTDNS_ID/${NEXTDNS_DEVICE_ID}_Librewolf"

echo "########## DNS-over-TLS/QUIC ##########"
echo "RouterName-$NEXTDNS_ID.dns.nextdns.io"
echo "AndroidDeviceName-$NEXTDNS_ID.dns.nextdns.io"
