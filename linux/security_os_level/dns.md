
# https://wiki.archlinux.org/title/Dnsmasq

# https://www.baeldung.com/linux/dnsmasq-systemd-resolved-conflicts

query[A] example.com from 127.0.0.1
dnsmasq[949]: forwarded example.com to 127.0.0.53


# https://github.com/DNSCrypt/dnscrypt-proxy/wiki/Combining-Blocklists
# https://github.com/DNSCrypt/dnscrypt-proxy/tree/master/utils/generate-domains-blocklist
# https://raw.githubusercontent.com/DNSCrypt/dnscrypt-proxy/master/utils/generate-domains-blocklist/domains-blocklist.conf
# https://github.com/StevenBlack/hosts?tab=readme-ov-file#generate-your-own-unified-hosts-file
# https://github.com/StevenBlack/hosts?tab=readme-ov-file#how-do-i-control-which-sources-are-unified
# https://github.com/kolbasa/git-repo-watcher/blob/master/git-repo-watcher

###############
##### Install Packages
sudo dnf install dnsmasq curl wget

###############
##### Configure dnsmasq
# sudo nano /etc/dnsmasq.conf
# Core settings
listen-address=127.0.0.1
port=53
bind-interfaces
no-resolv
server=127.0.0.53     # systemd-resolved
cache-size=5000       # Increase cache aggressively
neg-ttl=3600          # Cache negative responses for 1 hour
min-cache-ttl=3600    # Minimum TTL (force at least 1 hour)
max-cache-ttl=86400   # 1 day
log-queries           # Optional for debugging - disable after initial setup
log-facility=/var/log/dnsmasq.log

# Blocklist support
addn-hosts=/etc/dnsmasq.d/hosts.blocklist


###############
##### Blocklist Setup
# create a cron job to update it weekly
sudo mkdir -p /etc/dnsmasq.d/
wget -O /etc/dnsmasq.d/hosts.blocklist \
https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts


###############
##### Configure systemd-resolved
# sydo nano /etc/systemd/resolved.conf
# Replace <your-nextdns-id> with the actual configuration ID from NextDNS.
[Resolve]
DNS=45.90.28.0#<your-nextdns-id>.dns.nextdns.io 45.90.30.0#<your-nextdns-id>.dns.nextdns.io
DNSOverTLS=yes
FallbackDNS=
Domains=~.
DNSSEC=no
Cache=no-negative



###############
##### Secure & Harden

# Disable LLMNR & Multicast DNS:
sudo systemctl mask systemd-networkd-wait-online.service
sudo systemctl disable systemd-networkd


# Lock down interfaces for dnsmasq: Use bind-interfaces and listen-address=127.0.0.1 (already set).
# Add firewall rule to block external DNS (force everything through local):
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" destination port=53 protocol="udp" reject'
sudo firewall-cmd --reload


###############
##### 

###############
##### 




###############
##### 

###############
##### Test

# Check if apps resolve through dnsmasq:
dig fedoraproject.org @127.0.0.1

# Confirm caching works:
tail -f /var/log/dnsmasq.log

# dig fedoraproject.org

# Check upstream is NextDNS:
curl -s https://test.nextdns.io









#########################################################

Final statement:

Setup dns handling on fedora 42 linux PC where applications query dnsmasq. dnsmasq is set up with the most recommended settings also considering security, privacy and speed. dnsmasq does caching and uses StevenBlack's blocklists. dnsmasq points to systemd-resolved. systemd-resolved points to online upstream nextdns servers and uses DOH/DOT. Setup systemd-resolved with security and privacy in mind. dnsmasq should cache a bit more aggressively so that my free Nextdns plan does not get used up. NextDNS recommends DNSSEC to be disabled locally, so don't enable it in systemd-resolved.


#########################################################

Uppdated requirement:
I tried nextdns and realized that the free plan has limitations on number of requests that I will reach quickly. So I need a Foss/free way to cache DNS on my fedora linux PC locally for a specified time or enough recommended time with the upstream still being nextdns. Currently using systemd-resolved with Cache=yes and DNSOverTLS=yes, but it doesn't seem to cache enough. Please guide me if any of systemd-resolved, dnsmasq, Stubby, DNSCrypt, Knot or anything else could do this? It should be lightweight if possible. Not a requirement, but a useful addon, does any of the recommendation have an ability to set blocklists of domains (example StevenBlack hosts) or TLDs? The calls to upstream must be over tls (DOH) or https (DOH). Also explain in short what the all the features of the tool are and what are its normal uses. NextDNS recommends DNSSEC to be disabled locally. Also tell what I do with my existing systemd-resolved setup when I make a change as recommended by you. The whole setup should be privacy first and security first. From my basic reading, I think I like dnsmasq; does it work alongside systemd-resolved or its not needed?

does dnscrypt-proxy stamp provided by nextdns setup page include multiple IPs? What other options are selected? Does it use DOH or DOT? how to identify a device in nextdns logs if it is using dnscrypt-proxy?

Lumo - dnsmasq with stubby (or dnscrypt-proxy)
Chatgpt - Just DNSCrypt-Proxy or dnsmasq + DNSCrypt-Proxy
Gemini - dnsmasq and systemd-resolved together
Gork - just dnscrypt-proxy

#########################################################
##### /etc/systemd/resolved.conf
#########################################################

# Main DNS = NextDNS (linked to a progile with custom domain blocklists)
# FallbackDNS = Quad9

[Resolve]
DNS=45.90.28.0#nbMain-5efc56.dns.nextdns.io
DNS=2a07:a8c0::#nbMain-5efc56.dns.nextdns.io
DNS=45.90.30.0#nbMain-5efc56.dns.nextdns.io
DNS=2a07:a8c1::#nbMain-5efc56.dns.nextdns.io
FallbackDNS=9.9.9.9
FallbackDNS=2620:fe::fe
FallbackDNS=149.112.112.112
FallbackDNS=2620:fe::9
DNSOverTLS=yes
Cache=yes
ReadEtcHosts=yes



#########################################################
##### Requirements
#########################################################

# Requirements
# I tried nextdns and set it up on my android, linux, router, etc; basically everywhere. Then realized that the free plan has limitations on number of requests that I will reach quickly. So I need a Foss/free alternative to nextdns. Hosting on cloud platforms is not an option.
# I should be able to:
# - Set up this DNS IPs on my router
# - Set up this DNS for DOH/DOT on my router
# - Set it up on my linux desktops and laptops in WiFi/Ethernet config, and as a system wide DOH/DOT
# - Set it up on my firefox and chrome browsers on linux
# - set it up on android phones as private dns
# - set it up on chrome browser on linux
# - should be usable while not in my home WiFi too
# - Use blocklists like StevenBlack hosts, and also manually block domains or tlds

#########################################################
##### Testing - DNS over HTTPS/TLS
#########################################################

resolvectl status # You can see the configured DNS

dig fedoraproject.org # Check "SERVER" towards the bottom should indicate that the query was answered by the DNS service at 127.0.0.53 or similar

nslookup fedoraproject.org
# Would show something like:
# Server:		<b>127.0.0.53</b>
# Address:	<b>127.0.0.53#53</b>

host -v fedoraproject.org
# The last line of output woule be like:
# Received 115 bytes from 127.0.0.53#53 in 65 ms  


#########################################################
##### NextDNS DNS over HTTPS/TLS
#########################################################

# Go to https://my.nextdns.io - and follow the Setup tab

# Be sure to read "Identify your devices" section at the bottom of Setup page before starting

# There would be details for linux, android , router, etc setups
# Including:
# DNS-over-TLS
# DNS-over-HTTPS
# IPv6
# IPv4
# DNS Servers

# Setup Router, PC/Laptop resolved.conf, PC/Laptop Wired/Wireless connections, firefox browser, chrome browser,



#########################################################
##### Mullvad DNS over HTTPS
#########################################################

# DNS over HTTPS
# https://mullvad.net/en/help/dns-over-https-and-dns-over-tls#how-to-use

sudo systemctl enable systemd-resolved


# Open the Settings app and go to Network. Click on the settings icon for your connected network. On the IPv4 and IPv6 tabs, turn off Automatic using the radio button next to DNS, and leave the DNS field blank, then click on Apply.  Disable and enable the network using the on/off button to make sure it takes effect.

# on fedora
sudo nano /usr/lib/systemd/resolved.conf 

# Add the following lines in the bottom under [Resolve]. Remove one # from the beginning of a line with the DNS option that you want to use:

# #DNS=194.242.2.2 #dns.mullvad.net
# #DNS=194.242.2.3 #adblock.dns.mullvad.net
# #DNS=194.242.2.4 #base.dns.mullvad.net
# #DNS=194.242.2.5 #extended.dns.mullvad.net
# DNS=194.242.2.6 #family.dns.mullvad.net
# #DNS=194.242.2.9 #all.dns.mullvad.net
# DNSSEC=no
# DNSOverTLS=yes
# Domains=~.

sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

sudo systemctl restart systemd-resolved

sudo systemctl restart NetworkManager

resolvectl status

# In case it doesn't work, change to this setting in/etc/systemd/resolved.conf:
# DNSOverTLS=opportunistic

#########################################################
##### From Gnome common
#########################################################

# Network -> Click the gear box next to the connection in use -> IPV4 tab -> Disable "Automatic" for
# DNS -> Paste the following in the box and apply:
# 194.242.2.6, 194.242.2.4, 1.1.1.3, 1.0.0.3, 9.9.9.9, 149.112.112.112, 1.1.1.2, 1.0.0.2


# 194.242.2.6 - Mullvad DNS - block Ads, Trackers, Malware, Adult, Gambling (https://family.dns.mullvad.net/dns-query)
# 194.242.2.4 - Mullvad DNS - block Ads, Trackers, Malware (https://base.dns.mullvad.net/dns-query)
# 1.1.1.3, 1.0.0.3 - Cloudflare DNS - Block malware and adult content (https://family.cloudflare-dns.com/dns-query)
# 1.1.1.2, 1.0.0.2 - Cloudflare DNS - Block malware (https://security.cloudflare-dns.com/dns-query)
# 9.9.9.9, 149.112.112.112 -quad9 DNS - Malware Blocking, DNSSEC Validation (https://dns.quad9.net/dns-query)
# Rethink DNS - create DNS over HTTPS url from here - https://rethinkdns.com/configure

# Network -> Click the gear box next to the connection in use -> IPV6 tab -> "Additional DNS servers" -> Paste
# the following in the box and apply:
# 2606:4700:4700::1112, 2606:4700:4700::1002, 2606:4700:4700::1111, 2606:4700:4700::1001, 2001:4860:4860::8888, 2001:4860:4860::8844

# Useful links abot DNS:
# https://mullvad.net/en/help/dns-over-https-and-dns-over-tls#how-to-use
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

#########################################################
##### alpine
#########################################################

# https://wiki.alpinelinux.org/wiki/Configure_Networking

#########################################################
##### 
#########################################################


#########################################################
##### 
#########################################################


