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
# sudo tee /etc/systemd/resolved.conf >/dev/null <<EOF
# # https://wiki.archlinux.org/title/Systemd-resolved
# # https://wiki.archlinux.org/title/Domain_name_resolution
# #v
# [Resolve]
# DNS=45.90.28.0#$NEXTDNS_DEVICE_ID-$NEXTDNS_ID.dns.nextdns.io
# DNS=2a07:a8c0::#$NEXTDNS_DEVICE_ID-$NEXTDNS_ID.dns.nextdns.io
# DNS=45.90.30.0#$NEXTDNS_DEVICE_ID-$NEXTDNS_ID.dns.nextdns.io
# DNS=2a07:a8c1::#$NEXTDNS_DEVICE_ID-$NEXTDNS_ID.dns.nextdns.io
# FallbackDNS=9.9.9.9
# FallbackDNS=2620:fe::fe
# FallbackDNS=149.112.112.112
# FallbackDNS=2620:fe::9
# DNSOverTLS=yes
# Domains=~.
# #DNSSEC=no
# Cache=yes
# # Max Cache Capacity. Default DNSCacheSize is 4000
# DNSCacheSize=10000
# # Tells systemd-resolved not to store records for queries that originate from local applications targeting local addresses (127.0.0.1 or ::1)
# CacheFromLocalhost=no
# ReadEtcHosts=yes
# # Disables local network discovery protocols to enhance privacy and security (prevents leaks)
# LLMNR=no
# MulticastDNS=no
# # Prevent systemd-resolved from binding to 127.0.0.53:53
# # DNSStubListener=no
# EOF


sudo tee /etc/systemd/resolved.conf >/dev/null <<EOF
[Resolve]
# Primary NextDNS servers with DoT SNI device identification (Space-separated)
DNS=45.90.28.0#$NEXTDNS_DEVICE_ID-$NEXTDNS_ID.dns.nextdns.io 2a07:a8c0::#$NEXTDNS_DEVICE_ID-$NEXTDNS_ID.dns.nextdns.io 45.90.30.0#$NEXTDNS_DEVICE_ID-$NEXTDNS_ID.dns.nextdns.io 2a07:a8c1::#$NEXTDNS_DEVICE_ID-$NEXTDNS_ID.dns.nextdns.io

# Fallback DNS (Space-separated)
FallbackDNS=9.9.9.9 2620:fe::fe 149.112.112.112 2620:fe::9

# Enforcement & Routing
DNSOverTLS=yes
Domains=~.
#DNSSEC=no

# Caching Optimization
Cache=yes
ReadEtcHosts=yes

# Security & Privacy Hardening
LLMNR=no
MulticastDNS=no
# DNSStubListener=no
EOF

echo "Enabling services..."
sudo systemctl enable --now systemd-resolved

echo "Restarting services..."
sudo systemctl daemon-reload # Reload systemd
sudo resolvectl flush-caches
sudo systemctl restart NetworkManager
sudo systemctl restart systemd-resolved


############ 
# setup to run the NextDNS Linked IP update URL as a simple system-wide cron job - # TODO - This section is untested.
############

# Note: Before setting this up, 
# 1. Go to router's admin panel
# 2. Advanced → Network → DHCP Server (or LAN).
# 3. Find the Primary DNS and Secondary DNS fields under the DHCP settings.
# 4. Enter your two custom NextDNS IPv4 addresses.
# 5. Clear any entries in additional DNS fields so no third-party fallback (like Google 8.8.8.8) is present.
# 6. Click Save.

SCRIPT_PATH="/usr/local/bin/update-nextdns-ip.sh"

# Ensure target directory exists
mkdir -p "$(dirname "$SCRIPT_PATH")"

# Prompt user for the NextDNS DDNS / Update URL
read -rp "Enter your NextDNS DDNS Update URL (from Dashboard -> Linked IP): " NEXTDNS_URL

# Basic validation of the entered URL
if [[ -z "$NEXTDNS_URL" || ! "$NEXTDNS_URL" =~ ^https://link-ip\.nextdns\.io/ ]]; then
    echo "ERROR: Invalid URL. It should start with 'https://link-ip.nextdns.io/'" >&2
    exit 1
fi


# Create the executable updater script
sudo cat <<'UPDATE_NEXTDNS_EOF' > "$SCRIPT_PATH"
#!/usr/bin/env bash

# NextDNS Linked IP Updater Script
# Keeps your home network's public WAN IP linked to your NextDNS profile.

# Configured NextDNS DDNS Update URL
NEXTDNS_UPDATE_URL="TARGET_URL_PLACEHOLDER"

# Execute curl request silently with strict timeout to prevent hung processes
if RESPONSE=$(curl -s --max-time 10 "$NEXTDNS_UPDATE_URL" 2>&1); then
    # Log success to system logs (journalctl)
    logger -t nextdns-ip-update "NextDNS Linked IP update succeeded: ${RESPONSE}"
else
    # Log failure to system logs
    logger -t nextdns-ip-update "NextDNS Linked IP update failed: ${RESPONSE}"
fi
UPDATE_NEXTDNS_EOF

# Substitute the user's actual NextDNS URL into the script
sed -i "s|TARGET_URL_PLACEHOLDER|${NEXTDNS_URL}|g" "$SCRIPT_PATH"

# Set strict permissions (root owner, executable by root only)
chmod 700 "$SCRIPT_PATH"
chown root:root "$SCRIPT_PATH"

#Testing script execution..."
# Run the newly created script once to confirm it works
if "$SCRIPT_PATH"; then
    echo "Initial update trigger sent successfully."
else
    echo "WARNING: Initial test trigger returned an error. Check network connectivity or URL."
fi

# Configuring root crontab
# Fetch current root crontab (suppressing "no crontab for root" error)
CURRENT_CRON=$(crontab -l 2>/dev/null || true)

# Remove any existing entries for this specific script to prevent duplicates
CLEANED_CRON=$(echo "$CURRENT_CRON" | grep -v "$SCRIPT_PATH" || true)

# Define new cron entries: @reboot and every 30 minutes
NEW_CRON_ENTRIES=$(cat <<EOF
# NextDNS Linked IP Update Jobs
@reboot ${SCRIPT_PATH} >/dev/null 2>&1
*/30 * * * * ${SCRIPT_PATH} >/dev/null 2>&1
EOF
)

# Append new entries to cleaned crontab and install
if [ -z "$CLEANED_CRON" ]; then
    echo "$NEW_CRON_ENTRIES" | crontab -
else
    printf "%s\n\n%s\n" "$CLEANED_CRON" "$NEW_CRON_ENTRIES" | crontab -
fi

# Verifying crontab configuration
crontab -l | grep "$SCRIPT_PATH"

############





echo "########## DNS-over-HTTPS ##########"
echo "https://dns.nextdns.io/$NEXTDNS_ID/${NEXTDNS_DEVICE_ID}_Firefox"
echo "https://dns.nextdns.io/$NEXTDNS_ID/${NEXTDNS_DEVICE_ID}_Brave"
echo "https://dns.nextdns.io/$NEXTDNS_ID/${NEXTDNS_DEVICE_ID}_Librewolf"

echo "########## DNS-over-TLS/QUIC ##########"
echo "${NEXTDNS_DEVICE_ID}_RouterName-$NEXTDNS_ID.dns.nextdns.io"
echo "${NEXTDNS_DEVICE_ID}_AndroidDeviceName-$NEXTDNS_ID.dns.nextdns.io"
echo "${NEXTDNS_DEVICE_ID}Waydroid-$NEXTDNS_ID.dns.nextdns.io"
