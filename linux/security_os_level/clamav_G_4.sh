#!/bin/bash

# ==============================================================================
# ClamAV Comprehensive Setup Script for Fedora
#
# This script automates the full setup of ClamAV on a Fedora system. It includes:
# - Installation and core configuration
# - SELinux adjustments
# - Performance optimizations for mixed hardware
# - Automatic database updates via freshclam
# - Real-time on-access scanning with prevention
# - Weekly full system scans via a systemd timer
# - Automatic scanning of external devices upon connection
# - Gnome desktop notifications for scan results
# - Email notifications for infected files
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- User Configuration ---
# Replace with your email address for notifications
EMAIL_ADDRESS="your_email@example.com"
# --- End of User Configuration ---

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

echo "Starting ClamAV comprehensive setup on Fedora..."

# --- Step 1: Install ClamAV and Dependencies ---
echo "1. Installing ClamAV and other required packages..."
dnf install -y clamav clamav-freshclam clamav-daemon clamav-update notify-send postfix mailx

# --- Step 2: Configure SELinux ---
echo "2. Configuring SELinux for system scanning..."
setsebool -P antivirus_can_scan_system 1

# --- Step 3: Configure freshclam for Automatic Updates ---
echo "3. Configuring freshclam for automatic database updates..."
freshclam_conf="/etc/clamav/freshclam.conf"
sed -i 's/^Example/# Example/' "$freshclam_conf"
echo "LogFile /var/log/clamav/freshclam.log" >> "$freshclam_conf"
echo "LogRotate yes" >> "$freshclam_conf"
echo "LogTime yes" >> "$freshclam_conf"
echo "LogFileMaxSize 100M" >> "$freshclam_conf"

mkdir -p /var/log/clamav
chown clamav:clamav /var/log/clamav
chmod 755 /var/log/clamav

echo "Running initial 'freshclam' database update..."
freshclam

echo "Enabling and starting 'clamav-freshclam' service..."
systemctl enable --now clamav-freshclam.service

# --- Step 4: Configure clamd with Optimizations ---
echo "4. Configuring clamd with optimizations..."
clamd_conf="/etc/clamav/clamd.conf"
sed -i 's/^Example/# Example/' "$clamd_conf"
sed -i 's/^#LocalSocket \/run\/clamd.scan\/clamd.sock/LocalSocket \/run\/clamd.scan\/clamd.sock/' "$clamd_conf"
echo "LogFile /var/log/clamav/clamd.log" >> "$clamd_conf"
echo "LogRotate yes" >> "$clamd_conf"
echo "LogTime yes" >> "$clamd_conf"

echo "
# Optimization settings
OnAccessPrevention yes
MaxThreads 20
ConcurrentDatabaseReload no
CacheSize 1000000
" >> "$clamd_conf"

# --- Step 5: Enable On-Access Scanning and Services ---
echo "5. Enabling on-access scanning and ClamAV services..."
echo "ScanOnAccess yes" >> "$clamd_conf"
echo "OnAccessIncludePath /home" >> "$clamd_conf"
echo "OnAccessIncludePath /tmp" >> "$clamd_conf"
echo "OnAccessExcludeUname clamav" >> "$clamd_conf"

echo "Enabling and starting 'clamd@scan' service..."
systemctl enable --now clamd@scan.service

echo "Enabling and starting 'clamav-clamonacc' service..."
systemctl enable --now clamav-clamonacc.service

# --- Step 6: Setup Weekly Scans with systemd timer ---
echo "6. Setting up a weekly full system scan..."
# Create the script for the weekly scan
cat << 'EOF' > /usr/local/bin/clamav-weekly-scan.sh
#!/bin/bash
LOGFILE="/var/log/clamav/weekly_scan_$(date +\%Y-\%m-\%d).log"
clamdscan --multiscan -r / --exclude-dir="/proc|/sys|/dev|/run|/var/log|/var/spool/postfix" --infected --log="$LOGFILE"
INFECTED_COUNT=$(grep -c 'Infected files: 1' "$LOGFILE")
if [ "$INFECTED_COUNT" -gt 0 ]; then
    echo "ClamAV Weekly Scan found a virus!" | mail -s "ClamAV Weekly Scan Alert" "$EMAIL_ADDRESS"
    sudo -u "$SUDO_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$SUDO_USER")/bus notify-send "ClamAV Alert" "A virus was found during the weekly scan. Check $LOGFILE for details." -i dialog-warning
fi
EOF
chmod +x /usr/local/bin/clamav-weekly-scan.sh

# Create the systemd service file
cat << EOF > /etc/systemd/system/clamav-weekly-scan.service
[Unit]
Description=ClamAV Weekly Full System Scan

[Service]
Type=oneshot
ExecStart=/usr/local/bin/clamav-weekly-scan.sh
User=root
EOF

# Create the systemd timer file
cat << EOF > /etc/systemd/system/clamav-weekly-scan.timer
[Unit]
Description=Run ClamAV Weekly Full System Scan

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl enable --now clamav-weekly-scan.timer

# --- Step 7: Setup External Device Scanning with Udev Rules ---
echo "7. Setting up automatic external device scanning..."
# Create the script for scanning external devices
cat << 'EOF' > /usr/local/bin/clamav-usb-scan.sh
#!/bin/bash
LOGFILE="/var/log/clamav/usb_scan_$(date +\%Y-\%m-\%d).log"
if [ -n "$1" ]; then
    clamdscan -r "$1" --infected --log="$LOGFILE"
    INFECTED_COUNT=$(grep -c 'Infected files: 1' "$LOGFILE")
    if [ "$INFECTED_COUNT" -gt 0 ]; then
        echo "ClamAV found a virus on a connected USB device!" | mail -s "ClamAV USB Alert" "$EMAIL_ADDRESS"
        sudo -u "$SUDO_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$SUDO_USER")/bus notify-send "ClamAV Alert" "A virus was found on a connected external device. Check $LOGFILE for details." -i dialog-warning
    fi
fi
EOF
chmod +x /usr/local/bin/clamav-usb-scan.sh

# Create the udev rule
cat << EOF > /etc/udev/rules.d/85-clamav-usb.rules
ACTION=="add", SUBSYSTEMS=="usb", KERNEL=="sd[a-z][0-9]", RUN+="/bin/bash -c 'sleep 5 && /usr/local/bin/clamav-usb-scan.sh /run/media/$SUDO_USER/%k'"
EOF

# Reload udev rules to apply the change
udevadm control --reload-rules

# --- Step 8: Final Verification and Postfix Setup ---
echo "8. Finalizing setup and testing..."
echo "Configuring Postfix for sending emails..."
postconf -e "myhostname = $(hostname)"
postconf -e "mydestination = $myhostname, localhost"
systemctl enable --now postfix

echo "ClamAV comprehensive setup is complete. You can view logs in /var/log/clamav/."

exit 0