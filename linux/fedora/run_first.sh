#!/bin/bash

# https://www.baeldung.com/linux/set-command
set -eux

#######################################

# Benefits:
# 1. Don't have to manually type each command and make some mistakes
# 2. Don't have to enter credentials lot of times, just once in the beginning is enough
# 3. Save time

#######################################
echo "************************ NOTE: The script will ask you to authenticate multiple times till the end. ************************"
sleep 5s

echo "************************ Setting literals and constants ************************"
HOME_DIR=$(getent passwd $USER | cut -d: -f6)
DOWNLOADS_DIR="$HOME_DIR/nb/Downloads"
SYSUPDATE_CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects/system_update"
RUN_FIRST_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

echo "************************ HOME_DIR = $HOME_DIR ************************"
echo "************************ DOWNLOADS_DIR = $DOWNLOADS_DIR ************************"
echo "************************ SYSUPDATE_CODE_BASE_DIR = $SYSUPDATE_CODE_BASE_DIR ************************"
echo "************************ RUN_FIRST_LOCATION = $RUN_FIRST_DIR ************************" # https://stackoverflow.com/a/246128
sleep 5s

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
sudo tee /etc/dnf/dnf.conf <<EOL
# see "man dnf.conf" for defaults and possible options

[main]
max_parallel_downloads=5
defaultyes=True
fastestmirror=True    

EOL

#######################################
# LibreWolf, Mullvad browser, codium, etc
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

sudo tee /etc/yum.repos.d/vscodium.repo << 'EOF'
[gitlab.com_paulcarroty_vscodium_repo]
name=gitlab.com_paulcarroty_vscodium_repo
baseurl=https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/rpms/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
metadata_expire=1h
EOF

echo "************************ Adding Tor repo ************************"
# Tor - https://community.torproject.org/relay/setup/bridge/fedora/

sudo tee /etc/yum.repos.d/tor.repo << 'EOF'
[tor]
name=Tor for Fedora $releasever - $basearch
baseurl=https://rpm.torproject.org/fedora/$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=https://rpm.torproject.org/fedora/public_gpg.key
cost=100
EOF

echo "************************ Adding brave browser repo ************************"
# https://brave.com/linux/
sudo dnf install dnf-plugins-core
sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo

echo "************************ Installing packages ************************"
# install the packages
sudo dnf install -y librewolf git mullvad-browser codium flatpak tor torbrowser-launcher brave-browser # obfs4
# Note: flatpak and git may not come already installed on some flavors like xfce, etc.




# echo "************************ Edit your Tor config ************************"
# echo "************************ TODO - Don't forget to change the TODO1 options in Tor config. ************************"
# sudo tee /etc/tor/torrc << 'EOF'
# RunAsDaemon 1
# BridgeRelay 1

# # Replace "TODO1" with a Tor port of your choice.  This port must be externally
# # reachable.  Avoid port 9001 because it's commonly associated with Tor and
# # censors may be scanning the Internet for this port.
# ORPort TODO1
# EOF

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
# flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

#######################################

# Change default downloads dir:
mkdir -p $DOWNLOADS_DIR
sudo chown $USER:$USER $DOWNLOADS_DIR
echo "************************ Home directory is: $HOME_DIR ************************"

echo "************************ Identify Desktop Environment ************************"
DESKTOP=$(sh $SYSUPDATE_CODE_BASE_DIR/linux/common/check_desktop_env.sh)
echo "Desktop Environment is $DESKTOP"

if [ "$DESKTOP" = "gnome" ]
then
    echo "************************ Changing default downloads directory ************************"
    xdg-user-dirs-update --set DOWNLOAD "$DOWNLOADS_DIR" # Gnome specific

    echo "************************ Enable Minimize or Maximize Window Buttons ************************"
    gsettings set org.gnome.desktop.wm.preferences button-layout "appmenu:minimize,maximize,close"
fi

echo "************************ Rename pc ************************"
HOSTNAME="nbFedora"
sudo hostnamectl set-hostname $HOSTNAME

#######################################

echo "************************ Update hosts file ************************"
sh $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/hosts.sh

echo "************************ Setup nerd fonts ************************"
sh $SYSUPDATE_CODE_BASE_DIR/linux/common/fonts.sh

#######################################

echo "************************ Install and configure more dnf packages ************************"
sudo dnf install -y htop gh fzf keepassxc gnome-tweaks vlc fastfetch gparted bleachbit transmission timeshift
# sudo dnf install -y  gnome-browser-connector dnfdragora
# TODO - configure fzf

echo "************************ Install and configure more flatpak packages ************************"
flatpak install -y flathub com.mattjakeman.ExtensionManager org.signal.Signal org.gnome.Podcasts de.haeckerfelix.Shortwave com.protonvpn.www me.proton.Mail me.proton.Pass com.bitwarden.desktop org.telegram.desktop com.sindresorhus.Caprine
# flatpak install -y flathub ca.desrt.dconf-editor com.spotify.Client


# EXPERIMENTAL
sh $SYSUPDATE_CODE_BASE_DIR/linux/common/zsh.sh

# EXPERIMENTAL
sh $SYSUPDATE_CODE_BASE_DIR/linux/common/alacritty.sh

# EXPERIMENTAL
sh $SYSUPDATE_CODE_BASE_DIR/linux/common/git.sh


###############################
# Configure dns - $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/dns.sh

# Configure firewall - $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/firewalld.sh

# Configure tor - $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/tor.sh

# Configure Anti Virus - $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/clamav.sh

# Configure hosts - $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/hosts.sh

# Firefox, Librewolf, Mullvad browsers - refer $SYSUPDATE_CODE_BASE_DIR/linux/common/firefox.sh

# $SYSUPDATE_CODE_BASE_DIR/linux/common/bleachbit.sh
# $SYSUPDATE_CODE_BASE_DIR/linux/common/git.sh
# $SYSUPDATE_CODE_BASE_DIR/linux/common/gnome_settings.sh
# $SYSUPDATE_CODE_BASE_DIR/linux/common/nerd_fonts.sh
# $SYSUPDATE_CODE_BASE_DIR/linux/common/zsh.sh

# Thunderbird
# sudo dnf install thunderbird

# calendar

# timeshift

# preload equivalent


###############################



sudo tee -a ~/.zshrc << 'ZSHRC_EOF'

#################################################################
# Added by nbhirud manually:
#################################################################

### Custom linux aliases - add to ~/.zshrc

# Application shortcuts:
# alias codium="flatpak run com.vscodium.codium "

# Update/Upgrade related:
# alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && sudo freshclam && omz update -y && . torsocks on && fastfetch"
# freshclam is a service now
alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && omz update -y && . torsocks on && fastfetch"
# alias nbdistu="sudo apt dist-upgrade -y && sudo do-release-upgrade"
alias nbreload="systemctl daemon-reload && source ~/.zshrc"
alias nbclean="sync && sudo bleachbit --clean --preset && bleachbit --clean --preset && dnf clean -y all && yum clean -y all && flatpak uninstall --unused"
alias nbtoron=". torsocks on"
alias nbtoroff=". torsocks off"
alias nbshutdown="nbupdate && nbclean && shutdown"
alias nbreboot="nbupdate && nbclean && reboot"

### Stuff other than aliases:
autoload -U compinit; compinit
source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab/fzf-tab.plugin.zsh
. torsocks on

#################################################################

ZSHRC_EOF


#######################################

echo "************************ Update and upgrade everything ************************"
sudo dnf update -y && sudo dnf upgrade --refresh -y


# TODO
# firefox
# gnome
# kde
# dns (this is different from hosts)
# firewalld
# ufw
# clamav
# tor
# aliases like nbupdate, etc
# install dnf packages
# install flatpak apps
# TODO cron jobs - linux/common/cron_jobs.sh
# brave

