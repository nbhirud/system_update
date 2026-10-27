#!/usr/bin/env bash
# set -euo pipefail

set -eux


# https://www.baeldung.com/linux/clean-up-linux-system


#HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"

NBDIR="$HOME_DIR/nb"
SCRIPT_DATA="${NBDIR}/nb_script_data"

FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"


SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"

BLEACHBIT_DOWNLOADS_DIR_BASE="${SCRIPT_DATA_DOWNLOADS}/bleachbit"
BLEACHBIT_CURRENT_DOWNLOADS_DIR="${BLEACHBIT_DOWNLOADS_DIR_BASE}/bleachbit_${FILENAME_TIMESTAMP}"


mkdir -p "${BLEACHBIT_CURRENT_DOWNLOADS_DIR}"
chown "${REAL_USER}":"${REAL_USER}" "${BLEACHBIT_DOWNLOADS_DIR_BASE}" "${BLEACHBIT_CURRENT_DOWNLOADS_DIR}"

cd "$BLEACHBIT_CURRENT_DOWNLOADS_DIR" || exit

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