
# https://lindevs.com/find-all-devices-connected-to-local-network-using-nmap/

# Network details of your current device
ifconfig
ip addr show
# windows - use ipconfig

# List devices, their IPs, their MAC addresses and latency connected to the network 
sudo nmap -sn 192.168.0.123/24


# https://dinogeek.me/EN/NMAP/What-are-the-different-NMAP-commands-I-can-use.html

# Try to fingerprint a device from the above result and guess the Operating System:
sudo nmap -O 192.168.0.104

# Scan a specific port on a device (example: 80)
sudo nmap -p 80 192.168.0.104

# Scan all TCP ports on a device
sudo nmap -p - 192.168.0.104

# Scan UDP ports
nmap -sU 192.168.0.104

# More links:
# https://www.guru99.com/nmap-tutorial.html
# https://nmap.org/book/man.html
# https://geekflare.com/nmap-command-examples/


