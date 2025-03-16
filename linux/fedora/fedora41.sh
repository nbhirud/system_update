#######################################

sudo dnf install -y git
mkdir -p ~/nb/CodeProjects
cd ~/nb/CodeProjects
git clone https://github.com/nbhirud/system_update.git


# Run this first: linux/fedora/run_first.sh
sudo sh ~/nb/CodeProjects/linux/fedora/run_first.sh

#######################################



############# bash

# Setup zsh - check linux/common/zsh.sh

####################### zsh
echo $SHELL

# Enable Minimize or Maximize Window Buttons
gsettings set org.gnome.desktop.wm.preferences button-layout "appmenu:minimize,maximize,close"


### mount nb HDD and change ownership
# Disks app -> select nb HDD -> 3 gears -> edit mountpoint -> set mountpoint as /home/nbhirud/nb
sudo umount /home/nbhirud/nb
sudo chown -R nbhirud:nbhirud nb
sudo mount -va

### Fonts Setup
# Refer linux/common/nerd_fonts.sh

#######################################

### VSCode: (somethimes you need it)
# https://code.visualstudio.com/docs/setup/linux#_rhel-fedora-and-centos-based-distributions

# # Install the key and yum repository by running the following script:
# sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
# echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null

# # Then update the package cache and install the package using dnf
# dnf check-update
# sudo dnf install code # or code-insiders


#######################################


### rename pc
sudo hostnamectl set-hostname "nbFedora"

# Install software


sudo dnf install -y gh keepassxc gnome-tweaks gnome-browser-connector vlc htop fastfetch gparted bleachbit transmission dnfdragora timeshift alacritty torbrowser-launcher

flatpak install -y flathub com.mattjakeman.ExtensionManager com.spotify.Client org.signal.Signal org.gnome.Podcasts de.haeckerfelix.Shortwave com.protonvpn.www me.proton.Mail me.proton.Pass com.bitwarden.desktop
# flatpak install -y flathub ca.desrt.dconf-editor 


#### Kodi
sudo dnf install -y kodi-inputstream-adaptive kodi-firewalld kodi-inputstream-rtmp kodi-platform kodi-pvr-iptvsimple kodi-visualization-spectrum kodi-eventclients kodi

# flatpak install -y tv.kodi.Kodi

# uninstall
# sudo dnf remove kodi kodi-eventclients kodi-firewalld kodi-inputstream-adaptive kodi-inputstream-rtmp kodi-platform  kodi-pvr-iptvsimple kodi-visualization-spectrum 


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
# alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && sudo freshclam && omz update -y && . torsocks on && fastfetch"
# freshclam is a service now
alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && omz update -y && . torsocks on && fastfetch"
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

# add poetry completions - check linux/common/zsh.sh


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


#############


# Also see
# https://www.hackingthehike.com/fedora-41-after-install-guide/
# https://itsfoss.com/things-to-do-after-installing-fedora/
# https://www.fosslinux.com/139829/top-apps-for-fedora-linux.htm
# https://www.debugpoint.com/10-things-to-do-fedora-40-after-install/
# https://orcacore.com/add-essential-software-repositories-on-fedora-linux/
# https://arcanesavant.github.io/p/2024/10/31/12-things-to-do-after-installing-fedora-workstation-41/
# https://losst.pro/en/how-to-configure-fedora-41-after-install
# https://dev.to/alexantartico/after-installing-fedora-41-a-glorious-adventure-awaits-3anc
# https://www.linuxfordevices.com/tutorials/after-install-fedora

# https://discussion.fedoraproject.org/t/my-config-tweak-notes-for-fedora-41/134840
# https://wiki.realmofespionage.xyz/start
# https://discussion.fedoraproject.org/t/my-config-tweak-notes-for-fedora-41/134840
# https://wiki.realmofespionage.xyz/linux:distros:fedora_workstation_gnome#spinesnap

# https://www.server-world.info/en/note?os=Fedora_41
# https://www.server-world.info/en/note?os=Fedora_41&p=initial_conf&f=2


# List of available COPRs - https://copr.fedorainfracloud.org/coprs/
# Example - https://copr.fedorainfracloud.org/coprs/kylegospo/preload/


#### Fedora 41 server
# https://docs.fedoraproject.org/en-US/fedora-server/installation/
# https://www.tecmint.com/fedora-server-installation-guide/
# https://www.server-world.info/en/note?os=Fedora_41&p=install
# https://www.linuxtoday.com/developer/how-to-install-fedora-41-server-with-screenshots/
# https://www.linuxquestions.org/questions/linux-general-1/fedora-41-minimal-install-guide-with-samba-and-windows-shares-active-4175746330/
# https://oracle-base.com/articles/linux/fedora-41-installation
