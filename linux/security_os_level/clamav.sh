#!/usr/bin/env bash

# set -eux

# set -Eeuo pipefail
# [ "${DEBUG:-0}" = 1 ] && set -x   # -x on always is noisy

set -Eeuo pipefail

# Enable command tracing only when explicitly requested:
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x
fi

# # To debug the script, run:
# DEBUG=1 bash script.sh

# TODO
# Create a script where you pass directory to be scanned
# Script creates folder and log file based on timestamp in /home/user/username/Desktop/<here>
# Pass or set other values and flags

# root (sudo) check
[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user; the script calls sudo itself"; exit 1; }

# Pre-authenticate sudo
# sudo -v
# Pre-authenticate sudo (non-blocking)
if sudo -n -v 2>/dev/null; then
    echo "[+] Sudo already authenticated"
else
    sudo -v || { echo "ERROR: Sudo authentication failed"; exit 1; }
fi

#########################################################
# Useful Reading:
#########################################################

# https://docs.clamav.net/manual/Usage/Configuration.html
# https://wiki.archlinux.org/title/ClamAV
# https://wiki.gentoo.org/wiki/ClamAV
# https://wiki.gentoo.org/wiki/ClamAV_Unofficial_Signatures
# https://docs.clamav.net/manual/Installing/Community-projects.html
# https://docs.clamav.net/manual/OnAccess.html
# https://github.com/extremeshok/clamav-unofficial-sigs
# https://wiki.archlinux.org/title/Clam_AntiVirus
# https://www.linuxcapable.com/install-clamav-on-fedora-linux/


#########################################################
# Inputs:
#########################################################

# # TODO: Take following as inputs as named options. If not provided, use the defaults below
# # HAS_TORRENT_CLIENT
# # HAS_KODI
# # REAL_USER
# # FILENAME_TIMESTAMP
# # SCRIPT_BACKUPS_DIR
# # PC_TYPE

# REAL_USER="${SUDO_USER:-$USER}"

# FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
# # HOME_DIR=$(getent passwd $USER | cut -d: -f6)
# # Get the actual user's home when runing a script with sudo
# HOME_DIR=$(getent passwd "$REAL_USER" | cut -d: -f6)
# NBDIR="$HOME_DIR/nb"
# SCRIPT_DATA="$NBDIR/nb_script_data"
# SCRIPT_BACKUPS_DIR="$SCRIPT_DATA/backups"
# CLAMAV_BACKUP_DIR="$SCRIPT_BACKUPS_DIR/clamav/clamav_$FILENAME_TIMESTAMP"

# PC_TYPE=$(. /etc/os-release; [ "${VARIANT_ID:-}" = server ] && echo server || echo desktop)

# HAS_TORRENT_CLIENT=true # default true for PC_TYPE desktop and false for server
# HAS_KODI=true # default true for PC_TYPE desktop and false for server


##############################
# # INPUTS & CONFIGURATION DEFAULTS - using positional arguments

# # 1. PC_TYPE (default detected via OS release if not provided)
# : "${PC_TYPE:=$( [ "${VARIANT_ID:-}" = server ] && echo server || echo desktop )}"

# # 2. REAL_USER (defaults to SUDO_USER or current user)
# : "${REAL_USER:=${SUDO_USER:-$USER}}"

# # 3. FILENAME_TIMESTAMP (defaults to current timestamp)
# : "${FILENAME_TIMESTAMP:=$(date +%Y-%m-%d_%H-%M-%S)}"

# # Derived paths using REAL_USER and TIMESTAMP
# HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"
# NBDIR="$HOME_DIR/nb"
# SCRIPT_DATA="$NBDIR/nb_script_data"

# # 4. SCRIPT_BACKUPS_DIR (defaults to standard path under nb_script_data)
# : "${SCRIPT_BACKUPS_DIR:="$SCRIPT_DATA/backups"}"
# CLAMAV_BACKUP_DIR="$SCRIPT_BACKUPS_DIR/clamav/clamav_$FILENAME_TIMESTAMP"

# # 5. HAS_TORRENT_CLIENT (default: true for desktop, false for server)
# if [ -z "${HAS_TORRENT_CLIENT:-}" ]; then
#     [ "$PC_TYPE" = "desktop" ] && HAS_TORRENT_CLIENT=true || HAS_TORRENT_CLIENT=false
# fi

# # 6. HAS_KODI (default: true for desktop, false for server)
# if [ -z "${HAS_KODI:-}" ]; then
#     [ "$PC_TYPE" = "desktop" ] && HAS_KODI=true || HAS_KODI=false
# fi


##############################
# INPUTS & CONFIGURATION DEFAULTS - using named options


# DEFAULT VALUES (Fallback if not provided)

PC_TYPE=""
REAL_USER=""
FILENAME_TIMESTAMP=""
SCRIPT_BACKUPS_DIR=""
HAS_TORRENT_CLIENT=""
HAS_KODI=""


# PARSE NAMED OPTIONS

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pc-type=*)
            PC_TYPE="${1#*=}"
            shift
            ;;
        --pc-type)
            PC_TYPE="$2"
            shift 2
            ;;
        --real-user=*)
            REAL_USER="${1#*=}"
            shift
            ;;
        --real-user)
            REAL_USER="$2"
            shift 2
            ;;
        --torrent-client=*)
            HAS_TORRENT_CLIENT="${1#*=}"
            shift
            ;;
        --torrent-client)
            HAS_TORRENT_CLIENT="$2"
            shift 2
            ;;
        --kodi=*)
            HAS_KODI="${1#*=}"
            shift
            ;;
        --kodi)
            HAS_KODI="$2"
            shift 2
            ;;
        --backup-dir=*)
            SCRIPT_BACKUPS_DIR="${1#*=}"
            shift
            ;;
        --backup-dir)
            SCRIPT_BACKUPS_DIR="$2"
            shift 2
            ;;
        --timestamp=*)
            FILENAME_TIMESTAMP="${1#*=}"
            shift
            ;;
        --timestamp)
            FILENAME_TIMESTAMP="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "  --pc-type <desktop|laptop|server>"
            echo "  --real-user <username>"
            echo "  --torrent-client <true|false>"
            echo "  --kodi <true|false>"
            echo "  --backup-dir <path>"
            echo "  --timestamp <YYYY-MM-DD_HH-MM-SS>"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            exit 1
            ;;
    esac
done


# APPLY INTELLIGENT DEFAULTS FOR UNSET OPTIONS

# Treat laptop as desktop from security perspective.
if [ "$PC_TYPE" = "laptop" ]; then
    PC_TYPE="desktop"
fi

# 1. PC_TYPE (detected via OS release if not provided)
if [ -z "$PC_TYPE" ]; then
    PC_TYPE="$( . /etc/os-release; [ "${VARIANT_ID:-}" = server ] && echo server || echo desktop )"   # subshell: no variable pollution

fi

# 2. REAL_USER (defaults to SUDO_USER or current user)
REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"

# 3. TIMESTAMP (defaults to current time if not provided)
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"

# Derived paths using REAL_USER and TIMESTAMP
HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"
NBDIR="$HOME_DIR/nb"
SCRIPT_DATA="$NBDIR/nb_script_data"

# 4. SCRIPT_BACKUPS_DIR
SCRIPT_BACKUPS_DIR="${SCRIPT_BACKUPS_DIR:-$SCRIPT_DATA/backups}"
CLAMAV_BACKUP_DIR="$SCRIPT_BACKUPS_DIR/clamav/clamav_$FILENAME_TIMESTAMP"

# 5. HAS_TORRENT_CLIENT (default based on PC_TYPE if not provided)
if [ -z "$HAS_TORRENT_CLIENT" ]; then
    [ "$PC_TYPE" = "desktop" ] && HAS_TORRENT_CLIENT=true || HAS_TORRENT_CLIENT=false
fi

# 6. HAS_KODI (default based on PC_TYPE if not provided)
if [ -z "$HAS_KODI" ]; then
    [ "$PC_TYPE" = "desktop" ] && HAS_KODI=true || HAS_KODI=false
fi

if [[ ! "$FILENAME_TIMESTAMP" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "ERROR: --timestamp must use YYYY-MM-DD_HH-MM-SS" >&2
    exit 2
fi

#########################################################
# Paths and Constants:
#########################################################

# # Generate config files:
# clamconf -g freshclam.conf > freshclam.conf
# clamconf -g clamd.conf > clamd.conf
# clamconf -g clamav-milter.conf > clamav-milter.conf

# # Create log files:
# sudo touch /var/log/freshclam.log
# sudo chmod 640 /var/log/freshclam.log
# sudo chown clamupdate /var/log/freshclam.log

# sudo touch /var/log/clamav.log
# sudo chmod 640 /var/log/clamav.log
# sudo chown clamscan /var/log/clamav.log


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


#########################################################
# Install packages:
#########################################################

# Install packages
# sudo dnf upgrade --refresh -y
# sudo dnf install -y clamav clamd clamav-update clamav-unofficial-sigs clamav-data clamav-lib clamav-filesystem clamdtop flock
# clamdtop - Terminal dashboard for daemon activity, queued scans, memory usage and loaded signatures. Like htop for clamd

# clamav-lib and clamav-filesystem are pulled in as dependencies. policycoreutils-python-utils provides audit2allow and semanage. util-linux provides flock
sudo dnf install -y clamav clamd clamav-update clamav-unofficial-sigs clamdtop policycoreutils-python-utils util-linux

# Warning: clamav-unofficial-sigs will download third-party signatures.
# Review /etc/clamav-unofficial-sigs/master.conf to control which sources are enabled.
# Some sources are maintained by volunteers; assess trust levels accordingly.


#########################################################
# Dynamic Hardware-Aware Optimization:
#########################################################


CPU_CORES=$(nproc)

# RAM_GB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
RAM_MB=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)
RAM_GB=$(( RAM_MB / 1024 ))



# ClamAV multi-threaded scanning (--multiscan or clamd operations) can easily saturate 100% of available CPU power. By setting MaxThreads to total cores minus one (leaving at least 2 for low-end setups), you prevent ClamAV from completely starving your desktop environment, kernel, and UI responsiveness (Wayland/KDE) during background scans or heavy file unzipping.
# RECOMMENDED_THREADS=$(( CPU_CORES > 2 ? CPU_CORES - 1 : 2 ))

# # safer calculation
# if [ "$CPU_CORES" -le 1 ]; then
#     RECOMMENDED_THREADS=1
# else
#     RECOMMENDED_THREADS=$((CPU_CORES - 1))
# fi


# clamd threads are I/O-bound, so "cores - 1" is the wrong model. Floor of 4.
RECOMMENDED_THREADS=$(( CPU_CORES - 1 ))
if [ "$RECOMMENDED_THREADS" -lt 4 ]; then RECOMMENDED_THREADS=4; fi

echo "Detected $CPU_CORES CPU cores. Will set MaxThreads to $RECOMMENDED_THREADS."


# SSD Tuning

SSD_PRESENT=false
ROOT_DEV=$(df / | tail -1 | awk '{print $1}')
BACKING_DEV=$(lsblk -no pkname "$ROOT_DEV" 2>/dev/null || basename "$ROOT_DEV" | sed 's/[0-9]*$//')

if [ -n "$BACKING_DEV" ] && [ -f "/sys/block/$BACKING_DEV/queue/rotational" ]; then
    if [ "$(cat /sys/block/$BACKING_DEV/queue/rotational)" -eq 0 ]; then
        SSD_PRESENT=true
    fi
elif lsblk -d -o rota | grep -q "^0$"; then
    SSD_PRESENT=true
fi



if   [ "$RAM_MB" -lt 8000 ];  then RAM_PROFILE=low
elif [ "$RAM_MB" -lt 20000 ]; then RAM_PROFILE=mid
else                               RAM_PROFILE=high
fi

CONC_RELOAD=yes     # a second engine is loaded during reload = extra RAM (clamd.conf docs)
if [ "$RAM_PROFILE" = low ]; then CONC_RELOAD=no; fi

ONACC_PREVENT=no    # prevention = every watched open() waits for clamd
if [ "$RAM_MB" -ge 14000 ] && $SSD_PRESENT; then ONACC_PREVENT=yes; fi

ONACC_THREADS=$(( RECOMMENDED_THREADS - 2 ))   # must stay below clamd MaxThreads
if [ "$ONACC_THREADS" -gt 5 ]; then ONACC_THREADS=5; fi
echo "RAM profile=$RAM_PROFILE threads=$RECOMMENDED_THREADS prevention=$ONACC_PREVENT concurrent_reload=$CONC_RELOAD"




#########################################################
# Back up existing configuration files before modifying them:
#########################################################

# mkdir -p "$CLAMAV_BACKUP_DIR"
# sudo install -d -o "$CLAM_USER" -g "$CLAM_USER" -m 750 "$CLAMAV_BACKUP_DIR" 
# sudo install -d -o "$REAL_USER" -g "$REAL_USER" -m 750 "$CLAMAV_BACKUP_DIR"

# Backups are created by the invoking user. Never use root to create or copy
# files into this user-controlled destination: that would permit symlink/path attacks.
# umask 077
( umask 077; mkdir -p -- "$CLAMAV_BACKUP_DIR" )   # strict only for this one directory
mkdir -p -- "$CLAMAV_BACKUP_DIR"

# if [[ ! -d "$CLAMAV_BACKUP_DIR" || -L "$CLAMAV_BACKUP_DIR" ]]; then
#     echo "ERROR: Backup destination must be a real directory, not a symlink: $CLAMAV_BACKUP_DIR" >&2
#     exit 1
# fi


# SECURITY: Prevent symlink attacks on backup directory
if [[ -L "$CLAMAV_BACKUP_DIR" ]] || [[ -h "$CLAMAV_BACKUP_DIR" ]]; then
    echo "ERROR: Backup path is a symlink - possible attack. Aborting." >&2
    exit 1
fi

# Ensure it's a real directory (not a symlink to a file)
if [[ -e "$CLAMAV_BACKUP_DIR" ]] && [[ ! -d "$CLAMAV_BACKUP_DIR" ]]; then
    echo "ERROR: Backup path exists but is not a directory." >&2
    exit 1
fi

# Secure permissions BEFORE using the directory
chmod 700 -- "$CLAMAV_BACKUP_DIR"


for config_file in "$SCAN_CONF" "$FRESH_CONF" "$UNOFFICIAL_SIGS_MASTER_CONF" "$UNOFFICIAL_SIGS_OS_CONF"; do

    if [ -f "$config_file" ]; then
        sudo cp -a "$config_file" "$CLAMAV_BACKUP_DIR/"
    fi
done

echo "Configuration backups saved in: $CLAMAV_BACKUP_DIR"


#########################################################
### Filesystem and Permissions - Ensure volatile directories exist and have correct ownership.
#########################################################

# NOTE: TODO - 750 gives executable permission to log and db files. Find out what is ideal here. They should not need executable permission. 
# Maybe 640 instead of 750. Check what is ideal for each file or directory

# TODO: Review directory and regular-file permissions separately.
# Do not use recursive chmod 750 on mixed directories containing logs
# and database files. Determine the required ownership and permissions
# for each directory, regular file, and Unix socket before changing them.


###########################
# The following is Tested and works perfectly:

# # LOG files:
# sudo mkdir -p "$LOG_DIR"
# # sudo chown clamscan:clamscan "$LOG_DIR" $CLAMD_LOG
# sudo chown -R $CLAM_USER:$CLAM_USER "$LOG_DIR"
# sudo chmod -R 750 "$LOG_DIR"
# # sudo install -d -o "$CLAM_USER" -g "$CLAM_USER" -m 750 "$LOG_DIR"
# sudo touch "$FRESH_LOG" "$CLAMD_LOG" "$ONACC_LOG"
# sudo chmod 640  "$FRESH_LOG" "$CLAMD_LOG" "$ONACC_LOG"
# sudo chown -R $CLAM_USER:$CLAM_USER "$FRESH_LOG" "$CLAMD_LOG" "$ONACC_LOG"


sudo install -d -o "$CLAM_USER" -g "$CLAM_USER" -m 750 "$LOG_DIR"
sudo touch "$FRESH_LOG" "$CLAMD_LOG" "$ONACC_LOG"
sudo chown "$CLAM_USER:$CLAM_USER" "$FRESH_LOG" "$CLAMD_LOG" "$ONACC_LOG"
sudo chmod 640 "$FRESH_LOG" "$CLAMD_LOG" "$ONACC_LOG"

# # Creating logs with touch followed by chown/chmod leaves a brief window where unprivileged users might be able to replace or modify the log files. Use atomic file creation:
# for logfile in "$FRESH_LOG" "$CLAMD_LOG" "$ONACC_LOG"; do
#     if [[ ! -f "$logfile" ]]; then
#         sudo install -o "$CLAM_USER" -g "$CLAM_USER" -m 640 /dev/null "$logfile"
#     else
#         # Existing file: just fix ownership/permissions
#         sudo chown "$CLAM_USER:$CLAM_USER" "$logfile"
#         sudo chmod 640 "$logfile"
#     fi
# done

###########################
# The following is Tested and works perfectly:

# # DATABASE files:
# sudo chown -R $CLAM_USER:$CLAM_USER "$SIG_DB_DIR" # These are tested and correct credentials. Do not change
# sudo chmod -R 750 "$SIG_DB_DIR"

# # # Directories need execute permission for traversal.
# # sudo find "$SIG_DB_DIR" -type d -exec chmod 750 {} +

# # # Database files generally need read access, not execute permission.
# # sudo find "$SIG_DB_DIR" -type f -exec chmod 640 {} +



# DB dir: ownership kept as you have it; dirs need +x, files don't (your TODO at L169)
sudo chown -R "$CLAM_USER:$CLAM_USER" "$SIG_DB_DIR"
sudo find "$SIG_DB_DIR" -type d -exec chmod 750 {} +
sudo find "$SIG_DB_DIR" -type f -exec chmod 640 {} +


###########################
# The following is Tested and works perfectly:

# # RUNTIME files:
# sudo mkdir -p "$RUNTIME_DIR"
# # sudo chown clamscan:clamscan "$RUNTIME_DIR"
# sudo chown -R $CLAM_USER:$CLAM_USER "$RUNTIME_DIR"
# sudo chmod -R 750 "$RUNTIME_DIR"


# /run/clamd.scan: Commented above block as /run is wiped at boot; the package recreates it.

###########################
# SOCK
# sudo touch $CLAMD_SOCK
# Commented the touch command above because when clamd boots up, it reads $SCAN_CONF file. It sees LocalSocket $CLAMD_SOCK and automatically creates a Unix socket file at that location. 

# sudo chown -R $CLAM_USER:$CLAM_USER $CLAMD_SOCK

###########################
# The following is Tested and works perfectly:

# # QUARANTINE files:
# sudo mkdir -p "$QUARANTINE_DIR"
# sudo chown -R $CLAM_USER:$CLAM_USER "$QUARANTINE_DIR"
# sudo chmod -R 700 "$QUARANTINE_DIR"


# Quarantine: clamonacc (root) does the move. Give it a label the antivirus domain may write.
sudo install -d -o root -g root -m 700 "$QUARANTINE_DIR"
sudo semanage fcontext -a -t antivirus_db_t "$QUARANTINE_DIR(/.*)?" 2>/dev/null \
  || sudo semanage fcontext -m -t antivirus_db_t "$QUARANTINE_DIR(/.*)?"
sudo restorecon -R "$QUARANTINE_DIR"


#########################################################
# Fangfrisch - Skip this. We are using clamav-unofficial-sigs instead
#########################################################

# https://rseichter.github.io/fangfrisch/

# FANGFRISCH_API_KEY1=""
# # Edit /etc/fangfrisch/fangfrisch.conf with keys first.
# if [ "$FANGFRISCH_API_KEY1" = "" ]; then
#   echo "Enter FANGFRISCH_API_KEY1 and run again. Exiting."
# fi


# # Fangfrisch dirs - not creating as we are using clamav-unofficial-sigs instead
# sudo mkdir -p /var/lib/fangfrisch
# sudo chown clamupdate:clamupdate /var/lib/fangfrisch
# sudo mkdir -p /var/lib/fangfrisch
# sudo chmod 770 /var/lib/fangfrisch
# sudo chgrp clamav /var/lib/fangfrisch

# # Create home directory
# # mkdir -m 0770 -p /var/lib/fangfrisch
# mkdir -p /var/lib/fangfrisch
# chmod 770 /var/lib/fangfrisch
# chgrp clamav /var/lib/fangfrisch

# # Prepare and activate venv
# cd /var/lib/fangfrisch
# python3 -m venv venv
# source venv/bin/activate

# # Install via PyPI
# pip install fangfrisch


# echo "--- Phase 5: Unofficial Databases (Fangfrisch) ---"
# Fangfrisch is preferred over legacy scripts for MalwarePatrol/SecuriteInfo
# Note: You MUST edit /etc/fangfrisch/fangfrisch.conf with your API keys!


# Initialize unofficial DB (Safe to ignore errors if keys aren't added yet)
# sudo -u clamupdate fangfrisch --conf /etc/fangfrisch/fangfrisch.conf initdb


# # Fangfrisch

# # Use clamav-unofficial-sigs or fangfrisch (a more secure alternative) to manage MalwarePatrol signatures.
# sudo dnf install epel-release python3-fangfrisch
# # Configure /etc/fangfrisch/fangfrisch.conf
# # [malwarepatrol]
# # enabled = true
# # url = https://cdn.malwarepatrol.net/lists/clamav_basic
# # receipt_code = YOUR-RECEIPT-NUMBER
# # product_code = 8
# # output = /var/lib/clamav/malwarepatrol.db
# # Run fangfrisch to download signatures:
# sudo fangfrisch --conf /etc/fangfrisch/fangfrisch.conf refresh
# # Enable the fangfrisch.timer for automatic updates:
# sudo systemctl enable --now fangfrisch.timer


# For fangfrisch, configure /etc/fangfrisch/fangfrisch.conf:
# [securiteinfo]
# enabled = true
# url = https://www.securiteinfo.com/get/signatures/YOUR-AUTH-CODE/securiteinfo.hdb
# output = /var/lib/clamav/securiteinfo.hdb


##########


# # Install and Configure Fangfrisch

# # 10. Install Fangfrisch:
# # sudo dnf install -y python3-fangfrisch

# # If not available in repos:

# pip install python-fangfrisch

# # 11. Create Fangfrisch configuration:

# sudo mkdir -p /etc/fangfrisch
# sudo nano /etc/fangfrisch/fangfrisch.yaml

# # Add this configuration:

# # database_dir: /var/lib/clamav
# # log_file: /var/log/fangfrisch/fangfrisch.log
# # sources:
# #   - sanesecurity
# #   - urlhaus
# #   - malwaredomains
# #   - malc0de
# #   - ransomwaretracker
# #   - emerging-threats
# #   - cve

# # 12. Create log directory for Fangfrisch:

# sudo mkdir -p /var/log/fangfrisch
# sudo chown clamav:clamav /var/log/fangfrisch

# # 13. Set proper permissions:

# sudo chown -R clamav:clamav /var/lib/clamav
# sudo chmod -R 755 /var/lib/clamav

# # 14. Run manual Fangfrisch update:

# sudo fangfrisch update

# # 15. Verify signatures were downloaded:

# ls -lh /var/lib/clamav/*.hdb /var/lib/clamav/*.ndb /var/lib/clamav/*.cdb 2>/dev/null | head -20


# # 18. Enable Fangfrisch timer:

# sudo systemctl enable --now fangfrisch.timer
# sudo systemctl status fangfrisch.timer

# # 19. Optional: Set up scheduled scans via cron:

# sudo crontab -e

# # Add daily scan at 3 AM:

# # 0 3 * * * root /usr/bin/clamdscan --log=/var/log/clamav/daily.log --remove /home/nik/Downloads /var/www 2>&1


# # 20. Check service status:

# systemctl status clamav-freshclam
# systemctl status clamd@scan
# systemctl status fangfrisch.timer

# # 21. View logs:

# # ClamAV logs
# sudo tail -f /var/log/clamav/clamd.log

# # Fangfrisch logs
# sudo tail -f /var/log/fangfrisch/fangfrisch.log

# # Journalctl for all services
# journalctl -u clamav-freshclam -u clamd@scan -u fangfrisch.timer -f

# # 22. Quick health check script:

# #!/bin/bash
# echo "=== ClamAV Status ==="
# systemctl is-active clamd@scan
# echo "=== Freshclam Status ==="
# systemctl is-active clamav-freshclam
# echo "=== Fangfrisch Status ==="
# systemctl is-active fangfrisch.timer
# echo "=== Database Size ==="
# du -sh /var/lib/clamav/


# # Important: Both FreshClam and Fangfrisch can run together, but they shouldn't write to the same files simultaneously. The setup above separates concerns properly.

# # Troubleshooting:

# #     If signatures fail to download: sudo fangfrisch update --debug
# #     If ClamAV can't read signatures: sudo chown -R clamav:clamav /var/lib/clamav
# #     If services won't start: sudo journalctl -xe




#########################################################
# reusable configuration-setting function - Updates an active or commented setting, removes duplicate instances - set_config_value()
#########################################################

# # Set or replace a single-line configuration directive.
# # Supports both active and commented-out directives.
# set_config_value() {
#     config_file=$1
#     config_key=$2
#     config_value=$3

#     sudo awk -v key="$config_key" -v value="$config_value" '
#         BEGIN {
#             found = 0
#         }

#         $0 ~ "^[[:space:]]*#?[[:space:]]*" key "([[:space:]]|$)" {
#             if (!found) {
#                 print key " " value
#                 found = 1
#             }
#             next
#         }

#         {
#             print
#         }

#         END {
#             if (!found) {
#                 print key " " value
#             }
#         }
#     ' "$config_file" | sudo tee "${config_file}.tmp" >/dev/null &&
#         sudo install -m "$(stat -c '%a' "$config_file")" \
#             "${config_file}.tmp" "$config_file" &&
#         sudo rm -f "${config_file}.tmp"
# }






##################

# Set or update a configuration setting.
#
# Usage:
#   set_config_value CONFIG_FILE SETTING VALUE
#
# Supports:
#   - clamav-unofficial-sigs: key="value"
#   - ClamAV configs:         Key value
#
# Updates an active or commented setting, removes duplicate instances
# of that setting, or appends it if the setting does not exist.
# Preserves the existing file's ownership and permissions.

set_config_value() (
    config_file=$1
    config_key=$2
    config_value=$3

    if [ "$#" -ne 3 ] || [ -z "$config_file" ] || [ -z "$config_key" ]; then
        echo "Usage: set_config_value CONFIG_FILE SETTING VALUE" >&2
        exit 2
    fi

    if ! sudo test -f "$config_file"; then
        echo "Error: configuration file does not exist: $config_file" >&2
        exit 1
    fi

    # Detect which configuration syntax the file uses.
    case "$config_file" in
        */clamav-unofficial-sigs/*.conf)
            config_style="shell"
            ;;
        *)
            config_style="clamav"
            ;;
    esac

    # Keep the temporary file beside the original so the final rename
    # happens on the same filesystem.
    temp_file="${config_file}.tmp.$$"

    # Replace the first matching setting, discard duplicate settings,
    # and append the setting if it was not present.
    if ! sudo awk \
        -v key="$config_key" \
        -v value="$config_value" \
        -v style="$config_style" '
        BEGIN {
            found = 0
        }

        {
            if (style == "shell") {
                matches = $0 ~ ("^[[:space:]]*#?[[:space:]]*" key "[[:space:]]*=")
            } else {
                # matches = $0 ~ ("^[[:space:]]*#?[[:space:]]*" key "([[:space:]]|$)")
                matches = $0 ~ ("^[[:space:]]*#?" key "([[:space:]]|$)")
            }

            if (matches) {
                if (!found) {
                    if (style == "shell") {
                        print key "=\"" value "\""
                    } else {
                        print key " " value
                    }
                    found = 1
                }
                next
            }

            print
        }

        END {
            if (!found) {
                if (style == "shell") {
                    print key "=\"" value "\""
                } else {
                    print key " " value
                }
            }
        }
        ' "$config_file" | sudo tee "$temp_file" >/dev/null
    then
        sudo rm -f "$temp_file"
        echo "Error: failed to update $config_file" >&2
        exit 1
    fi

    # Preserve the original ownership and permissions.
    if ! sudo chmod --reference="$config_file" "$temp_file" ||
       ! sudo chown --reference="$config_file" "$temp_file" ||
       ! sudo mv -f "$temp_file" "$config_file"
    then
        sudo rm -f "$temp_file"
        echo "Error: could not safely replace $config_file" >&2
        exit 1
    fi

    echo "Updated $config_key in $config_file"
)


#########################################################
# helper for repeatable settings - add_config_value():
#########################################################


# Add a repeatable ClamAV directive without deleting other entries
# with the same directive name.
#
# Usage:
#   add_config_value CONFIG_FILE DIRECTIVE VALUE

add_config_value() (
    config_file=$1
    config_key=$2
    config_value=$3

    if [ "$#" -ne 3 ] || [ -z "$config_file" ] || [ -z "$config_key" ]; then
        echo "Usage: add_config_value CONFIG_FILE DIRECTIVE VALUE" >&2
        exit 2
    fi

    if ! sudo test -f "$config_file"; then
        echo "Error: configuration file does not exist: $config_file" >&2
        exit 1
    fi

    # Treat the directive and value as separate fields.
    # Ignore commented lines when checking for an existing entry.
    if sudo awk -v key="$config_key" -v value="$config_value" '
        /^[[:space:]]*#/ { next }
        $1 == key {
            $1 = ""
            sub(/^[[:space:]]+/, "")
            if ($0 == value) found = 1
        }
        END { exit !found }
    ' "$config_file"; then
        echo "Already present: $config_key $config_value"
        exit 0
    fi

    if ! printf '%s %s\n' "$config_key" "$config_value" |
        sudo tee -a "$config_file" >/dev/null; then
        echo "Error: could not append to $config_file" >&2
        exit 1
    fi

    echo "Added: $config_key $config_value"
)




#########################################################
# Configuration:
#########################################################


# # Disable the background update service to prevent 'locked database' errors during first run
# sudo systemctl stop clamav-freshclam.service
# # Also stop scan service
# sudo systemctl stop clamd@scan.service


# Stop services only if they exist and are currently active.
# This avoids aborting on a fresh installation where a service
# may not yet be installed or started.
for service in clamav-freshclam.service clamd@scan.service; do
    if systemctl cat "$service" >/dev/null 2>&1; then
        if systemctl is-active --quiet "$service"; then
            sudo systemctl stop "$service"
        fi
    fi
done

# Note:
# The following and all similar config changes work when the configuration contains the commented line: #LogTime ...
# sudo sed -i 's|^#LogTime.*|LogTime yes|' "$FRESH_CONF"
# On subsequent runs, the expression no longer matches. The same issue affects settings such as User, MaxThreads, LocalSocket, and PidFile.
# Also, about appending several settings using tee -a - Every execution can add another copy. Example:
# echo "VirusEvent /usr/local/bin/clamav-notify.sh" | sudo tee -a "$SCAN_CONF"
# Repeated executions can accumulate duplicate directives.
# Better approach to all these problems is using set_config_value()
# Instead of:
# sudo sed -i "s|^#MaxThreads.*|MaxThreads $RECOMMENDED_THREADS|" "$SCAN_CONF"
# Use:
# set_config_value "$SCAN_CONF" MaxThreads "$RECOMMENDED_THREADS"
# can use the same function for ordinary single-line settings:
# set_config_value "$SCAN_CONF" LogTime yes
# set_config_value "$SCAN_CONF" LogRotate yes
# set_config_value "$SCAN_CONF" User "$CLAM_USER"
# set_config_value "$SCAN_CONF" LocalSocket "$CLAMD_SOCK"
# set_config_value "$FRESH_CONF" LogTime yes
# set_config_value "$FRESH_CONF" LogRotate yes
# set_config_value "$FRESH_CONF" DatabaseOwner "$CLAM_USER"






# freshclam config:

sudo sed -i '/^Example/d' "$FRESH_CONF"

# sudo sed -i 's|^#LogTime.*|LogTime yes|' "$FRESH_CONF"
# sudo sed -i 's|^#LogFileMaxSize.*|LogFileMaxSize 20M|' "$FRESH_CONF"
# sudo sed -i 's|^#LogRotate.*|LogRotate yes|' "$FRESH_CONF"
# sudo sed -i "s|^#UpdateLogFile.*|UpdateLogFile $FRESH_LOG|" "$FRESH_CONF"
# # sudo sed -i "s|^#DatabaseOwner.*|DatabaseOwner $UPDATE_USER|" "$FRESH_CONF"
# sudo sed -i "s|^#DatabaseOwner.*|DatabaseOwner $CLAM_USER|" "$FRESH_CONF"
# sudo sed -i "s|^#NotifyClamd.*|NotifyClamd $SCAN_CONF|" "$FRESH_CONF"
# sudo sed -i 's|^#Checks.*|Checks 12|' "$FRESH_CONF"
# # DatabaseMirror database.clamav.net

set_config_value "$FRESH_CONF" LogTime yes
set_config_value "$FRESH_CONF" LogFileMaxSize 20M
set_config_value "$FRESH_CONF" LogRotate yes
set_config_value "$FRESH_CONF" LogSyslog yes # sends logs to journald, which has its own retention.
set_config_value "$FRESH_CONF" UpdateLogFile "$FRESH_LOG"
set_config_value "$FRESH_CONF" DatabaseOwner "$CLAM_USER"
set_config_value "$FRESH_CONF" NotifyClamd "$SCAN_CONF"
set_config_value "$FRESH_CONF" Checks 12
# set_config_value "$FRESH_CONF" SafeBrowsing yes
set_config_value "$FRESH_CONF" Bytecode yes
set_config_value "$FRESH_CONF" DNSDatabaseInfo yes


# Configuring clamav-unofficial-sigs

# UNOFFICIAL_SIGS_MASTER_CONF
# sudo sed -i 's|^user_configuration_complete=.*|user_configuration_complete="yes"|' "$UNOFFICIAL_SIGS_MASTER_CONF"
# sudo sed -i "s|^#clam_user=.*|clam_user=\"$CLAM_USER\"|" "$UNOFFICIAL_SIGS_MASTER_CONF"
# sudo sed -i "s|^#clam_group=.*|clam_group=\"$CLAM_USER\"|" "$UNOFFICIAL_SIGS_MASTER_CONF"

# Use set_config_value instead of directly setting using sed
set_config_value "$UNOFFICIAL_SIGS_MASTER_CONF" user_configuration_complete yes
set_config_value "$UNOFFICIAL_SIGS_MASTER_CONF" clam_user "$CLAM_USER"
set_config_value "$UNOFFICIAL_SIGS_MASTER_CONF" clam_group "$CLAM_USER"


# Enable only trusted free sources
# sudo sed -i 's|^#enable_.*sanesecurity.*|enable_sanesecurity="yes"|' $UNOFFICIAL_SIGS_MASTER_CONF

# UNOFFICIAL_SIGS_OS_CONF
# sudo sed -i "s|^clam_user=.*|clam_user=\"$CLAM_USER\"|" "$UNOFFICIAL_SIGS_OS_CONF"
# sudo sed -i "s|^clam_group=.*|clam_group=\"$CLAM_USER\"|" "$UNOFFICIAL_SIGS_OS_CONF"
# sudo sed -i "s|^clam_dbs=.*|clam_dbs=\"$SIG_DB_DIR\"|" "$UNOFFICIAL_SIGS_OS_CONF"
# sudo sed -i "s|^clamd_pid=.*|clamd_pid=\"$CLAMD_PID\"|" "$UNOFFICIAL_SIGS_OS_CONF"
# sudo sed -i "s|^#clamd_socket=.*|clamd_socket=\"$CLAMD_SOCK\"|" "$UNOFFICIAL_SIGS_OS_CONF"
# sudo sed -i "s|^clamd_reload_opt=.*|clamd_reload_opt=\"clamdscan --config-file=$SCAN_CONF --reload\"|" "$UNOFFICIAL_SIGS_OS_CONF"
# sudo sed -i "s|^reload_dbs=.*|reload_dbs=\"yes\"|" "$UNOFFICIAL_SIGS_OS_CONF"


set_config_value "$UNOFFICIAL_SIGS_OS_CONF" clam_user "$CLAM_USER"
set_config_value "$UNOFFICIAL_SIGS_OS_CONF" clam_group "$CLAM_USER"
set_config_value "$UNOFFICIAL_SIGS_OS_CONF" clam_dbs "$SIG_DB_DIR"
set_config_value "$UNOFFICIAL_SIGS_OS_CONF" clamd_pid "$CLAMD_PID"
set_config_value "$UNOFFICIAL_SIGS_OS_CONF" clamd_socket "$CLAMD_SOCK"
set_config_value "$UNOFFICIAL_SIGS_OS_CONF" clamd_reload_opt "clamdscan --config-file=$SCAN_CONF --reload"
set_config_value "$UNOFFICIAL_SIGS_OS_CONF" reload_dbs yes


# Daemon (clamd) Config:

sudo sed -i '/^Example/d' "$SCAN_CONF"

# set_config_value / add_config_value only add or replace; they never delete directives that
# older runs or hand edits left behind. Remove the ones this script no longer wants:
sudo sed -i -E '/^(ScanOnAccess|OnAccessExcludePath|OnAccessMountPath)[[:space:]]/d' "$SCAN_CONF"

# sudo sed -i "s|^#LogFile.*|LogFile $CLAMD_LOG|" "$SCAN_CONF"
# sudo sed -i 's|^#LogTime.*|LogTime yes|' "$SCAN_CONF"
# sudo sed -i 's|^#LogRotate.*|LogRotate yes|' "$SCAN_CONF"
# sudo sed -i "s|^#PidFile.*|PidFile $CLAMD_PID|" "$SCAN_CONF"

# sudo sed -i 's|^#FixStaleSocket.*|FixStaleSocket yes|' "$SCAN_CONF"
# sudo sed -i "s|^#User.*|User $CLAM_USER|" "$SCAN_CONF"
# sudo sed -i 's|^#DetectPUA.*|DetectPUA yes|' "$SCAN_CONF"
# # sudo sed -i 's|^#MaxThreads.*|MaxThreads 4|' "$SCAN_CONF"
# # Thread tuning based on CPU cores
# sudo sed -i "s|^#MaxThreads.*|MaxThreads $RECOMMENDED_THREADS|" "$SCAN_CONF"
# sudo sed -i 's|^#ReadTimeout.*|ReadTimeout 180|' "$SCAN_CONF"

set_config_value "$SCAN_CONF" LogFile "$CLAMD_LOG"
set_config_value "$SCAN_CONF" LogTime yes
set_config_value "$SCAN_CONF" LogFileMaxSize 10M    # ClamAV renames the full log to clamd-<timestamp>.log
set_config_value "$SCAN_CONF" LogRotate yes
set_config_value "$SCAN_CONF" LogSyslog yes    # sends logs to journald, which has its own retention.
set_config_value "$SCAN_CONF" PidFile "$CLAMD_PID"
set_config_value "$SCAN_CONF" FixStaleSocket yes
set_config_value "$SCAN_CONF" User "$CLAM_USER"
set_config_value "$SCAN_CONF" DetectPUA yes
set_config_value "$SCAN_CONF" MaxThreads "$RECOMMENDED_THREADS"
set_config_value "$SCAN_CONF" ReadTimeout 180



# sudo sed -i "s|^#LocalSocket.*|LocalSocket $CLAMD_SOCK|" "$SCAN_CONF"

# # Configure exactly one active Unix socket directive.
# sudo sed -i '/^[[:space:]]*LocalSocket[[:space:]]/d' "$SCAN_CONF"
# sudo sed -i "s|^#LocalSocket.*|LocalSocket $CLAMD_SOCK|" "$SCAN_CONF"

# Configure exactly one active Unix socket directive.
set_config_value "$SCAN_CONF" LocalSocket "$CLAMD_SOCK"


# # Restrict socket access to the ClamAV service account.
# sudo sed -i '/^[[:space:]]*#LocalSocketMode[[:space:]]/d' "$SCAN_CONF"
# sudo sed -i '/^[[:space:]]*LocalSocketMode[[:space:]]/d' "$SCAN_CONF"
# echo "LocalSocketMode 600" | sudo tee -a "$SCAN_CONF" >/dev/null

# Restrict socket access to its owner only.
# set_config_value "$SCAN_CONF" LocalSocketMode 600

# LocalSocketMode 600 allows only the socket owner (clamscan, in your setup) to access the socket. If you run clamdscan as your normal desktop user, it may no longer be able to connect.
# If you need regular-user access, use a group-based arrangement instead, like:
set_config_value "$SCAN_CONF" LocalSocketGroup clamscan
# set_config_value "$SCAN_CONF" LocalSocketMode 660
# sudo usermod -aG clamscan "$REAL_USER"

# the socket is root-only, so a compromised user session can't stop clamd.
set_config_value "$SCAN_CONF" LocalSocketMode 600
sudo sed -i '/^LocalSocketGroup/d' "$SCAN_CONF"    # TODO - What does this do?
sudo gpasswd -d "$REAL_USER" clamscan 2>/dev/null || true    # undo earlier membership





# Trigger notification script on any real-time detection
# echo "VirusEvent /usr/local/bin/clamav-notify.sh" | sudo tee -a "$SCAN_CONF"

set_config_value "$SCAN_CONF" VirusEvent /usr/local/bin/clamav-notify.sh

# # TemporaryDirectory /dev/shm (RAM Optimization) - Use RAM disk for temporary scanning files if sufficient memory is available. Forces ClamAV to extract and inspect archives entirely inside your system's RAM (tmpfs).
# # RAM-based temp directory (Independent of disk type, check RAM instead)
# if [ "$RAM_GB" -ge 14 ]; then

#     echo "[*] Sufficient RAM ($RAM_GB GB) detected: routing ClamAV temp files to RAM (/dev/shm)..."
#     # sudo sed -i 's|^#TemporaryDirectory.*|TemporaryDirectory /dev/shm|' "$SCAN_CONF"
#     set_config_value "$SCAN_CONF" TemporaryDirectory /dev/shm

# fi

sudo sed -i '/^TemporaryDirectory/d' "$SCAN_CONF"   # clears machines already configured; /tmp is tmpfs on Fedora


# # ConcurrentDatabaseReload yes (Storage Optimization) - Allows clamd to load updated virus definitions in the background using a secondary thread pool while continuing to handle scan requests uninterrupted.
# # Why it relates to SSDs: Database files are large and frequently updated by freshclam. Reloading them concurrently causes heavy concurrent disk I/O. While it works on HDDs, it performs significantly better on fast storage (SSDs or NVMe drives) without causing I/O bottlenecks.
# # SSD-specific optimizations
# if $SSD_PRESENT; then
#     echo "SSD detected: enabling concurrent database reloads..."
#     # sudo sed -i 's|^#ConcurrentDatabaseReload.*|ConcurrentDatabaseReload yes|' "$SCAN_CONF"

#     set_config_value "$SCAN_CONF" ConcurrentDatabaseReload yes
# fi

# LogFileMaxSize 20M
# ExitOnOOM yes # Not sure if this is a good thing to do

# # Log Detailed Threat Information:
# ExtendedDetectionInfo yes

set_config_value "$SCAN_CONF" OnAccessMaxThreads "$ONACC_THREADS"
set_config_value "$SCAN_CONF" OnAccessMaxFileSize 25M    # default 5M: bigger files are never on-access scanned
set_config_value "$SCAN_CONF" ConcurrentDatabaseReload "$CONC_RELOAD"
set_config_value "$SCAN_CONF" ExtendedDetectionInfo yes  # logs size + hash with each detection

# ExitOnOOM makes clamd exit cleanly on an out-of-memory condition and lets systemd restart it. The cost is a full signature reload.
set_config_value "$SCAN_CONF" ExitOnOOM yes             




# FixStaleSocket yes - explaination - If the system crashes or services are abruptly restarted, a stale clamd.sock can linger in /run/clamd.scan/, causing the daemon to refuse startup on subsequent boots. While you have FixStaleSocket yes commented out or handled via runtime directory recreation, enforcing it explicitly in the config ensures bulletproof recovery.



# Excluded dirs
# cat <<EOF | sudo tee -a "$SCAN_CONF"
# ExcludePath /etc/hosts
# # Add trusted browser extensions (regex including profiles, etc)
# EOF

#  Exclude specific paths from scanning
# add_config_value "$SCAN_CONF" ExcludePath /etc/hosts
# add_config_value "$SCAN_CONF" ExcludePath /path/to/another/file
# add_config_value "$SCAN_CONF" ExcludePath /path/to/cache

# ExcludePath takes regexes, and it is honored even for fd-passed scans. Avoid backslashes, because awk -v mangles them and your dedupe would break:
# Excluding /var/lib/clamav/ matters because signature files can match each other.
for p in '^/proc/' '^/sys/' '^/dev/' '^/run/' '^/var/quarantine/' '^/var/lib/clamav/' \
         '^/var/log/clamav/' '^/var/lib/docker/' '^/var/lib/containers/' \
         '^/home/[^/]+/[.]local/share/containers/'; do
    add_config_value "$SCAN_CONF" ExcludePath "$p"
done


# Content Scanning Options
# sudo sed -i 's|^#ScanPE.*|ScanPE yes|' "$SCAN_CONF"
# sudo sed -i 's|^#ScanELF.*|ScanELF yes|' "$SCAN_CONF"
# sudo sed -i 's|^#ScanOLE2.*|ScanOLE2 yes|' "$SCAN_CONF"
# sudo sed -i 's|^#ScanPDF.*|ScanPDF yes|' "$SCAN_CONF"
# sudo sed -i 's|^#AlertBrokenExecutables.*|AlertBrokenExecutables yes|' "$SCAN_CONF"


set_config_value "$SCAN_CONF" ScanPE yes
set_config_value "$SCAN_CONF" ScanELF yes
set_config_value "$SCAN_CONF" ScanOLE2 yes
set_config_value "$SCAN_CONF" ScanPDF yes
set_config_value "$SCAN_CONF" AlertBrokenExecutables yes




# Enable Comprehensive File Scanning for file types commonly downloaded
# ScanHTML yes
# ScanArchive yes
# AlertEncrypted yes

# # Phishing and DLP Settings:
# PhishingSignatures yes
# PhishingAlwaysBlockSSLMismatch yes
# PhishingAlwaysBlockCloak yes

# MinCreditCardCount 1
# SSNFormat yes
# MinSSNCount 1


# Enable heuristic detection in clamd.conf:
# HeuristicScanPrecedence yes
# StructuredDataDetection yes









#########################################################
# Some notes about additional signatures
#########################################################

# Adding third-party signature URLs - TODO: These are broken/non-free. Replace them with more free and reputed sources.
# echo "DatabaseCustomURL http://www.malware.expert/clamav/main.cvd" | sudo tee -a "$FRESH_CONF"
# echo "DatabaseCustomURL https://www.securiteinfo.com/get/clamav-unofficial/securiteinfo.hdb" | sudo tee -a "$FRESH_CONF"
# DatabaseCustomURL http://www.malware.expert/clamav/
# DatabaseCustomURL https://www.securiteinfo.com/get/clamav-unofficial/
# SecuriteInfo - Register at SecuriteInfo to obtain an authorization code.
# For clamav-unofficial-sigs, edit /etc/clamav-unofficial-sigs/master.conf:
# securiteinfo_dbs_rating="HIGH"
# securiteinfo_authorisation_code="YOUR-AUTH-CODE"


# MalwarePatrol - https://github.com/malwarepatrol/clamav-signatures - Broad coverage of newer ransomware & trojans.
# Edit /etc/clamav-unofficial-sigs/user.conf with MalwarePatrol credentials if using their paid service.
# Sign up for a free account at MalwarePatrol to obtain a receipt code. (is it privacy friendly?)

# YARA Rules (via YaraRulesProject or Custom Rules)
# Edit /etc/clamav-unofficial-sigs/master.conf
# yararulesproject_enabled="yes"
# work_dir_yararules="/var/lib/clamav"

# Enable SaneSecurity, MalwarePatrol, Securiteinfo, Yara-Rules Project, and more
# options include HIGH, MEDIUM, LOW, or DISABLED
# sanesecurity_dbs_rating="HIGH" 


# Ransomware‑Tracker - https://github.com/ytisf/ransomware-sig - Focused on ransomware hashes and filenames.

# ESET‑NOD32‑Signatures - (not officially supported) - Adds a different vendor’s perspective on threats.

# Sigs are usually .cvd or plain text .hdb/.mdb - Place them in /var/lib/clamav/ (or wherever your DatabaseDirectory points)

# ClamAV‑Bytecode‑Repo - (https://github.com/Cisco-Talos/clamav-bytecode) - additional experimental Bytecode modules.
# Enable in clamd.conf - Bytecode = Yes
# place the .cbc files in the bytecode directory (default: /var/lib/clamav/bytecode/


#########################################################
# On-Access Scanning (ClamOnAcc)
#########################################################

# # Configure Real-time protection for Downloads and Browser Caches
# cat <<EOF | sudo tee -a "$SCAN_CONF"

# # On-Access Scanning (ClamOnAcc) Flags
# # ScanOnAccess yes # deprecated option
# OnAccessPrevention yes
# # OnAccessDisableDDD yes

# # On-Access Scanning (ClamOnAcc) Inclusions
# # OnAccessIncludePath /home/$(whoami)/Downloads
# # OnAccessIncludePath /home/$(whoami)/.cache/thunderbird
# # OnAccessIncludePath /home/$(whoami)/.cache/torbrowser
# # OnAccessIncludePath /home/$(whoami)/.cache/librewolf
# # OnAccessIncludePath /home/$(whoami)/.cache/BraveSoftware
# # OnAccessIncludePath /home/$(whoami)/.cache/google-chrome
# # OnAccessIncludePath /home/$(whoami)/.cache/akregator
# # OnAccessIncludePath /home/$(whoami)/.cache/qBittorrent
# # OnAccessIncludePath /home/$(whoami)/.cache/mozilla
# # OnAccessIncludePath /home/$(whoami)/nb/Torrents
# # OnAccessIncludePath /home/$(whoami)/nb/nb_script_downloads
# # OnAccessIncludePath /home/$(whoami)/nb/Downloads
# # OnAccessIncludePath /home/$(whoami)/Downloads
# # OnAccessIncludePath /home/$(whoami)/.thunderbird/
# # OnAccessIncludePath /home/$(whoami)/.mullvad-browser/
# # OnAccessIncludePath /home/$(whoami)/.mozilla/
# # OnAccessIncludePath /home/$(whoami)/.kodi/

# OnAccessIncludePath "${HOME_DIR}"/Downloads
# OnAccessIncludePath "${HOME_DIR}"/.cache/thunderbird
# OnAccessIncludePath "${HOME_DIR}"/.cache/torbrowser
# OnAccessIncludePath "${HOME_DIR}"/.cache/librewolf
# OnAccessIncludePath "${HOME_DIR}"/.cache/BraveSoftware
# OnAccessIncludePath "${HOME_DIR}"/.cache/google-chrome
# OnAccessIncludePath "${HOME_DIR}"/.cache/akregator
# OnAccessIncludePath "${HOME_DIR}"/.cache/qBittorrent
# OnAccessIncludePath "${HOME_DIR}"/.cache/mozilla
# OnAccessIncludePath "${HOME_DIR}"/nb/Torrents
# OnAccessIncludePath "${HOME_DIR}"/nb/nb_script_downloads
# OnAccessIncludePath "${HOME_DIR}"/nb/Downloads
# OnAccessIncludePath "${HOME_DIR}"/.cache/
# OnAccessIncludePath "${HOME_DIR}"/.thunderbird/
# OnAccessIncludePath "${HOME_DIR}"/.mullvad-browser/
# OnAccessIncludePath "${HOME_DIR}"/.mozilla/
# OnAccessIncludePath "${HOME_DIR}"/.kodi/

# # On-Access Scanning (ClamOnAcc) Exclusions
# OnAccessExcludeUname $CLAM_USER

# EOF



# set_config_value "$SCAN_CONF" ScanOnAccess yes  # deprecated option? # On-access monitoring is managed by clamonacc, not ScanOnAccess.
# set_config_value "$SCAN_CONF" OnAccessPrevention yes
set_config_value "$SCAN_CONF" OnAccessPrevention "$ONACC_PREVENT"
# set_config_value "$SCAN_CONF" OnAccessDisableDDD yes

# On-Access Scanning (ClamOnAcc) Exclusions
# Exclude the ClamAV daemon's own user from on-access scanning.
add_config_value "$SCAN_CONF" OnAccessExcludeUname $CLAM_USER

# Paths to include in On-Access scanning
# add_config_value "$SCAN_CONF" OnAccessIncludePath /home/youruser
# add_config_value "$SCAN_CONF" OnAccessIncludePath /srv/shared
# add_config_value "$SCAN_CONF" OnAccessIncludePath /opt/myapp

# Monitor the primary user's download directory.
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/Downloads
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/nb/Downloads

# Monitor a dedicated directory for downloaded scripts and files.
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/nb/nb_script_downloads

# Scan Torrent downloads
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/nb/Torrents


# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/.thunderbird/
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/.mullvad-browser/
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/.mozilla/
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/.kodi/

# Everything under .cache
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/.cache/

# Individual dirs under .cache
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/.cache/thunderbird
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/.cache/torbrowser
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/.cache/librewolf
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/.cache/BraveSoftware
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/.cache/google-chrome
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/.cache/akregator
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/.cache/qBittorrent
# add_config_value "$SCAN_CONF" OnAccessIncludePath "${HOME_DIR}"/.cache/mozilla


##########

# Old entries persist because add_config_value only appends. Reset, then rebuild.
sudo sed -i '/^OnAccessIncludePath/d' "$SCAN_CONF"

# Watch where payloads LAND, not profile or cache dirs.
# Initialize base directories common to all client setups
# NEVER use OnAccessExcludePath on a directory that has subfolders: clamonacc logs
# "ERROR: ClamInotif: can't exclude ..." and silently stops blocking the WHOLE watch.
ONACC_DIRS=(
    "$HOME_DIR/Downloads"
    "$NBDIR/Downloads"
    "$NBDIR/Torrents/Completed"
    "$NBDIR/nb_script_downloads"
    "$NBDIR/Syncthing/"   # Syncthing folders that receive files from other devices
    "$HOME_DIR/.kodi/"   # Because it uses random repos
)

# Basically, the following skips the onaccess path inclusions for servers
if [ "$ROLE" = desktop ]; then
    for d in "${ONACC_DIRS[@]}"; do
        if [ -d "$d" ]; then add_config_value "$SCAN_CONF" OnAccessIncludePath "$d"; fi
    done
fi




#########################################################
# Smart USB / External Drive Scanning
#########################################################

# To differentiate a small USB thumb drive from a massive external HDD, the helper script can inspect the mounted filesystem's total capacity. For example, setting a threshold at 256 GB ensures pen drives are scanned while multi-terabyte backup drives are safely skipped.

# To differentiate a small USB thumb drive from a massive external HDD, the helper script checks mounted filesystem capacity. The default threshold is 256 GiB; larger external HDDs are skipped.

echo "Configuring smart USB drive scanner"

# sudo tee /usr/local/bin/clamav-usb-scan.sh > /dev/null <<'EOF'
# #!/bin/bash

# # # Inside clamav-usb-scan.sh, if you pass the full path or wildcard:
# # DEVICE_PATH="$1"

# # if [ -z "$DEVICE_PATH" ] || [ ! -d "$DEVICE_PATH" ]; then
# #     exit 0
# # fi

# # # If /run/media/*/$1 is passed, resolve it:
# # if [ ! -d "$DEVICE_PATH" ]; then
# #     DEVICE_PATH=$(find /run/media -maxdepth 2 -name "$1" -print -quit)
# # fi

# DEVICE_PATH="${1:-}"

# # Resolve a device label or directory name if a full path was not supplied.
# if [ -n "$DEVICE_PATH" ] && [ ! -d "$DEVICE_PATH" ]; then
#     DEVICE_PATH=$(find /run/media -maxdepth 3 \
#         -type d -name "$1" -print -quit 2>/dev/null)
# fi

# # Exit if no mounted directory could be resolved.
# if [ -z "$DEVICE_PATH" ] || [ ! -d "$DEVICE_PATH" ]; then
#     echo "No valid mounted USB directory found." >&2
#     exit 1
# fi

# # Resolve symbolic links and verify that the path exists.
# DEVICE_PATH=$(realpath -e -- "$DEVICE_PATH") || {
#     echo "Cannot resolve USB mount path." >&2
#     exit 1
# }

# # Refuse to scan a path that is not a mount point.
# mountpoint -q -- "$DEVICE_PATH" || {
#     echo "Path is not a mount point: $DEVICE_PATH" >&2
#     exit 1
# }

# SIZE_THRESHOLD_GB=256

# # Dynamically find the active graphical user session for notifications
# # ACTIVE_USER=$(loginctl list-users --no-legend | awk '{print $2}' | head -n 1)

# # Find the first active graphical desktop user (UID >= 1000)
# # ACTIVE_USER=$(loginctl list-sessions --no-legend | awk '{print $2}' | while read -r user; do id -u "$user" &>/dev/null && [ "$(id -u "$user")" -ge 1000 ] && echo "$user" && break; done)

# # Use awk '{print $3}' instead of $2 - gives user rather than uid
# # ACTIVE_USER=$(loginctl list-sessions --no-legend |
# #     awk '{print $3}' |
# #     while read -r user; do
# #         id -u "$user" &>/dev/null &&
# #         [ "$(id -u "$user")" -ge 1000 ] &&
# #         echo "$user" &&
# #         break
# #     done)

# ACTIVE_USER=$(
#     loginctl list-sessions --no-legend |
#         awk '{print $3}' |
#         while read -r user; do
#             [[ -n "$user" ]] || continue

#             user_uid=$(id -u "$user" 2>/dev/null) || continue

#             if (( user_uid >= 1000 && user_uid < 65534 )); then
#                 printf '%s\n' "$user"
#                 break
#             fi
#         done
# )

# # Fallback if no active session is found
# if [ -z "$ACTIVE_USER" ]; then
#     ACTIVE_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd | head -n 1)
# fi

# # Check storage capacity in GB to skip large external backup HDDs (> SIZE_THRESHOLD_GB GB)
# DEV_SIZE_KB=$(df "$DEVICE_PATH" 2>/dev/null | tail -1 | awk '{print $2}')
# if [ -z "$DEV_SIZE_KB" ]; then
#     exit 0
# fi
# DEV_SIZE_GB=$(( DEV_SIZE_KB / 1024 / 1024 ))

# if [ "$DEV_SIZE_GB" -gt "$SIZE_THRESHOLD_GB" ]; then
#     echo "Skipping device at $DEVICE_PATH: Size (${DEV_SIZE_GB} GB) exceeds USB thumb drive threshold ($SIZE_THRESHOLD_GB GB)."
#     exit 0
# fi
# LOG_DIR="/var/log/clamav"
# # LOGFILE="${LOG_DIR}/usb_scan_$(date +\%Y-\%m-\%d).log"
# LOGFILE="${LOG_DIR}/usb_scan_$(date +%Y-%m-%d).log"

# echo "Scanning USB drive at $DEVICE_PATH (${DEV_SIZE_GB} GB)..."

# # nice -n 19 clamdscan -r "$DEVICE_PATH" --infected --log="$LOGFILE"

# # nice -n 19 ionice -c 3 clamdscan -r "$DEVICE_PATH" --infected --log="$LOGFILE"

# # Capture the scanner's exit status without treating detections as
# # equivalent to scanner errors.
# SCAN_STATUS=0

# nice -n 19 ionice -c 3 clamdscan -r "$DEVICE_PATH" --infected --log="$LOGFILE" 

# SCAN_STATUS=$?

# # case "$SCAN_STATUS" in
# #     0)
# #         echo "USB scan completed: no infections reported."
# #         ;;
# #     1)
# #         echo "WARNING: USB scan detected an infection. See $LOGFILE"
# #         ;;
# #     *)
# #         echo "ERROR: USB scan failed with status $SCAN_STATUS." >&2
# #         ;;
# # esac

# # if grep -q "Infected files: [1-9]" "$LOGFILE"; then
# #     sudo -u "$SUDO_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$SUDO_USER")/bus \
# #         notify-send "⚠ ClamAV USB Alert" "Infected files found on USB drive! Check $LOGFILE" -i dialog-warning
# # fi

# # if grep -q "Infected files: [1-9]" "$LOGFILE"; then
# #     if [ -n "$ACTIVE_USER" ]; then
# #         USER_UID=$(id -u "$ACTIVE_USER")
# #         sudo -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$USER_UID/bus \
# #             notify-send "⚠ ClamAV USB Alert" "Infected files found on USB drive! Check $LOGFILE" -i dialog-warning
# #     fi
# # fi

# NOTIFICATION_TITLE=""
# NOTIFICATION_MESSAGE=""
# NOTIFICATION_ICON=""

# # Determine the scan result using both the log and exit status.
# if grep -qE 'Infected files: [1-9][0-9]*' "$LOGFILE" || [ "$SCAN_STATUS" -eq 1 ]; then

#     NOTIFICATION_TITLE="⚠ ClamAV USB Alert"
#     NOTIFICATION_MESSAGE="Infection detected on USB drive: $DEVICE_PATH. Exit status: $SCAN_STATUS. Check $LOGFILE"
#     NOTIFICATION_ICON="dialog-warning"
#     logger -t clamav-alert "$NOTIFICATION_MESSAGE"

# elif [ "$SCAN_STATUS" -eq 0 ]; then

#     NOTIFICATION_TITLE="ClamAV USB Scan Complete"
#     NOTIFICATION_MESSAGE="No infections found on USB drive: $DEVICE_PATH. Check $LOGFILE"
#     NOTIFICATION_ICON="dialog-information"
#     logger -t clamav-scan "$NOTIFICATION_MESSAGE"

# else

#     NOTIFICATION_TITLE="⚠ ClamAV USB Scan Error"
#     NOTIFICATION_MESSAGE="USB scan failed or was incomplete. Drive: $DEVICE_PATH. Exit status: $SCAN_STATUS. Check $LOGFILE"
#     NOTIFICATION_ICON="dialog-error"
#     logger -t clamav-scan "$NOTIFICATION_MESSAGE"

# fi


# # Notify the active desktop user, if available.
# if [ -n "$ACTIVE_USER" ]; then
#     USER_UID=$(id -u "$ACTIVE_USER")

#     sudo -u "$ACTIVE_USER" \
#         DISPLAY=:0 \
#         DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_UID/bus" \
#         notify-send -u normal -i "$NOTIFICATION_ICON" \
#         "$NOTIFICATION_TITLE" "$NOTIFICATION_MESSAGE"
# fi
# EOF


sudo tee /usr/local/bin/clamav-usb-scan.sh > /dev/null <<'EOF'
#!/usr/bin/bash
set -u -o pipefail

LOG_DIR="/var/log/clamav"
SIZE_THRESHOLD_GIB=256
WAIT_INTERVAL_SECONDS=2

log() {
    logger -t clamav-usb-scan -- "$*"
    printf '%s\n' "$*"
}

find_active_graphical_user() {
    local session_id _session_uid _session_user _rest session_info
    local session_name session_active session_remote session_type session_class

    while read -r session_id _session_uid _session_user _rest; do
        [[ -n "$session_id" ]] || continue
        session_info=$(loginctl show-session "$session_id" \
            -p Name -p Active -p Remote -p Type -p Class --no-pager 2>/dev/null) || continue

        session_name=$(sed -n 's/^Name=//p' <<< "$session_info")
        session_active=$(sed -n 's/^Active=//p' <<< "$session_info")
        session_remote=$(sed -n 's/^Remote=//p' <<< "$session_info")
        session_type=$(sed -n 's/^Type=//p' <<< "$session_info")
        session_class=$(sed -n 's/^Class=//p' <<< "$session_info")

        if [[ "$session_active" == yes && "$session_remote" == no &&
              "$session_class" == user &&
              ( "$session_type" == wayland || "$session_type" == x11 ) &&
              -n "$session_name" ]]; then
            printf '%s\n' "$session_name"
            return 0
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null)

    return 1
}

notify_desktop_user() {
    local title=$1 message=$2 icon=$3 urgency=$4 active_user user_uid runtime_dir

    active_user=$(find_active_graphical_user) || active_user=""
    [[ -n "$active_user" ]] || {
        log "No active local graphical session; notification was not displayed: $title"
        return 0
    }

    user_uid=$(id -u -- "$active_user") || return 0
    runtime_dir="/run/user/$user_uid"
    [[ -S "$runtime_dir/bus" ]] || {
        log "No session D-Bus socket for $active_user; notification was not displayed."
        return 0
    }

    if ! runuser -u "$active_user" -- /usr/bin/env \
        XDG_RUNTIME_DIR="$runtime_dir" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
        /usr/bin/notify-send -u "$urgency" -i "$icon" -- "$title" "$message"; then
        log "Failed to send desktop notification to $active_user: $title"
    fi
}

find_mountpoint_for_device() {
    local wanted_device_id line mount_id parent_id device_id mount_root mount_target mount_options rest

    wanted_device_id=$(lsblk -dnro MAJ:MIN -- "$DEVICE_NODE" 2>/dev/null) || return 1
    [[ -n "$wanted_device_id" ]] || return 1

    # Prefer findmnt source matching; this also handles filesystems mounted via
    # FUSE, where mountinfo's major:minor may be the FUSE device, not the USB.
    mount_target=$(findmnt --raw --noheadings --source "$DEVICE_NODE" \
        --output TARGET 2>/dev/null | head -n 1) || mount_target=""
    if [[ -n "$mount_target" ]]; then
        mount_target=${mount_target//\\x20/$' '}
        mount_target=${mount_target//\\x09/$'\t'}
        mount_target=${mount_target//\\x0a/$'\n'}
        mount_target=${mount_target//\\x5c/$'\\'}
        printf '%s\n' "$mount_target"
        return 0
    fi

    # Fallback: /proc/self/mountinfo escapes spaces, tabs, newlines, and
    # backslashes. Match by major:minor rather than guessing /run/media paths.
    while IFS= read -r line; do
        read -r mount_id parent_id device_id mount_root mount_target mount_options rest <<< "$line"
        [[ "$device_id" == "$wanted_device_id" ]] || continue

        mount_target=${mount_target//\\040/$' '}
        mount_target=${mount_target//\\011/$'\t'}
        mount_target=${mount_target//\\012/$'\n'}
        mount_target=${mount_target//\\134/$'\\'}
        printf '%s\n' "$mount_target"
        return 0
    done < /proc/self/mountinfo

    return 1
}

if [[ $# -ne 1 ]]; then
    log "Usage: $0 /dev/<USB-partition-or-unpartitioned-device>"
    exit 2
fi

DEVICE_NODE=$1
# For automatic scanning, %I in the systemd unit is a kernel block-device name.
# Reject paths outside /dev and malformed device names before querying block tools.
if [[ ! "$DEVICE_NODE" =~ ^/dev/[[:alnum:]_-]+$ ]]; then
    log "Refusing invalid block-device path: $DEVICE_NODE"
    exit 2
fi

if [[ ! -b "$DEVICE_NODE" ]]; then
    log "Block device is not present: $DEVICE_NODE"
    exit 1
fi

DEVICE_NAME=${DEVICE_NODE##*/}
if [[ ! -e "/sys/class/block/$DEVICE_NAME" ]]; then
    log "No matching sysfs block device: $DEVICE_NODE"
    exit 1
fi

log "Waiting for $DEVICE_NODE to be mounted; this wait ends when the volume is mounted or disconnected."
DEVICE_MOUNT=""
while [[ -b "$DEVICE_NODE" ]]; do
    DEVICE_MOUNT=$(find_mountpoint_for_device) || DEVICE_MOUNT=""
    if [[ -n "$DEVICE_MOUNT" ]]; then
        break
    fi
    sleep "$WAIT_INTERVAL_SECONDS"
done

if [[ ! -b "$DEVICE_NODE" ]]; then
    log "Device was removed before it could be scanned: $DEVICE_NODE"
    exit 1
fi

if [[ -z "$DEVICE_MOUNT" ]]; then
    log "No mount detected for $DEVICE_NODE; not scanning an unmounted device."
    exit 1
fi

DEVICE_MOUNT=$(realpath -e -- "$DEVICE_MOUNT") || {
    log "Could not resolve mount path for $DEVICE_NODE."
    exit 1
}

mountpoint -q -- "$DEVICE_MOUNT" || {
    log "Resolved path is not a mount point: $DEVICE_MOUNT"
    exit 1
}

# Skip large external HDDs / backup drives. This threshold is in GiB.
DEV_SIZE_KIB=$(df -Pk -- "$DEVICE_MOUNT" 2>/dev/null | awk 'NR == 2 { print $2 }')
if [[ ! "$DEV_SIZE_KIB" =~ ^[0-9]+$ ]]; then
    log "Could not determine filesystem size for $DEVICE_MOUNT."
    exit 1
fi

if (( DEV_SIZE_KIB > SIZE_THRESHOLD_GIB * 1024 * 1024 )); then
    log "Skipping $DEVICE_NODE at $DEVICE_MOUNT: filesystem size exceeds ${SIZE_THRESHOLD_GIB} GiB."
    exit 0
fi

LOGFILE="${LOG_DIR}/usb_scan_$(date +%F).log"
log "Scanning $DEVICE_NODE mounted at $DEVICE_MOUNT (size <= ${SIZE_THRESHOLD_GIB} GiB). Log: $LOGFILE"

# --fdpass lets this root-run client open files that the clamscan daemon user
# cannot traverse on KDE's user-mounted /run/media paths. LocalSocket is configured.
# clamdscan exit statuses: 0 = clean, 1 = infected, 2 = scan/error condition.
SCAN_STATUS=0
if nice -n 19 ionice -c 3 /usr/bin/clamdscan --fdpass -r "$DEVICE_MOUNT" --infected --log="$LOGFILE"; then
    SCAN_STATUS=0
else
    SCAN_STATUS=$?
fi

if (( SCAN_STATUS == 1 )); then
    NOTIFICATION_TITLE="ClamAV USB Alert: Threat detected"
    NOTIFICATION_MESSAGE="A threat was detected on $DEVICE_MOUNT. Review the scan log: $LOGFILE"
    NOTIFICATION_ICON="dialog-warning"
    NOTIFICATION_URGENCY="critical"
    log "Threat detected on $DEVICE_MOUNT. Review $LOGFILE"
elif (( SCAN_STATUS == 0 )); then
    NOTIFICATION_TITLE="ClamAV USB scan complete"
    NOTIFICATION_MESSAGE="No threats reported on $DEVICE_MOUNT. Log: $LOGFILE"
    NOTIFICATION_ICON="dialog-information"
    NOTIFICATION_URGENCY="normal"
    log "USB scan completed with no detections: $DEVICE_MOUNT"
else
    NOTIFICATION_TITLE="ClamAV USB scan error"
    NOTIFICATION_MESSAGE="Scan failed or was incomplete for $DEVICE_MOUNT (exit status $SCAN_STATUS). Log: $LOGFILE"
    NOTIFICATION_ICON="dialog-error"
    NOTIFICATION_URGENCY="critical"
    log "USB scan failed with exit status $SCAN_STATUS for $DEVICE_MOUNT. Log: $LOGFILE"
fi

notify_desktop_user "$NOTIFICATION_TITLE" "$NOTIFICATION_MESSAGE" \
    "$NOTIFICATION_ICON" "$NOTIFICATION_URGENCY"

# A detection is a completed scan, not a systemd service malfunction.
# Return success for clean/infected completed scans; errors remain visible in systemd.
if (( SCAN_STATUS == 2 )); then
    exit 2
fi
exit 0
EOF

# sudo chmod +x /usr/local/bin/clamav-usb-scan.sh

sudo chown root:root /usr/local/bin/clamav-usb-scan.sh
sudo chmod 0755 /usr/local/bin/clamav-usb-scan.sh


# # Udev rule matching inserted storage partitions
# sudo tee /etc/udev/rules.d/99-clamav-usb.rules > /dev/null <<EOF

# ACTION=="add", SUBSYSTEMS=="usb", KERNEL=="sd[a-z][0-9]", RUN+="/bin/bash -c 'sleep 5 && /usr/local/bin/clamav-usb-scan.sh /run/media/*/%k'"

# EOF


# sudo udevadm control --reload


# To scan a USB drive manually, first mount it in KDE Dolphin,
# then run the following command, replacing USERNAME and VOLUME_LABEL
# with the actual directory names shown under /run/media:
#
# sudo /usr/local/bin/clamav-usb-scan.sh "/run/media/USERNAME/VOLUME_LABEL"
#
# Reliable automation should use a mount-aware systemd workflow
# that passes the actual mounted filesystem path to the scanner.



# udev must only enqueue a short systemd activation; never sleep or scan in RUN.
sudo tee /etc/udev/rules.d/99-clamav-usb.rules > /dev/null <<'EOF'
# Scan USB-attached partitions containing a filesystem.
ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_FS_USAGE}=="filesystem", SUBSYSTEMS=="usb", TAG+="systemd", ENV{SYSTEMD_WANTS}+="clamav-usb-scan@%k.service"

# Also support an unpartitioned USB device with a filesystem written directly to it.
ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{ID_FS_USAGE}=="filesystem", SUBSYSTEMS=="usb", TAG+="systemd", ENV{SYSTEMD_WANTS}+="clamav-usb-scan@%k.service"
EOF

sudo tee /etc/systemd/system/clamav-usb-scan@.service > /dev/null <<'EOF'
[Unit]
Description=ClamAV USB scan for /dev/%I
BindsTo=dev-%i.device
After=dev-%i.device

[Service]
Type=oneshot
User=root
Group=root
ExecStart=/usr/local/bin/clamav-usb-scan.sh /dev/%I
Nice=19
IOSchedulingClass=idle
TimeoutStartSec=infinity
EOF

# Manual scan: identify a mounted USB filesystem's device with lsblk, then scan it.
# Example:
#   lsblk -o NAME,TRAN,SIZE,FSTYPE,LABEL,MOUNTPOINTS
#   sudo /usr/local/bin/clamav-usb-scan.sh /dev/sdX1
# The automatic service waits without blocking udev until KDE mounts the filesystem
# or the device is disconnected. The waiting loop sleeps between checks.

sudo systemctl daemon-reload
sudo udevadm control --reload-rules


#########################################################
# SELinux:
#########################################################

# SELinux Hardening - Mandatory for scanning home directories and system paths in Fedora

# # sudo setsebool -P antivirus_can_scan_system true
# sudo setsebool -P antivirus_can_scan_system 1
# sudo setsebool -P antivirus_use_jit 1
# # Allow clamonacc to scan user home directories
# sudo setsebool -P antivirus_scan_home_dirs 1


for b in antivirus_can_scan_system antivirus_use_jit; do
    if getsebool "$b" >/dev/null 2>&1; then sudo setsebool -P "$b" 1
    else echo "SELinux boolean $b not present, skipping"; fi
done



#########################################################
# Create a systemd service for ClamOnAcc
#########################################################


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
# echo "[+] Creating clamonacc service..."

# sudo tee /etc/systemd/system/clamav-clamonacc.service >/dev/null <<EOF
# [Unit]
# Description=ClamAV On-Access Scanner
# Requires=clamd@scan.service
# After=clamd@scan.service

# [Service]
# Type=simple
# ExecStart=/usr/sbin/clamonacc \
#   --foreground \
#   --fdpass \
#   --log=$ONACC_LOG \
#   --move=$QUARANTINE_DIR \
#   --include-path=/home \
#   --exclude-uids=0 \
#   --exclude-dir=/proc \
#   --exclude-dir=/sys

# Restart=on-failure

# [Install]
# WantedBy=multi-user.target
# EOF

################

# sudo systemctl stop clamav-clamonacc.service

if systemctl cat clamav-clamonacc.service >/dev/null 2>&1 &&
   systemctl is-active --quiet clamav-clamonacc.service; then
    sudo systemctl stop clamav-clamonacc.service
fi

sudo tee /etc/systemd/system/clamav-clamonacc.service > /dev/null <<EOF
[Unit]
Description=ClamAV On-Access Scanner
Requires=clamd@scan.service
After=clamd@scan.service

[Service]
Type=simple
User=root
# Minimal arguments: Just foreground, logging, and fdpass
# ExecStart=/usr/sbin/clamonacc \
#   --foreground \
#   --fdpass \
#   --log=$ONACC_LOG \
#   --move=$QUARANTINE_DIR

# Fedora's own packaged clamonacc unit also passes --config-file explicitly (per the dist-git patch)
# --wait --ping 90:2 waits up to 3 minutes for clamd. I tested that it waits, then starts once clamd appears, or exits 21 on timeout.
ExecStart=/usr/sbin/clamonacc \
    --foreground \
    --fdpass \
    --config-file=$SCAN_CONF \
    --wait --ping 90:2 \
    --log=$ONACC_LOG \
    --move=$QUARANTINE_DIR

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF


#########################################################
# Systemd Resource Hardening Overlay
#########################################################

# Instead of editing the package's native service file (which gets overwritten during system updates), we use a systemd drop-in override directory (/etc/systemd/system/clamd@scan.service.d/override.conf). Systemd automatically merges this with the default unit. Out of the box, clamd@scan.service has no resource limits.
# ClamAV is notorious for memory spikes when encountering complex archives or "archive bombs" (e.g., a tiny zip file that expands into hundreds of gigabytes). Without a memory cap, a runaway scan can consume 100% of your system RAM, triggering the Linux kernel's Out-Of-Memory (OOM) killer and potentially crashing your desktop session or other critical background apps. Capping memory (e.g., MemoryMax=4G) and CPU (CPUQuota=60%) forces ClamAV to run safely in the background as a disciplined citizen.

# sudo mkdir -p /etc/systemd/system/clamd@scan.service.d
# cat <<EOF | sudo tee /etc/systemd/system/clamd@scan.service.d/override.conf
# [Service]
# # Prevent ClamAV from consuming all system RAM during heavy archive expansions
# MemoryMax=4G
# # Limit CPU core utilization to avoid locking up desktop interactions during background scans
# CPUQuota=60%
# EOF



# Do not impose a fixed memory ceiling: ClamAV's memory needs
# vary with its signature databases and scan workload.
#
# Give clamd a lower CPU scheduling weight when competing with
# other services. This is a relative priority, not a hard CPU cap.
#
# 1. MemoryMax removed: ClamAV can use the memory it needs without being abruptly constrained by an arbitrary 4 GB ceiling. This does mean there is no memory cap from this override, so monitor memory usage on lower-RAM machines.
# 2. CPUQuota=60% removed: 60% means roughly 60% of one CPU's capacity, not 60% of your machine's total CPU capacity. It can substantially slow scans.
# 3. CPUWeight=50 added: systemd gives the daemon a lower relative CPU weight than services with the default weight of 100 when they compete for CPU time. It does not cap CPU use when the system is otherwise idle.
#
sudo mkdir -p /etc/systemd/system/clamd@scan.service.d
cat <<EOF | sudo tee /etc/systemd/system/clamd@scan.service.d/override.conf
[Service]
CPUWeight=50
Restart=on-failure
RestartSec=10
EOF


sudo systemctl daemon-reload


#########################################################
# Maybe TODO
#########################################################

# Desktop Integration (Wayland)
# For KDE Dolphin (Plasma 6 Path)
# mkdir -p ~/.local/share/kio/servicemenus/
# ln -sf /usr/share/kservices5/ServiceMenus/clamtk-kde.desktop ~/.local/share/kio/servicemenus/clamtk-kde.desktop

# For Gnome Nautilus
# Extensions are installed via clamtk-gnome package automatically.


#########################################################
# squidclamav
#########################################################

# # Configure ClamAV with Squid via SquidClamAV - Proxy Integration for Web Scanning
# sudo apt install squid squidclamav

# # /etc/squid/squid.conf:
# icap_enable on
# icap_service clamav_scan reqmod_precache icap://127.0.0.1:1344/clamav
# icap_service clamav_scan respmod_precache icap://127.0.0.1:1344/clamav
# # Ensure clamd is running and configured for network access (TCPSocket in clamd.conf):
# TCPSocket 3310
# TCPAddr 127.0.0.1

# sudo systemctl restart squid clamav-daemon

#########################################################
# Automatated update scheduling: (Older method)
#########################################################

# # 1. create a systemd timer
# sudo nano /etc/systemd/system/freshclam.timer

# # Add the following content:

# # [Unit]
# # Description=freshclam database updates

# # [Timer]
# # OnCalendar=daily
# # Persistent=true

# # [Install]
# # WantedBy=timers.target

# # 2. create the corresponding service file
# sudo nano /etc/systemd/system/freshclam.service

# # Add the following content:

# # [Unit]
# # Description=freshclam database updater

# # [Service]
# # Type=oneshot
# # ExecStart=/usr/bin/freshclam --quiet

# # 3. enable and start the timer
# sudo systemctl enable freshclam.timer
# sudo systemctl start freshclam.timer
# # sudo systemctl enable --now clamav-freshclam.service

# ## scheduled scans

# # create a cron job
# sudo crontab -e

# # Add a line to run a daily scan at 2 AM
# # 0 2 * * * /usr/bin/clamscan -r /home > /var/log/clamav/daily_scan.log


# # Scheduled ClamAV Scans
# crontab -e
# # sudo dnf install cronie # IF ABOVE DOESN'T WORK
# # add following line to add daily scan
# # 0 1 * * * /usr/bin/clamscan -r --quiet --move=/home/USER/infected /home/


#########################################################
# Update databases for the first time
#########################################################

sudo freshclam


#########################################################
# Persistent Weekly Scan Setup
#########################################################

# identify that the last scheduled scan didn't run because of the PC being off, etc. - Systemd timers natively handle this via Persistent=true. If your PC is powered off when the weekly scan is scheduled, systemd automatically triggers the scan as soon as the system boots back up. 
# To prevent system overload, we use nice and ionice to run the scan with low priority so it doesn't freeze your desktop or heavy tasks.

echo "Configuring background weekly system scan timer..."








sudo tee /usr/local/bin/clamav-weekly-scan.sh > /dev/null <<'EOF'
#!/bin/bash
set -u

# Prevent overlapping weekly scan instances.
exec 9>/run/clamav-weekly-scan.lock
# if ! flock -n 9; then
#     echo "A weekly scan is already running; exiting."
#     exit 0
# fi
flock -n 9 || { echo "weekly scan already running"; exit 0; }

echo "Weekly scan started: $(date --iso-8601=seconds)"

LOG_DIR="/var/log/clamav"
# LOGFILE="${LOG_DIR}/weekly_scan_$(date +\%Y-\%m-\%d).log"
# LOGFILE="${LOG_DIR}/weekly_scan_$(date +%Y-%m-%d).log"
LOGFILE="${LOG_DIR}/weekly_scan.log"        # fixed name: logrotate handles retention

# Run with low CPU/IO priority to avoid overloading the system
# nice -n 19 ionice -c 3 clamdscan --multiscan -r / \
#     --exclude-dir="/proc|/sys|/dev|/run|/var/log|/var/spool/postfix" \
#     --infected --log="$LOGFILE"


# The above exclusion argument is a regular expression, not a list of independent path arguments. That means the expression needs to match the paths as they are presented to ClamAV. The following excludes the listed top-level directories and their descendants.
# nice -n 19 ionice -c 3 clamdscan --multiscan -r / \
#     --exclude-dir='^/(proc|sys|dev|run|var/log|var/spool/postfix)(/|$)' \
#     --infected --log="$LOGFILE"
# SCAN_STATUS=$?

# The above version uses clamdscan (https://docs.clamav.net/manual/Usage/Scanning.html#clamdscan). And the below version uses clamscan (https://docs.clamav.net/manual/Usage/Scanning.html#clamscan)


# Scan where malware lives; /usr is rpm-verifiable (see opinions table). /srv covers nbServer's data disks.
ROOTS=()
for d in /home /root /etc /opt /srv /usr/local /var/tmp /tmp; do
    if [ -d "$d" ]; then ROOTS+=("$d"); fi
done

nice -n 19 ionice -c 3 clamscan -r --infected --cross-fs=yes --log="$LOGFILE" \
    --exclude-dir='^/var/quarantine(/|$)' \
    --exclude-dir='^/var/lib/(docker|containers)(/|$)' \
    --exclude-dir='^/home/[^/]+/[.]local/share/containers(/|$)' \
    --exclude-dir='^/(proc|sys|dev|run|var/log|var/spool/postfix)(/|$)' \
    "${ROOTS[@]}"
SCAN_STATUS=$?


# Find the first active graphical desktop user (UID >= 1000)
# ACTIVE_USER=$(loginctl list-sessions --no-legend | awk '{print $2}' | while read -r user; do id -u "$user" &>/dev/null && [ "$(id -u "$user")" -ge 1000 ] && echo "$user" && break; done)

# Use awk '{print $3}' instead of $2 - gives user rather than uid
# ACTIVE_USER=$(loginctl list-sessions --no-legend |
#     awk '{print $3}' |
#     while read -r user; do
#         id -u "$user" &>/dev/null &&
#         [ "$(id -u "$user")" -ge 1000 ] &&
#         echo "$user" &&
#         break
#     done)

ACTIVE_USER=$(
    loginctl list-sessions --no-legend |
        awk '{print $3}' |
        while read -r user; do
            [[ -n "$user" ]] || continue

            user_uid=$(id -u "$user" 2>/dev/null) || continue

            if (( user_uid >= 1000 && user_uid < 65534 )); then
                printf '%s\n' "$user"
                break
            fi
        done
)

# Fallback if no active session is found
if [ -z "$ACTIVE_USER" ]; then
    ACTIVE_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd | head -n 1)
fi


# # Check for infections and notify if found
# if grep -q "Infected files: [1-9]" "$LOGFILE"; then
#     sudo -u "$SUDO_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$SUDO_USER")/bus \
#         notify-send "⚠ ClamAV Alert" "Infected files found during weekly scan! Check $LOGFILE" -i dialog-warning
# fi

# if grep -q "Infected files: [1-9]" "$LOGFILE"; then
#     if [ -n "$ACTIVE_USER" ]; then
#         USER_UID=$(id -u "$ACTIVE_USER")
#         sudo -u "$ACTIVE_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$USER_UID/bus \
#             notify-send "⚠ ClamAV Alert" "Infected files found during weekly scan! Check $LOGFILE" -i dialog-warning
#     fi 
# fi


if grep -qE 'Infected files: [1-9][0-9]*' "$LOGFILE" ||
   [ "$SCAN_STATUS" -eq 1 ]; then

    NOTIFICATION_TITLE="⚠ ClamAV Alert"
    NOTIFICATION_MESSAGE="Infection detected during weekly scan. Exit status: $SCAN_STATUS. Check $LOGFILE"
    NOTIFICATION_ICON="dialog-warning"
    logger -t clamav-alert "$NOTIFICATION_MESSAGE"
    # logger -p authpriv.warning -t clamav-alert "Weekly scan: INFECTED files found, see $LOGFILE" ;;

elif [ "$SCAN_STATUS" -eq 0 ]; then

    NOTIFICATION_TITLE="ClamAV Scan Complete"
    NOTIFICATION_MESSAGE="No infections found during weekly scan. Check $LOGFILE"
    NOTIFICATION_ICON="dialog-information"
    logger -t clamav-scan "$NOTIFICATION_MESSAGE"

else

    NOTIFICATION_TITLE="⚠ ClamAV Scan Error"
    NOTIFICATION_MESSAGE="Weekly scan failed or was incomplete. Exit status: $SCAN_STATUS. Check $LOGFILE"
    NOTIFICATION_ICON="dialog-error"
    logger -t clamav-scan "$NOTIFICATION_MESSAGE"
    # logger -p authpriv.err     -t clamav-alert "Weekly scan finished with errors (SCAN_STATUS=$SCAN_STATUS), see $LOGFILE" ;;

fi


# Display the result to the active desktop user, if available.
if [ -n "$ACTIVE_USER" ]; then
    USER_UID=$(id -u "$ACTIVE_USER")
    sudo -u "$ACTIVE_USER" \
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_UID/bus" \
        notify-send -u normal -i "$NOTIFICATION_ICON" \
        "$NOTIFICATION_TITLE" "$NOTIFICATION_MESSAGE"
fi

echo "Weekly scan finished: $(date --iso-8601=seconds)"
exit 0

EOF


sudo chmod +x /usr/local/bin/clamav-weekly-scan.sh

sudo tee /etc/systemd/system/clamav-weekly-scan.service > /dev/null <<EOF
[Unit]
Description=ClamAV Weekly Full System Scan

[Service]
Type=oneshot
ExecStart=/usr/local/bin/clamav-weekly-scan.sh
# User=root
Nice=19
IOSchedulingClass=idle
CPUSchedulingPolicy=idle
# ConditionACPower=true   # laptops: skip on battery (nbXPS, nbLenovo)
EOF



sudo tee /etc/systemd/system/clamav-weekly-scan.timer > /dev/null <<EOF
[Unit]
Description=Run ClamAV Weekly Full System Scan
After=network.target

[Timer]
# Runs weekly and catches up missed runs if the PC was powered off
OnCalendar=weekly
Persistent=true
RandomizedDelaySec=30min

[Install]
WantedBy=timers.target
EOF

sudo systemctl enable --now clamav-weekly-scan.timer


#########################################################
# Real-Time VirusEvent Notification Hook
#########################################################

# enables an instant desktop popup at the exact moment the daemon intercepts a threat. Because clamd runs as an unprivileged background user (clamscan), it cannot trigger GUI notifications directly without a helper hook and a sudoers exception.

# echo "[+] Configuring real-time VirusEvent notification hook..."

# sudo tee /usr/local/bin/clamav-notify.sh > /dev/null <<'EOF'
# #!/bin/bash
# VIRUS_NAME="$CLAM_VIRUSEVENT_VIRUSNAME"
# FILE_PATH="$CLAM_VIRUSEVENT_FILENAME"

# # Find the active graphical desktop user (UID >= 1000)
# # ACTIVE_USER=$(loginctl list-sessions --no-legend | awk '{print $2}' | while read -r user; do id -u "$user" &>/dev/null && [ "$(id -u "$user")" -ge 1000 ] && echo "$user" && break; done)

# # Use awk '{print $3}' instead of $2 - gives user rather than uid
# # ACTIVE_USER=$(loginctl list-sessions --no-legend |
# #     awk '{print $3}' |
# #     while read -r user; do
# #         id -u "$user" &>/dev/null &&
# #         [ "$(id -u "$user")" -ge 1000 ] &&
# #         echo "$user" &&
# #         break
# #     done)

# ACTIVE_USER=$(
#     loginctl list-sessions --no-legend |
#         awk '{print $3}' |
#         while read -r user; do
#             [[ -n "$user" ]] || continue

#             user_uid=$(id -u "$user" 2>/dev/null) || continue

#             if (( user_uid >= 1000 && user_uid < 65534 )); then
#                 printf '%s\n' "$user"
#                 break
#             fi
#         done
# )

# if [ -n "$ACTIVE_USER" ]; then
#     USER_UID=$(id -u "$ACTIVE_USER")
#     sudo -u "$ACTIVE_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_UID/bus" \
#         notify-send -u critical -i dialog-warning "⚠ ClamAV Real-Time Alert" "Threat: ${VIRUS_NAME}\nFile: ${FILE_PATH}"
# fi

# # Audit trail logging
# logger -t clamav-alert "ALERT: Threat ${VIRUS_NAME} detected in ${FILE_PATH}"
# EOF

# sudo chmod +x /usr/local/bin/clamav-notify.sh



echo "[+] Configuring real-time VirusEvent notification hook..."

# clamd runs VirusEvent as the clamd service user (clamscan in this setup).
# This unprivileged wrapper passes the two documented ClamAV event variables
# as quoted argv entries to one fixed, root-owned helper.
sudo tee /usr/local/bin/clamav-notify.sh > /dev/null <<'EOF'
#!/usr/bin/bash
set -u

VIRUS_NAME="${CLAM_VIRUSEVENT_VIRUSNAME:-Unknown threat}"
FILE_PATH="${CLAM_VIRUSEVENT_FILENAME:-Unknown file}"

exec /usr/bin/sudo -n -- /usr/local/sbin/clamav-notify-root "$VIRUS_NAME" "$FILE_PATH"
EOF

# Privileged helper: it can only log a ClamAV alert and notify the active
# local graphical session. No shell is constructed from event data.
sudo install -d -o root -g root -m 0755 /usr/local/sbin
sudo tee /usr/local/sbin/clamav-notify-root > /dev/null <<'EOF'
#!/usr/bin/bash
set -Eeuo pipefail

if (( EUID != 0 )); then
    echo "clamav-notify-root must be run as root." >&2
    exit 1
fi
if (( $# != 2 )); then
    echo "Usage: clamav-notify-root VIRUS_NAME FILE_PATH" >&2
    exit 2
fi

# Keep untrusted filenames/labels as data; avoid notification/log spoofing by
# collapsing line breaks and limiting the amount of displayed text.
VIRUS_NAME=${1//$'\n'/ }
VIRUS_NAME=${VIRUS_NAME//$'\r'/ }
FILE_PATH=${2//$'\n'/ }
FILE_PATH=${FILE_PATH//$'\r'/ }
VIRUS_NAME=${VIRUS_NAME:0:240}
FILE_PATH=${FILE_PATH:0:800}

logger -p authpriv.warning -t clamav-alert -- "ALERT: Threat ${VIRUS_NAME} detected in ${FILE_PATH}"

find_active_graphical_user() {
    local session_id _session_uid _session_user _rest session_info
    local session_name session_active session_remote session_type session_class

    while read -r session_id _session_uid _session_user _rest; do
        [[ -n "$session_id" ]] || continue
        session_info=$(loginctl show-session "$session_id" \
            -p Name -p Active -p Remote -p Type -p Class --no-pager 2>/dev/null) || continue

        session_name=$(sed -n 's/^Name=//p' <<< "$session_info")
        session_active=$(sed -n 's/^Active=//p' <<< "$session_info")
        session_remote=$(sed -n 's/^Remote=//p' <<< "$session_info")
        session_type=$(sed -n 's/^Type=//p' <<< "$session_info")
        session_class=$(sed -n 's/^Class=//p' <<< "$session_info")

        if [[ "$session_active" == yes && "$session_remote" == no &&
              "$session_class" == user &&
              ( "$session_type" == wayland || "$session_type" == x11 ) &&
              -n "$session_name" ]]; then
            printf '%s\n' "$session_name"
            return 0
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null)

    return 1
}

ACTIVE_USER=$(find_active_graphical_user) || ACTIVE_USER=""
if [[ -z "$ACTIVE_USER" ]]; then
    logger -t clamav-alert -- "No active local graphical session; real-time notification not displayed."
    exit 0
fi

USER_UID=$(id -u -- "$ACTIVE_USER") || exit 0
RUNTIME_DIR="/run/user/$USER_UID"
if [[ ! -S "$RUNTIME_DIR/bus" ]]; then
    logger -t clamav-alert -- "No session D-Bus socket for $ACTIVE_USER; real-time notification not displayed."
    exit 0
fi

MESSAGE="Threat: ${VIRUS_NAME}"$'\n'"File: ${FILE_PATH}"
if ! runuser -u "$ACTIVE_USER" -- /usr/bin/env \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus" \
    /usr/bin/notify-send -u critical -i dialog-warning -- \
    "ClamAV Real-Time Alert" "$MESSAGE"; then
    logger -t clamav-alert -- "notify-send failed for active user $ACTIVE_USER."
fi
EOF

sudo chown root:root /usr/local/bin/clamav-notify.sh /usr/local/sbin/clamav-notify-root
sudo chmod 0755 /usr/local/bin/clamav-notify.sh /usr/local/sbin/clamav-notify-root


# # Grant the clamscan user permission to invoke notify-send via sudo
# sudo tee /etc/sudoers.d/clamav-notify > /dev/null <<'EOF'
# clamscan ALL=(ALL) NOPASSWD: SETENV: /usr/bin/notify-send
# EOF
# sudo chmod 440 /etc/sudoers.d/clamav-notify

# if ! sudo visudo -cf /etc/sudoers.d/clamav-notify; then
#     echo "ERROR: Invalid sudoers configuration for ClamAV notifications." >&2
#     exit 1
# fi

# # a root-owned file should have permissions 440
# sudo stat -c '%U:%G %a %n' /etc/sudoers.d/clamav-notify



# Narrow exception: clamscan may run only this fixed, root-owned helper as root.
# No SETENV is granted, and notify-send itself is no longer sudo-authorized.
sudo tee /etc/sudoers.d/clamav-notify > /dev/null <<'EOF'
clamscan ALL=(root) NOPASSWD: NOSETENV: /usr/local/sbin/clamav-notify-root
EOF
sudo chown root:root /etc/sudoers.d/clamav-notify
sudo chmod 0440 /etc/sudoers.d/clamav-notify

if ! sudo visudo -cf /etc/sudoers.d/clamav-notify; then
    echo "ERROR: Invalid sudoers configuration for ClamAV notifications." >&2
    exit 1
fi
if ! sudo visudo -c; then
    echo "ERROR: The complete sudoers configuration is invalid." >&2
    exit 1
fi


#########################################################
# SELinux: Restore expected contexts before service start
#########################################################

############################ OLD Code:
# Fix ClamD Scan Service Start Failure - maybe do this if Verification at the end fails # TODO  - check


# # turn SELinux on if disabled
# sudo setenforce 1

# # # When clamd@scan.service fails, inspect the relevant records:
# # sudo ausearch -m AVC -ts recent
# # sudo journalctl -u clamd@scan.service -b --no-pager -n 100
# # # Check the file contexts:
# # ls -Zd /var/log/clamav /var/lib/clamav /run/clamd.scan
# # # Restore default contexts when appropriate:
# # sudo restorecon -Rv /var/log/clamav /var/lib/clamav
# # Only consider a custom policy after identifying a specific denial that cannot be resolved by correcting the configuration or restoring the expected context.

# ##########
# # Fix 1
# # Sometimes the issue isn't a missing permission rule, but simply that the files have the wrong SELinux context 
# # Restore the default contexts:
# sudo restorecon -Rv /var/log/clamav
# sudo restorecon -Rv /var/lib/clamav

# # # If above fix 1 fails, manually set the context:
# # # Set the log directory context
# # sudo semanage fcontext -a -t clamav_var_log_t "/var/log/clamav(/.*)?"
# # sudo restorecon -Rv /var/log/clamav
# # # Set the database directory context
# # sudo semanage fcontext -a -t clamav_var_lib_t "/var/lib/clamav(/.*)?"
# # sudo restorecon -Rv /var/lib/clamav

# ##########
# # # Fix 2
# # # This reads the audit log and creates a policy module named 'clamd_fix'
# # # audit2allow tool reads the denial logs and creates a custom policy module automatically.

# # audit2allow generates a custom policy from observed denials. Those denials might reflect a genuine configuration error rather than a missing policy rule.
# # sudo ausearch -m avc -ts recent | grep clamd | audit2allow -M clamd_fix

# # Automatically installing the generated module can grant additional permissions without you reviewing them.
# # sudo semodule -i clamd_fix.pp

# ####### NOTE: if the fix was needed to be run, then run the "Service Activation" section again




############################ NEW Code:

# This turns enforcement on if SELinux is permissive, but does not incorrectly attempt to enable it at runtime when SELinux is disabled.    
SELINUX_MODE=$(getenforce)
if [[ "$SELINUX_MODE" == "Permissive" ]]; then
    echo "[+] SELinux is permissive; enabling enforcement."
    sudo setenforce 1
elif [[ "$SELINUX_MODE" == "Disabled" ]]; then
    echo "WARNING: SELinux is disabled. It cannot be enabled with setenforce." >&2
fi

sudo restorecon -Rv /var/log/clamav
sudo restorecon -Rv /var/lib/clamav

sudo restorecon -v /usr/local/bin/clamav-usb-scan.sh /usr/local/bin/clamav-notify.sh /usr/local/sbin/clamav-notify-root
sudo restorecon -v /etc/udev/rules.d/99-clamav-usb.rules /etc/systemd/system/clamav-usb-scan@.service /etc/sudoers.d/clamav-notify


#########################################################
# Service Activation
#########################################################

# Validate ClamD Configuration Syntax
# If a typo slips into your sed rules or configuration appends, clamd@scan.service will fail to start silently or throw obscure systemd errors. Adding a config syntax test before starting services saves troubleshooting time.
echo "[+] Validating clamd configuration syntax..."
if ! clamd --config-file="$SCAN_CONF" --test; then
    echo "Error: ClamD configuration test failed. Please check syntax."
    exit 1
fi


# Fedora uses clamd@scan as the default instance.
sudo systemctl daemon-reload
sudo systemctl enable --now clamav-freshclam.service
sudo systemctl enable --now clamav-unofficial-sigs.timer
sudo systemctl enable --now clamd@scan.service
sudo systemctl enable --now clamav-clamonacc.service
# sudo systemctl enable --now fangfrisch.timer




# sudo systemctl daemon-reload
# sudo systemctl restart clamav-freshclam.service
# sudo systemctl restart clamav-unofficial-sigs.timer
# sudo systemctl restart clamd@scan.service
# sudo systemctl restart clamav-clamonacc.service

#########################################################
# Configure Logrotate for ClamAV
#########################################################

# ClamAV's internal LogRotate yes: Tt only tells the daemon to handle log management internally when a certain size threshold is met, but it does not compress files, manage retention cycles (e.g., keeping only the last 4 weeks), or safely purge old logs. It often just renames or truncates files, which can leave dangling file descriptors if the daemon isn't signaled properly.

# the following system logrotate utility: It provides comprehensive lifecycle automation: compresses old logs (.gz), enforces hard limits (rotate 4 to keep disk usage predictable), manages file permissions, and executes a safe postrotate script (systemctl try-restart clamd@scan.service) so the daemon cleanly re-opens the new log file without losing tracking or leaking file handles.

# cat <<EOF | sudo tee /etc/logrotate.d/clamav
# /var/log/clamav/*.log {
#     weekly
#     rotate 4
#     compress
#     delaycompress
#     missingok
#     notifempty
#     create 640 $CLAM_USER $CLAM_USER
#     sharedscripts
#     postrotate
#         systemctl try-restart clamd@scan.service >/dev/null 2>&1 || true
#     endscript
# }
# EOF

############################

# The following rotates the custom USB and weekly scan logs, retaining up to eight rotated weekly files. It intentionally does not rotate the ClamAV daemon logs, because those already have their own LogRotate configuration in the script. The --debug check validates the configuration without performing rotation.

sudo tee /etc/logrotate.d/clamav-custom-scans > /dev/null <<'EOF'
/var/log/clamav/usb_scan_*.log
/var/log/clamav/weekly_scan_*.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    dateext
    su root root
}
EOF

sudo chmod 644 /etc/logrotate.d/clamav-custom-scans

# Validate the configuration before finishing setup.
sudo logrotate --debug /etc/logrotate.d/clamav-custom-scans

#########################################################
# Verification
#########################################################

# if systemctl is-active --quiet clamd@scan.service; then
#     echo "ClamAV automation successful"
#     clamdscan --version
# else
#     echo "Critical: ClamAV daemon failed to start. Reviewing journal logs..."
#     # journalctl -u clamd@scan.service --no-pager -n 50
#     # exit 1
# fi


# # I know the following could go in the else block just above. But wanted to keep this here bacause this is an interesting use of || (OR) condition that I would like to ponder upon:

# # Verify both services started successfully.
# sudo systemctl is-active --quiet clamd@scan.service || {
#     echo "ERROR: clamd@scan.service is not active." >&2
#     sudo journalctl -u clamd@scan.service -b --no-pager -n 50
#     exit 1
# }

# sudo systemctl is-active --quiet clamav-clamonacc.service || {
#     echo "ERROR: clamav-clamonacc.service is not active." >&2
#     sudo journalctl -u clamav-clamonacc.service -b --no-pager -n 50
#     exit 1
# }

# if ! systemctl is-active --quiet clamav-unofficial-sigs.timer; then
#     echo "ERROR: Unofficial-signature update timer is not active." >&2
#     sudo systemctl status clamav-unofficial-sigs.timer --no-pager
#     exit 1
# fi


echo "Checking ClamAV services..."

FAILED=0

for service in \
    clamav-freshclam.service \
    clamd@scan.service \
    clamav-clamonacc.service \
    clamav-unofficial-sigs.timer \
    clamav-weekly-scan.timer
do
    if systemctl is-active --quiet "$service"; then
        printf 'OK: %s is active\n' "$service"
    else
        printf 'ERROR: %s is not active\n' "$service"
        sudo systemctl status "$service" --no-pager || true
        FAILED=1
    fi
done

if [ "$FAILED" -ne 0 ]; then
    echo "ClamAV setup completed with errors." >&2
    exit 1
fi

echo "Validating generated systemd units and logrotate configuration..."
sudo systemd-analyze verify \
    /etc/systemd/system/clamav-clamonacc.service \
    /etc/systemd/system/clamav-weekly-scan.service \
    /etc/systemd/system/clamav-weekly-scan.timer
sudo logrotate --debug /etc/logrotate.d/clamav-custom-scans

echo "ClamAV services and timers are active."
clamdscan --version

# Check the custom scan-log rotation configuration without changing any logs:
sudo logrotate --debug /etc/logrotate.d/clamav-custom-scans

#########################################################
# Scanning syntax:
#########################################################

# # sudo clamscan [options] [file/directory/-]
# sudo clamscan -h # Help
# sudo clamscan /home/script.sh # Scan a file
# sudo clamscan /home/ # Scan a dir
# sudo clamscan -i /home/ # Print only infected files
# sudo clamscan -o /home/ # Exclude printing OK files
# sudo clamscan --bell -i /home # bell notification upon virus detection
# sudo clamscan --bell -i -r /home # Scan directories recursively 
# sudo clamscan --bell -i -r /home -l output.txt # Save the scan report to file 
# sudo clamscan -i -f /tmp/scan # Scan files listed line-by-line in a specified file 
# sudo clamscan -r --remove /home/USER # automatically remove infected files detected during the scan
# sudo clamscan -r -i --move=/home/USER/infected /home/ # Move all files requiring quarantine into the specified location
# sudo nice -n 15 clamscan && sudo clamscan --bell -i -r /home # To limit CPU usage during the scan, use the nice command

# --bell --quiet --cross-fs=yes --move="/home/nbhirud/nb/clamscan_infected" --heuristic-alerts=yes --recursive

# clamscan --bell --quiet --cross-fs=yes --move="/home/nbhirud/Desktop/clamscan_infected" --heuristic-alerts=yes --recursive -i /

# clamscan --bell --cross-fs=yes --move="/home/nbhirud/Desktop/clamscan_infected" --heuristic-alerts=yes --recursive -i /

# clamscan --bell --cross-fs=yes --move="/home/nbhirud/Desktop/clamscan_infected" --heuristic-alerts=yes --recursive -i . | tee clamscan.log





#########################################################
# Debugging / Testing / Troubleshooting:
#########################################################

# Check if the script is syntactically correct:
# bash -n clamav.sh
# shellcheck clamav.sh

# run your setup script and inspect the resulting services:
# systemctl --failed
# systemctl status clamd@scan.service clamav-freshclam.service clamav-clamonacc.service --no-pager
# systemctl status clamav-weekly-scan.timer clamav-unofficial-sigs.timer --no-pager


# Verify ClamD Configuration Syntax:
# sudo clamd --config-file=/etc/clamd.d/scan.conf --test
# Should return: Configuration file parsed successfully.

# Check Core Service Health:
# sudo systemctl status clamav-freshclam.service clamd@scan.service clamav-clamonacc.service --no-pager
# All three services should show: Active: active (running).

# Verify Systemd Timer for Weekly Scans:
# sudo systemctl list-timers clamav-weekly-scan.timer
# Should display the next scheduled execution time and confirms Persistent=true is active.

# Test On-Access Scanning (ClamOnAcc):
# wget https://secure.eicar.org/eicar.com.txt -P ~/Downloads
# ClamOnAcc should immediately block or flag the file, and you can verify the catch in /var/log/clamav/clamonacc.log.

# VirusEvent Notification
# # After the main script generates the helper, run:
# bash -n /usr/local/bin/clamav-notify.sh
# # Then inspect the generated file:
# sudo sed -n '1,80p' /usr/local/bin/clamav-notify.sh

# If you do choose /dev/shm, first inspect its capacity:
# df -h /dev/shm

# verify the effective limit settings (clamd@scan.service.d) before specifying things like MemoryMax=4G with:
# systemctl show clamd@scan.service -p MemoryMax -p CPUQuotaPerSecUSec -p CPUWeight

# Check the current owner and permissions:
# stat -c '%U:%G %a %n' /var/lib/clamav
# Check the actual files:
# sudo find /var/lib/clamav -maxdepth 1 -type f -printf '%u:%g %m %f\n'

# SELinux booleans
# antivirus_scan_home_dirs does not show up, so removed it. antivirus_can_scan_system and antivirus_use_jit are available
# getsebool -a | grep antivirus


# ls -l /var/lib/clamav/ # Check ClamAV directory and the dates of the files

# sudo clamdtop

# Output system and configuration information for viewing or possible debugging purposes
# sudo clamav-unofficial-sigs.sh -i

# inspect the most recent update (unofficial-sigs):
# sudo systemctl list-timers clamav-unofficial-sigs.timer

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



# ############################
# # Debugging freshclam

# # Database Problems The ClamAV database might be missing or corrupted:
# # Check if freshclam ran successfully
# sudo freshclam

# # Verify database exists
# ls -la /var/lib/clamav/

# # Check for errors in the freshclam log
# sudo tail -n 20 /var/log/clamav/freshclam.log

# ############################
# # Debugging clamd@scan.service

# # Check the specific error logs
# # sudo journalctl -u clamd@scan.service -n 50 --no-pager
# sudo journalctl -u clamd@scan.service -n 100 --no-pager -e

# # Or view the service status with extended output
# sudo systemctl status clamd@scan.service -l

# # Configuration File Issues Check /etc/clamav/clamd.conf for syntax errors:
# sudo clamd --config-file=/etc/clamav/clamd.conf --test

# # check if the clamscan user exists
# id clamscan

# # Check for SELinux/AppArmor interference
# # Check SELinux status
# getenforce
# # If enforcing, check for denials
# sudo ausearch -m avc -ts recent 2>/dev/null | grep clamd
# # sudo ausearch -m avc -ts recent | grep clamd
# # Temporarily set to permissive to test (not recommended for production)
# # sudo setenforce 0

# # Port Conflicts Check if another process is using port 3310:
# sudo netstat -tlnp | grep 3310
# # or
# sudo ss -tlnp | grep 3310

# # Resource Constraints Check system resources:
# free -h
# df -h

# # Verify it's working


# sudo systemctl is-active clamd@scan.service
# # Should return "active"

# # check what user the service is supposed to run as:
# # Check the service file
# grep -i user /usr/lib/systemd/system/clamd@.service
# # Check the config file
# grep -i user /etc/clamd.d/scan.conf


# ############################
# # Debugging clamav-clamonacc.service

# sudo journalctl -u clamav-clamonacc.service -n 50 --no-pager -e

# # Check if the binary supports the flags you are using:
# /usr/sbin/clamonacc --help | grep -E "fdpass|include-path"

# # Check for denials:
# sudo ausearch -m avc -ts recent | grep clamonacc

# # Monitor scan output directly using standard system logging tools:
# journalctl -u clamd@scan -f -o cat

# If you want a visual overview in the terminal without a GUI, tools like `lnav` (Log File Navigator) automatically parse and highlight ClamAV log files located in `/var/log/clamav/`.


# Test with the EICAR test file:
# wget https://secure.eicar.org/eicar.com.txt -P ~/Downloads
# cat ~/Downloads/eicar.com.txt
# If configured correctly, ClamOnAcc will block access with an "Operation not permitted" error.

# # Test with EICAR test file (safe test virus):
# echo 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' | sudo tee /tmp/eicar.txt
# sudo clamscan /tmp/eicar.txt
# Should detect it as "Win.Test.EICAR_HDB-1"
