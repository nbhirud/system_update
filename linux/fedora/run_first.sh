#!/bin/sh

# https://www.baeldung.com/linux/set-command
# https://linuxize.com/post/bash-set-command/
set -eux
# set -e: Exit on Error - tells bash to exit immediately if any command returns a non-zero status. It stops a script from continuing past a failure.
# set -u: Treat Unset Variables as Errors - makes bash exit when you reference a variable that has not been set.

# set -x: Trace Each Command - prints every command to standard error before it runs, with the expanded values of any variables. Because tracing is noisy, it is common to enable it only around the section you are debugging with set -x and then turn it off again with set +x.

# set -o pipefail: Catch Failures in a Pipeline - By default, a pipeline returns the exit status of its last command, so a failure earlier in the pipe is hidden. set -o pipefail changes this so the pipeline returns the status of the rightmost command that failed, or 0 if every command succeeded. Combined with set -e, it makes a failed first stage actually stop the script.

# set -euo pipefail: This enables exit-on-error, unset-variable checking, and pipeline failure detection in one line. Add x as set -euxo pipefail while debugging, then remove it. This pattern is the foundation of what is often called "bash strict mode".

# Table of most common options used in scripts (There are more like -C, -f, -a, -u)
# <Option>          <Long form>	      <Effect>
# set -e	          set -o errexit	  Exit immediately on a command failure
# set -u	          set -o nounset	  Error when an unset variable is used
# set -x	          set -o xtrace	    Print each command before running it
# set -o pipefail	  set -o pipefail	  Fail a pipeline if any command in it fails
# set +e	          set +o errexit	  Disable an option (plus instead of dash), commonly used for a block of code.
# set -o		                          List all options and their state
# set -- a b c		                    Set the positional parameters

#######################################

# Benefits:
# 1. Don't have to manually type each command and make some mistakes
# 2. Don't have to enter credentials lot of times, just once in the beginning is enough
# 3. Save time


#######################################

# https://docs.fedoraproject.org/en-US/quick-docs/upgrading-fedora-new-release/
# https://docs.fedoraproject.org/en-US/quick-docs/switching-desktop-environments/
# https://docs.fedoraproject.org/en-US/quick-docs/systemd-understanding-and-administering/
# https://docs.fedoraproject.org/en-US/quick-docs/debug-systemd-problems/
# https://docs.fedoraproject.org/en-US/quick-docs/viewing-logs/
# https://docs.fedoraproject.org/en-US/quick-docs/kernel-overview/
# https://docs.fedoraproject.org/en-US/quick-docs/virtualization-an-overview/
# https://docs.fedoraproject.org/en-US/quick-docs/troubleshooting-wayland-problems/

#######################################


# Do not run-as-root check
# https://www.baeldung.com/linux/check-script-run-root
if [ ${EUID:-0} -ne 0 ] || [ "$(id -u)" -ne 0 ]; then
  echo "You are running as $(whoami)"
else
  echo "Please do not run as root (or with sudo). This may set up packages and create directories and files in root home. You are running as $(whoami)."
  exit 1
fi

# Authenticate sudo up front. Does not execute anything as root. It simply asks sudo to authenticate you and refreshes the sudo credential.
# sudo -v
sudo -v || {
    echo "ERROR: sudo authentication failed." >&2
    exit 1
}

echo "************************ NOTE: The script will ask you to authenticate multiple times till the end. ************************"
sleep 5s


echo "************************ Read only constants ************************"


# EMULATED ENUM CLASS (Read-Only Constants)

readonly PC_TYPE_DESKTOP="desktop"
readonly PC_TYPE_LAPTOP="laptop"
readonly PC_TYPE_HEADLESS_SERVER="server"

readonly PRIVACY_HOME="home"
readonly PRIVACY_PORTABLE="portable"
readonly PRIVACY_PARANOID="paranoid"

readonly SETUP_TYPE_FULL="full"
readonly SETUP_TYPE_LIGHT="light"
readonly SETUP_TYPE_MINIMAL="minimal"

readonly DESKTOP_KDE="kde"
readonly DESKTOP_GNOME="gnome"
readonly DESKTOP_COSMIC="cosmic"

# "${DESKTOP_COSMIC}"


echo "************************ Setting User-Defined constants and flags ************************"


PC_TYPE=""  # If not set, we identify using /linux/common/get_pc_type.sh
# PC_TYPE - allowed values: desktop or laptop or server - "${PC_TYPE_DESKTOP}" or "${PC_TYPE_LAPTOP}" or "${PC_TYPE_HEADLESS_SERVER}"


PRIVACY_LEVEL="${PRIVACY_PORTABLE}"
# PRIVACY_LEVEL - allowed values: home, portable, paranoid - "${PRIVACY_HOME}" or "${PRIVACY_PORTABLE}" or "${PRIVACY_PARANOID}"
# home - For devices that never leave home network. Higher level of trust.
# portable - For devices such as laptops that can leave home network. Lower level of trust.
# paranoid - For devices such as laptops that are meant to be used in public wifi at a library, airport, etc. Zero trust.

# SETUP_TYPE="light" 
SETUP_TYPE="${SETUP_TYPE_LIGHT}"
# SETUP_TYPE - allowed values: full or light  or minimal - "${SETUP_TYPE_FULL}" or "${SETUP_TYPE_LIGHT}" or "${SETUP_TYPE_MINIMAL}"
# Default is light
# minimal - TBD - bare minimum, remove all optional stuff and even stuff like libreoffice, etc. and installs bare minimum things


# Ignored if connected to wifi. Renames name of ethernet connection connected at the time of running the script. Use with CONNECTION_TYPE inferred in next section
NEW_ETHERNET_NAME="" # nbEthernet, etc

HOSTNAME=""  # "nbPC"
GIT_USER_EMAIL=""  # "<GITHUB PRIVATE EMAIL>@users.noreply.github.com"
NEXTDNS_ID=""  
NEXTDNS_DEVICE_ID="$HOSTNAME"

# Decide whether to install specific applications:
HAS_TORRENT_CLIENT=false  # qBittorrent
HAS_KODI=false


# provide a default with ${VAR:-default} so the reference is always defined:
# echo "Deploying to ${ENVIRONMENT:-staging}"

MEDIA_PC=false # grayjay, freetube, kodi, spotify, etc # TODO
CONFERENCING_APPS=false # zoom, proton meet, etc

INSTALL_XYZ=true


echo "************************ Setting Inferred constants and flags ************************"

# TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"

# HOME_LAN_SUBNET=""
# Automatically detect the local LAN subnet (e.g., 192.168.1.0/24)
HOME_LAN_SUBNET=$(python3 -c '
import subprocess, ipaddress
try:
    route = subprocess.check_output(["ip", "-o", "-4", "route", "show", "to", "default"], text=True)
    iface = route.split()[4]
    addr_info = subprocess.check_output(["ip", "-o", "-4", "addr", "show", "dev", iface], text=True)
    cidr = addr_info.split()[3]
    # Calculate the proper network base address (e.g., .0/24 instead of host IP; normalizes host IPs to base subnet)
    print(ipaddress.ip_network(cidr, strict=False))
except Exception:
    print("192.168.1.0/24") # Safe fallback if network lookup fails
' 2>/dev/null)

# Fallback explicit override if desired
HOME_LAN_SUBNET="${HOME_LAN_SUBNET:-192.168.1.0/24}"
readonly HOME_LAN_SUBNET

echo "************************ Identify the real user (non root) running the script/logged in ************************"
# REAL_USER=$(sh $SYSUPDATE_CODE_BASE_DIR/linux/common/get_real_user.sh)

# 1. Check SUDO_USER first, but make sure it isn't 'root'
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    REAL_USER="$SUDO_USER"
# 2. Fall back to the owner of the controlling terminal (tty)
elif [ -t 0 ] && [ -n "$(logname 2>/dev/null)" ] && [ "$(logname)" != "root" ]; then
    REAL_USER="$(logname)"
# 3. Fall back to the active desktop/graphical session user (UID >= 1000)
else
    REAL_USER=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | while read -r u; do id -u "$u" &>/dev/null && [ "$(id -u "$u")" -ge 1000 ] && echo "$u" && break; done)
fi

# Fallback to current user if all checks fail
REAL_USER="${REAL_USER:-$USER}"

echo "************************ Setting Directories ************************"

# HOME_DIR=$(getent passwd $USER | cut -d: -f6)
HOME_DIR=$(getent passwd "$REAL_USER" | cut -d: -f6)
NBDIR="$HOME_DIR/nb"
CODEPROJECTS_DIR="$NBDIR/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="$CODEPROJECTS_DIR/system_update"
# RUN_FIRST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

DESKTOP_DIR="$NBDIR/Desktop"
DOCUMENTS_DIR="$NBDIR/Documents"
DOWNLOADS_DIR="$NBDIR/Downloads"
VIDEOS_DIR="$NBDIR/Videos"
PICTURES_DIR="$NBDIR/Pictures"
MUSIC_DIR="$NBDIR/Music"
PUBLIC_DIR="$NBDIR/Public"
TEMPLATES_DIR="$NBDIR/Templates"
PROJECTS_DIR="$NBDIR/Projects"

SCRIPT_DATA_DIR="$NBDIR/nb_script_data"
SCRIPT_BACKUPS_DIR="$SCRIPT_DATA_DIR/backups"
SCRIPT_DOWNLOADS_DIR="$SCRIPT_DATA_DIR/downloads"
SCRIPT_LOGS_DIR="$SCRIPT_DATA_DIR/logs"


echo "************************ Verifying User-Defined constants and flags ************************"

IS_ETHERNET=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_is_ethernet.sh)

if [ "$GIT_USER_EMAIL" = "" ]; then
  echo "Warning - GIT_USER_EMAIL not provided."
  sleep 5s
fi

if [ "$PC_TYPE" = "" ]; then
  PC_TYPE=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_pc_type.sh)
fi


if [ "$PRIVACY_LEVEL" = "" ]; then

  # case "${PC_TYPE:-}" in
  #   laptop)  PRIVACY_LEVEL="paranoid" ;;
  #   desktop) PRIVACY_LEVEL="home" ;;
  #   server)  PRIVACY_LEVEL="home" ;;
  #   "")      PRIVACY_LEVEL="portable" ;;
  # #    *)       PRIVACY_LEVEL="home" ;; # Safe fallback for unknown inputs
  # esac


  # Clean conditional checks using the constant
  case "$PC_TYPE" in
      "$PC_TYPE_LAPTOP")                                    PRIVACY_LEVEL="$PRIVACY_PARANOID" ;;
      "$PC_TYPE_TYPE_DESKTOP"|"$PC_TYPE_HEADLESS_SERVER")   PRIVACY_LEVEL="$PRIVACY_HOME" ;;
      "")                                                   PRIVACY_LEVEL="$PRIVACY_PORTABLE" ;;

      *)
          echo "ERROR: Unknown PC_TYPE." >&2
          exit 1
          ;;
  esac

fi


if [ "$HOSTNAME" = "" ] || [ "$SETUP_TYPE" = "" ] || [ "$PC_TYPE" = "" ] || [ "$PRIVACY_LEVEL" = "" ] || [ "$NEXTDNS_ID" = "" ] || [ "$NEXTDNS_DEVICE_ID" = "" ]; then
  echo "Please set User-Defined constants and run again"
  exit 1
fi


echo "************************ Create directories ************************"
# TODO - use this downloads dir for downloads of ProtonAG installers, etc
# TODO - Use this backup fir for backup of configs, etc before replacing or editing like .zshrc

mkdir -p $SCRIPT_DATA_DIR $SCRIPT_BACKUPS_DIR $SCRIPT_DOWNLOADS_DIR $SCRIPT_LOGS_DIR $DESKTOP_DIR $DOCUMENTS_DIR $DOWNLOADS_DIR $VIDEOS_DIR $PICTURES_DIR $MUSIC_DIR $PUBLIC_DIR $TEMPLATES_DIR $PROJECTS_DIR
sudo chown $USER:$USER $SCRIPT_DATA_DIR $SCRIPT_BACKUPS_DIR $SCRIPT_DOWNLOADS_DIR $SCRIPT_LOGS_DIR $DESKTOP_DIR $DOCUMENTS_DIR $DOWNLOADS_DIR $VIDEOS_DIR $PICTURES_DIR $MUSIC_DIR $PUBLIC_DIR $TEMPLATES_DIR $PROJECTS_DIR

# sudo install -d -o "$REAL_USER" -g "$REAL_USER" -m 750 "$SCRIPT_DATA_DIR"

echo "************************ Identify Desktop Environment ************************"
DESKTOP=$(sh $SYSUPDATE_CODE_BASE_DIR/linux/common/get_desktop_env.sh)
echo "Desktop Environment is $DESKTOP"

if [ "$DESKTOP" = "" ]; 
then
  echo "Desktop not identified. Fix get_desktop_env.sh and run again"
  exit 1
else
  echo "Desktop is $DESKTOP"
fi

echo "************************ Identify Distro ************************"
# Useful in cases where the common/security/etc scripts need them when they support multiple distros
DISTRO=$(sh $SYSUPDATE_CODE_BASE_DIR/linux/common/get_distro_name.sh)

if [ "$DISTRO" = "" ];
then
  echo "Distro not identified. Fix get_distro_name.sh and run again"
  exit 1
else
  echo "Distro is $DISTRO"
fi


echo "************************ HOME_DIR = $HOME_DIR ************************"
echo "************************ DOWNLOADS_DIR = $DOWNLOADS_DIR ************************"
echo "************************ SYSUPDATE_CODE_BASE_DIR = $SYSUPDATE_CODE_BASE_DIR ************************"
# echo "************************ RUN_FIRST_LOCATION = $RUN_FIRST_DIR ************************" # https://stackoverflow.com/a/246128
sleep 5s


# Rename the active wired connection if we are on Ethernet and a new name was provided
if [ "$IS_ETHERNET" = true ] && [ -n "$NEW_ETHERNET_NAME" ]; then
    # Apply the new name if a profile was successfully found
    if [ -n "$CURRENT_ETHERNET_NAME" ]; then
        echo "************************ Renaming active ethernet connection from $CURRENT_ETHERNET_NAME to $NEW_ETHERNET_NAME ************************"
        nmcli connection modify "$CURRENT_ETHERNET_NAME" connection.id "$NEW_ETHERNET_NAME"
        
        sleep 5s
    fi
fi

# Verify
if [ "$IS_ETHERNET" = true ] && [ -n "$NEW_ETHERNET_NAME" ]; then
    TMP_ETHERNET_NAME=$(nmcli -t -f TYPE,CONNECTION device | awk -F: '$1=="ethernet" {print $2; exit}')
    echo "Verification: Now connected to: $TMP_ETHERNET_NAME"
fi



echo "************************ Updating /etc/dnf/dnf.conf ************************"

# Configurations to dnf
# https://dnf.readthedocs.io/en/latest/conf_ref.html
# sudo nano /etc/dnf/dnf.conf
# fastestmirror=True
# max_parallel_downloads=5
# defaultyes=True

# Another way
# echo 'fastestmirror=True' | sudo tee -a /etc/dnf/dnf.conf
# echo 'max_parallel_downloads=5' | sudo tee -a /etc/dnf/dnf.conf
# echo 'defaultyes=True' | sudo tee -a /etc/dnf/dnf.conf

# Configure DNF settings
# https://www.man7.org/linux/man-pages/man5/dnf.conf.5.html
# https://docs.fedoraproject.org/en-US/quick-docs/dnf/
# https://docs.fedoraproject.org/en-US/quick-docs/fedora-repositories/
sudo tee /etc/dnf/dnf.conf <<EOL
# see "man dnf.conf" for defaults and possible options

[main]
max_parallel_downloads=5
defaultyes=True
#fastestmirror=True
clean_requirements_on_remove=True
color=always

EOL

# https://docs.fedoraproject.org/en-US/quick-docs/installing-chromium-or-google-chrome-browsers/
sudo dnf install fedora-workstation-repositories

# echo "************************ Adding helium copr repo ************************"
# https://helium.computer/download#all-downloads
# AppImage is their default option for linux - install this
# dnf copr enable imput/helium
# sudo dnf install -y helium-bin

echo "************************ Installing packages ************************"
# install the packages
sudo dnf install -y git flatpak

# Note: flatpak and git may not come already installed on some flavors like xfce, etc.



#######################################

echo "************************ Removing packages ************************"
# remove stuff
sudo dnf remove -y totem yelp gnome-tour gnome-connections firefox
# remove the gnome terminal ptyxis as we have installed

sudo rm -r /opt/firefox
rm ~/.local/share/applications/firefox.desktop
rm -r ~/.mozilla

#######################################

echo "************************ Enabling RPM Fusion ************************"
# Enable RPM Fusion
# https://rpmfusion.org/Configuration

# curl https://rpmfusion.org/Configuration | grep "Fedora with dnf" | grep "sudo dnf install https"

### Configuration of Repositories - https://rpmfusion.org/Configuration
# https://docs.fedoraproject.org/en-US/quick-docs/rpmfusion-setup/

sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm # use bash, not zsh (done above)

echo "************************ Configuring @core ************************"
sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
sudo dnf update -y @core

echo "************************ Configuring Multimedia on Fedora ************************"
### Multimedia on Fedora - https://rpmfusion.org/Howto/Multimedia

sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin

echo "************************ Configuring Codecs ************************"
### Codecs - https://docs.fedoraproject.org/en-US/quick-docs/installing-plugins-for-playing-movies-and-music/
sudo dnf group install -y multimedia
sudo dnf install gstreamer1-plugin-openh264 mozilla-openh264

# https://docs.fedoraproject.org/en-US/quick-docs/how-to-troubleshoot-sound-problems/

#######################################

echo "************************ Enabling flatpak flathub ************************"
### Enable flatpak flathub
# https://docs.fedoraproject.org/en-US/quick-docs/flathub-flatpak-applications/
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
# flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo



echo "************************ Enabling AppMan/AM ************************"
# https://docs.fedoraproject.org/en-US/quick-docs/appimage/
# https://appimage.github.io/apps/
curl -s -Lo ./AM-INSTALLER https://raw.githubusercontent.com/ivan-hc/AM/main/AM-INSTALLER && chmod a+x ./AM-INSTALLER && ./AM-INSTALLER && rm ./AM-INSTALLER


#######################################

# Change default downloads dir:

if [ "$DESKTOP" = "${DESKTOP_GNOME}" ]; then
  echo "************************ Changing default downloads directory ************************"
  
  # File where default dirs are stored: 
  # cat ~/.config/user-dirs.dirs
  # echo "$(xdg-user-dir DESKTOP)" "$(xdg-user-dir DOCUMENTS)" "$(xdg-user-dir PICTURES)"

  xdg-user-dirs-update --set DOWNLOAD "$DOWNLOADS_DIR" # Gnome specific

  echo "************************ Enable Minimize or Maximize Window Buttons ************************"
  gsettings set org.gnome.desktop.wm.preferences button-layout "appmenu:minimize,maximize,close"
fi

echo "************************ Rename pc ************************"
# https://docs.fedoraproject.org/en-US/quick-docs/changing-hostname/
sudo hostnamectl set-hostname $HOSTNAME

######################################

echo "************************ Install and configure more dnf packages ************************"
sudo dnf install -y gh fzf fastfetch 
# bleachbit - Fedora repo generally has a very old version. Installing latest stable version it below from bleachbit's rpm
# sudo dnf install -y  gnome-browser-connector dnfdragora transmission
# sudo dnf install -y akregator alligator kasts clementine
# TODO - configure fzf
# Podcasts - gpodder
# nautilus-python - research what this can be used for


if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}" ]; 
then
  sudo dnf install -y ksystemlog htop keepassxc timeshift qbittorrent vlc 
  # thunderbird
  # ksystemlog - UI to view/filter system logs
  

fi


if [ "$DESKTOP" = "${DESKTOP_GNOME}" ]
then
  sudo dnf install -y gnome-tweaks

  if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}" ];
  then
    sudo dnf install -y gparted liferea quiterss
  fi

elif  [ "$DESKTOP" = "${DESKTOP_KDE}" ]
then
  sudo dnf install -y kde-gtk-config plasma-browser-integration kasts

  echo "Installing apps to try out on KDE - dnf"
  sudo dnf install -y kalarm kbackup

  echo "Use pre-installed KDE Partition Manager instead of gparted"
  echo "Use pre-installed Kasts instead of Gnome Podcasts"
  echo "Use pre-installed Akregator instead of liferea and quiterss"

  # TODO manually: https://community.kde.org/Dolphin/FAQ/Freeze
  # kate - nah

fi


echo "************************ Install and configure more flatpak packages ************************"
flatpak install -y flathub org.signal.Signal com.github.tchx84.Flatseal it.mijorus.gearlever
# com.brave.Browser - use dnf package
# it.mijorus.gearlever using AppMan/AM instead. Ok ok, install it till get used to AppMan/AM

# TODO - check which brave is installed (flatpak vs dnf) and set following accordingly
export CHROME_EXECUTABLE=/usr/bin/brave-browser
# export CHROME_EXECUTABLE="flatpak run com.brave.Browser"


if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}" ];
then
  flatpak install -y com.rtosta.zapzap org.telegram.desktop chat.simplex.simplex network.loki.Session io.freetubeapp.FreeTube dev.fredol.open-tv com.spotify.Client app.grayjay.Grayjay app.organicmaps.desktop im.riot.Riot org.localsend.localsend_app com.sindresorhus.Caprine com.super_productivity.SuperProductivity
  
  # com.bitwarden.desktop
  # io.github.hkdb.Aerion
  # net.rpdev.OpenTodoList

fi

if [ "$DESKTOP" = "${DESKTOP_GNOME}" ]
then
  flatpak install -y flathub com.mattjakeman.ExtensionManager

  if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}" ];
  then
    flatpak install -y flathub org.gnome.Podcasts de.haeckerfelix.Shortwave 
    # org.gnome.Fractal
  fi

elif  [ "$DESKTOP" = "${DESKTOP_KDE}" ]
then
  # flatpak install -y flathub

  if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}" ];
  then
    flatpak install -y flathub io.github.amit9838.mousam
    # org.kde.kasts - install dnf package instead
    # org.kde.neochat

    # echo "Installing apps to try out on KDE - flatpak"
    # flatpak install -y flathub <>
    # dev.zed.Zed
  fi

fi



### echo "Installing apps to try out on KDE - curl/wget | sh"

# ZED IDE
# curl -f https://zed.dev/install.sh | sh



# com.protonvpn.www me.proton.Mail me.proton.Pass # installing using official instructions via script
# flatpak install -y flathub ca.desrt.dconf-editor com.spotify.Client
# Facebook messenger (deprecated) - com.sindresorhus.Caprine
# element matrix client - im.riot.Riot - 
# install Fractal (or Fluffychat) - other matrix clients
# im.fluffychat.Fluffychat
# org.gnome.Fractal - prefer on Gnome
# io.github.kolunmi.Bazaar - an alternative software store from flatpak/flathub
# flatpak install flathub app.grayjay.Grayjay

#######################################
# Some configs
# TODO something similar for Element, Telegram, etc

if [ "$DESKTOP" = "${DESKTOP_GNOME}" ] || [ "$DESKTOP" = "${DESKTOP_COSMIC}" ];
then
  sudo flatpak override --env=SIGNAL_PASSWORD_STORE=gnome-libsecret org.signal.Signal
  
  # sudo flatpak override --password-store=gnome-libsecret im.riot.Riot


elif  [ "$DESKTOP" = "${DESKTOP_KDE}" ]
then
  sudo flatpak override --env=SIGNAL_PASSWORD_STORE=kwallet6 org.signal.Signal
  
  if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}" ];
  then
    # sudo flatpak override --env=password-store=kwallet6 im.riot.Riot
    flatpak override --user im.riot.Riot \
    --talk-name=org.kde.kwalletd6 \
    --talk-name=org.freedesktop.secrets
    
    # To enable drag ang drop, etc
    sudo flatpak override --user --filesystem=home com.rtosta.zapzap
  fi

fi

#######################################

# # Reference: https://github.com/laurent22/joplin/blob/dev/Joplin_install_and_update.sh
# INSTALL_DIR="${HOME}/.joplin"   # default installation directory
# # Check if it's an update or a new install
# DOWNLOAD_TYPE="New"
# if [[ -f "${INSTALL_DIR}/Joplin.AppImage" ]]; then
#   DOWNLOAD_TYPE="Update"
# fi


# if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}"" ];
# then
#   # https://joplinapp.org/help/install/
#   wget -O - https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh | bash
# fi

#######################################

if [ "$SETUP_TYPE" = "${SETUP_TYPE_MINIMAL}" ]; 
then
  
  echo "Removing all optional stuff and even stuff like libreoffice - TBD"
  # TBD
  # sh "$SYSUPDATE_CODE_BASE_DIR"/linux/fedora/remove_stuff.sh
  

fi


# sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/vscodium_orig.sh
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/vscodium.sh
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/librewolf_browser.sh
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/brave_browser.sh
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/tor_browser.sh
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/fonts.sh
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/zsh_orig.sh "$DISTRO" $SETUP_TYPE "$DESKTOP" "$FILENAME_TIMESTAMP"
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/alacritty_orig.sh
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/bleachbit.sh
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/git.sh "$GIT_USER_EMAIL"
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/syncthing.sh
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/avahi.sh
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/mpv.sh
# sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/cron_jobs.sh
sudo sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/dns.sh "$NEXTDNS_ID" "$NEXTDNS_DEVICE_ID"
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/proton_ag.sh --setup-type "$SETUP_TYPE" --desktop "$DESKTOP"
# bash linux/security_os_level/proton_ag.sh --setup-type full --desktop kde

# sudo sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/clamav.sh
# sudo DEBUG=1 sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/clamav.sh

 sudo DEBUG=1 sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/clamav.sh \
    --pc-type="${PC_TYPE}" \
    --real-user="${REAL_USER}" \
    --torrent-client="${HAS_TORRENT_CLIENT}" \
    --kodi="${HAS_KODI}" \
    --backup-dir="${SCRIPT_BACKUPS_DIR}" \
    --timestamp="${FILENAME_TIMESTAMP}"

# # If any of those variables might occasionally be empty/unset in the caller script and you only want to pass them when they actually contain a value, you can build an argument array dynamically:
# # Build argument array dynamically to omit empty variables
# CLAMAV_ARGS=()

# [ -n "${PC_TYPE:-}" ] && CLAMAV_ARGS+=("--pc-type=${PC_TYPE}")
# [ -n "${REAL_USER:-}" ] && CLAMAV_ARGS+=("--real-user=${REAL_USER}")
# [ -n "${HAS_TORRENT_CLIENT:-}" ] && CLAMAV_ARGS+=("--torrent-client=${HAS_TORRENT_CLIENT}")
# [ -n "${HAS_KODI:-}" ] && CLAMAV_ARGS+=("--kodi=${HAS_KODI}")
# [ -n "${SCRIPT_BACKUPS_DIR:-}" ] && CLAMAV_ARGS+=("--backup-dir=${SCRIPT_BACKUPS_DIR}")
# [ -n "${FILENAME_TIMESTAMP:-}" ] && CLAMAV_ARGS+=("--timestamp=${FILENAME_TIMESTAMP}")

# # Execute the script with the constructed arguments
#  sudo sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/clamav.sh "${CLAMAV_ARGS[@]}"


# Be sure to run the following after: clamav
sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/hosts.sh


# Be sure to run the following after: firewalld
# sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/fail2ban.sh


if [ "$SETUP_TYPE" = "${SETUP_TYPE_FULL}" ];
then
  sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/bash.sh
  sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/aws.sh
  sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/zoom.sh
  sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/jetbrains_toolbox.sh
  
  sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/docker.sh
  sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/neovim_lazyvim.sh
  sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/i2p.sh

  # Be sure to run the following after: zsh, alacritty, neovim
  sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/tmux_zellij.sh
  sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/yazi.sh
  
  # Be sure to run the following after: clamav
  sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/mullvad_browser.sh
  

  if [ "$DESKTOP" = "${DESKTOP_GNOME}" ]
  then
    sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/gsconnect_kde_connect.sh
  fi

fi

# Also, it is best to setup firewalld at the end so it finds all installed services/packages to check before setting up
# Be sure to run the following after: zsh
# sudo sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/firewalld.sh "$FILENAME_TIMESTAMP" "$SCRIPT_BACKUPS_DIR" $PRIVACY_LEVEL
sudo sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/firewalld.sh \
    --filename-timestamp "$FILENAME_TIMESTAMP" \
    --script-backups-dir "$SCRIPT_BACKUPS_DIR" \
    --sysupdate-code-base-dir "$SYSUPDATE_CODE_BASE_DIR" \
    --home-lan-subnet "$HOME_LAN_SUBNET" \
    --privacy-level "$PRIVACY_LEVEL" \
    --desktop "$DESKTOP" \
    --home-dir "$HOME_DIR" \
    --real-user "$REAL_USER"


######################################
# MIME defaults
######################################

# Set codium as the default text editor
xdg-mime default codium.desktop text/plain
# Set brave as the default browser - TODO
# Set thunderbird/ProtonMail as the default email client - TODO
# Set KDEConnect/GSConnect as the default Phone numbers handler - TODO
# Set VLC as the default video player - TODO
# Set Okular as the default PDF viewer - TODO
# Set Alacritty as the default terminal emulator - TODO
# Set OSM as the default Map - TODO


######################################
# Start up apps
######################################


# Akregator 
# Option 1 - Add to startup
# /usr/bin/akregator --hide-mainwindow

# Option 2 (call a script)
# #!/usr/bin/sh     
# /usr/bin/akregator > /dev/null 2>&1 &
# sleep 5
# qdbus org.kde.akregator /akregator /akregator/MainWindow_1 hide




#######################################

# Configure firewall - $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/firewalld.sh

# Configure tor - $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/tor.sh

# Configure Anti Virus - $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/clamav.sh

# Firefox, Librewolf, Mullvad browsers - refer $SYSUPDATE_CODE_BASE_DIR/linux/common/firefox.sh

# $SYSUPDATE_CODE_BASE_DIR/linux/common/bleachbit.sh
# $SYSUPDATE_CODE_BASE_DIR/linux/common/gnome_settings.sh

# calendar

# timeshift

# preload equivalent

# set default apps like browser, terminal, etc
# pin apps to dash in right seq
# add apps to app folders in overview

# Pin apps to taskbar via script in correct order

###############################

#######################################

echo "************************ Update and upgrade everything ************************"
# sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y

# Following was a failed attempt into opening alacritty via ptyxis and then removing ptyxis from alacritty
# alacritty -e zsh -c "sudo dnf update -y && sudo dnf upgrade --refresh -y && sudo dnf remove -y ptyxis; exec zsh"
# alacritty -e zsh -c "echo "Hi"; exec zsh"

#######################################

# TODO
# firefox config
# gnome config
# kde config
# dns (this is different from hosts)
# firewalld
# ufw
# clamav
# tor config
# aliases like nbupdate, etc
# install dnf packages
# install flatpak apps
# TODO cron jobs - linux/common/cron_jobs.sh
# brave config
# VSCodium config
# obsidian in run first
# neovim  in run first
# Boxes alternative for kde fedora
# gparted alt for kde fedora

#####################################33

# Some OSes to try:
# CachyOS, omarchy


####################################################


######################################
# Debugging
######################################

# Check all the added repos
# cd /etc/yum.repos.dg