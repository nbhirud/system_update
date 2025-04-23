
# Tested only by running from directory "system_update" as `sh linux/common/fonts.sh`
# TODO - the script assumes a very rigid and specific file structure. Make it generic and resilient

USERNAME="nbhirud"
HOME_DIR="/home/$USERNAME/"
CODE_BASE_DIR="/home/$USERNAME/nb/CodeProjects"
DEST_DIR="/home/$USERNAME/.local/share/fonts/nerd-fonts"
# CODE_BASE_DIR="/home/$USERNAME/nb/test02/code"
# DEST_DIR="/home/$USERNAME/nb/test02/dest"
NERD_FONTS_DIR="$CODE_BASE_DIR/nerd-fonts"
PATCHED_FONTS_DIR="$NERD_FONTS_DIR/patched-fonts"

BASEDIR=$(dirname "$0")
# echo "BASEDIR = $BASEDIR" # outputs "linux/common"
FONT_NAMES_FILE_PATH="$CODE_BASE_DIR/system_update/$BASEDIR/data/fonts.txt"



mkdir -p $CODE_BASE_DIR
cd $CODE_BASE_DIR

if test -d nerd-fonts; then 
    cd nerd-fonts
    git pull --rebase
else 
    git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git
    cd nerd-fonts
fi 
cd patched-fonts

mkdir -p $DEST_DIR  # fonts folder is absent by default
# cp ~/nb/CodeProjects/nerd-fonts/patched-fonts ~/.local/share/fonts/nerd-fonts -r

xargs -a $FONT_NAMES_FILE_PATH cp -t $DEST_DIR -r

find $DEST_DIR -name "*.md" -type f -delete
find $DEST_DIR -name "*.txt" -type f -delete
find $DEST_DIR -name "LICENSE" -type f -delete
find $DEST_DIR -name ".uuid" -type f -delete
pwd

# rm -rf ~/nb/CodeProjects/nerd-fonts
cd $HOME_DIR
echo "syncing"
sync

fc-cache -fr
# fc-list | grep "JetBrains"