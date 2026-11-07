#!/usr/bin/env bash

set -eux

# Note: I don't know if this script is of any practical use. I wrote it, so now it exists here.

PACKAGE_INSTALLER=""

# packagesNeeded=(clamav clamd clamav-update clamtk)
if [ -x "$(command -v apk)" ];
then
    # Alpine Linux
    # sudo apk add --no-cache "${packagesNeeded[@]}"
    PACKAGE_INSTALLER="apk add --no-cache "

elif [ -x "$(command -v pacman)" ];
then
    # Arch, etc.
    # sudo pacman -S "${packagesNeeded[@]}"
    PACKAGE_INSTALLER="sudo pacman -S "

elif [ -x "$(command -v apt-get)" ];
then
    # Debian, Ubuntu, etc.
    # sudo apt-get install "${packagesNeeded[@]}"
    PACKAGE_INSTALLER="sudo apt-get install "

elif [ -x "$(command -v dnf)" ];
then
    # Fedora, RHEL, etc.
    # sudo dnf install "${packagesNeeded[@]}"
    PACKAGE_INSTALLER="sudo dnf install "

elif [ -x "$(command -v zypper)" ];
then
    # OpenSUSE, etc.
    # sudo zypper install "${packagesNeeded[@]}"
    PACKAGE_INSTALLER="sudo zypper install "

else
    # echo "FAILED TO INSTALL PACKAGE: Package manager not found. You must manually install: ${packagesNeeded[@]}">&2;
	# echo "FAILED TO INSTALL PACKAGE: Package manager not found. You must manually install"
    echo "Package manager not found."
fi

echo $PACKAGE_INSTALLER