#!/usr/bin/env bash

set -eux

sudo dnf -y install clamav clamd clamav-freshclam clamav-update clamav-unofficial-sigs

# Not installing clamtk because it hsa been an unmaintained project for long. Installing ClamUI flatpak instead.


# If using KDE:
# sudo dnf -y install klamav # GUI for clamav on KDE


flatpak install flathub io.github.linx_systems.ClamUI

# https://github.com/extremeshok/clamav-unofficial-sigs
sudo setsebool -P antivirus_can_scan_system true

# **Run the following command to display which signatures are being loaded by clamav
# clamscan --debug 2>&1 /dev/null | grep "loaded"

# Output system and configuration information for viewing or possible debugging purposes
sudo clamav-unofficial-sigs.sh -i

# Further reading:
# https://wiki.archlinux.org/title/ClamAV
# https://wiki.gentoo.org/wiki/ClamAV
# https://wiki.gentoo.org/wiki/ClamAV_Unofficial_Signatures#top


sudo systemctl start clamav-daemon.service
sudo systemctl start clamav-freshclam.service
sudo systemctl enable clamav-daemon.service
sudo systemctl enable clamav-freshclam.service 


# https://rseichter.github.io/fangfrisch/
# https://docs.clamav.net/manual/Installing/Community-projects.html

# Create home directory
# mkdir -m 0770 -p /var/lib/fangfrisch
mkdir -p /var/lib/fangfrisch
chmod 770 /var/lib/fangfrisch
chgrp clamav /var/lib/fangfrisch

# Prepare and activate venv
cd /var/lib/fangfrisch
python3 -m venv venv
source venv/bin/activate

# Install via PyPI
pip install fangfrisch



