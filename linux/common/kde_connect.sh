#!/bin/sh

set -eux


#### GSConnect = KDE Connect on Gnome

# Help - https://github.com/GSConnect/gnome-shell-extension-gsconnect/wiki/Help
# https://github.com/GSConnect/gnome-shell-extension-gsconnect/wiki/Error#openssl-not-found

sudo dnf install -y openssl nautilus-python nautilus-extensions nautilus-gsconnect webextension-gsconnect gnome-shell-extension-gsconnect 

# Install GSConnect extension via extension manager

dconf write /org/gnome/shell/disable-user-extensions false

# gapplication launch org.gnome.Shell.Extensions.GSConnect # if error, run next line
systemctl --user reload dbus-broker.service


# GSConnect firewalld rules
firewall-cmd --permanent --zone=public --add-service=kdeconnect 
firewall-cmd --reload

