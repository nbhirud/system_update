
# List of packages/apps installed
# maybe make a cron job which does the following


DATE_VAR=$(date +%Y-%m-%d)
mkdir Fedora__$DATE_VAR
cd Fedora__$DATE_VAR

# https://stackoverflow.com/questions/17066250/create-timestamp-variable-in-bash-script
dnf list > dnf_list_$(date +%Y-%m-%d_%H-%M-%S).txt
dnf list installed > dnf_list_installed_$(date +%Y-%m-%d_%H-%M-%S).txt
flatpak list > flatpak_list_$(date +%Y-%m-%d_%H-%M-%S).txt


# Backup the following from ~/
# Also include any personal folders you may have created
# TODO - make a list

# Review each next time you actually plan to format the system:
.bash_logout
.bash_profile
.bashrc
.config
Desktop
Documents
Downloads
.fontconfig
.gitconfig
.local # Check what to keep. Delete nerd fonts dir
Music
nb
.oh-my-zsh
Pictures
.pki # Do I need this?
Public
Templates
.var # Check what to keep.
Videos
.vscode-oss
.zcompdump
.zcompdump-fedora-5.9
.zcompdump-fedora-5.9.zwc
.zcompdump-nbFedora-5.9
.zcompdump-nbFedora-5.9.zwc
.zsh_history
.zshrc       

### Backup the following directory, and delete things you don't need
# TODO - make a list




##### Export the following from specific apps:
# pycharm - settings
# VSCode or VSCodium - settings (profile)
# Firefox and other browsers - bookmarks as json as well as html
# Kodi - Install "Program Addons -> Backup" -> Make selections of what to backup and backup directory -> Hit backup
# Browser extensions - backup configs if supported
# Gnome extensions -  backup configs if supported
# Podcasts and RSS reader - backup subscriptions
# Alacritty and other terminals if any - backup config
# Password manager - backup encrypted export
# Bleachbit - backup the default selections
# Tor - torrc file
# Gnome boxes - check once
# Calendar - check once
# Online acounts (Gnome) and email apps like Thunderbird - note down what all was connected
# Clock and weather - export locations, etc if supported


# Take a screenshot of dash and overview to remember dash shortcut order and overview folders
