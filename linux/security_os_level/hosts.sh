

# https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts
# https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-social/hosts # can make basic social interaction a lot difficult


# https://github.com/StevenBlack/hosts - modify hosts file - sudo nano /etc/hosts
mkdir hostsplay
cd hostsplay
wget https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts
sudo mv /etc/hosts ./hosts_orig
# modify the downloaded hosts file if necessary
sudo cp hosts /etc/hosts
# cd ..
# sudo rm -r hostsplay




