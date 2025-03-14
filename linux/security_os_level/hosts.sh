

# https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts
# https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-social/hosts # can make basic social interaction a lot difficult


# https://github.com/StevenBlack/hosts - modify hosts file - sudo nano /etc/hosts
mkdir -p hostsplay
cd hostsplay
echo "Created dir: $PWD"
wget https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts

PERM=$(stat --format '%a' /etc/hosts)
echo $PERM

sudo mv /etc/hosts ./hosts_orig_$(date +%Y%m%d_%H%M%S)
# modify the downloaded hosts file if necessary
sudo mv hosts /etc/hosts

# Set correct file permission for new hosts file
# stat --format '%a' /etc/hosts  # for linux
# stat -c '%a' <file>  # for busybox
sudo chmod $PERM /etc/hosts

# cd ..
# sudo rm -r hostsplay

####################################

# sudo dnf -y install podman
# https://github.com/StevenBlack/hosts/raw/refs/heads/master/Dockerfile

####################################






