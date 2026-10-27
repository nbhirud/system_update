#!/bin/sh

set -eux

# https://wiki.archlinux.org/title/Domain_name_resolution

# https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts
# https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-social/hosts # can make basic social interaction a lot difficult


# https://github.com/StevenBlack/hosts - modify hosts file - sudo nano /etc/hosts

# TODO - "$SCRIPT_DOWNLOADS_DIR" is covered by onaccess scanning of clamav (OnAccessIncludePath) so these hosts files may keep getting deleted as they contains urls to block. Use "$SCRIPT_DATA/hostsplay/" or something else instead
# See below configs in clamav.sh
# add_config_value "$SCAN_CONF" ExcludePath '^/etc/hosts$'
# add_config_value "$SCAN_CONF" ExcludePath "^$SCRIPT_DATA/hostsplay/"


REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"

NBDIR="$HOME_DIR/nb"
SCRIPT_DATA="${NBDIR}/nb_script_data"

FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"

#SCRIPT_DOWNLOADS_DIR="${SCRIPT_DATA}/downloads"

# Do not place this under SCRIPT_DOWNLOADS_DIR as clamav would delete it
#/home/nbhirud/nb/nb_script_data/hostsplay/
HOSTS_DOWNLOADS_DIR_BASE="${SCRIPT_DATA}/hostsplay"

HOSTS_CURRENT_DOWNLOADS_DIR="${HOSTS_DOWNLOADS_DIR_BASE}/hosts_${FILENAME_TIMESTAMP}"

HOSTS_FILE_NEW="$HOSTS_CURRENT_DOWNLOADS_DIR/hosts_new_$FILENAME_TIMESTAMP"
HOSTS_FILE_OLD="$HOSTS_CURRENT_DOWNLOADS_DIR/hosts_old_$FILENAME_TIMESTAMP"

mkdir -p "${HOSTS_CURRENT_DOWNLOADS_DIR}"
chown "${REAL_USER}":"${REAL_USER}" "${HOSTS_DOWNLOADS_DIR_BASE}" "${HOSTS_CURRENT_DOWNLOADS_DIR}"

cd "$HOSTS_CURRENT_DOWNLOADS_DIR" || exit
echo "Created dir: $PWD"


# if [ -d "$HOSTS_CURRENT_DOWNLOADS_DIR" ]; then
#   echo "$DIRECTORY does exist."
# else

# SCAN_CONF="/etc/clamd.d/scan.conf"

# cat <<EOF | sudo tee -a "$SCAN_CONF"

# # Exclude hosts setup intermediate files from ClamOnAcc:

# OnAccessExcludePath /home/$(whoami)/nb/nb_script_data/hostsplay
# # OnAccessExcludePath /home/nbhirud/nb/nb_script_data/hostsplay


# EOF


# fi



# Download from Github - https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts
# Non-Github mirror - http://sbc.io/hosts/alternates/fakenews-gambling-porn/hosts

wget -O "$HOSTS_FILE_NEW" https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts
# wget -O "$HOSTS_FILE_NEW" http://sbc.io/hosts/alternates/fakenews-gambling-porn/hosts


PERM=$(stat --format '%a' /etc/hosts)
echo "$PERM"

sudo mv /etc/hosts "$HOSTS_FILE_OLD"
# modify the downloaded hosts file if necessary
sudo mv "$HOSTS_FILE_NEW" /etc/hosts

# Set correct file permission for new hosts file
# stat --format '%a' /etc/hosts  # for linux
# stat -c '%a' <file>  # for busybox
sudo chmod "$PERM" /etc/hosts
# sudo chown user:group /etc/hosts # TODO - find out correct user/group

sudo ausearch -c 'systemd-resolve' --raw | sudo audit2allow -M my-systemdresolve
sudo semodule -X 300 -i my-systemdresolve.pp
sudo /sbin/restorecon -v /etc/hosts

# https://github.com/StevenBlack/hosts?tab=readme-ov-file#linux
# sudo ipconfig /flushdns
sudo resolvectl flush-caches
sudo systemctl restart NetworkManager.service
sudo systemctl restart systemd-resolved

# cd ..
# sudo rm -r hostsplay

####################################

# sudo dnf -y install podman
# https://github.com/StevenBlack/hosts/raw/refs/heads/master/Dockerfile

####################################


echo "hosts - done"



