
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
##### 
#########################################################


#########################################################
##### 
#########################################################


#########################################################
##### 
#########################################################


