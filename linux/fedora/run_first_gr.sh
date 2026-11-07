#!/bin/bash

# Useful Links
# https://docs.fedoraproject.org/en-US/quick-docs/upgrading-fedora-new-release/
# https://docs.fedoraproject.org/en-US/quick-docs/switching-desktop-environments/
# https://docs.fedoraproject.org/en-US/quick-docs/systemd-understanding-and-administering/
# https://docs.fedoraproject.org/en-US/quick-docs/debug-systemd-problems/
# https://docs.fedoraproject.org/en-US/quick-docs/viewing-logs/
# https://docs.fedoraproject.org/en-US/quick-docs/kernel-overview/
# https://rpmfusion.org/Configuration
# https://rpmfusion.org/Howto/Multimedia
# https://discussion.fedoraproject.org/t/btrfs-snapshots-in-fedora-the-definitive-step-by-step-easy-and-safe-guide/194483
# https://fedoraproject.org/wiki/Changes/StableSSIDMACAddress

#########################################################
# Strict mode + early helpers
#########################################################

set -Eeuo pipefail

log_info()    { printf '[INFO]  %s\n' "$*"; }
log_success() { printf '[OK]    %s\n' "$*"; }
log_warn()    { printf '[WARN]  %s\n' "$*" >&2; }
log_error()   { printf '[ERROR] %s\n' "$*" >&2; }

require_script() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    log_error "Required script missing: $path"
    exit 1
  fi
}

# Backup a file before overwriting it. Creates timestamped copy under SCRIPT_BACKUPS_DIR.
backup_file() {
  local src="$1"
  local dest_dir="${SCRIPT_BACKUPS_DIR}/${FILENAME_TIMESTAMP}"
  if [[ -f "$src" ]]; then
    mkdir -p "$dest_dir"
    cp -a "$src" "$dest_dir/$(basename "$src").bak"
    log_info "Backed up $src"
  fi
}

# Do not run as root
if [[ ${EUID:-0} -eq 0 ]] || [[ "$(id -u)" -eq 0 ]]; then
  log_error "Do not run as root (or with sudo). Packages and directories would land in root home."
  log_error "You are running as $(whoami)."
  exit 1
fi

# Authenticate sudo once up front
sudo -v || {
  log_error "sudo authentication failed."
  exit 1
}

log_info "NOTE: The script will re-prompt for sudo periodically until the end."
sleep 2

#########################################################
# Read-only constants (emulated enums)
#########################################################

readonly PC_TYPE_DESKTOP="desktop"
readonly PC_TYPE_LAPTOP="laptop"
readonly PC_TYPE_HEADLESS_SERVER="server"

readonly PRIVACY_HOME="home"
readonly PRIVACY_PORTABLE="portable"
readonly PRIVACY_PARANOID="paranoid"

readonly SETUP_TYPE_FULL="full"
readonly SETUP_TYPE_LIGHT="light"
readonly SETUP_TYPE_MINIMAL="minimal"

readonly DESKTOP_KDE="kde"
readonly DESKTOP_GNOME="gnome"
readonly DESKTOP_COSMIC="cosmic"

#########################################################
# User-Defined constants and flags
# Edit these before running
#########################################################

PC_TYPE=""                              # auto-detected if empty
PRIVACY_LEVEL="${PRIVACY_PORTABLE}"     # home | portable | paranoid
SETUP_TYPE="${SETUP_TYPE_LIGHT}"        # full | light | minimal

NEW_ETHERNET_NAME=""                    # e.g. nbEthernet (only if on ethernet)
HOSTNAME=""                             # required
GIT_USER_EMAIL=""                       # e.g. 123456+user@users.noreply.github.com
NEXTDNS_ID=""                           # required
NEXTDNS_DEVICE_ID=""                    # defaults to HOSTNAME if empty

HAS_TORRENT_CLIENT=false
HAS_KODI=false
MEDIA_PC=false                          # Grayjay, FreeTube, Kodi, Spotify, etc.
CONFERENCING_APPS=false                 # Zoom, Proton Meet, etc.

#########################################################
# Inferred constants
#########################################################

FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"

HOME_LAN_SUBNET=$(python3 -c '
import subprocess, ipaddress
try:
    route = subprocess.check_output(["ip", "-o", "-4", "route", "show", "to", "default"], text=True)
    iface = route.split()[4]
    addr_info = subprocess.check_output(["ip", "-o", "-4", "addr", "show", "dev", iface], text=True)
    cidr = addr_info.split()[3]
    print(ipaddress.ip_network(cidr, strict=False))
except Exception:
    print("192.168.1.0/24")
' 2>/dev/null || echo "192.168.1.0/24")
readonly HOME_LAN_SUBNET

#########################################################
# Real user detection
#########################################################

if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  REAL_USER="$SUDO_USER"
elif [[ -t 0 ]] && [[ -n "$(logname 2>/dev/null)" ]] && [[ "$(logname)" != "root" ]]; then
  REAL_USER="$(logname)"
else
  REAL_USER=$(loginctl list-sessions --no-legend 2>/dev/null \
    | awk '{print $3}' \
    | while read -r u; do
        id -u "$u" &>/dev/null && [[ "$(id -u "$u")" -ge 1000 ]] && echo "$u" && break
      done)
fi
REAL_USER="${REAL_USER:-$USER}"

#########################################################
# Directories
#########################################################

HOME_DIR=$(getent passwd "$REAL_USER" | cut -d: -f6)
NBDIR="$HOME_DIR/nb"
CODEPROJECTS_DIR="$NBDIR/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="$CODEPROJECTS_DIR/system_update"

DESKTOP_DIR="$NBDIR/Desktop"
DOCUMENTS_DIR="$NBDIR/Documents"
DOWNLOADS_DIR="$NBDIR/Downloads"
VIDEOS_DIR="$NBDIR/Videos"
PICTURES_DIR="$NBDIR/Pictures"
MUSIC_DIR="$NBDIR/Music"
PUBLIC_DIR="$NBDIR/Public"
TEMPLATES_DIR="$NBDIR/Templates"
PROJECTS_DIR="$NBDIR/Projects"

SCRIPT_DATA_DIR="$NBDIR/nb_script_data"
SCRIPT_BACKUPS_DIR="$SCRIPT_DATA_DIR/backups"
SCRIPT_DOWNLOADS_DIR="$SCRIPT_DATA_DIR/downloads"
SCRIPT_LOGS_DIR="$SCRIPT_DATA_DIR/logs"

#########################################################
# Verify required user-defined values
#########################################################

if [[ -z "$HOSTNAME" ]]; then
  log_error "HOSTNAME must be set."
  exit 1
fi
if [[ -z "$NEXTDNS_ID" ]]; then
  log_error "NEXTDNS_ID must be set."
  exit 1
fi
NEXTDNS_DEVICE_ID="${NEXTDNS_DEVICE_ID:-$HOSTNAME}"

if [[ -z "$GIT_USER_EMAIL" ]]; then
  log_warn "GIT_USER_EMAIL not provided. Continuing, but git config will be incomplete."
  sleep 3
fi

#########################################################
# Create directories + ownership
#########################################################

mkdir -p \
  "$SCRIPT_DATA_DIR" "$SCRIPT_BACKUPS_DIR" "$SCRIPT_DOWNLOADS_DIR" "$SCRIPT_LOGS_DIR" \
  "$DESKTOP_DIR" "$DOCUMENTS_DIR" "$DOWNLOADS_DIR" "$VIDEOS_DIR" \
  "$PICTURES_DIR" "$MUSIC_DIR" "$PUBLIC_DIR" "$TEMPLATES_DIR" "$PROJECTS_DIR"

sudo chown -R "$REAL_USER:$REAL_USER" \
  "$SCRIPT_DATA_DIR" "$SCRIPT_BACKUPS_DIR" "$SCRIPT_DOWNLOADS_DIR" "$SCRIPT_LOGS_DIR" \
  "$DESKTOP_DIR" "$DOCUMENTS_DIR" "$DOWNLOADS_DIR" "$VIDEOS_DIR" \
  "$PICTURES_DIR" "$MUSIC_DIR" "$PUBLIC_DIR" "$TEMPLATES_DIR" "$PROJECTS_DIR"

#########################################################
# Identify PC type, desktop, distro, hardware profile
#########################################################

require_script "$SYSUPDATE_CODE_BASE_DIR/linux/commong/get_pc_type.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/commong/get_desktop_env.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/commong/get_distro_name.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/commong/get_is_ethernet.sh"

if [[ -z "$PC_TYPE" ]]; then
  PC_TYPE=$(bash "$SYSUPDATE_CODE_BASE_DIR/linux/commong/get_pc_type.sh")
fi

case "$PC_TYPE" in
  "$PC_TYPE_LAPTOP")                  PRIVACY_LEVEL="${PRIVACY_LEVEL:-$PRIVACY_PARANOID}" ;;
  "$PC_TYPE_DESKTOP"|"$PC_TYPE_HEADLESS_SERVER") PRIVACY_LEVEL="${PRIVACY_LEVEL:-$PRIVACY_HOME}" ;;
  *)                                  PRIVACY_LEVEL="${PRIVACY_LEVEL:-$PRIVACY_PORTABLE}" ;;
esac

DESKTOP=$(bash "$SYSUPDATE_CODE_BASE_DIR/linux/commong/get_desktop_env.sh")
if [[ -z "$DESKTOP" ]]; then
  log_error "Desktop environment not identified. Fix get_desktop_env.sh"
  exit 1
fi
log_info "Desktop Environment: $DESKTOP"

DISTRO=$(bash "$SYSUPDATE_CODE_BASE_DIR/linux/commong/get_distro_name.sh")
if [[ -z "$DISTRO" ]]; then
  log_error "Distro not identified. Fix get_distro_name.sh"
  exit 1
fi
log_info "Distro: $DISTRO"

IS_ETHERNET=$(bash "$SYSUPDATE_CODE_BASE_DIR/linux/commong/get_is_ethernet.sh")

# Hardware profile
TOTAL_RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
LOW_RAM=false
if (( TOTAL_RAM_MB <= 8192 )); then
  LOW_RAM=true
  log_warn "Low-RAM machine detected (${TOTAL_RAM_MB} MB). Package lists and ClamAV will be lighter."
fi

log_info "HOME_DIR=$HOME_DIR"
log_info "SYSUPDATE_CODE_BASE_DIR=$SYSUPDATE_CODE_BASE_DIR"
log_info "PRIVACY_LEVEL=$PRIVACY_LEVEL  SETUP_TYPE=$SETUP_TYPE  PC_TYPE=$PC_TYPE  LOW_RAM=$LOW_RAM"
sleep 2

#########################################################
# Btrfs Snapper – pre-install safety net
#########################################################

if findmnt -n -o FSTYPE / | grep -q btrfs; then
  log_info "Btrfs detected – installing Snapper + creating pre-run snapshot"
  sudo dnf install -y snapper snapper-dnf-plugin btrfs-assistant || true

  if ! snapper -c root get-config &>/dev/null; then
    sudo snapper -c root create-config /
  fi

  # Conservative retention for desktop use
  sudo sed -i \
    -e 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="yes"/' \
    -e 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="8"/' \
    -e 's/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="5"/' \
    -e 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="3"/' \
    -e 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="5"/' \
    -e 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="2"/' \
    /etc/snapper/configs/root 2>/dev/null || true

  sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer 2>/dev/null || true
  sudo snapper -c root create --description "Pre-run_first baseline ${FILENAME_TIMESTAMP}" || true
  log_success "Pre-run Snapper snapshot created"
else
  log_warn "Root is not Btrfs – Snapper skipped"
fi

#########################################################
# NetworkManager privacy (MAC randomization)
# stable-ssid = different stable MAC per SSID (Fedora 40+ recommended)
# Do NOT restart NetworkManager here.
#########################################################

sudo mkdir -p /etc/NetworkManager/conf.d
sudo tee /etc/NetworkManager/conf.d/00-macrandomize.conf > /dev/null <<'EOL'
[device]
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=stable-ssid
EOL

log_success "NetworkManager MAC randomization set to stable-ssid"

# Optional ethernet rename
if [[ "$IS_ETHERNET" == "true" && -n "$NEW_ETHERNET_NAME" ]]; then
  CURRENT_ETHERNET_NAME=$(nmcli -t -f TYPE,CONNECTION device | awk -F: '$1=="ethernet"{print $2; exit}')
  if [[ -n "$CURRENT_ETHERNET_NAME" ]]; then
    log_info "Renaming ethernet connection $CURRENT_ETHERNET_NAME → $NEW_ETHERNET_NAME"
    nmcli connection modify "$CURRENT_ETHERNET_NAME" connection.id "$NEW_ETHERNET_NAME" || true
  fi
fi

#########################################################
# DNF configuration (drop-in preferred)
#########################################################

log_info "Configuring DNF"
sudo mkdir -p /etc/dnf/libdnf5.conf.d
sudo tee /etc/dnf/libdnf5.conf.d/50-local.conf > /dev/null <<'EOL'
[main]
max_parallel_downloads=10
defaultyes=True
keepcache=True
installonly_limit=3
clean_requirements_on_remove=True
deltarpm=False
color=always
EOL

sudo tee /etc/dnf/dnf.conf > /dev/null <<'EOL'
# see man dnf.conf
[main]
max_parallel_downloads=10
defaultyes=True
keepcache=True
installonly_limit=3
clean_requirements_on_remove=True
deltarpm=False
color=always
EOL

log_success "DNF configured (max_parallel=10, keepcache, installonly_limit=3)"

#########################################################
# Firmware update (early)
#########################################################

if command -v fwupdmgr &>/dev/null; then
  log_info "Refreshing firmware metadata"
  sudo fwupdmgr refresh --force || true
  sudo fwupdmgr get-updates || true
  # Uncomment to apply firmware automatically:
  # sudo fwupdmgr update || true
fi

#########################################################
# Core repositories + base packages
#########################################################

log_info "Installing base packages and enabling repositories"
sudo dnf install -y git flatpak

# Remove unwanted defaults early
sudo dnf remove -y totem yelp gnome-tour gnome-connections firefox 2>/dev/null || true
sudo rm -rf /opt/firefox 2>/dev/null || true
rm -f ~/.local/share/applications/firefox.desktop 2>/dev/null || true
rm -rf ~/.mozilla 2>/dev/null || true

# RPM Fusion
sudo dnf install -y \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

sudo dnf install -y fedora-workstation-repositories
sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1 || true

#########################################################
# Hardware video acceleration + multimedia
#########################################################

log_info "Installing hardware-accelerated codecs"
sudo dnf install -y \
  libva-intel-driver \
  intel-media-driver \
  mesa-va-drivers-freeworld \
  mesa-vdpau-drivers-freeworld || true

sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing || true
sudo dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin || true
sudo dnf group install -y multimedia || true
sudo dnf install -y gstreamer1-plugin-openh264 mozilla-openh264 || true

#########################################################
# Flatpak + AppImage helpers
#########################################################

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

if [[ ! -f /usr/local/bin/am ]]; then
  curl -s -Lo /tmp/AM-INSTALLER https://raw.githubusercontent.com/ivan-hc/AM/main/AM-INSTALLER
  chmod +x /tmp/AM-INSTALLER
  /tmp/AM-INSTALLER || true
  rm -f /tmp/AM-INSTALLER
fi

#########################################################
# Hostname
#########################################################

sudo hostnamectl set-hostname "$HOSTNAME"
log_success "Hostname set to $HOSTNAME"

#########################################################
# Core CLI + desktop packages
#########################################################

sudo dnf install -y gh fzf fastfetch

if [[ "$SETUP_TYPE" == "$SETUP_TYPE_FULL" ]]; then
  sudo dnf install -y ksystemlog htop keepassxc timeshift vlc
  if [[ "$HAS_TORRENT_CLIENT" == true ]]; then
    sudo dnf install -y qbittorrent
  fi
fi

if [[ "$DESKTOP" == "$DESKTOP_GNOME" ]]; then
  sudo dnf install -y gnome-tweaks
  if [[ "$SETUP_TYPE" == "$SETUP_TYPE_FULL" ]]; then
    sudo dnf install -y gparted liferea quiterss
  fi
  xdg-user-dirs-update --set DOWNLOAD "$DOWNLOADS_DIR" || true
  gsettings set org.gnome.desktop.wm.preferences button-layout "appmenu:minimize,maximize,close" || true
elif [[ "$DESKTOP" == "$DESKTOP_KDE" ]]; then
  sudo dnf install -y kde-gtk-config plasma-browser-integration kasts kalarm kbackup
  # Prefer KDE Partition Manager over gparted
fi

#########################################################
# Flatpak applications (respect MEDIA_PC, CONFERENCING, LOW_RAM)
#########################################################

flatpak install -y flathub org.signal.Signal com.github.tchx84.Flatseal it.mijorus.gearlever

if [[ "$SETUP_TYPE" == "$SETUP_TYPE_FULL" ]]; then
  if [[ "$LOW_RAM" == false ]]; then
    # Core communication
    flatpak install -y \
      com.rtosta.zapzap org.telegram.desktop chat.simplex.simplex \
      network.loki.Session im.riot.Riot org.localsend.localsend_app \
      com.sindresorhus.Caprine com.super_productivity.SuperProductivity || true

    # Media stack
    if [[ "$MEDIA_PC" == true ]]; then
      flatpak install -y \
        io.freetubeapp.FreeTube app.grayjay.Grayjay \
        com.spotify.Client || true
      if [[ "$HAS_KODI" == true ]]; then
        # Kodi is usually better as RPM; install only if you really want Flatpak
        true
      fi
    fi

    # Conferencing
    if [[ "$CONFERENCING_APPS" == true ]]; then
      # Zoom is handled by dedicated script later; Proton Meet can be added here if desired
      true
    fi
  else
    log_warn "Low-RAM: installing only essential Flatpaks"
    flatpak install -y org.localsend.localsend_app || true
  fi
fi

# Signal password store
if [[ "$DESKTOP" == "$DESKTOP_KDE" ]]; then
  sudo flatpak override --env=SIGNAL_PASSWORD_STORE=kwallet6 org.signal.Signal || true
  if [[ "$SETUP_TYPE" == "$SETUP_TYPE_FULL" ]]; then
    flatpak override --user im.riot.Riot \
      --talk-name=org.kde.kwalletd6 \
      --talk-name=org.freedesktop.secrets || true
    sudo flatpak override --user --filesystem=home com.rtosta.zapzap || true
  fi
elif [[ "$DESKTOP" == "$DESKTOP_GNOME" || "$DESKTOP" == "$DESKTOP_COSMIC" ]]; then
  sudo flatpak override --env=SIGNAL_PASSWORD_STORE=gnome-libsecret org.signal.Signal || true
fi

#########################################################
# Modular common / security scripts
#########################################################

require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/vscodium.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/librewolf_browser.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/brave_browser.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/tor_browser.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/fonts.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/zsh.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/omz.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/cli_tools.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/starship.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/atuin.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/alacritty_orig.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/bleachbit.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/git.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/syncthing.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/avahi.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/common/mpv.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/dns.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/proton_ag.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/clamav.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/hosts.sh"
require_script "$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/firewalld.sh"

bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/vscodium.sh"
bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/librewolf_browser.sh"
bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/brave_browser.sh"
bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/tor_browser.sh"
bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/fonts.sh"

sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/zsh.sh"
sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/omz.sh"
sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/cli_tools.sh"
sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/starship.sh"
sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/atuin.sh"

bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/alacritty_orig.sh"
bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/bleachbit.sh"
bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/git.sh" "$GIT_USER_EMAIL"
bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/syncthing.sh"
bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/avahi.sh"
bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/mpv.sh"

# DNS / NextDNS – force any downloads into SCRIPT_DOWNLOADS_DIR inside the helper if possible
sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/dns.sh" "$NEXTDNS_ID" "$NEXTDNS_DEVICE_ID"

# Proton (Pass, VPN, Mail, etc.) – helpers should download into $SCRIPT_DOWNLOADS_DIR
bash "$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/proton_ag.sh" \
  --setup-type "$SETUP_TYPE" \
  --desktop "$DESKTOP"

# ClamAV – lighter on low-RAM
CLAMAV_DEBUG=1
if [[ "$LOW_RAM" == true ]]; then
  log_warn "Low-RAM: ClamAV will be configured more lightly"
fi
sudo DEBUG="$CLAMAV_DEBUG" bash "$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/clamav.sh" \
  --pc-type="${PC_TYPE}" \
  --real-user="${REAL_USER}" \
  --torrent-client="${HAS_TORRENT_CLIENT}" \
  --kodi="${HAS_KODI}" \
  --backup-dir="${SCRIPT_BACKUPS_DIR}" \
  --timestamp="${FILENAME_TIMESTAMP}"

bash "$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/hosts.sh"

#########################################################
# Full-setup extras
#########################################################

if [[ "$SETUP_TYPE" == "$SETUP_TYPE_FULL" ]]; then
  bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/bash.sh" || true
  bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/aws.sh" || true

  if [[ "$CONFERENCING_APPS" == true ]]; then
    bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/zoom.sh" || true
  fi

  bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/jetbrains_toolbox.sh" || true
  bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/docker.sh" || true
  bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/neovim_lazyvim.sh" || true
  bash "$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/i2p.sh" || true
  bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/tmux_zellij.sh" || true
  bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/yazi.sh" || true
  bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/mullvad_browser.sh" || true

  if [[ "$DESKTOP" == "$DESKTOP_GNOME" ]]; then
    bash "$SYSUPDATE_CODE_BASE_DIR/linux/common/gsconnect_kde_connect.sh" || true
  fi
fi

#########################################################
# firewalld (near the end) + fail2ban
#########################################################

sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/firewalld.sh" \
  --filename-timestamp "$FILENAME_TIMESTAMP" \
  --script-backups-dir "$SCRIPT_BACKUPS_DIR" \
  --sysupdate-code-base-dir "$SYSUPDATE_CODE_BASE_DIR" \
  --home-lan-subnet "$HOME_LAN_SUBNET" \
  --privacy-level "$PRIVACY_LEVEL" \
  --desktop "$DESKTOP" \
  --home-dir "$HOME_DIR" \
  --real-user "$REAL_USER"

# fail2ban after firewalld
if [[ -f "$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/fail2ban.sh" ]]; then
  log_info "Configuring fail2ban"
  sudo bash "$SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/fail2ban.sh" || true
else
  log_warn "fail2ban.sh not found – skipping"
fi

#########################################################
# MIME defaults
#########################################################

log_info "Setting MIME defaults"
xdg-mime default codium.desktop text/plain || true

# Prefer Brave if present, otherwise LibreWolf
if command -v brave-browser &>/dev/null; then
  xdg-settings set default-web-browser brave-browser.desktop 2>/dev/null || true
  xdg-mime default brave-browser.desktop x-scheme-handler/http || true
  xdg-mime default brave-browser.desktop x-scheme-handler/https || true
elif command -v librewolf &>/dev/null; then
  xdg-settings set default-web-browser librewolf.desktop 2>/dev/null || true
fi

# Video
if command -v vlc &>/dev/null; then
  xdg-mime default vlc.desktop video/mp4 || true
  xdg-mime default vlc.desktop video/x-matroska || true
elif command -v mpv &>/dev/null; then
  xdg-mime default mpv.desktop video/mp4 || true
fi

# PDF
if command -v okular &>/dev/null; then
  xdg-mime default okularApplication_pdf.desktop application/pdf || true
fi

# Terminal (Alacritty preferred)
if command -v alacritty &>/dev/null; then
  # Desktop files vary; this is best-effort
  true
fi

#########################################################
# Final system update + final snapshot
#########################################################

log_info "Final system update"
sudo dnf upgrade --refresh -y || true
flatpak update -y || true

if findmnt -n -o FSTYPE / | grep -q btrfs; then
  sudo snapper -c root create --description "Post-run_first complete ${FILENAME_TIMESTAMP}" || true
  log_success "Final Snapper snapshot created"
fi

#########################################################
# Ownership cleanup
#########################################################

sudo chown -R "$REAL_USER:$REAL_USER" "$NBDIR" || true

#########################################################
# Done
#########################################################

log_success "run_first.sh completed successfully"
log_info "Reboot recommended, especially after firmware or kernel updates."
log_info "Verify: snapper list | firewall-cmd --list-all | systemctl status snapper-timeline.timer"

#########################################################
# Remaining work (tracked)
#########################################################
# - cron_jobs.sh / systemd timers (ClamAV scan, BleachBit, fwupd, flatpak update)
# - fzf key-bindings + FZF_DEFAULT_OPTS (add to cli_tools.sh or dedicated fzf.sh)
# - Ensure all external helpers (proton_ag, browser installers, etc.) download into $SCRIPT_DOWNLOADS_DIR
# - Expand backup_file() usage inside every helper that overwrites configs
# - Optional: Obsidian Flatpak/AppImage, virt-manager (KDE Boxes alternative)
# - Per-app NextDNS unique IDs where the client supports it
# - Power management tuning for laptops (TLP or power-profiles-daemon)

# Notes + Troubleshooting
# - Home network needs permanent MAC (MAC filter / captive portal):
#     nmcli connection modify "YourSSID" wifi.cloned-mac-address permanent
# - Low-RAM machines: prefer SETUP_TYPE=light and review Flatpak list after first run
# - Snapper GUI: btrfs-assistant
# - Re-run is reasonably safe; Snapper gives rollback points
# - Check $SCRIPT_LOGS_DIR and $SCRIPT_BACKUPS_DIR after runs