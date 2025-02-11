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


###################################

# Install the following:
# Notification Banner Reloaded

