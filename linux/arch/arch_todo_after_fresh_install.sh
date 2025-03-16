
##########################################################################
########## Installation - using archinstall script
##########################################################################

# when you get the tty prompt, type:
archinstall

# You will get a lot of options to choose from, for customizing how you want your system to be
# Choose the following:

# Archinstall laoguage - English (100%)
# Mirrors - Defalut
# Locales - Default
    # keyboard - us
    # Locale language - en_US
    # Locale encoding - UTF-8
# Disk configuration - Use a best-effort default partition layout
    # Select one or more devices to use and configure - select the appropriate one
    # filesystem - ext4 (if btrfs, then use compression)

# Bootloader - Grub
# Swap - True
# Hostname - nbArch
# Root password - <set something strong and complicated)
# User account - 
    # Add a user
        # Enter username - abc
        # Password for user "abc" - xyz
        # Should "abc" be a superuser (sudo)? - yes
    # confirm and exit
# Profile - 
    # Type - Desktop
        # Select desired desktop env - Gnome
    # Graphics driver - <open and check this>
    # Greeter (boot loader) - sddm
# Audio - Pipewire
# Kernels - linux
# Additional packages - 
    # firefox chromium vim pcmanfm dmenu
# Network configuration - Use NetworkManager
# Timezone - America/New York
# Automatic time sync (NTP) - True
# Optional repositories - multilib

## Save configuration (to create a re-usable config - optional), then Install
# https://bbs.archlinux.org/viewtopic.php?pid=2139798#p2139798



##### Notes
# pcmanfm - a file manager
# dmenu - a run launcher 
# Terminal emulator alacritty is installed by default 




##########################################################################
########## Installation - the traditional way
##########################################################################

# Download here
# https://archlinux.org/download/


##########################################################################
########## zsh
##########################################################################

# Check linux/common/zsh.sh

##########################################################################
########## Update
##########################################################################

# an existing Arch Linux system can always be updated with
pacman -Syu

# install a package
# sudo pacman -S emacs # just for syntax

##########################################################################
########## mirrorlist
##########################################################################

# generate the most up-to-date mirrorlist possible
# https://archlinux.org/mirrorlist/


##########################################################################
########## 
##########################################################################

## yay
# https://itsfoss.com/install-yay-arch-linux/
sudo pacman -Syu
sudo pacman -S --needed base-devel git less #less needed for git diff
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
yay --version
yay -Sua # Upgrading (only) the AUR packages:

##########################################################################
########## 
##########################################################################

# ## aura
# # https://fosskers.github.io/aura/install.html
# git clone https://aur.archlinux.org/aura.git
# cd aura
# makepkg -s
# sudo pacman -U <the-package-file-that-makepkg-produces>
# aura check
# aura conf --gen > ~/.config/aura/config.toml
# aura stats --lang
# aura -Au # Updating your AUR Packages - run without sudo

##########################################################################
########## 
##########################################################################

# Configure dns - linux/security_os_level/dns.sh

# Configure firewall - linux/security_os_level/ufw.sh

# Configure tor - linux/security_os_level/tor.sh

# Configure Anti Virus - linux/security_os_level/clamav.sh

# Configure hosts - linux/security_os_level/hosts.sh

# linux/common/bleachbit.sh
# linux/common/firefox.sh
# linux/common/git.sh
# linux/common/gnome_settings.sh
# linux/common/nerd_fonts.sh
# linux/common/zsh.sh

##########################################################################
########## 
##########################################################################

## vscodium
# https://vscodium.com/
# https://aur.archlinux.org/packages/vscodium-bin/

# Aura:
# sudo aura -A vscodium-bin

# Yay:
yay -S vscodium-bin

##########################################################################
########## 
##########################################################################

xprop

##########################################################################
########## 
##########################################################################

sudo pacman -Syu && yay -Sua && sudo freshclam && omz update && fastfetch


##########################################################################
########## 
##########################################################################


# Also see:
# https://wiki.archlinux.org/title/Preload
# https://github.com/AlexMekkering/Arch-Linux/tree/master/docs

# vscode extension about Arch AUR
# https://open-vsx.org/vscode/item?itemName=claui.packaging

##########################################################################
########## 
##########################################################################


# https://wiki.archlinux.org/title/Improving_performance

##########################################################################
########## 
##########################################################################


##########################################################################
########## 
##########################################################################


##########################################################################
########## 
##########################################################################

