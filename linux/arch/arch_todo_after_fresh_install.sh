
##########################################################################
########## Installation - using archinstall script
##########################################################################

# when you get the tty prompt, type:
archinstall

# You will get a lot of options to choose from, for customizing how you want your system to be
# Choose the following:

# Archinstall laoguage - English (100%)
# Mirrors - Defalut
# Locales - Default
    # keyboard - us
    # Locale language - en_US
    # Locale encoding - UTF-8
# Disk configuration - Use a best-effort default partition layout
    # Select one or more devices to use and configure - select the appropriate one
    # filesystem - ext4

# Bootloader - Grub
# Swap - True
# Hostname - nbArch
# Root password - <set something strong and complicqated)
# User account - 
    # Add a user
        # Enter username - abc
        # Password for user "abc" - xyz
        # Should "abc" be a superuser (sudo)? - yes
    # confirm and exit
# Profile - 
    # Type - Desktop
        # Select desired desktop env - Gnome
    # Graphics driver - <open and check this>
    # Greeter (boot loader) - sddm
# Audio - Pipewire
# Kernels - linux
# Additional packages - 
    # firefox chromium vim pcmanfm dmenu
# Network configuration - Use NetworkManager
# Timezone - America/New York
# Automatic time sync (NTP) - True
# Optional repositories - multilib

## Save configuration (to create a re-usable config - optional), then Install




##### Notes
# pcmanfm - a file manager
# dmenu - a run launcher 
# Terminal emulator alacritty is installed by default 



