#!/bin/sh

# Do not run as root
# https://www.baeldung.com/linux/check-script-run-root
if [ ${EUID:-0} -eq 0 ] || [ "$(id -u)" -eq 0 ]; then
  echo "[-] Do not run as root (or with sudo)."
  exit 1
else
    echo "You are running as $(whoami)"
fi

set -eux

# https://wiki.archlinux.org/title/Nextcloud
# https://nextcloud.com/blog/how-to-install-the-nextcloud-all-in-one-on-linux/
# https://github.com/nextcloud/all-in-one

# Search for solutions here when stuck:
# https://github.com/nextcloud/all-in-one/discussions/categories/wiki?discussions_q=is%3Aopen+category%3AWiki


HOME_DIR=$(getent passwd $USER | cut -d: -f6)
DATA_DIR="$HOME_DIR/nb/nextcloud_data"

# Step 1: Have Docker and Docker compose installed.

# PACKAGE_NAME="docker"
# if rpm -q "$PACKAGE_NAME" > /dev/null 2>&1; then
#     echo "$PACKAGE_NAME is installed on your system."
# else
#     echo "$PACKAGE_NAME is not installed on your system."
# fi

# Verify that we can at least get version output
# https://github.com/docker/docker-install/blob/master/verify-docker-install
if ! docker --version; then
	echo "ERROR: Is Docker installed?"
	exit 1
fi
# TODO - If docker not installed, run linux/common/docker.sh

# Step 2: Create data dir
mkdir -p "$DATA_DIR"

# Step 3: Install AIO

sudo dnf update -y && sudo dnf upgrade -y

# For Linux and without a web server or reverse proxy (like Apache, Nginx and else) already in place:
sudo docker run \
  --init \
  --sig-proxy=false \
  --name nextcloud-aio-mastercontainer \
  --restart always \
  --publish 80:80 \
  --publish 8080:8080 \
  --publish 8443:8443 \
  --volume nextcloud_aio_mastercontainer:/mnt/docker-aio-config \
  --volume /var/run/docker.sock:/var/run/docker.sock:ro \
  --env NEXTCLOUD_DATADIR="$DATA_DIR" \
  ghcr.io/nextcloud-releases/all-in-one:latest

# In case you are asked for a passphrase when you open the web UI but have no idea what it might be (happened with me), use the following command:
# https://github.com/nextcloud/all-in-one/discussions/1786
# sudo docker exec nextcloud-aio-mastercontainer grep password /mnt/docker-aio-config/data/configuration.json


###########################################
# Some docker commands
###########################################

# lists all local docker containers - https://docs.docker.com/reference/cli/docker/container/ls/
# sudo docker container ls -a 
# sudo docker ps -a

# sudo docker image ls -a # lists all downloaded images - https://docs.docker.com/reference/cli/docker/image/ls/ 
# sudo docker system prune -a # remove any stopped containers and all unused images - https://www.digitalocean.com/community/tutorials/how-to-remove-docker-images-containers-and-volumes

# Stop and remove all containers
# sudo docker stop $(sudo docker ps -a -q)
# sudo docker rm $(sudo docker ps -a -q)

###########################################
# Skipped alternative installation method
###########################################

# # Cancelled using it this way because it is lot more to setup and gets too intertwined with OS:

# sudo dnf install -y nextcloud


# sudo firewall-cmd --add-service=http --permanent 
# sudo firewall-cmd --add-service=https --permanent 
# sudo firewall-cmd --reload

# # Apache (httpd)
# sudo systemctl enable --now httpd

# # MariaDB (MySQL compatible)
# sudo systemctl enable --now mariadb

# I read further instructions and decided to go with AIO way