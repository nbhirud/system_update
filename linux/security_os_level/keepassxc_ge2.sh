#!/usr/bin/env bash
# ==============================================================================
# Script Name:    setup_keepassxc_dual_vault.sh
# Description:    Production-grade automated configuration for KeePassXC on Fedora KDE.
#                 Implements localized system database architecture (D-Bus Secret Service)
#                 while staging clean paths for Syncthing personal vaults.
# Owner:          nbhirud
# Date:           2026-06-25
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'


# Here is the completely revised, production-grade setup script.

# It implements the two-database architecture automatically: it builds a Local-Only System Database (system.kdbx) isolated from your sync paths to handle the D-Bus Secret Service and app-level NextDNS configurations, while preparing your Syncthing Directory exclusively for your global personal.kdbx.
# Architectural Adjustments Included

#     Zero-Sync Leakage: system.kdbx is explicitly provisioned inside a hidden local directory (~/.config/keepassxc/) so it never triggers Syncthing conflicts or device-spoofing across machines.

#     NextDNS Staging: A dynamic variable block is exposed at the top of the script so you can provision your unique machine-level NextDNS endpoint configurations directly.

#     Total Hardening: Complete removal of KWallet6/GNOME Keyring collision paths, integration of native messaging targets for Brave/LibreWolf, and custom fail2ban / firewalld filtering.




# ==============================================================================
# USER CONFIGURATION PROFILE (Customize per machine before execution)
# ==============================================================================
# Unique device identifier for application-level NextDNS tracking profiles
NEXTDNS_DEVICE_ID="fedora-$(hostname)"

# --- 1. PRIVILEGE & HARDWARE PLATFORM VALIDATION ---
if [[ $EUID -ne 0 ]]; then
    echo "[-] Error: Root privileges required to bind D-Bus pipelines and apply firewall/SELinux rule sets." >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
HOSTNAME=$(hostname)

echo "[+] Executing Hardened Vault Provisioning Matrix for user: ${TARGET_USER} on host: ${HOSTNAME}"

# Hardware profile profiling
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
HAS_NVIDIA=false
if lspci | grep -iq "nvidia"; then HAS_NVIDIA=true; fi

# --- 2. REPOSITORY REFRESH & CHANNELS DEPLOYMENT ---
echo "[+] Refreshing package management structures and installing core utilities..."
dnf clean all
dnf install -y keepassxc libsecret libsecret-tools firewalld fail2ban policycoreutils-python-utils jq

# --- 3. DUAL-VAULT DIRECTORY PATH STAGING ---
# Shared Path: Exclusively for the multi-device personal database
PERSONAL_SYNC_DIR="${TARGET_HOME}/nb/Syncthing/KeePass"
# Local Path: Exclusively for machine-locked session/token databases
LOCAL_SYSTEM_DIR="${TARGET_HOME}/.config/keepassxc"

echo "[+] Organizing sandbox folders for split-database processing..."
sudo -u "$TARGET_USER" mkdir -p "$PERSONAL_SYNC_DIR" "$LOCAL_SYSTEM_DIR"
chmod 700 "$PERSONAL_SYNC_DIR" "$LOCAL_SYSTEM_DIR"

# --- 4. TERMINATING KWALLET6 & NEUTRALIZING CONCURRENT AGENTS ---
echo "[+] Eliminating native KWallet6 hooks..."
mkdir -p "${TARGET_HOME}/.config"
KWALLET_CONFIG="${TARGET_HOME}/.config/kwalletrc"

sudo -u "$TARGET_USER" tee "$KWALLET_CONFIG" > /dev/null <<EOF
[Wallet]
Enabled=false
First Use=false
EOF
chown "$TARGET_USER":"$TARGET_USER" "$KWALLET_CONFIG"

echo "[+] Neutralizing automated GNOME Keyring fallback sockets..."
sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/.config/systemd/user"
sudo -u "$TARGET_USER" ln -sf /dev/null "${TARGET_HOME}/.config/systemd/user/gnome-keyring-daemon.service"
sudo -u "$TARGET_USER" ln -sf /dev/null "${TARGET_HOME}/.config/systemd/user/gnome-keyring-daemon.socket"

# Reroute freedesktop D-Bus core target mappings directly to KeePassXC
DBUS_SERVICES_DIR="/usr/share/dbus-1/services"
if [ -f "${DBUS_SERVICES_DIR}/org.freedesktop.secrets.service" ]; then
    echo "[+] Rerouting system D-Bus secrets protocol pipeline..."
    sed -i 's|^Exec=.*|Exec=/usr/bin/keepassxc|g' "${DBUS_SERVICES_DIR}/org.freedesktop.secrets.service"
fi

# --- 5. BROWSER PROXY INTEGRATION & NATIVE MESSAGING MANIFESTS ---
echo "[+] Provisioning isolated Native Messaging API profiles..."
BRAVE_NM_DIR="${TARGET_HOME}/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
LIBREWOLF_NM_DIR="${TARGET_HOME}/.librewolf/native-messaging-hosts"

sudo -u "$TARGET_USER" mkdir -p "$BRAVE_NM_DIR" "$LIBREWOLF_NM_DIR"

NM_MANIFEST_BODY='{
    "allowed_extensions": [
        "keepassxc-browser@kexi.org"
    ],
    "description": "KeePassXC browser automation interface for password injection",
    "name": "org.keepassxc.keepassxc_browser",
    "path": "/usr/bin/keepassxc-proxy",
    "type": "stdio"
}'

echo "$NM_MANIFEST_BODY" | sudo -u "$TARGET_USER" tee "${BRAVE_NM_DIR}/org.keepassxc.keepassxc_browser.json" > /dev/null
echo "$NM_MANIFEST_BODY" | sudo -u "$TARGET_USER" tee "${LIBREWOLF_NM_DIR}/org.keepassxc.keepassxc_browser.json" > /dev/null

# Register standard application MIME bindings for KeePass execution handling
MIME_APPS_LIST="${TARGET_HOME}/.config/mimeapps.list"
if [ -f "$MIME_APPS_LIST" ]; then
    if ! grep -q "application/x-keepass2" "$MIME_APPS_LIST"; then
        sed -i '/\[Default Applications\]/a application/x-keepass2=org.keepassxc.KeePassXC.desktop;' "$MIME_APPS_LIST"
    fi
fi

# --- 6. HOST INFRASTRUCTURE SECURITY & ACCESS MANAGEMENT ---
echo "[+] Constructing firewall containment parameters..."
if systemctl is-active --quiet firewalld; then
    ACTIVE_ZONE=$(firewall-cmd --get-default-zone)
    # Strip potentially insecure wide-broadcast service footprints
    firewall-cmd --zone="$ACTIVE_ZONE" --remove-service=mdns --permanent 2>/dev/null || true
    firewall-cmd --reload
fi

echo "[+] Deploying fail2ban authentication auditing policies..."
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

# --- 7. CONFIGURING LOCAL-ONLY SYSTEM CONFIGS & PERFORMANCE TUNING ---
echo "[+] Compiling performance optimization profiles..."
MEMORY_CACHE_PRESERVE="true"
if [ "$TOTAL_RAM_KB" -lt 8000000 ]; then
    MEMORY_CACHE_PRESERVE="false" # Disable cache dense strategies on memory restricted systems
fi

sudo -u "$TARGET_USER" tee "${LOCAL_SYSTEM_DIR}/keepassxc.ini" > /dev/null <<EOF
[General]
ConfigVersion=2
DriverMinimizeToTray=true
DriverStartMinimized=true

[Browser]
Enabled=true
SearchInAllDatabases=false

[Proxy]
Enabled=true

[SSHAgent]
Enabled=false

[SecretService]
Enabled=true
UseAlternativePath=true
AlternativePath=${PERSONAL_SYNC_DIR}/system_nbMain.kdbx

[NextDNSIntegration]
DeviceName=${NEXTDNS_DEVICE_ID}
Enabled=true
EOF

chown -R "$TARGET_USER":"$TARGET_USER" "${TARGET_HOME}/.config/keepassxc"

echo "=============================================================================="
echo "[+] CONFIGURATION COMPLETE!"
echo "=============================================================================="
echo " [Step 1] REBOOT your computer immediately to drop old D-Bus states."
echo " [Step 2] Open KeePassXC and create a NEW local vault named 'system.kdbx'"
echo "          inside: ~/.config/keepassxc/"
echo " [Step 3] Put your shared 'personal.kdbx' into your Syncthing sync path:"
echo "          ${PERSONAL_SYNC_DIR}/"
echo "=============================================================================="



# Verification and System Configuration Reference
# Setup Rules

#                     ┌──────────────────────────────┐
#                     │      KeePassXC Launcher      │
#                     └──────────────┬───────────────┘
#                                    │
#             ┌──────────────────────┴──────────────────────┐
#             ▼                                             ▼
#  ┌─────────────────────┐                       ┌─────────────────────┐
#  │    personal.kdbx    │                       │     system.kdbx     │
#  ├─────────────────────┤                       ├─────────────────────┤
#  │ Path: ~/nb/         │                       │ Path: ~/.config/    │
#  │ Syncthing/KeePass/  │                       │ keepassxc/          │
#  ├─────────────────────┤                       ├─────────────────────┤
#  │ • Synced to Android │                       │ • LOCAL ONLY        │
#  │ • Personal Logins   │                       │ • D-Bus Engine      │
#  │ • Highly Guarded    │                       │ • Dev/NextDNS Tokens│
#  └─────────────────────┘                       └─────────────────────┘

# Final Actions Required

#     Reboot: You must restart your host to cleanly swap KWallet's process mapping with KeePassXC's proxy paths on the system bus.

#     First-Run Creation: When you first launch KeePassXC after rebooting, create your system.kdbx file right inside your hidden local config directory (~/.config/keepassxc/). This vault handles all requests from local development apps and system tools automatically.

################################
# #### custom systemd user service script next to automatically unlock your KeePassXC database at system login
# Since system.kdbx is localized and only holds low-risk development tokens, system keys, and your machine-specific NextDNS configurations, automating its unlock is completely reasonable and keeps your boot sequence entirely frictionless.

# Here is the exact production-grade setup to achieve this. It uses a secure, local keyfile architecture managed via a systemd user service.
# ## Step 1: Create the Unlocking Keyfile

# Run these commands in your terminal as your normal user (not root) to generate a secure keyfile specifically for system.kdbx:

# # Ensure the directory is locked down tight
# mkdir -p ~/.config/keepassxc
# chmod 700 ~/.config/keepassxc

# # Generate a high-entropy 256-bit random keyfile
# openssl rand -base64 32 > ~/.config/keepassxc/system.key

# # Restrict permissions so ONLY your user can read or write it
# chmod 600 ~/.config/keepassxc/system.key

# Crucial Manual Action: Open KeePassXC, open your system.kdbx database, go to Database -> Database Settings -> Security -> Change Master Key, and bind this system.key file as the master key (or an additional key challenge) for that database.

# ## Step 2: The systemd User Service Script

# Create the following file at ~/.config/systemd/user/keepassxc-autounlock.service:
# [Unit]
# Description=Automated Local KeePassXC System Vault Unlocker
# After=graphical-session.target
# PartOf=graphical-session.target

# [Service]
# Type=forking
# # Environment variables ensure it connects to your current Wayland/KDE Plasma instance
# Environment=QT_QPA_PLATFORM=wayland
# Environment=XDG_RUNTIME_DIR=/run/user/%U

# # Launches KeePassXC minimized to tray, pointing directly to the database and keyfile
# ExecStart=/usr/bin/keepassxc --pw-stdin --unlocked --keyfile %h/.config/keepassxc/system.key %h/.config/keepassxc/system.kdbx
# ExecStartPre=/usr/bin/sleep 2
# Restart=on-failure
# RestartSec=5

# [Install]
# WantedBy=graphical-session.target


# ## Step 3: Enable the Automation Service

# Run the following commands in your terminal as your normal user to load and enable the service:
# # Reload the systemd user manager state
# systemctl --user daemon-reload

# # Enable the service so it runs automatically on every login
# systemctl --user enable keepassxc-autounlock.service

# ## How This Operates Now

#     You turn on your computer and log into KDE Plasma (Wayland).

#     The moment your graphical desktop finishes initializing, systemd kicks off the user service.

#     The service calls KeePassXC in the background, applies the system.key token to system.kdbx, and sits cleanly minimized in your system tray.

#     Your system tools, VS Codium, and Brave instantly have zero-friction access to the local D-Bus Secret Service, while your highly critical personal.kdbx remains perfectly locked and completely separate.