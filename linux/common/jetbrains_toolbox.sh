#!/bin/bash

set -eux

# https://www.jetbrains.com/help/pycharm/installation-guide.html#toolbox

# TODO - Make this an "Install, or update if already installed" script
# Need to run this to open toolbox and then click update: 
# '''sudo /opt/jetbrains-toolbox/bin/jetbrains-toolbox'''

# RELEASE_TYPE=release

HOME_DIR=$(getent passwd $USER | cut -d: -f6)

JT_DOWNLOAD_DIR="$HOME_DIR/nb/Downloads/Jetbrains/jt_$(date +%Y-%m-%d_%H-%M-%S)"
JT_INSTALL_DEST="/opt/jetbrains-toolbox"

mkdir -p $JT_DOWNLOAD_DIR
sudo mkdir -p $JT_INSTALL_DEST

cd $JT_DOWNLOAD_DIR

# TARBALL_URL=$(curl -s 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=${RELEASE_TYPE}' | jq -r '.TBA[0].downloads.linux.link')
TARBALL_URL=$(curl -s 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' | jq -r '.TBA[0].downloads.linux.link')

TARBALL_FILENAME=$(basename $TARBALL_URL)

# TARBALL_SHA_URL=$(curl -s 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=$RELEASE_TYPE' | jq -r '.TBA[0].downloads.linux.checksumLink')
TARBALL_SHA_URL=$(curl -s 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' | jq -r '.TBA[0].downloads.linux.checksumLink')

JT_SHA_LONG=$(curl $TARBALL_SHA_URL )

# JT_SHA=$(echo $JT_SHA_LONG | awk '{ print $1}')

# echo "TARBALL_URL = $TARBALL_URL"
# echo "TARBALL_FILENAME = $TARBALL_FILENAME"
# echo "TARBALL_SHA_URL = $TARBALL_SHA_URL"
# echo "JT_SHA_LONG = $JT_SHA_LONG"
# echo "JT_SHA = $JT_SHA"

# Download the tarball:
wget -O "$JT_DOWNLOAD_DIR/$TARBALL_FILENAME" "$TARBALL_URL"

# Check SHA-256 checksum:
echo $JT_SHA_LONG | sha256sum -c

# De-Compress (unzip) the tarball in destination dir
sudo tar -xzvf "$TARBALL_FILENAME" --directory="$JT_INSTALL_DEST/" --strip-components=1

# Make jetbrains-toolbox aqn executable
sudo chmod +x "$JT_INSTALL_DEST/bin/jetbrains-toolbox"

# Run jetbrains-toolbox for the first time to initialize it
$JT_INSTALL_DEST/bin/jetbrains-toolbox

# The above will initialize various Toolbox application files in the application directory:
# ~/.local/share/JetBrains/Toolbox


mkdir -p /home/nbhirud/.local/share/JetBrains/Toolbox/apps
mkdir -p /home/nbhirud/.local/share/JetBrains/Toolbox/scripts
# Upon the first launch, the Toolbox App will also create a .desktop entry file in ~/.local/share/applications.

# The above will add it to app drawer as well as to auto-start


sleep 15s

###########################################################################################
# Old notes
###########################################################################################

# # flatpak install -y flathub com.jetbrains.PyCharm-Community
# # flatpak run com.jetbrains.PyCharm-Community
# # https://copr.fedorainfracloud.org/coprs/phracek/PyCharm/


# ###########################################

# # Install jetbrains toolbox

# # Follow instructions here: https://www.jetbrains.com/help/pycharm/installation-guide.html
# # May need to run the following if opening toolbox app gives error:
# # sudo apt install -y libfuse2
# # TLDR:
# sudo apt install libfuse2

# cd /opt/
# sudo tar -xvzf ~/Downloads/jetbrains-toolbox-1.xx.xxxx.tar.gz
# sudo mv jetbrains-toolbox-1.xx.xxxx jetbrains
# jetbrains/jetbrains-toolbox # Open JetBrains Toolbox (and installs?)

# # # Install Pycharm (Avoid on old/slow machines, and use VSCodium there instead): 
# # # If toolbox not needed, go for "Standalone installation" of pycharm. Remember to download Pycharm community edition
# # sudo tar xzf pycharm-*.tar.gz -C /opt/
# # cd /opt/pycharm-professional-2024.1/bin
# # sh pycharm.sh

# # If the above standalone installation doesn't seem to work, install pycharm flatpak (try to avoid snap Pycharm, it's slower)

# ### Pycharm Un-install:
# # https://toolbox-support.jetbrains.com/hc/en-us/articles/115001313270-How-to-uninstall-Toolbox-App
# # https://www.jetbrains.com/help/pycharm/uninstall.html


# ##### Jetbrains Toolbox
# # login to the toolbox app
# # Toolbox -> Settings -> Enable auto update
# # Toolbox -> Install Pycharm Community
# # Toolbox -> Pycharm Community Settings -> Auto update, larger memory 


# ###########################################

# # Open app "Startup Applications" -> Check if alright

# # To delay opening of start-up applicarions,

# # Find the .desktop file that corresponds with your application
# # in /home/nbhirud/.config/autostart/ directoryand open it in a text editor:

# # For example, for jetbrains toolbox:
# # /home/nbhirud/.config/autostart/jetbrains-toolbox.desktop
# # gedit ~/.config/autostart/jetbrains-toolbox.desktop
# # Append/Edit the following line to the file:
# #X-GNOME-Autostart-Delay=90
# #where 90 is the time in seconds you want to delay the application launch by

# #### Another method that doesn't seem to work:
# # For apps that you want to delay startup, append "sleep" <space> <seconds> <semicolon> before the existing command there
# # Example: Change the following in command box for jetbrains toolbox startup entry:
# # /home/nbhirud/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox --minimize
# # To the following
# # sleep 60;/home/nbhirud/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox --minimize
# # This did not work - find out why

# #############################################

# # https://draculatheme.com/jetbrains





# ##### pycharm
# # Set "JetbrainsMono Nerd Font" as default editor font
# # set latest python as interpreter

