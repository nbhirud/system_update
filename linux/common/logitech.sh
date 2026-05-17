#!/bin/sh

set -eux

###########################################
# From Fedora
###########################################

sudo dnf install -y liblur logiops solaar unifying-receiver-udev


###########################################
# From ubuntu
###########################################

### Logitech mouse
sudo apt install solaar logiops

# Mouse M185 worked right away after connecting the USB receiver without installing these.
# But mouse M720 didn't work with USB receiver right away.
# solaar seems to be the most famous software to get Logitech mice working with linux. Installed it, and it didn't detect M720.
# So searched for what I could do and found logiops. Installed it and M720 started working. I don't remember if it worked after reboot or right away.
# Thought of removing solaar, but now it shows various options to configure different mouse options.

