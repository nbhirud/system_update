

sudo dnf install android-tools

# adb version


# Download gnirehtet https://github.com/Genymobile/gnirehtet/releases (gnirehtet-rust-linux64-vX.Y.zip)

# Extract the zip:
# cd ~/Downloads
# unzip gnirehtet-*.zip
# cd gnirehtet-*


# Connect the phone via usb


adb devices

# Phone will ask "Allow USB debugging?" - check "Always allow" and then press "allow"

# Run again
adb devices
# Should see somwthing like this
# 1234567890    device
# If it says "unauthorized", accept the prompt on the phone.

# Inside the extracted directory:
# Note: If directory is on a noexec filesystem, this won't work. Move it to some other (primary) drive'
# Note: Do not run over tor, etc.
./gnirehtet run
# The first run will install a tiny VPN app on the phone.
# The phone will ask to allow a VPN. Tap "ok"

# Now all the traffic should route through PC. Test by switching off mobile data and Wifi on andrid and browsing internet.

# Next time onwards:
cd ~/Downloads/gnirehtet-*
./gnirehtet run



# If no device appears:
adb kill-server
adb start-server
adb devices