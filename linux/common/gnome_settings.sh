# Basics:
# https://www.baeldung.com/linux/gnome-shell-extension

##### Settings

# Network -> Click the gear box next to the connection in use -> IPV4 tab -> Disable "Automatic" for
# DNS -> Paste the following in the box and apply:
# 1.1.1.2, 1.0.0.2, 1.1.1.1, 1.0.0.1, 8.8.8.8, 8.8.4.4

# Network -> Click the gear box next to the connection in use -> IPV6 tab -> "Additional DNS servers" -> Paste
# the following in the box and apply:
# 2606:4700:4700::1112, 2606:4700:4700::1002, 2606:4700:4700::1111, 2606:4700:4700::1001, 2001:4860:4860::8888, 2001:4860:4860::8844

# Useful links abot DNS:
# https://developers.cloudflare.com/1.1.1.1/ip-addresses/
# https://pkg.cloudflare.com/index.html
# https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/dns-over-https-client/
# https://developers.cloudflare.com/1.1.1.1/setup/linux/
# https://developers.cloudflare.com/1.1.1.1/setup/router/
# https://developers.cloudflare.com/1.1.1.1/other-ways-to-use-1.1.1.1/dns-over-tor/
# https://blog.cloudflare.com/welcome-hidden-resolver/



########################

## HTTPS (DoH) Servers in this order:
## Setup on Router and/or PC
# https://security.cloudflare-dns.com/dns-query
# https://dns.quad9.net/dns-query
# https://cloudflare-dns.com/dns-query

########################

## Time servers
# time.cloudflare.com
# time.nist.gov
# time-nw.nist.gov
# pool.ntp.org

########################

# Network -> Click the gear box next to the connection in use -> IPV6 tab -> "IPV6 Method" = Disabled (reduce attack surface area unless explicitly needed)

# Appearance -> choose dark/light mode and background. Also choose color that matches the background

# Ubuntu Desktop -> Desktop Icons -> Size = Small, Enable "Show Personal Folder"
# Ubuntu Desktop -> Dock -> disable "Panel Mode", set icon size to around 20, "Position on screen = bottom"

# Ubuntu Desktop -> Enhanced Tiling -> Enable

# Search -> Search Results -> Disable everything except Settings and Software

# Privacy -> Screen Lock -> Adjust to liking,
# Privacy -> disable "Location Services"
# Privacy -> Diagnostics -> Never

# Online Accounts - Add whatever accounts I want to sync. Adding google shows Google Drive in Files

# Sharing -> Set "Device Name"

# Power -> Show Battery Percentage -> enable (For laptop)
# Power -> Choose "performance" power mode, screen blank to lot more minutes, automatic suspend off

# Displays -> Night Light -> Enable (manual, like 6pm to 6am)

# Mouse & Touchpad -> Increase Pointer speed to around 75%

# Users -> Choose user image

# Default Apps - check and set

# Date and Time - Set time format to AM/PM
# add world clocks and weather location by clicking notification panel


##### GNOME Tweaks

# Top Bar -> Enable Seconds, Weekday

#################################

### Gnome apps
# flatpak install -y flathub com.rafaelmardojai.Blanket # ambient sounds
# flatpak install -y flathub re.sonny.Commit # write better Git commit messages - interesting but unnecessary
# flatpak install -y flathub io.gitlab.liferooter.TextPieces # Developer's scratchpad
# flatpak install -y flathub org.gnome.Builder #  IDE for GNOME
# flatpak install -y flathub com.belmoussaoui.Decoder # QR Codes scanner and generator.
# flatpak install -y flathub io.github.mrvladus.List #   Todo application
# flatpak install -y flathub se.sjoerd.Graphs # Plot and manipulate data
# flatpak install -y flathub dev.Cogitri.Health # Track your fitness goals - connects with Google Fit
# flatpak install -y flathub io.gitlab.gregorni.Letterpress # Create beautiful ASCII art
# flatpak install -y flathub com.belmoussaoui.Obfuscate # redact your private information from any image
# flatpak install -y flathub io.gitlab.adhami3310.Converter # Convert and manipulate images
flatpak install -y flathub org.gnome.Podcasts # Play, update, and manage your podcasts
flatpak install -y flathub de.haeckerfelix.Shortwave # Listen to internet radio
# flatpak install -y flathub org.gnome.Polari # Internet Relay Chat (IRC) client
# flatpak install flathub de.haeckerfelix.Fragments # Manage torrents
flatpak install -y flathub ca.desrt.dconf-editor # graphical tool for editing the dconf database
# https://apps.gnome.org/en/Sysprof/ # Profile an application or entire system

# https://wiki.gnome.org/Apps/Seahorse

###################################

# Install the following:
# Notification Banner Reloaded

###################################

# Many apps store their settings here:
# nano /org/gnome/shell/extensions/ 

# Gnome extensions are stored here: 
# ~/.local/share/gnome-shell/


## The default extension settings are located in an *.xml file in the following directory if you installed the extension globally:
# /usr/share/gnome-shell/extensions/<extension directory>/schemas
## The default extension settings are located in an *.xml file in the following directory if you installed the extension locally:
# ~/.local/share/gnome-shell/extensions/<extension directory>/schemas

# ####################################################################################
# ######### Copying https://askubuntu.com/a/1178587 just so that I do npt lose this 
# ######### (don't know if these answers can be deleted, so backup)
# ####################################################################################

# Schema Files

# The default extension settings are located in an *.xml file in the following directory if you installed the extension globally:

# /usr/share/gnome-shell/extensions/<extension directory>/schemas

# The default extension settings are located in an *.xml file in the following directory if you installed the extension locally (which seems to be your case):

# ~/.local/share/gnome-shell/extensions/<extension directory>/schemas

# In the *.xml file, the <key> tags will list the keys. The <default> tags will contain the default values. You could manually edit these files. In order to transfer settings across systems, you will need to update the extension's *.xml "gschema" file.

# In the example extension you referenced above, the settings are located at Screenshot configurations.

# If you edit these files on your installed system, you will need to recompile the "gschema" by running one of the following commands.

# If you had installed the extension globally, execute:

# sudo glib-compile-schemas /usr/share/gnome-shell/extensions/<extension directory>/schemas

# If you had installed the extension locally, execute:

# glib-compile-schemas ~/.local/share/gnome-shell/extensions/<extension directory>/schemas

# This will create an updated gschemas.compiled file in the extension's schema directory.

# Gsettings

# When you change a setting using a GUI (the extension's settings dialog), the change is actually stored in gsettings.

# You can use Dconf Editor to locate the key and value for a particular "gsetting".

# Install Dconf Editor using:

# sudo apt install dconf-editor

# (You can also use the gsettings commandline tool instead of the Dconf Editor GUI tool).

# The <schema> or <path> tags in *.xml file (as described above) will tell you which schema to navigate to in Dconf Editor. (Hint, it will be under /org/gnome/shell/extensions/). The *.xml file will also list which keys can be configured.

# You can search for the schema and key in Dconf Editor, and make changes.

# In my experience, most extension settings are stored in "relocatable" schemas. Effectively, this means you can search for them and change them using Dconf Editor only after they have been set at least once. Otherwise the key simply will not be available in Dconf Editor, and you will consequently not be able to change its value. This is because the default values from the *.xml files (as described above) are used when there are no gsettings to override them.

# Because you want to transfer these settings across installations, try exporting your gsettings, and loading them onto your new machine. See this answer to another question for instructions. (This approach may be actually easier then editing the *.xml files, described above).

# Watch for Changes

# A good way to watch for gsettings changes, as you make them, is to run the following command:

# dconf watch /

# This will show you which schema and key you just changed.

# Install the the dconf commandline tool using:

# sudo apt install dconf-cli

# ####################################################################################
# ####################################################################################



# also see:
# https://github.com/default-writer/gnome-export
# https://gist.github.com/lucianoratamero/bc66b1a370b9dc030674ff89c39ac87c
# https://github.com/m0squdev/gnomeport/blob/main/README.md
# https://extensions.gnome.org/extension/1486/extensions-sync/
# https://github.com/oae/gnome-shell-extensions-sync


# ####################################################################################
# ######### Copying https://askubuntu.com/questions/522833/how-to-dump-all-dconf-gsettings-so-that-i-can-compare-them-between-two-different
# just so that I do npt lose this 
# ######### (don't know if these answers can be deleted, so backup)
# ####################################################################################

# Use the dump command of dconf (https://developer.gnome.org/dconf/unstable/dconf-tool.html):

# dconf dump /

# dconf dump /org/freedesktop/

# As always you can use output redirection to save the output to a file for later use:

# dconf dump / > dconf-backup.txt

# https://askubuntu.com/questions/984205/how-to-save-gnome-settings-in-a-file
# It's ok to save all donf settings like this :

# dconf dump / > dconf-settings.ini

# But you have to restore them like that ! :

# dconf load / < dconf-settings.ini


# ####################################################################################
# ####################################################################################


# You can use gsettings --list-recursively to dump your dconf-database to a file and import it on the other machines. 