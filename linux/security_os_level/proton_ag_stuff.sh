#!/bin/sh

echo "************************ Installing proton stuff ************************"
cd $DOWNLOADS_DIR

echo "************************ Installing ProtonAuthenticator ************************"
# https://proton.me/support/set-up-proton-authenticator-linux
# Download the RPM file.
wget https://proton.me/download/authenticator/linux/ProtonAuthenticator.rpm
# Confirm the package’s integrity
echo "<SHA512CheckSum> ProtonAuthenticator.rpm" | sha512sum --check -
wget -O ProtonAuthenticator_version.json https://proton.me/download/authenticator/linux/version.json
echo "************************ To find the SHA512CheckSum for the latest version of this package, open the downloaded $DOWNLOADS_DIR/ProtonAuthenticator_version.json file in a text editor ************************"
sleep 30s
# Install it
sudo dnf install ProtonAuthenticator.rpm

echo "************************ Installing ProtonPass ************************"
# https://proton.me/support/set-up-proton-pass-linux
# Download the RPM file.
wget https://proton.me/download/PassDesktop/linux/x64/ProtonPass.rpm
# Confirm the package’s integrity
echo "<SHA512CheckSum> ProtonPass.rpm" | sha512sum --check -
wget -O ProtonPass_version.json https://proton.me/download/PassDesktop/linux/x64/version.json
echo "************************ To find the SHA512CheckSum for the latest version of this package, open the downloaded $DOWNLOADS_DIR/ProtonPass_version.json file in a text editor ************************"
sleep 30s
# Install it
sudo rpm -i --force ProtonPass.rpm

echo "************************ Installing ProtonVPN ************************"
# https://protonvpn.com/support/official-linux-vpn-fedora/
# Download the package that contains the repository configuration and keys required to install the Proton VPN app
wget "https://repo.protonvpn.com/fedora-$(cat /etc/fedora-release | cut -d' ' -f 3)-stable/protonvpn-stable-release/protonvpn-stable-release-1.0.3-1.noarch.rpm"
# Install the Proton VPN repository containing the app
sudo dnf install -y ./protonvpn-stable-release-1.0.3-1.noarch.rpm && sudo dnf check-update --refresh 
# Install the app and accept an OpenPGP key.
sudo dnf install -y proton-vpn-gnome-desktop 
# Enable GNOME desktop tray icons
sudo dnf install -y libappindicator-gtk3 gnome-shell-extension-appindicator gnome-extensions-app
echo "************************ Open the Extensions app and ensure that AppIndicator and KStatusNotifierItem Support is toggled on before opening the app ************************"
sleep 30s

echo "************************ Installing ProtonMail ************************"
# https://proton.me/support/set-up-proton-mail-linux
# Download the RPM file.
wget https://proton.me/download/mail/linux/ProtonMail-desktop-beta.rpm
# check the RPM file’s integrity
echo "<SHA512CheckSum> ProtonMail-desktop-beta.rpm" | sha512sum --check -
wget -O ProtonMail_version.json https://proton.me/download/mail/linux/version.json
echo "************************ To find the SHA512CheckSum for the latest version of this package, open the downloaded $DOWNLOADS_DIR/ProtonMail_version.json file in a text editor ************************"
sleep 30s
# Install it
sudo dnf install ./ProtonMail-desktop-beta.rpm