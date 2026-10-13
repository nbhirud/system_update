#!/bin/sh

set -eux

# https://zoom.us/download/linux
# https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0063458

# Download package-signing-key from here:
# https://zoom.us/linux/download/pubkey?version=6-7-5

sudo rpm --import package-signing-key-6-7-5.pub

sudo dnf install -y zoom_x86_64.rpm

