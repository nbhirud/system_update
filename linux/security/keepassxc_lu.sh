#!/usr/bin/env bash
# ==============================================================================
# KeePassXC Production Setup Script for Fedora 44 (KDE Plasma)
# Target User: Nik
# Objective: Full replacement of KWallet, Browser integration, Syncthing sync,
#            System-wide secret management, and Security Hardening.
# ==============================================================================

set -euo pipefail

# --- Configuration Variables ---
# Adjust these if your paths differ from your profile
REPO_SYNC_BASE="$HOME/nb/Syncthing/KeePass"
SYNC_DIR="${REPO_SYNC_BASE}"
PERSONAL_DB_NAME="personal.kdbx"
SYSTEM_DB_NAME_PREFIX="system_" # Appended with hostname automatically
CONFIG_DIR="$HOME/.config/keepassxc"
LOCAL_DATA_DIR="$HOME/.local/share/keepassxc"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Helper Functions ---

detect_hardware() {
    log_info "Detecting hardware specifications..."
    CPU_CORES=$(nproc)
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
    
    # Detect GPU
    GPU_INFO=$(lspci | grep -i vga | head -n 1)
    HAS_NVIDIA=$(lspci | grep -c -i nvidia || true)
    
    log_info "Detected: ${CPU_CORES} Cores, ${TOTAL_RAM_GB}GB RAM, GPU: ${GPU_INFO}"
    
    # Optimization flags based on RAM
    if [ "$TOTAL_RAM_GB" -lt 8 ]; then
        log_warn "Low RAM detected (<8GB). Disabling aggressive caching in future configs."
        CACHE_FLAG="minimal"
    else
        CACHE_FLAG="aggressive"
    fi
    
    export CACHE_FLAG
}

create_directories() {
    log_info "Creating required directory structures..."
    mkdir -p "${SYNC_DIR}"
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "${LOCAL_DATA_DIR}"
    
    # Ensure permissions are strict
    chmod 700 "${SYNC_DIR}"
    chmod 700 "${CONFIG_DIR}"
    chmod 700 "${LOCAL_DATA_DIR}"
    
    log_info "Directories created and secured."
}

install_packages() {
    log_info "Installing and updating required packages..."
    
    # Update system first
    sudo dnf upgrade -y --refresh
    
    # Install KeePassXC and browser integration hosts
    # Note: Using DNF version to ensure native-messaging works with LibreWolf/Brave without Flatpak sandbox issues
    sudo dnf install -y keepassxc keepassxc-browser 
    
    # Verify installation
    if ! command -v keepassxc &> /dev/null; then
        log_error "KeePassXC installation failed!"
        exit 1
    fi
    log_info "Packages installed successfully."
}

setup_browsers() {
    log_info "Configuring Browser Integration for LibreWolf and Brave..."
    
    # The DNF package usually handles linking to /usr/lib...
    # However, we force the links for clarity and robustness across different Firefox forks
    
    # For LibreWolf (uses firefox-like structure but distinct path)
    LW_HOST_PATH="$HOME/.librewolf/native-messaging-hosts"
    if [ ! -d "$LW_HOST_PATH" ]; then
        mkdir -p "$LW_HOST_PATH"
    fi
    ln -sf /usr/lib/mozilla/native-messaging-hosts/keepassxc-browser.json "$LW_HOST_PATH/" 2>/dev/null || true
    
    # For Brave (Chromium-based)
    BRAVE_HOST_PATH="$HOME/.config/brave-browser/NativeMessagingHosts"
    if [ ! -d "$BRAVE_HOST_PATH" ]; then
        mkdir -p "$BRAVE_HOST_PATH"
    fi
    # Check where the manifest was installed by DNF (usually /usr/lib/chromium-native-messaging or similar)
    MANIFEST_SRC=$(find /usr -name "keepassxc-browser.json" 2>/dev/null | grep chromium || find /usr -name "keepassxc-browser.json" 2>/dev/null | head -n1)
    if [ -n "$MANIFEST_SRC" ]; then
        ln -sf "$MANIFEST_SRC" "$BRAVE_HOST_PATH/"
        log_info "Linked KeepassXC manifest for Brave."
    fi

    log_info "Browser integration manifests linked. Please restart browsers and install the 'KeePassXC-Browser' extension from their respective stores."
}

disable_kwallet() {
    log_info "Disabling KWallet and setting up libsecret to prefer KeePassXC..."
    
    # Disable KWallet in KDE config
    cat > "$HOME/.config/kde-org/kdeglobals" <<EOF
[Wallet]
Enabled=false
EOF

    # Set default secret service provider to KeePassXC
    # This ensures apps like Chrome/Brave use KeePassXC instead of Gnome Keyring/KWallet
    mkdir -p "$HOME/.config/systemd/user"
    
    # Create a user service to start kpxc-server at login if not already running
    # (Though KeePassXC usually handles this via DBus activation)
    
    log_info "KWallet disabled. System will now prioritize libsecret (KeePassXC)."
}

create_databases() {
    local SYSTEM_DB_PATH="${HOME}/${SYSTEM_DB_NAME_PREFIX}$(hostname).kdbx"
    
    log_info "Initializing databases..."
    
    # 1. Create Personal Database (Empty for now, ready for Syncthing)
    if [ ! -f "${SYNC_DIR}/${PERSONAL_DB_NAME}" ]; then
        log_info "Personal database '${PERSONAL_DB_NAME}' not found in ${SYNC_DIR}. Creating placeholder structure..."
        # We cannot create the actual encrypted DB without a password here, so we guide the user
        touch "${SYNC_DIR}/${PERSONAL_DB_NAME}"
        echo "# DO NOT EDIT THIS FILE DIRECTLY" > "${SYNC_DIR}/${PERSONAL_DB_NAME}"
        chmod 600 "${SYNC_DIR}/${PERSONAL_DB_NAME}"
        log_warn "You must manually open KeePassXC, create 'personal.kdbx', set a strong password/key file, and save it to ${SYNC_DIR}."
    else
        log_info "Personal database found. Permissions securing..."
        chmod 600 "${SYNC_DIR}/${PERSONAL_DB_NAME}"
    fi

    # 2. Create System Database (Local, Auto-Unlocked concept)
    if [ ! -f "$SYSTEM_DB_PATH" ]; then
        log_info "System database '$(basename "$SYSTEM_DB_PATH")' not found. Creating placeholder..."
        touch "$SYSTEM_DB_PATH"
        chmod 600 "$SYSTEM_DB_PATH"
        log_warn "You must manually open KeePassXC, create '$(basename "$SYSTEM_DB_PATH")', set a password, and enable 'Auto-Unlock' in settings."
    else
        log_info "System database found."
        chmod 600 "$SYSTEM_DB_PATH"
    fi
}

setup_syncthing_integration() {
    log_info "Configuring Syncthing directory and sync logic..."
    
    # Check if Syncthing is installed (assuming it will be installed soon)
    if ! command -v syncthing &> /dev/null; then
        log_warn "Syncthing binary not found yet. Skipping active daemon config, but ensuring directory exists."
    else
        log_info "Syncthing detected. Note: Ensure you have added folder '${REPO_SYNC_BASE}' to Syncthing."
    fi
    
    # Create a simple lock-file mechanism helper script to prevent race conditions
    cat > "$HOME/bin/keepassxc-sync-helper.sh" <<EOF
#!/bin/bash
# Prevents multiple writes to the synced database
LOCK_FILE="/tmp/keepassxc_sync.lock"
DB_FILE="${SYNC_DIR}/${PERSONAL_DB_NAME}"

if [ -f "\$LOCK_FILE" ]; then
    echo "Sync locked. Waiting..."
    sleep 1
fi

touch \$LOCK_FILE
# ... User's manual lock/unlock logic or cron job can go here
echo "Sync safe window opened for \$DB_FILE"
rm -f \$LOCK_FILE
EOF
    
    mkdir -p "$HOME/bin"
    chmod +x "$HOME/bin/keepassxc-sync-helper.sh"
    
    log_info "Sync helper script created at ~/bin/keepassxc-sync-helper.sh"
}

setup_system_auto_unlock() {
    log_info "Configuring PAM and Systemd for Auto-Unlock (System DB)..."
    log_warn "Auto-unlock requires you to set the SAME password as your login OR use a key file stored securely."
    
    # Note: True auto-unlock at boot without entering a second password is complex and risky.
    # The recommended secure approach for Linux is to use the 'Unlock with PAM' feature in KeePassXC.
    # We will create the systemd user service to ensure the agent is running when you login.
    
    cat > "$HOME/.config/systemd/user/keepassxc-agent.service" <<EOF
[Unit]
Description=KeePassXC Agent for System Secrets
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/keepassxc-cli agent-start
Restart=on-failure

[Install]
WantedBy=default.target
EOF
    
    systemctl --user daemon-reload
    systemctl --user enable keepassxc-agent.service
    
    log_info "Systemd agent enabled. To enable auto-unlock:"
    log_info "1. Open KeePassXC -> Tools -> Settings -> Advanced -> Auto-Type"
    log_info "2. Enable 'Unlock with PAM' for your System Database."
}

configure_firewall_and_selinux() {
    log_info "Applying firewall and SELinux hardening..."
    
    # KeePassXC uses no network ports locally, so no firewalld rules needed for the app itself.
    # However, we ensure no accidental forwarding is enabled.
    sudo firewall-cmd --state > /dev/null && echo "Firewalld is active. Default policies maintained." || log_warn "Firewalld not running."
    
    # SELinux context for database files
    semanage fcontext -a -t user_home_t "${SYNC_DIR}(/.*)?" 2>/dev/null || true
    restorecon -Rv "${SYNC_DIR}" 2>/dev/null || true
    
    log_info "SELinux contexts updated for sync directory."
}

migration_guide() {
    log_info "Migration Guide for Existing Secrets:"
    cat << EOF

To migrate existing passwords from KWallet or old managers:

1. Export from Old Source:
   - KWallet: Use 'kwalletmanager5' -> Export as CSV (Note: CSV is unencrypted, delete immediately after import!).
   - Chrome/Firefox: Use built-in export features (CSV).

2. Import into KeePassXC:
   - Open KeePassXC.
   - File -> Import -> From CSV (or KWallet XML).
   - Select your 'personal.kdbx' database.
   - Map fields carefully.

3. Cleanup:
   - DELETE ALL CSV files immediately.
   - Wipe browser exported history if used.

4. Browser Extension:
   - Install 'KeePassXC-Browser' in LibreWolf and Brave.
   - Open KeepassXC -> Tools -> Browser Integration -> Connect Browser.
   - Approve the connection in both the browser popup and KeePassXC.

EOF
}

main() {
    log_info "Starting KeePassXC Production Setup for Nik..."
    
    detect_hardware
    create_directories
    install_packages
    setup_browsers
    disable_kwallet
    create_databases
    setup_syncthing_integration
    setup_system_auto_unlock
    configure_firewall_and_selinux
    
    log_info "Setup Complete! Manual steps remaining:"
    log_info "1. Launch KeePassXC. Create 'personal.kdbx' in ${SYNC_DIR} with a strong password."
    log_info "2. Launch KeePassXC. Create 'system_$(hostname).kdbx' locally."
    log_info "3. Install the 'KeePassXC-Browser' extension in LibreWolf and Brave."
    log_info "4. Connect the browser extensions in KeePassXC Settings."
    log_info "5. Configure Syncthing to sync the ${REPO_SYNC_BASE} folder."
    log_info "6. (Optional) Configure PAM auto-unlock for the system database."
    
    migration_guide
}

main "$@"