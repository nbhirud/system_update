#!/usr/bin/env bash
set -e

dnf -y upgrade jellyfin\* ffmpeg
systemctl restart jellyfin

echo "Jellyfin updated"