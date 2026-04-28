#!/bin/sh

# https://www.baeldung.com/linux/set-command
set -eux

HOME_DIR=$(getent passwd $USER | cut -d: -f6)
# DOWNLOADS_DIR="$HOME_DIR/nb/Downloads"
SYSUPDATE_CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects/system_update"
# RUN_FIRST_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )


# . torsocks off
sudo dnf update -y
sudo dnf upgrade --refresh -y
flatpak update -y
sudo freshclam


cd $SYSUPDATE_CODE_BASE_DIR/

# Update hosts file
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/hosts.sh

# Update Proton AG stuff
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/proton_ag_stuff.sh

# Update nerd fonts
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/fonts.sh




# omz update -y
fastfetch
# . torsocks on

echo "Done!"
