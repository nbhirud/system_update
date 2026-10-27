#!/usr/bin/env bash

set -euo pipefail

#############################
# Official discord client
#############################

# https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=linux&arch=x64&format=rpm

# DISCORD_DOWNLOAD_PAGE_URL="https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=linux&arch=x64&format=rpm"
# page_content="$(curl "$DISCORD_DOWNLOAD_PAGE_URL/")"
# actual_download_url=$(echo "$page_content" | grep -oP 'href="\K[^"]+')
# curl $download_url --output discord.rpm
# sudo dnf install -y discord.rpm

#############################
# vencord
#############################


VENCORD_DOWNLOAD_PAGE_URL="https://vencord.dev/download/vesktop/amd64/rpm"

SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"

VENCORD_DOWNLOADS_DIR_BASE="${SCRIPT_DATA_DOWNLOADS}/vencord"
VENCORD_CURRENT_DOWNLOADS_DIR="${VENCORD_DOWNLOADS_DIR_BASE}/vencord_${FILENAME_TIMESTAMP}"

mkdir -p "${VENCORD_CURRENT_DOWNLOADS_DIR}"
chown "${REAL_USER}":"${REAL_USER}" "${VENCORD_DOWNLOADS_DIR_BASE}" "${VENCORD_CURRENT_DOWNLOADS_DIR}"

# Follow the HTTP redirect to get the direct GitHub release RPM URL
DOWNLOAD_URL=$(curl -sIL "$VENCORD_DOWNLOAD_PAGE_URL" | grep -i "^location:" | tail -n 1 | tr -d '\r' | awk '{print $2}')

if [[ -z "$DOWNLOAD_URL" ]]; then
    echo "[!] Error: Failed to automatically resolve the download URL from the redirect page." >&2
    exit 1
fi

# RPM_FILENAME=$(basename "$DOWNLOAD_URL") # filename too long
RPM_FILENAME="vencord.rpm"
OUTPUT_RPM="$VENCORD_CURRENT_DOWNLOADS_DIR/$RPM_FILENAME"

echo "Resolved URL: $DOWNLOAD_URL"
echo "Downloading package to $OUTPUT_RPM"

# Download the RPM package
curl -L "$DOWNLOAD_URL" -o "$OUTPUT_RPM"


echo "Installing package"
sudo dnf install -y "$OUTPUT_RPM"

echo "Installation complete!"

