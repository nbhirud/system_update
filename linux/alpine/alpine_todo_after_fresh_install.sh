
#######################################################

# Very detailed official setup instructions: https://wiki.alpinelinux.org/wiki/Installation

# Install alpine as a desktop OS: https://wiki.alpinelinux.org/wiki/Installation#setup-alpine_based_System_Disk_Install
setup-alpine # Command to initiate installation to disk
# choose "sys"

#######################################################

# Create user
setup-user # uses adduser in the backend
adduser -g "Nikhil Bhirud" nbhirud -s /bin/zsh -S
adduser nbhirud wheel # add an existing user as admin user
apk add doas # doas is a simplified and lightweight replacement for sudo

# Repositories (from where you receive updates, etc)
setup-apkrepos -cf
# Check if this supports https: https://mirrors.alpinelinux.org
# For better security you should probably change the url's from http to https in /etc/apk/repositories manually if supported, else change mirror/repo


# Graphics drivers - https://wiki.alpinelinux.org/wiki/Graphics_driver

# setup Desktop Environment:
setup-desktop
# choose gnome
# cat /sbin/setup-desktop # view all the packages that are installed by the script for the chosen desktop

# Fonts: https://wiki.alpinelinux.org/wiki/Fonts
apk add font-terminus font-inconsolata font-dejavu font-noto font-noto-cjk font-awesome font-noto-extra font-noto-devanagari 
fc-cache -fv # display the font locations and to update the cache


# Audio - https://wiki.alpinelinux.org/wiki/PipeWire
# your user should be in audio (to access audio devices) and video (to access webcam devices) groups
doas addgroup nbhirud audio
doas addgroup nbhirud video
doas apk add pipewire wireplumber pipewire-pulse pipewire-jack pipewire-alsa gst-plugin-pipewire
/usr/libexec/pipewire-launcher # just run and ignore errors

#######################################################
















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



