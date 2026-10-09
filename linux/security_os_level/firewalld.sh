#!/bin/bash

set -eux

#########################################################
# Useful links
#########################################################
# https://fedoraproject.org/wiki/Firewalld
# https://wiki.archlinux.org/title/Firewalld
# https://www.redhat.com/en/blog/how-to-configure-firewalld
# https://docs.fedoraproject.org/en-US/quick-docs/firewalld/
# https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/security_guide/sec-using_firewalls#sec-Getting_started_with_firewalld



#########################################################
# Info for basic understanding of firewalld:
#########################################################

# Check Your Current Setup: See what zone your network interfaces are currently assigned to. You will see zone names and assigned interfaces.
# firewall-cmd --get-active-zones

################### zones
# Understanding the common zones:
# https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/security_guide/sec-using_firewalls#sec-Zones

# firewalld provides multiple zones because network trust is contextual. Instead of treating every network the same, zones let you define trust boundaries based on where you are.
# For example, your laptop needs a completely different set of rules when connected to a public Wi-Fi at a coffee shop versus your secure home network. Zones package sets of rules into reusable profiles so you don't have to rewrite firewall rules every time you change networks.

# <Zone>,             <Trust Level>,          <Best Use Case>
# drop,               Zero Trust,             Drops all incoming packets silently; allows outgoing only. Good for hostile public networks.
# block,              Low Trust,"             Rejects incoming packets with an ICMP error. Similar to drop, but signals rejection."
# public,             Untrusted (Default),    Standard for public Wi-Fi. Only allows specifically selected incoming connections.
# home / internal,    Moderate Trust,"        For home or local networks. Implicitly trusts other local devices (allows mDNS, DHCP, Samba, etc.)."
# trusted,            Full Trust,"            Accepts all incoming traffic. Use sparingly (e.g., for specific VPN tunnels or loopbacks)."

# We are going to use and configure only: drop, public, home

################### basic commands

# Check the current default zone:
# firewall-cmd --get-default-zone

# Set a Secure Default: Ensure your system defaults to a locked-down posture for unassigned networks:
# sudo firewall-cmd --set-default-zone=public

# Bind Interfaces Intentionally: If you have a desktop or server that stays at home, explicitly bind your network interface to the home zone:
# sudo firewall-cmd --zone=home --add-interface=eth0 --permanent

# Audit and Trim Services: Check what services are allowed in your active zone and remove what you don't need:
# See what's allowed in public
# s
# Remove unnecessary services (e.g., dhcpv6-client if using static IPs)
# sudo firewall-cmd --zone=public --remove-service=dhcpv6-client --permanent

# Apply Changes
# sudo firewall-cmd --reload


#########################################################
# Pre-Defined services
#########################################################
# https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/security_guide/sec-controlling_traffic#sec-Controlling-Traffic-with-CLI-using-Predefined-Services

# List all predefined services: 
# firewall-cmd --get-services
# firewall-cmd --get-services | grep -i syncthing

# In case of these predefined services, we can just add or remove a service using its name without having to specify ports, etc

#########################################################
# Root check
#########################################################

# Run-as-root check
if [ ${EUID:-0} -ne 0 ] || [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (or with sudo). You are running as $(whoami)."
  exit 1
else
  echo "You are running as $(whoami)"
fi

#########################################################
# Input data processing
#########################################################

# TODO optional inputs:
# FILENAME_TIMESTAMP
# SCRIPT_BACKUPS_DIR
# SYSUPDATE_CODE_BASE_DIR
# HOME_LAN_SUBNET
# HOME_ZONE_CONNECTIONS
# PUBLIC_ZONE_CONNECTIONS

FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"

HOME_DIR=$(getent passwd $USER | cut -d: -f6)
NBDIR="$HOME_DIR/nb"
SCRIPT_DATA="$NBDIR/nb_script_data"
SCRIPT_BACKUPS_DIR="$SCRIPT_DATA/backups"

# HOME_DIR=$(getent passwd $USER | cut -d: -f6)
# NBDIR="$HOME_DIR/nb"
# CODEPROJECTS_DIR="$NBDIR/CodeProjects"
# SYSUPDATE_CODE_BASE_DIR="$CODEPROJECTS_DIR/system_update"




# HOME_LAN_SUBNET="192.168.0.0/24"   

# TODO - find out if these connections can even be assigned to zones while setting up PC for the first time when most of these connections aren't even configured/connected ever
# HOME_ZONE_CONNECTIONS = () # list of wifi connections and ethernet connectons that should be assigned to home zone like own home network
# PUBLIC_ZONE_CONNECTIONS = () # list of wifi connections and ethernet connectons that should be assigned to public zone like relatives' place or friends' place

# Prompt for Home Wi-Fi SSIDs (space-separated) another way of doing HOME_ZONE_CONNECTIONS
# read command - use the -p option to display a prompt before reading. The prompt is printed before read executes and does not include a newline
# read command - To disable backslash escaping (\t for tab, \n for newline, etc), invoke the command with the -r option. 
# read -r -p "[?] Enter your trusted Home Wi-Fi SSID(s) [e.g., MyHomeWiFi HotspotName]: " -a HOME_ZONE_CONNECTIONS
# read -r -p "[?] Enter your Semi Trusted known Public Wi-Fi SSID(s) [e.g., YourFriendsWiFi YourRelativesWiFi HotspotName]: " -a PUBLIC_ZONE_CONNECTIONS

#########################################################
# Set user-defined constants/variables
#########################################################

# 4. Real caveat, stated plainly: rich rules scoped to 192.168.0.0/24 restrict
#    access to devices ON that subnet - they do NOT distinguish your phone
#    from a compromised IoT device on the same subnet. If you want real
#    isolation, that's a router-level VLAN problem, not a host-firewall
#    problem. This script gets you 90% of the way; the last 10% is your
#    router.

DROP_ZONE="drop"
PUBLIC_ZONE="public"
HOME_ZONE="home"

DEFAULT_ZONE="$DROP_ZONE"

# Rate limit for SSH (connections per minute)
# SSH_LIMIT_PUBLIC="1/m"
# SSH_LIMIT_HOME="5/m"

FIREWALLD_BACKUP_DIR="$SCRIPT_BACKUPS_DIR/firewalld/firewalld_$FILENAME_TIMESTAMP"


#########################################################
# Set inferred constants/variables
#########################################################

# Get active default zone
# CURRENT_ACTIVE_ZONE=$(sudo firewall-cmd --get-default-zone)

# CURRENT_INTERFACE="$(nmcli -t -f DEVICE,STATE d | grep ':connected' | cut -d: -f1 | head -n1)"

# HOSTNAME="$(hostnamectl --static 2>/dev/null || hostname)"
# echo "Host: $HOSTNAME"

#########################################################
# Identify installed packages for firrewall rules
#########################################################

# Ignored if the service is not found installed on the system

SSH_AVAILABLE=false
KDECONNECT_AVAILABLE=false       # on kde
GSCONNECT_AVAILABLE=false        # on gnome 
SYNCTHING_AVAILABLE=false
IMMICH_AVAILABLE=false
GRAYJAY_AVAILABLE=false          # Grayjay sync + mDNS (only on home)
AVAHI_MDNS_AVAILABLE=false
RADICALE_AVAILABLE=false
NEXTCLOUD_AVAILABLE=false
JELLYFIN_AVAILABLE=false
HOME_ASSISTANT_AVAILABLE=false
OPENHAB_AVAILABLE=false          # ports 8080, 8443, 5007
SAMBA_CLIENT_AVAILABLE=false
HTTP_SERVER_AVAILABLE=false
HTTPS_SERVER_AVAILABLE=false
CUPS_AVAILABLE=false

# DHCP_AVAILABLE=false
# DHCPV6_AVAILABLE=false
# COCKPIT_AVAILABLE=false
# QBITTORRENT_AVAILABLE=false
# DNS_AVAILABLE=false
# IPV6_AVAILABLE=false           # keep IPv6; set false to drop all IPv6
# TAILSCALE_AVAILABLE=false
# DOCKER_AVAILABLE=false
# KUBERNETES_AVAILABLE=false
# ICMP_AVAILABLE=false


#########################
# Following code block can be used to pre-configure (hardcode) which machine gets what added

# # Per-machine service toggles. All 4 machines run this same script, but you
# # likely don't run Radicale/OpenHAB on all 4 boxes. Default: all enabled.
# # Edit per-host below if e.g. only nbMain actually hosts Radicale/OpenHAB.

# case "$HOSTNAME" in
#   nbMain)
#     ;; # primary desktop - leave all enabled
#   nbXPS|nbAcer|nbLenovo)
#     # Uncomment to disable services this machine doesn't actually host,
#     # e.g. if Radicale/OpenHAB only ever run on nbMain:
#     # RADICALE_AVAILABLE=false
#     # OPENHAB_AVAILABLE=false
#     ;;
# esac
#########################


# Check whether either of dnf (if officially available) or flatpak (if officially available) packages or installed rpms or installed tarballs of the following are installed.

# SSH
if dnf list --installed openssh-server &>/dev/null || rpm -q openssh-server &>/dev/null; then
    echo "SSH Server is installed."
    # add_firewall_service "ssh"
    SSH_AVAILABLE=true
else
    echo "SSH Server is NOT installed."
fi


# KDECONNECT (on KDE)
if dnf list --installed kde-connect &>/dev/null || flatpak info org.kde.kdeconnect &>/dev/null || rpm -q kde-connect &>/dev/null; then
    echo "KDECONNECT is installed."
    # add_firewall_service "kdeconnect"
    KDECONNECT_AVAILABLE=true
else
    echo "KDECONNECT is NOT installed."
fi


# GSCONNECT (on GNOME)
if dnf list --installed gnome-shell-extension-gsconnect &>/dev/null || rpm -q gnome-shell-extension-gsconnect &>/dev/null; then
    echo "GSCONNECT is installed."
    # GSConnect uses similar ports to KDEConnect (often handled via custom rules or kdeconnect service profile)
    # add_firewall_service "kdeconnect"
    GSCONNECT_AVAILABLE=true
else
    echo "GSCONNECT is NOT installed."
fi


# SYNCTHING
# if dnf list --installed syncthing &>/dev/null || flatpak info me.syncthing.Syncthing &>/dev/null || rpm -q syncthing &>/dev/null; then
if dnf list --installed syncthing &>/dev/null || systemctl list-unit-files | grep -q "syncthing" || [ -e "/usr/bin/syncthing" ]; then
    echo "SYNCTHING is installed/configured."
    # Syncthing default ports: 22000/tcp (sync), 21027/udp (discovery)
    # add_firewall_port "Syncthing Sync" "22000/tcp"
    # add_firewall_port "Syncthing Discovery" "21027/udp"
    SYNCTHING_AVAILABLE=true
else
    echo "SYNCTHING is NOT installed."
fi


# IMMICH (Self-Hosted Photo Management Server)
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "immich" || [ -d "/opt/immich" ]; then
    echo "Immich is detected."
    # add_firewall_port "Immich UI" "2283/tcp"
    IMMICH_AVAILABLE=true
else
    echo "Immich is NOT detected."
fi


# GRAYJAY
# if flatpak info app.grayjay.Grayjay &>/dev/null || [ -e "/opt/grayjay" ] || rpm -q grayjay &>/dev/null; then
if flatpak info app.grayjay.Grayjay &>/dev/null; then
    echo "GRAYJAY (Flatpak) is installed."
    # Grayjay is a client media app; no inbound host firewall ports required.
    GRAYJAY_AVAILABLE=true
else
    echo "GRAYJAY is NOT installed."
fi


# MDNS (Avahi / systemd-resolved)
if dnf list --installed avahi &>/dev/null || rpm -q avahi &>/dev/null; then
    echo "MDNS / Avahi is installed."
    # add_firewall_service "mdns"
    AVAHI_MDNS_AVAILABLE=true
else
    echo "MDNS / Avahi is NOT installed."
fi


# RADICALE
# if dnf list --installed radicale &>/dev/null || rpm -q radicale &>/dev/null || [ -e "/usr/local/bin/radicale" ]; then
if dnf list --installed radicale &>/dev/null || systemctl list-unit-files | grep -q "radicale"; then
    echo "[+] RADICALE is installed."
    # add_firewall_port "Radicale Web/CalDAV" "5232/tcp"
    RADICALE_AVAILABLE=true
else
    echo "[-] RADICALE is NOT installed."
fi


# NextCloud
# if dnf list --installed nextcloud-client &>/dev/null || flatpak info com.nextcloud.desktopclient.nextcloud &>/dev/null || rpm -q nextcloud-client &>/dev/null; then
if dnf list --installed nextcloud-client &>/dev/null || flatpak info com.nextcloud.desktopclient.nextcloud &>/dev/null || [ -d "/var/www/nextcloud" ] || docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "nextcloud"; then
    echo "Nextcloud (Client or Server component) detected."
    # If self-hosting server instance, standard HTTP/HTTPS ports apply (handled below if web server active)
    NEXTCLOUD_AVAILABLE=true
else
    echo "Nextcloud is NOT detected."
fi

if $NEXTCLOUD_AVAILABLE; then
  HTTP_SERVER_AVAILABLE=true
  HTTPS_SERVER_AVAILABLE=true
fi


# jellyfin
# if dnf list --installed jellyfin &>/dev/null || rpm -q jellyfin &>/dev/null || [ -e "/opt/jellyfin" ]; then
if dnf list --installed jellyfin &>/dev/null || docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "jellyfin" || [ -e "/opt/jellyfin" ]; then
    echo "Jellyfin is installed/detected."
    # add_firewall_port "Jellyfin HTTP" "8096/tcp"
    # add_firewall_port "Jellyfin HTTPS" "8920/tcp"
    JELLYFIN_AVAILABLE=true
else
    echo "Jellyfin is NOT installed."
fi


# home assistant
# if command -v hass &>/dev/null || [ -e "/opt/homeassistant" ] || docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "homeassistant"; then
if command -v hass &>/dev/null || docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "homeassistant" || [ -d "/opt/homeassistant" ]; then
    echo "Home Assistant is detected."
    # add_firewall_port "Home Assistant UI" "8123/tcp"
    HOME_ASSISTANT_AVAILABLE=true
else
    echo "Home Assistant is NOT detected."
fi





# OpenHAB
# if dnf list --installed openhab &>/dev/null || rpm -q openhab &>/dev/null || [ -e "/opt/openhab" ]; then
if dnf list --installed openhab &>/dev/null || [ -d "/usr/share/openhab" ] || [ -e "/opt/openhab" ]; then
    echo "OpenHAB is installed."
    # add_firewall_port "OpenHAB HTTP" "8080/tcp"
    # add_firewall_port "OpenHAB HTTPS" "8443/tcp"
    OPENHAB_AVAILABLE=true
else
    echo "OpenHAB is NOT installed."
fi





# SAMBA-CLIENT
# if dnf list --installed samba-client &>/dev/null || rpm -q samba-client &>/dev/null; then
if dnf list --installed samba &>/dev/null || rpm -q samba &>/dev/null; then
    echo "Samba Server is installed."
    # add_firewall_service "samba"
    SAMBA_CLIENT_AVAILABLE=true
else
    echo "Samba Server (samba-client is separate and needs no inbound ports) is NOT installed."
fi


# HTTPS (Secure Web Service / Port 443 / Common Daemons)
# if dnf list --installed httpd &>/dev/null || dnf list --installed nginx &>/dev/null || ss -tulpn 2>/dev/null | grep -q ":80 "; then
# if dnf list --installed httpd &>/dev/null || dnf list --installed nginx &>/dev/null || ss -tulpn 2>/dev/null | grep -q ":443 "; then
if dnf list --installed httpd &>/dev/null || dnf list --installed nginx &>/dev/null; then
    echo "Web server (Apache/Nginx) is installed."
    # add_firewall_service "http"
    # add_firewall_service "https"
    HTTP_SERVER_AVAILABLE=true
    HTTPS_SERVER_AVAILABLE=true
else
    echo "Standard web servers (Apache/Nginx) are NOT installed."
fi


# CUPS (Printer Sharing / IPP - Port 631)
if dnf list --installed cups &>/dev/null || systemctl list-unit-files | grep -q "cups.service"; then
    echo "CUPS (Printing service) is installed."
    # add_firewall_service "ipp"
    CUPS_AVAILABLE=true
else
    echo "CUPS is NOT installed."
fi

# # DHCP (Kea, dnsmasq, or dhcp-server)
# # if dnf list --installed kea &>/dev/null || dnf list --installed dnsmasq &>/dev/null || dnf list --installed dhcp-server &>/dev/null || rpm -q kea &>/dev/null; then
# if dnf list --installed kea &>/dev/null || dnf list --installed dhcp-server &>/dev/null; then
#     echo "DHCP Server package is installed."
#     # add_firewall_service "dhcp"
#     DHCP_AVAILABLE=true
# else
#     echo "DHCP Server package is NOT installed."
# fi

# # DHCPV6
# # if dnf list --installed dhcpv6 &>/dev/null || rpm -q dhcpv6 &>/dev/null || rpm -q NetworkManager &>/dev/null; then
# if dnf list --installed dhcpv6 &>/dev/null || systemctl list-unit-files | grep -q "dhcpd6"; then
#     echo "DHCPv6 support is present."
#     # add_firewall_service "dhcpv6"
#     DHCPV6_AVAILABLE=true
# else
#     echo "DHCPv6 packages are NOT installed."
# fi

# # Cockpit
# # if dnf list --installed cockpit &>/dev/null || rpm -q cockpit &>/dev/null; then
# if dnf list --installed cockpit &>/dev/null || systemctl list-unit-files | grep -q "cockpit"; then
#     echo "Cockpit is installed."
#     # add_firewall_service "cockpit"
#     COCKPIT_AVAILABLE=true
# else
#     echo "Cockpit is NOT installed."
# fi

# # QBITTORRENT (BitTorrent Client / Web UI)
# if dnf list --installed qbittorrent &>/dev/null || dnf list --installed qbittorrent-nox &>/dev/null || flatpak info org.qbittorrent.qBittorrent &>/dev/null || command -v qbittorrent &>/dev/null || pgrep -x "qbittorrent" &>/dev/null; then
#     echo "qBittorrent is installed/detected."
#     # add_firewall_port "qBittorrent Peer Port (TCP)" "6881/tcp"
#     # add_firewall_port "qBittorrent Peer Port (UDP)" "6881/udp"
#     # Uncomment the line below if you have the Web UI enabled and need inbound access:
#     # add_firewall_port "qBittorrent Web UI" "8080/tcp"
#     QBITTORRENT_AVAILABLE=true
# else
#     echo "qBittorrent is NOT installed."
# fi

# DNS visibility is already completely blocked by default when using systemd-resolved
# You don't need any extra configuration because of two built-in security layers:
# Loopback Binding: systemd-resolved binds its DNS stub resolver exclusively to the internal loopback address (127.0.0.53), meaning it never opens ports or listens on your external Wi-Fi or Ethernet IP addresses. Other devices on the network cannot talk to it even if they tried.
# The Drop Zone: The drop zone policy in firewalld silently discards all incoming packets on your network interface.
# Run the following command to check where port 53 is listening:
# sudo ss -tulpn | grep "53"
# Verification: Confirm that the local address for port 53 only shows 127.0.0.53:53 or 127.0.0.54:53. If you see 0.0.0.0:53 or your local Wi-Fi IP address, it would mean it's exposed (which it isn't with systemd-resolved).

# # DNS (BIND, dnsmasq, or systemd-resolved)
# if dnf list --installed bind &>/dev/null || dnf list --installed dnsmasq &>/dev/null || systemctl is-active --quiet systemd-resolved; then
#     echo "Local DNS service/resolver is active."
#     # add_firewall_service "dns"
#     DNS_AVAILABLE=true
# else
#     echo "Local DNS service/resolver package not found as active server."
# fi


# # IPV6 (Network Stack Check)
# if sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | grep -q "0"; then
#     echo "IPV6 is active on the system."
#     # IPv6 is handled at kernel/firewalld level automatically; no extra open port needed unless specified.
#     IPV6_AVAILABLE=true
# else
#     echo "IPV6 is disabled."
# fi

# # TAILSCALE
# # if dnf list --installed tailscale &>/dev/null || rpm -q tailscale &>/dev/null; then
# if dnf list --installed tailscale &>/dev/null || systemctl list-unit-files | grep -q "tailscaled"; then
#     echo "TAILSCALE is installed."
#     # Note: Tailscale manages its own secure mesh routing via its interface (tailscale0). 
#     # Standard firewalld rules are typically bypassed or handled by tailscale daemon, 
#     # but we ensure the service state is recognized.
#     TAILSCALE_AVAILABLE=true
# else
#     echo "TAILSCALE is NOT installed."
# fi

# # docker
# # if dnf list --installed docker-ce &>/dev/null || dnf list --installed moby-engine &>/dev/null || rpm -q docker-ce &>/dev/null || rpm -q moby-engine &>/dev/null || command -v docker &>/dev/null; then
# if dnf list --installed docker-ce &>/dev/null || dnf list --installed moby-engine &>/dev/null || command -v docker &>/dev/null; then
#     echo "Docker is installed."
#     # Docker manages its own iptables/nftables rules for container bridging.
#     DOCKER_AVAILABLE=true
# else
#     echo "Docker is NOT installed."
# fi

# # kubernetes
# # if dnf list --installed kubectl &>/dev/null || rpm -q kubectl &>/dev/null || command -v kubectl &>/dev/null; then
# if dnf list --installed kubectl &>/dev/null || command -v kubectl &>/dev/null || rpm -q kubelet &>/dev/null; then
#     echo "Kubernetes tools are installed."
#     # If control plane, Kubernetes components manage their own ports.
#     KUBERNETES_AVAILABLE=true
# else
#     echo "Kubernetes tools are NOT installed."
# fi

# # ICMP (Network Protocol / Firewall / Kernel Check)
# # if { systemctl is-active --quiet firewalld && firewall-cmd --query-service=icmp --quiet 2>/dev/null; } || [ "$(sysctl -n net.ipv4.icmp_echo_ignore_all 2>/dev/null)" = "0" ]; then
# if systemctl is-active --quiet firewalld; then
#     # Keep ICMP enabled/disabled based on hardening preference (default allows echo-request)
#     echo "Checking ICMP rule status."
#     add_firewall_service "icmp"
# fi

# # ANDROID DEBUG BRIDGE (ADB - Local/Network Development)
# if dnf list --installed android-tools &>/dev/null || command -v adb &>/dev/null; then
#     echo "ADB tools are installed (typically local interface unless wireless debugging is active)."
#     # ADB daemon typically runs on port 5037 locally. No external firewalld rule needed unless using wireless ADB.
# else
#     echo "ADB tools are NOT installed."
# fi


#########################################################
# Helpers
#########################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*" >&2; }

need_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Run as root (sudo)."
    exit 1
  fi
}


#########################################################
# Install and setup firewalld:
#########################################################

# firewalld should be already installed, but just in case
sudo dnf install -y firewalld firewall-config

sudo systemctl enable --now firewalld


#########################################################
# functions:
#########################################################

# Not in use
add_service() {
  local zone="$1" svc="$2"
  sudo firewall-cmd --permanent --zone="$zone" --add-service="$svc" || true
}

# Not in use
remove_service() {
  local zone="$1" svc="$2"
  sudo firewall-cmd --permanent --zone="$zone" --remove-service="$svc" &>/dev/null || true
}

# Not in use
add_port() {
  local zone="$1" port="$2"
  sudo firewall-cmd --permanent --zone="$zone" --add-port="$port" || true
}

# Not in use
add_rich() {
  local zone="$1" rule="$2"
  sudo firewall-cmd --permanent --zone="$zone" --add-rich-rule="$rule" || true
}


# Helper function to add firewalld service safely
# Not in use
add_firewall_service() {
    local svc="$1"
    if firewall-cmd --get-services | grep -qw "$svc"; then
        if ! firewall-cmd --query-service="$svc" --permanent &>/dev/null; then
            firewall-cmd --permanent --add-service="$svc"
            echo "Firewalld: Added service '$svc'."
        else
            echo "Firewalld: Service '$svc' already enabled."
        fi
    else
        echo "Firewalld warning: Service '$svc' is not recognized by firewalld."
    fi
}

# Helper function to add firewalld port safely
# Not in use
add_firewall_port() {
    local port_proto="$2"
    local desc="$1"
    if ! firewall-cmd --query-port="$port_proto" --permanent &>/dev/null; then
        firewall-cmd --permanent --add-port="$port_proto"
        echo "Firewalld: Added port/proto '$port_proto' for $desc."
    else
        echo "Firewalld: Port '$port_proto' for $desc already enabled."
    fi
}


#########################################################
# Backup existing config
#########################################################

mkdir -p "$FIREWALLD_BACKUP_DIR"
cp -a /etc/firewalld "$FIREWALLD_BACKUP_DIR"
echo "Backup: $FIREWALLD_BACKUP_DIR"



#########################################################
# Clean the slate:
#########################################################

# Print current state before we reset everythinf
for z in "$PUBLIC_ZONE" "$HOME_ZONE" "$DROP_ZONE"; do
    echo "zone = $z ##############"
    
    # Loop through and remove each rich rule safely
    while read -r rule; do
        [ -n "$rule" ] && echo "zone = $z and rule = $rule"
    done < <(firewall-cmd --permanent --zone="$z" --list-rich-rules)

    for s in $(firewall-cmd --permanent --zone="$z" --list-services); do
    echo "zone = $z and service = $s"
    done
    for p in $(firewall-cmd --permanent --zone="$z" --list-ports); do
    echo "zone = $z and port = $p"
    done
done


# # Remove everything else from Public that might have been there by default
# # Reset public zone to clean state (optional, comment out if you want to keep existing rules)

# reset_zone() {
#   local zone="$1"
#   sudo firewall-cmd --permanent --zone="$zone" --remove-service=ssh || true
#   sudo firewall-cmd --permanent --zone="$zone" --remove-service=http || true
#   sudo firewall-cmd --permanent --zone="$zone" --remove-service=https || true
#   sudo firewall-cmd --permanent --zone="$zone" --remove-service=kdeconnect || true
#   sudo firewall-cmd --permanent --zone="$zone" --remove-port=5232/tcp || true
#   sudo firewall-cmd --permanent --zone="$zone" --remove-port=8080/tcp || true
#   sudo firewall-cmd --permanent --zone="$zone" --remove-port=8443/tcp || true
#   sudo firewall-cmd --permanent --zone="$zone" --remove-port=5007/tcp || true
# }

# Similar to above reset_zone() but more compact and intuitive
# # Not in use. We wrote a better version below
clean_zone() {
  local zone="$1"
  info "Cleaning zone: $zone"

  for svc in ssh http https kdeconnect syncthing mdns samba-client dhcpv6-client cockpit; do
    firewall-cmd --permanent --zone="$zone" --remove-service="$svc" 2>/dev/null || true
  done

  for port in 22/tcp 80/tcp 443/tcp 5232/tcp 8080/tcp 8443/tcp 5007/tcp \
              22000/tcp 22000/udp 21027/udp 8384/tcp 12315/tcp; do
    firewall-cmd --permanent --zone="$zone" --remove-port="$port" 2>/dev/null || true
  done

  # Best-effort removal of previous rich rules
  firewall-cmd --permanent --zone="$zone" --remove-rich-rule='rule family="ipv4" service name="ssh" limit value="5/m" accept' 2>/dev/null || true
  firewall-cmd --permanent --zone="$zone" --remove-rich-rule='rule family="ipv4" service name="ssh" limit value="10/m" accept' 2>/dev/null || true
}

###################
# "$PUBLIC_ZONE"
# Strip anything Fedora may have pre-populated (mdns, samba-client, ssh, etc.)
# for svc in mdns samba-client ssh dhcpv6-client cockpit; do
#   remove_service "$PUBLIC_ZONE" "$svc"
# done
# clean_zone "$PUBLIC_ZONE"

###################
# "$HOME_ZONE"
# Clean slate: strip any bare (non-scoped) service grants that might exist
# for svc in kdeconnect http https ssh syncthing mdns; do
#   remove_service "$HOME_ZONE" "$svc"
# done
# for port in 5232/tcp 8080/tcp 8443/tcp 5007/tcp 12315/tcp 22000/tcp 22000/udp 21027/udp 8384/tcp; do
#   sudo firewall-cmd --permanent --zone="$HOME_ZONE" --remove-port="$port" &>/dev/null || true
# done
# clean_zone "$HOME_ZONE"

# for z in "$HOME_ZONE" "$PUBLIC_ZONE" "$DROP_ZONE"; do
#   clean_zone "$z"
# done

# Better than clean_zone() - here we go through the list of all currently added ports, services as well as rich rules one by one and remove them in looks
# for z in "$HOME_ZONE" "$PUBLIC_ZONE" "$DROP_ZONE"; do
# #   firewall-cmd --permanent --delete-all-rich-rules --zone="$z" || true
#   firewall-cmd --permanent --remove-rich-rule --zone="$z" || true
#   for s in $(firewall-cmd --permanent --zone="$z" --list-services); do
#     firewall-cmd --permanent --zone="$z" --remove-service="$s" || true
#   done
#   for p in $(firewall-cmd --permanent --zone="$z" --list-ports); do
#     firewall-cmd --permanent --zone="$z" --remove-port="$p" || true
#   done
# done

# Corrected version of above:
for z in "$HOME_ZONE" "$PUBLIC_ZONE" "$DROP_ZONE"; do
  # Loop through and remove each rich rule safely
  while read -r rule; do
    [ -n "$rule" ] && firewall-cmd --permanent --zone="$z" --remove-rich-rule="$rule" || true
  done < <(firewall-cmd --permanent --zone="$z" --list-rich-rules)

  for s in $(firewall-cmd --permanent --zone="$z" --list-services); do
    firewall-cmd --permanent --zone="$z" --remove-service="$s" || true
  done
  for p in $(firewall-cmd --permanent --zone="$z" --list-ports); do
    firewall-cmd --permanent --zone="$z" --remove-port="$p" || true
  done
done



# Create zones if missing
# No custom zones are created. Firewalld ships with "home", "public" and "drop"
for z in "$HOME_ZONE" "$PUBLIC_ZONE" "$DROP_ZONE"; do
  if ! firewall-cmd --get-zones | grep -qw "$z"; then
    echo "Creating zone: $z"
    sudo firewall-cmd --permanent --new-zone="$z"
  fi
done


#########################################################
# Set default zone for new connections:
#########################################################

# Every new connection (new hotel/cafe Wi-Fi, etc.) falls back to the default zone (drop) automatically - no per-network action needed.
# Set the default zone to 'drop' (Fedora default is public zone)
# The --set-default-zone option cannot be combined with --permanent because changing the default zone is already permanent by default.
# sudo firewall-cmd --permanent --set-default-zone="$PUBLIC_ZONE"
# sudo firewall-cmd --permanent --set-default-zone="$DEFAULT_ZONE"
sudo firewall-cmd --set-default-zone="$DEFAULT_ZONE"

#########################################################
# home zone config:
#########################################################

# trusted Wi-Fi/Ethernet, still deny-by-default, LAN-scoped. explicit allows only.

# Explicitly sets (or resets) the fallback target of the zone back to its standard baseline behavior (default).
# firewall-cmd --permanent --zone="$HOME_ZONE" --set-target=default


# home zone (trusted LAN) - ACCEPT is convenient on a trusted network.
# Change to DROP + explicit allows if you want tighter control even at home.

# For zones target is one of: default, ACCEPT, DROP, REJECT
# --set-target=ACCEPT: This strips away your security posture by allowing all incoming traffic from the network, bypassing your explicit allowlists.
# --set-target=default is similar to REJECT, but it implicitly allows ICMP packets. 
# --set-target=REJECT: Generally similar to drop, but signals rejection. - confirm this
# --set-target=DROP: This enforces a strict default-deny stance, ensuring any incoming traffic that does not match an explicitly allowed service (like Syncthing or Cockpit) is silently dropped.

# sudo firewall-cmd --permanent --zone="$HOME_ZONE" --set-target=ACCEPT
# sudo firewall-cmd --permanent --zone="$HOME_ZONE" --set-target=DROP
sudo firewall-cmd --permanent --zone="$HOME_ZONE" --set-target=default


#   # # Home
#   # for svc in ssh http https; do firewall-cmd --permanent --zone="$HOME_ZONE" --add-service=$svc; done

#   # # Optional ports in home
#   # for p in 5232/tcp 8080/tcp 8443/tcp 5007/tcp 22000/tcp 22000/udp 21027/udp; do
#   #  firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=$p
#   # done


#########################################################
# public (default) zone config:
#########################################################

# Public Wi-Fi: Your Fedora machine will use the public zone. Because our script sets the target to DROP, your laptop becomes a "black hole." Scanners won't even see that a device is there.

# Change the zone target to DROP
# This makes the firewall drop packets silently instead of rejecting them, which is better for privacy/stealth.
sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --set-target=DROP
# sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --set-target=REJECT

#########################################################
# "$DROP_ZONE" zone config:
#########################################################

# Explained above
sudo firewall-cmd --permanent --zone="$DROP_ZONE" --set-target=DROP

# Use "$DROP_ZONE" profile with VPN

# Intentionally NOTHING else open here. No SSH, no services. Outbound is
# always allowed by firewalld regardless of zone - you lose nothing.



#########################################################
# List of firewall rules per services:
#########################################################

# http: Allows inbound World Wide Web traffic over unencrypted TCP port 80.

# https: Allows inbound secure web traffic over TCP port 443 (TLS/SSL).

# kdeconnect: Allows your desktop to communicate with your mobile devices (e.g., sharing notifications, clipboard, media control) using local network discovery ports (UDP/TCP 1714-1764).

# mdns: Multicast DNS (Bonjour/Avahi), which allows your machine to discover devices and printers automatically on your local network (UDP port 5353).

# syncthing: Allows file synchronization across your devices using Syncthing's sync protocol (TCP port 22000 and UDP discovery).

# dhcpv6-client: Allows your machine to request and receive an IPv6 address and network configuration from your local router/DHCPv6 server.

# mdns: Multicast DNS for local device and hostname discovery (same as above).

# samba-client: Allows your computer to connect to and browse shared folders on other network computers (SMB/CIFS shares).

# ssh: Secure Shell, which allows remote command-line administration and secure tunneling over TCP port 22.




############################
# SSH 
############################

# SSH_AVAILABLE
# add_firewall_service "ssh"


#    SSH: rate-limited and scoped to the home LAN in the home zone only.
#    Public zone does NOT open SSH - see the Tailscale note near the bottom.
#    Once you set up Tailscale (per your own roadmap), route SSH through the
#    tailscale0 interface instead of exposing it to the public internet at
#    all. That is a strictly better answer than opening SSH on the public
#    zone with a rate limit, so this script doesn't even offer that as an
#    option.

if $SSH_AVAILABLE; then

    ##### home
    # sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-service=ssh
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-rich-rule='rule family="ipv4" service name="ssh" limit value="5/m" accept'
    # add_rich "$HOME_ZONE" "rule family=\"ipv4\" source address=\"$HOME_LAN_SUBNET\" service name=\"ssh\" limit value=\"5/m\" accept"


    ##### public
    # sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-service=ssh
    # Rate-limited SSH in public zone (1 connection attempts / min limit) - protecting against brute force.
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --add-rich-rule='rule family="ipv4" service name="ssh" limit value="1/m" accept'
    # The following achieves the same exact goal as above command
    # sudo firewall-cmd --zone="$PUBLIC_ZONE" --add-rich-rule='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="22" limit value="1/min" accept' --permanent

    # firewall-cmd --permanent --zone="$PUBLIC_ZONE" --add-rich-rule="rule family=\"ipv4\" service name=\"ssh\" limit value=\"${SSH_LIMIT}\" accept"


    ##### drop
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-service=ssh

fi


############################
# HTTP - Web Traffic (NextCloud / Standard Web)
############################
# HTTP_SERVER_AVAILABLE
# add_firewall_service "http"


# # Explaining: --remove-service=http and --remove-service=https
# firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-service=http
# firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-service=https
# # Don't expose my machine's web-server ports to incoming connections through the public zone.
# # In home zone, don't remove these services, otherwise accessing Nextcloud, Jellyfin, a FastAPI app, a local web UI, etc from other home-network PCs will stop working

# <Situation>	                            <Effect>
# Your browser → Internet HTTPS           Works
# Your browser → Internet HTTP            Works
# dnf → Internet	                        Works
# curl https://...	                      Works
# Another PC → your PC:80                 Blocked
# Another PC → your PC:443	              Blocked
# Web server running on your PC	          No longer publicly reachable through that zone
# Existing HTTP/HTTPS connections	        Generally continue until closed

if $HTTP_SERVER_AVAILABLE; then

    ##### home
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-service=http

    ##### public
    # Explained in http section
    # HTTP/HTTPS intentionally NOT added to public by default.
#   # Add only if you truly need to expose a web service on untrusted networks.
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-service=http

    ##### drop
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-service=http

fi


############################
# HTTPS - Web Traffic (NextCloud / Standard Web)
############################
# HTTPS_SERVER_AVAILABLE
# add_firewall_service "https"

if $HTTPS_SERVER_AVAILABLE; then

    ##### home
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-service=https

    ##### public
    # Explained in http section
    # HTTP/HTTPS intentionally NOT added to public by default.
#   # Add only if you truly need to expose a web service on untrusted networks.
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-service=https

    ##### drop
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-service=https

fi


############################
# ICMP (Ping)
############################
# Assume it is always available by default
# add_firewall_service "icmp"

# Block ping. This prevents your machine from responding to ping requests on public networks. reduces trivial host-discovery.
sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --add-icmp-block=echo-request

sudo firewall-cmd --permanent --zone="$DROP_ZONE" --add-icmp-block=echo-request

############################
# Syncthing
############################
# SYNCTHING_AVAILABLE

# https://docs.syncthing.net/users/firewall.html
# Port 22000/TCP: TCP based sync protocol traffic
# Port 22000/UDP: QUIC based sync protocol traffic
# Port 21027/UDP: for discovery broadcasts on IPv4 and multicasts on IPv6
# Port 8384/tcp: Web GUI
# Firewalld has included support for syncthing (since version 0.5.0, January 2018), and you can enable it with:
# sudo firewall-cmd --zone=<zone> --add-service=syncthing --permanent
# sudo firewall-cmd --zone=<zone> --add-service=syncthing-gui --permanent


if $SYNCTHING_AVAILABLE; then

    ##### home
    # firewall-cmd --get-services | grep -i syncthing
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-service=syncthing
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-service=syncthing-gui
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-service=syncthing-relay

    # # Above is same as doing:
    # firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=22000/tcp
    # firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=22000/udp
    # firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=21027/udp   # local discovery
    # To be able to access the web GUI from other computers, you need to change the GUI Listen Address setting from the default 127.0.0.1:8384 to 0.0.0.0:8384. 
    # firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=8384/tcp   # web UI (LAN only)


    # # NOTE: Syncthing peers can also connect via global discovery/relay servers
    # # when you're off the home LAN. Scoping this to home-only means sync will
    # # only happen automatically while you're on your home network; while
    # # traveling it will rely on relays for outbound-initiated connections only
    # # (which still works - this just blocks unsolicited inbound from the internet).
    # if $SYNCTHING_AVAILABLE; then
    # echo "    - Syncthing (LAN only): sync port + local discovery"
    # add_rich "$HOME_ZONE" "rule family=\"ipv4\" source address=\"$HOME_LAN_SUBNET\" port protocol=\"tcp\" port=\"22000\" accept"
    # add_rich "$HOME_ZONE" "rule family=\"ipv4\" source address=\"$HOME_LAN_SUBNET\" port protocol=\"udp\" port=\"22000\" accept"
    # add_rich "$HOME_ZONE" "rule family=\"ipv4\" source address=\"$HOME_LAN_SUBNET\" port protocol=\"udp\" port=\"21027\" accept"
    # # Web UI - only if you actually manage Syncthing from another LAN device.
    # # add_rich "$HOME_ZONE" "rule family=\"ipv4\" source address=\"$HOME_LAN_SUBNET\" port protocol=\"tcp\" port=\"8384\" accept"
    # fi



    ##### public
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-service=syncthing
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-service=syncthing-gui
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-service=syncthing-relay

    ##### drop
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-service=syncthing
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-service=syncthing-gui
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-service=syncthing-relay


fi



############################
# Immich
############################
# IMMICH_AVAILABLE
# add_firewall_port "Immich UI" "2283/tcp"
# https://docs.immich.app/install/environment-variables/#ports

if $IMMICH_AVAILABLE; then

    ##### home
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --add-port=2283/tcp

    ##### public
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-port=2283/tcp

    ##### drop
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-port=2283/tcp

fi


############################
# Jellyfin
############################
# JELLYFIN_AVAILABLE
# add_firewall_port "Jellyfin HTTP" "8096/tcp"
# add_firewall_port "Jellyfin HTTPS" "8920/tcp"

# If installing the dnf/rpm jellyfin package, which will automatically install jellyfin-server, jellyfin-web and jellyfin-firewalld 
# jellyfin-firewalld makes service jellyfin available in the predefined list
# https://jellyfin.org/docs/general/installation/advanced/community/

# sudo firewall-cmd --permanent --add-service=jellyfin
# This will open the following ports:
#     8096 TCP, used by default for HTTP traffic; you can change this in the dashboard
#     8920 TCP, used by default for HTTPS traffic; you can change this in the dashboard
#     1900 UDP, used for service auto-discovery; this is not configurable
#     7359 UDP, used for auto-discovery; this is not configurable

# If installed as a container, the ports stay the same but not sure if the predefined service is created
# https://jellyfin.org/docs/general/installation/container/

if $JELLYFIN_AVAILABLE; then

    ##### home
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-service=jellyfin

    ##### public
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-service=jellyfin

    ##### drop
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-service=jellyfin

fi

############################
# KDE Connect
############################
# KDECONNECT_AVAILABLE       # on kde
# GSCONNECT_AVAILABLE        # on gnome 
# add_firewall_service "kdeconnect" # KDECONNECT and GSCONNECT
# https://userbase.kde.org/KDEConnect

if $KDECONNECT_AVAILABLE; then
  
    ##### home
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-service=kdeconnect

    # Optional: Restrict KDE Connect to local subnet (better privacy)
    # Home mode improvement (recommended)
    # Behavior: Restricts access to the KDE Connect service only to incoming traffic originating from the 192.168.0.0/16 subnet (which encompasses all 192.168.0.0 through 192.168.255.255 addresses).
    # Limitation with Roaming: If you connect your laptop to a network using a different private range (such as 10.x.x.x on some routers or corporate setups) or a public/hotel Wi-Fi, KDE Connect will completely fail to connect, because the source IP address will not match your hardcoded /16 rule.
    # sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-rich-rule='rule family="ipv4" source address="192.168.0.0/16" service name="kdeconnect" accept'
    # sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-rich-rule='rule family="ipv4" source address="$HOME_LAN_SUBNET" service name="kdeconnect" accept'

    # # LAN-only KDE Connect - most subnets
    # for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
    #     firewall-cmd --permanent --zone="$HOME_ZONE" --add-rich-rule="rule family=\"ipv4\" source address=\"$net\" service name=\"kdeconnect\" accept"
    # done


    ##### public
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-service=kdeconnect

    ##### drop
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-service=kdeconnect


fi



############################
# OpenHAB
############################
# OPENHAB_AVAILABLE          # ports 8080, 8443, 5007
# add_firewall_port "OpenHAB HTTP" "8080/tcp"
# add_firewall_port "OpenHAB HTTPS" "8443/tcp"

# https://www.openhab.org/docs/installation/linux.html#required-ports-and-firewalls
# Port 	Protocol 	Purpose
# 8080 	TCP 	    openHAB Dashboard via HTTP
# 8443 	TCP 	    openHAB Dashboard via HTTPS
# 5007 	TCP 	    Language Server Protocol (LSP) for VS Code


if $OPENHAB_AVAILABLE; then

    ##### home
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=8080/tcp
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=8443/tcp
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=5007/tcp

    # add_rich "$HOME_ZONE" "rule family=\"ipv4\" source address=\"$HOME_LAN_SUBNET\" port protocol=\"tcp\" port=\"8080\" accept"
    # add_rich "$HOME_ZONE" "rule family=\"ipv4\" source address=\"$HOME_LAN_SUBNET\" port protocol=\"tcp\" port=\"8443\" accept"
    # add_rich "$HOME_ZONE" "rule family=\"ipv4\" source address=\"$HOME_LAN_SUBNET\" port protocol=\"tcp\" port=\"5007\" accept"



    ##### public
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-port=8080/tcp
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-port=8443/tcp
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-port=5007/tcp

    ##### drop
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-port=8080/tcp
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-port=8443/tcp
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-port=5007/tcp


fi



############################
# 8. Radicale (Calendar/Contacts) (CalDAV/CardDAV)
############################
# RADICALE_AVAILABLE
# add_firewall_port "Radicale Web/CalDAV" "5232/tcp"



if $RADICALE_AVAILABLE; then

    ##### home
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=5232/tcp

    # add_rich "$HOME_ZONE" "rule family=\"ipv4\" source address=\"$HOME_LAN_SUBNET\" port protocol=\"tcp\" port=\"5232\" accept"


    ##### public
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-port=5232/tcp


    ##### drop
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-port=5232/tcp


fi



############################
# mDNS and Avahi
############################
# AVAHI_MDNS_AVAILABLE
# add_firewall_service "mdns" # Avahi/mDNS # uses port 5353

# sudo firewall-cmd --permanent --add-service=mdns

if $AVAHI_MDNS_AVAILABLE; then

    ##### home
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-service=mdns

    # add_rich "$HOME_ZONE" "rule family=\"ipv4\" source address=\"$HOME_LAN_SUBNET\" service name=\"mdns\" accept"

    ##### public
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-service=mdns

    ##### drop
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-service=mdns

fi



############################
# Grayjay
############################
# GRAYJAY_AVAILABLE          # Grayjay sync + mDNS (only on home)


# Port        Protocol	  Purpose?                                                  Needed?
# 12315	      TCP	        Grayjay direct device sync	                              Yes
# 12315	      UDP	        Possibly useful for LAN discovery/connection behavior	    Optional (Recommended if sync isn't working)
# 9000	      TCP	        Grayjay relay connection	                                No (Outbound for relay)
# 80/443	    TCP	        Grayjay/content/services	                                No (Outbound already allowed; don't add as inbound)
# mDNS 5353	  UDP	        Potential LAN discovery	                                  Possibly, but not the primary sync port


if $GRAYJAY_AVAILABLE; then

    ##### home
    # Essential - direct device sync
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=12315/tcp

    # Optional: Only if Grayjay's LAN device discovery requires it in your setup:
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=12315/udp

    # Grayjay's relay connection is outbound, so your normal outbound traffic policy allows it. Do not open 9000/tcp in either zone.

    # add_rich "$HOME_ZONE" "rule family=\"ipv4\" source address=\"$HOME_LAN_SUBNET\" port protocol=\"tcp\" port=\"12315\" accept"


    ##### public
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-port=12315/tcp
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-port=12315/udp


    ##### drop
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-port=12315/tcp
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-port=12315/udp

fi


############################
# samba and samba-client
############################
# SAMBA_CLIENT_AVAILABLE
# add_firewall_service "samba"

# Not using samba for network shares, etc. So remove it in all zones

if $SAMBA_CLIENT_AVAILABLE; then

    ##### home
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --remove-service=samba
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --remove-service=samba-client

    ##### public
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-service=samba
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-service=samba-client

    ##### drop
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-service=samba
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-service=samba-client

fi




############################
# Home Assistant
############################
# HOME_ASSISTANT_AVAILABLE
# add_firewall_port "Home Assistant UI" "8123/tcp"
# Required Ports for Home Assistant
#     TCP 8123:                         Sure - The primary web frontend and API port. This is mandatory for accessing the dashboard or using the companion app.   
#     UDP 5353 (Multicast DNS - mDNS),  Not sure - Required for local auto-discovery of smart home devices.   
#     UDP 1900: SSDP/UPnP,              Not sure - Used by various smart devices to announce themselves on the local network.   

# 8123 - This is only needed to be added to access the Home Assistant frontend that is running on a host outside of the host machine
# https://www.home-assistant.io/installation/linux/#no-access-to-the-frontend
# https://www.home-assistant.io/integrations/http/
# https://www.home-assistant.io/docs/configuration/remote/

if $HOME_ASSISTANT_AVAILABLE; then
    ##### home
    sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=8123/tcp
    ##### public
    sudo firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-port=8123/tcp
    ##### drop
    sudo firewall-cmd --permanent --zone="$DROP_ZONE" --remove-port=8123/tcp
fi


############################
# Nextcloud
############################
# NEXTCLOUD_AVAILABLE
# https://github.com/nextcloud-releases/all-in-one/blob/main/reverse-proxy.md

# https://docs.nextcloud.com/server/stable/admin_manual/installation/index.html
# Nextcloud Server Host (Hosting Nextcloud locally)
# If this machine is running the Nextcloud server (e.g., via Docker or native Apache/Nginx), incoming web traffic needs to reach the web server:
# Just needs http and https - we toook care of these above. See setting of NEXTCLOUD_AVAILABLE above

# https://apps.nextcloud.com/apps/nextcloud_all_in_one
# https://github.com/nextcloud/all-in-one
# For Nextcloud AIO - Required Firewall Ports:
#     TCP 80 & 443:     Standard HTTP and HTTPS web traffic. Required for Let's Encrypt automated SSL certificate generation and general browser/client synchronization.   
#     TCP 8080 / 8443:  Used specifically for the initial Nextcloud AIO master container setup interface. (Can be closed after the initial setup is complete).   
#     TCP/UDP 3478:     Required if you enable Nextcloud Talk for high-performance audio/video calls and TURN server functionality.  
# sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-service=http
# sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-service=https
# sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=8080/tcp
# sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=3478/tcp
# sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-port=3478/udp


############################
# QBITTORRENT
############################
# QBITTORRENT_AVAILABLE
# add_firewall_port "qBittorrent Peer Port (TCP)" "6881/tcp"
# add_firewall_port "qBittorrent Peer Port (UDP)" "6881/udp"
# Uncomment the line below if you have the Web UI enabled and need inbound access:
# add_firewall_port "qBittorrent Web UI" "8080/tcp"


############################
# IoT
############################

# --- Optional: explicitly reject specific known IoT devices on the same
#     subnet even though they technically match $HOME_LAN_SUBNET above.
#     Fill in actual IPs (ideally give them DHCP reservations first) if you
#     want this belt-and-suspenders layer. Rich rules are evaluated in
#     priority order; a reject with an explicit priority below the accepts
#     above can carve out exceptions. Left disabled by default:
# add_rich "$HOME_ZONE" "rule family=\"ipv4\" source address=\"192.168.0.50\" priority=\"-10\" reject"

# Block IoT subnet explicitly
# If IoT devices are on same subnet (not ideal), you can still block them:
# Find IP of Google Home, Alexa, etc and other smart devices that shouldn't need access to your PC and:
# sudo firewall-cmd --permanent \
#   --add-rich-rule='rule family="ipv4" source address="192.168.0.ABC" reject'


############################
# Cups (Printing service) - Common Unix Printing System
############################
# CUPS_AVAILABLE
# add_firewall_service "ipp" # CUPS

# Only needed when hosting a Printer - If other devices on your network need to send print jobs to a printer connected directly to this machine:
# sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-service=ipp 


############################
# Tailscale
############################
# TAILSCALE_AVAILABLE
# https://tailscale.com/docs/reference/faq/firewall-ports
# https://tailscale.com/docs/reference/netfilter-modes

# Once Tailscale is installed, don't open SSH on the public zone to reach
# these PCs remotely - bind SSH to the tailscale0 interface instead, e.g.:
#
#   sudo firewall-cmd --permanent --zone=trusted --add-interface=tailscale0
#   sudo firewall-cmd --permanent --zone=trusted --add-service=ssh
#   sudo firewall-cmd --reload
#
# Tailscale's own ACLs (tailnet policy) then become your actual access
# control layer, and these PCs never expose SSH to the raw internet at all.


############################
# Cockpit
############################
# COCKPIT_AVAILABLE
# add_firewall_service "cockpit" # opens TCP port 9090
# which allows other devices on your local home network to access the Cockpit web-based management dashboard of that machine via https://<ip-address>:9090.
# access Cockpit locally on the host machine via http://localhost:9090 or https://localhost:9090 regardless of firewall rules

# sudo firewall-cmd --permanent --zone="$HOME_ZONE" --add-service=cockpit

############################
# DNS
############################
# DNS_AVAILABLE
# add_firewall_service "dns"

# "$DROP_ZONE" profile - Optional: allow DNS + DHCP implicitly via system
# Only allow outbound (default behavior)


############################
# DHCP
############################
# DHCP_AVAILABLE
# add_firewall_service "dhcp"

# "$DROP_ZONE" profile - Optional: allow DNS + DHCP implicitly via system
# Only allow outbound (default behavior)


############################
# DHCPv6
############################
# DHCPV6_AVAILABLE
# add_firewall_service "dhcpv6"

# "$DROP_ZONE" profile - Optional: allow DNS + DHCP implicitly via system
# Only allow outbound (default behavior)
# firewall-cmd --permanent --zone="$PUBLIC_ZONE" --remove-service=dhcpv6-client 


############################
# IPv6
############################
# IPV6_AVAILABLE           # keep IPv6; set false to drop all IPv6

#   if [[ "$IPV6_AVAILABLE" != "true" ]]; then
#     firewall-cmd --permanent --zone="$PUBLIC_ZONE" --add-rich-rule='rule family="ipv6" drop'
#   fi


#   if [[ "$IPV6_AVAILABLE" != "true" ]]; then
#     firewall-cmd --permanent --zone="$DROP_ZONE" --add-rich-rule='rule family="ipv6" drop'
#   fi


############################
# Docker
############################
# DOCKER_AVAILABLE

############################
# Kubernetes
############################
# KUBERNETES_AVAILABLE



#########################################################
# Assign zones to known connections
#########################################################

# Could be done later using nbFirewalldSetConnectionZone
# Or can be done later by calling:
# bash "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/firewalld_assign_zone_to_connection.sh $CONNECTION_NAME $ZONE






# Home Wi-Fi: When you walk into your house, Fedora recognizes the SSID and automatically switches to the home zone, opening up your OpenHAB and Radicale ports so your devices can sync.
# Automating the Switch - Now, you need to tell Fedora which Wi-Fi connection is your "Home." Run this while connected to your home router:
# Replace 'MyHomeWiFi' with your actual Wi-Fi name (SSID)
# sudo nmcli connection modify "MyHomeWiFi" connection.zone "$HOME_ZONE"
# Now, whenever you connect to that Wi-Fi, Fedora instantly opens your OpenHAB and KDE Connect ports. When you disconnect or go to a coffee shop, it defaults back to the public zone, where it is a "Black Hole" again.


# Zone switching: uses NetworkManager's NATIVE per-connection zone binding
#    (nmcli connection modify <conn> connection.zone="$HOME_ZONE"), NOT a custom
#    SSID-sniffing dispatcher script. NM already does this natively per saved
#    connection profile - a dispatcher script duplicates that logic, adds a
#    failure point, and needs root-owned copies of your scripts in /usr/local.

#   # Bind your actual home Wi-Fi / Ethernet profile(s) to the home zone:
#   sudo nmcli connection modify "<YourHomeWiFiName>" connection.zone "$HOME_ZONE"
#   sudo nmcli connection modify "<YourHomeEthernetName>" connection.zone "$HOME_ZONE"
# sudo nmcli connection modify "KNSv1" connection.zone "$HOME_ZONE"
# sudo nmcli connection modify "KNSv4" connection.zone "$HOME_ZONE"





# Prefered method - populate these connections lists before running the code and then use them
# TODO - loop over these and assign zones
# TODO - read the TODO above where we declare these sets
# HOME_ZONE_CONNECTIONS
# PUBLIC_ZONE_CONNECTIONS

# if anything in HOME_ZONE_CONNECTIONS
# for home
# sudo nmcli connection modify "$CONNECTION_NAME" connection.zone "$HOME_ZONE"
# done

# if anything in PUBLIC_ZONE_CONNECTIONS
# for public
# sudo nmcli connection modify "$CONNECTION_NAME" connection.zone "$PUBLIC_ZONE"
# done





# Alternative method - Ask for these connections lists while running the code and then use them - asked above. Search TRUSTED_SSIDS
# In either case, reuse the loop if it looks good

# # Default fallback if empty
# if [[ ${#TRUSTED_SSIDS[@]} -eq 0 ]]; then
#     TRUSTED_SSIDS=("HomeWiFi")
# fi

# # Configure explicit NM connection zone bindings if active SSID matches trusted list
# CURRENT_SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2 || true)
# if [[ -n "$CURRENT_SSID" ]]; then
#     for s in "${TRUSTED_SSIDS[@]}"; do
#         if [[ "$CURRENT_SSID" == "$s" ]]; then
#             echo "Setting persistent zone $HOME_ZONE for active connection: $CURRENT_SSID"
#             nmcli connection modify "$CURRENT_SSID" connection.zone "$HOME_ZONE" || true
#             /usr/local/bin/fw-profile "$HOME_ZONE"
#             break
#         fi
#     done
# fi






# # Verify it was set:
# nmcli -f connection.zone connection show "$CONNECTION_NAME"


#########################################################
# Create aliases in .zshrc
#########################################################


sudo tee -a "$HOME_DIR/.zshrc" <<'FIREWALLD_ZSHRC_EOF'

############################
# firewalld stuff
############################

# Configured zones: home, public, drop

# script that is intended to just set a firewalld zone only for current usage without affecting the global defaults
# Usage
# nbFirewalldSwitchZone home
# nbFirewalldSwitchZone status
# nbFirewalldSwitchZone <firewalld_zone|status>
nbFirewalldSwitchZone() {
    sudo sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/firewalld_switch_current_zone.sh "$@"
}


# Sets a firewalld zone to a connection such that whenever connected to that wifi/ethernet connection, the PC automatically switches to the assigned zone 
# Needs to be set only once when a new wifi/ethernet connection is added
# Usage
# nbFirewalldSetConnectionZone "Wired connection 1" home
# nbFirewalldSetConnectionZone <connection name> <firewalld zone>
nbFirewalldSetConnectionZone() {
    sudo sh "$SYSUPDATE_CODE_BASE_DIR"/linux/security_os_level/firewalld_assign_zone_to_connection.sh "$@"
}

############################

FIREWALLD_ZSHRC_EOF


#########################################################
# Apply changes and verify
#########################################################

# Apply changes
sudo firewall-cmd --reload
nmcli connection reload
systemctl restart NetworkManager


nmcli connection show
# nmcli -f NAME,DEVICE,TYPE connection show --active

# confirm the firewall reloaded successfully and is running
sudo firewall-cmd --state

# To verify active zones
sudo firewall-cmd --get-active-zones

# To verify which zone is currently active and what it's blocking, run:
sudo firewall-cmd --list-all
# firewall-cmd --list-all --zone="$PUBLIC_ZONE"

systemctl is-active firewalld

for z in "$PUBLIC_ZONE" "$HOME_ZONE" "$DROP_ZONE"; do
  if firewall-cmd --get-zones | grep -qw "$z"; then
    echo "--- Zone: $z ---"
    firewall-cmd --zone="$z" --list-all
    echo
    # firewall-cmd --zone="$z" --list-services
    # echo
  fi
done


systemctl is-active firewalld
systemctl is-enabled firewalld

# The zone details are stored in xml files here. Not sure if they are just an output for use and not the actual place for configuration
# cd /etc/firewalld/zones

# To reset all zone configs to default state of firewalld: (Method 1)
# firewall-cmd --load-zone-defaults=FedoraWorkstation --permanent
# firewall-cmd --reload

# To reset all zone configs to default state of firewalld: (Method 2)
# rm -rf /etc/firewalld/zones/
# This will cause firewalld to use the default file in /usr/lib/firewalld/zones/.
# After removing the configuration you can restart firewalld to take effect, and then any configuration changes made followed by a subsequent 'Runtime to permanent' configuration will get the updated configuration written to /etc/firewalld/zones/ again.

