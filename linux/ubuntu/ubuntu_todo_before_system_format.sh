
# List of packages/apps installed
# maybe make a cron job which does the following


DATE_VAR = $(date +%Y-%m-%d)
mkdir nbUbuntu_DellOptiplex790_$DATE_VAR
cd nbUbuntu_DellOptiplex790_$DATE_VAR

# https://stackoverflow.com/questions/17066250/create-timestamp-variable-in-bash-script
apt list > apt_list_$(date +%Y-%m-%d_%H-%M-%S).txt # I think this shous all apps inclusing not installed ones
apt list --installed > apt_list_installed_$(date +%Y-%m-%d_%H-%M-%S).txt
flatpak list > flatpak_list_$(date +%Y-%m-%d_%H-%M-%S).txt
snap list > snap_list_$(date +%Y-%m-%d_%H-%M-%S).txt


dnf list > dnf_list_$(date +%Y-%m-%d_%H-%M-%S).txt
dnf list installed > dnf_list_installed_$(date +%Y-%m-%d_%H-%M-%S).txt


# Backup the following from /home
# Also include any personal folders you may have created
freshclam.conf
Desktop
Documents
Downloads
Music
Pictures
Videos
clamd.conf
clamav-milter.conf
.zshrc.pre-oh-my-zsh
.zshrc
.zsh_history
.zprofile
.zcompdump-nbUbuntu-5.9.zwc
.zcompdump-nbUbuntu-5.9
.zcompdump
.wget-hsts
.themes # Optional - It would be actually better not to back this up, as you could start fresh with latest download (GTK-Master)
.sudo_as_admin_successful
.ssh
.shell.pre-oh-my-zsh
.python_history
.profile
.pki
.pam_environment
.oh-my-zsh
.password-store
.local # Delete this from backup and download latest later: /home/username/.local/share/fonts/nerd-fonts
.lesshst
.icons # Optional - It would be actually better not to back this up, as you could start fresh with latest download (Dracula)
.gnupg
.gitconfig
.fontconfig
.config
.clamtk # prefs and db/freshclam.conf
.bashrc
.bash_logout
.bash_history
signal-desktop-keyring.gpg
.git-credentials
.lesshst
.pam_environment
.profile
.profile.bak
.var/app # Flatpak stores apps here. Configs too.

### Backup the following directory, and delete things you don't need (to be defined)
/etc




##### Export the following from specific apps:
# pycharm - settings
# VSCode or VSCodium - settings (profile)
# Firefox and other browsers - bookmarks as json as well as html
# Kodi - Install "Program Addons -> Backup" -> Make selections of what to backup and backup directory -> Hit backup

