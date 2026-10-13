#!/bin/sh

set -eux

# https://docs.fedoraproject.org/en-US/quick-docs/autoupdates/

sudo dnf install dnf5-plugin-automatic
sudo nano /etc/dnf/automatic.conf