#!/bin/sh

set -eux

echo "************************ Adding openHAB repo ************************"
# https://www.openhab.org/docs/installation/linux.html#yum-or-dnf-based-systems

sudo tee /etc/yum.repos.d/openhab.repo << 'EOF'
[openHAB-Stable]
name=openHAB Stable
baseurl=https://openhab.jfrog.io/artifactory/openhab-linuxpkg-rpm/stable
gpgcheck=1
gpgkey="https://openhab.jfrog.io/artifactory/api/gpg/key/public"
enabled=1
EOF


sudo dnf install -y openhab openhab-addons

# Start openHAB automatically
sudo systemctl start openhab.service
# sudo systemctl status openhab.service

sudo systemctl daemon-reload
sudo systemctl enable openhab.service

# reach the openHAB Dashboard at http://openhab-device:8080


sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --permanent --add-port=8443/tcp
sudo firewall-cmd --permanent --add-port=5007/tcp

# or
# sudo ufw allow 8080/tcp
# sudo ufw allow 8443/tcp
# sudo ufw allow 5007/tcp