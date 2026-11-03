#!/usr/bin/env bash

# NextDNS Linked IP Updater Script
# Keeps your home network's public WAN IP linked to your NextDNS profile.

# Configured NextDNS DDNS Update URL
NEXTDNS_UPDATE_URL="https://link-ip.nextdns.io/xyz/abc"

# Execute curl request silently with strict timeout to prevent hung processes
if RESPONSE=$(curl -s --max-time 10 "$NEXTDNS_UPDATE_URL" 2>&1); then
    # Log success to system logs (journalctl)
    logger -t nextdns-ip-update "NextDNS Linked IP update succeeded: ${RESPONSE}"
else
    # Log failure to system logs
    logger -t nextdns-ip-update "NextDNS Linked IP update failed: ${RESPONSE}"
fi

