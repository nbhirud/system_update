
# The following has been tested on:
# Fedora Linux 40 (Workstation Edition) x86_64

#######################################################

### Shell

# bash
# sudo dnf install bash-completion

# Zsh - Check linux/common/zsh.sh

#######################################################

# Configurations to dnf
# https://dnf.readthedocs.io/en/latest/conf_ref.html
# sudo nano /etc/dnf/dnf.conf
# fastestmirror=True
# max_parallel_downloads=5
# defaultyes=True

# Another way
# echo 'fastestmirror=1' | sudo tee -a /etc/dnf/dnf.conf
# echo 'max_parallel_downloads=10' | sudo tee -a /etc/dnf/dnf.conf

sudo dnf update -y && sudo dnf upgrade --refresh -y

#######################################################

# Get this repo
which git || sudo dnf install -y git # check if a package is already installed to avoid unnecessary operations
mkdir -p ~/nb
mkdir -p ~/nb/CodeProjects
cd ~/nb/CodeProjects
git clone https://github.com/nbhirud/system_update.git
gedit system_update/linux/ubuntu/ubuntu_todo_after_fresh_install.sh

#######################################################

# Fonts Setup
# Refer linux/common/nerd_fonts.sh

# Firefox, Librewolf, Mullvad browsers - refer linux/common/firefox.sh

#######################################################


#######################################################

#######################################################

#######################################################

#######################################################


# Enable RPM Fusion
# https://rpmfusion.org/Configuration

sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
# The above doesn't work with zsh. Use bash
# If the above doesn't work, there is another GUI method in the link
sudo dnf config-manager --enable fedora-cisco-openh264
sudo dnf update -y && sudo dnf upgrade --refresh -y
sudo dnf groupupdate core

# Install Media Codecs
# https://rpmfusion.org/Howto/Multimedia
sudo dnf swap ffmpeg-free ffmpeg --allowerasing
sudo dnf groupupdate multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf groupupdate sound-and-video
sudo dnf install libva-intel-driver # This is for old intel chips, for others check the link

# More codecs
# https://docs.fedoraproject.org/en-US/quick-docs/installing-plugins-for-playing-movies-and-music/
sudo dnf group install Multimedia
# sudo dnf install gstreamer1-plugins-{base,good,bad,ugly,libav} gstreamer1-plugin-openh264 libdvdcss libdvdread # above contains this?


# Enable fathub repo in flatpak (Not enabled by default in fedora)
# https://flatpak.org/setup/Fedora
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
# flatpak remote-modify --enable flathub # A different way of doing the above?

# Install snap
# sudo dnf install snapd # skip this

# Set host-name (name the computer)
sudo hostnamectl set-hostname "nbFedora"


# Firmware updates:
sudo fwupdmgr refresh --force
sudo fwupdmgr get-updates
sudo fwupdmgr update


# Install relavent Nvidia/AMD GPU drivers 
# https://itsfoss.com/install-nvidia-drivers-fedora/
# Check if you have nvidia card:
/sbin/lspci | grep -e VGA
/sbin/lspci | grep -e 3D
# Search and install based on system - Following is for recent systems:
sudo dnf update -y # and reboot if you are not on the latest kernel

# # For semi-old nvidia graphics cards:
# sudo dnf install akmod-nvidia # rhel/centos users can use kmod-nvidia instead
# sudo dnf install xorg-x11-drv-nvidia-cuda #optional for cuda/nvdec/nvenc support
# # modinfo -F version nvidia
# # Also see: https://www.nvidia.com/content/DriverDownloads/confirmation.php?url=/XFree86/Linux-x86_64/550.90.07/NVIDIA-Linux-x86_64-550.90.07.run&lang=us&type=geforcem

# # For very old graphics cards like GeForce 210:
# sudo dnf copr enable kwizart/kernel-longterm-6.1
# sudo dnf install akmods gcc kernel-longterm kernel-longterm-devel
# # sudo dnf remove xorg-x11-drv-nvidia-libs-3
# sudo dnf install xorg-x11-drv-nvidia-340xx akmod-nvidia-340xx --allowerasing
# sudo dnf install xorg-x11-drv-nvidia-340xx-cuda


sudo dnf update -y && sudo dnf upgrade --refresh -y
# reboot

#######################################################



#######################################################

### Install software

sudo dnf install -y gh python

# https://fedoramagazine.org/two-factor-authentication-ssh-fedora/
# sudo dnf install -y google-authenticator

# Password management
sudo dnf install keepassxc


# Install GNOME Tweaks
sudo dnf install -y gnome-tweaks

# Install Extensions Manager
flatpak install flathub com.mattjakeman.ExtensionManager # Or install the GNOME Extensions app
sudo dnf install -y gnome-browser-connector
# Go to extensions.gnome.org and install the browser extension

# Install useful things:
sudo dnf install -y vlc htop neofetch gparted alacritty bleachbit transmission 

# Install Brave instead of chromium
# https://brave.com/linux/
sudo dnf install dnf-plugins-core
sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
sudo dnf install -y brave-browser

# sudo dnf install -y kdenlive gimp chromium

# auto-cpufreq # Install for better battery management on laptops

# Pachage manager (for fedora like what synaptic is for ubuntu)
# sudo dnf install -y dnfdragora

# Speeds up opening of most used apps (avoid on low end or low RAM PCs)
# sudo dnf install -y preload 
# sudo dnf copr enable elxreno/preload -y && sudo dnf install preload -y

# To connect phone and PC
# sudo dnf install -y kdeconnectd # if using KDE Plasma
# Install Gnome extension: GSConnect if using Gnome
# Install KDE Connect on android phone and connect both

# sudo dnf install -y steam # If you wish to play games

# VLC
# https://www.videolan.org/vlc/download-fedora.html
# su -
# dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
# dnf install https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
# dnf install vlc
# dnf install python-vlc # (optional)

# https://docs.fedoraproject.org/en-US/quick-docs/installing-and-running-vlc/
sudo dnf install -y  vlc
sudo dnf remove -y totem # Remove stock video player

# PeaZip for archive management
# https://peazip.github.io/peazip-linux.html

# # Set up automatic updates: (Read more and see if there are any better alternatives before installing this)
# sudo dnf install -y dnf-automatic
# sudo systemctl enable dnf-automatic.timer
# sudo systemctl start dnf-automatic.timer

# Find out more about this (what is this doing exactly?):
# sudo dnf install fedore-workstation-repositories
# sudo dnf config-manager --set-enabled google-chrome
# sudo dnf install google-chrome-stable


######################################################

### Backups


sudo dnf install -y timeshift # For backups

######################################################

# Web UI for system monitoring
# sudo dnf install cockpit
# sudo systemctl start cockpit
# sudo systemctl enable cockpit
# https://localhost:9090

######################################################

# Good software for running virtual machines:
# KVM is a powerful tool
# sudo dnf install -y qemu @Virtualization # Another tool

######################################################

# Remove unused software
# Thunderbird
# Boxes



######################################################

### VSCodium
# Flatpak is easier to install, but I could not get zsh working with it. So install using external repo

# flatpak --user remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo # Add flathub repo
# flatpak install -y flathub com.vscodium.codium # Install it
# flatpak run com.vscodium.codium # Run it
# sudo flatpak uninstall com.vscodium.codium # uninstall it

# https://vscodium.com/#install
sudo rpmkeys --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg
printf "[gitlab.com_paulcarroty_vscodium_repo]\nname=download.vscodium.com\nbaseurl=https://download.vscodium.com/rpms/\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg\nmetadata_expire=1h" | sudo tee -a /etc/yum.repos.d/vscodium.repo
sudo dnf install codium

# codium # to run it

# Uninstall
# sudo dnf remove codium
# sudo rm /etc/yum.repos.d/vscodium.repo

#######################################################

# Configure tor - linux/security_os_level/tor.sh

#######################################################

# Configure firewall - linux/security_os_level/firewalld.sh

#######################################################

sudo dnf update -y
sudo dnf upgrade -y

# sudo dnf upgrade --refresh -y
# sudo dnf install dnf-plugin-system-upgrade -y
# sudo dnf system-upgrade download --releasever=40 -y

# sudo dnf system-upgrade reboot -y

# reboot
######################################################

# flatpak install -y flathub com.jetbrains.PyCharm-Community
# flatpak run com.jetbrains.PyCharm-Community
# https://copr.fedorainfracloud.org/coprs/phracek/PyCharm/

# dnf install
# dnf remove

# dnf check
# dnf check-update
# sudo dnf distro-sync
# dnf info
# dnf list
# dnf list installed # displays list of all installed packages
# dnf search
# dnf updateinfo
# dnf upgrade
# dnf upgrade-minimal
# dnf system-upgrade
# sudo dnf --refresh upgrade

# dnf clean all

######################################################

# Make Dock/Dash always visible
# sudo dnf install -y gnome-shell-extension-dash-to-dock # configure from gnome extensions manager

########################################################

# Wine for installing Windows apps
# sudo dnf config-manager --add-repo https://dl.winehq.org/wine-builds/fedora/40/winehq.repo
# sudo dnf install winehq-stable
# wine --version
# download Windows exe installer, and right click and open with wine to install them.

######################################################




######################################################

# Scheduled update, etc:






#################################################################
# Added by nbhirud manually:
#################################################################

### Custom linux aliases - add to ~/.zshrc

# Application shortcuts:
# alias codium="flatpak run com.vscodium.codium "

# Update/Upgrade related:
alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && sudo freshclam && omz update -y && . torsocks on"
# alias nbdistu="sudo apt dist-upgrade -y && sudo do-release-upgrade"
alias nbreload="systemctl daemon-reload && source ~/.zshrc"
alias nbclean="dnf clean -y all && flatpak uninstall --unused"
alias nbtoron=". torsocks on"
alias nbtoroff=". torsocks off"

### Stuff other than aliases:
. torsocks on

#################################################################

### Settings

# Follow instructions here:
# linux/gnome_common/gnome_settings.sh


#################################################################

### App specific Settings



################################################################

### UI Customization

# Themes
# can find some on dnfdragora too
# apply using GNOME Tweaks app

# Icon Packs

# App specific themes

# Wallpaper

###############################################################

# https://linuxcapable.com/how-to-install-kodi-on-fedora-linux/
# flatpak install -y flathub tv.kodi.Kodi
sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf install -y kodi-inputstream-adaptive kodi-firewalld kodi-inputstream-rtmp kodi-platform kodi-pvr-iptvsimple kodi-visualization-spectrum kodi-eventclients kodi

# cmake make automake gcc gcc-c++


# flatpak install flathub com.stremio.Stremio


###############################################################

# cron jobs

###############################################################

# Android apps on linux:
# https://docs.waydro.id/usage/install-on-desktops
# sudo dnf install waydroid
# System OTA: https://ota.waydro.id/system
# Vendor OTA: https://ota.waydro.id/vendor

###############################################################

# For creating WebApps (PWA): https://ostechnix.com/linux-mint-webapp-manager/
# sudo dnf copr enable refi64/webapp-manager
# sudo dnf install webapp-manager

###############################################################

# Change default downloads dir:
xdg-user-dirs-update --set DOWNLOAD "/home/nbhirud/nb/Downloads"

###############################################################


###############################################################


###############################################################


###############################################################


###############################################################


###############################################################


###############################################################


###############################################################

# dnf tweaks
sudo nano /etc/dnf/dnf.conf
# don't do dnf update here

# rpmfusion
sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
# don't do dnf update here

# zsh - check linux/common/zsh.sh

# don't do dnf update here

# name
sudo hostnamectl set-hostname "nbFedora"

# nvidia drivers
sudo dnf copr enable kwizart/kernel-longterm-6.1
#sudo dnf install akmods gcc kernel-longterm kernel-longterm-devel
#sudo dnf install xorg-x11-drv-nvidia-340xx akmod-nvidia-340xx --allowerasing
## sudo dnf remove xorg-x11-drv-nvidia-libs-3:555.58.02-1.fc40.x86_64
#sudo dnf install xorg-x11-drv-nvidia-340xx-cuda

# firmware stuff
sudo fwupdmgr refresh --force
sudo fwupdmgr get-updates
sudo fwupdmgr update

# important updates
sudo dnf config-manager --enable fedora-cisco-openh264
# sudo dnf update -y && sudo dnf upgrade --refresh -y
sudo dnf groupupdate core -y
sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y
sudo dnf groupupdate multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin -y
sudo dnf groupupdate sound-and-video -y
sudo dnf install libva-intel-driver -y
sudo dnf group install Multimedia -y
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# update
# this will update huge number of things when run for the first time
sudo dnf update -y && sudo dnf upgrade --refresh -y

# reboot
sudo reboot


# codium
sudo rpmkeys --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg
printf "[gitlab.com_paulcarroty_vscodium_repo]\nname=download.vscodium.com\nbaseurl=https://download.vscodium.com/rpms/\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg\nmetadata_expire=1h" | sudo tee -a /etc/yum.repos.d/vscodium.repo
sudo dnf install codium -y

# software
sudo dnf install -y git gh htop bleachbit neofetch vlc transmission gparted chromium steam 

sudo dnf update -y && sudo dnf upgrade --refresh -y


# after reboot
sudo reboot
omz update

# boot order
sudo efibootmgr -v
# sudo efibootmgr -o 0006,0008,0004,0003,0001,0002


# memory testing software
# sudo dnf install -y memtest86+ 


# TODO:

# signal - check flatpak - https://www.signal.org/download/linux/
flatpak install flathub org.signal.Signal
# flatpak run org.signal.Signal

# hosts file

# configure app specific settings
# configure firewall



###############################################################

https://itsfoss.com/things-to-do-after-installing-fedora/
https://www.hackingthehike.com/fedora-40-after-install-guide/
https://www.debugpoint.com/10-things-to-do-fedora-39-after-install/
https://artofcoding.dev/things-to-do-after-installing-fedora-40


###############################################################

# Virtualization
# https://docs.fedoraproject.org/en-US/quick-docs/virtualization-an-overview/

egrep '^flags.*(vmx|svm)' /proc/cpuinfo # Should return something - else hardware virtualization isn't supported

dnf groupinfo virtualization # view the packages in Virtualization Package Group

sudo dnf install @virtualization # install the mandatory and default packages in the virtualization group
sudo dnf group install --with-optional virtualization # install the mandatory, default, and optional packages

sudo systemctl start libvirtd
sudo systemctl enable libvirtd # start the service on boot
lsmod | grep kvm # verify that the KVM kernel modules are properly loaded


# Permissions

mkdir vm
cd vm
# Create a group shared and two users
sudo groupadd vm_group
sudo usermod -aG vm_group nbhirud
sudo usermod -aG vm_group qemu
# Recursively change group folder ownership (. = current dir = vm dir)
sudo chgrp -R vm_group .
# Adding reading, writing and executing (only for files already executables) permissions for the group
sudo chmod -R g+rwX .



# virt-install (CLI)

sudo dd if=/dev/zero of=/home/nbhirud/nb/vm/pureos10/pureos10_20240922.img bs=1M count=20480
sudo virt-install --name pureos10 \
--description 'PureOS 10 Workstation' \
--ram 2048 \
--vcpus 2 \
--disk /home/nbhirud/nb/vm/pureos10/pureos10_20240922.img,size=20 \
--os-type linux \
--os-variant pureos10 \
--network bridge=virbr0 \
--graphics vnc,listen=127.0.0.1,port=5901 \
--cdrom /home/nbhirud/Downloads/pureos-10.3-gnome-live-20230614_amd64.iso \
--noautoconsole

# Install virt-manager (GUI)
# sudo virt-manager # Start Virtual Machine Manager
virt-manager



