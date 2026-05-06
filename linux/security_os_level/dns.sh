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

# Anything assigned here will be disregarded. Pass these instead to the script as:
# sh $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/dns.sh $NEXTDNS_ID $NEXTDNS_DEVICE_ID
NEXTDNS_ID="" # Do not initialize here
NEXTDNS_DEVICE_ID="" # Do not initialize here

# Making sure nothing was manually initialized above
if [ "$NEXTDNS_DEVICE_ID" != "" ] || [ "$NEXTDNS_ID" != "" ]; then
  echo "Found hardcoded NEXTDNS_DEVICE_ID = $NEXTDNS_DEVICE_ID and NEXTDNS_ID = $NEXTDNS_ID in dns.sh. These will be ignored. "
  sleep 30s
fi

if [[ -z $1 ]] && [[ -z $2 ]];
then 
  echo "NEXTDNS_ID and/or NEXTDNS_DEVICE_ID not passed as input. Need to pass both"
  exit 1
  
else
  echo "NEXTDNS_ID and/or NEXTDNS_DEVICE_ID are provided. Proceeding."
  NEXTDNS_ID=$1
  NEXTDNS_DEVICE_ID=$2
  echo "Inputs provided: NEXTDNS_DEVICE_ID = $NEXTDNS_DEVICE_ID and NEXTDNS_ID = $NEXTDNS_ID"

fi


# Redundant checks. Remove this later if nothing gets caught here after multiple tests.
if [ "$NEXTDNS_ID" = "" ] || [ "$NEXTDNS_DEVICE_ID" = "" ]; then
  echo "NEXTDNS_ID = $NEXTDNS_ID and NEXTDNS_DEVICE_ID = $NEXTDNS_DEVICE_ID. Why is any of them blank? Check"
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
ReadEtcHosts=yes
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
sudo resolvectl flush-caches
sudo systemctl restart NetworkManager
sudo systemctl restart systemd-resolved

echo "########## DNS-over-HTTPS ##########"
echo "https://dns.nextdns.io/$NEXTDNS_ID/${NEXTDNS_DEVICE_ID}_Firefox"
echo "https://dns.nextdns.io/$NEXTDNS_ID/${NEXTDNS_DEVICE_ID}_Brave"
echo "https://dns.nextdns.io/$NEXTDNS_ID/${NEXTDNS_DEVICE_ID}_Librewolf"

echo "########## DNS-over-TLS/QUIC ##########"
echo "${NEXTDNS_DEVICE_ID}_RouterName-$NEXTDNS_ID.dns.nextdns.io"
echo "${NEXTDNS_DEVICE_ID}_AndroidDeviceName-$NEXTDNS_ID.dns.nextdns.io"
