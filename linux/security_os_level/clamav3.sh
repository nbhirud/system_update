#!/bin/bash
# Run as root

set -e
# -e = Exit immediately if a command exits with a non-zero status.

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

EMAIL="you@example.com"   # Set your email address here

# Check if email was set
if [[ $EMAIL -e "you@example.com" ]]; then
   echo "Set email address and run again."
   exit 1
fi

echo "[+] Installing required packages..."
dnf install -y clamav clamav-update clamav-scanner clamav-scanner-systemd \
clamav-server clamav-server-systemd libnotify mailx
# dnf install -y clamav clamav-freshclam clamav-daemon clamav-update notify-send postfix mailx

# packagesNeeded=(clamav clamd clamav-update clamtk)
# sudo dnf install "${packagesNeeded[@]}"

# Config paths
SCAN_CONF="/etc/clamd.d/scan.conf"
FRESHCLAM_CONF="/etc/freshclam.conf"


# Log paths
CLAMAV_LOG_BASE="/var/log/clamav"
CLAM_SCAN_LOG="/var/log/clamd.scan"
# $CLAMAV_LOG_BASE/clamd.log
FRESHCLAM_LOG="/var/log/freshclam.log"
# $CLAMAV_LOG_BASE/freshclam.log
DAILY_LOG="/var/log/clamav-daily.log"

# Create clamav log base directory
mkdir -p $CLAMAV_LOG_BASE
chown clamav:clamav $CLAMAV_LOG_BASE
chmod 755 /var/log/clamav

# Creating log files and setting permissions..."
touch $CLAM_SCAN_LOG $FRESHCLAM_LOG $DAILY_LOG
chown clamscan:clamscan $CLAM_SCAN_LOG
chown clamupdate:clamupdate $FRESHCLAM_LOG

echo "[+] Configuring ClamAV (clamd and freshclam)..."

# Configure freshclam
# LogRotate yes
# LogTime yes
# LogFileMaxSize 100M
# LogFile '$FRESHCLAM_LOG'
sed -i 's/^Example/#Example/' $FRESHCLAM_CONF
sed -i 's|^#UpdateLogFile .*|UpdateLogFile '$FRESHCLAM_LOG'|' $FRESHCLAM_CONF
if ! grep -q "^Checks" $FRESHCLAM_CONF; then
    echo "Checks 24" >> $FRESHCLAM_CONF
fi

# Configure clamd
# LogRotate yes
sed -i 's/^Example/#Example/' $SCAN_CONF
sed -i 's|^#LocalSocket .*|LocalSocket /run/clamd.scan/clamd.sock|' $SCAN_CONF
sed -i 's|^#LogFile .*|LogFile '$CLAM_SCAN_LOG'|' $SCAN_CONF
sed -i 's|^#LogTime .*|LogTime yes|' $SCAN_CONF
sed -i 's|^#LogSyslog .*|LogSyslog yes|' $SCAN_CONF
sed -i 's|^#User .*|User clamscan|' $SCAN_CONF


# Configure SELinux
# -P flag makes this setting persistent across reboots
setsebool -P antivirus_can_scan_system 1 

echo "[+] Configuring On-Access Scanning..."
if ! grep -q "^OnAccessIncludePath" $SCAN_CONF; then
    cat <<EOL >> $SCAN_CONF

# On-Access Scanning Settings
OnAccessIncludePath /home
OnAccessIncludePath /tmp
OnAccessExcludeUname clamav
OnAccessExcludeRootUID true # check this setting
OnAccessPrevention yes
OnAccessMountPath /
# ScanOnAccess yes # check this setting

EOL
fi

echo "[+] Initial virus database update..."
freshclam # freshclam will run as a service later.

echo "[+] Enabling and starting clamd and freshclam services..."
systemctl enable --now clamd@scan
# systemctl enable --now clamd@scan.service
systemctl enable --now freshclam
# systemctl enable --now clamav-freshclam.service
# systemctl enable --now clamav-clamonacc.service


echo "[+] Enabling clamonacc (On-Access Scanning)..."
systemctl enable --now clamonacc@scan
# systemctl enable --now clamav-clamonacc.service

echo "[+] Detecting SSD/HDD and RAM and applying performance tuning..."
SSD_PRESENT=false
while read -r dev rota; do
    if [ "$rota" -eq 0 ]; then
        SSD_PRESENT=true
    fi
done < <(lsblk -d -o name,rota | tail -n +2)

RAM_GB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
echo "[*] Total RAM: $RAM_GB GB"

if $SSD_PRESENT; then
    echo "[*] SSD detected: applying optimizations..."
    sed -i 's|^#TemporaryDirectory .*|TemporaryDirectory /dev/shm|' $SCAN_CONF
    sed -i 's|^#MaxThreads .*|MaxThreads 4|' $SCAN_CONF
    sed -i 's|^#ConcurrentDatabaseReload .*|ConcurrentDatabaseReload yes|' $SCAN_CONF
    # MaxThreads 20
    # ConcurrentDatabaseReload no
    # CacheSize 1000000
if [ "$RAM_GB" -ge 16 ]; then
    echo "[*] RAM >=16GB: mounting /tmp as tmpfs"
    if ! grep -q "tmpfs /tmp" /etc/fstab; then
        echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev 0 0" >> /etc/fstab
        mount -o remount /tmp
    fi
fi

echo "[+] Creating systemd service and timer for daily scan..."

# # Create the script for the weekly scan
# cat << 'EOF' > /usr/local/bin/clamav-weekly-scan.sh
# #!/bin/bash
# LOGFILE="/var/log/clamav/weekly_scan_$(date +\%Y-\%m-\%d).log"
# clamdscan --multiscan -r / --exclude-dir="/proc|/sys|/dev|/run|/var/log|/var/spool/postfix" --infected --log="$LOGFILE"
# INFECTED_COUNT=$(grep -c 'Infected files: 1' "$LOGFILE")
# if [ "$INFECTED_COUNT" -gt 0 ]; then
#     echo "ClamAV Weekly Scan found a virus!" | mail -s "ClamAV Weekly Scan Alert" "$EMAIL_ADDRESS"
#     sudo -u "$SUDO_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$SUDO_USER")/bus notify-send "ClamAV Alert" "A virus was found during the weekly scan. Check $LOGFILE for details." -i dialog-warning
# fi
# EOF
# chmod +x /usr/local/bin/clamav-weekly-scan.sh

cat <<EOL > /etc/systemd/system/clamav-scan.service
[Unit]
Description=Daily ClamAV Scan

[Service]
Type=oneshot
ExecStart=/bin/bash -c '/usr/bin/clamdscan --infected --log=$DAILY_LOG / && \
if grep -q "Infected files: [1-9]" $DAILY_LOG; then \
/usr/bin/notify-send "⚠ ClamAV Alert" "Infected files detected! Check $DAILY_LOG"; \
cat $DAILY_LOG | mailx -s "ClamAV Alert: Infected Files Detected" $EMAIL; \
fi'
EOL

# # Create the systemd service file
# cat << EOF > /etc/systemd/system/clamav-weekly-scan.service
# [Unit]
# Description=ClamAV Weekly Full System Scan

# [Service]
# Type=oneshot
# ExecStart=/usr/local/bin/clamav-weekly-scan.sh
# User=root
# EOF


cat <<EOL > /etc/systemd/system/clamav-scan.timer
[Unit]
Description=Run ClamAV Scan Daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOL

# # Create the systemd timer file
# cat << EOF > /etc/systemd/system/clamav-weekly-scan.timer
# [Unit]
# Description=Run ClamAV Weekly Full System Scan

# [Timer]
# OnCalendar=weekly
# Persistent=true

# [Install]
# WantedBy=timers.target
# EOF

systemctl daemon-reload
systemctl enable --now clamav-scan.timer
# systemctl enable --now clamav-weekly-scan.timer




echo "[+] Setting up automatic USB/external drive scanning..."
# Create systemd template service
cat <<EOL > /etc/systemd/system/clamav-usb@.service
[Unit]
Description=ClamAV Scan for USB Drive %I
After=local-fs.target
[Service]
Type=oneshot
ExecStart=/bin/bash -c '/usr/bin/clamdscan --infected --log=/var/log/clamav-usb-%i.log /run/media/%U/%i && \
if grep -q "Infected files: [1-9]" /var/log/clamav-usb-%i.log; then \
/usr/bin/notify-send "⚠ ClamAV Alert" "Infected files detected on USB drive %i"; \
cat /var/log/clamav-usb-%i.log | mailx -s "ClamAV Alert: Infected Files on USB %i" '$EMAIL'; \
fi'
EOL

# # --- Step 7: Setup External Device Scanning with Udev Rules ---
# echo "7. Setting up automatic external device scanning..."
# # Create the script for scanning external devices
# cat << 'EOF' > /usr/local/bin/clamav-usb-scan.sh
# #!/bin/bash
# LOGFILE="/var/log/clamav/usb_scan_$(date +\%Y-\%m-\%d).log"
# if [ -n "$1" ]; then
#     clamdscan -r "$1" --infected --log="$LOGFILE"
#     INFECTED_COUNT=$(grep -c 'Infected files: 1' "$LOGFILE")
#     if [ "$INFECTED_COUNT" -gt 0 ]; then
#         echo "ClamAV found a virus on a connected USB device!" | mail -s "ClamAV USB Alert" "$EMAIL_ADDRESS"
#         sudo -u "$SUDO_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$SUDO_USER")/bus notify-send "ClamAV Alert" "A virus was found on a connected external device. Check $LOGFILE for details." -i dialog-warning
#     fi
# fi
# EOF
# chmod +x /usr/local/bin/clamav-usb-scan.sh

# Create udev rule
cat <<EOL > /etc/udev/rules.d/99-clamav-usb.rules
ACTION=="mount", KERNEL=="sd[a-z][0-9]", ENV{ID_FS_TYPE}!="", RUN+="/bin/systemctl start clamav-usb@%E{ID_FS_LABEL}.service"
EOL

# # Create the udev rule
# cat << EOF > /etc/udev/rules.d/85-clamav-usb.rules
# ACTION=="add", SUBSYSTEMS=="usb", KERNEL=="sd[a-z][0-9]", RUN+="/bin/bash -c 'sleep 5 && /usr/local/bin/clamav-usb-scan.sh /run/media/$SUDO_USER/%k'"
# EOF

udevadm control --reload
udevadm trigger

# # Reload udev rules to apply the change
# udevadm control --reload-rules




# # --- Step 8: Final Verification and Postfix Setup ---
# echo "8. Finalizing setup and testing..."
# echo "Configuring Postfix for sending emails..."
# postconf -e "myhostname = $(hostname)"
# postconf -e "mydestination = $myhostname, localhost"
# systemctl enable --now postfix

# echo "ClamAV comprehensive setup is complete. You can view logs in /var/log/clamav/."

# exit 0



echo "[+] Master ClamAV setup complete!"
echo "Logs:"
echo " - ClamAV: $CLAM_SCAN_LOG"
echo " - Freshclam: $FRESHCLAM_LOG"
echo " - Daily scan: $DAILY_LOG"
echo " - USB scans: /var/log/clamav-usb-<LABEL>.log"
echo
echo "[*] On-access scanning via clamonacc enabled"
echo "[*] Daily scan timer active: clamav-scan.timer"
echo "[*] USB/external drives will be scanned automatically on mount"
echo "[*] GNOME notifications and email alerts enabled for all scans"

# Testing:
# systemctl status clamav-freshclam.service
# systemctl status clamd@scan.service
# systemctl status clamav-clamonacc.service

# Download the EICAR test file, which is a harmless file that most antivirus programs detect as a virus. When you attempt to access this file, clamonacc should detect it and block access if OnAccessPrevention is enabled. You can check the logs to see the detection.
# wget https://www.eicar.org/download/eicar.com.txt

# check log files
# tail -f /var/log/clamav/clamd.log

