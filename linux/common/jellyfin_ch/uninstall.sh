#!/usr/bin/env bash
set -e

systemctl stop jellyfin
dnf remove -y jellyfin jellyfin-server jellyfin-web jellyfin-ffmpeg

rm -rf /etc/jellyfin
rm -rf /var/lib/jellyfin

echo "Jellyfin removed"