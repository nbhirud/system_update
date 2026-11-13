#!/bin/sh

set -eux

# Fcast from FUTO - use this to cast GrayJay from mobile to linux PC or other devices.

flatpak install flathub org.fcast.Receiver org.fcast.Sender

# Check current config
# sudo firewall-cmd --list-all

##### home
sudo firewall-cmd --permanent --zone="home" --add-port=46899/tcp
sudo firewall-cmd --permanent --zone="home" --add-service=mdns

##### public
sudo firewall-cmd --permanent --zone="public" --remove-port=46899/tcp
sudo firewall-cmd --permanent --zone="public" --remove-service=mdns

##### drop
sudo firewall-cmd --permanent --zone="drop" --remove-port=46899/tcp
sudo firewall-cmd --permanent --zone="drop" --remove-service=mdns

sudo firewall-cmd --reload
