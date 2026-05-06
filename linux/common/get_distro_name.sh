#!/usr/bin/env bash

# set -eux

DISTRO_NAME=""

# lsb_release -i | cut -f 2- 
# The following does the same job
# lsb_release -is

if [ -x "$(command -v lsb_release)" ];
then
    DISTRO_NAME=$(lsb_release -is  | tr '[:upper:]' '[:lower:]')
    # lsb_release -is  | tr '[:upper:]' '[:lower:]'
fi

echo $DISTRO_NAME
