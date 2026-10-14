#!/bin/sh

set -eux

# https://wiki.archlinux.org/title/Domain_name_resolution

# https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts
# https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-social/hosts # can make basic social interaction a lot difficult


# https://github.com/StevenBlack/hosts - modify hosts file - sudo nano /etc/hosts

DATETIME_STAMP="$(date +%Y-%m-%d_%H-%M-%S)"

HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)
SCRIPT_DOWNLOADS_DIR="$HOME_DIR/nb/nb_script_downloads"
DOWNLOADS_DIR_HOSTS="$SCRIPT_DOWNLOADS_DIR/hostsplay/hosts_$DATETIME_STAMP"

HOSTS_FILE_NEW="$DOWNLOADS_DIR_HOSTS/hosts_new_$DATETIME_STAMP"
HOSTS_FILE_OLD="$DOWNLOADS_DIR_HOSTS/hosts_old_$DATETIME_STAMP"

mkdir -p "$DOWNLOADS_DIR_HOSTS"
cd "$DOWNLOADS_DIR_HOSTS" || exit

echo "Created dir: $PWD"

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



