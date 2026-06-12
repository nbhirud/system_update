#!/bin/bash
# NVIDIA 535 Installation with Secure Boot Support
# Target: GTX 960M (GM107M) on Fedora 44

set -e


# Note: 
# Changes made:
# Added MOK key generation (openssl).
# Added sign-file commands to sign the .ko modules.
# Added mokutil to prepare for enrollment.
# Removed the automatic reboot at the end (you need to do the MOK wizard first).



# --- CONFIGURATION ---
MOK_PASSWORD="ChangeMeNow123!"  # <--- CHANGE THIS! Used for MOK enrollment
KEY_DIR="/root/nvidia-keys"
DRIVER_VERSION="535"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    print_error "Must run as root (sudo)"
    exit 1
fi

# 1. Cleanup & Removal
print_status "Cleaning up existing drivers..."
dnf remove -y akmod-nvidia xorg-x11-drv-nvidia* nvidia* nouveau* xorg-x11-drv-nouveau || true
rm -rf /etc/modprobe.d/blacklist-nouveau.conf
dracut --force

# 2. Repos
print_status "Enabling RPM Fusion..."
dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
               https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf upgrade -y

# 3. Install Driver
print_status "Installing NVIDIA ${DRIVER_VERSION}..."
# Try specific version first, fallback to generic if 535 is EOL in repos
if ! dnf install -y akmod-nvidia-${DRIVER_VERSION} xorg-x11-drv-nvidia-${DRIVER_VERSION} xorg-x11-drv-nvidia-cuda-${DRIVER_VERSION} xorg-x11-drv-nvidia-libs-${DRIVER_VERSION}; then
    print_warning "Version ${DRIVER_VERSION} not found. Attempting latest akmod-nvidia..."
    dnf install -y akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-libs
fi

# 4. Generate MOK Keys
print_status "Generating MOK keys..."
mkdir -p $KEY_DIR
cd $KEY_DIR

# Generate private key
openssl genrsa -out MOK.priv 2048
# Generate public key
openssl req -new -x509 -key MOK.priv -out MOK.der -days 3650 -subj "/CN=NVIDIA Custom Signing/"

# 5. Sign the Modules
print_status "Signing kernel modules..."
# Find the kernel version
KERNEL_VER=$(uname -r)
MOD_DIR="/lib/modules/${KERNEL_VER}/extra"

# List of modules to sign (common NVIDIA akmod names)
MODULES=(
    "nvidia.ko"
    "nvidia-uvm.ko"
    "nvidia-drm.ko"
    "nvidia-modeset.ko"
    "nvidia-peermem.ko"
)

for MOD in "${MODULES[@]}"; do
    if [ -f "$MOD_DIR/$MOD" ]; then
        print_status "Signing $MOD..."
        /usr/src/kernels/${KERNEL_VER}/scripts/sign-file sha256 \
            $KEY_DIR/MOK.priv $KEY_DIR/MOK.der \
            $MOD_DIR/$MOD
    else
        print_warning "Module $MOD not found in $MOD_DIR. Skipping."
    fi
done

# 6. Rebuild Initramfs (Crucial: includes signed modules)
print_status "Rebuilding initramfs with signed modules..."
dracut --force

# 7. Prepare for Enrollment
print_status "Preparing MOK enrollment..."
# Import the public key into the MOK list for next boot
mokutil --import $KEY_DIR/MOK.der --password "$MOK_PASSWORD"

# 8. Final Checks
print_status "Installation and Signing Complete."
echo ""
echo "=========================================="
echo "       CRITICAL NEXT STEPS               "
echo "=========================================="
echo ""
echo "1. REBOOT NOW to enroll the key:"
echo "   sudo reboot"
echo ""
echo "2. DURING BOOT (Blue Screen 'MOK Management'):"
echo "   - Select 'Enroll MOK'"
echo "   - Select 'Continue'"
echo "   - Enter the password: $MOK_PASSWORD"
echo "   - Select 'Yes' to confirm"
echo "   - Select 'Reboot'"
echo ""
echo "3. IF YOU SKIP THIS:"
echo "   The NVIDIA driver will NOT load due to Secure Boot."
echo "   Your system will fall back to 'nouveau' (slow)."
echo ""
echo "4. VERIFY AFTER REBOOT:"
echo "   nvidia-smi"
echo "   lsmod | grep nvidia"
echo ""
echo "=========================================="

# If nvidia-smi fails:
# Check if the module is blocked: lsmod | grep nvidia (should show nothing).
# Check logs: journalctl -k | grep -i "secure boot" or dmesg | grep -i "signature".
# Fix: You may need to go into your BIOS/UEFI settings and temporarily disable Secure Boot, boot once to let the system load the unsigned modules (to verify the driver itself works), then re-enable Secure Boot and re-run the signing steps if the keys didn't register.