#!/bin/sh

set -eux

echo "************************ Adding Tor repo ************************"
# Tor - https://community.torproject.org/relay/setup/bridge/fedora/

sudo tee /etc/yum.repos.d/tor.repo <<'EOF'
[tor]
name=Tor for Fedora $releasever - $basearch
baseurl=https://rpm.torproject.org/fedora/$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=https://rpm.torproject.org/fedora/public_gpg.key
cost=100
EOF

echo "************************ Installing Tor and Tor browser ************************"
sudo dnf install -y tor torbrowser-launcher 


# echo "************************ Edit your Tor config ************************"
# echo "************************ TODO - Don't forget to change the TODO1 options in Tor config. ************************"
# sudo tee /etc/tor/torrc << 'EOF'
# RunAsDaemon 1
# BridgeRelay 1

# # Replace "TODO1" with a Tor port of your choice.  This port must be externally
# # reachable.  Avoid port 9001 because it's commonly associated with Tor and
# # censors may be scanning the Internet for this port.
# ORPort TODO1
# EOF
