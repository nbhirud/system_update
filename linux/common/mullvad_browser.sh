#!/bin/bash

set -eux

# Run-as-root check
if [ ${EUID:-0} -ne 0 ] || [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (or with sudo). You are running as $(whoami)."
  exit 1
else
  echo "You are running as $(whoami)"
fi

# HOME_DIR=$(getent passwd $USER | cut -d: -f6)
# Get the actual user's home when runing a script with sudo
FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
HOME_DIR=$(getent passwd "$SUDO_USER" | cut -d: -f6)
MULLVAD_CONFIG_DIR="$HOME_DIR"/.mullvad-browser/.mullvad/mullvadbrowser
SCAN_CONF="/etc/clamd.d/scan.conf"

NBDIR="$HOME_DIR/nb"
SCRIPT_DATA="$NBDIR/nb_script_data"
SCRIPT_BACKUPS_DIR="$SCRIPT_DATA"/backups/mullvad-browser_"${FILENAME_TIMESTAMP}"

mkdir -p "$SCRIPT_BACKUPS_DIR"
chown -R "$SUDO_USER:" "$SCRIPT_DATA"

echo "************************ Adding Mullvad repo ************************"
# https://mullvad.net/en/download/browser/linux
# Add the Mullvad repository server to dnf
# curl https://mullvad.net/en/download/browser/linux | grep addrepo

# Backup existing mullvad.repo if present
MULLVAD_REPO_FILE="/etc/yum.repos.d/mullvad.repo"
if [ -f "$MULLVAD_REPO_FILE" ]; then
    echo "Creating backup of $MULLVAD_REPO_FILE"
    cp -a "$MULLVAD_REPO_FILE" "${SCRIPT_BACKUPS_DIR}/mullvad.repo.bak"
    chown "$SUDO_USER:" "${SCRIPT_BACKUPS_DIR}/mullvad.repo.bak"
fi

sudo dnf config-manager addrepo --overwrite --from-repofile=https://repository.mullvad.net/rpm/stable/mullvad.repo

echo "************************ Installing Mullvad browser ************************"
sudo dnf install -y mullvad-browser


#########################################################
# Open and close mullvad-browser to initialize it
#########################################################

echo "************************ Initializing Mullvad Browser Profile ************************"

# # Run mullvad-browser as the actual user in headless mode briefly to generate profile directories
# su - "$SUDO_USER" -c "mullvad-browser --headless &"
# BROWSER_PID=$!
# sleep 5
# kill "$BROWSER_PID" 2>/dev/null || true
# wait "$BROWSER_PID" 2>/dev/null || true

# Run mullvad-browser as the actual user in headless mode briefly using timeout
# This avoids $! unbound variable issues under 'set -u' and cleans up automatically.
su - "$SUDO_USER" -c "timeout 5 mullvad-browser --headless >/dev/null 2>&1 || true"


#########################################################
# Exclude ublock Origin from Clamav: For some reason, clamav keeps deleting the extension
#########################################################

# cd "$HOME_DIR"/.mullvad-browser/.mullvad/mullvadbrowser/
# if [[ $(grep '\[Profile[^0]\]' profiles.ini) ]]
# then PROFPATH=$(grep -E '^\[Profile|^Path|^Default' profiles.ini | grep -1 '^Default=1' | grep '^Path' | cut -c6-)
# else PROFPATH=$(grep 'Path=' profiles.ini | sed 's/^Path=//')
# fi

cd "$MULLVAD_CONFIG_DIR"

# Note: Using bash evaluation since [[ ]] is a bashism
if su - "$SUDO_USER" -c "cd '$MULLVAD_CONFIG_DIR' && [[ \$(grep '\[Profile[^0]\]' profiles.ini) ]]"; then 
    PROFPATH=$(su - "$SUDO_USER" -c "cd '$MULLVAD_CONFIG_DIR' && grep -E '^\[Profile|^Path|^Default' profiles.ini | grep -1 '^Default=1' | grep '^Path' | cut -c6-")
else 
    PROFPATH=$(su - "$SUDO_USER" -c "cd '$MULLVAD_CONFIG_DIR' && grep 'Path=' profiles.ini | sed 's/^Path=//'")
fi


# PROFPATH will have the name/directory-name of default mullvad-browser profile
echo "The default mullvad-browser profile is: $PROFPATH"
cd "$PROFPATH"

############################
# Check if the exclusion is already present to maintain idempotency
EXCLUSION_MARKER="$PROFPATH/extensions/uBlock0@raymondhill.net.xpi"

if sudo grep -q "$EXCLUSION_MARKER" "$SCAN_CONF"; then
  echo "ClamAV exclusions for Mullvad browser are already configured."

else

  # Backup scan.conf if present
  if [ -f "$SCAN_CONF" ]; then
      echo "Creating backup of $SCAN_CONF..."
      cp -a "$SCAN_CONF" "${SCRIPT_BACKUPS_DIR}/scan.conf.bak"
      chown "$SUDO_USER:" "${SCRIPT_BACKUPS_DIR}/scan.conf.bak"
  fi

  cat <<EOF | sudo tee -a "$SCAN_CONF"

# Exclude Mullvad-browser's ublock-Origin from ClamOnAcc:
# OnAccessExcludePath /home/user # Add trusted browser extensions (regex including profiles, etc)

# uBlock Origin - uBlock0@raymondhill.net
# uBlock0@raymondhill.net.xpi
OnAccessExcludePath "$MULLVAD_CONFIG_DIR"/"$PROFPATH"/extensions/staged/uBlock0@raymondhill.net.xpi
OnAccessExcludePath "$MULLVAD_CONFIG_DIR"/"$PROFPATH"/extensions/uBlock0@raymondhill.net.xpi

# Mullvad Browser Extension - {d19a89b9-76c1-4a61-bcd4-49e8de916403}
# {d19a89b9-76c1-4a61-bcd4-49e8de916403}.xpi

# NoScript - {73a6fe31-595d-460b-a920-fcc0f8843232}
# {73a6fe31-595d-460b-a920-fcc0f8843232}.xpi

EOF

fi

cd "$HOME_DIR"

