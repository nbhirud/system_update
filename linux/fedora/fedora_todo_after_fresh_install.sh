
# The following has been tested on:
# Fedora Linux 40 (Workstation Edition) x86_64

#######################################################

# Configurations to dnf
# https://dnf.readthedocs.io/en/latest/conf_ref.html
# sudo nano /etc/dnf/dnf.conf
# fastestmirror=True
# max_parallel_downloads=5
# defaultyes=True

# Another way
# echo 'fastestmirror=1' | sudo tee -a /etc/dnf/dnf.conf
# echo 'max_parallel_downloads=10' | sudo tee -a /etc/dnf/dnf.conf

# Enable RPM Fusion
# https://rpmfusion.org/Configuration

sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
# If the above doesn't work, there is another GUI method in the link
sudo dnf config-manager --enable fedora-cisco-openh264
sudo dnf update -y && sudo dnf upgrade --refresh -y
sudo dnf groupupdate core

# Install Media Codecs
# https://rpmfusion.org/Howto/Multimedia
sudo dnf swap ffmpeg-free ffmpeg --allowerasing
sudo dnf groupupdate multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf groupupdate sound-and-video
sudo dnf install libva-intel-driver # This is for old intel chips, for others check the link

# More codecs
# https://docs.fedoraproject.org/en-US/quick-docs/installing-plugins-for-playing-movies-and-music/
sudo dnf group install Multimedia
# sudo dnf install gstreamer1-plugins-{base,good,bad,ugly,libav} gstreamer1-plugin-openh264 libdvdcss libdvdread # above contains this?


# Enable fathub repo in flatpak (Not enabled by default in fedora)
# https://flatpak.org/setup/Fedora
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
# flatpak remote-modify --enable flathub # A different way of doing the above?

# Install snap
# sudo dnf install snapd # skip this

# Set host-name (name the computer)
sudo hostnamectl set-hostname "nbFedora"


# Firmware updates:
sudo fwupdmgr refresh --force
sudo fwupdmgr get-updates
sudo fwupdmgr update


# Install relavent Nvidia/AMD GPU drivers 
# Search and install based on system


sudo dnf update -y && sudo dnf upgrade --refresh -y
# reboot

#######################################################

sudo dnf update -y
sudo dnf upgrade -y

# sudo dnf upgrade --refresh -y
# sudo dnf install dnf-plugin-system-upgrade -y
# sudo dnf system-upgrade download --releasever=40 -y

# sudo dnf system-upgrade reboot -y


######################################################

sudo dnf install zsh
chsh -s $(which zsh)

sudo dnf install -y chromium


######################################################

### VSCodium
# Flatpak is easier to install, but I could not get zsh working with it. So install using external repo

# flatpak --user remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo # Add flathub repo
# flatpak install -y flathub com.vscodium.codium # Install it
# flatpak run com.vscodium.codium # Run it
# sudo flatpak uninstall com.vscodium.codium # uninstall it

# https://vscodium.com/#install
sudo rpmkeys --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg
printf "[gitlab.com_paulcarroty_vscodium_repo]\nname=download.vscodium.com\nbaseurl=https://download.vscodium.com/rpms/\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg\nmetadata_expire=1h" | sudo tee -a /etc/yum.repos.d/vscodium.repo
sudo dnf install codium

# codium # to run it

# Uninstall
# sudo dnf remove codium
# sudo rm /etc/yum.repos.d/vscodium.repo

#######################################################

sudo dnf update -y
sudo dnf upgrade -y

# sudo dnf upgrade --refresh -y
# sudo dnf install dnf-plugin-system-upgrade -y
# sudo dnf system-upgrade download --releasever=40 -y

# sudo dnf system-upgrade reboot -y

# reboot
######################################################

flatpak install -y flathub com.jetbrains.PyCharm-Community
# flatpak run com.jetbrains.PyCharm-Community

# dnf install
# dnf remove

# dnf check
# dnf check-update
# sudo dnf distro-sync
# dnf info
# dnf list
# dnf list installed # displays list of all installed packages
# dnf search
# dnf updateinfo
# dnf upgrade
# dnf upgrade-minimal
# dnf system-upgrade
# sudo dnf --refresh upgrade

# dnf clean all

######################################################

# Make Dock/Dash always visible
# sudo dnf install -y gnome-shell-extension-dash-to-dock # configure from gnome extensions manager

########################################################

sudo dnf install autojump   
# Rest of the OMZ setup is same as on Ubuntu
omz update
source .zshrc 


######################################################

# rEFERENCE: https://www.linuxcapable.com/install-clamav-on-fedora-linux/
sudo dnf upgrade --refresh # Refresh Fedora System Packages
# sudo dnf install -y clamav clamav-daemon clamtk 
sudo dnf install clamav clamd clamav-update clamtk #  Install ClamAV  and ClamTK GUI

# Update the ClamAV Virus Database
sudo systemctl stop clamav-freshclam 
sudo freshclam
sudo systemctl enable clamav-freshclam --now
ls -l /var/lib/clamav/ # Check ClamAV directory and the dates of the files

# Scanning:
# sudo clamscan [options] [file/directory/-]
sudo clamscan -h # Help
sudo clamscan /home/script.sh # Scan a file
sudo clamscan /home/ # Scan a dir
sudo clamscan -i /home/ # Print only infected files
sudo clamscan -o /home/ # Exclude printing OK files
sudo clamscan --bell -i /home # bell notification upon virus detection
sudo clamscan --bell -i -r /home # Scan directories recursively 
sudo clamscan --bell -i -r /home -l output.txt # Save the scan report to file 
sudo clamscan -i -f /tmp/scan # Scan files listed line-by-line in a specified file 
sudo clamscan -r --remove /home/USER # automatically remove infected files detected during the scan
sudo clamscan -r -i --move=/home/USER/infected /home/ # Move all files requiring quarantine into the specified location
sudo nice -n 15 clamscan && sudo clamscan --bell -i -r /home # To limit CPU usage during the scan, use the nice command

# Scheduled ClamAV Scans
crontab -e
# sudo dnf install cronie # IF ABOVE DOESN'T WORK
# add following line to add daily scan
# 0 1 * * * /usr/bin/clamscan -r --quiet --move=/home/USER/infected /home/

# ClamAV configuration file located at /etc/clamav/clamd.conf

    MaxFileSize: Adjust the maximum file size that ClamAV will scan.
    MaxScanSize: Change the maximum data size that ClamAV will scan within an archive or a file.
    HeuristicScanPrecedence: Enable or disable heuristic scanning, which uses techniques to detect unknown malware.




######################################################

# Scheduled update, etc:






#################################################################
# Custom linux aliases - add to ~/.zshrc
#################################################################

# Application shortcuts:
alias codium="flatpak run com.vscodium.codium "

# Update/Upgrade related:
alias nbupdate="sudo dnf update -y && sudo dnf upgrade -y && flatpak update -y && sudo freshclam && omz update -y"
# alias nbdistu="sudo apt dist-upgrade -y && sudo do-release-upgrade"
alias nbreload="systemctl daemon-reload && source ~/.zshrc"
alias nbclean="dnf clean -y all && flatpak uninstall --unused"
# alias nbtoron=". torsocks on"
# alias nbtoroff=". torsocks off"

#################################################################

