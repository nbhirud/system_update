#!/bin/bash
# NVIDIA 535 Driver Installation Script for Fedora 44
# GTX 960M (GM107M) - Dell XPS 15 9550

# Note: This script uses the akmod drivers from RPM Fusion. Needs disabling Secure Boot. Skip this method. 


set -e

echo "=== NVIDIA Driver Installation Script ==="
echo "Target: GeForce GTX 960M (GM107M)"
echo "Driver: 535 (proprietary)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (sudo)"
    exit 1
fi

# Step 1: Backup current configuration
print_status "Creating backup of current configuration..."
mkdir -p ~/nvidia-backup-$(date +%Y%m%d-%H%M%S)
cp /etc/modprobe.d/blacklist-nouveau.conf ~/nvidia-backup-$(date +%Y%m%d-%H%M%S)/ 2>/dev/null || true

# Step 2: Remove existing NVIDIA drivers and nouveau
print_status "Removing existing NVIDIA drivers and nouveau..."
dnf remove -y \
    akmod-nvidia \
    xorg-x11-drv-nvidia-cuda \
    xorg-x11-drv-nvidia-libs \
    xorg-x11-drv-nvidia \
    xorg-x11-drv-nvidia-power \
    kmod-nvidia \
    nvidia-driver \
    nvidia-utils \
    nvidia-settings \
    nouveau \
    xorg-x11-drv-nouveau \
    || print_warning "Some packages may not have been installed"

# Blacklist nouveau
cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

# Rebuild initramfs
print_status "Rebuilding initramfs..."
dracut --force

# Step 3: Enable RPM Fusion repositories
print_status "Enabling RPM Fusion repositories..."
dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Step 4: Update system
print_status "Updating system packages..."
dnf upgrade -y

# Step 5: Install NVIDIA 535 driver
print_status "Installing NVIDIA 535 proprietary driver..."
# Note: If 535 is not available, this will install the closest available version
dnf install -y \
    akmod-nvidia-535 \
    xorg-x11-drv-nvidia-cuda-535 \
    xorg-x11-drv-nvidia-libs-535 \
    xord-x11-drv-nvidia-535 \
    nvidia-driver-535 \
    nvidia-utils-535 \
    nvidia-settings-535 \
    || print_warning "Driver 535 may not be available. Installing latest available NVIDIA driver instead..." && \
    dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-libs

# Step 6: Build kernel modules
print_status "Building kernel modules (this may take 5-10 minutes)..."
akmods --force

# Step 7: Rebuild initramfs again with new modules
print_status "Final initramfs rebuild..."
dracut --force

# Step 8: Verify installation
print_status "Installation complete. Verifying..."
if lsmod | grep -q nvidia; then
    print_status "NVIDIA kernel module loaded successfully"
else
    print_warning "NVIDIA module not loaded yet. Will load after reboot."
fi

# Step 9: Display post-installation info
echo ""
echo "=========================================="
echo "         POST-INSTALLATION NOTES         "
echo "=========================================="
echo ""
echo "1. REBOOT REQUIRED:"
echo "   sudo reboot"
echo ""
echo "2. SECURE BOOT:"
echo "   If Secure Boot is enabled in BIOS, the driver may not load."
echo "   Either disable Secure Boot or sign the kernel modules manually."
echo ""
echo "3. VERIFY INSTALLATION AFTER REBOOT:"
echo "   nvidia-smi                    # Shows GPU status"
echo "   glxinfo | grep OpenGL         # Confirms OpenGL driver"
echo "   lspci -k | grep -A 2 VGA      # Shows active driver"
echo ""
echo "4. GAMING OPTIMIZATION:"
echo "   Install Steam and enable NVIDIA optimizations:"
echo "   sudo dnf install steam"
echo ""
echo "5. DRIVER VERSION 535 NOTE:"
echo "   This is a legacy driver. For best gaming performance in 2026,"
echo "   consider updating to the latest NVIDIA driver when available."
echo ""
echo "6. TROUBLESHOOTING:"
echo "   If display issues occur, boot into recovery mode and run:"
echo "   sudo dnf remove akmod-nvidia && sudo dnf install xorg-x11-drv-nouveau"
echo ""
echo "=========================================="