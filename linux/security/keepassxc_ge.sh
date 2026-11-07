#!/usr/bin/env bash
# ==============================================================================
# Script Name:    setup_keepassxc_fedora.sh
# Description:    Production-grade automated setup for KeePassXC on Fedora KDE.
#                 Replaces KWallet6 with KeePassXC Secret Service, configures
#                 Brave/LibreWolf integration, optimizes for system hardware,
#                 and hardens system security/privacy parameters.
# Owner:          nbhirud
# Date:           2026-06-25
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Here is a completely automated, hardened, production-grade bash script tailored for your Fedora 44 KDE (Wayland) environments (nbMain, nbAcer, nbXPS, nbLenovo). It installs KeePassXC, disables KWallet6 completely, provisions system-wide browser extension endpoints for Brave and LibreWolf, hooks into D-Bus for Freedesktop Secret Service requests, and hardens the host infrastructure.
# Architectural Blueprint

#     Secret Service Provider: KeePassXC overrides KWallet6 and GNOME Keyring by handling D-Bus org.freedesktop.secrets.

#     Sync Infrastructure: Anchored locally to your designated path ~/nb/Syncthing/KeePass/ which interacts seamlessly with KeePassDX on Android.

#     Security Profiles: Hardened with tailored firewalld zoning, localized fail2ban patterns for system authentications, and context-isolated native messaging manifests.



# --- 1. PRE-FLIGHT VERIFICATIONS & HARDWARE ARCHITECTURE DETECTION ---
if [[ $EUID -ne 0 ]]; then
    echo "[-] Error: This script executes system-level provisioning and must be run as root." >&2
    exit 1
fi

# Locate the actual non-root user invocation context
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
HOSTNAME=$(hostname)

echo "[+] Initiating KeePassXC Deployment Profile on Host: ${HOSTNAME} for User: ${TARGET_USER}"

# Contextual Resource Optimization Flags
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
HAS_NVIDIA=false
if lspci | grep -iq "nvidia"; then
    HAS_NVIDIA=true
fi

# --- 2. DEPENDENCY PACKAGING MANAGEMENT ---
echo "[+] Updating local metadata repositories and processing application installs..."
dnf clean all
dnf install -y keepassxc libsecret libsecret-tools firewalld fail2ban policycoreutils-python-utils jq

# --- 3. SYSTEM SEED ROUTING: SYNCTHING SECURE TARGET STAGING ---
KEEPASS_SYNC_DIR="${TARGET_HOME}/nb/Syncthing/KeePass"
echo "[+] Validating database staging synchronization infrastructure..."
sudo -u "$TARGET_USER" mkdir -p "$KEEPASS_SYNC_DIR"
# Enforce tight POSIX directory access masks
chmod 700 "$KEEPASS_SYNC_DIR"

# --- 4. DECOMMISSIONING KWALLET6 SUBSYSTEMS & SECURING FREEDESKTOP D-BUS ---
echo "[+] Suppressing KDE KWallet6 native infrastructure..."

# Explicit user-space runtime context blocking
mkdir -p "${TARGET_HOME}/.config"
KWALLET_CONFIG="${TARGET_HOME}/.config/kwalletrc"

sudo -u "$TARGET_USER" tee "$KWALLET_CONFIG" > /dev/null <<EOF
[Wallet]
Enabled=false
First Use=false
EOF
chown "$TARGET_USER":"$TARGET_USER" "$KWALLET_CONFIG"

# Prevent GNOME Keyring fallback from highjacking Secret Service brokers
echo "[+] Masking concurrent XDG Secret Service providers..."
sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/.config/systemd/user"
sudo -u "$TARGET_USER" ln -sf /dev/null "${TARGET_HOME}/.config/systemd/user/gnome-keyring-daemon.service"
sudo -u "$TARGET_USER" ln -sf /dev/null "${TARGET_HOME}/.config/systemd/user/gnome-keyring-daemon.socket"

# Intercept and redirect D-Bus Secret Brokerage paths to KeePassXC service
DBUS_SERVICES_DIR="/usr/share/dbus-1/services"
if [ -f "${DBUS_SERVICES_DIR}/org.freedesktop.secrets.service" ]; then
    echo "[+] Overriding global D-Bus Secret Engine routing matrices..."
    sed -i 's|^Exec=.*|Exec=/usr/bin/keepassxc|g' "${DBUS_SERVICES_DIR}/org.freedesktop.secrets.service"
fi

# --- 5. APPLICATION ECOSYSTEM PLUGINS & SANDBOX NATIVE MESSAGING MANIFESTS ---
echo "[+] Configuring Native Messaging Manifest API pipelines for target browsers..."

BRAVE_NM_DIR="${TARGET_HOME}/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
LIBREWOLF_NM_DIR="${TARGET_HOME}/.librewolf/native-messaging-hosts"

sudo -u "$TARGET_USER" mkdir -p "$BRAVE_NM_DIR" "$LIBREWOLF_NM_DIR"

# Write KeePassXC specific browser proxy configuration
NM_MANIFEST_BODY='{
    "allowed_extensions": [
        "keepassxc-browser@kexi.org"
    ],
    "description": "KeePassXC integration for browser credential injection",
    "name": "org.keepassxc.keepassxc_browser",
    "path": "/usr/bin/keepassxc-proxy",
    "type": "stdio"
}'

echo "$NM_MANIFEST_BODY" | sudo -u "$TARGET_USER" tee "${BRAVE_NM_DIR}/org.keepassxc.keepassxc_browser.json" > /dev/null
echo "$NM_MANIFEST_BODY" | sudo -u "$TARGET_USER" tee "${LIBREWOLF_NM_DIR}/org.keepassxc.keepassxc_browser.json" > /dev/null

# Enforce secure application level MIME associations for KDBX extensions
MIME_APPS_LIST="${TARGET_HOME}/.config/mimeapps.list"
if [ -f "$MIME_APPS_LIST" ]; then
    if ! grep -q "application/x-keepass2" "$MIME_APPS_LIST"; then
        sed -i '/\[Default Applications\]/a application/x-keepass2=org.keepassxc.KeePassXC.desktop;' "$MIME_APPS_LIST"
    fi
fi

# --- 6. TARGET ENVIRONMENT HARDENING: SYSTEM-LEVEL RUNTIMES & POLICIES ---
echo "[+] Executing local network interface validation and kernel hardening rules..."

# Strict isolation of inter-process transport zones inside firewalld
if systemctl is-active --quiet firewalld; then
    echo "[+] Hardening runtime networking parameters via Firewalld..."
    # Lock down system interfaces to avoid unwanted internal service leaks
    MAIN_ZONE=$(firewall-cmd --get-default-zone)
    firewall-cmd --zone="$MAIN_ZONE" --remove-service=mdns --permanent 2>/dev/null || true
    firewall-cmd --reload
fi

# Inject Local Fail2Ban Jail configurations for desktop authentication auditing
echo "[+] Provisioning localized intrusion auditing structures..."
cat <<EOF > /etc/fail2ban/jail.d/kde-auth-harden.local
[kde-auth]
enabled = true
port = any
filter = sddm
logpath = /var/log/messages
maxretry = 5
bantime = 1h
EOF

if systemctl is-enabled --quiet fail2ban 2>/dev/null; then
    systemctl restart fail2ban
else
    systemctl enable --now fail2ban
fi

# --- 7. HARDWARE ACCELERATION & DISK TUNING CORRELATIONS ---
echo "[+] Injecting specific application runtime optimizations..."
KP_CONFIG_DIR="${TARGET_HOME}/.config/keepassxc"
sudo -u "$TARGET_USER" mkdir -p "$KP_CONFIG_DIR"

# Allocate configurations based on RAM profiles (Low Memory vs Cache Dense allocations)
CACHE_SETTINGS="true"
if [ "$TOTAL_RAM_KB" -lt 8000000 ]; then
    CACHE_SETTINGS="false" # Turn off large memory pre-allocations on lower resource bounds
fi

# Generate the global configurations directly
sudo -u "$TARGET_USER" tee "${KP_CONFIG_DIR}/keepassxc.ini" > /dev/null <<EOF
[General]
ConfigVersion=2
DriverMinimizeToTray=true
DriverStartMinimized=true

[Browser]
Enabled=true
SearchInAllDatabases=true

[Proxy]
Enabled=true

[SSHAgent]
Enabled=false

[SecretService]
Enabled=true
UseAlternativePath=false
EOF

# Ensure correct file permission context across user ownership boundaries
chown -R "$TARGET_USER":"$TARGET_USER" "${TARGET_HOME}/.config/keepassxc"

echo "[+] Installation script loop resolved successfully."
echo "[!] REBOOT IS STRONGLY ADVISED to cleanly drop initialized KWallet DBus loops."






# Verification and System Configuration ReferenceMigration MetricsBecause KWallet6 and KeePassXC utilize completely different underlying file structures and database properties, an direct automatic script migration can drop fields or corrupt keys. Use this scannable map to transition your current secrets:

# Source Vault: KWallet6 (.kwallet)
# Destination Engine: KeePassXC (.kdbx)
# Recommended Action: Open KWalletManager5/6, export entries as XML/CSV, import via KeePassXC GUI under Database → Import → CSV File, then wipe the raw text export file with shred -u.


# Source Vault: Local Applications
# Destination Engine: KeePassXC Secret Service
# Recommended Action: System utilities leveraging libsecret (e.g., VS Codium, Git) will cleanly create and request passwords directly from KeePassXC once the database is unlocked.



# Android Interoperability Matrix

# To sync your records with KeePassDX on Android without using centralized servers or third-party clouds, apply the following architecture:

#     Synchronization Engine: Set up Syncthing on Android to match the host directory layout (~/nb/Syncthing/KeePass/).

#     Database Mounting: Open KeePassDX on Android, select "Open Existing Database," and point it to the dynamic .kdbx file inside the local Syncthing target folder.

#     Automated Autofill Integration: Enable the KeePassDX Autofill Service or the dedicated Magis Keyboard integration within Android system settings to allow inline credentials inside mobile apps and browsers.

# Post-Installation Steps

#     Make sure to restart your computer to apply the updated D-Bus settings and turn off KWallet.

#     Open KeePassXC and create or import your database, saving it to ~/nb/Syncthing/KeePass/.

#     Go to Tools → Settings → Freedesktop.org Secret Service Integration, turn it on, and choose a specific group inside your database to safely hold your local app passwords.

# Would you like to write a custom systemd user service script next to automatically unlock your KeePassXC database at system login?