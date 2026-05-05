#!/bin/sh

set -eux

# FANGFRISCH_API_KEY1=""
# # Edit /etc/fangfrisch/fangfrisch.conf with keys first.
# if [ "$FANGFRISCH_API_KEY1" = "" ]; then
#   echo "Enter FANGFRISCH_API_KEY1 and run again. Exiting."
# fi

# what is /var/log/clamav.log

# Define operational paths
SCAN_CONF="/etc/clamd.d/scan.conf"
FRESH_CONF="/etc/freshclam.conf"
RUNTIME_DIR="/run/clamd.scan"
CLAMD_PID=$RUNTIME_DIR/clamd.pid
CLAMD_SOCK=$RUNTIME_DIR/clamd.sock
QUARANTINE_DIR="/var/quarantine/clamav"
SIG_DB_DIR="/var/lib/clamav"

LOG_DIR="/var/log/clamav"
FRESH_LOG="$LOG_DIR/freshclam.log"
CLAMD_LOG="$LOG_DIR/clamd.log"
ONACC_LOG="$LOG_DIR/clamonacc.log"

UNOFFICIAL_SIGS_MASTER_CONF="/etc/clamav-unofficial-sigs/master.conf"
UNOFFICIAL_SIGS_OS_CONF="/etc/clamav-unofficial-sigs/os.conf"
# UNOFFICIAL_SIGS_USER_CONF="/etc/clamav-unofficial-sigs/user.conf"



# CLAM_USER="clamav"
CLAM_USER="clamscan"
# UPDATE_USER="clamupdate"


# Install packages
sudo dnf upgrade --refresh -y
sudo dnf install -y clamav clamd clamav-update clamav-unofficial-sigs clamav-data clamav-lib clamav-filesystem 



# Filesystem and Permissions - Ensure volatile directories exist and have correct ownership.

sudo mkdir -p "$RUNTIME_DIR" "$LOG_DIR" "$QUARANTINE_DIR"
# sudo chown clamscan:clamscan "$RUNTIME_DIR" "$LOG_DIR" $CLAMD_LOG
sudo chown -R $CLAM_USER:$CLAM_USER "$RUNTIME_DIR" "$LOG_DIR" "$QUARANTINE_DIR"
sudo chmod -R 750 "$RUNTIME_DIR" "$LOG_DIR"
sudo touch "$FRESH_LOG" "$CLAMD_LOG" "$ONACC_LOG"
sudo chown -R $CLAM_USER:$CLAM_USER "$CLAMD_LOG" "$ONACC_LOG"
sudo chown -R $CLAM_USER:$CLAM_USER "$FRESH_LOG"
sudo chmod -R 700 "$QUARANTINE_DIR"
sudo chown -R $CLAM_USER:$CLAM_USER "$SIG_DB_DIR" # These are tested and correct credentials. Do not change
sudo chmod -R 775 "$SIG_DB_DIR"


# Fangfrisch dirs - not creating as we are using clamav-unofficial-sigs instead
# sudo mkdir -p /var/lib/fangfrisch
# sudo chown clamupdate:clamupdate /var/lib/fangfrisch
# sudo mkdir -p /var/lib/fangfrisch
# sudo chmod 770 /var/lib/fangfrisch
# sudo chgrp clamav /var/lib/fangfrisch




# nautilus-python 
# python3-fangfrisch  
# clamtk clamtk-gnome clamtk-kde


# Disable the background update service to prevent 'locked database' errors during first run
sudo systemctl stop clamav-freshclam.service
# Also stop scan service
sudo systemctl stop clamd@scan.service

# freshclam config:

sudo sed -i '/^Example/d' "$FRESH_CONF"
sudo sed -i 's|^#LogTime.*|LogTime yes|' "$FRESH_CONF"
sudo sed -i 's|^#LogFileMaxSize.*|LogFileMaxSize 20M|' "$FRESH_CONF"
sudo sed -i 's|^#LogRotate.*|LogRotate yes|' "$FRESH_CONF"
sudo sed -i "s|^#UpdateLogFile.*|UpdateLogFile $FRESH_LOG|" "$FRESH_CONF"
# sudo sed -i "s|^#DatabaseOwner.*|DatabaseOwner $UPDATE_USER|" "$FRESH_CONF"
sudo sed -i "s|^#DatabaseOwner.*|DatabaseOwner $CLAM_USER|" "$FRESH_CONF"
sudo sed -i "s|^#NotifyClamd.*|NotifyClamd $SCAN_CONF|" "$FRESH_CONF"
sudo sed -i 's|^#Checks.*|Checks 12|' "$FRESH_CONF"

# Adding third-party signature URLs - TODO: These are broken/non-free. Replace them with more free and reputed sources.
# echo "DatabaseCustomURL http://www.malware.expert/clamav/main.cvd" | sudo tee -a "$FRESH_CONF"
# echo "DatabaseCustomURL https://www.securiteinfo.com/get/clamav-unofficial/securiteinfo.hdb" | sudo tee -a "$FRESH_CONF"


# Configuring clamav-unofficial-sigs

# UNOFFICIAL_SIGS_MASTER_CONF
sudo sed -i 's|^user_configuration_complete=.*|user_configuration_complete="yes"|' "$UNOFFICIAL_SIGS_MASTER_CONF"
sudo sed -i "s|^#clam_user=.*|clam_user=\"$CLAM_USER\"|" "$UNOFFICIAL_SIGS_MASTER_CONF"
sudo sed -i "s|^#clam_group=.*|clam_group=\"$CLAM_USER\"|" "$UNOFFICIAL_SIGS_MASTER_CONF"

# Enable only trusted free sources
# sudo sed -i 's|^#enable_.*sanesecurity.*|enable_sanesecurity="yes"|' $UNOFFICIAL_SIGS_MASTER_CONF

# UNOFFICIAL_SIGS_OS_CONF
sudo sed -i "s|^clam_user=.*|clam_user=\"$CLAM_USER\"|" "$UNOFFICIAL_SIGS_OS_CONF"
sudo sed -i "s|^clam_group=.*|clam_group=\"$CLAM_USER\"|" "$UNOFFICIAL_SIGS_OS_CONF"
sudo sed -i "s|^clam_dbs=.*|clam_dbs=\"$SIG_DB_DIR\"|" "$UNOFFICIAL_SIGS_OS_CONF"
sudo sed -i "s|^clamd_pid=.*|clamd_pid=\"$CLAMD_PID\"|" "$UNOFFICIAL_SIGS_OS_CONF"
sudo sed -i "s|^#clamd_socket=.*|clamd_socket=\"$CLAMD_SOCK\"|" "$UNOFFICIAL_SIGS_OS_CONF"
sudo sed -i "s|^clamd_reload_opt=.*|clamd_reload_opt=\"clamdscan --config-file=$SCAN_CONF --reload\"|" "$UNOFFICIAL_SIGS_OS_CONF"
sudo sed -i "s|^reload_dbs=.*|reload_dbs=\"yes\"|" "$UNOFFICIAL_SIGS_OS_CONF"



# Daemon (clamd) Config:



sudo sed -i '/^Example/d' "$SCAN_CONF"
sudo sed -i "s|^#LogFile.*|LogFile $CLAMD_LOG|" "$SCAN_CONF"
sudo sed -i 's|^#LogTime.*|LogTime yes|' "$SCAN_CONF"
sudo sed -i 's|^#LogRotate.*|LogRotate yes|' "$SCAN_CONF"
sudo sed -i "s|^#PidFile.*|PidFile $CLAMD_PID|" "$SCAN_CONF"
sudo sed -i "s|^#LocalSocket.*|LocalSocket $CLAMD_SOCK|" "$SCAN_CONF"
sudo sed -i 's|^#FixStaleSocket.*|FixStaleSocket yes|' "$SCAN_CONF"
sudo sed -i "s|^#User.*|User $CLAM_USER|" "$SCAN_CONF"
sudo sed -i 's|^#DetectPUA.*|DetectPUA yes|' "$SCAN_CONF"
sudo sed -i 's|^#MaxThreads.*|MaxThreads 4|' "$SCAN_CONF"
sudo sed -i 's|^#ReadTimeout.*|ReadTimeout 180|' "$SCAN_CONF"

# Content Scanning Options
sudo sed -i 's|^#ScanPE.*|ScanPE yes|' "$SCAN_CONF"
sudo sed -i 's|^#ScanELF.*|ScanELF yes|' "$SCAN_CONF"
sudo sed -i 's|^#ScanOLE2.*|ScanOLE2 yes|' "$SCAN_CONF"
sudo sed -i 's|^#ScanPDF.*|ScanPDF yes|' "$SCAN_CONF"
sudo sed -i 's|^#AlertBrokenExecutables.*|AlertBrokenExecutables yes|' "$SCAN_CONF"

# On-Access Scanning (ClamOnAcc)
# Configure Real-time protection for Downloads and Browser Caches
cat <<EOF | sudo tee -a "$SCAN_CONF"
ScanOnAccess yes
OnAccessIncludePath /home/$(whoami)/Downloads
OnAccessIncludePath /home/$(whoami)/.cache/mozilla
OnAccessIncludePath /home/$(whoami)/.cache/google-chrome
OnAccessPrevention yes
OnAccessExcludeUname $CLAM_USER
EOF


# SELinux Hardening - Mandatory for scanning home directories and system paths in Fedora
sudo setsebool -P antivirus_can_scan_system 1
sudo setsebool -P antivirus_use_jit 1


# echo "--- Phase 5: Unofficial Databases (Fangfrisch) ---"
# Fangfrisch is preferred over legacy scripts for MalwarePatrol/SecuriteInfo
# Note: You MUST edit /etc/fangfrisch/fangfrisch.conf with your API keys!


# Initialize unofficial DB (Safe to ignore errors if keys aren't added yet)
# sudo -u clamupdate fangfrisch --conf /etc/fangfrisch/fangfrisch.conf initdb



# Create a systemd service for ClamOnAcc

################
# cat <<EOF | sudo tee /etc/systemd/system/clamav-clamonacc.service
# [Unit]
# Description=ClamAV On-Access Scanner
# Requires=clamd@scan.service
# After=clamd@scan.service


# Type=simple
# User=root
# ExecStart=/usr/sbin/clamonacc -F --log=$CLAMD_LOG --move=/tmp/quarantine
# Restart=on-failure

# [Install]
# WantedBy=multi-user.target
# EOF

################

# cat <<EOF | sudo tee /etc/systemd/system/clamav-clamonacc.service
# [Unit]
# Description=ClamAV On-Access Scanner
# Requires=clamd@scan.service
# After=clamd@scan.service syslog.target network.target


# Type=simple
# User=root
# ExecStart=/usr/sbin/clamonacc -F --fdpass --log=$CLAMD_LOG --move=/tmp/quarantine
# Restart=on-failure

# [Install]
# WantedBy=multi-user.target
# EOF



# sudo mkdir -p /tmp/quarantine
# sudo chmod 700 /tmp/quarantine



################


# --- clamonacc service ---
echo "[+] Creating clamonacc service..."

sudo tee /etc/systemd/system/clamav-clamonacc.service >/dev/null <<EOF
[Unit]
Description=ClamAV On-Access Scanner
Requires=clamd@scan.service
After=clamd@scan.service

[Service]
Type=simple
ExecStart=/usr/sbin/clamonacc \
  --foreground \
  --fdpass \
  --log=$ONACC_LOG \
  --move=$QUARANTINE_DIR \
  --include-path=/home \
  --exclude-uids=0 \
  --exclude-dir=/proc \
  --exclude-dir=/sys

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

################


# Desktop Integration (Wayland)
# For KDE Dolphin (Plasma 6 Path)
# mkdir -p ~/.local/share/kio/servicemenus/
# ln -sf /usr/share/kservices5/ServiceMenus/clamtk-kde.desktop ~/.local/share/kio/servicemenus/clamtk-kde.desktop

# For Gnome Nautilus
# Extensions are installed via clamtk-gnome package automatically.



# Update databases for the first time
sudo freshclam

# Service Activation
# Fedora uses clamd@scan as the default instance.
sudo systemctl daemon-reload
# sudo systemctl enable --now clamav-freshclam.service
sudo systemctl enable --now clamd@scan.service
# sudo systemctl enable --now clamav-clamonacc.service
sudo systemctl enable --now clamav-unofficial-sigs.timer
# sudo systemctl enable --now fangfrisch.timer

# Verification
if systemctl is-active --quiet clamd@scan.service; then
    echo "ClamAV automation successful"
    clamdscan --version
else
    echo "Critical: ClamAV daemon failed to start. Reviewing journal logs..."
    journalctl -u clamd@scan.service --no-pager -n 50
    # exit 1
fi





##### Debugging:

# sudo systemctl status clamd@scan

# ps aux | grep clam

# sudo tail -100 /var/log/clamav/clamd.log
# sudo tail -100 /var/log/clamav/freshclam.log
# sudo tail -100 /var/log/clamav/clamonacc.log

# journalctl -xeu clamd@scan.service

# systemctl cat clamd@scan.service

# sudo journalctl -u clamd@scan.service -n 50 --no-pager

# # Run the following command to display which signatures are being loaded by clamav
# clamscan --debug 2>&1 /dev/null | grep "loaded"


# sudo systemctl daemon-reload
# sudo systemctl restart clamav-freshclam.service
# sudo systemctl restart clamd@scan.service
# sudo systemctl restart clamav-clamonacc.service
# sudo systemctl restart clamav-unofficial-sigs.timer


# sudo systemctl status clamav-freshclam.service
# sudo systemctl status clamd@scan.service
# sudo systemctl status clamav-clamonacc.service
# sudo systemctl status clamav-unofficial-sigs.timer


# sudo systemctl disable clamav-freshclam.service
# sudo systemctl disable clamav-clamonacc.service
