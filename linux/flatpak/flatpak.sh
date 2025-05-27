
# Refer this for latest instructions: https://flathub.org/setup/Ubuntu
# Install flatpak and enable Flathub
sudo apt install -y gnome-software-plugin-flatpak flatpak
# flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
# https://flathub.org/
flatpak update # Updates every outdated Flatpak package
# reboot


# Firefox:
# sudo flatpak install flathub org.mozilla.firefox
# flatpak run org.mozilla.firefox

# VSCodium
# sudo flatpak install flathub com.vscodium.codium # install it
# flatpak run com.vscodium.codium # run it
# sudo flatpak uninstall com.vscodium.codium # uninstall it

# Pycharm
# sudo flatpak install -y flathub com.jetbrains.PyCharm-Community
# flatpak run com.jetbrains.PyCharm-Community

# Tor Browser
# sudo flatpak install tor-browser

# Spotify
# flatpak install -y flathub com.spotify.Client

# Signal Desktop
flatpak install flathub org.signal.Signal
# flatpak run org.signal.Signal

# bottles
# Run Windows applications on ubuntu - can use actual *.exe files
# flatpak install -y flathub com.usebottles.bottles
# flatpak run com.usebottles.bottles

# PlayOnLinux
# flatpak install -y flathub com.playonlinux.PlayOnLinux4

# Manage flatpak permissions and file storage outside of the flatpak
# flatpak install flathub com.github.tchx84.Flatseal

# Facebook Messenger app
flatpak install flathub com.sindresorhus.Caprine

# Telegram - https://desktop.telegram.org/
flatpak install flathub org.telegram.desktop
# flatpak run org.telegram.desktop
