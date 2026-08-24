#!/bin/sh

set -eux

# https://github.com/docker/docker-install/blob/master/install.sh
# https://github.com/docker/docker-install/blob/master/verify-docker-install

DOCKER_DIR="$HOME/nb/Docker/"
mkdir -p "$DOCKER_DIR"
cd "$DOCKER_DIR"

curl -fsSL https://get.docker.com -o install-docker.sh
sudo sh install-docker.sh

cd "$HOME"

systemctl enable --now docker
