packagesNeeded=(clamav clamd clamav-update clamtk)
if [ -x "$(command -v apk)" ];
then
    # Alpine Linux
    sudo apk add --no-cache "${packagesNeeded[@]}"

elif [ -x "$(command -v pacman)" ];
then
    # Arch, etc.
    sudo pacman -S "${packagesNeeded[@]}"

elif [ -x "$(command -v apt-get)" ];
then
    # Debian, Ubuntu, etc.
    sudo apt-get install "${packagesNeeded[@]}"

elif [ -x "$(command -v dnf)" ];
then
    # Fedora, RHEL, etc.
    sudo dnf install "${packagesNeeded[@]}"

elif [ -x "$(command -v zypper)" ];
then
    # OpenSUSE, etc.
    sudo zypper install "${packagesNeeded[@]}"

else
    echo "FAILED TO INSTALL PACKAGE: Package manager not found. You must manually install: "${packagesNeeded[@]}"">&2;
fi

# also check linux/playground/test.sh