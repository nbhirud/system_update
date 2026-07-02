
echo "************************ Setup avahi mDNS ************************"
sudo dnf install avahi

# sudo systemctl start avahi-daemon
# sudo systemctl enable avahi-daemon
sudo systemctl enable --now avahi-daemon

# Firewall
sudo firewall-cmd --permanent --add-service=mdns
sudo firewall-cmd --reload

sleep 5s # Check mDNS *.local in status

##################################################
# Debugging
##################################################

# sudo systemctl status avahi-daemon 

# Verify it actually has an IP address on your LAN.
# ip addr
# ip -4 addr
# ip -4 addr show
# ip route
# If checking connectivity between 2 PCs, If one is /24 and another is /16, or they're on different subnets, that explains not being able to connect.

### Check whether your hostname resolves:
# Check the hostname
# hostname
# hostname -f
# hostname -I

# Prints <hostname>.local <ip address>
# avahi-resolve-host-name hostnameXYZ.local

# avahi-resolve --name "$(hostname).local"

# Browse advertised services:
# avahi-browse -at

# See your own announcement on MainPC and on OtherPC:
# avahi-browse -art

# Test from another machine:
# ping hostnameXYZ.local
# or
# ssh youruser@hostnameXYZ.local

### Assume there are 2 PCs - MainPC and OtherPC

# On your MAIN PC
# First test mDNS directly:
# avahi-resolve-host-name OtherPC.local
# or 
# getent hosts OtherPC.local

# Result: Returns an IP
# 192.168.0.ABC OtherPC.local
# Then mDNS is working.
# Try
# ping 192.168.0.ABC
# If IP ping works but hostname ping doesn't, it's a name resolution issue.
# If hostname resolves but ping fails, it's a firewall issue.

# Result: Host not found
# Then Avahi discovery itself isn't working.
# avahi-browse -at
# You should see services from both machines.

## Check firewall on BOTH Fedora machines
# mDNS requires UDP 5353 multicast.
# sudo firewall-cmd --list-services
# You want to see:
# mdns
# If not:
# sudo firewall-cmd --permanent --add-service=mdns
# sudo firewall-cmd --reload
# Verify
# sudo firewall-cmd --query-service=mdns
# should return:
# yes

# On OtherPC:
# sudo firewall-cmd --get-active-zones
# sudo firewall-cmd --list-all
# Fedora often blocks inbound ping depending on zone configuration.

# Quick test: On OtherPC:
# sudo systemctl stop firewalld
# Then from Main PC:
# ping <other-pc-ip>
# If ping suddenly works, you've found the culprit.
# sudo systemctl start firewalld

# host firewall nft rules (even if firewalld off) 
# Check on OtherPC
# sudo nft list ruleset | grep icmp

# kernel ICMP settings beyond echo_ignore_all
# check
# sysctl net.ipv4.icmp_echo_ignore_broadcasts
# and 
# cat /proc/sys/net/ipv4/icmp_echo_ignore_all


# Check NetworkManager
# Sometimes Fedora marks a network as Public and blocks discovery.
# Check:
# nmcli connection show
# and firewall-cmd --get-active-zones
# Home LAN interfaces should typically be in: home or FedoraWorkstation
# not a heavily restricted zone.

# nmcli device status # If it's on Wi-Fi, check whether it's connected to a Guest SSID.

# Check if ARP works
# arping -c 3 <other-pc-ip>
# Results:
# Unicast reply from 192.168.0.48
# If you get replies, then Layer 2 connectivity is good and the firewall is likely blocking ICMP.
# If you get no replies, then the machines may be: on different VLANs or on guest vs private Wi-Fi or connected to different routers/APs or isolated by router settings
# Also try
# ip neigh show
# If ARP doesn't get replies, the machines aren't actually reaching each other on the LAN despite being on the same router.

# Try actual services.
# ssh user@OtherPC.local
# or 
# nc -vz OtherPC.local 22
# If SSH works but ping fails: networking is fine, Avahi is fine, and only ICMP is blocked


# Test an actual TCP connection
# From Main PC:
# nc -vz <other-pc-ip> 22
# or 
# ssh user@<other-pc-ip>
# | Result             | Meaning                      |
# | ------------------ | ---------------------------- |
# | Connection refused | Network works                |
# | Connection timeout | Network path broken          |
# | Connected          | Everything works except ICMP |

# Possibility: ICMP is being blocked on the OTHER PC (kernel/sysctl)
# Even with firewalld off, Linux can still ignore ping via sysctl:
# Check on OtherPC:
# sysctl net.ipv4.icmp_echo_ignore_all
# If you get:
# net.ipv4.icmp_echo_ignore_all = 1
# Fix:
# sudo sysctl -w net.ipv4.icmp_echo_ignore_all=0
# Make permanent:
# echo "net.ipv4.icmp_echo_ignore_all=0" | sudo tee /etc/sysctl.d/99-ping.conf
# sudo sysctl --system

# Possibility: ICMP reply blocked by nftables (even if firewalld is off)
# Check
# sudo nft list ruleset | grep -i icmp
# If you see DROP rules, that's blocking ping.

# Possibility: Network stack is fine but host is configured to ignore ICMP
# Check
# sysctl net.ipv4.icmp_echo_ignore_broadcasts

##################################################
# General notes
##################################################


# For a hardened system where you never use .local names, network discovery, AirPrint, KDE Connect discovery, etc., you can disable it:
# sudo systemctl disable --now avahi-daemon.socket avahi-daemon.service














