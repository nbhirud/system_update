#!/bin/bash

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

# Deletes downloaded intermediate data like git repo, etc after setting up fonts.
CLEANUP_DELETE_LATER=true
SET_DEFAULT_FONTS=true

# full - downloads the complete git repo with depth 1 and then works on it (slowest multi-GB download)
# sparse - only fetch metadata and the specific paths configured
# archive - fetch only the specific release zip files directly from GitHub Releases. Nerd Fonts publishes individual, self-contained zip files for every font family with every release. (fastest download)
DOWNLOAD_METHOD="archive" # Choose one of "full", "sparse", "archive"


# echo "************************ Identify Desktop Environment ************************"
# DESKTOP=$(sh "$SYSUPDATE_CODE_DIR"/linux/common/check_desktop_env.sh)
# echo "Desktop Environment is $DESKTOP"

##########################################################################
# Set Directories
##########################################################################
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

##########################################################################
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

echo "************************ delete unused nerd-fonts repo ************************"
# rm -rf ~/nb/CodeProjects/nerd-fonts
rm -rf "$NERD_FONTS_DIR"

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


# ##########################################################################
# # Option 1: Direct Archive Downloads (Recommended & Fastest)
# ##########################################################################

# # Font names file should contain Nerd Font tar.xz/zip asset names or foldernames
# # Example lines in $FONT_NAMES_FILE_PATH:
# # FiraCode
# # JetBrainsMono
# # Noto
# # Ubuntu

# NF_VERSION="v3.2.1" # Target release version
# # DEST_DIR="${HOME}/.local/share/fonts/nerd-fonts"

# mkdir -p "$DEST_DIR"

# echo "************************ Downloading target Nerd Fonts ************************"

# # Read FONT_NAMES_FILE_PATH line by line
# while IFS= read -r font || [ -n "$font" ]; do
#     # Skip empty lines or comments
#     [[ -z "$font" || "$font" =~ ^# ]] && continue

#     echo "Fetching ${font}..."
#     # Download tar.xz directly from GitHub releases and extract into destination
#     curl -sSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NF_VERSION}/${font}.tar.xz" | \
#         tar -xJ -C "$DEST_DIR" --exclude="*.md" --exclude="*.txt" --exclude="LICENSE" --exclude="readme.md" 2>/dev/null \
#         || echo "Failed to download or extract ${font}"
# done < "$FONT_NAMES_FILE_PATH"

# # Refresh font cache once
# fc-cache -fr "$DEST_DIR"


# ##########################################################################



# install_nerd_fonts() {
#     # Usage: install_nerd_fonts "/path/to/font_names.txt" ["/optional/dest/dir"] ["v3.2.1"]
#     local font_list_file="$1"
#     local dest_dir="${2:-"${HOME}/.local/share/fonts/nerd-fonts"}"
#     local version="${3:-"v3.2.1"}"

#     if [[ ! -f "$font_list_file" ]]; then
#         echo "Error: Font list file '$font_list_file' not found." >&2
#         return 1
#     fi

#     # Ensure destination directory exists
#     mkdir -p "$dest_dir"

#     echo "************************ Installing Nerd Fonts (${version}) ************************"

#     local installed_count=0
#     local font

#     while IFS= read -r font || [[ -n "$font" ]]; do
#         # Strip leading/trailing whitespace, skip empty lines and comments
#         font="$(echo "$font" | xargs)"
#         [[ -z "$font" || "$font" =~ ^# ]] && continue

#         echo "--> Processing: ${font}"

#         # Fetch archive directly from GitHub Releases and stream-extract directly into destination
#         if curl -sSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${version}/${font}.tar.xz" | \
#            tar -xJ -C "$dest_dir" \
#                --exclude="*.md" \
#                --exclude="*.txt" \
#                --exclude="LICENSE*" \
#                --exclude="readme*" \
#                --exclude="README*" 2>/dev/null; then
#             echo "    Successfully installed ${font}"
#             ((installed_count++))
#         else
#             echo "    Error: Failed to download or extract ${font}" >&2
#         fi
#     done < "$font_list_file"

#     if (( installed_count > 0 )); then
#         echo "************************ Refreshing Font Cache ************************"
#         # Force refresh only on target directory to avoid full system rescan delay
#         fc-cache -f "$dest_dir"
#         echo "Successfully updated font cache for ${dest_dir}"
#     else
#         echo "No fonts were installed."
#     fi
# }




# ##########################################################################
# # Option 2: Git Sparse Checkout (If using repo subdirectories directly)
# ##########################################################################

# # CODE_BASE_DIR="${CODE_BASE_DIR:-$HOME/CodeProjects}"
# # NERD_FONTS_DIR="$CODE_BASE_DIR/nerd-fonts"
# # DEST_DIR="${HOME}/.local/share/fonts/nerd-fonts"

# mkdir -p "$CODE_BASE_DIR"
# cd "$CODE_BASE_DIR" || exit 1

# if [ ! -d "$NERD_FONTS_DIR" ]; then
#     echo "************************ Initializing Sparse Repository ************************"
#     # Initialize empty repo without downloading objects
#     git clone --filter=blob:none --no-checkout --depth 1 https://github.com/ryanoasis/nerd-fonts.git "$NERD_FONTS_DIR"
#     cd "$NERD_FONTS_DIR" || exit 1
    
#     # Enable sparse checkout
#     git sparse-checkout init --cone
# else
#     cd "$NERD_FONTS_DIR" || exit 1
# fi

# echo "************************ Configuring Sparse Paths ************************"
# # Construct target paths under patched-fonts/
# SPARSE_PATHS=()
# while IFS= read -r font || [ -n "$font" ]; do
#     [[ -z "$font" || "$font" =~ ^# ]] && continue
#     SPARSE_PATHS+=("patched-fonts/$font")
# done < "$FONT_NAMES_FILE_PATH"

# # Set sparse checkout rules and checkout files
# git sparse-checkout set "${SPARSE_PATHS[@]}"
# git checkout

# echo "************************ Installing Fonts ************************"
# mkdir -p "$DEST_DIR"

# # Copy targeted patched-fonts subdirectories
# for path in "${SPARSE_PATHS[@]}"; do
#     if [ -d "$NERD_FONTS_DIR/$path" ]; then
#         cp -r "$NERD_FONTS_DIR/$path" "$DEST_DIR/"
#     fi
# done

# # Cleanup non-font files inside destination
# find "$DEST_DIR" -type f \( -name "*.md" -o -name "*.txt" -o -name "LICENSE*" -o -name ".uuid" \) -delete

# # Refresh cache
# fc-cache -fr "$DEST_DIR"



