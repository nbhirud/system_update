
###########################
# RESET
###########################
sudo systemctl stop waydroid-container
waydroid session stop
sudo waydroid container stop

sudo rm -rf /var/lib/waydroid
rm -rf ~/.local/share/waydroid
rm -rf ~/.waydroid
rm -rf ~/waydroid
rm -rf ~/.share/waydroid
rm -f ~/.local/share/applications/*waydroid*

# New installation
# The -f (--force) option tells Waydroid to reinitialize even if previous configuration existed.
# sudo waydroid init -f

###########################
# Fresh Install
###########################

HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)
DOWNLOADS_DIR="$HOME_DIR/nb/Downloads"
WAYDROID_STUFF="$DOWNLOADS_DIR/WaydroidStuff/ws_$(date +%Y-%m-%d_%H-%M-%S)"

mkdir -p "$WAYDROID_STUFF"
cd "$WAYDROID_STUFF" || exit

# Test
# echo $XDG_SESSION_TYPE
# wayland

sudo dnf upgrade --refresh

sudo dnf install -y python3-pyclip waydroid
# python3-pyclip - For enabling clipboard sharing with host

sudo systemctl enable --now waydroid-container


sudo waydroid init -f -s GAPPS -c "https://ota.waydro.id/system" -v "https://ota.waydro.id/vendor"

mkdir -p ~/nb/waydroid_shared

sudo mount --bind ~/nb/waydroid_shared ~/.local/share/waydroid/data/media/0/waydroid_shared

waydroid show-full-ui

# sudo systemctl status waydroid-container
# journalctl -u waydroid-container


# waydroid images stored here by default
# /var/lib/waydroid/images


# custom images added to 
#  /usr/share/waydroid-extra/images


wget https://f-droid.org/F-Droid.apk
waydroid app install F-Droid.apk
