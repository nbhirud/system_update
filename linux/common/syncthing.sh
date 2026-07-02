#!/bin/bash

set -eux

# https://github.com/syncthing/syncthing
# https://syncthing.net/
# https://docs.syncthing.net/intro/getting-started.html
# https://wiki.archlinux.org/title/Syncthing
# http://127.0.0.1:8384/ - Syncthing Web GUI

HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)
SYSUPDATE_CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects/system_update"

sudo dnf install -y syncthing


# if id "$REAL_USER" &>/dev/null; then
# loginctl enable-linger "$REAL_USER" || true

# su - "$REAL_USER" -c '
#     if systemctl --user list-unit-files 2>/dev/null | grep -q "^syncthing.service"; then
#         systemctl --user enable --now syncthing
#     fi
# ' || true

# fi

# Enable it to launch automatically on login  and start it
systemctl --user enable --now syncthing.service

# mkdir -p "$HOME_DIR"/nb/Syncthing/{Obsidian,Joplin,send_to_devices} # not POSIX compliant

# # https://www.baeldung.com/linux/shell-script-iterate-over-string-list
# # DCIM_nbM42_external  DCIM_nbM42_internal  DeSyncCC  Joplin  KeePass  kodi_backups  nbM42_and_nbMain  nbM42_sms_import_export  nbMain_and_nbAcer  Obsidian  OrgMode  Recordings_nbM42  Signal_Backup_nbM42

# for i in Obsidian Joplin
# do
# 	mkdir -p "$HOME_DIR/nb/Syncthing/$i"
# done

SYNC_DIRS=(
    "DCIM_nbM42_external"  
    "DCIM_nbM42_internal"  
    "DeSyncCC"  
    "Joplin"  
    "KeePass"  
    "kodi_backups"  
    "nbM42_and_nbMain"  
    "nbM42_sms_import_export"  
    "nbMain_and_nbAcer"  
    "Obsidian"  
    "OrgMode"  
    "Recordings_nbM42"  
    "Signal_Backup_nbM42"
)

for i in "${SYNC_DIRS[@]}"
do
	mkdir -p "$HOME_DIR/nb/Syncthing/$i"
done

# --------------------------------------------------
# Syncthing GUI LAN access
# --------------------------------------------------
# 0.0.0.0:8384 allows accessing syncthing using http://hostname.local:8384, http://127.0.0.1:8384, http://192.168.0.XYZ:8384 (Machine IP), http://localhost:8384 from anywhere on your LAN without worrying about DHCP changes. (Use only is you know the network is always going to be safe)

# SYNCTHING_CONFIG="/home/${REAL_USER}/.local/state/syncthing/config.xml"

# if [[ -f "$SYNCTHING_CONFIG" ]]; then

# cp -a "$SYNCTHING_CONFIG" "${SYNCTHING_CONFIG}.bak.$(date +%s)"

# # Option A (recommended)
# sed -Ei \
#     's|<address>[^<]+</address>|<address>0.0.0.0:8384</address>|' \
#     "$SYNCTHING_CONFIG"

# chown "${REAL_USER}:${REAL_USER}" "$SYNCTHING_CONFIG"

# su - "$REAL_USER" -c '
#     systemctl --user restart syncthing 2>/dev/null || true
# '

# fi


# Setup syncthing after setup in web browser:
# xdg-open http://127.0.0.1:8384

# On the linux web GUI:
# - accept the security warning (self‑signed cert)
# - create login
# - create a device ID
# - In the GUI, click "Add Folder" → Folder Path, Folder id, etc (Do this for each folder you want to sync including the ones created above)

# On Android:
# - Create a parent folder to place all the synced folders
# - install and setup syncthing on fdroid - syncthing fork something. Check https://docs.syncthing.net/users/contrib.html#android

# On Each device:
# - "Devices" tab → + (Add Device). Do this for each device

# On the linux web GUI / Android app:
# - Accept device connection requests

# Sharing:
# - Setup what folder is shared with what device, and other settings

# Test by placing a file or modifying a file that the syncing is working

#########################
# Firewall: (Figure out correct commands)
# https://docs.syncthing.net/users/firewall.html#firewall-setup

# sudo firewall-cmd --permanent --add-port=8384/tcp
# sudo firewall-cmd --reload

##########

# Following rule allows only your OtherPC (192.168.0.XYZ) to reach the Syncthing GUI. You can specify more IPs like this to restrict local network usability
# sudo firewall-cmd --permanent \
#   --add-rich-rule='rule family="ipv4" source address="192.168.0.XYZ" port protocol="tcp" port="8384" accept'

# sudo firewall-cmd --permanent \
#   --add-rich-rule='rule family="ipv4" port protocol="tcp" port="8384" drop'

# sudo firewall-cmd --reload

#############################


echo "************************ Identify Desktop Environment ************************"
DESKTOP=$(sh $SYSUPDATE_CODE_BASE_DIR/linux/common/check_desktop_env.sh)
echo "Desktop Environment is $DESKTOP"



if [ "$DESKTOP" = "gnome" ]; then
  echo "Install Gnome extension on linux: https://github.com/2nv2u/gnome-shell-extension-syncthing-indicator"

elif [ "$DESKTOP" = "kde" ]; then
  # sudo dnf install -y syncthingtray
  flatpak install -y flathub io.github.martchus.syncthingtray

fi


##################################################
# Debugging and Testing
##################################################

### Is Syncthing running?
# systemctl --user status syncthing
# systemctl --user enable --now syncthing
# systemctl --user restart syncthing
# systemctl --user stop syncthing

# ss -tulpn | grep 8384
# You should see something like:
# LISTEN 0 4096 127.0.0.1:8384
# or
# LISTEN 0 4096 0.0.0.0:8384
# or machine IP
# 192.168.0.XYZ:8384

### Can you access it locally?
# curl http://127.0.0.1:8384
# xdg-open http://127.0.0.1:8384

# syncthing connectivity status


### Check Syncthing's GUI bind address

# Look in:
# ~/.local/state/syncthing/config.xml
# and find:
# <gui enabled="true" tls="false">
#     <address>127.0.0.1:8384</address>
# </gui>

# If it's bound to: 127.0.0.1:8384, then only localhost can access it.

# If you want access via hostnameXYZ.local (while using avahi), change to: 
# <address>0.0.0.0:8384</address> 
# or machine IP
# <address>192.168.0.xyz:8384</address>
# then restart:
# systemctl --user restart syncthing


# grep -A5 "<gui" ~/.local/state/syncthing/config.xml
# Look for
# <address>127.0.0.1:8384</address>
# or 
# <address>0.0.0.0:8384</address>

### Check firewall
# sudo firewall-cmd --list-ports

# To allow 8384:
# sudo firewall-cmd --permanent --add-port=8384/tcp
# sudo firewall-cmd --reload


# Check name resolution - Verify that .local resolves:
# ping hostnameXYZ.local
# Expected:
# PING hostnameXYZ.local (192.168.0.xyz)
# If ping fails, the problem is Avahi/mDNS.

# On Fedora, Syncthing's web UI is typically configured to listen only on: 127.0.0.1:8384
# In that configuration: http://localhost:8384 works
# http://nbMain.local:8384 fails because the browser resolves nbMain.local to 192.168.0.66, not 127.0.0.1.

# The linger setting lets Syncthing continue running even if you log out of KDE, which is useful for a machine acting as a synchronization node.
# systemctl --user enable --now syncthing
# loginctl enable-linger $USER

# Check whether linger is already enabled:
# loginctl show-user $USER -p Linger


# If you want LAN access but only from trusted machines, keep in the XML:
# <address>0.0.0.0:8384</address> 
# and restrict it with firewalld:
# sudo firewall-cmd --permanent \
#   --add-rich-rule='rule family="ipv4" source address="192.168.0.0/24" port protocol="tcp" port="8384" accept'
# or even to specific hosts (Then only selected LAN devices can access the GUI.):
# sudo firewall-cmd --permanent \
#   --add-rich-rule='rule family="ipv4" source address="192.168.0.48" port protocol="tcp" port="8384" accept'


