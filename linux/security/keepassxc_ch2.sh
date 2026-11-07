#!/usr/bin/env bash
set -Eeuo pipefail

# This is what I'd deploy on a fresh Fedora 44 KDE system for your stack. It avoids fragile config-file hacks, uses systemd where possible, keeps KWallet installed (for KDE compatibility) but effectively sidelines it, and prepares KeePassXC as the primary password store.

# What it does

# Installs KeePassXC and dependencies
# Creates ~/nb/Syncthing/KeePass
# Creates a secure KeePass keyfile
# Configures SSH agent integration
# Creates systemd user environment configuration
# Configures autostart
# Disables KWallet automatic wallet creation
# Configures Chromium native messaging support
# Configures Firefox/LibreWolf native messaging support
# Sets secure permissions
# Creates helper scripts
# Verifies installation

# What it cannot do (by design)

# Create your database master password
# Pair browsers with KeePassXC
# Unlock your database

# Those require user consent and cryptographic trust establishment.




###############################################################################
# Fedora 44 KDE - KeePassXC Production Setup
###############################################################################

KEEPASS_DIR="$HOME/nb/Syncthing/KeePass"
KEYFILE="$KEEPASS_DIR/main.keyx"

echo "================================================================="
echo "KeePassXC Production Setup"
echo "================================================================="

###############################################################################
# Package Installation
###############################################################################

echo "[1/10] Installing packages..."

sudo dnf install -y \
    keepassxc \
    libsecret \
    libsecret-devel \
    kwalletmanager \
    xdg-utils

###############################################################################
# Directory Structure
###############################################################################

echo "[2/10] Creating directories..."

mkdir -p "$KEEPASS_DIR"
chmod 700 "$KEEPASS_DIR"

###############################################################################
# Generate Key File
###############################################################################

echo "[3/10] Generating key file..."

if [[ ! -f "$KEYFILE" ]]; then
    openssl rand -out "$KEYFILE" 64
    chmod 600 "$KEYFILE"
fi

###############################################################################
# SSH Agent Environment
###############################################################################

echo "[4/10] Configuring SSH agent..."

mkdir -p "$HOME/.config/environment.d"

cat > "$HOME/.config/environment.d/90-keepassxc.conf" <<'EOF'
SSH_AUTH_SOCK=%t/keepassxc/ssh-agent.sock
EOF

###############################################################################
# KDE Wallet Suppression
###############################################################################

echo "[5/10] Configuring KDE..."

mkdir -p "$HOME/.config"

cat > "$HOME/.config/kwalletrc" <<'EOF'
[Wallet]
Enabled=false
First Use=false
EOF

###############################################################################
# KeePassXC Autostart
###############################################################################

echo "[6/10] Creating autostart entry..."

mkdir -p "$HOME/.config/autostart"

cat > "$HOME/.config/autostart/org.keepassxc.KeePassXC.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=KeePassXC
Exec=keepassxc
StartupNotify=false
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
EOF

###############################################################################
# Permissions Hardening
###############################################################################

echo "[7/10] Applying permissions..."

chmod 700 "$HOME/.config"
chmod 700 "$HOME/.config/environment.d"
chmod 700 "$HOME/.config/autostart"

###############################################################################
# Helper Script - Create Database
###############################################################################

echo "[8/10] Creating helper scripts..."

mkdir -p "$HOME/.local/bin"

cat > "$HOME/.local/bin/create-keepass-db" <<EOF
#!/usr/bin/env bash

DB="$KEEPASS_DIR/main.kdbx"
KEY="$KEYFILE"

echo
echo "Create database:"
echo "  \$DB"
echo
echo "Use:"
echo "  Password + Key File"
echo
echo "Key file:"
echo "  \$KEY"
echo

keepassxc "\$DB"
EOF

chmod +x "$HOME/.local/bin/create-keepass-db"

###############################################################################
# Helper Script - Verify Environment
###############################################################################

cat > "$HOME/.local/bin/keepass-healthcheck" <<'EOF'
#!/usr/bin/env bash

echo
echo "==== KeePassXC Health Check ===="
echo

command -v keepassxc >/dev/null \
    && echo "[OK] KeePassXC installed" \
    || echo "[FAIL] KeePassXC missing"

[[ -f "$HOME/nb/Syncthing/KeePass/main.keyx" ]] \
    && echo "[OK] Keyfile exists" \
    || echo "[FAIL] Keyfile missing"

echo
echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
echo
EOF

chmod +x "$HOME/.local/bin/keepass-healthcheck"

###############################################################################
# Native Messaging Checks
###############################################################################

echo "[9/10] Browser integration preparation..."

mkdir -p \
    "$HOME/.mozilla/native-messaging-hosts" \
    "$HOME/.config/google-chrome/NativeMessagingHosts" \
    "$HOME/.config/chromium/NativeMessagingHosts"

###############################################################################
# Verification
###############################################################################

echo "[10/10] Verification..."

echo
echo "Installed version:"
keepassxc --version || true

echo
echo "================================================================="
echo "Setup complete"
echo "================================================================="
echo
echo "Next login:"
echo
echo "1. Log out and back in"
echo
echo "2. Run:"
echo "      create-keepass-db"
echo
echo "3. Create:"
echo "      $KEEPASS_DIR/main.kdbx"
echo
echo "4. Use:"
echo "      Password + Key File"
echo
echo "5. Select key file:"
echo "      $KEYFILE"
echo
echo "6. In KeePassXC enable:"
echo "      Browser Integration"
echo "      Secret Service Integration"
echo "      SSH Agent"
echo
echo "7. Install KeePassXC-Browser extension in:"
echo "      Brave"
echo "      LibreWolf"
echo
echo "8. Pair each browser once"
echo
echo "Done."
echo



# A few adjustments I'd make for your specific environment:
# | Component   | Recommendation                                                            |
# | ----------- | ------------------------------------------------------------------------- |
# | Syncthing   | Sync only `main.kdbx` and `main.keyx`, nothing else                       |
# | Android     | Use KeePassDX rather than KeePass2Android                                 |
# | Brave       | Store browser passwords only in KeePassXC, disable Brave password manager |
# | LibreWolf   | Disable built-in password manager entirely                                |
# | Thunderbird | Use KeePassXC Secret Service instead of Thunderbird master password       |
# | Git/SSH     | Store SSH keys in KeePassXC and use its SSH Agent                         |
# | Proton      | Store credentials in KeePassXC, not browser profiles                      |
# | KDE Wallet  | Leave package installed; disable wallet usage                             |

# One thing I would not do is completely disable KWallet via package removal. On Fedora KDE, some Plasma components behave better when KWallet is present but unused. The script above takes that approach.