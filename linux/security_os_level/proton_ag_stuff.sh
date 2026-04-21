#!/bin/sh

# Do not run as root

# ################# The following isn't POSIX compliant because EUID is undefined in POSIX
# # https://www.baeldung.com/linux/check-script-run-root
# if [ ${EUID:-0} -eq 0 ] || [ "$(id -u)" -eq 0 ]; then
#   echo "[-] Do not run as root (or with sudo)."
#   exit 1
# else
#     echo "You are running as $(whoami)"
# fi

# ################# The following isn't POSIX compliant because EUID is undefined in POSIX. This is a shorter version of above
# # bool function to test if the user is root or not
# is_user_root () { [ "${EUID:-$(id -u)}" -eq 0 ]; }

# ################# The following is POSIX compliant
# bool function to test if the user is root or not (POSIX only)
is_user_root ()
{
    [ "$(id -u)" -eq 0 ]
}

# ################# The following is example usage of POSIX compliant function above
# if is_user_root; then
#     echo 'You are the almighty root!'
#     # You can do whatever you need...
# else
#     echo 'You are just an ordinary user.' >&2
#     exit 1
# fi

if ! is_user_root; then
	echo "You are running as $(whoami)"
else
  echo "[-] Do not run as root (or with sudo)."
  exit 1
fi

set -eux


################################################
# TODO - implement the following:
# 
# 1. ProtonPass versions json had "RolloutPercentage" as 0.05. So the wget ProtonPass.rpm kept getting the 0.95 percent rpm, but the SHA script kept returning SHA of 0.05 percent rpm as it was the latest version. So Strategy should be to first find the latest version, and return the corresponding "Url" and "Sha512CheckSum" for the *.rpm URL. Use this returned URL to download the rpm file:
  # "Releases": [
  #   {
  #     "CategoryName": "Stable",
  #     "Version": "1.35.0",
  #     "ReleaseDate": "2026-03-09T10:47:04Z",
  #     "RolloutPercentage": 0.05,
  #     "File": [
#
#
# 2. Somethimes, the latest version will have "CategoryName" as something other than "Stable". Skip those non-stable versions while fetching SHA:
  # "Releases": [
  #   {
  #     "CategoryName": "Stable",
#
#
################################################

echo "************************ Setting literals and constants ************************"
HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)

CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects"
SYSUPDATE_SEC_CODE_DIR="$CODE_BASE_DIR/system_update/linux/security_os_level/"
SYSUPDATE_FEDORA_CODE_DIR="$CODE_BASE_DIR/system_update/linux/fedora/"

DOWNLOADS_DIR="$HOME_DIR/nb/Downloads"
DOWNLOADS_DIR_PROTON="$DOWNLOADS_DIR/ProtonAG/proton_ag_downloads_$(date +%Y-%m-%d_%H-%M-%S)"

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
# Calculate *.rpm file's SHA for debugging:
SHA_CALCULATED_PROTAUTH=$(sha512sum ProtonAuthenticator.rpm)
echo "Calculated SHA512sum of *.rpm file = $SHA_CALCULATED_PROTAUTH" 
# Confirm the package’s integrity
echo "$SHA_ProtonAuthenticator" ProtonAuthenticator.rpm | sha512sum --check -
# Install it
sudo dnf install -y ProtonAuthenticator.rpm


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
# Calculate *.rpm file's SHA for debugging:
SHA_CALCULATED_PROTPASS=$(sha512sum ProtonPass.rpm)
echo "Calculated SHA512sum of *.rpm file = $SHA_CALCULATED_PROTPASS" 
# Confirm the package’s integrity
echo "$SHA_ProtonPass ProtonPass.rpm" | sha512sum --check -
# Install it
# sudo rpm -i --force ProtonPass.rpm # OFFICIAL way, but RedHat seems to discourage this usage
sudo dnf install -y ProtonPass.rpm


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
# Calculate *.rpm file's SHA for debugging:
SHA_CALCULATED_PROTMAIL=$(sha512sum ProtonMail-desktop-beta.rpm)
echo "Calculated SHA512sum of *.rpm file = $SHA_CALCULATED_PROTMAIL" 
# check the RPM file’s integrity
echo "$SHA_ProtonMail ProtonMail-desktop-beta.rpm" | sha512sum --check -
# Install it
sudo dnf install -y ./ProtonMail-desktop-beta.rpm


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
sudo dnf install -y ./protonvpn-stable-release-1.0.3-1.noarch.rpm # && sudo dnf check-update --refresh 
# Install the app and accept an OpenPGP key.
sudo dnf install -y proton-vpn-gnome-desktop 
# Enable GNOME desktop tray icons
sudo dnf install -y libappindicator-gtk3 gnome-shell-extension-appindicator # gnome-extensions-app
echo "************************ TODO: Open the Extensions app and ensure that AppIndicator and KStatusNotifierItem Support is toggled on before opening the app ************************"


######################### ProtonMeet ###################################################################
echo "************************ Installing ProtonMeet ************************"
# https://proton.me/meet/download
# Download the RPM file.
wget https://proton.me/download/meet/linux/1.0.8/ProtonMeet-desktop.rpm
# Install it
sudo dnf install -y ./ProtonMeet-desktop.rpm
echo "Note: TODO: Check if Proton has made available the SHA for ProtonMeet rpm yet. Also, there is no good way to automate getting the latest rpm"

