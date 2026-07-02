#!/bin/sh

set -eux

nmcli connection modify "Wired connection 1" connection.id "nbInternet"

# nmcli connection modify nbInternet ipv4.method auto ipv6.method disable ipv4.dns 194.242.2.6,194.242.2.4,1.1.1.3,1.0.0.3,9.9.9.9,149.112.112.112,1.1.1.2,1.0.0.2 ipv4.dns-search example.com

nmcli connection modify nbInternet ipv4.method auto 
nmcli connection modify nbInternet ipv6.method "disabled"
nmcli connection modify nbInternet ipv4.dns 194.242.2.6,194.242.2.4,1.1.1.3,1.0.0.3,9.9.9.9,149.112.112.112,1.1.1.2,1.0.0.2 
# nmcli connection modify nbInternet ipv4.dns-search example.com



# https://wiki.archlinux.org/title/NetworkManager
# https://www.privacyguides.org/en/os/linux-overview/ - see "MAC Address Randomization" and other stuff

##################################################
# Debugging and Testing
##################################################

# Check your network
# ip route | grep default
# ip addr show
# ip route

# Check if there are any unknown devices in your network
# sudo dnf install -y nmap
# sudo nmap -sn 192.168.0.0/24
# arp -an

# You may see hostnames that identify the devices.
# avahi-browse -at

# You can also inspect vendors:
# ip neigh

# Check MAC - The MAC OUI often reveals the manufacturer.
# sudo nmap -sP 192.168.0.ABC
# sudo nmap -sP 192.168.0.XYZ