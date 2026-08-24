#!/usr/bin/env bash
# set -euo pipefail

set -eux


# https://www.baeldung.com/linux/clean-up-linux-system



HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)
DOWNLOADS_DIR="$HOME_DIR/nb/Downloads"
DOWNLOADS_DIR_BLEACHBIT="$DOWNLOADS_DIR/Bleachbit/bleachbit_$(date +%Y-%m-%d_%H-%M-%S)"

mkdir -p "$DOWNLOADS_DIR_BLEACHBIT"
cd "$DOWNLOADS_DIR_BLEACHBIT" || exit

url=$(curl -fsSL https://www.bleachbit.org/download/linux |
    grep -oE 'https://download\.bleachbit\.org/[^"]+\.fc[0-9]+\.noarch\.rpm' |
    head -n1)


# rpm_url=$(curl -fsSL https://www.bleachbit.org/download/linux |
#     grep -oE 'https://download\.bleachbit\.org/[^"]+\.fc44\.noarch\.rpm' |
#     head -n1)

wget "$url"

INSTALLER_FILE=$(ls | grep ".rpm")
# INSTALLER_FILE=${rpm##*/}


# sig=$(rpm -qip "$INSTALLER_FILE" --nosignature | grep '^Signature')

# grep -q 'D6D447B02B4D4C9D' <<< "$sig" ||
#     { echo "ERROR: unexpected BleachBit signing key"; exit 1; }

# rpm --checksig "$INSTALLER_FILE" | grep -q 'digests signatures OK' ||
#     { echo "ERROR: RPM signature verification failed"; exit 1; }


sudo dnf install -y "$INSTALLER_FILE"

bleachbit --version