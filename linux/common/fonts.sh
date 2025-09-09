#!/bin/sh

# Tested only by running from directory "system_update"
# 1. as `sh linux/common/fonts.sh`
# 2. invoked via `linux/fedora/run_first.sh`
# TODO - the script assumes a very rigid and specific file structure. Make it generic and resilient

# USERNAME="nbhirud"
# HOME_DIR="/home/$USERNAME/"
HOME_DIR=$(getent passwd $USER | cut -d: -f6)
CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects"
SYSUPDATE_CODE_DIR="$CODE_BASE_DIR/system_update"
# DEST_DIR="$HOME_DIR/.local/share/fonts/nerd-fonts"
DEST_DIR="$HOME_DIR/nb/test02/dest"
NERD_FONTS_DIR="$CODE_BASE_DIR/nerd-fonts"
PATCHED_FONTS_DIR="$NERD_FONTS_DIR/patched-fonts"

# BASEDIR=$(dirname "$0")
# echo "BASEDIR = $BASEDIR" # outputs "linux/common"
FONT_NAMES_FILE_PATH="$SYSUPDATE_CODE_DIR/linux/common/data/fonts.txt"


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

echo "************************ Identify Desktop Environment ************************"
DESKTOP=$(sh $SYSUPDATE_CODE_DIR/linux/common/check_desktop_env.sh)
echo "Desktop Environment is $DESKTOP"

if [ "$DESKTOP" = "gnome" ]
then
    echo "************************ Setting default UI fonts to Ubuntu and monospace font to Jetbrains ************************"
    dconf write /org/gnome/desktop/interface/font-name "'Ubuntu Nerd Font 11'"
    dconf write /org/gnome/desktop/interface/document-font-name "'Ubuntu Nerd Font 11'"
    dconf write /org/gnome/desktop/wm/preferences/titlebar-font "'Ubuntu Nerd Font Bold 11'"
    dconf write /org/gnome/desktop/interface/monospace-font-name "'JetBrainsMono Nerd Font 10'"
fi
