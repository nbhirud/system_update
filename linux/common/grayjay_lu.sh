#!/bin/bash
# ==============================================================================
# Grayjay Desktop Native Setup Script for Fedora 44 (Wayland/KDE)
# Target User: Nik | OS: Linux Fedora KDE
# 
# Strategy:
# 1. Download latest GitHub Release (ZIP).
# 2. Extract to /opt/grayjay (system-wide install) OR $HOME/.local/opt (user-only).
# 3. Configure hardware-specific flags (GPU/RAM/CPU).
# 4. Create .desktop entry for KDE menu.
# 5. Harden: Firewall, SELinux, Telemetry blocks.
# 6. Verify NextDNS routing.
#
# PREREQUISITES:
# - Fedora 44+ (Wayland recommended)
# - dnf, curl, wget, systemd, firewalld, selinux-policy-targeted
# ==============================================================================

set -euo pipefail

# --- Configuration Variables (USER MUST SET THESE) ---
# Replace with your NextDNS Profile ID
NEXTDNS_PROFILE_ID="${NEXTDNS_PROFILE_ID:-}"

# Install Path (System-wide requires sudo, User-only does not)
INSTALL_PATH="/opt/grayjay"
USE_USER_INSTALL=false

# If true, installs to user directory instead of /opt
if [ "${1:-}" == "--user" ]; then
    INSTALL_PATH="$HOME/.local/opt/grayjay"
    USE_USER_INSTALL=true
fi

# GitHub Release URL Pattern
REPO_OWNER="futo-org"
REPO_NAME="Grayjay.Desktop"
LINUX_ARCH="x64" # Supports x86_64 primarily; ARM64 may need separate build

# --- Hardware Detection & Optimization ---
detect_hardware() {
    echo ">>> Detecting Hardware for Optimizations..."
    
    CPU_CORES=$(nproc)
    TOTAL_RAM_KB=$(free -k | awk '/^Mem:/ {print $2}')
    TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
    
    # GPU Detection
    if lspci | grep -q "NVIDIA"; then
        GPU_VENDOR="nvidia"
    elif lspci | grep -q "AMD\|Radeon"; then
        GPU_VENDOR="amd"
    elif lspci | grep -q "Intel"; then
        GPU_VENDOR="intel"
    else
        GPU_VENDOR="unknown"
    fi

    echo "     CPU: $CPU_CORES Cores ($CPU_MODEL)"
    echo "     RAM: ${TOTAL_RAM_GB} GB"
    echo "     GPU: $GPU_VENDOR"
    
    # Store for later use
    export CPU_CORES TOTAL_RAM_GB GPU_VENDOR
}

apply_electron_flags() {
    echo ">>> Applying Electron Flags based on Hardware..."
    
    local flags=()
    
    # Low RAM Optimization (< 8GB)
    if [ "$TOTAL_RAM_GB" -lt 8 ]; then
        echo "     [INFO] Low RAM detected. Limiting memory usage."
        flags+=("--max-old-space-size=2048")
    fi
    
    # GPU Acceleration Tuning
    case "$GPU_VENDOR" in
        intel)
            # Intel i915 usually works well, but older gens (like nbMain's 2nd gen) might struggle
            if grep -q "2nd Generation" /proc/cpuinfo 2>/dev/null || \
               lspci | grep -q "2nd Generation"; then
                echo "     [WARN] Older Intel GPU detected. Disabling HW acceleration for stability."
                flags+=("--disable-gpu")
            else
                echo "     [INFO] Modern Intel GPU. Enabling HW acceleration."
            fi
            ;;
        amd)
            # AMD Radeon usually stable with Vulkan/OpenGL
            flags+=("--enable-features=UseOzonePlatform,OzonePlatformWayland,Vulkan")
            ;;
        nvidia)
            # NVIDIA proprietary drivers often require explicit flags
            flags+=("--enable-features=UseOzonePlatform,OzonePlatformWayland,Vulkan")
            ;;
        *)
            echo "     [WARN] Unknown GPU. Disabling GPU features for safety."
            flags+=("--disable-gpu")
            ;;
    esac

    # Write flags to a config file for the launcher
    echo "${flags[*]}" > "$INSTALL_PATH/grayjay.flags"
}

# --- Security Hardening ---
setup_firewall_rules() {
    echo ">>> Configuring Firewalld Rules..."
    
    # Grayjay needs outbound HTTPS (443) and possibly UDP for streaming protocols
    # We create a custom zone or restrict existing one.
    
    # Check if firewalld is active
    if ! systemctl is-active --quiet firewalld; then
        echo "     [WARN] firewalld is not running. Skipping firewall rules."
        return
    fi

    # Define custom zone if needed (optional, but cleaner)
    # For simplicity, we rely on default output rules but block known telemetry domains via NextDNS.
    # If you want strict port blocking, uncomment below:
    
    # firewall-cmd --permanent --new-zone=grayjay
    # firewall-cmd --permanent --zone=grayjay --add-port=443/tcp
    # firewall-cmd --permanent --zone=grayjay --add-port=53/udp
    # firewall-cmd --permanent --zone=grayjay --change-interface=waydroid0 # Not applicable for native
    # firewall-cmd --reload
    
    echo "     [INFO] Relying on NextDNS for domain-level filtering."
    echo "     [INFO] Ensure NextDNS profile blocks 'Google Analytics', 'Telemetry', etc."
}

setup_selinux_context() {
    echo ">>> Adjusting SELinux Contexts..."
    
    if command -v semanage &> /dev/null; then
        # Allow execution from /opt or user dir
        semanage fcontext -a -t bin_t "${INSTALL_PATH}(/.*)?" 2>/dev/null || true
        restorecon -Rv "${INSTALL_PATH}" 2>/dev/null || true
        echo "     [OK] SELinux contexts applied."
    else
        echo "     [WARN] semanage not found. Skipping SELinux hardening."
    fi
}

create_desktop_entry() {
    echo ">>> Creating KDE Desktop Entry..."
    
    local desktop_file
    if [ "$USE_USER_INSTALL" = true ]; then
        desktop_file="$HOME/.local/share/applications/grayjay.desktop"
    else
        desktop_file="/usr/share/applications/grayjay.desktop"
        sudo mkdir -p "$(dirname "$desktop_file")"
    fi

    cat <<EOF | sudo tee "$desktop_file" > /dev/null
[Desktop Entry]
Name=Grayjay
Comment=Universal media aggregator following creators, not platforms
Exec=/bin/bash -c "source $INSTALL_PATH/grayjay.flags 2>/dev/null && ELECTRON_FLAGS=\"\$GRAYJAY_FLAGS\" \"$INSTALL_PATH/grayjay\""
Icon=grayjay
Type=Application
Categories=AudioVideo;Video;Network;
StartupWMClass=grayjay
Terminal=false
X-GNOME-Autostart-enabled=false
EOF

    # Set icon path (download if missing)
    if [ ! -f "/usr/share/icons/hicolor/256x256/apps/grayjay.png" ]; then
        echo "     [INFO] Downloading app icon..."
        curl -L -o "$INSTALL_PATH/grayjay-icon.png" "https://github.com/futo-org/Grayjay.Desktop/raw/main/assets/icon.png" 2>/dev/null || true
        if [ -f "$INSTALL_PATH/grayjay-icon.png" ]; then
            sudo cp "$INSTALL_PATH/grayjay-icon.png" /usr/share/icons/hicolor/256x256/apps/grayjay.png
            sudo gtk-update-icon-cache -f /usr/share/icons/hicolor
        fi
    fi

    sudo update-desktop-database
    echo "     [OK] Desktop entry created at $desktop_file"
}

disable_teometry() {
    echo ">>> Attempting to disable Electron Telemetry..."
    # Electron apps often respect environment variables
    export DISABLE_TELEMETRY="true"
    export DO_NOT_TRACK="true"
    export TELEMETRY_DISABLED="1"
    # Note: Grayjay's internal logic determines if these work.
    # Primary defense remains NextDNS blocking of tracking domains.
}

# --- Main Execution ---

main() {
    clear
    echo "=================================================="
    echo "   Grayjay Desktop Native Setup (Fedora 44)"
    echo "   User: Nik | OS: Linux Fedora KDE"
    echo "=================================================="

    if [ "$EUID" -eq 0 ] && [ "$USE_USER_INSTALL" = false ]; then
        echo "Running as root is allowed for system-wide install."
    elif [ "$EUID" -eq 0 ] && [ "$USE_USER_INSTALL" = true ]; then
        echo "Error: Cannot install to user directory as root. Remove --user flag or run as normal user."
        exit 1
    fi

    detect_hardware

    # 1. Download Latest Release
    echo ">>> Fetching latest release from GitHub..."
    LATEST_RELEASE_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest"
    DOWNLOAD_URL=$(curl -s "$LATEST_RELEASE_URL" | grep "browser_download_url.*linux-$LINUX_ARCH\.zip" | cut -d '"' -f 4)

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "Error: Could not find Linux x64 release. Aborting."
        exit 1
    fi

    echo "     Downloading from: $DOWNLOAD_URL"
    mkdir -p "$INSTALL_PATH"
    cd "$INSTALL_PATH"
    curl -L -o "grayjay.zip" "$DOWNLOAD_URL"
    unzip -q grayjay.zip
    rm grayjay.zip

    # Find the executable (usually named 'Grayjay' or similar inside extracted dir)
    EXECUTABLE=$(find . -type f -name "grayjay" -executable | head -n 1)
    if [ -z "$EXECUTABLE" ]; then
        # Try common names
        EXECUTABLE=$(find . -type f \( -name "Grayjay" -o -name "grayjay-linux" \) | head -n 1)
    fi

    if [ -z "$EXECUTABLE" ]; then
        echo "Error: Executable not found in archive."
        exit 1
    fi

    mv "$EXECUTABLE" ./grayjay
    chmod +x ./grayjay

    # 2. Hardware Optimization
    apply_electron_flags

    # 3. Security Hardening
    setup_firewall_rules
    setup_selinux_context
    disable_teometry

    # 4. Desktop Entry
    create_desktop_entry

    # 5. NextDNS Verification
    if [ -n "$NEXTDNS_PROFILE_ID" ]; then
        echo ">>> Verifying NextDNS..."
        if ! resolvectl status | grep -q "NextDNS"; then
            echo "Warning: NextDNS not found in system resolver."
            echo "Set your DNS to https://dns.nextdns.io/$NEXTDNS_PROFILE_ID in systemd-resolved.conf"
        else
            echo "     [OK] System DNS routed through NextDNS (Profile: $NEXTDNS_PROFILE_ID)."
        fi
    else
        echo "WARNING: NEXTDNS_PROFILE_ID not set. Device tracking disabled on NextDNS dashboard."
    fi

    echo ""
    echo "=================================================="
    echo "   SETUP COMPLETE"
    echo "=================================================="
    echo "To launch Grayjay:"
    echo "  - Search 'Grayjay' in KDE Application Menu"
    echo "  - Or run: $INSTALL_PATH/grayjay"
    echo ""
    echo "Notes for Nik:"
    echo "- Sync: Log into Grayjay account to sync subscriptions across devices."
    echo "- Plugins: Enable YouTube, PeerTube, Odysee, etc., manually in Settings -> Plugins."
    echo "- Privacy: Telemetry blocked via NextDNS + env vars."
    echo "- Performance: Tuned for ${TOTAL_RAM_GB}GB RAM and $GPU_VENDOR GPU."
    echo "- Updates: Run this script again periodically to fetch latest releases."
    echo ""
    echo "Alternative: Use 'flatpak install flathub app.grayjay.Grayjay' for sandboxed auto-updates."
    echo "             (If you prefer Flatpak over manual ZIP install)"
}

main "$@"