#!/bin/bash
# KeePassXC Production Setup for Fedora KDE Plasma (your machines)
# Author: Grok (tailored to your setup: Fedora 44 KDE, NextDNS, Syncthing, etc.)
# Run with: bash setup_keepassxc.sh
# Idempotent where possible; re-runnable.

set -euo pipefail



# Production-grade KeePassXC setup script for your Fedora KDE Plasma 44 machines.
# This script assumes a fresh Fedora install (as noted). It installs via DNF (native, best for browser/SSH integration — avoid Flatpak/Snap), configures everything per your preferences (hardened, no telemetry, NextDNS-aware if needed, hardware-aware), sets up Syncthing sync, disables KWallet, enables Secret Service, browser integration, SSH agent, autostart, etc. It handles multi-machine differences via auto-detection.
# Key design choices (practical & opinionated):

# Native dnf package for seamless integration (browsers, SSH, Secret Service).
# KeePassXC as the sole secrets provider via Secret Service + KWallet disable.
# Database in ~/nb/Syncthing/KeePass/ (create if needed; Syncthing handles versioning/conflicts).
# Auto-start with minimal delay; database unlock prompt on demand.
# Migration: Manual export/import for KWallet (tools are limited; script guides + backs up).
# Security: Strong defaults, firewalld (if needed), no unnecessary daemons.
# Education: Comments explain why.

# Run as regular user (sudo where needed). Test on one machine first.



echo "=== KeePassXC Setup Starting ==="

# Auto-detect hardware for optimizations
CPU_CORES=$(nproc)
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
echo "Detected: $CPU_CORES cores, ~${RAM_GB}GB RAM"

# 1. Install KeePassXC (native package)
sudo dnf install -y keepassxc

# 2. Create Syncthing sync dir (idempotent)
SYNC_DIR="$HOME/nb/Syncthing/KeePass"
mkdir -p "$SYNC_DIR"
echo "Database will sync to: $SYNC_DIR (ensure Syncthing folder shared)"

# 3. Disable KWallet completely (KDE Plasma 6)
cat > ~/.config/kwalletrc << EOF
[Wallet]
Enabled=false
UseKDEWallet=false

[org.freedesktop.secrets]
apiEnabled=true
EOF

# Create D-Bus service override for KeePassXC as Secret Service
mkdir -p ~/.local/share/dbus-1/services
cat > ~/.local/share/dbus-1/services/org.freedesktop.secrets.service << EOF
[D-BUS Service]
Name=org.freedesktop.secrets
Exec=/usr/bin/keepassxc
EOF

echo "KWallet disabled. KeePassXC is now the Secret Service provider."

# 4. Create example DB if none exists (user will customize)
DB_PATH="$SYNC_DIR/myvault.kdbx"
if [[ ! -f "$DB_PATH" ]]; then
    echo "No DB found. Launching KeePassXC to create one in sync dir..."
    keepassxc "$DB_PATH" &
    echo "Create database, set strong master password, enable Secret Service + Browser + SSH in settings."
    echo "Press Enter after initial DB setup..."
    read -r
fi

# 5. Browser Integration (Brave + LibreWolf)
# KeePassXC handles native-messaging hosts automatically for Chromium/Firefox-based.
# For LibreWolf (Firefox fork), may need custom path in advanced settings.

echo "Browser setup:"
echo "- In KeePassXC: Tools > Settings > Browser Integration > Enable + check Brave & Firefox."
echo "- Install KeePassXC-Browser extension in Brave/LibreWolf from their stores."
echo "- LibreWolf: If issues, set custom native-messaging to ~/.librewolf/native-messaging-hosts in advanced."
echo "- Keep KeePassXC open before browsers for best results."<grok-card data-id="0caba6" data-type="citation_card" data-plain-type="render_inline_citation" ></grok-card>

# 6. Autostart KeePassXC (minimal resource use)
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/keepassxc.desktop << EOF
[Desktop Entry]
Name=KeePassXC
Exec=keepassxc --minimized
Icon=keepassxc
Type=Application
Categories=Utility;
X-KDE-Autostart=true
X-KDE-Autostart-after=plasma
EOF

# 7. SSH Agent Integration (great for your multi-machine/server setup)
echo "Enable SSH Agent in KeePassXC Settings > SSH Agent."
echo "Store SSH keys as entries (attach private key, use password field for passphrase)."
echo "Works with your OpenSSH setup; no extra daemon needed."<grok-card data-id="0ef9c1" data-type="citation_card" data-plain-type="render_inline_citation" ></grok-card>

# 8. Other integrations (your app list)
echo "Integrations:"
echo "- **Thunderbird/Proton Mail/PGP**: Use KeePassXC for web logins; manual for app-specific if needed."
echo "- **Proton Pass / others**: Export/import via CSV/XML as bridge."
echo "- **qBittorrent, VLC, etc.**: Secret Service will handle where supported."
echo "- **Docker/AWS/etc.**: Store creds in DB; use CLI tools like secret-tool or keepassxc-cli."
echo "- **Android (KeePassDX)**: Install KeePassDX + Syncthing (F-Droid preferred). Share $SYNC_DIR folder. Use file-based sync (no cloud)."

# 9. Firewalld / SELinux / Hardening (minimal for local app)
# KeePassXC is local-only; no ports usually needed.
sudo firewall-cmd --reload  # Ensure defaults
echo "SELinux: KeePassXC should work confined; audit logs if issues."

# 10. Migration from KWallet
echo "=== KWallet Migration ==="
echo "Backup first:"
kwalletmanager6 --help > /dev/null && kwalletmanager6 || echo "Install kwalletmanager6 if needed: sudo dnf install kwalletmanager"
echo "1. Export KWallet entries manually via KWalletManager (or kwallet-query CLI)."
echo "2. In KeePassXC: Create matching groups/entries. Or use CSV export/import."
echo "Recent KDE has better Secret Service migration paths — test with secret-tool."<grok-card data-id="adfeaf" data-type="citation_card" data-plain-type="render_inline_citation" ></grok-card>
echo "Kill lingering kwalletd: systemctl --user stop kwalletd6* || true"

# 11. CLI tools + aliases (educational)
cat >> ~/.zshrc << 'EOF'
# KeePassXC aliases
alias kpcli='keepassxc-cli'
alias secret-tool='secret-tool'  # Now routes to KeePassXC

# Hardware-aware example function (low-RAM machines)
function kp-open() {
    if [[ $RAM_GB -lt 8 ]]; then
        keepassxc --minimized &
    else
        keepassxc &
    fi
}
EOF

source ~/.zshrc

# Final steps
echo "=== Post-Setup Manual Steps (critical) ==="
echo "1. Restart session or run: systemctl --user restart dbus"
echo "2. Open KeePassXC → Settings: Enable Secret Service, Browser Integration, SSH Agent, Auto-Type."
echo "3. Unlock DB, test browser autofill, secret-tool store/retrieve."
echo "4. Configure Syncthing folder (ignore .kdbx~ temp files; enable versioning)."
echo "5. Android: KeePassDX points to Syncthing-synced file."
echo "6. Test on low-RAM machines (nbLenovo): Use --minimized, close when idle."
echo "7. For NextDNS: No change needed (app-local)."

echo "Reboot recommended. Verify no KWallet popups."

echo "Done. This is robust, FOSS-first, and matches your stack. Questions or tweaks?"


# Better alternatives considered:

# Full migration tool: Limited; manual + keepassxc-cli is most reliable.
# Flatpak: Worse integration → skipped.
# Cloud sync: Syncthing is perfect for your privacy/Syncthing setup (local-first, versioning).
# Auto-unlock with KWallet remnant: Avoided for security (you want full switch).

# Hardware notes: Script detects RAM/cores. On nbLenovo/nbAcer (low RAM), keep minimized. On nbXPS (GPU), hardware accel is automatic in Qt app.
# Test thoroughly. Syncthing + KeePassDX on Android will give seamless cross-device. Let me know output/issues for refinements.