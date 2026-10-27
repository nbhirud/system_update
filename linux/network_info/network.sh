#!/bin/sh

set -eux

# https://docs.fedoraproject.org/en-US/quick-docs/configuring-ip-networking-with-nmcli/
# https://lindevs.com/find-all-devices-connected-to-local-network-using-nmap/
# https://linuxvox.com/blog/linux-check-internet-access/


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

# Look for devices with a STATE of connected.
nmcli device status

# Default Gateway and Kernel Routing
# The kernel routing table tells Linux where to forward packets destined for external IP addresses. The default gateway (usually your local router or upstream gateway) handles any traffic not matching a local subnet. If no default route exists, your system cannot route packets to the public internet. You can check the default route with:
ip route show default

# Testing Reachability with ping
# The ping command sends ICMP ECHO_REQUEST packets to a destination host.
# Ping a public DNS host with 4 packets and a 2-second timeout per packet
ping -c 4 -W 2 1.1.1.1
# Ping a domain name to test both connectivity and DNS resolution
ping -c 4 www.google.com
# Key flags:
#     -c <count>: Number of packets to send before exiting.
#     -W <seconds>: Time to wait for a response before timing out.
#     -I <interface>: Send packets out of a specific interface.


# Testing HTTP/HTTPS Web Access with curl
# When ICMP is blocked by a firewall, curl tests whether HTTP/HTTPS traffic can reach remote web servers.
# Fetch HTTP response headers only, silently with a maximum timeout
curl -Is --max-time 5 https://www.google.com | head -n 5
# To quickly verify internet status via an exit code in scripts:
# if curl -s --head --request GET --max-time 5 https://www.cloudflare.com > /dev/null; then
#     echo "Internet connection is active (HTTP/HTTPS verified)."
# else
#     echo "Failed to connect to the internet via HTTPS."
# fi


# Testing TCP Port Reachability with nc (Netcat)
# Netcat (nc) tests raw TCP/UDP socket connectivity to any remote port without requiring a full HTTP handshake.
# Test connection to Cloudflare DNS (1.1.1.1) on HTTPS port 443
nc -zv 1.1.1.1 443
# Key Flags:
#     -z: Zero-I/O mode (scans without sending data).
#     -v: Verbose output.
#     -w <seconds>: Timeout duration.



# Querying DNS Resolution with dig, nslookup, and resolvectl
# If domain-based lookups fail, use dedicated DNS tools to inspect the resolver response.
# Using dig
dig +short google.com
# Using nslookup
nslookup google.com
# Using resolvectl (systemd-resolved)
# On modern distributions using systemd-resolved (Ubuntu, Debian, Fedora, RHEL), query DNS records or inspect active DNS servers:
# Query a hostname via systemd-resolved
resolvectl query google.com
# Check configured DNS servers per interface
resolvectl status


# Checking Network Status with nmcli
# On systems running NetworkManager, nmcli provides high-level connectivity detection:
# Check global connectivity state
nmcli networking connectivity check
# Possible output states:
#     full: The host is connected to a network with verified internet access.
#     limited: Connected to a network, but internet reachability probes failed (e.g., behind a captive portal).
#     portal: Behind a captive portal requiring authentication.
#     none: The host is not connected to any network.

# turn wifi on and off
nmcli radio wifi off
nmcli radio wifi on

# Tracing Network Paths with traceroute and tracepath#
# When packets fail to reach their destination, route tracing displays each intermediate hop and identifies where packet loss occurs.
# Trace route to an internet host
traceroute -n 8.8.8.8
# Alternatively, tracepath does not require superuser privileges:
tracepath 8.8.8.8


# Step-by-Step Troubleshooting Workflow#
# When troubleshooting internet access issues, follow a systematic bottom-up approach through the network layers:
# [Layer 1/2: Physical & Interface]   ip link / ip addr
#                 ↓
# [Layer 3: Local Gateway Route]     ip route show default
#                 ↓
# [Layer 3: Public IP Ping]          ping 1.1.1.1 (or nc -zv 1.1.1.1 443)
#                 ↓
# [Layer 7: DNS Name Resolution]     resolvectl query / dig google.com
#                 ↓
# [Layer 7: End-to-End Application]  curl -I https://www.google.com


# Step                      Diagnostic Command	                            What It Checks	                                What Failure Indicates
# 1.Interface               ip link show / ip addr	                        Is the interface UP with an assigned IP?	    Disconnected cable, Wi-Fi down, or DHCP failure.
# 2.Gateway	                ip route show default	                        Is there a valid default gateway route?	        Missing default route in kernel routing table.
# 3.Gateway Reachability	ping -c 2 <gateway_ip>	                        Can packets reach the local router?	            Local LAN issue, switch fault, or subnet mismatch.
# 4.Public IP Reachability	ping -c 2 1.1.1.1	                            Can packets reach the public internet?	        Upstream ISP failure, modem offline, or WAN block.
# 5.DNS Resolution	        dig google.com / resolvectl query google.com	Can the system resolve domain names?	        Misconfigured /etc/resolv.conf or unreachable DNS server.
# 6.Web / Application	    curl -Is --max-time 5 https://google.com	    Can applications establish TLS/HTTP sessions?	Proxy required, captive portal, or firewall blocking port 443.