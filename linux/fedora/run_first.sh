#!/bin/bash

# https://www.baeldung.com/linux/set-command
set -eux

#######################################

# Benefits:
# 1. Don't have to manually type each command and make some mistakes
# 2. Don't have to enter credentials lot of times, just once in the beginning is enough
# 3. Save time

#######################################

echo "************************ Updating /etc/dnf/dnf.conf ************************"
# Configurations to dnf
# https://dnf.readthedocs.io/en/latest/conf_ref.html
# sudo nano /etc/dnf/dnf.conf
# fastestmirror=True
# max_parallel_downloads=5
# defaultyes=True

# Another way
# echo 'fastestmirror=True' | sudo tee -a /etc/dnf/dnf.conf
# echo 'max_parallel_downloads=5' | sudo tee -a /etc/dnf/dnf.conf
# echo 'defaultyes=True' | sudo tee -a /etc/dnf/dnf.conf

# Configure DNF settings
sudo tee -a /etc/dnf/dnf.conf <<EOL
max_parallel_downloads=5
defaultyes=True
fastestmirror=True
EOL

#######################################
# LibreWolf, Mullvad browser and alacritty
#######################################

echo "************************ Adding Librewolf repo ************************"
# LibreWolf - https://librewolf.net/installation/fedora/
# add the repo

# cd
# mkdir -p nb/temp
# cd nb/temp
# wget https://librewolf.net/installation/fedora/
# cat index.html | grep pkexec

# add the repo
curl -fsSL https://repo.librewolf.net/librewolf.repo | pkexec tee /etc/yum.repos.d/librewolf.repo


echo "************************ Adding Mullvad repo ************************"
# https://mullvad.net/en/download/browser/linux
# Add the Mullvad repository server to dnf
# curl https://mullvad.net/en/download/browser/linux | grep addrepo
sudo dnf config-manager addrepo --from-repofile=https://repository.mullvad.net/rpm/stable/mullvad.repo


echo "************************ Adding VSCodium repo ************************"
### VSCodium
# https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo

sudo tee -a /etc/yum.repos.d/vscodium.repo << 'EOF'
[gitlab.com_paulcarroty_vscodium_repo]
name=gitlab.com_paulcarroty_vscodium_repo
baseurl=https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/rpms/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
metadata_expire=1h
EOF


echo "************************ Installing packages ************************"
# install the package
sudo dnf install -y librewolf alacritty git mullvad-browser codium

#######################################

echo "************************ Removing packages ************************"
# remove stuff
sudo dnf remove -y  totem yelp gnome-tour gnome-connections firefox
# remove the gnome terminal ptyxis as we have installed 

#######################################

echo "************************ Enabling RPM Fusion ************************"
# Enable RPM Fusion
# https://rpmfusion.org/Configuration

# curl https://rpmfusion.org/Configuration | grep "Fedora with dnf" | grep "sudo dnf install https"

### Configuration of Repositories - https://rpmfusion.org/Configuration

sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm # use bash, not zsh (done above)

echo "************************ Configuring @core ************************"
sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
sudo dnf update -y @core

echo "************************ Configuring Multimedia on Fedora ************************"
### Multimedia on Fedora - https://rpmfusion.org/Howto/Multimedia 
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin

echo "************************ Configuring Codecs ************************"
### Codecs - https://docs.fedoraproject.org/en-US/quick-docs/installing-plugins-for-playing-movies-and-music/
sudo dnf group install -y multimedia

#######################################

echo "************************ Enabling flatpak flathub ************************"
### Enable flatpak flathub
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

#######################################

echo "************************ Changing default downloads dir ************************"
# Change default downloads dir:
mkdir -p /home/nbhirud/nb/Downloads
# TODO - add condition to check if current DE is Gnome
echo $XDG_CURRENT_DESKTOP
echo $DESKTOP_SESSION
echo $GDMSESSION
xdg-user-dirs-update --set DOWNLOAD "/home/nbhirud/nb/Downloads" # Gnome specific

#######################################

echo "************************ Update and upgrade everything ************************"
sudo dnf update -y && sudo dnf upgrade --refresh -y

#######################################

echo "************************ Update hosts file ************************"
sudo sh linux/security_os_level/hosts.sh

echo "************************ Setup nerd fonts ************************"
# Experimental
sh linux/common/fonts.sh

#######################################

echo "************************ Install and configure more packages ************************"

sudo dnf install -y htop

# TODO - check if the following invocation works
# sudo sh linux/common/zsh.sh

