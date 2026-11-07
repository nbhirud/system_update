#!/bin/sh

# set -eux

release_version=$(cat /etc/fedora-release | cut -d' ' -f 3)
echo "$release_version"