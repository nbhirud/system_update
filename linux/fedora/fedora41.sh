#######################################

sudo dnf install -y git
mkdir -p ~/nb/CodeProjects
cd ~/nb/CodeProjects
git clone https://github.com/nbhirud/system_update.git


# Run this first: linux/fedora/run_first.sh
sudo sh ~/nb/CodeProjects/system_update/linux/fedora/run_first.sh

#######################################

sudo dnf remove -y ptyxis
# remove the gnome terminal ptyxis as we have installed 


#######################################

# Intel/AMD/Nvidia drivers - https://wiki.archlinux.org/title/Hardware_video_acceleration

# Which INTEL driver to install -  check above link
sudo dnf install libva-intel-driver

# For AMD, no need to install anything separately as mesa takes care of it. Check configurations

####################################### Run on bash

# Setup zsh - check linux/common/zsh.sh

####################################### Run on zsh
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


sudo dnf install -y gh keepassxc gnome-tweaks gnome-browser-connector vlc htop fastfetch gparted bleachbit transmission dnfdragora timeshift alacritty

flatpak install -y flathub com.mattjakeman.ExtensionManager com.spotify.Client org.signal.Signal org.gnome.Podcasts de.haeckerfelix.Shortwave com.protonvpn.www me.proton.Mail me.proton.Pass com.bitwarden.desktop
# flatpak install -y flathub ca.desrt.dconf-editor 


#### Kodi
sudo dnf install -y kodi-inputstream-adaptive kodi-firewalld kodi-inputstream-rtmp kodi-platform kodi-pvr-iptvsimple kodi-visualization-spectrum kodi-eventclients kodi

# flatpak install -y tv.kodi.Kodi

# uninstall
# sudo dnf remove kodi kodi-eventclients kodi-firewalld kodi-inputstream-adaptive kodi-inputstream-rtmp kodi-platform  kodi-pvr-iptvsimple kodi-visualization-spectrum 


#######################################

# Configure dns - linux/security_os_level/dns.sh

# Configure firewall - linux/security_os_level/firewalld.sh

# Configure tor - linux/security_os_level/tor.sh

# Configure Anti Virus - linux/security_os_level/clamav.sh

# Configure hosts - linux/security_os_level/hosts.sh

# linux/common/bleachbit.sh
# linux/common/firefox.sh
# linux/common/git.sh
# linux/common/gnome_settings.sh
# linux/common/nerd_fonts.sh
# linux/common/zsh.sh

#######################################

#### GSConnect
# Help - https://github.com/GSConnect/gnome-shell-extension-gsconnect/wiki/Help
# https://github.com/GSConnect/gnome-shell-extension-gsconnect/wiki/Error#openssl-not-found
sudo dnf install openssl
dconf write /org/gnome/shell/disable-user-extensions false
gapplication launch org.gnome.Shell.Extensions.GSConnect # if error, run next line
systemctl --user reload dbus-broker.service

#######################################



#######################################

# Firefox
# First thing to do (STEP 1):
# https://github.com/arkenfox/user.js - The arkenfox user.js is a template which aims to provide as much privacy and enhanced security as possible, and to reduce tracking and fingerprinting as much as possible - while minimizing any loss of functionality and breakage (but it will happen).
# And then:
# Review all settings including labs
# and then:

#######################################

# Ublock Origin - Enable relevant filters
# https://github.com/mchangrh/yt-neuter - Add this filter to ublock origin

# replace hosts file - check ../security_os_level/


####################################### Privacy/youtube extensions - reference: https://www.youtube.com/watch?v=rteYHxcLCZk
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

#######################################

# Optimizing SSD Drive
# sudo systemctl status fstrim.timer
# sudo systemctl enable fstrim.timer


#######################################

# https://brave.com/linux/
sudo dnf install dnf-plugins-core
sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
sudo dnf install -y brave-browser

# Thunderbird
# sudo dnf install thunderbird

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

# sudo dnf install -y python3-spyder # spyder wants to install 599 total packages if installed on my fedora 41, so skip it
# sudo dnf install -y meld
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



#################################################
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
