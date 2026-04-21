#!/usr/bin/env bash

set -eux

####################################################
# Part 1: Install and Configure ClamAV

# 1. Update your system:

sudo dnf upgrade --refresh -y

# 2. Install ClamAV packages:

sudo dnf install -y clamav clamav-update clamav-scanner-systemd clamd

# 3. Stop freshclam service temporarily (to prevent conflicts during initial setup):

sudo systemctl stop clamav-freshclam

# 4. Download initial virus definitions:

sudo freshclam

# 5. Re-enable freshclam service:

sudo systemctl enable --now clamav-freshclam

# 6. Create quarantine directory:

sudo mkdir -p /var/quarantine
sudo chown clamav:clamav /var/quarantine
sudo chmod 750 /var/quarantine

# 7. Configure ClamAV daemon: Edit /etc/clamd.d/scan.conf:

sudo nano /etc/clamd.d/scan.conf

# Key settings to verify/set:

# LogFile /var/log/clamav/clamd.log
# LogTime yes
# User clamav
# LocalSocket /var/run/clamav/clamd.sock
# QuarantineDirectory /var/quarantine

# 8. Create log directory:

sudo mkdir -p /var/log/clamav
sudo chown clamav:clamav /var/log/clamav

# 9. Enable and start ClamAV daemon:

sudo systemctl enable --now clamd@scan
sudo systemctl status clamd@scan

####################################################
# Part 2: Install and Configure Fangfrisch

# 10. Install Fangfrisch:
# sudo dnf install -y python3-fangfrisch

# If not available in repos:

pip install python-fangfrisch

# 11. Create Fangfrisch configuration:

sudo mkdir -p /etc/fangfrisch
sudo nano /etc/fangfrisch/fangfrisch.yaml

# Add this configuration:

# database_dir: /var/lib/clamav
# log_file: /var/log/fangfrisch/fangfrisch.log
# sources:
#   - sanesecurity
#   - urlhaus
#   - malwaredomains
#   - malc0de
#   - ransomwaretracker
#   - emerging-threats
#   - cve

# 12. Create log directory for Fangfrisch:

sudo mkdir -p /var/log/fangfrisch
sudo chown clamav:clamav /var/log/fangfrisch

# 13. Set proper permissions:

sudo chown -R clamav:clamav /var/lib/clamav
sudo chmod -R 755 /var/lib/clamav

####################################################
# Part 3: Initial Testing

# 14. Run manual Fangfrisch update:

sudo fangfrisch update

# 15. Verify signatures were downloaded:

ls -lh /var/lib/clamav/*.hdb /var/lib/clamav/*.ndb /var/lib/clamav/*.cdb 2>/dev/null | head -20

# 16. Test ClamAV scan:

sudo clamscan --version
sudo clamscan -r /home/nik/Downloads  # Adjust path as needed

# 17. Test with EICAR test file (safe test virus):

echo 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' | sudo tee /tmp/eicar.txt
sudo clamscan /tmp/eicar.txt

# Should detect it as "Win.Test.EICAR_HDB-1"

####################################################
# Part 4: Automation

# 18. Enable Fangfrisch timer:

sudo systemctl enable --now fangfrisch.timer
sudo systemctl status fangfrisch.timer

# 19. Optional: Set up scheduled scans via cron:

sudo crontab -e

# Add daily scan at 3 AM:

# 0 3 * * * root /usr/bin/clamdscan --log=/var/log/clamav/daily.log --remove /home/nik/Downloads /var/www 2>&1

# Part 5: Monitoring & Maintenance

####################################################
# 20. Check service status:

systemctl status clamav-freshclam
systemctl status clamd@scan
systemctl status fangfrisch.timer

# 21. View logs:

# ClamAV logs
sudo tail -f /var/log/clamav/clamd.log

# Fangfrisch logs
sudo tail -f /var/log/fangfrisch/fangfrisch.log

# Journalctl for all services
journalctl -u clamav-freshclam -u clamd@scan -u fangfrisch.timer -f

# 22. Quick health check script:

#!/bin/bash
echo "=== ClamAV Status ==="
systemctl is-active clamd@scan
echo "=== Freshclam Status ==="
systemctl is-active clamav-freshclam
echo "=== Fangfrisch Status ==="
systemctl is-active fangfrisch.timer
echo "=== Database Size ==="
du -sh /var/lib/clamav/

# Key Points to Remember
# Component	Purpose	Service Name
# ClamAV	Core antivirus engine	clamd@scan
# FreshClam	Official ClamAV signatures	clamav-freshclam
# Fangfrisch	Unofficial signatures	fangfrisch.timer

# Important: Both FreshClam and Fangfrisch can run together, but they shouldn't write to the same files simultaneously. The setup above separates concerns properly.

# Troubleshooting:

#     If signatures fail to download: sudo fangfrisch update --debug
#     If ClamAV can't read signatures: sudo chown -R clamav:clamav /var/lib/clamav
#     If services won't start: sudo journalctl -xe
