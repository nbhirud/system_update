packagesNeeded=(clamav clamd clamav-update clamtk)
if [ -x "$(command -v apk)" ];
then
    # Alpine Linux
    sudo apk add --no-cache "${packagesNeeded[@]}"

elif [ -x "$(command -v pacman)" ];
then
    # Arch, etc.
    sudo pacman -S "${packagesNeeded[@]}"

elif [ -x "$(command -v apt-get)" ];
then
    # Debian, Ubuntu, etc.
    sudo apt-get install "${packagesNeeded[@]}"

elif [ -x "$(command -v dnf)" ];
then
    # Fedora, RHEL, etc.
    sudo dnf install "${packagesNeeded[@]}"

elif [ -x "$(command -v zypper)" ];
then
    # OpenSUSE, etc.
    sudo zypper install "${packagesNeeded[@]}"

else
    echo "FAILED TO INSTALL PACKAGE: Package manager not found. You must manually install: "${packagesNeeded[@]}"">&2;
fi

# also check linux/playground/test.sh




######################################################
# From Fedora 41
######################################################


###### clamav

sudo dnf upgrade --refresh
sudo dnf -y install clamav clamd clamav-update clamtk
clamscan --version
sudo systemctl stop clamav-freshclam 
sudo freshclam
sudo systemctl start clamav-freshclam
sudo systemctl enable clamav-freshclam --now


# Generate config files:
clamconf -g freshclam.conf > freshclam.conf
clamconf -g clamd.conf > clamd.conf
clamconf -g clamav-milter.conf > clamav-milter.conf

# Create log files:
sudo touch /var/log/freshclam.log
sudo chmod 600 /var/log/freshclam.log
sudo chown clamupdate /var/log/freshclam.log

sudo touch /var/log/clamav.log
sudo chmod 600 /var/log/clamav.log
sudo chown clamscan /var/log/clamav.log

# Configurations:


## freshclam
sudo nano /etc/freshclam.conf
# LogFileMaxSize 20M
# LogTime yes
# LogRotate yes
# DatabaseMirror database.clamav.net
# UpdateLogFile /var/log/freshclam.log
# DatabaseOwner clamupdate
# NotifyClamd yes


## clamd
sudo nano /etc/clamd.d/scan.conf

# Comment the "Example"
# LogFile /var/log/clamav.log
# LogFileMaxSize 20M
# LogTime yes
# LogRotate yes
# ExitOnOOM yes # Not sure if this is a good thing to do
# LocalSocket /var/run/clamd.scan/clamd.sock
# User clamscan
# DetectPUA yes
# TLDR of - https://docs.clamav.net/manual/OnAccess.html
# OnAccessIncludePath /home # Figure out if this is the best option
# OnAccessExcludeUname clamscan
# OnAccessPrevention yes
# OnAccessDisableDDD yes


## Automatated update scheduling:

# 1. create a systemd timer
sudo nano /etc/systemd/system/freshclam.timer

# Add the following content:

# [Unit]
# Description=freshclam database updates

# [Timer]
# OnCalendar=daily
# Persistent=true

# [Install]
# WantedBy=timers.target

# 2. create the corresponding service file
sudo nano /etc/systemd/system/freshclam.service

# Add the following content:

# [Unit]
# Description=freshclam database updater

# [Service]
# Type=oneshot
# ExecStart=/usr/bin/freshclam --quiet

# 3. enable and start the timer
sudo systemctl enable freshclam.timer
sudo systemctl start freshclam.timer


## scheduled scans

# create a cron job
sudo crontab -e

# Add a line to run a daily scan at 2 AM
# 0 2 * * * /usr/bin/clamscan -r /home > /var/log/clamav/daily_scan.log


## Service Management

#  start the ClamAV daemon and enable it to start automatically on boot:
sudo systemctl start clamd@scan
sudo systemctl enable clamd@scan
sudo systemctl status clamd@scan




######################################################
# From Fedora 40
######################################################



# Reference: https://www.linuxcapable.com/install-clamav-on-fedora-linux/
sudo dnf upgrade --refresh # Refresh Fedora System Packages
# sudo dnf install -y clamav clamav-daemon clamtk 
sudo dnf install clamav clamd clamav-update clamtk #  Install ClamAV  and ClamTK GUI

# Update the ClamAV Virus Database
sudo systemctl stop clamav-freshclam 
sudo freshclam
sudo systemctl enable clamav-freshclam --now
sudo systemctl start clamav-freshclam
# ls -l /var/lib/clamav/ # Check ClamAV directory and the dates of the files

# Scanning:
# sudo clamscan [options] [file/directory/-]
sudo clamscan -h # Help
sudo clamscan /home/script.sh # Scan a file
sudo clamscan /home/ # Scan a dir
sudo clamscan -i /home/ # Print only infected files
sudo clamscan -o /home/ # Exclude printing OK files
sudo clamscan --bell -i /home # bell notification upon virus detection
sudo clamscan --bell -i -r /home # Scan directories recursively 
sudo clamscan --bell -i -r /home -l output.txt # Save the scan report to file 
sudo clamscan -i -f /tmp/scan # Scan files listed line-by-line in a specified file 
sudo clamscan -r --remove /home/USER # automatically remove infected files detected during the scan
sudo clamscan -r -i --move=/home/USER/infected /home/ # Move all files requiring quarantine into the specified location
sudo nice -n 15 clamscan && sudo clamscan --bell -i -r /home # To limit CPU usage during the scan, use the nice command

# Scheduled ClamAV Scans
crontab -e
# sudo dnf install cronie # IF ABOVE DOESN'T WORK
# add following line to add daily scan
# 0 1 * * * /usr/bin/clamscan -r --quiet --move=/home/USER/infected /home/

# ClamAV configuration file located at /etc/clamav/clamd.conf

    MaxFileSize: Adjust the maximum file size that ClamAV will scan.
    MaxScanSize: Change the maximum data size that ClamAV will scan within an archive or a file.
    HeuristxxicScanPrecedence: Enable or disable heuristic scanning, which uses techniques to detect unknown malware.



# Configure using - https://docs.clamav.net/manual/Usage/Configuration.html
# TLDR:

# Generate config files:
clamconf -g freshclam.conf > freshclam.conf
clamconf -g clamd.conf > clamd.conf
clamconf -g clamav-milter.conf > clamav-milter.conf

# Create log files:
sudo touch /var/log/freshclam.log
sudo chmod 600 /var/log/freshclam.log
sudo chown clamupdate /var/log/freshclam.log

sudo touch /var/log/clamav.log
sudo chmod 600 /var/log/clamav.log
sudo chown clamscan /var/log/clamav.log

# Configurations:

## freshclam
# Do these configs in ~/freshclam.conf
# LogFileMaxSize 20M
# LogTime yes
# LogRotate yes
# UpdateLogFile /var/log/freshclam.log
# DatabaseOwner clamupdate
# NotifyClamd yes

## clamd
# Do these configs in ~/clamd.conf 
# TODO - find correct path (/etc/clamav/clamd.conf ?)
# Comment the "Example"
# LogFile /var/log/clamav.log
# LogFileMaxSize 20M
# LogTime yes
# LogRotate yes
# ExitOnOOM yes # Not sure if this is a good thing to do
# User clamscan
# DetectPUA yes
# TLDR of - https://docs.clamav.net/manual/OnAccess.html
# OnAccessIncludePath /home # Figure out if this is the best option
# OnAccessExcludeUname clamscan
# OnAccessPrevention yes
# OnAccessDisableDDD yes


# also check /etc/clamd.d/scan.conf


# clamav config
# cd /usr/share/doc/clamd/
sudo nano /usr/share/doc/clamd/clamd.conf



######################################################
# From Ubuntu
######################################################



# clamav and clamtk
sudo apt install -y clamav clamav-daemon clamtk # Found clamtk to be very un-intuitive, but still install
# Configure using - https://docs.clamav.net/manual/Usage/Configuration.html
# TLDR:

# Generate config files:
clamconf -g freshclam.conf > freshclam.conf
clamconf -g clamd.conf > clamd.conf
clamconf -g clamav-milter.conf > clamav-milter.conf

# Create log files:
sudo touch /var/log/freshclam.log
sudo chmod 600 /var/log/freshclam.log
sudo chown clamav /var/log/freshclam.log

sudo touch /var/log/clamav.log
sudo chmod 600 /var/log/clamav.log
sudo chown clamav /var/log/clamav.log

# Configurations:

## freshclam
# Do these configs in ~/freshclam.conf
# LogFileMaxSize 20M
# LogTime yes
# LogRotate yes
# UpdateLogFile /var/log/freshclam.log
# DatabaseOwner clamav
# NotifyClamd yes

## clamd
# Do these configs in ~/clamd.conf
# Comment the "Example"
# LogFile /var/log/clamav.log
# LogFileMaxSize 20M
# LogTime yes
# LogRotate yes
# ExitOnOOM yes # Not sure if this is a good thing to do
# User clamav
# DetectPUA yes
# TLDR of - https://docs.clamav.net/manual/OnAccess.html
# OnAccessIncludePath /home # Figure out if this is the best option
# OnAccessExcludeUname clamav
# OnAccessPrevention yes
# OnAccessDisableDDD yes





######################################################
# From Alpine
######################################################


# Clamav
sudo apk add clamav
sudo freshclam

# https://docs.clamav.net/manual/Usage/Configuration.html

# update the config files
sudo clamscan -i -r /home



######################################################
# From 
######################################################



