#!/bin/sh

set -eux

# Fcast from FUTO - use this to cast GrayJay from mobile to linux PC or other devices.

flatpak install flathub org.fcast.Receiver org.fcast.Sender

# Check current config
# sudo firewall-cmd --list-all

# Allow mDNS (critical for discovery)
sudo firewall-cmd --permanent --add-service=mdns

# Allow FCast port
sudo firewall-cmd --permanent --add-port=46899/tcp

# Reload
# sudo firewall-cmd --reload

# Also add to your active zone if needed (usually FedoraWorkstation or home):
sudo firewall-cmd --permanent --zone=FedoraWorkstation --add-service=mdns
sudo firewall-cmd --permanent --zone=FedoraWorkstation --add-port=46899/tcp
sudo firewall-cmd --reload

