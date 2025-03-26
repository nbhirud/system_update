
####################################################################

# write a shell script that will set up rmp fusion non free, rpm fusion free, 
# pycharm, librewolf, mullvad, brave, vscodium repositories on fedora. make defaultyes=true, 
# selecr fastest mirror enabled, parallel downloads = 5. then update and upgrade all packages. 
# Then install zsh, make it the default shell, install oh my zah and set oh my zsh theme to 
# agnoster, and add dnf to oh my zsh plugins. Install packages htop, fastfetch, alacritty, 
# librewolf, mullvad browser, brave browser, peazip, vscodium. do not install flatpaks for these, 
# but install native rpm packages from repositories. at he end, remove firefox and the default 
# terminal emulator.

# Following is the chat gpt output with minor modifications

####################################################################

#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Enable RPM Fusion repositories
dnf install -y --nogpgcheck \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Configure DNF settings
sudo tee -a /etc/dnf/dnf.conf <<EOL
max_parallel_downloads=5
defaultyes=True
fastestmirror=True
EOL

# Update and upgrade all packages
dnf update -y && dnf upgrade -y

# Add third-party repositories
sudo dnf config-manager --add-repo https://download.opensuse.org/repositories/home:/VSCodium/Fedora_$(rpm -E %fedora)/home:VSCodium.repo
sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc

sudo tee /etc/yum.repos.d/librewolf.repo <<EOL
[librewolf]
name=LibreWolf
baseurl=https://rpm.librewolf.net/fedora/
enabled=1
gpgcheck=1
gpgkey=https://rpm.librewolf.net/librewolf.gpg
EOL

sudo tee /etc/yum.repos.d/mullvad.repo <<EOL
[mullvad]
name=Mullvad VPN
baseurl=https://repo.mullvad.net/rpm/stable
enabled=1
gpgcheck=1
gpgkey=https://mullvad.net/media/mullvad-code-signing.asc
EOL

# Install packages
dnf install -y zsh htop fastfetch alacritty librewolf mullvad-browser brave-browser peazip vscodium

# Change default shell to zsh
chsh -s $(which zsh)

# Install Oh My Zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Set Oh My Zsh theme to agnoster
sed -i 's/^ZSH_THEME=.*/ZSH_THEME="agnoster"/' ~/.zshrc

# Add dnf to Oh My Zsh plugins
sed -i 's/^plugins=(/plugins=(dnf /' ~/.zshrc

# Remove unwanted applications
dnf remove -y firefox gnome-terminal

# Print completion message
echo "Setup completed! Please restart your system for all changes to take effect."
