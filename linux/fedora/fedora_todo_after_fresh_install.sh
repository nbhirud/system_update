
# The following has been tested on:
# Fedora Linux 40 (Workstation Edition) x86_64

#######################################################

### Shell

# bash
# sudo dnf install bash-completion

# zsh
sudo dnf install -y zsh autojump
chsh -s $(which zsh) # set zsh as default

# Rest of the OMZ setup is same as on Ubuntu
omz update
source .zshrc 

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

cd ~/nb/CodeProjects
git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git

# delete using script

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

# LibreWolf
# https://librewolf.net/installation/
# add the repo
curl -fsSL https://rpm.librewolf.net/librewolf-repo.repo | pkexec tee /etc/yum.repos.d/librewolf.repo
# install the package
sudo dnf install -y librewolf

# another privacy browser:
# https://mullvad.net/en/download/browser/linux
# Add the Mullvad repository server to dnf
sudo dnf config-manager --add-repo https://repository.mullvad.net/rpm/stable/mullvad.repo
# Install the package
sudo dnf install mullvad-browser

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

# https://support.torproject.org/rpm/


sudo nano /etc/yum.repos.d/tor.repo

## Paste the following:
# [tor]
# name=Tor for Fedora $releasever - $basearch
# baseurl=https://rpm.torproject.org/fedora/$releasever/$basearch
# enabled=1
# gpgcheck=1
# gpgkey=https://rpm.torproject.org/fedora/public_gpg.key
# cost=100

sudo dnf install tor -y

sudo nano /etc/tor/torrc
## Paste the following, and modify as necessary:
EntryNodes {ca}{us}{uk} StrictNodes 1
ExitNodes {ca}{us}{uk} StrictNodes 1
sudo systemctl reload tor


source torsocks on
echo ". torsocks on" >> ~/.bashrc
echo ". torsocks on" >> ~/.zshrc


## DNS over Tor

# Step 1
# Download cloudflared from here: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/
# TLDR: download this for Fedora: https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-x86_64.rpm

# Step 2:
# https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/dns-over-https-client/
# TLDR: 
cloudflared --version  # verify if its installed

###
sudo tee /etc/systemd/system/cloudflared-proxy-dns.service >/dev/null <<EOF
[Unit]
Description=DNS over HTTPS (DoH) proxy client
Wants=network-online.target nss-lookup.target
Before=nss-lookup.target

[Service]
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
DynamicUser=yes
ExecStart=/usr/local/bin/cloudflared proxy-dns

[Install]
WantedBy=multi-user.target
EOF
###

sudo systemctl enable --now cloudflared-proxy-dns
sudo rm -f /etc/resolv.conf
echo nameserver 127.0.0.1 | sudo tee /etc/resolv.conf >/dev/null
dig +short @127.0.0.1 cloudflare.com AAAA # verify if it works

# Step 3"
# https://blog.cloudflare.com/welcome-hidden-resolver/
# https://developers.cloudflare.com/1.1.1.1/other-ways-to-use-1.1.1.1/dns-over-tor/
dnf install -y socat
sudo socat TCP4-LISTEN:443,reuseaddr,fork SOCKS4A:127.0.0.1:dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion:443,socksport=9150

###
cat << EOF >> /etc/hosts
127.0.0.1 dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion
EOF

###

cloudflared proxy-dns --upstream "https://dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion/dns-query"

#######################################################

# ufw

# https://linuxconfig.org/how-to-install-and-use-ufw-firewall-on-linux
# https://www.baeldung.com/linux/uncomplicated-firewall


# Fedora comes with firewalld
# Figure out which is better and learn an configure

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

# Reference: https://www.linuxcapable.com/install-clamav-on-fedora-linux/
sudo dnf upgrade --refresh # Refresh Fedora System Packages
# sudo dnf install -y clamav clamav-daemon clamtk 
sudo dnf install clamav clamd clamav-update clamtk #  Install ClamAV  and ClamTK GUI

# Update the ClamAV Virus Database
sudo systemctl stop clamav-freshclam 
sudo freshclam
sudo systemctl enable clamav-freshclam --now
sudo systemctl start clamav-freshclam
# ls -l /var/lib/clamav/ # Check ClamAV directory and the dates of the files

# Scanning:
# sudo clamscan [options] [file/directory/-]
sudo clamscan -h # Help
sudo clamscan /home/script.sh # Scan a file
sudo clamscan /home/ # Scan a dir
sudo clamscan -i /home/ # Print only infected files
sudo clamscan -o /home/ # Exclude printing OK files
sudo clamscan --bell -i /home # bell notification upon virus detection
sudo clamscan --bell -i -r /home # Scan directories recursively 
sudo clamscan --bell -i -r /home -l output.txt # Save the scan report to file 
sudo clamscan -i -f /tmp/scan # Scan files listed line-by-line in a specified file 
sudo clamscan -r --remove /home/USER # automatically remove infected files detected during the scan
sudo clamscan -r -i --move=/home/USER/infected /home/ # Move all files requiring quarantine into the specified location
sudo nice -n 15 clamscan && sudo clamscan --bell -i -r /home # To limit CPU usage during the scan, use the nice command

# Scheduled ClamAV Scans
crontab -e
# sudo dnf install cronie # IF ABOVE DOESN'T WORK
# add following line to add daily scan
# 0 1 * * * /usr/bin/clamscan -r --quiet --move=/home/USER/infected /home/

# ClamAV configuration file located at /etc/clamav/clamd.conf

    MaxFileSize: Adjust the maximum file size that ClamAV will scan.
    MaxScanSize: Change the maximum data size that ClamAV will scan within an archive or a file.
    HeuristxxicScanPrecedence: Enable or disable heuristic scanning, which uses techniques to detect unknown malware.



# Configure using - https://docs.clamav.net/manual/Usage/Configuration.html
# TLDR:

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
# Do these configs in ~/freshclam.conf
# LogFileMaxSize 20M
# LogTime yes
# LogRotate yes
# UpdateLogFile /var/log/freshclam.log
# DatabaseOwner clamupdate
# NotifyClamd yes

## clamd
# Do these configs in ~/clamd.conf 
# TODO - find correct path (/etc/clamav/clamd.conf ?)
# Comment the "Example"
# LogFile /var/log/clamav.log
# LogFileMaxSize 20M
# LogTime yes
# LogRotate yes
# ExitOnOOM yes # Not sure if this is a good thing to do
# User clamscan
# DetectPUA yes
# TLDR of - https://docs.clamav.net/manual/OnAccess.html
# OnAccessIncludePath /home # Figure out if this is the best option
# OnAccessExcludeUname clamscan
# OnAccessPrevention yes
# OnAccessDisableDDD yes


# also check /etc/clamd.d/scan.conf

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


### Firefox Tweaks:
# about:config
# layers.acceleration.force-enabled
# gfx.webrender.all

### 

################################################################

### UI Customization

# Themes
# can find some on dnfdragora too
# apply using GNOME Tweaks app

# Icon Packs

# App specific themes

# Wallpaper


################################################################

# Better Fonts:
# sudo dnf copr enable dawid/better_fonts -y
# sudo dnf install fontconfig-font-replacements -y
# sudo dnf install fontconfig-enhanced-defaults -y

# Change default fonts using GNOME Tweaks
# Change app specific fonts 



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

# zsh
sudo dnf install -y zsh 
chsh -s $(which zsh) 
zsh
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
sudo dnf install -y git gh htop bleachbit neofetch vlc transmission gparted chromium steam clamav clamd clamav-update clamtk

sudo dnf update -y && sudo dnf upgrade --refresh -y


curl -fsSL https://rpm.librewolf.net/librewolf-repo.repo | pkexec tee /etc/yum.repos.d/librewolf.repo
sudo dnf install -y librewolf





# tor
sudo nano /etc/yum.repos.d/tor.repo
# put stuff there
# don't install tor
sudo dnf update -y && sudo dnf upgrade --refresh -y

# install tor browser
sudo dnf install -y torbrowser-launcher




# clamav config
# cd /usr/share/doc/clamd/
sudo nano /usr/share/doc/clamd/clamd.conf

# omz
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

cd $ZSH_CUSTOM/plugins
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

#cd
#nano .zshrc
## do the following changes:
## ZSH_THEME="robbyrussell" # comment this line
#ZSH_THEME="agnoster"
#zstyle ':omz:update' mode auto # Uncomment this
#zstyle ':omz:update' frequency 7 # Uncomment and change value
#ENABLE_CORRECTION="true" # Uncomment - Give it a try
#COMPLETION_WAITING_DOTS="true"
#plugins=(git sudo safe-paste github python repo zsh-autosuggestions zsh-syntax-highlighting)
## At the bottom of oh-my-zsh stuff:
#ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#ff00ff,bg=cyan,bold,underline"
#ZSH_AUTOSUGGEST_STRATEGY=(history completion match_prev_cmd)
#ZSH_HIGHLIGHT_HIGHLIGHTERS+=(main brackets pattern cursor)

# fonts
mkdir -p ~/.local/share/fonts
# paste folder 
fc-cache -fr 
# fc-list | grep "JetBrains" 








# after reboot
sudo reboot
omz update

# boot order
sudo efibootmgr -v
# sudo efibootmgr -o 0006,0008,0004,0003,0001,0002


# memory testing software
# sudo dnf install -y memtest86+ 


# TODO:

# clamav config

# signal - check flatpak - https://www.signal.org/download/linux/
flatpak install flathub org.signal.Signal
# flatpak run org.signal.Signal

# firefox privacy
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
# https://docs.fedoraproject.org/en-US/quick-docs/virtualization-getting-started/

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



