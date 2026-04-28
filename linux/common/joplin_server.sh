#!/bin/sh

set -eux

exit # TODO - test this first

# https://github.com/laurent22/joplin/blob/dev/packages/server/README.md

# Install Docker and Docker Compose before this step
# Verify Installations
docker --version
docker-compose --version

# Set Up Joplin Server with Docker Compose
joplin-server

# HOME_DIR=$(getent passwd $USER | cut -d: -f6)
# CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects"
# SYSUPDATE_CODE_DIR="$CODE_BASE_DIR/system_update"
# DEST_DIR="$HOME_DIR/.local/share/fonts/nerd-fonts"


mkdir -p ~/joplin-server && cd ~/joplin-server