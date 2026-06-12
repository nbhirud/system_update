#!/bin/sh

set -eux

sudo dnf install firewalld firewall-cmd firewall-config







# mDNS and Avahi
# sudo firewall-cmd --permanent --add-service=mdns

# SSH
# sudo firewall-cmd --permanent --add-service=ssh


# Assign active interfaces to home zone
# while read -r iface; do
# [[ "$iface" == "lo" ]] && continue
# firewall-cmd --permanent --zone=home --add-interface="$iface" || true
# done < <(
# nmcli -t -f DEVICE,STATE device status
# | awk -F: '$2=="connected"{print $1}'
# )


# Block IoT subnet explicitly
# If IoT devices are on same subnet (not ideal), you can still block them:
# Find IP of Google Home, Alexa, etc and other smart devices that shouldn't need access to your PC and:
# sudo firewall-cmd --permanent \
#   --add-rich-rule='rule family="ipv4" source address="192.168.0.ABC" reject'





# ensure you're in a LAN-friendly zone:- If home Desktop/Laptop
# sudo firewall-cmd --set-default-zone=home


systemctl enable --now firewalld

# At the end:
sudo firewall-cmd --reload
nmcli connection reload
