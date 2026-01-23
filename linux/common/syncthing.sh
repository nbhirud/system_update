#!/bin/sh

set -eux

# https://github.com/syncthing/syncthing
# https://syncthing.net/
# https://docs.syncthing.net/intro/getting-started.html
# https://wiki.archlinux.org/title/Syncthing
# http://127.0.0.1:8384/ - Syncthing Web GUI

HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)

sudo dnf install -y syncthing


# Firewall: (Figure out correct commands)
# https://docs.syncthing.net/users/firewall.html#firewall-setup

# sudo firewall-cmd --permanent --add-port=8384/tcp
# sudo firewall-cmd --reload

# Enable it to launch automatically on login  and start it
systemctl --user enable --now syncthing.service

mkdir -p "$HOME_DIR"/nb/Syncthing/{Obsidian,Joplin,Default,send_to_devices}

# Setup syncthing after setup in web browser:
# xdg-open http://127.0.0.1:8384

# On the linux web GUI:
# - accept the security warning (self‑signed cert)
# - create login
# - create a device ID
# - In the GUI, click “Add Folder” → Folder Path, Folder id, etc (Do this for each folder you want to sync including the ones created above)

# On Android:
# - Create a parent folder to place all the synced folders
# - install and setup syncthing on fdroid - syncthing fork something. Check https://docs.syncthing.net/users/contrib.html#android

# On Each device:
# - “Devices” tab → + (Add Device). Do this for each device

# On the linux web GUI / Android app:
# - Accept device connection requests

# Sharing:
# - Setup what folder is shared with what device, and other settings

# Test by placing a file or modifying a file that the syncing is working

# Install Gnome extension on linux: https://github.com/2nv2u/gnome-shell-extension-syncthing-indicator
