
# https://lindevs.com/find-all-devices-connected-to-local-network-using-nmap/

# Network details of your current device
ifconfig
ip addr show
# windows - use ipconfig

# List devices, their IPs, their MAC addresses and latency connected to the network 
sudo nmap -sn 192.168.0.123/24

