#!/bin/sh

# Do not run as root
# https://www.baeldung.com/linux/check-script-run-root
if [ ${EUID:-0} -eq 0 ] || [ "$(id -u)" -eq 0 ]; then
  echo "[-] Do not run as root (or with sudo)."
  exit 1
else
    echo "You are running as $(whoami)"
fi

set -eux
