#!/bin/sh

set -eux

# Tested only by running from directory "system_update"
# 1. as `sh linux/common/fonts.sh`
# 2. invoked via `linux/fedora/run_first.sh`
# TODO - the script assumes a very rigid and specific file structure. Make it generic and resilient


##########################################################################
# Input data
##########################################################################

# TODO
# if [[ -z $1 ]];
# then
#     echo "DESKTOP not provided. Identifying."
#     HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)
#     SYSUPDATE_CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects/system_update"
#     DESKTOP=$(sh $SYSUPDATE_CODE_BASE_DIR/linux/common/check_desktop_env.sh)
# else 
#     DESKTOP="$1"
# fi

HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)
SYSUPDATE_CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects/system_update"
DESKTOP=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/check_desktop_env.sh)

echo "The current DESKTOP is $DESKTOP."

##########################################################################
# Set Constants, Variables, flags
##########################################################################

# USERNAME="nbhirud"
# HOME_DIR="/home/$USERNAME/"
HOME_DIR=$(getent passwd $USER | cut -d: -f6)
CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects"
SYSUPDATE_CODE_DIR="$CODE_BASE_DIR/system_update"
DEST_DIR="$HOME_DIR/.local/share/fonts/nerd-fonts"
# DEST_DIR="$HOME_DIR/nb/test/fonts_dest"
NERD_FONTS_DIR="$CODE_BASE_DIR/nerd-fonts"
PATCHED_FONTS_DIR="$NERD_FONTS_DIR/patched-fonts"

# BASEDIR=$(dirname "$0")
# echo "BASEDIR = $BASEDIR" # outputs "linux/common"
FONT_NAMES_FILE_PATH="$SYSUPDATE_CODE_DIR/linux/common/data/fonts.txt"

# TODO - Figure out a way to check first:
# 1. Whether there has been any update in the repo at all
# 2. If yes, whether there has been any change to the folders (fonts) I am using

#####################################

# # TODO - This code checks if nerd fonts are already installed
# # Check if this could b used.

# FONT_DIR="$HOME/.local/share/fonts"
# if ! fc-list : family | grep -qi "Nerd Font"; then
#     echo "--> No Nerd Font detected. Fetching JetBrainsMono Nerd Font..."
#     mkdir -p "$FONT_DIR"
#     TEMP_DIR=$(mktemp -d)
    
#     curl -sSL -o "$TEMP_DIR/JetBrainsMono.zip" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
#     unzip -q "$TEMP_DIR/JetBrainsMono.zip" -d "$TEMP_DIR"
#     cp "$TEMP_DIR"/*.ttf "$FONT_DIR/"
    
#     echo "--> Regenerating font cache..."
#     fc-cache -f "$FONT_DIR"
#     rm -rf "$TEMP_DIR"
#     echo "✔ Font installed. Be sure to select 'JetBrainsMono Nerd Font' in Konsole's Profile Settings!"
# else
#     echo "✔ Found an existing Nerd Font configuration."
# fi
#####################################


mkdir -p "$CODE_BASE_DIR"
cd "$CODE_BASE_DIR"  || exit

if test -d "$NERD_FONTS_DIR"; then 
    echo "************************ $NERD_FONTS_DIR repo already present locally. Pulling latest ************************"
    cd "$NERD_FONTS_DIR" || exit
    git pull --rebase
else 
    echo "************************ Cloning nerd-fonts repo ************************"
    git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git
    cd "$NERD_FONTS_DIR" || exit
fi 
cd "$PATCHED_FONTS_DIR" || exit

echo "************************ Setting up fonts ************************"
# TODO - check whether this already exists, and decide what to do
# For now, delete it first if it exists.
rm -rf $DEST_DIR

mkdir -p $DEST_DIR  # fonts folder is absent by default
# cp ~/nb/CodeProjects/nerd-fonts/patched-fonts ~/.local/share/fonts/nerd-fonts -r

xargs -a $FONT_NAMES_FILE_PATH cp -t $DEST_DIR -r

find $DEST_DIR -name "*.md" -type f -delete
find $DEST_DIR -name "*.txt" -type f -delete
find $DEST_DIR -name "LICENSE" -type f -delete
find $DEST_DIR -name ".uuid" -type f -delete
pwd

# rm -rf ~/nb/CodeProjects/nerd-fonts
cd $HOME_DIR || exit
echo "************************ sync ************************"
sync

echo "************************ refresh font cache ************************"
fc-cache -fr
# fc-list | grep "JetBrains"



if [ "$DESKTOP" = "gnome" ]
then
    echo "************************ Setting default UI fonts to Ubuntu and monospace font to Jetbrains ************************"
    dconf write /org/gnome/desktop/interface/font-name "'Ubuntu Nerd Font 11'"
    dconf write /org/gnome/desktop/interface/document-font-name "'Ubuntu Nerd Font 11'"
    dconf write /org/gnome/desktop/wm/preferences/titlebar-font "'Ubuntu Nerd Font Bold 11'"
    dconf write /org/gnome/desktop/interface/monospace-font-name "'JetBrainsMono Nerd Font 10'"

elif  [ "$DESKTOP" = "kde" ]
then
    echo "************************ Setting default UI fonts to NotoSans and monospace font to Jetbrains ************************"
    # KDE Plasma 6 font configuration
    kwriteconfig6 --group "General" --key "font" "NotoSans Nerd Font,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
    kwriteconfig6 --group "General" --key "fixed" "JetBrainsMono Nerd Font,10,-1,5,50,0,0,0,0,0"

fi
