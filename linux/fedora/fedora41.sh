############# bash

sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

echo $SHELL
sudo dnf install -y zsh autojump
chsh -s $(which zsh)
zsh

####################### zsh
echo $SHELL

# Change default downloads dir:
xdg-user-dirs-update --set DOWNLOAD "/home/nbhirud/nb/Downloads"

# Enable Minimize or Maximize Window Buttons
gsettings set org.gnome.desktop.wm.preferences button-layout "appmenu:minimize,maximize,close"


### OMZ
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

cd $ZSH_CUSTOM/plugins
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

cd
nano .zshrc
# do changes in .zshrc
omz update
source ~/.zshrc

### mount nb HDD and change ownership
# Disks app -> select nb HDD -> 3 gears -> edit mountpoint -> set mountpoint as /home/nbhirud/nb
sudo umount /home/nbhirud/nb
sudo chown -R nbhirud:nbhirud nb
sudo mount -va

### Fonts
mkdir nb
mkdir nb/CodeProjects
cd nb/CodeProjects

git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git

cd nerd-fonts
find . -name "*.md" -type f -delete
find . -name "*.txt" -type f -delete
find . -name "LICENSE" -type f -delete
find . -name ".uuid" -type f -delete

mkdir -p ~/.local/share/fonts # this fonts folder is absent by default
cp ~/nb/CodeProjects/nerd-fonts/patched-fonts ~/.local/share/fonts/nerd-fonts -r
rm -rf ~/nb/CodeProjects/nerd-fonts

fc-cache -fr
fc-list | grep "JetBrains"


### VSCodium

sudo rpmkeys --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg

printf "[gitlab.com_paulcarroty_vscodium_repo]\nname=download.vscodium.com\nbaseurl=https://download.vscodium.com/rpms/\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg\nmetadata_expire=1h" | sudo tee -a /etc/yum.repos.d/vscodium.repo

sudo dnf install codium


### Configuration of Repositories - https://rpmfusion.org/Configuration

sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm # use bash, not zsh (done above)

sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
sudo dnf update @core

### Multimedia on Fedora - https://rpmfusion.org/Howto/Multimedia 
sudo dnf swap ffmpeg-free ffmpeg --allowerasing
sudo dnf update @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin

# Which intel driver to install -  https://wiki.archlinux.org/title/Hardware_video_acceleration
sudo dnf install libva-intel-driver

### Codecs - https://docs.fedoraproject.org/en-US/quick-docs/installing-plugins-for-playing-movies-and-music/
sudo dnf group install multimedia

sudo dnf update -y && sudo dnf upgrade --refresh -y


### Enable flatpak flathub
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

### rename pc
sudo hostnamectl set-hostname "nbFedora"

# Install software


sudo dnf install -y gh keepassxc gnome-tweaks gnome-browser-connector vlc htop fastfetch gparted bleachbit transmission dnfdragora timeshift alacritty torbrowser-launcher

flatpak install -y flathub com.mattjakeman.ExtensionManager com.spotify.Client org.signal.Signal org.gnome.Podcasts de.haeckerfelix.Shortwave com.protonvpn.www me.proton.Mail me.proton.Pass com.bitwarden.desktop
# flatpak install -y flathub ca.desrt.dconf-editor 


##### LibreWolf - https://librewolf.net/installation/fedora/
# add the repo
curl -fsSL https://repo.librewolf.net/librewolf.repo | pkexec tee /etc/yum.repos.d/librewolf.repo
# install the package
sudo dnf install librewolf

#### Kodi
sudo dnf install -y kodi-inputstream-adaptive kodi-firewalld kodi-inputstream-rtmp kodi-platform kodi-pvr-iptvsimple kodi-visualization-spectrum kodi-eventclients kodi

# flatpak install -y tv.kodi.Kodi

# uninstall
# sudo dnf remove kodi kodi-eventclients kodi-firewalld kodi-inputstream-adaptive kodi-inputstream-rtmp kodi-platform  kodi-pvr-iptvsimple kodi-visualization-spectrum 

# remove stuff
sudo dnf remove -y  totem yelp gnome-tour gnome-connections ptyxis 
# remove the gnome terminal ptyxis as we have installed alacritty


######################
sudo nano /etc/yum.repos.d/tor.repo

# [tor]
# name=Tor for Fedora $releasever - $basearch
# baseurl=https://rpm.torproject.org/fedora/$releasever/$basearch
# enabled=1
# gpgcheck=1
# gpgkey=https://rpm.torproject.org/fedora/public_gpg.key
# cost=100


dnf install tor -y


sudo nano /etc/tor/torrc

# Note: ExitNodes is what shows up as your location
# LOL
# EntryNodes {sg}{ae}{sa}{tr}{tw}{aq} StrictNodes 1
# MiddleNodes {in}{ru}{su}{cn}{ir} StrictNodes 1
# ExitNodes {ca}{us}{uk}{au} StrictNodes 1
sudo systemctl enable tor
sudo systemctl start tor
# sudo systemctl reload tor

source torsocks on
echo ". torsocks on" >> ~/.bashrc
echo ". torsocks on" >> ~/.zshrc


#### GSConnect
# Help - https://github.com/GSConnect/gnome-shell-extension-gsconnect/wiki/Help
# https://github.com/GSConnect/gnome-shell-extension-gsconnect/wiki/Error#openssl-not-found
sudo dnf install openssl
dconf write /org/gnome/shell/disable-user-extensions false
gapplication launch org.gnome.Shell.Extensions.GSConnect # if error, run next line
systemctl --user reload dbus-broker.service


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

###########################

# Firefox
# First thing to do (STEP 1):
# https://github.com/arkenfox/user.js - The arkenfox user.js is a template which aims to provide as much privacy and enhanced security as possible, and to reduce tracking and fingerprinting as much as possible - while minimizing any loss of functionality and breakage (but it will happen).
# And then:
# Review all settings including labs
# and then:



# Ublock Origin - Enable relevant filters
# https://github.com/mchangrh/yt-neuter - Add this filter to ublock origin

# replace hosts file - check ../security_os_level/


##### Privacy/youtube extensions - reference: https://www.youtube.com/watch?v=rteYHxcLCZk
# https://github.com/mchangrh/yt-neuter
#Return YouTube Dislike: https://returnyoutubedislike.com/
#SponsorBlock: https://sponsor.ajay.app/
#Dearrow (clickbait remover): https://dearrow.ajay.app/
#Unhook: https://unhook.app/
#uBlock Origin: https://ublockorigin.com/
#uBO troubleshooting:   / megathread
#uBO status: https://drhyperion451.github.io/does-...
#Hide YouTube Shorts: https://github.com/gijsdev/ublock-hid...
#NewPipe: https://newpipe.net/


# Optimizing SSD Drive
# sudo systemctl status fstrim.timer
# sudo systemctl enable fstrim.timer



# https://mullvad.net/en/download/browser/linux
# Add the Mullvad repository server to dnf
sudo dnf config-manager addrepo --from-repofile=https://repository.mullvad.net/rpm/stable/mullvad.repo
# Install the package
sudo dnf install mullvad-browser


# https://brave.com/linux/
sudo dnf install dnf-plugins-core
sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
sudo dnf install brave-browser

# Thunderbird
sudo dnf install thunderbird

# calendar

# timeshift

# preload equivalent



#################################################################
# Added by nbhirud manually:
#################################################################

### Custom linux aliases - add to ~/.zshrc

# Application shortcuts:
# alias codium="flatpak run com.vscodium.codium "

# Update/Upgrade related:
alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && sudo freshclam && omz update -y && . torsocks on && fastfetch"
# alias nbdistu="sudo apt dist-upgrade -y && sudo do-release-upgrade"
alias nbreload="systemctl daemon-reload && source ~/.zshrc"
alias nbclean="dnf clean -y all && yum clean -y all && flatpak uninstall --unused"
alias nbtoron=". torsocks on"
alias nbtoroff=". torsocks off"

### Stuff other than aliases:
. torsocks on




##############################################################
##############################################################
##############################################################
##############################################################


# import Kodi backup

# spyder, meld, poetry

sudo dnf install -y python3-spyder meld
# sudo dnf install -y python3-poetry # install using pipx instead as below?

# pipx - https://pipx.pypa.io/stable/installation/
sudo dnf install pipx
pipx ensurepath

# poetry - https://python-poetry.org/docs/#installing-with-pipx
pipx install poetry
# pipx upgrade poetry
# pipx uninstall poetry
mkdir $ZSH_CUSTOM/plugins/poetry
poetry completions zsh > $ZSH_CUSTOM/plugins/poetry/_poetry
# add poetry in OMZ plugins array

### Interesting/Useful Oh My ZSH plugins
# python related: autopep8 conda conda-env dotenv pep8 pip pipenv poetry poetry-env pyenv pylint python virtualenvwrapper
# fedora related: dnf yum
# linux (general) related: colored-man-pages colorize history history-substring-search perms safe-paste screen sudo systemadmin systemd 
# security: firewalld gpg-agent keychain ufw
# git related: branch gh git git-auto-fetch git-commit git-escape-magic gitfast github gitignore git-prompt  pre-commit
# cloud and containers: aws docker docker-compose helm kops kubectl kubectx podman terraform toolbox
# database related: mongocli postgres
# misc: isodate jsontools rsync rust thefuck timer torrent transfer universalarchive urltools vscode web-search wp-cli zsh-interactive-cd zsh-navigation-tools



# DBeaver
flatpak install flathub io.dbeaver.DBeaverCommunity


# vpn via network settings - skip


#################################################################


# # UFW
# # Recommended rules from https://christitus.com/linux-security-mistakes/
# sudo ufw limit 22/tcp
# sudo ufw allow 80/tcp
# sudo ufw allow 443/tcp
# sudo ufw default deny incoming
# sudo ufw default allow outgoing
# # Enable ufw
# sudo ufw enable
# #sudo systemctl enable ufw # Didn't work for some reason
# #sudo systemctl start ufw # Didn't work for some reason
# # sudo ufw status numbered
# # sudo ufw delete 7 # Use numbers from above numbered command



###### firewalld #TODO
# https://www.redhat.com/en/blog/how-to-configure-firewalld

sudo dnf install firewall-config # GUI

## basic commands
systemctl status firewalld
# systemctl start --now firewalld
systemctl enable --now firewalld
# systemctl stop firewalld
# systemctl restart firewalld

## config

firewall-cmd --state
# firewall-cmd --reload
firewall-cmd --list-all






# GSConnect firewalld rules
firewall-cmd --permanent --zone=public --add-service=kdeconnect 
firewall-cmd --reload


# SELinux

sudo dnf update -y && sudo dnf upgrade --refresh -y

# reboot
sudo reboot


###################################################

# One of the VPN options - Proton
# https://protonvpn.com/support/linux-openvpn/
# https://protonvpn.com/support/official-linux-vpn-fedora/
# https://protonvpn.com/support/linux-vpn-setup/

# Another option - Nord

###################################################

# btop like htop

###################################################

# Alacritty config
# https://alacritty.org/config-alacritty.html
