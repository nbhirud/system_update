#!/bin/sh

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

echo "************************ Setting User-Defined constants ************************"

HOSTNAME=""
GIT_USER_EMAIL=""
NEXTDNS_ID=""
NEXTDNS_DEVICE_ID="$HOSTNAME"
SETUP_TYPE="light" # full or light (or minimal - TBD - bare minimum, remove all optional stuff)
PC_TYPE="paranoid" # public or private or paranoid

if [ "$GIT_USER_EMAIL" = "" ]; then
  echo "Warning - GIT_USER_EMAIL not provided."
  sleep 5s
fi

if [ "$HOSTNAME" = "" ] || [ "$SETUP_TYPE" = "" ] || [ "$PC_TYPE" = "" ] || [ "$NEXTDNS_ID" = "" ] || [ "$NEXTDNS_DEVICE_ID" = "" ]; then
  echo "Please set User-Defined constants and run again"
  exit 1
fi

echo "************************ Setting INFERRED literals and constants ************************"
HOME_DIR=$(getent passwd $USER | cut -d: -f6)

DESKTOP_DIR="$HOME_DIR/nb/Desktop"
DOCUMENTS_DIR="$HOME_DIR/nb/Documents"
DOWNLOADS_DIR="$HOME_DIR/nb/Downloads"
VIDEOS_DIR="$HOME_DIR/nb/Videos"
PICTURES_DIR="$HOME_DIR/nb/Pictures"
MUSIC_DIR="$HOME_DIR/nb/Music"
PUBLIC_DIR="$HOME_DIR/nb/Public"
TEMPLATES_DIR="$HOME_DIR/nb/Templates"
PROJECTS_DIR="$HOME_DIR/nb/Projects"

SYSUPDATE_CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects/system_update"
# RUN_FIRST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

SCRIPT_BACKUPS_DIR="$HOME_DIR/nb/nb_script_backups" 
SCRIPT_DOWNLOADS_DIR="$HOME_DIR/nb/nb_script_downloads" 

TIMESTAMP_FILENAME="$(date +%Y-%m-%d_%H-%M-%S)"

echo "************************ Create directories ************************"
# TODO - use this downloads dir for downloads of ProtonAG installers, etc
# TODO - Use this backup fir for backup of configs, etc before replacing or editing like .zshrc

mkdir -p $SCRIPT_BACKUPS_DIR $SCRIPT_DOWNLOADS_DIR $DESKTOP_DIR $DOCUMENTS_DIR $DOWNLOADS_DIR $VIDEOS_DIR $PICTURES_DIR $MUSIC_DIR $PUBLIC_DIR $TEMPLATES_DIR $PROJECTS_DIR
sudo chown $USER:$USER $SCRIPT_BACKUPS_DIR $SCRIPT_DOWNLOADS_DIR $DESKTOP_DIR $DOCUMENTS_DIR $DOWNLOADS_DIR $VIDEOS_DIR $PICTURES_DIR $MUSIC_DIR $PUBLIC_DIR $TEMPLATES_DIR $PROJECTS_DIR

echo "************************ Identify Desktop Environment ************************"
DESKTOP=$(sh $SYSUPDATE_CODE_BASE_DIR/linux/common/check_desktop_env.sh)
echo "Desktop Environment is $DESKTOP"

if [ "$DESKTOP" = "" ]; 
then
  echo "Desktop not identified. Fix check_desktop_env.sh and run again"
  exit 1
else
  echo "Desktop is $DESKTOP"
fi

echo "************************ Identify Distro ************************"
# Useful in cases where the common/security/etc scripts need them when they support multiple distros
DISTRO=$(sh $SYSUPDATE_CODE_BASE_DIR/linux/common/get_distro_name.sh)

if [ "$DISTRO" = "" ];
then
  echo "Distro not identified. Fix get_distro_name.sh and run again"
  exit 1
else
  echo "Distro is $DISTRO"
fi


echo "************************ HOME_DIR = $HOME_DIR ************************"
echo "************************ DOWNLOADS_DIR = $DOWNLOADS_DIR ************************"
echo "************************ SYSUPDATE_CODE_BASE_DIR = $SYSUPDATE_CODE_BASE_DIR ************************"
# echo "************************ RUN_FIRST_LOCATION = $RUN_FIRST_DIR ************************" # https://stackoverflow.com/a/246128
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
# https://www.man7.org/linux/man-pages/man5/dnf.conf.5.html
sudo tee /etc/dnf/dnf.conf <<EOL
# see "man dnf.conf" for defaults and possible options

[main]
max_parallel_downloads=5
defaultyes=True
#fastestmirror=True
clean_requirements_on_remove=True
color=always

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

sudo tee /etc/yum.repos.d/vscodium.repo <<'EOF'
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

sudo tee /etc/yum.repos.d/tor.repo <<'EOF'
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
sudo dnf install -y librewolf git mullvad-browser codium flatpak tor torbrowser-launcher
# brave-browser - trying flatpak
# obfs4
# Note: flatpak and git may not come already installed on some flavors like xfce, etc.

echo "************************ Adding docker browser repo (not installing) ************************"
# https://docs.docker.com/engine/install/fedora/
sudo dnf -y install dnf-plugins-core
sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

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
sudo dnf remove -y totem yelp gnome-tour gnome-connections firefox
# remove the gnome terminal ptyxis as we have installed

#######################################

echo "************************ Enabling RPM Fusion ************************"
# Enable RPM Fusion
# https://rpmfusion.org/Configuration

# curl https://rpmfusion.org/Configuration | grep "Fedora with dnf" | grep "sudo dnf install https"

### Configuration of Repositories - https://rpmfusion.org/Configuration

sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm # use bash, not zsh (done above)

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

if [ "$DESKTOP" = "gnome" ]; then
  echo "************************ Changing default downloads directory ************************"
  xdg-user-dirs-update --set DOWNLOAD "$DOWNLOADS_DIR" # Gnome specific

  echo "************************ Enable Minimize or Maximize Window Buttons ************************"
  gsettings set org.gnome.desktop.wm.preferences button-layout "appmenu:minimize,maximize,close"
fi

echo "************************ Rename pc ************************"
sudo hostnamectl set-hostname $HOSTNAME

#######################################

echo "************************ Update hosts file ************************"
sh $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/hosts.sh

echo "************************ Setup nerd fonts ************************"
sh $SYSUPDATE_CODE_BASE_DIR/linux/common/fonts.sh

######################################

echo "************************ Install and configure more dnf packages ************************"
sudo dnf install -y  gh fzf fastfetch bleachbit 
# sudo dnf install -y  gnome-browser-connector dnfdragora transmission
# sudo dnf install -y akregator alligator kasts clementine
# TODO - configure fzf
# Podcasts - gpodder
# nautilus-python - research what this can be used for


if [ "$SETUP_TYPE" = "full" ]; 
then 
  sudo dnf install -y htop keepassxc timeshift qbittorrent vlc

fi


if [ "$DESKTOP" = "gnome" ]
then
  sudo dnf install -y gnome-tweaks 

  if [ "$SETUP_TYPE" = "full" ]; 
  then 
    sudo dnf install -y gparted liferea quiterss
  fi

elif  [ "$DESKTOP" = "kde" ]
then
  echo "Use pre-installed KDE Partition Manager instead of gparted"
  echo "Use pre-installed Kasts instead of Gnome Podcasts"
  echo "Use pre-installed Akregator instead of liferea and quiterss"
fi

echo "************************ Install and configure more flatpak packages ************************"
flatpak install -y flathub com.brave.Browser org.signal.Signal

# TODO - check which brave is installed (flatpak vs dnf) and set following accordingly
# export CHROME_EXECUTABLE=/usr/bin/brave-browser
export CHROME_EXECUTABLE="flatpak run com.brave.Browser"


if [ "$SETUP_TYPE" = "full" ]; 
then 
  flatpak install -y com.rtosta.zapzap com.bitwarden.desktop org.telegram.desktop chat.simplex.simplex io.freetubeapp.FreeTube dev.fredol.open-tv com.spotify.Client app.grayjay.Grayjay

fi


if [ "$DESKTOP" = "gnome" ]
then
  flatpak install -y flathub com.mattjakeman.ExtensionManager 

  if [ "$SETUP_TYPE" = "full" ]; 
  then 
    flatpak install -y flathub org.gnome.Podcasts de.haeckerfelix.Shortwave org.gnome.Fractal
  fi

elif  [ "$DESKTOP" = "kde" ]
then
  # flatpak install -y flathub 

  if [ "$SETUP_TYPE" = "full" ]; 
  then 
    flatpak install -y flathub org.kde.kasts org.kde.neochat
  fi

fi


# com.protonvpn.www me.proton.Mail me.proton.Pass # installing using official instructions via script
# flatpak install -y flathub ca.desrt.dconf-editor com.spotify.Client
# Facebook messenger (deprecated) - com.sindresorhus.Caprine
# element matrix client - im.riot.Riot - too heavy, so install Fractal (or Fluffychat)
# im.fluffychat.Fluffychat
# org.gnome.Fractal - prefer on Gnome
# io.github.kolunmi.Bazaar - an alternative software store from flatpak/flathub
# flatpak install flathub app.grayjay.Grayjay

#######################################
# Some configs

if [ "$DESKTOP" = "gnome" ] || [ "$DESKTOP" = "cosmic" ];
then
  sudo flatpak override --env=SIGNAL_PASSWORD_STORE=gnome-libsecret org.signal.Signal 
  # Do something similar for Element, Telegram, etc

elif  [ "$DESKTOP" = "kde" ]
then
  sudo flatpak override --env=SIGNAL_PASSWORD_STORE=kwallet6 org.signal.Signal
  
fi

#######################################

sh $SYSUPDATE_CODE_BASE_DIR/linux/common/zsh.sh $DISTRO $SETUP_TYPE $DESKTOP $TIMESTAMP_FILENAME

sh $SYSUPDATE_CODE_BASE_DIR/linux/common/alacritty.sh

sh $SYSUPDATE_CODE_BASE_DIR/linux/common/git.sh $GIT_USER_EMAIL

sh $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/proton_ag_stuff.sh $SETUP_TYPE $DESKTOP

sh $SYSUPDATE_CODE_BASE_DIR/linux/common/avahi.sh

sudo sh $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/dns.sh $NEXTDNS_ID $NEXTDNS_DEVICE_ID

#######################################

# Configure firewall - $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/firewalld.sh

# Configure tor - $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/tor.sh

# Configure Anti Virus - $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/clamav.sh

# Firefox, Librewolf, Mullvad browsers - refer $SYSUPDATE_CODE_BASE_DIR/linux/common/firefox.sh

# $SYSUPDATE_CODE_BASE_DIR/linux/common/bleachbit.sh
# $SYSUPDATE_CODE_BASE_DIR/linux/common/gnome_settings.sh

# Thunderbird
# sudo dnf install -y thunderbird

# calendar

# timeshift

# preload equivalent

# set default apps like browser, terminal, etc
# pin apps to dash in right seq
# add apps to app folders in overview

###############################

# TODO - Edit nbclean for cosmic
# sudo bleachbit doesn'tt work idirectly on cosmic. it blames wayland. Surround it with commands as follows to use xwayland
# https://docs.bleachbit.org/doc/frequently-asked-questions.html
# https://wiki.archlinux.org/title/Running_GUI_applications_as_root
# xhost si:localuser:root && sudo bleachbit --clean --preset && xhost -si:localuser:root


sudo tee -a ~/.zshrc <<'ZSHRC_EOF'

#################################################################
# Added by nbhirud:
#################################################################

### Custom linux aliases - add to ~/.zshrc

# Application shortcuts:
# alias codium="flatpak run com.vscodium.codium "

# Update/Upgrade related:
# alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && sudo freshclam && omz update -y && . torsocks on && fastfetch"
# freshclam is a service now
alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && omz update -y && . torsocks on && fastfetch"
alias nbupdateproton=". torsocks off && cd /home/nbhirud/nb/CodeProjects/system_update/ && sh /home/nbhirud/nb/CodeProjects/system_update/linux/security_os_level/proton_ag_stuff.sh && cd && . torsocks on"


# https://docs.fedoraproject.org/en-US/quick-docs/upgrading-fedora-offline/
# alias nbdistu="sudo sudo dnf upgrade --refresh -y && sudo sudo dnf system-upgrade download --releasever=43 -y"
alias nbreload="systemctl daemon-reload && source ~/.zshrc"
alias nbclean="sync && sudo bleachbit --clean --preset && bleachbit --clean --preset && dnf clean -y all && yum clean -y all && flatpak uninstall --unused && sudo resolvectl flush-caches && sudo resolvectl reset-statistics"
alias nbtoron=". torsocks on"
alias nbtoroff=". torsocks off"
alias nbshutdown="nbupdate && nbclean && shutdown"
alias nbreboot="nbupdate && nbclean && reboot"

### Stuff other than aliases:
autoload -U compinit; compinit
source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab/fzf-tab.plugin.zsh
. torsocks on

# TODO: ##############################
# Add to nbclean - clean old kernels script invocation
# Add to nbUpdate? - update fonts - invocation from this repo dir - use linux/common/git_repo_update_checker.sh maybe?
# Add to nbReboot - update hosts
# Add to nbReboot - update dnsmasq blocklists
# Or maybe most of these just need to be cron jobs? (linux/common/cron_jobs.sh)

#################################################################

ZSHRC_EOF

#######################################

echo "************************ Update and upgrade everything ************************"
# sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y

# Following was a failed attempt into opening alacritty via ptyxis and then removing ptyxis from alacritty
# alacritty -e zsh -c "sudo dnf update -y && sudo dnf upgrade --refresh -y && sudo dnf remove -y ptyxis; exec zsh"
# alacritty -e zsh -c "echo "Hi"; exec zsh"

#######################################

# TODO
# firefox config
# gnome config
# kde config
# dns (this is different from hosts)
# firewalld
# ufw
# clamav
# tor config
# aliases like nbupdate, etc
# install dnf packages
# install flatpak apps
# TODO cron jobs - linux/common/cron_jobs.sh
# brave config
# VSCodium config

#####################################33

# Some OSes to try:
# CachyOS, omarchy
