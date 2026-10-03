#!/bin/sh

set -eux

# https://github.com/docker/docker-install/blob/master/install.sh
# https://github.com/docker/docker-install/blob/master/verify-docker-install
# https://github.com/sandervanvugt/ckad/blob/master/minikube-docker-setup.sh

DOCKER_DIR="$HOME/nb/Docker/"
mkdir -p "$DOCKER_DIR"
cd "$DOCKER_DIR"

echo "************************ Adding docker browser repo (not installing) ************************"
# https://docs.docker.com/engine/install/fedora/
sudo dnf -y install dnf-plugins-core
sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

curl -fsSL https://get.docker.com -o install-docker.sh
sudo sh install-docker.sh

cd "$HOME"

systemctl enable --now docker

