#!/bin/sh

set -eux

echo "************************ Adding Brave browser repo ************************"
# https://brave.com/linux/
sudo dnf install dnf-plugins-core
sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo

echo "************************ Installing Brave browser ************************"
sudo dnf install -y git flatpak tor torbrowser-launcher brave-browser

