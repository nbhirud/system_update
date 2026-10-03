#!/bin/sh

set -eux

echo "************************ Adding VSCodium repo ************************"
### VSCodium
# https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo

sudo tee /etc/yum.repos.d/vscodium.repo <<'EOF'
[gitlab.com_paulcarroty_vscodium_repo]
name=gitlab.com_paulcarroty_vscodium_repo
baseurl=https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/rpms/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
metadata_expire=1h
EOF

echo "************************ Installing VSCodium ************************"
sudo dnf install -y codium
