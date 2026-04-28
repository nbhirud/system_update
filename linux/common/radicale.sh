#!/bin/sh

set -eux


# httpd-tools is needed for the htpasswd command to secure your login.
sudo dnf install -y radicale httpd-tools

# Create a user for your sync
sudo mkdir -p /etc/radicale
sudo htpasswd -B -c /etc/radicale/users nbhirud


# Edit the Configuration
# Modify or add these sections to ensure it's accessible on your local network and uses the password file you just created:
# sudo nano /etc/radicale/config

sudo tee /etc/radicale/config << 'EOF'
[server]
# Listen on all interfaces (your PC's local IP)
hosts = 0.0.0.0:5232

[auth]
type = htpasswd
htpasswd_filename = /etc/radicale/users
htpasswd_encryption = bcrypt

[storage]
filesystem_folder = /var/lib/radicale/collections
EOF

# Firewall & Permissions
# sudo firewall-cmd --add-port=5232/tcp --permanent
# sudo firewall-cmd --reload
sudo ufw allow 5232/tcp
sudo ufw reload

# Ensure the radicale user owns the storage folder
sudo mkdir -p /var/lib/radicale/collections
sudo chown -R radicale:radicale /var/lib/radicale/collections

# Start the Service
sudo systemctl enable --now radicale

# Access in browser
# http://localhost:5232