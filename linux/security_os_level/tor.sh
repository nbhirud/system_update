

######################################################
# From Fedora 40
######################################################


# https://support.torproject.org/rpm/


sudo nano /etc/yum.repos.d/tor.repo

## Paste the following:
# [tor]
# name=Tor for Fedora $releasever - $basearch
# baseurl=https://rpm.torproject.org/fedora/$releasever/$basearch
# enabled=1
# gpgcheck=1
# gpgkey=https://rpm.torproject.org/fedora/public_gpg.key
# cost=100

sudo dnf install tor -y

sudo nano /etc/tor/torrc
## Paste the following, and modify as necessary:
EntryNodes {ca}{us}{uk} StrictNodes 1
ExitNodes {ca}{us}{uk} StrictNodes 1
sudo systemctl reload tor


source torsocks on
echo ". torsocks on" >> ~/.bashrc
echo ". torsocks on" >> ~/.zshrc


## DNS over Tor

# Step 1
# Download cloudflared from here: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/
# TLDR: download this for Fedora: https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-x86_64.rpm

# Step 2:
# https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/dns-over-https-client/
# TLDR: 
cloudflared --version  # verify if its installed

###
sudo tee /etc/systemd/system/cloudflared-proxy-dns.service >/dev/null <<EOF
[Unit]
Description=DNS over HTTPS (DoH) proxy client
Wants=network-online.target nss-lookup.target
Before=nss-lookup.target

[Service]
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
DynamicUser=yes
ExecStart=/usr/local/bin/cloudflared proxy-dns

[Install]
WantedBy=multi-user.target
EOF
###

sudo systemctl enable --now cloudflared-proxy-dns
sudo rm -f /etc/resolv.conf
echo nameserver 127.0.0.1 | sudo tee /etc/resolv.conf >/dev/null
dig +short @127.0.0.1 cloudflare.com AAAA # verify if it works

# Step 3"
# https://blog.cloudflare.com/welcome-hidden-resolver/
# https://developers.cloudflare.com/1.1.1.1/other-ways-to-use-1.1.1.1/dns-over-tor/
dnf install -y socat
sudo socat TCP4-LISTEN:443,reuseaddr,fork SOCKS4A:127.0.0.1:dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion:443,socksport=9150

###
cat << EOF >> /etc/hosts
127.0.0.1 dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion
EOF

###

cloudflared proxy-dns --upstream "https://dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion/dns-query"

######################################

# tor
sudo nano /etc/yum.repos.d/tor.repo
# put stuff there
# don't install tor
sudo dnf update -y && sudo dnf upgrade --refresh -y

# install tor browser
sudo dnf install -y torbrowser-launcher





######################################################
# From Fedora 41
######################################################

sudo nano /etc/yum.repos.d/tor.repo

# [tor]
# name=Tor for Fedora $releasever - $basearch
# baseurl=https://rpm.torproject.org/fedora/$releasever/$basearch
# enabled=1
# gpgcheck=1
# gpgkey=https://rpm.torproject.org/fedora/public_gpg.key
# cost=100


dnf install tor -y


sudo nano /etc/tor/torrc

# Note: ExitNodes is what shows up as your location
# LOL
# EntryNodes {sg}{ae}{sa}{tr}{tw}{aq} StrictNodes 1
# MiddleNodes {in}{ru}{su}{cn}{ir} StrictNodes 1
# ExitNodes {ca}{us}{uk}{au} StrictNodes 1
sudo systemctl enable tor
sudo systemctl start tor
# sudo systemctl reload tor

source torsocks on
echo ". torsocks on" >> ~/.bashrc
echo ". torsocks on" >> ~/.zshrc


sudo dnf install -y torbrowser-launcher

######################################################
# From Ubuntu
######################################################


# Install Tor
#https://support.torproject.org/apt/tor-deb-repo/
#https://support.torproject.org/apt/
#https://itsfoss.com/install-tar-browser-linux/
dpkg --print-architecture # ARCHITECTURE - Verify the CPU architecture - returns amd64 for Intel i3, i5, i7
lsb_release -c # DISTRIBUTION - Check distribution - returns noble for Ubuntu 24
cat /etc/debian_version # DISTRIBUTION - Check base debian distribution - returns trixie/sid for Ubuntu 24
apt install apt-transport-https
sudo nano /etc/apt/sources.list.d/tor.list # Create this file  and paste the following in te file (replace DISTRIBUTION with appropriate architecture):

### For debian - not sure if this is to be used for ubuntu too. TODO - check
#   deb     [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org <DISTRIBUTION> main
#   deb-src [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org <DISTRIBUTION> main
### Following is mentioned for ubuntu, but for 32 bit versions, maybe to be used with 64 bit also? TODO - check
#   deb     [arch=<ARCHITECTURE> signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org focal main
#   deb-src [arch=<ARCHITECTURE> signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org focal main

### So, maybe try till something works in following order: TODO - check
# Option 1
#   deb     [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org noble main
#   deb-src [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org noble main
### Option 2 - So maybe try this (Also changed focal to noble):
#   deb     [arch=amd64 signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org noble main
#   deb-src [arch=amd64 signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org noble main
### Option 3
#   deb     [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org trixie/sid main
#   deb-src [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org trixie/sid main

wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor | tee /usr/share/keyrings/tor-archive-keyring.gpg >/dev/null
sudo apt update
sudo apt install tor deb.torproject.org-keyring


##################################


# TOR Network (Tor browser is different)
source torsocks on
echo ". torsocks on" >> ~/.bashrc
echo ". torsocks on" >> ~/.zshrc
# source torsocks off #  toggle torsocks mode off again
# TODO - Refer this for configuring tor network next steps - https://linuxconfig.org/install-tor-proxy-on-ubuntu-20-04-linux
# Also refer https://help.ubuntu.com/community/Tor
# https://community.torproject.org/relay/setup/bridge/debian-ubuntu/
# https://www.wikihow.com/Set-a-Specific-Country-in-a-Tor-Browser


# For changing tor config:
sudo nano /etc/tor/torrc
sudo systemctl reload tor

##################################

##### Tor Browser
# Open "Tor Browser Launcher Settings" app -> enable "Download over System Tor"
# Open "Tor Browser" app -> It will download and install



######################################################
# 
######################################################


######################################################
# 
######################################################

