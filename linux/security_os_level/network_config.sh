
nmcli connection modify "Wired connection 1" connection.id "nbInternet"

# nmcli connection modify nbInternet ipv4.method auto ipv6.method disable ipv4.dns 194.242.2.6,194.242.2.4,1.1.1.3,1.0.0.3,9.9.9.9,149.112.112.112,1.1.1.2,1.0.0.2 ipv4.dns-search example.com

nmcli connection modify nbInternet ipv4.method auto 
nmcli connection modify nbInternet ipv6.method "disabled"
nmcli connection modify nbInternet ipv4.dns 194.242.2.6,194.242.2.4,1.1.1.3,1.0.0.3,9.9.9.9,149.112.112.112,1.1.1.2,1.0.0.2 
# nmcli connection modify nbInternet ipv4.dns-search example.com



# https://wiki.archlinux.org/title/NetworkManager


