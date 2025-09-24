#!/bin/sh

# set -eux

echo "************************ Setting literals and constants ************************"
HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)

CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects"
SYSUPDATE_SEC_CODE_DIR="$CODE_BASE_DIR/system_update/linux/security_os_level/"
SYSUPDATE_FEDORA_CODE_DIR="$CODE_BASE_DIR/system_update/linux/fedora/"

DOWNLOADS_DIR="$HOME_DIR/nb/Downloads"
DOWNLOADS_DIR_PROTON="$DOWNLOADS_DIR/proton_ag_downloads_$(date +%Y-%m-%d_%H-%M-%S)"

FEDORA_RELEASE_VERSION=$(sh "$SYSUPDATE_FEDORA_CODE_DIR"/get_fedora_release_version.sh)


echo "************************ Installing proton stuff ************************"
mkdir -p "$DOWNLOADS_DIR_PROTON"
cd "$DOWNLOADS_DIR_PROTON" || exit


######################### ProtonAuthenticator ###################################################################
echo "************************ Installing ProtonAuthenticator ************************"
# https://proton.me/support/set-up-proton-authenticator-linux
# Download the RPM file.
wget https://proton.me/download/authenticator/linux/ProtonAuthenticator.rpm
# Download the json with SHA
JSON_ProtonAuthenticator="ProtonAuthenticator_version.json"
wget -O $JSON_ProtonAuthenticator https://proton.me/download/authenticator/linux/version.json
# Get SHA from JSON
SHA_ProtonAuthenticator=$(sh "$SYSUPDATE_SEC_CODE_DIR"/proton_get_sha.sh "$DOWNLOADS_DIR_PROTON" $JSON_ProtonAuthenticator)
# Remove any leading or trailing quotes
SHA_ProtonAuthenticator=${SHA_ProtonAuthenticator%\"} # Remove a single quote from the end
SHA_ProtonAuthenticator=${SHA_ProtonAuthenticator#\"} # Remove a single quote from the beginning
# Confirm the package’s integrity
echo "$SHA_ProtonAuthenticator" ProtonAuthenticator.rpm | sha512sum --check -
# Install it
sudo dnf install ProtonAuthenticator.rpm


######################### ProtonPass ###################################################################
echo "************************ Installing ProtonPass ************************"
# https://proton.me/support/set-up-proton-pass-linux
# Download the RPM file.
wget https://proton.me/download/PassDesktop/linux/x64/ProtonPass.rpm
# Download the json with SHA
JSON_ProtonPass="ProtonPass_version.json"
wget -O $JSON_ProtonPass https://proton.me/download/PassDesktop/linux/x64/version.json
# Get SHA from JSON
SHA_ProtonPass=$(sh "$SYSUPDATE_SEC_CODE_DIR"/proton_get_sha.sh "$DOWNLOADS_DIR_PROTON" $JSON_ProtonPass)
# Remove any leading or trailing quotes
SHA_ProtonPass=${SHA_ProtonPass%\"} # Remove a single quote from the end
SHA_ProtonPass=${SHA_ProtonPass#\"} # Remove a single quote from the beginning
# Confirm the package’s integrity
echo "$SHA_ProtonPass ProtonPass.rpm" | sha512sum --check -
# Install it
# sudo rpm -i --force ProtonPass.rpm # OFFICIAL way, but RedHat seems to discourage this usage
sudo dnf install ProtonPass.rpm


######################### ProtonMail ###################################################################
echo "************************ Installing ProtonMail ************************"
# https://proton.me/support/set-up-proton-mail-linux
# Download the RPM file.
wget https://proton.me/download/mail/linux/ProtonMail-desktop-beta.rpm
# Download the json with SHA
JSON_ProtonMail="ProtonMail_version.json"
wget -O ProtonMail_version.json https://proton.me/download/mail/linux/version.json
# Get SHA from JSON
SHA_ProtonMail=$(sh "$SYSUPDATE_SEC_CODE_DIR"/proton_get_sha.sh "$DOWNLOADS_DIR_PROTON" $JSON_ProtonMail)
# Remove any leading or trailing quotes from the variable
SHA_ProtonMail=${SHA_ProtonMail%\"} # Remove a single quote from the end
SHA_ProtonMail=${SHA_ProtonMail#\"} # Remove a single quote from the beginning
# check the RPM file’s integrity
echo "$SHA_ProtonMail ProtonMail-desktop-beta.rpm" | sha512sum --check -
# Install it
sudo dnf install ./ProtonMail-desktop-beta.rpm


########################## ProtonVPN ###################################################################

########################## ProtonVPN - Following is an implementation of the OFFICIAL way: 
# echo "************************ Installing ProtonVPN ************************"
# # https://protonvpn.com/support/official-linux-vpn-fedora/
# # Download the package that contains the repository configuration and keys required to install the Proton VPN app
# wget "https://repo.protonvpn.com/fedora-$(cat /etc/fedora-release | cut -d' ' -f 3)-stable/protonvpn-stable-release/protonvpn-stable-release-1.0.3-1.noarch.rpm"
# # Install the Proton VPN repository containing the app
# sudo dnf install -y ./protonvpn-stable-release-1.0.3-1.noarch.rpm && sudo dnf check-update --refresh 
# # Install the app and accept an OpenPGP key.
# sudo dnf install -y proton-vpn-gnome-desktop 
# # Enable GNOME desktop tray icons
# sudo dnf install -y libappindicator-gtk3 gnome-shell-extension-appindicator gnome-extensions-app
# echo "************************ TODO: Open the Extensions app and ensure that AppIndicator and KStatusNotifierItem Support is toggled on before opening the app ************************"


########################## ProtonVPN - Following is an implementation in a slightly better way: 
# We fetch the filename to download instead of hardcoding it so that we always have the latest version.

PROTON_VPN_BASE_URL="https://repo.protonvpn.com/fedora-$FEDORA_RELEASE_VERSION-stable/protonvpn-stable-release"
page="$(curl "$PROTON_VPN_BASE_URL/")"

line=$(echo "$page" | grep ".rpm")
# Sample line:
# <a href="protonvpn-stable-release-1.0.3-1.noarch.rpm">protonvpn-stable-release-1.0.3-1.noarch.rpm</a>        03-Apr-2025 09:24                7765

# get text (filename) between double quotes (from the <a> tag)
FILENAME=${line#*\"}
FILENAME=${FILENAME%\"*}
# echo "URL for downloading ProtonVPN = $PROTON_VPN_BASE_URL/$FILENAME"

# # Download the package that contains the repository configuration and keys required to install the Proton VPN app
wget "$PROTON_VPN_BASE_URL/$FILENAME"

############ Everything below this is same as the OFFICIAL way above

# Install the Proton VPN repository containing the app
sudo dnf install -y ./protonvpn-stable-release-1.0.3-1.noarch.rpm && sudo dnf check-update --refresh 
# Install the app and accept an OpenPGP key.
sudo dnf install -y proton-vpn-gnome-desktop 
# Enable GNOME desktop tray icons
sudo dnf install -y libappindicator-gtk3 gnome-shell-extension-appindicator gnome-extensions-app
echo "************************ TODO: Open the Extensions app and ensure that AppIndicator and KStatusNotifierItem Support is toggled on before opening the app ************************"

