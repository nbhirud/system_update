#!/usr/bin/env bash

set -euo pipefail


# Note: Be sure to install rpm versions (and not flatpak or snap) of web browsers and keepassxc for better integration with keepassxc

echo "Installing KeePassXC..."

sudo dnf install -y \
    keepassxc \
    keepassxc-browser

echo "Creating KeePass sync directory..."

mkdir -p "$HOME/nb/Syncthing/KeePass"

echo "Disabling KDE Wallet..."

kwriteconfig6 \
    --file kwalletrc \
    --group Wallet \
    --key Enabled false || true

mkdir -p "$HOME/.config"

cat > "$HOME/.config/keepassxc.ini" <<'EOF'
[General]
MinimizeAfterUnlock=true
MinimizeOnClose=true

[Browser]
Enabled=true

[SSHAgent]
Enabled=true

[SecretService]
Enabled=true
EOF

echo "Creating autostart entry..."

mkdir -p "$HOME/.config/autostart"

cat > "$HOME/.config/autostart/org.keepassxc.KeePassXC.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=KeePassXC
Exec=keepassxc
X-GNOME-Autostart-enabled=true
EOF





######################
# Files layout:
# ~/nb/Syncthing/KeePass/

# ├── main.kdbx
# ├── main.keyx


# Additional settings:

# 1. Database   → Settings
# Argon2id KDF
# Memory: 256 MB+
# Iterations: Auto-tune
# AES-KDF disabled


# 2. Settings   → Security
# Lock database on screen lock
# Lock after suspend
# Clear clipboard after 10 seconds
# Minimize after unlock


echo "Setup complete."

echo
echo "Next steps:"
echo "1. Create database:"
echo "   ~/nb/Syncthing/KeePass/main.kdbx"
echo
echo "2. Enable:"
echo "   Tools -> Settings -> Browser Integration"

# Install Browser extension "KeePassXC-Browser" in web browsers
# Thunderbird also supports system Secret Service.

echo
echo "3. Enable:"
echo "   Tools -> Settings -> Secret Service Integration"
echo
echo "4. Enable:"
echo "   Tools -> Settings -> SSH Agent"
# Then run:
# export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/keepassxc/ssh-agent.sock"

# Then create:
# ~/.config/environment.d/keepassxc.conf

# SSH_AUTH_SOCK=%t/keepassxc/ssh-agent.sock

# Useful for: GitHub, GitLab, Servers, Tailscale SSH. KeePassXC becomes your SSH agent.



echo
echo "5. Reboot"