#!/bin/bash

# ==============================================================================
# Fedora RAM-Backed Tmpfs & Performance Optimization Script
# Run as root: sudo ./setup_tmpfs.sh
# ==============================================================================

set -e

if [[ $EUID -ne 0 ]]; then
   echo "[-] This script must be run as root."
   exit 1
fi

##################
# Is tmpfs present by default in Fedora?
# Yes. Fedora automatically mounts several standard temporary file systems in RAM via tmpfs out of the box, most notably /run, /sys/fs/cgroup, and /tmp (depending on the installer/desktop profile configuration, though systemd's tmp.mount unit can dynamically manage /tmp as a tmpfs as well). However, manually declaring or tuning specific performance mounts ensures it is explicitly persistent and optimized for your workloads.

##################
# What services and packages benefit from /dev/shm or RAM-backed tmpfs?
#     ClamAV (clamd): Extracts and inspects compressed archives, tarballs, and software packages. Running this in RAM (/dev/shm) avoids heavy disk read/write cycles and accelerates scanning speeds.
#     Compilers & Build Tools (gcc, rustc, make, ninja): Object files and intermediate build artifacts generated during software compilation are written and discarded rapidly. RAM storage cuts build times significantly.
#     Web Browsers (Firefox, LibreWolf, Brave): Cache directories, session data, and media buffers benefit from being placed in RAM to reduce SSD wear and speed up page loading.
#     Database Engines (PostgreSQL, SQLite): Temporary sorting tables (work_mem) and transaction logs can leverage RAM-backed storage for transactional throughput.

##################
# Standalone Setup Script for Fresh Fedora Installations
# Save this script as setup_tmpfs.sh. It checks your total system RAM, configures /tmp as an optimized tmpfs if you have sufficient memory, and ensures secure permissions for shared memory (/dev/shm).


echo "[+] Analyzing system memory..."
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$(( TOTAL_RAM_KB / 1024 / 1024 ))
echo "[*] Detected Total RAM: ${TOTAL_RAM_GB} GB"

# 1. Secure and Optimize /dev/shm permissions
echo "[+] Ensuring secure permissions for /dev/shm..."
if grep -q "/dev/shm" /etc/fstab; then
    echo "[*] /dev/shm entry already exists in fstab."
else
    echo "tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0" >> /etc/fstab
    echo "[+] Added hardened /dev/shm configuration to /etc/fstab."
fi

# 2. Optionally mount /tmp as tmpfs if RAM is >= 8GB
if [ "$TOTAL_RAM_GB" -ge 8 ]; then
    echo "[+] Sufficient RAM detected (>= 8GB). Configuring /tmp as tmpfs..."
    
    # Enable systemd's native tmp.mount unit if not already active
    systemctl enable --now tmp.mount
    
    # Alternatively, ensure fstab handles it if systemd unit is overridden
    if ! grep -q "tmpfs /tmp tmpfs" /etc/fstab; then
        echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,size=4G 0 0" >> /etc/fstab
        echo "[+] Added /tmp tmpfs entry to /etc/fstab."
    fi
else
    echo "[*] RAM is below 8GB. Skipping /tmp as tmpfs to prevent memory exhaustion."
fi

echo "[+] Remounting filesystems to apply changes..."
mount -o remount /dev/shm || true
systemctl daemon-reload

echo "[+] Tmpfs optimization setup complete!"




# How to verify success: 
# Run df -h | grep -E "tmpfs|shm" to confirm that /tmp and /dev/shm are active as mounted tmpfs instances utilizing your system memory.


