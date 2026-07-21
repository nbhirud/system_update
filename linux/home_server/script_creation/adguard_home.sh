
# 1. Install Docker (if not already present)
# curl -fsSL https://get.docker.com | sh

# docker pull adguard/adguardhome

podman pull docker.io/adguard/adguardhome:latest

# podman run \
#     --name adguardhome\
#     --restart unless-stopped\
#     -v /opt/adguard/work:/opt/adguardhome/work \
#     -v /opt/adguard/conf:/opt/adguardhome/conf \
#     -p 53:53/tcp -p 53:53/udp \                       # plain DNS
#     -p 67:67/udp -p 68:68/udp \                       # use AdGuard Home as a DHCP server
#     -p 80:80/tcp  \                                   # HTTP UI (use AdGuard Home's admin panel)
#     -p 443:443/tcp -p 443:443/udp -p 3000:3000/tcp \  # run AdGuard Home as an HTTPS/DNS-over-HTTPS⁠ server
#     -p 853:853/tcp\                                   # run AdGuard Home as a DNS-over-TLS⁠ server.
#     #-p 784:784/udp -p 853:853/udp -p 8853:8853/udp\   # run AdGuard Home as a DNS-over-QUIC⁠ server.
#     -p 5443:5443/tcp -p 5443:5443/udp\                # run AdGuard Home as a DNSCrypt⁠ server.
#     -d adguard/adguardhome


# podman run \
#     --name adguardhome \
#     --restart unless-stopped \
#     -v /opt/adguard/work:/opt/adguardhome/work \
#     -v /opt/adguard/conf:/opt/adguardhome/conf \
#     -p 53:53/tcp -p 53:53/udp \                       
#     -p 67:67/udp -p 68:68/udp \                       
#     -p 80:80/tcp  \                                   
#     -p 443:443/tcp -p 443:443/udp -p 3000:3000/tcp \  
#     -p 853:853/tcp\                                  
#     -p 5443:5443/tcp -p 5443:5443/udp\                
#     -d adguard/adguardhome

sudo mkdir -p /opt/adguard/work 
sudo mkdir -p /opt/adguard/conf

podman run \
    --name adguardhome \
    --restart unless-stopped \
    -v /opt/adguard/work:/opt/adguardhome/work \
    -v /opt/adguard/conf:/opt/adguardhome/conf \
    -p 53:53/tcp -p 53:53/udp -p 67:67/udp -p 68:68/udp -p 80:80/tcp -p 443:443/tcp -p 443:443/udp -p 3000:3000/tcp -p 853:853/tcp -p 5443:5443/tcp -p 5443:5443/udp -d adguard/adguardhome