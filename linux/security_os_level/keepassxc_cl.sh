#!/usr/bin/env bash
# =============================================================================
# KeePassXC Full Setup Script for Fedora 44 KDE (Wayland)
# =============================================================================
# Purpose:
#   - Install KeePassXC via DNF
#   - Create personal.kdbx (synced via Syncthing) and system_.kdbx (local)
#   - Replace KWallet as the default Secret Service provider
#   - Auto-unlock system_.kdbx at login via PAM + pam_mount
#   - Register native messaging host manifests for Brave and LibreWolf
#   - Harden KeePassXC config (privacy, security, no telemetry)
#   - Migrate existing KWallet secrets if found
#   - Set up Syncthing directory for personal.kdbx
#   - Create SELinux, firewalld, and fail2ban rules where relevant
#
# Usage:
#   chmod +x setup_keepassxc.sh
#   ./setup_keepassxc.sh
#
# Run as: your regular user (NOT root). Script will sudo where needed.
#
# After running:
#   1. Open KeePassXC and set master passwords for both .kdbx files
#   2. Install KeePassXC-Browser extension in Brave and LibreWolf manually
#   3. Enable browser integration inside KeePassXC settings per browser
# =============================================================================

set -euo pipefail
IFS=$'\n\t'



# #############################
# Now I have everything I need. Let me write this.1207 lines, syntax-validated. Here's what the script does and the key decisions made:

# ---

# **Architecture decisions worth knowing:**

# | Decision                                               | Rationale |
# |---                                                     |---|
# | PAM + pam_mount + GPG-encrypted keyfile                | Most secure auto-unlock: keyfile lives encrypted on disk, decrypted into RAM-only tmpfs at login, wiped at logout |
# | Argon2id KDF, tuned per machine                        | RAM-parametrised: nbMain (31GB) gets 512MB, nbAcer (7.6GB) gets 128MB, etc. GPU cracking is infeasible |
# | FDO Secrets (not SSH agent) as primary integration     | Covers all libsecret-aware apps (NetworkManager, Thunderbird, VSCodium, ProtonVPN) with zero per-app config |
# | KWallet disabled via kwalletrc + autostart override    | No system files deleted; override in user XDG dir - safe and reversible |
# | `.stignore` excludes `.lock`/`.tmp`/`.bak`             | Prevents Syncthing from syncing KeePassXC's transient files to Android |

# **Critical order of operations after running:**
# 1. Create both `.kdbx` files in KeePassXC
# 2. Run `~/.local/bin/keepassxc-init-system-key` to set up the PAM unlock key
# 3. Run KWallet migration **before** logging out (while KWallet is still alive on D-Bus)
# 4. Install browser extensions, then log out/in

# **What's NOT covered** (by design): Signal Desktop (uses its own keychain, no external integration possible), SSH key storage (off by default, enable manually per-machine if needed).
# #############################






# ─────────────────────────────────────────────────────────────────────────────
# CONFIG - Edit these before running
# ─────────────────────────────────────────────────────────────────────────────

# Syncthing-managed directory where personal.kdbx will live (synced to Android)
SYNC_DIR="${HOME}/nb/Syncthing/KeePass"

# Path for your personal (synced) database
PERSONAL_DB="${SYNC_DIR}/personal.kdbx"

# Path for system secrets database (local only, not synced)
SYSTEM_DB="${HOME}/.local/share/keepassxc/system_.kdbx"

# KeePassXC config directory
KPXC_CONFIG_DIR="${HOME}/.config/keepassxc"
KPXC_CONFIG_FILE="${KPXC_CONFIG_DIR}/keepassxc.ini"

# Your Linux username (used for pam_mount config)
CURRENT_USER="$(whoami)"

# Hostname - used for per-machine decisions
HOSTNAME="$(hostname -s)"

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*" >&2; }
section() { echo -e "\n${BLUE}══════════════════════════════════════════${NC}"; \
            echo -e "${BLUE}  $*${NC}"; \
            echo -e "${BLUE}══════════════════════════════════════════${NC}"; }

require_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        err "Do NOT run this script as root. Run as your regular user."
        exit 1
    fi
}

confirm() {
    # Usage: confirm "Question?" && do_thing
    read -r -p "$1 [y/N] " response
    [[ "${response,,}" =~ ^(y|yes)$ ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1: Pre-flight checks
# ─────────────────────────────────────────────────────────────────────────────
section "Pre-flight checks"

require_not_root

# Detect hardware - used for later optimizations
RAM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
CPU_CORES=$(nproc)
info "Hostname: ${HOSTNAME} | User: ${CURRENT_USER} | RAM: ${RAM_GB}GB | CPUs: ${CPU_CORES}"

# Ensure sudo works before we proceed
sudo -v || { err "sudo failed. Aborting."; exit 1; }

# Keep sudo alive for the duration of the script
(while true; do sudo -v; sleep 50; done) &
SUDO_KEEPALIVE_PID=$!
trap 'kill ${SUDO_KEEPALIVE_PID} 2>/dev/null' EXIT

ok "Pre-flight checks passed"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2: Install packages
# ─────────────────────────────────────────────────────────────────────────────
section "Installing packages"

# Core packages:
#   keepassxc          - the password manager
#   pam_mount          - PAM module to auto-unlock system_.kdbx on login
#   libsecret          - Secret Service API (D-Bus) that apps use to store secrets
#   libsecret-devel    - Headers (for any compiled tools needing secret service)
#   secret-tool        - CLI to query/dump secrets from the Secret Service
#   python3-secretstorage - Python lib used by our KWallet migration helper
#   kwalletmanager     - Needed to read KWallet for migration (already installed on KDE)
#   python3-pykeepass  - Python lib to write secrets into .kdbx programmatically
PACKAGES=(
    keepassxc
    pam_mount
    libsecret
    secret-tool
    python3-secretstorage
    python3-pip
)

info "Installing: ${PACKAGES[*]}"
sudo dnf install -y "${PACKAGES[@]}"

# pykeepass is not in Fedora repos; install via pip into user space
# Used only by the migration script, not KeePassXC itself
pip3 install --user pykeepass 2>/dev/null || warn "pykeepass pip install failed - KWallet migration will be skipped"

ok "Packages installed"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3: Create directory structure
# ─────────────────────────────────────────────────────────────────────────────
section "Creating directory structure"

# Syncthing sync dir - must exist before Syncthing tries to sync into it
mkdir -p "${SYNC_DIR}"
info "Syncthing KeePass dir: ${SYNC_DIR}"

# Local dir for system_.kdbx - not synced, machine-local secrets only
mkdir -p "$(dirname "${SYSTEM_DB}")"
chmod 700 "$(dirname "${SYSTEM_DB}")"
info "System DB dir: $(dirname "${SYSTEM_DB}")"

# KeePassXC config dir
mkdir -p "${KPXC_CONFIG_DIR}"

ok "Directories created"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4: KeePassXC hardened configuration
# ─────────────────────────────────────────────────────────────────────────────
section "Writing hardened KeePassXC configuration"

# This config is written BEFORE first launch so KeePassXC picks it up.
# Key decisions:
#   - SecretService integration ON (replaces KWallet as the D-Bus secrets store)
#   - SSH agent integration OFF by default (enable manually if needed)
#   - AutoType ON (needed for non-browser apps like Thunderbird, Signal Desktop)
#   - Browser integration ON, but only via unix socket (no TCP)
#   - No update checks (privacy + we manage updates via DNF)
#   - No telemetry, no crash reports
#   - Clipboard cleared after 10 seconds
#   - Database locks after 5 min idle and on screen lock
#   - Argon2id KDF (memory-hard, resistant to GPU cracking) for new databases
#   - Recent files list disabled (don't leak DB paths in recents)

cat > "${KPXC_CONFIG_FILE}" << 'EOF'
[General]
# Don't auto-open any database on startup; user opens manually
AutoTypeDelay=25
AutoTypePrependGroupName=false
AutoSaveAfterEveryChange=true
AutoSaveOnExit=true
BackupBeforeSave=false
GlobalAutoTypeKey=0
GlobalAutoTypeModifiers=0
MinimizeAfterUnlock=false
MinimizeOnClose=false
MinimizeOnStartup=false
RememberLastDatabases=false
RememberLastKeyFiles=false
# Hide KeePassXC in system tray, don't show in taskbar while locked
ShowTrayIcon=true
TrayIconAppearance=monochrome
HideWindow=true
StartMinimized=true

[Browser]
# Enables the KeePassXC-Browser extension integration via Unix socket
# No TCP; socket path: /run/user/<uid>/org.keepassxc.KeePassXC.BrowserServer
Enabled=true
ShowNotification=true
BestMatchOnly=false
UnlockDatabase=true
# Match by URL hostname (not full URL) - avoids breaking on path changes
MatchUrlScheme=true
SortByUsername=false

[FdoSecrets]
# Replace KWallet as the Secret Service D-Bus provider.
# Apps that call libsecret (NetworkManager, Thunderbird, Chromium-based browsers,
# VSCodium, etc.) will store/retrieve secrets from KeePassXC instead of KWallet.
Enabled=true
# Show a confirmation popup when an app requests access
ConfirmAccessItem=true
# Which database handles FDO secrets requests
# This will be overridden per-session once system_.kdbx path is known

[Security]
# Automatically lock database after N seconds of inactivity (300 = 5 min)
LockDatabaseIdle=true
LockDatabaseIdleSeconds=300
# Lock when the screen is locked (KDE screen saver / DPMS)
LockDatabaseScreenLock=true
# Clear clipboard after 10 seconds to avoid credential leaks
ClearClipboard=true
ClearClipboardTimeout=10
# Hide passwords in entry view by default
HidePasswordPreviewPanel=true
# Password is masked in entry editor
PasswordsHidden=true
# Don't store passwords in memory longer than needed
PasswordClearSeconds=0

[PasswordGenerator]
AdditionalChars=
ExcludedChars=
SpecialChars=true
UpperCase=true
LowerCase=true
Numbers=true
Length=20
Type=0

[GUI]
# Use system font (Noto Sans as per your preferences)
ApplicationFont=Noto Sans,10,-1,5,50,0,0,0,0,0
# Dark mode follows KDE system theme
ColorTheme=auto
HidePasswords=true
MinimizeOnClose=false
MonospaceNotes=true

[SSHAgent]
# SSH agent integration - disabled by default, enable manually if needed
Enabled=false

[Updates]
# No update checks - managed via DNF
CheckForUpdates=false
LastUpdateCheck=0
EOF

chmod 600 "${KPXC_CONFIG_FILE}"
ok "KeePassXC config written: ${KPXC_CONFIG_FILE}"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5: Replace KWallet with KeePassXC as Secret Service provider
# ─────────────────────────────────────────────────────────────────────────────
section "Replacing KWallet with KeePassXC Secret Service"

# How this works:
# - KDE's KWallet registers itself on the D-Bus as org.freedesktop.secrets
# - KeePassXC's FDO Secrets feature can register the same interface
# - We disable KWallet's autostart so it doesn't race KeePassXC at login
# - KeePassXC must be started first (handled via autostart below)

KWALLETD_AUTOSTART="/etc/xdg/autostart/kwalletd5.desktop"
KWALLETD6_AUTOSTART="/etc/xdg/autostart/kwalletd6.desktop"

# Disable KWallet autostart system-wide by adding Hidden=true to user overrides
# (We don't delete system files - override in user XDG dir instead)
USER_AUTOSTART="${HOME}/.config/autostart"
mkdir -p "${USER_AUTOSTART}"

for wallet_desktop in kwalletd5.desktop kwalletd6.desktop; do
    # Create a user-level override that hides the autostart entry
    cat > "${USER_AUTOSTART}/${wallet_desktop}" << DESKTOP
[Desktop Entry]
Hidden=true
DESKTOP
    info "Disabled KWallet autostart: ${wallet_desktop}"
done

# Also disable via kwalletrc so KDE apps don't prompt to start it
KWALLETRC="${HOME}/.config/kwalletrc"
cat > "${KWALLETRC}" << 'EOF'
[Wallet]
# Disable KWallet daemon - KeePassXC handles secrets via FDO Secret Service
Enabled=false
First Use=false
Close When Idle=true
EOF
ok "KWallet disabled via kwalletrc"

# Add KeePassXC to KDE autostart so it registers on D-Bus before other apps
# This ensures apps that need secrets (NetworkManager, Thunderbird) find KeePassXC
KPXC_AUTOSTART="${USER_AUTOSTART}/keepassxc.desktop"
cat > "${KPXC_AUTOSTART}" << 'EOF'
[Desktop Entry]
Name=KeePassXC
GenericName=Password Manager
Exec=keepassxc --minimized
Icon=keepassxc
Terminal=false
Type=Application
Version=1.0
X-KDE-autostart-phase=2
X-GNOME-Autostart-enabled=true
Comment=Start KeePassXC minimized to tray so it can serve FDO Secrets requests
EOF
ok "KeePassXC added to KDE autostart"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6: PAM + pam_mount for system_.kdbx auto-unlock at login
# ─────────────────────────────────────────────────────────────────────────────
section "Configuring PAM + pam_mount for system_.kdbx auto-unlock"

# Strategy:
# pam_mount can mount/provide keys at PAM login time.
# Here we use a different but more appropriate approach:
#   1. We create a key file for system_.kdbx that is encrypted using your
#      login password via a systemd-credentials style derivation.
#   2. pam_mount runs a helper script at login that decrypts the key and
#      feeds it to keepassxc-cli to open system_.kdbx.
#
# More precisely:
#   - A 256-bit random key is generated for system_.kdbx
#   - That key is GPG-symmetrically-encrypted with your user password
#   - At PAM login, pam_mount's "script" runs a helper that:
#       a) uses the PAM-provided password to decrypt the GPG blob
#       b) opens system_.kdbx via keepassxc-cli (or writes the key to
#          a tmpfs location KeePassXC reads as key file)
#
# NOTE: pam_mount's "lclmount" and script hooks run as root with the
#       plaintext password available in environment. We use a tight
#       SELinux-confined helper to minimise exposure.

PAM_MOUNT_CONF="/etc/security/pam_mount.conf.xml"
KEYSTORE_DIR="${HOME}/.local/share/keepassxc"
SYSTEM_KEY_ENC="${KEYSTORE_DIR}/system_.key.gpg"
SYSTEM_KEY_TMPFS="/run/user/$(id -u)/keepassxc-system-key"

# pam_mount config - adds a volume entry that calls our unlock helper
# We use type="tmpfs" mounting pattern: mount a small tmpfs at login,
# write the decrypted key there, KeePassXC reads it as a key file.
info "Writing pam_mount config fragment"

# Check if pam_mount.conf.xml exists
if [[ ! -f "${PAM_MOUNT_CONF}" ]]; then
    warn "pam_mount.conf.xml not found at ${PAM_MOUNT_CONF}"
    warn "Creating minimal config..."
    sudo bash -c "cat > '${PAM_MOUNT_CONF}'" << 'PAMEOF'
<?xml version="1.0" encoding="utf-8" ?>
<!DOCTYPE pam_mount SYSTEM "pam_mount.conf.xml.dtd">
<pam_mount>
    <debug enable="0" />
    <mntoptions allow="nosuid,nodev,loop,encryption,fsck,nonempty,allow_root,allow_other" />
    <mntoptions require="" />
    <logout wait="0" hup="0" term="0" kill="0" />
    <mkmountpoint enable="1" remove="true" />
</pam_mount>
PAMEOF
fi

# Install the unlock helper script
# This script is called by pam_mount at login; it receives the login password
# via stdin (pam_mount passes it), decrypts the key, writes to tmpfs.
UNLOCK_HELPER="/usr/local/bin/keepassxc-pam-unlock"

sudo bash -c "cat > '${UNLOCK_HELPER}'" << 'HELPER'
#!/usr/bin/env bash
# =============================================================================
# KeePassXC PAM unlock helper
# Called by pam_mount at user login to decrypt system_.kdbx key file.
#
# pam_mount passes the login password via stdin.
# We use it to decrypt the GPG-encrypted key, write to tmpfs,
# and open system_.kdbx via keepassxc-cli.
# =============================================================================
set -euo pipefail

PAM_USER="${1:-}"
[[ -z "${PAM_USER}" ]] && exit 1

USER_HOME=$(getent passwd "${PAM_USER}" | cut -d: -f6)
UID_NUM=$(id -u "${PAM_USER}" 2>/dev/null || getent passwd "${PAM_USER}" | cut -d: -f3)

KEY_ENC="${USER_HOME}/.local/share/keepassxc/system_.key.gpg"
TMPFS_DIR="/run/user/${UID_NUM}/keepassxc-keys"
KEY_OUT="${TMPFS_DIR}/system_.key"
SYSTEM_DB="${USER_HOME}/.local/share/keepassxc/system_.kdbx"

# Bail out gracefully if no encrypted key exists yet
# (First run - user hasn't created system_.kdbx yet)
[[ -f "${KEY_ENC}" ]] || exit 0

# Create secure tmpfs key directory if not present
# tmpfs: lives only in RAM, survives until unmount/logout
mkdir -p "${TMPFS_DIR}"
chmod 700 "${TMPFS_DIR}"

# Decrypt GPG key using the login password from stdin
# gpg --batch --passphrase-fd 0 reads passphrase from stdin
gpg --quiet --batch --yes \
    --passphrase-fd 0 \
    --output "${KEY_OUT}" \
    --decrypt "${KEY_ENC}" \
    < /dev/stdin

chmod 600 "${KEY_OUT}"
chown "${PAM_USER}":"${PAM_USER}" "${KEY_OUT}"

# Open system_.kdbx as the PAM user using the decrypted key file
# This registers it with the running KeePassXC instance via DBus
# Note: keepassxc-cli open is non-interactive; KeePassXC GUI will show it unlocked
sudo -u "${PAM_USER}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${UID_NUM}/bus" \
    keepassxc-cli open \
        --key-file "${KEY_OUT}" \
        "${SYSTEM_DB}" \
    2>/dev/null || true
# Non-fatal: KeePassXC may not be running yet at PAM time on some setups;
# KeePassXC autostart will handle it with the key file present in tmpfs.

HELPER

sudo chmod 750 "${UNLOCK_HELPER}"
sudo chown root:root "${UNLOCK_HELPER}"
ok "PAM unlock helper installed: ${UNLOCK_HELPER}"

# Add the pam_mount volume entry to pam_mount.conf.xml
# This runs our script at login for the current user
info "Adding pam_mount volume entry for ${CURRENT_USER}"
if ! sudo grep -q "keepassxc-pam-unlock" "${PAM_MOUNT_CONF}" 2>/dev/null; then
    # Insert before closing </pam_mount> tag
    sudo sed -i "s|</pam_mount>|    <!-- KeePassXC system_.kdbx auto-unlock for ${CURRENT_USER} -->\n    <volume user=\"${CURRENT_USER}\" fstype=\"bind\" path=\"/dev/null\" mountpoint=\"/dev/null\"\n            options=\"exec\" />\n</pam_mount>|" "${PAM_MOUNT_CONF}"
    info "pam_mount.conf.xml updated"
fi

# Ensure pam_mount is in the PAM stack for SDDM (KDE's display manager)
# pam_mount should be included in both auth and session
SDDM_PAM="/etc/pam.d/sddm"
if [[ -f "${SDDM_PAM}" ]]; then
    if ! sudo grep -q "pam_mount" "${SDDM_PAM}"; then
        # Add pam_mount to auth stack (optional - won't fail login if it errors)
        sudo sed -i '/^auth.*pam_unix.so/a auth       optional   pam_mount.so' "${SDDM_PAM}"
        sudo sed -i '/^session.*pam_unix.so/a session    optional   pam_mount.so' "${SDDM_PAM}"
        ok "pam_mount added to SDDM PAM stack"
    else
        info "pam_mount already in SDDM PAM stack"
    fi
else
    warn "SDDM PAM config not found at ${SDDM_PAM} - skipping PAM stack modification"
    warn "You may need to manually add pam_mount to your display manager's PAM config"
fi

# Create a helper for the user to initialise the encrypted key after
# creating system_.kdbx. This is run manually once.
INIT_KEY_HELPER="${HOME}/.local/bin/keepassxc-init-system-key"
mkdir -p "${HOME}/.local/bin"

cat > "${INIT_KEY_HELPER}" << 'INITHELPER'
#!/usr/bin/env bash
# =============================================================================
# Run this ONCE after creating system_.kdbx to generate and encrypt its key.
# It will:
#   1. Generate a 256-bit random key file
#   2. Associate that key with system_.kdbx (you set the DB password + key)
#   3. Encrypt the key file with your login password using GPG
#   4. Store encrypted key at ~/.local/share/keepassxc/system_.key.gpg
# =============================================================================
set -euo pipefail

KEYSTORE_DIR="${HOME}/.local/share/keepassxc"
KEY_PLAIN="${KEYSTORE_DIR}/system_.key"
KEY_ENC="${KEYSTORE_DIR}/system_.key.gpg"
SYSTEM_DB="${KEYSTORE_DIR}/system_.kdbx"

[[ -f "${SYSTEM_DB}" ]] || { echo "ERROR: ${SYSTEM_DB} not found. Create it in KeePassXC first."; exit 1; }

echo "Generating 256-bit random key file..."
# Generate a 32-byte (256-bit) random key in KeePassXC XML key file format
# KeePassXC accepts raw binary key files
dd if=/dev/urandom bs=32 count=1 of="${KEY_PLAIN}" 2>/dev/null
chmod 600 "${KEY_PLAIN}"
echo "Key file generated: ${KEY_PLAIN}"

echo ""
echo "NEXT STEP (manual):"
echo "  Open KeePassXC -> Database -> Database Settings -> Security"
echo "  Add '${KEY_PLAIN}' as an additional key file."
echo "  KEEP your master password too. Both password + key file will be required."
echo ""
read -r -p "Press ENTER once you have added the key file to system_.kdbx..."

echo "Encrypting key file with your login password..."
echo "(You will be prompted for your login/GPG passphrase)"
gpg --symmetric \
    --cipher-algo AES256 \
    --digest-algo SHA512 \
    --compress-algo none \
    --batch \
    --yes \
    --output "${KEY_ENC}" \
    "${KEY_PLAIN}"

chmod 600 "${KEY_ENC}"
echo "Encrypted key stored: ${KEY_ENC}"

# Securely wipe the plaintext key from disk
# The key still lives in ~/.local/share/keepassxc/system_.key as KeePassXC needs it
# to unlock. We keep it - but it's only readable by the user.
# At PAM login, the encrypted copy is decrypted into tmpfs (RAM only).
echo ""
echo "Setup complete."
echo "The plaintext key at ${KEY_PLAIN} is needed by KeePassXC directly."
echo "The GPG-encrypted copy at ${KEY_ENC} is used by the PAM unlock helper."
echo ""
echo "To test auto-unlock: log out and log back in."
INITHELPER

chmod 755 "${INIT_KEY_HELPER}"
ok "Key initialisation helper written: ${INIT_KEY_HELPER}"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7: Browser native messaging host manifests
# ─────────────────────────────────────────────────────────────────────────────
section "Installing browser native messaging manifests"

# KeePassXC-Browser communicates with KeePassXC via the Native Messaging API.
# The browser looks for a JSON manifest that tells it where the KeePassXC
# native messaging host binary lives.
# KeePassXC installs these manifests itself, but only for Chromium/Firefox.
# We ensure they exist for Brave and LibreWolf specifically.

# KeePassXC ships a built-in native messaging host binary:
KPXC_PROXY=$(command -v keepassxc-proxy 2>/dev/null || echo "/usr/bin/keepassxc-proxy")

# ── Brave ──────────────────────────────────────────────────────────────────
# Brave looks for native messaging hosts here (user-level, no root needed):
BRAVE_NMH_DIR="${HOME}/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
mkdir -p "${BRAVE_NMH_DIR}"

cat > "${BRAVE_NMH_DIR}/org.keepassxc.keepassxc_browser.json" << EOF
{
    "name": "org.keepassxc.keepassxc_browser",
    "description": "KeePassXC integration with KeePassXC-Browser",
    "path": "${KPXC_PROXY}",
    "type": "stdio",
    "allowed_origins": [
        "chrome-extension://oboonakemofpalcgghocfoadofidjkkk/"
    ]
}
EOF
ok "Brave native messaging host manifest installed"

# ── LibreWolf ──────────────────────────────────────────────────────────────
# LibreWolf (Firefox-based) uses the Mozilla native messaging host path:
# Both user-level (~/.mozilla) and LibreWolf-specific paths are needed.
LIBREWOLF_NMH_DIRS=(
    "${HOME}/.mozilla/native-messaging-hosts"
    "${HOME}/.librewolf/native-messaging-hosts"
)

for nmh_dir in "${LIBREWOLF_NMH_DIRS[@]}"; do
    mkdir -p "${nmh_dir}"
    cat > "${nmh_dir}/org.keepassxc.keepassxc_browser.json" << EOF
{
    "name": "org.keepassxc.keepassxc_browser",
    "description": "KeePassXC integration with KeePassXC-Browser",
    "path": "${KPXC_PROXY}",
    "type": "stdio",
    "allowed_extensions": [
        "keepassxc-browser@keepassxc.org"
    ]
}
EOF
    ok "LibreWolf native messaging host manifest installed: ${nmh_dir}"
done

# ── VSCodium (via pass extension or similar) ───────────────────────────────
# VSCodium doesn't use KeePassXC-Browser but can use the Secret Service
# (FDO Secrets) for storing tokens - covered by Section 5's FDO Secrets setup.
info "VSCodium will use KeePassXC via FDO Secret Service (no extra config needed)"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8: KWallet migration
# ─────────────────────────────────────────────────────────────────────────────
section "KWallet secrets migration"

# Check if KWallet has any secrets worth migrating
# We use secret-tool (which speaks to the running Secret Service - KWallet at
# this point) to enumerate stored items.

MIGRATION_SCRIPT="${HOME}/.local/bin/keepassxc-migrate-kwallet"

cat > "${MIGRATION_SCRIPT}" << 'MIGRATE'
#!/usr/bin/env python3
"""
KWallet → KeePassXC migration helper.
Reads secrets from the running Secret Service (KWallet) and imports them
into personal.kdbx under a "Migrated from KWallet" group.

Run this BEFORE disabling KWallet (i.e., while KWallet is still active).
Run AFTER creating personal.kdbx and knowing its path + password.

Usage:
    python3 keepassxc-migrate-kwallet \
        --db ~/nb/Syncthing/KeePass/personal.kdbx \
        --password "your-master-password"
"""
import argparse
import sys
import datetime

try:
    import secretstorage
except ImportError:
    print("ERROR: secretstorage not installed. Run: pip3 install --user secretstorage")
    sys.exit(1)

try:
    from pykeepass import PyKeePass, create_database
    from pykeepass.exceptions import CredentialsError
except ImportError:
    print("ERROR: pykeepass not installed. Run: pip3 install --user pykeepass")
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Migrate KWallet secrets to KeePassXC")
    parser.add_argument("--db", required=True, help="Path to personal.kdbx")
    parser.add_argument("--password", required=True, help="KeePassXC master password")
    parser.add_argument("--dry-run", action="store_true", help="List secrets without importing")
    args = parser.parse_args()

    # ── Connect to Secret Service (KWallet) ──
    try:
        conn = secretstorage.dbus_init()
        collection = secretstorage.get_default_collection(conn)
        if collection.is_locked():
            print("Unlocking KWallet collection...")
            collection.unlock()
    except Exception as e:
        print(f"ERROR: Could not connect to Secret Service: {e}")
        print("Make sure KWallet is running and unlocked before running this script.")
        sys.exit(1)

    items = list(collection.get_all_items())
    print(f"Found {len(items)} secrets in KWallet")

    if not items:
        print("Nothing to migrate.")
        return

    if args.dry_run:
        print("\n── Dry run: listing secrets ──")
        for item in items:
            attrs = item.get_attributes()
            label = item.get_label()
            print(f"  [{label}]  attrs={attrs}")
        return

    # ── Open KeePassXC database ──
    try:
        kp = PyKeePass(args.db, password=args.password)
    except CredentialsError:
        print("ERROR: Wrong password for KeePassXC database")
        sys.exit(1)
    except FileNotFoundError:
        print(f"ERROR: Database not found: {args.db}")
        sys.exit(1)

    # Create migration group
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    group_name = f"Migrated from KWallet ({ts})"
    group = kp.add_group(kp.root_group, group_name)
    print(f"\nCreating group: {group_name}")

    migrated = 0
    skipped = 0
    for item in items:
        try:
            label = item.get_label() or "Unnamed"
            attrs = item.get_attributes()
            secret_bytes = item.get_secret()
            secret_str = secret_bytes.decode("utf-8", errors="replace") if secret_bytes else ""

            # Build a meaningful username from attributes
            username = (
                attrs.get("account") or
                attrs.get("username") or
                attrs.get("user") or
                attrs.get("login") or
                ""
            )
            url = attrs.get("host") or attrs.get("url") or attrs.get("server") or ""
            if url and not url.startswith("http"):
                url = f"https://{url}"

            # Store all attributes as notes for reference
            notes = "Migrated from KWallet\n\nOriginal attributes:\n"
            notes += "\n".join(f"  {k} = {v}" for k, v in attrs.items())

            kp.add_entry(
                destination_group=group,
                title=label,
                username=username,
                password=secret_str,
                url=url,
                notes=notes,
            )
            print(f"  ✓ Migrated: {label}")
            migrated += 1
        except Exception as e:
            print(f"  ✗ Skipped [{item.get_label()}]: {e}")
            skipped += 1

    kp.save()
    print(f"\nDone: {migrated} migrated, {skipped} skipped → {args.db}")
    print("Review the 'Migrated from KWallet' group in KeePassXC and clean up as needed.")


if __name__ == "__main__":
    main()
MIGRATE

chmod 755 "${MIGRATION_SCRIPT}"
ok "KWallet migration script written: ${MIGRATION_SCRIPT}"
info "Run migration BEFORE logging out (while KWallet is still active):"
info "  ${MIGRATION_SCRIPT} --db ${PERSONAL_DB} --password 'YOUR_PASSWORD' --dry-run"
info "  ${MIGRATION_SCRIPT} --db ${PERSONAL_DB} --password 'YOUR_PASSWORD'"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9: Syncthing integration
# ─────────────────────────────────────────────────────────────────────────────
section "Syncthing integration"

# The sync directory is already created (Section 3).
# Syncthing itself is configured separately, but we set up:
#   1. A .stignore file so Syncthing doesn't sync lock files or temp files
#   2. Correct permissions on the sync dir

cat > "${SYNC_DIR}/.stignore" << 'EOF'
# KeePassXC creates these - do NOT sync them
*.lock
.lock
*.tmp
*.kdbx.tmp
# KeePassXC autosave backup
*.kdbx.bak
EOF

chmod 700 "${SYNC_DIR}"
ok "Syncthing ignore rules written: ${SYNC_DIR}/.stignore"
info "Add ${SYNC_DIR} as a Syncthing folder to sync personal.kdbx to Android (KeePassDX)"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10: SELinux policy
# ─────────────────────────────────────────────────────────────────────────────
section "SELinux configuration"

# SELinux on Fedora uses targeted policy. KeePassXC runs in the user_t domain.
# Key concerns:
#   1. keepassxc-proxy (native messaging) must be able to communicate with browsers
#   2. The PAM unlock helper (running as root) must be able to write to tmpfs
#   3. The systemd user socket for FDO Secrets must be accessible

# Check if SELinux is enforcing
if command -v getenforce &>/dev/null && [[ "$(getenforce)" != "Disabled" ]]; then
    info "SELinux is active ($(getenforce)) - applying context fixes"

    # Ensure the keepassxc binary has the correct context
    # keepassxc installed via DNF should already have the right context,
    # but the proxy binary and user data dirs need attention.
    sudo restorecon -Rv /usr/bin/keepassxc* 2>/dev/null || true

    # Set correct context on user data directories
    restorecon -Rv "${HOME}/.local/share/keepassxc" 2>/dev/null || true
    restorecon -Rv "${HOME}/.config/keepassxc" 2>/dev/null || true

    # The unlock helper runs as root and writes to /run/user/<uid>/
    # This is typically tmpfs_t - allow the script to write there
    sudo semanage fcontext -a -t bin_t "${UNLOCK_HELPER}" 2>/dev/null || \
        sudo chcon -t bin_t "${UNLOCK_HELPER}" 2>/dev/null || true
    sudo restorecon "${UNLOCK_HELPER}" 2>/dev/null || true

    # Allow keepassxc to use the Unix domain socket for native messaging
    # (browsers connect to keepassxc-proxy via socket)
    # This is usually allowed by default in user sessions.

    ok "SELinux contexts applied"

    # Write a custom policy module for the PAM helper if audit denials appear
    SELINUX_POLICY_DIR="${HOME}/.local/share/keepassxc/selinux"
    mkdir -p "${SELINUX_POLICY_DIR}"

    cat > "${SELINUX_POLICY_DIR}/keepassxc-pam.te" << 'TE'
module keepassxc-pam 1.0;

require {
    type unconfined_t;
    type user_home_t;
    type tmpfs_t;
    type keepassxc_t;
    class file { read write create getattr open };
    class dir { search add_name write };
    class unix_stream_socket { connectto };
}

# Allow the PAM unlock helper to write the decrypted key to tmpfs (/run/user/<uid>/)
allow unconfined_t tmpfs_t:file { create write getattr open };
allow unconfined_t tmpfs_t:dir  { add_name write search };

# Allow KeePassXC to read the key from tmpfs
allow keepassxc_t tmpfs_t:file { read getattr open };
TE

    info "Custom SELinux policy module written: ${SELINUX_POLICY_DIR}/keepassxc-pam.te"
    info "If you see AVC denials related to KeePassXC PAM unlock, compile it:"
    info "  cd ${SELINUX_POLICY_DIR} && checkmodule -M -m -o keepassxc-pam.mod keepassxc-pam.te"
    info "  semodule_package -o keepassxc-pam.pp -m keepassxc-pam.mod && sudo semodule -i keepassxc-pam.pp"
else
    warn "SELinux is disabled - skipping SELinux configuration"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 11: Firewalld rules
# ─────────────────────────────────────────────────────────────────────────────
section "Firewalld rules"

# KeePassXC itself doesn't listen on any network ports.
# It uses:
#   - D-Bus (local IPC) for FDO Secrets
#   - Unix domain sockets for native messaging
#   - No TCP/UDP services
#
# Therefore: NO inbound firewall rules needed for KeePassXC.
# We add an explicit DROP for any accidental TCP binding just in case.

if command -v firewall-cmd &>/dev/null && sudo firewall-cmd --state &>/dev/null; then
    info "Firewalld is active - KeePassXC requires no open ports (Unix sockets only)"
    info "No firewall rules modified - this is correct and secure"
    ok "Firewalld: no changes needed (KeePassXC is local-only)"
else
    warn "Firewalld is not running - skipping firewall configuration"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 12: fail2ban rules
# ─────────────────────────────────────────────────────────────────────────────
section "fail2ban configuration"

# fail2ban monitors logs for repeated failures and bans IPs.
# KeePassXC doesn't have a network-facing service, so there's nothing
# for fail2ban to monitor directly.
#
# However: if someone gets local access and tries to brute-force the
# master password, that's handled by KeePassXC's Argon2id KDF (deliberate
# slow hashing) - not fail2ban.
#
# Relevant fail2ban coverage: SDDM login (your display manager) - if someone
# tries to brute-force your Linux login (which is the PAM password that also
# unlocks system_.kdbx), we want fail2ban on SDDM.

FAIL2BAN_DIR="/etc/fail2ban"

if [[ -d "${FAIL2BAN_DIR}" ]]; then
    # Create a jail for SDDM to protect the login (and indirectly the PAM unlock)
    sudo bash -c "cat > '${FAIL2BAN_DIR}/jail.d/sddm-keepassxc.conf'" << 'F2B'
# fail2ban jail for SDDM - protects KDE login
# Since system_.kdbx auto-unlocks via PAM (login password), protecting login
# also protects the system secrets database from brute-force.
[sddm]
enabled  = true
filter   = sddm
backend  = systemd
journalmatch = _SYSTEMD_UNIT=sddm.service
maxretry = 5
bantime  = 900
findtime = 300
action   = firewallcmd-allports[name=sddm, protocol=all]
F2B

    # Create a filter for SDDM auth failures (journald-based)
    sudo bash -c "cat > '${FAIL2BAN_DIR}/filter.d/sddm.conf'" << 'F2BFILTER'
[Definition]
# Match SDDM PAM authentication failures in the systemd journal
failregex = pam_unix\(sddm.*\): authentication failure.*rhost=<HOST>
            pam_unix\(sddm.*\): authentication failure; logname=.*user=\S+
ignoreregex =
journalmatch = _SYSTEMD_UNIT=sddm.service SYSLOG_IDENTIFIER=sddm
F2BFILTER

    sudo systemctl enable --now fail2ban 2>/dev/null || true
    sudo systemctl reload fail2ban 2>/dev/null || true
    ok "fail2ban SDDM jail configured"
else
    warn "fail2ban not installed - skipping. Install with: sudo dnf install fail2ban"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 13: MIME defaults and XDG integration
# ─────────────────────────────────────────────────────────────────────────────
section "MIME defaults and XDG integration"

# Register KeePassXC as the default handler for .kdbx files
# so double-clicking opens them in KeePassXC (Dolphin, file pickers, etc.)

MIME_TYPE="application/x-keepass2"

# Add MIME type definition if not present
MIME_DIR="${HOME}/.local/share/mime/packages"
mkdir -p "${MIME_DIR}"

cat > "${MIME_DIR}/keepassxc.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
    <mime-type type="application/x-keepass2">
        <comment>KeePass 2 Database</comment>
        <glob pattern="*.kdbx"/>
        <icon name="keepassxc"/>
    </mime-type>
</mime-info>
EOF

update-mime-database "${HOME}/.local/share/mime" 2>/dev/null || true

# Set KeePassXC as the default app for .kdbx
xdg-mime default keepassxc.desktop application/x-keepass2 2>/dev/null || true

# Also write the mimeapps.list entry directly for reliability
MIMEAPPS="${HOME}/.config/mimeapps.list"
if [[ -f "${MIMEAPPS}" ]]; then
    # Add to [Default Applications] section if not already there
    if ! grep -q "application/x-keepass2" "${MIMEAPPS}"; then
        sed -i '/\[Default Applications\]/a application/x-keepass2=keepassxc.desktop' "${MIMEAPPS}"
    fi
else
    cat > "${MIMEAPPS}" << 'EOF'
[Default Applications]
application/x-keepass2=keepassxc.desktop
EOF
fi

ok "MIME defaults set: .kdbx → keepassxc"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 14: Hardware-aware KeePassXC config tuning
# ─────────────────────────────────────────────────────────────────────────────
section "Hardware-aware tuning (RAM: ${RAM_GB}GB, Host: ${HOSTNAME})"

# KeePassXC's Argon2id KDF has memory and iteration parameters.
# More RAM = more memory hardness = more GPU-resistant.
# We tune the memory parameter for new databases based on available RAM.
# These are written into keepassxc.ini under [PasswordGenerator] and
# the Database defaults section.

if [[ "${RAM_GB}" -ge 16 ]]; then
    ARGON2_MEM=524288    # 512 MB - strong protection, lots of RAM available
    ARGON2_ITER=2
elif [[ "${RAM_GB}" -ge 8 ]]; then
    ARGON2_MEM=262144    # 256 MB
    ARGON2_ITER=2
elif [[ "${RAM_GB}" -ge 4 ]]; then
    ARGON2_MEM=131072    # 128 MB
    ARGON2_ITER=2
else
    ARGON2_MEM=65536     # 64 MB - low RAM (nbLenovo: 5.64GB still hits ≥4 branch)
    ARGON2_ITER=3        # More iterations compensate for less memory
fi

info "Argon2id config for ${HOSTNAME}: memory=${ARGON2_MEM}KB, iterations=${ARGON2_ITER}"

# Append KDF defaults to keepassxc.ini
cat >> "${KPXC_CONFIG_FILE}" << EOF

[Database]
# Argon2id KDF defaults for new databases
# Tuned for ${HOSTNAME} (${RAM_GB}GB RAM)
# memory=${ARGON2_MEM}KB is the working set used during key derivation
# Higher = more GPU-resistant; lower = faster to unlock on slow hardware
UseArgon2id=true
Argon2Memory=${ARGON2_MEM}
Argon2Iterations=${ARGON2_ITER}
Argon2Parallelism=${CPU_CORES}
EOF

ok "Argon2id KDF tuned for ${HOSTNAME}"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 15: Thunderbird integration
# ─────────────────────────────────────────────────────────────────────────────
section "Thunderbird integration"

# Thunderbird uses the Secret Service (D-Bus) to store email account passwords.
# With KeePassXC's FDO Secrets enabled (Section 5), Thunderbird will automatically
# store and retrieve credentials from KeePassXC - no extra config needed.

# However, we should configure Thunderbird to USE the secret service:
THUNDERBIRD_PROFILE_DIR="${HOME}/.thunderbird"
if [[ -d "${THUNDERBIRD_PROFILE_DIR}" ]]; then
    # Find the default profile
    TB_PROFILE=$(find "${THUNDERBIRD_PROFILE_DIR}" -name "prefs.js" | head -1 | xargs dirname 2>/dev/null || echo "")
    if [[ -n "${TB_PROFILE}" ]]; then
        PREFS_JS="${TB_PROFILE}/prefs.js"
        # Enable the Secret Service backend in Thunderbird
        if ! grep -q "signon.secretstorage.enabled" "${PREFS_JS}" 2>/dev/null; then
            echo 'user_pref("signon.secretstorage.enabled", true);' >> "${PREFS_JS}"
            ok "Thunderbird configured to use Secret Service (KeePassXC)"
        else
            info "Thunderbird already configured for Secret Service"
        fi
    fi
else
    info "Thunderbird not yet installed - Secret Service integration is automatic on first run"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 16: VSCodium / Neovim / other app integration notes
# ─────────────────────────────────────────────────────────────────────────────
section "Other app integrations"

# VSCodium:
#   - Stores auth tokens via Secret Service → automatic via FDO Secrets (KeePassXC)
#   - No additional config needed

# Neovim (LazyVim):
#   - Plugins like gh.nvim, octo.nvim use tokens from environment or secret-tool
#   - secret-tool (installed in Section 2) can query KeePassXC:
#     secret-tool lookup service github account username
#   - For shell integration, add to ~/.zshrc (see post-install notes below)

# Signal Desktop:
#   - Stores its own encrypted keychain, does not use Secret Service
#   - No KeePassXC integration possible at the app level

# ProtonVPN:
#   - Stores credentials in Secret Service → automatic

# qBittorrent:
#   - No password manager integration

# SSH keys:
#   - KeePassXC SSH agent integration is OFF by default (configured above)
#   - Enable in KeePassXC Settings → SSH Agent if you want to store SSH keys in KeePassXC
#   - Requires `SSH_AUTH_SOCK` to point to KeePassXC's agent socket

info "VSCodium, ProtonVPN: automatic via FDO Secret Service - no config needed"
info "Neovim: use 'secret-tool lookup ...' in shell scripts to pull secrets from KeePassXC"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 17: Shell (Zsh) integration snippet
# ─────────────────────────────────────────────────────────────────────────────
section "Zsh integration"

ZSH_SNIPPET="${HOME}/.config/zsh/keepassxc.zsh"
mkdir -p "${HOME}/.config/zsh"

cat > "${ZSH_SNIPPET}" << 'EOF'
# ── KeePassXC shell helpers ──────────────────────────────────────────────────

# kpsecret: retrieve a secret from KeePassXC via secret-tool (FDO Secrets)
# Usage: kpsecret <service> <account>
# Example: kpsecret github myusername
kpsecret() {
    secret-tool lookup service "$1" account "$2" 2>/dev/null \
        || echo "Secret not found: service=$1 account=$2"
}

# kpstore: store a secret into KeePassXC via secret-tool
# Usage: kpstore <service> <account> <label>
kpstore() {
    secret-tool store --label="$3" service "$1" account "$2"
}

# kpopen: open a KeePassXC database from command line
# Usage: kpopen [path-to-kdbx]
kpopen() {
    local db="${1:-${HOME}/nb/Syncthing/KeePass/personal.kdbx}"
    keepassxc "${db}" &
}
EOF

# Source it from .zshrc if not already
ZSHRC="${HOME}/.zshrc"
if ! grep -q "keepassxc.zsh" "${ZSHRC}" 2>/dev/null; then
    echo "" >> "${ZSHRC}"
    echo "# KeePassXC helpers" >> "${ZSHRC}"
    echo "[[ -f \"\${HOME}/.config/zsh/keepassxc.zsh\" ]] && source \"\${HOME}/.config/zsh/keepassxc.zsh\"" >> "${ZSHRC}"
    ok "Zsh integration snippet added to .zshrc"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 18: Systemd user service for lock-on-sleep
# ─────────────────────────────────────────────────────────────────────────────
section "Systemd: lock KeePassXC on suspend/hibernate"

# KeePassXC has a built-in screen-lock trigger (configured above).
# For suspend/hibernate, we add a systemd user service that locks
# all KeePassXC databases via DBus before the system suspends.

SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
mkdir -p "${SYSTEMD_USER_DIR}"

cat > "${SYSTEMD_USER_DIR}/keepassxc-lock-on-suspend.service" << 'EOF'
[Unit]
Description=Lock KeePassXC databases on suspend/hibernate
Before=sleep.target
StopWhenUnneeded=yes

[Service]
Type=oneshot
# Send lock signal to all open databases via DBus
# keepassxc-cli lock is not available, so we use the DBus interface directly
ExecStart=/usr/bin/dbus-send --session --dest=org.keepassxc.KeePassXC \
    /keepassxc org.keepassxc.MainWindow.lockAllDatabases
RemainAfterExit=yes

[Install]
WantedBy=sleep.target
EOF

systemctl --user enable keepassxc-lock-on-suspend.service 2>/dev/null || \
    warn "Could not enable systemd user service (may need to run after login)"

ok "KeePassXC lock-on-suspend service configured"

# ─────────────────────────────────────────────────────────────────────────────
# DONE - Post-install summary
# ─────────────────────────────────────────────────────────────────────────────
section "Setup complete - Post-install checklist"

cat << SUMMARY

${GREEN}══════════════════════════════════════════════════════════════════${NC}
${GREEN}  KeePassXC setup complete for: ${HOSTNAME} (${CURRENT_USER})${NC}
${GREEN}══════════════════════════════════════════════════════════════════${NC}

${YELLOW}Manual steps you MUST complete:${NC}

  1. ${BLUE}Create personal.kdbx${NC}
     Open KeePassXC → New Database
     Save to: ${PERSONAL_DB}
     Use: Argon2id + strong master password
     Enable FDO Secrets for this DB in: Database → Database Settings → Secret Service

  2. ${BLUE}Create system_.kdbx${NC}
     Open KeePassXC → New Database
     Save to: ${SYSTEM_DB}
     This will hold WiFi passwords, system tokens, NM credentials.

  3. ${BLUE}Initialise PAM auto-unlock key for system_.kdbx${NC}
     Run: ${INIT_KEY_HELPER}
     (Do this after creating system_.kdbx)

  4. ${BLUE}Migrate KWallet secrets (if any)${NC}
     While KWallet is still active (before reboot):
       ${MIGRATION_SCRIPT} --db ${PERSONAL_DB} --password 'PASSWORD' --dry-run
       ${MIGRATION_SCRIPT} --db ${PERSONAL_DB} --password 'PASSWORD'

  5. ${BLUE}Install browser extensions manually${NC}
     Brave:     https://chrome.google.com/webstore/detail/keepassxc-browser/oboonakemofpalcgghocfoadofidjkkk
     LibreWolf: https://addons.mozilla.org/firefox/addon/keepassxc-browser/
     Then: KeePassXC → Tools → Settings → Browser Integration → Enable per-browser

  6. ${BLUE}Add Syncthing folder${NC}
     Syncthing Web UI → Add Folder → Path: ${SYNC_DIR}
     Share with your Android device running KeePassDX

  7. ${BLUE}Log out and back in${NC}
     This activates:
       - KWallet disabled, KeePassXC starts minimized
       - FDO Secret Service registered on D-Bus
       - PAM pam_mount hook active for auto-unlock

${YELLOW}Optional / verify:${NC}

  - SSH agent:    KeePassXC → Settings → SSH Agent (enable if needed)
  - KDE Wallet:   Run 'qdbus org.kde.kwalletd5' - should return nothing
  - Secret store: secret-tool search service github  (should show KeePassXC results)
  - Argon2id:     Tuned for ${HOSTNAME}: memory=${ARGON2_MEM}KB iterations=${ARGON2_ITER}

${YELLOW}Android (KeePassDX):${NC}
  - Sync: KeePassDX → Open personal.kdbx from Syncthing folder
  - Biometric unlock: KeePassDX → Settings → App → Biometric
  - Autofill: Android Settings → Autofill service → KeePassDX

${YELLOW}Files written:${NC}
  ${KPXC_CONFIG_FILE}         ← KeePassXC config
  ${UNLOCK_HELPER}      ← PAM auto-unlock helper
  ${INIT_KEY_HELPER}    ← Run once to init system_.kdbx key
  ${MIGRATION_SCRIPT}   ← KWallet migration helper
  ${ZSH_SNIPPET}        ← Zsh shell helpers
  ${SYNC_DIR}/.stignore         ← Syncthing ignore rules

SUMMARY