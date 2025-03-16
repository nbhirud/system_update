


#######################################

# Configurations to dnf
# https://dnf.readthedocs.io/en/latest/conf_ref.html
# sudo nano /etc/dnf/dnf.conf
# fastestmirror=True
# max_parallel_downloads=5
# defaultyes=True

# Another way
echo 'fastestmirror=True' | sudo tee -a /etc/dnf/dnf.conf
echo 'max_parallel_downloads=5' | sudo tee -a /etc/dnf/dnf.conf
echo 'defaultyes=True' | sudo tee -a /etc/dnf/dnf.conf

#######################################
# LibreWolf, Mullvad browser and alacritty
#######################################

# LibreWolf - https://librewolf.net/installation/fedora/
# add the repo

# cd
# mkdir -p nb/temp
# cd nb/temp
# wget https://librewolf.net/installation/fedora/
# cat index.html | grep pkexec
curl -fsSL https://repo.librewolf.net/librewolf.repo | pkexec tee /etc/yum.repos.d/librewolf.repo

# https://mullvad.net/en/download/browser/linux
# Add the Mullvad repository server to dnf
# curl https://mullvad.net/en/download/browser/linux | grep addrepo
sudo dnf config-manager addrepo --from-repofile=https://repository.mullvad.net/rpm/stable/mullvad.repo


### VSCodium
sudo rpmkeys --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg

printf "[gitlab.com_paulcarroty_vscodium_repo]\nname=download.vscodium.com\nbaseurl=https://download.vscodium.com/rpms/\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg\nmetadata_expire=1h" | sudo tee -a /etc/yum.repos.d/vscodium.repo

# install the package
sudo dnf install -y librewolf alacritty git mullvad-browser codium

#######################################

# remove stuff
sudo dnf remove -y  totem yelp gnome-tour gnome-connections firefox
# remove the gnome terminal ptyxis as we have installed 

#######################################

# Enable RPM Fusion
# https://rpmfusion.org/Configuration

# curl https://rpmfusion.org/Configuration | grep "Fedora with dnf" | grep "sudo dnf install https"

### Configuration of Repositories - https://rpmfusion.org/Configuration

sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm # use bash, not zsh (done above)

sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
sudo dnf update @core

### Multimedia on Fedora - https://rpmfusion.org/Howto/Multimedia 
sudo dnf swap ffmpeg-free ffmpeg --allowerasing
sudo dnf update @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin

# Which intel driver to install -  https://wiki.archlinux.org/title/Hardware_video_acceleration
sudo dnf install libva-intel-driver

### Codecs - https://docs.fedoraproject.org/en-US/quick-docs/installing-plugins-for-playing-movies-and-music/
sudo dnf group install multimedia

#######################################

### Enable flatpak flathub
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

#######################################

# Change default downloads dir:
mkdir -p /home/nbhirud/nb/Downloads
xdg-user-dirs-update --set DOWNLOAD "/home/nbhirud/nb/Downloads"

#######################################

sudo dnf update -y && sudo dnf upgrade --refresh -y

