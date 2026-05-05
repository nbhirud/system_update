#!/bin/bash


##########################################################

# if you want to be truly "stealthy" when you're at a cafe, you can run this single command while connected to your home network:
# Tell Fedora that your current Wi-Fi connection belongs to the 'home' zone
# Public Wi-Fi: Your Fedora machine will use the public zone. Because our script sets the target to DROP, your laptop becomes a "black hole." Scanners won't even see that a device is there.
# Home Wi-Fi: When you walk into your house, Fedora recognizes the SSID and automatically switches to the home zone, opening up your OpenHAB and Radicale ports so your devices can sync.
sudo nmcli connection modify "Your_Home_SSID_Name" connection.zone home

# To see exactly what the outside world sees on your Fedora machine right now, run:
sudo firewall-cmd --get-active-zones
# This will show you which "security profile" is currently protecting your internet connection.

# We want the public zone to be a "Black Hole." If someone scans you, they get nothing. We will only allow SSH with strict rate-limiting.
# Set Public to stealth mode
sudo firewall-cmd --permanent --zone=public --set-target=DROP
# Only allow SSH with a 2-try-per-minute limit
sudo firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" service name="ssh" flood-limit value="2/m" accept'
# Remove everything else from Public that might have been there by default
sudo firewall-cmd --permanent --zone=public --remove-service=mdns --remove-service=samba-client

# "Home" Zone - These ports will only open when you are connected to a network you have manually labeled as "Home."
# Allow your specific services in the Home zone
sudo firewall-cmd --permanent --zone=home --add-service=kdeconnect
sudo firewall-cmd --permanent --zone=home --add-service=http
sudo firewall-cmd --permanent --zone=home --add-service=https
# OpenHAB & Radicale Ports
sudo firewall-cmd --permanent --zone=home --add-port=8080/tcp
sudo firewall-cmd --permanent --zone=home --add-port=8443/tcp
sudo firewall-cmd --permanent --zone=home --add-port=5007/tcp
sudo firewall-cmd --permanent --zone=home --add-port=5232/tcp
# Apply changes
sudo firewall-cmd --reload

# Automating the Switch - Now, you need to tell Fedora which Wi-Fi connection is your "Home." Run this while connected to your home router:
# Replace 'MyHomeWiFi' with your actual Wi-Fi name (SSID)
sudo nmcli connection modify "MyHomeWiFi" connection.zone home
# Now, whenever you connect to that Wi-Fi, Fedora instantly opens your OpenHAB and KDE Connect ports. When you disconnect or go to a coffee shop, it defaults back to the public zone, where it is a "Black Hole" again.

# To verify which "Shield" is currently active and what it's blocking, run:
sudo firewall-cmd --get-active-zones




###########################################################

# 1. Ensure firewalld is running and enabled
systemctl enable --now firewalld

# 2. Set the default zone to 'public' (Fedora default, but good to be explicit)
firewall-cmd --set-default-zone=public

# 3. Change the zone target to DROP
# This makes the firewall drop packets silently instead of rejecting them, 
# which is better for privacy/stealth.
sudo firewall-cmd --permanent --zone=public --set-target=DROP

# 4. SSH Security: Limit connections (Replaces 'ufw limit 22/tcp')
# This allows 2 new connections per minute—protecting against brute force.
sudo firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" service name="ssh" banter="limit value=2/m" accept'

# 5. Web Traffic (NextCloud / Standard Web)
sudo firewall-cmd --permanent --zone=public --add-service=http
sudo firewall-cmd --permanent --zone=public --add-service=https

# 6. KDE Connect
# This is a complex service with many ports; using the service name is much safer.
sudo firewall-cmd --permanent --zone=public --add-service=kdeconnect

# 7. OpenHAB Ports
sudo firewall-cmd --permanent --zone=public --add-port=8080/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8443/tcp
sudo firewall-cmd --permanent --zone=public --add-port=5007/tcp

# 8. Radicale (Calendar/Contacts)
sudo firewall-cmd --permanent --zone=public --add-port=5232/tcp

# 9. Privacy Hardening: Disable ICMP (Ping)
# This prevents your machine from responding to ping requests on public networks.
sudo firewall-cmd --permanent --zone=public --add-icmp-block=echo-request

# 10. Apply all changes
sudo firewall-cmd --reload

echo "Firewall hardening complete."
sudo firewall-cmd --list-all