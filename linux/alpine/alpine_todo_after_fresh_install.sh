
#######################################################

# Very detailed official setup instructions: https://wiki.alpinelinux.org/wiki/Installation

# Install alpine as a desktop OS: https://wiki.alpinelinux.org/wiki/Installation#setup-alpine_based_System_Disk_Install
setup-alpine # Command to initiate installation to disk

# keyboard layout = us
# select variant = us
# hostname = nbAlpine

# Interface = eth0 (default)
# ip address = dhcp (default)
# manual network config = n

# root password = <set something>

# Timezone = America -> <city>

# proxy = none
# NTP client = busybox (default)

# APK mirror = 1

# User loginname = <enter something>
# full name fir user = <>
# ssh key for user = none (Check if this is ideal)
# which ssh server = openssh

# which disk would you like to use = sda (check the list displayed first)
# how would you like to use it? = lvm (experiment this)
# how would you like to use it? = sys
# erase the above disk? = y

# reboot

#######################################################

# Create user
setup-user # uses adduser in the backend
adduser -g "Nikhil Bhirud" nbhirud -s /bin/zsh -S
adduser nbhirud wheel # add an existing user as admin user
apk add doas # doas is a simplified and lightweight replacement for sudo

# Repositories (from where you receive updates, etc)
doas setup-apkrepos -cf
# Check if this supports https: https://mirrors.alpinelinux.org
# For better security you should probably change the url's from http to https in /etc/apk/repositories manually if supported, else change mirror/repo


# Graphics drivers - https://wiki.alpinelinux.org/wiki/Graphics_driver
doas apk add mesa-dri-gallium mesa-va-gallium

# setup Desktop Environment:
doas setup-desktop
# choose xfce or gnome
# cat /sbin/setup-desktop # view all the packages that are installed by the script for the chosen desktop

# Audio - https://wiki.alpinelinux.org/wiki/PipeWire
# your user should be in audio (to access audio devices) and video (to access webcam devices) groups
doas addgroup nbhirud audio
doas addgroup nbhirud video
doas apk add pipewire wireplumber pipewire-pulse pipewire-jack pipewire-alsa gst-plugin-pipewire
/usr/libexec/pipewire-launcher # just run and ignore errors

sudo apk update && sudo apk upgrade
#######################################################


sudo update-kernel


#######################################################

sudo setup-apkrepos
sudo nano /etc/apk/repositories
sudo apk add --upgrade apk-tools

sudo apk update && sudo apk upgrade

#######################################################

# Configure dns - linux/security_os_level/dns.sh

# Configure firewall - linux/security_os_level/ufw.sh

# Configure tor - linux/security_os_level/tor.sh

# Configure Anti Virus - linux/security_os_level/clamav.sh

# Configure hosts - linux/security_os_level/hosts.sh

# linux/common/bleachbit.sh
# linux/common/firefox.sh
# linux/common/git.sh
# linux/common/gnome_settings.sh
# Configure Fonts - linux/common/nerd_fonts.sh
# linux/common/zsh.sh

#######################################################


# Alpine Package Keeper (apk) commands
apk search firefox
apk info zlib
apk info # list all installed packages
doas apk add bash zsh
doas apk update # update the list of available packages
doas apk upgrade # upgrade the installed packages
doas apk -U upgrade # combines update and upgrade
doas apk del bash vim # remove package
apk cache clean

#######################################################

# Enable flatpack flathub - https://flathub.org/setup/Alpine
doas apk add flatpak
doas apk add gnome-software-plugin-flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# restart

# # You can also restrict the repository, for example "only free libre open source" or "only verified apps". The Librewolf Flatpak is verified, so you can use the subset:
# flatpak remote-add --subset=verified flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# # or when already added, check if all your apps are verified, or they don't get updates!
# flatpak remote-modify --subset=verified flathub

# # to remove the subset:
# flatpak remote-modify --subset= flathub


# LibreWolf - https://librewolf.net/installation/linux/
flatpak install flathub io.gitlab.librewolf-community
# flatpak run io.gitlab.librewolf-community

flatpak install org.bleachbit.BleachBit
# flatpak run org.bleachbit.BleachBit  # clean up using the UI that opens

#######################################################

# zsh - check linux/common/zsh.sh

#######################################################

sudo apk add gnome-apps-extra
sudo apk add fastfetch
sudo apk add nano
sudo nano /etc/passwd

# do not install alacritty or kitty terminal emulators as the cursor keeps disappearing on them. Keep the default 

#######################################################

# Update "ALL" command 
sudo apk update && sudo apk upgrade && flatpak update -y && sudo freshclam && omz update && fastfetch


# Clean all command
apk autoremove && apk cache clean

#######################################################



#######################################################

# Firefox, Librewolf, Mullvad browsers - refer linux/common/firefox.sh




