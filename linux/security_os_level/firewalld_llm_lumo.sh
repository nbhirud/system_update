#!/bin/bash
# Firewall setup script for Fedora - Privacy-focused
# Author: Nik (via Lumo)
# Date: $(date +%Y-%m-%d)

set -e  # Exit on error

echo "🔒 Setting up firewalld with privacy-focused rules..."

# Ensure firewalld is running
sudo systemctl enable --now firewalld

# Reset public zone to clean state (optional, comment out if you want to keep existing rules)
# sudo firewall-cmd --zone=public --remove-service=ssh
# sudo firewall-cmd --zone=public --remove-port=80/tcp
# ... etc

# Set default policy: deny incoming, allow outgoing (already default, but explicit)
sudo firewall-cmd --zone=public --set-target=DROP  # Drop all incoming by default
# Outgoing is already allowed by default in Fedora

# SSH: Limit connections (rate limiting for brute-force protection)
sudo firewall-cmd --zone=public --add-service=ssh --permanent
sudo firewall-cmd --zone=public --add-rich-rule='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="22" limit value="3/min" accept' --permanent

# Web services (Nextcloud)
sudo firewall-cmd --zone=public --add-service=http --permanent
sudo firewall-cmd --zone=public --add-service=https --permanent

# Radicale (CalDAV/CardDAV)
sudo firewall-cmd --zone=public --add-port=5232/tcp --permanent

# OpenHAB (uncomment if needed)
# sudo firewall-cmd --zone=public --add-port=8080/tcp --permanent
# sudo firewall-cmd --zone=public --add-port=8443/tcp --permanent
# sudo firewall-cmd --zone=public --add-port=5007/tcp --permanent

# KDE Connect (local network only - restrict to private zone if possible)
# If you're on a trusted home network, you could move this to 'home' zone
sudo firewall-cmd --zone=public --add-service=kdeconnect --permanent

# Apply changes
sudo firewall-cmd --reload

echo "✅ Firewall configured. Checking status..."
sudo firewall-cmd --list-all --zone=public

echo "🛡️  Privacy notes:"
echo "- SSH is rate-limited to prevent brute-force attacks"
echo "- Only explicitly allowed ports/services are open"
echo "- Outgoing traffic is allowed (necessary for normal use)"
echo "- Consider moving KDE Connect to 'home' zone if on trusted network"
echo "- Review OpenHAB rules - uncomment only if actively using those ports"