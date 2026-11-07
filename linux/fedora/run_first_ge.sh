#!/usr/bin/env bash

#########################################################
# Useful Links
#########################################################
# Bash Strict Mode: https://www.baeldung.com/linux/set-command
# Fedora Quick Docs (Upgrades/Admin): https://docs.fedoraproject.org/en-US/quick-docs/
# RPM Fusion Setup: https://rpmfusion.org/Configuration
# RPM Fusion Multimedia & Codecs: https://rpmfusion.org/Howto/Multimedia
# NetworkManager MAC Randomization: https://wiki.archlinux.org/title/NetworkManager#MAC_address_anonymization
# Kernel Hardening & sysctl: https://www.kernel.org/doc/Documentation/sysctl/ / https://wiki.archlinux.org/title/Security

#########################################################
# Strict Mode & Error Handling
#########################################################

# Exit immediately on error (-e), treat unset variables as errors (-u),
# and fail pipelines if any command fails (-o pipefail).
set -euo pipefail

#########################################################
# Standard Logging & Helper Definitions
#########################################################

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'

log_header()  { echo -e "\n${CYAN}==================== $* ====================${NC}\n"; }
log_info()    { echo -e "${BLUE}[INFO] $*${NC}"; }
log_success() { echo -e "${GREEN}[✓] $*${NC}"; }
log_warn()    { echo -e "${YELLOW}[!] $*${NC}"; }
log_error()   { echo -e "${RED}[✗] $*${NC}" >&2; }
log_die()     { echo -e "${RED}[✗] $*${NC}" >&2; exit 1; }

# Trap for tracking failing line numbers and exiting cleanly
failure_handler() {
    local exit_code=$?
    local line_no=$1
    log_error "Script failed at line ${line_no} with exit status code ${exit_code}."
    exit "${exit_code}"
}
trap 'failure_handler ${LINENO}' ERR

# SELinux-aware configuration deployment helper function
deploy_config_file() {
    local src="$1"
    local dest="$2"
    local mode="${3:-644}"
    
    if [ -e "$dest" ]; then
        log_info "Backing up existing ${dest} to ${SCRIPT_BACKUPS_DIR}"
        mkdir -p "${SCRIPT_BACKUPS_DIR}/$(dirname "${dest#$HOME_DIR/}")"
        cp -a "$dest" "${SCRIPT_BACKUPS_DIR}/${FILENAME_TIMESTAMP}_$(basename "$dest")"
    fi
    
    sudo mkdir -p "$(dirname "$dest")"
    sudo cp "$src" "$dest"
    sudo chmod "$mode" "$dest"
    
    if command -v selinuxenabled &>/dev/null && selinuxenabled; then
        sudo restorecon -R -v "$dest"
    fi
    log_success "Deployed and secured: ${dest}"
}

# Secure execution helper for remote installer scripts to prevent raw curl | sh vulnerability
secure_install_script() {
    local script_name="$1"
    local download_url="$2"
    local target_path="${SCRIPT_DOWNLOADS_DIR}/${script_name}"
    
    log_info "Securely downloading ${script_name} to ${SCRIPT_DOWNLOADS_DIR}..."
    mkdir -p "$SCRIPT_DOWNLOADS_DIR"
    curl -sSfL "$download_url" -o "$target_path"
    chmod +x "$target_path"
    
    log_info "Executing ${script_name}..."
    bash "$target_path"
    rm -f "$target_path"
}

#########################################################
# User Check & Credential Authentication
#########################################################

log_header "User Authentication & Privileges Check"

if [ "${EUID:-0}" -eq 0 ] || [ "$(id -u)" -eq 0 ]; then
  log_die "Please do not run as root (or with sudo). This may set up packages and create directories in root's home directory. You are running as $(whoami)."
fi

sudo -v || log_die "ERROR: sudo authentication failed."

log_warn "The script will require root privilege execution via sudo periodically."
sleep 2

#########################################################
# Read-Only Constants (Emulated Enums)
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
# Named Options Processing (CLI Arguments)
#########################################################

CLI_PC_TYPE=""
CLI_PRIVACY_LEVEL=""
CLI_SETUP_TYPE=""
CLI_HOSTNAME=""
CLI_NEXTDNS_ID=""
CLI_GIT_USER_EMAIL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pc-type)
            CLI_PC_TYPE="$2"
            shift 2
            ;;
        --privacy-level)
            CLI_PRIVACY_LEVEL="$2"
            shift 2
            ;;
        --setup-type)
            CLI_SETUP_TYPE="$2"
            shift 2
            ;;
        --hostname)
            CLI_HOSTNAME="$2"
            shift 2
            ;;
        --nextdns-id)
            CLI_NEXTDNS_ID="$2"
            shift 2
            ;;
        --git-email)
            CLI_GIT_USER_EMAIL="$2"
            shift 2
            ;;
        *)
            log_die "Unknown option passed to script: $1"
            ;;
    esac
done

#########################################################
# User-Defined Variables & Defaults
#########################################################

log_header "Setting User-Defined Variables & Defaults"

PC_TYPE="${CLI_PC_TYPE:-""}"
PRIVACY_LEVEL="${CLI_PRIVACY_LEVEL:-"${PRIVACY_PORTABLE}"}"
SETUP_TYPE="${CLI_SETUP_TYPE:-"${SETUP_TYPE_LIGHT}"}"

NEW_ETHERNET_NAME="" 
HOSTNAME="${CLI_HOSTNAME:-""}"
GIT_USER_EMAIL="${CLI_GIT_USER_EMAIL:-""}"
NEXTDNS_ID="${CLI_NEXTDNS_ID:-""}"

HAS_TORRENT_CLIENT=false
HAS_KODI=false
MEDIA_PC=false
CONFERENCING_APPS=false

#########################################################
# Dynamic System Identification & Inferred Variables
#########################################################

log_header "Identifying Real User & System Environment"

if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    REAL_USER="$SUDO_USER"
elif [ -t 0 ] && [ -n "$(logname 2>/dev/null)" ] && [ "$(logname)" != "root" ]; then
    REAL_USER="$(logname)"
else
    REAL_USER=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | while read -r u; do id -u "$u" &>/dev/null && [ "$(id -u "$u")" -ge 1000 ] && echo "$u" && break; done || true)
fi
REAL_USER="${REAL_USER:-$USER}"
readonly REAL_USER

FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
readonly FILENAME_TIMESTAMP

HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
readonly HOME_DIR

NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update"

DESKTOP_DIR="${NBDIR}/Desktop"
DOCUMENTS_DIR="${NBDIR}/Documents"
DOWNLOADS_DIR="${NBDIR}/Downloads"
VIDEOS_DIR="${NBDIR}/Videos"
PICTURES_DIR="${NBDIR}/Pictures"
MUSIC_DIR="${NBDIR}/Music"
PUBLIC_DIR="${NBDIR}/Public"
TEMPLATES_DIR="${NBDIR}/Templates"
PROJECTS_DIR="${NBDIR}/Projects"

SCRIPT_DATA_DIR="${NBDIR}/nb_script_data"
SCRIPT_BACKUPS_DIR="${SCRIPT_DATA_DIR}/backups"
SCRIPT_DOWNLOADS_DIR="${SCRIPT_DATA_DIR}/downloads"
SCRIPT_LOGS_DIR="${SCRIPT_DATA_DIR}/logs"

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

IS_ETHERNET=$(sh "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_is_ethernet.sh" 2>/dev/null || echo false)

if [ -z "$PC_TYPE" ]; then
    PC_TYPE=$(sh "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_pc_type.sh" 2>/dev/null || echo "$PC_TYPE_DESKTOP")
fi
readonly PC_TYPE

if [ -z "$CLI_PRIVACY_LEVEL" ]; then
  case "$PC_TYPE" in
      "$PC_TYPE_LAPTOP")           PRIVACY_LEVEL="$PRIVACY_PARANOID" ;;
      "$PC_TYPE_DESKTOP"|"$PC_TYPE_HEADLESS_SERVER") PRIVACY_LEVEL="$PRIVACY_HOME" ;;
      *)                           PRIVACY_LEVEL="$PRIVACY_PORTABLE" ;;
  esac
fi
readonly PRIVACY_LEVEL

NEXTDNS_DEVICE_ID="${HOSTNAME:-$(hostname)}"
readonly NEXTDNS_DEVICE_ID

DESKTOP=$(sh "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_desktop_env.sh" 2>/dev/null || echo "")
[ -z "$DESKTOP" ] && log_die "Desktop Environment not identified. Fix get_desktop_env.sh and run again."
readonly DESKTOP

DISTRO=$(sh "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/get_distro_name.sh" 2>/dev/null || echo "")
[ -z "$DISTRO" ] && log_die "Distro not identified. Fix get_distro_name.sh and run again."
readonly DISTRO

if [ -z "$HOSTNAME" ] || [ -z "$NEXTDNS_ID" ]; then
  log_die "Mandatory parameters missing: Please specify --hostname and --nextdns-id via command flags or set them in the script user variables."
fi

#########################################################
# Directory Creation & Ownership Normalization
#########################################################

log_header "Creating Standard Directory Hierarchy"

mkdir -p "$SCRIPT_DATA_DIR" "$SCRIPT_BACKUPS_DIR" "$SCRIPT_DOWNLOADS_DIR" "$SCRIPT_LOGS_DIR" \
         "$DESKTOP_DIR" "$DOCUMENTS_DIR" "$DOWNLOADS_DIR" "$VIDEOS_DIR" \
         "$PICTURES_DIR" "$MUSIC_DIR" "$PUBLIC_DIR" "$TEMPLATES_DIR" "$PROJECTS_DIR"

sudo chown -R "${REAL_USER}:${REAL_USER}" "$NBDIR"
log_success "Base directory structure created and ownership updated to ${REAL_USER}:${REAL_USER}."

#########################################################
# Dynamic Network Connection Setup
#########################################################

if [ "$IS_ETHERNET" = true ] && [ -n "$NEW_ETHERNET_NAME" ]; then
    CURRENT_ETHERNET_NAME=$(nmcli -t -f TYPE,CONNECTION device | awk -F: '$1=="ethernet" {print $2; exit}')
    if [ -n "$CURRENT_ETHERNET_NAME" ]; then
        log_info "Renaming ethernet connection from '${CURRENT_ETHERNET_NAME}' to '${NEW_ETHERNET_NAME}'..."
        nmcli connection modify "$CURRENT_ETHERNET_NAME" connection.id "$NEW_ETHERNET_NAME"
    fi
fi

#########################################################
# NetworkManager Privacy Hardening (MAC Randomization)
#########################################################

log_header "Applying NetworkManager Privacy Hardening"

sudo mkdir -p /etc/NetworkManager/conf.d

sudo tee /etc/NetworkManager/conf.d/00-macrandomize.conf > /dev/null <<EOL
[device]
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=random
ethernet.cloned-mac-address=random
EOL

sudo systemctl restart NetworkManager
log_success "NetworkManager MAC address randomization enabled."

#########################################################
# Kernel Security Hardening (sysctl Drop-in)
#########################################################

log_header "Applying Kernel Hardening Parameters"

sudo tee /etc/sysctl.d/99-security-hardening.conf > /dev/null <<EOL
# Restrict kernel pointer leaks in proc
kernel.kptr_restrict=2

# Restrict dmesg access to root
kernel.dmesg_restrict=1

# Disable kexec to prevent unverified runtime kernel loading
kernel.kexec_load_disabled=1

# Protect against symlink/hardlink exploitation
fs.protected_hardlinks=1
fs.protected_symlinks=1
fs.protected_fifos=2
fs.protected_regular=2

# Enable BPF JIT hardening
net.core.bpf_jit_harden=2
EOL

sudo sysctl --system >/dev/null
log_success "Kernel security parameters enforced."

#########################################################
# DNF Optimization & Configuration
#########################################################

log_header "Optimizing DNF Package Manager Settings"

if [ -f /etc/dnf/dnf.conf ]; then
    sudo cp /etc/dnf/dnf.conf "${SCRIPT_BACKUPS_DIR}/${FILENAME_TIMESTAMP}_dnf.conf"
fi

sudo tee /etc/dnf/dnf.conf > /dev/null <<EOL
[main]
max_parallel_downloads=5
defaultyes=True
clean_requirements_on_remove=True
color=always
deltarpm=False
EOL

log_info "Installing Fedora Workstation extra repositories..."
sudo dnf install -y fedora-workstation-repositories

#########################################################
# Btrfs Auto-Snapshotting Checkpoint (Snapper)
#########################################################

log_header "Configuring Btrfs Snapshots (Snapper Baseline)"

if ! rpm -q snapper &>/dev/null; then
    log_info "Installing snapper and grub-btrfs for filesystem rollbacks..."
    sudo dnf install -y snapper grub-btrfs
fi

if findmnt -n -o FSTYPE / | grep -q btrfs; then
    if ! sudo snapper -c root get-config &>/dev/null; then
        sudo snapper -c root create-config /
    fi
    log_info "Creating pre-setup baseline system snapshot..."
    sudo snapper -c root create --description "Baseline pre-setup system snapshot"
    log_success "Snapper pre-setup snapshot completed."
fi

#########################################################
# Base System Package Setup & Cleanups
#########################################################

log_header "Base Package Management (Install & Remove)"

sudo dnf install -y git flatpak

sudo dnf remove -y totem yelp gnome-tour gnome-connections firefox ptyxis || true

rm -rf ~/.mozilla
rm -f ~/.local/share/applications/firefox.desktop

# If SETUP_TYPE is minimal, purge optional suite/bloat
if [ "$SETUP_TYPE" = "$SETUP_TYPE_MINIMAL" ]; then
    log_info "Applying minimal setup profile: removing optional office, media, and productivity apps..."
    sudo dnf remove -y libreoffice-* rhythmbox totem cheese mediawriter simple-scan || true
fi

#########################################################
# RPM Fusion & Hardware Acceleration (VA-API Freeworld)
#########################################################

log_header "Enabling RPM Fusion & VA-API Codecs"

sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm \
                    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm

sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
sudo dnf update -y @core

log_info "Installing multimedia group and VA-API freeworld drivers..."
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf group install -y multimedia
sudo dnf install -y gstreamer1-plugin-openh264 mozilla-openh264 libva-intel-driver intel-media-driver mesa-va-drivers-freeworld mesa-vdpau-drivers-freeworld

#########################################################
# Flatpak Flathub Integration
#########################################################

log_header "Configuring Flatpak & Flathub"

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

#########################################################
# Secure Third-Party Installers (AppMan / AM)
#########################################################

log_header "Installing AppMan (AM) via Secure Script Execution"

secure_install_script "AM-INSTALLER" "https://raw.githubusercontent.com/ivan-hc/AM/main/AM-INSTALLER"

#########################################################
# Desktop Environment Specific Adjustments & Hostname
#########################################################

log_header "Applying Desktop Environment Settings & Hostname"

sudo hostnamectl set-hostname "$HOSTNAME"

if [ "$DESKTOP" = "$DESKTOP_GNOME" ]; then
    log_info "Configuring GNOME user directories and window button layout..."
    xdg-user-dirs-update --set DOWNLOAD "$DOWNLOADS_DIR"
    gsettings set org.gnome.desktop.wm.preferences button-layout "appmenu:minimize,maximize,close"
fi

#########################################################
# Application Package Installation (DNF & Flatpak)
#########################################################

log_header "Installing Application Packages"

sudo dnf install -y gh fzf fastfetch

if [ "$SETUP_TYPE" = "$SETUP_TYPE_FULL" ]; then
    sudo dnf install -y ksystemlog htop keepassxc timeshift qbittorrent vlc
fi

if [ "$DESKTOP" = "$DESKTOP_GNOME" ]; then
    sudo dnf install -y gnome-tweaks
    [ "$SETUP_TYPE" = "$SETUP_TYPE_FULL" ] && sudo dnf install -y gparted liferea quiterss
elif [ "$DESKTOP" = "$DESKTOP_KDE" ]; then
    # Note: Use pre-installed partitionmanager (KDE Partition Manager) instead of gparted.
    # Note: Use virt-manager instead of GNOME boxes for KVM/QEMU virtualization on KDE.
    sudo dnf install -y kde-gtk-config plasma-browser-integration kasts kalarm kbackup
fi

flatpak install -y flathub org.signal.Signal com.github.tchx84.Flatseal it.mijorus.gearlever

if [ "$SETUP_TYPE" = "$SETUP_TYPE_FULL" ]; then
    flatpak install -y flathub com.rtosta.zapzap org.telegram.desktop chat.simplex.simplex network.loki.Session \
                               io.freetubeapp.FreeTube dev.fredol.open-tv com.spotify.Client app.grayjay.Grayjay \
                               app.organicmaps.desktop im.riot.Riot org.localsend.localsend_app com.sindresorhus.Caprine \
                               com.super_productivity.SuperProductivity
fi

if [ "$DESKTOP" = "$DESKTOP_GNOME" ]; then
    flatpak install -y flathub com.mattjakeman.ExtensionManager
    [ "$SETUP_TYPE" = "$SETUP_TYPE_FULL" ] && flatpak install -y flathub org.gnome.Podcasts de.haeckerfelix.Shortwave
elif [ "$DESKTOP" = "$DESKTOP_KDE" ]; then
    [ "$SETUP_TYPE" = "$SETUP_TYPE_FULL" ] && flatpak install -y flathub io.github.amit9838.mousam
fi

#########################################################
# Flatpak Permissions & Sandboxing Overrides
#########################################################

log_header "Setting Flatpak Security & Secret Store Overrides"

if [ "$DESKTOP" = "$DESKTOP_GNOME" ] || [ "$DESKTOP" = "$DESKTOP_COSMIC" ]; then
    sudo flatpak override --env=SIGNAL_PASSWORD_STORE=gnome-libsecret org.signal.Signal
elif [ "$DESKTOP" = "$DESKTOP_KDE" ]; then
    sudo flatpak override --env=SIGNAL_PASSWORD_STORE=kwallet6 org.signal.Signal
    if [ "$SETUP_TYPE" = "$SETUP_TYPE_FULL" ]; then
        flatpak override --user im.riot.Riot --talk-name=org.kde.kwalletd6 --talk-name=org.freedesktop.secrets
        sudo flatpak override --user --filesystem=home com.rtosta.zapzap
    fi
fi

#########################################################
# External Common & Security Modular Scriptlets
#########################################################

log_header "Executing Modular Configuration Scriptlets"

sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/vscodium.sh"
sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/librewolf_browser.sh"
sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/brave_browser.sh"
sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/tor_browser.sh"
sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/fonts.sh"

sudo sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/zsh.sh"
sudo sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/omz.sh"
sudo sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/cli_tools.sh"
sudo sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/starship.sh"
sudo sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/atuin.sh"

sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/alacritty_orig.sh"
sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/bleachbit.sh"
[ -n "$GIT_USER_EMAIL" ] && sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/git.sh" "$GIT_USER_EMAIL"
sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/syncthing.sh"
sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/avahi.sh"
sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/mpv.sh"

# NextDNS configuration handled via dns.sh module
sudo sh "${SYSUPDATE_CODE_BASE_DIR}/linux/security/dns.sh" "$NEXTDNS_ID" "$NEXTDNS_DEVICE_ID"
sh "${SYSUPDATE_CODE_BASE_DIR}/linux/security/proton_ag.sh" --setup-type "$SETUP_TYPE" --desktop "$DESKTOP"

# Security & ClamAV configuration
sudo DEBUG=1 sh "${SYSUPDATE_CODE_BASE_DIR}/linux/security/clamav.sh" \
    --pc-type="${PC_TYPE}" \
    --real-user="${REAL_USER}" \
    --torrent-client="${HAS_TORRENT_CLIENT}" \
    --kodi="${HAS_KODI}" \
    --backup-dir="${SCRIPT_BACKUPS_DIR}" \
    --timestamp="${FILENAME_TIMESTAMP}"

sh "${SYSUPDATE_CODE_BASE_DIR}/linux/security/hosts.sh"

if [ "$SETUP_TYPE" = "$SETUP_TYPE_FULL" ]; then
    sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/bash.sh"
    sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/aws.sh"
    sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/zoom.sh"
    sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/jetbrains_toolbox.sh"
    sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/docker.sh"
    sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/neovim_lazyvim.sh"
    sh "${SYSUPDATE_CODE_BASE_DIR}/linux/security/i2p.sh"

    sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/tmux_zellij.sh"
    sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/yazi.sh"
    sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/mullvad_browser.sh"

    [ "$DESKTOP" = "$DESKTOP_GNOME" ] && sh "${SYSUPDATE_CODE_BASE_DIR}/linux/common/gsconnect_kde_connect.sh"
fi

sudo sh "${SYSUPDATE_CODE_BASE_DIR}/linux/security/firewalld.sh" \
    --filename-timestamp "$FILENAME_TIMESTAMP" \
    --script-backups-dir "$SCRIPT_BACKUPS_DIR" \
    --sysupdate-code-base-dir "$SYSUPDATE_CODE_BASE_DIR" \
    --home-lan-subnet "$HOME_LAN_SUBNET" \
    --privacy-level "$PRIVACY_LEVEL" \
    --desktop "$DESKTOP" \
    --home-dir "$HOME_DIR" \
    --real-user "$REAL_USER"

#########################################################
# Environment Tools Configuration (FZF & Brave Execution)
#########################################################

log_header "Configuring Environment Tooling & Variables"

# FZF Optimal Options Configuration
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"

# Dynamic Brave Browser Executable Route Resolution
if rpm -q brave-browser &>/dev/null; then
    export CHROME_EXECUTABLE="/usr/bin/brave-browser"
    log_info "Brave Browser resolved to DNF path."
elif flatpak list --app | grep -q com.brave.Browser; then
    export CHROME_EXECUTABLE="flatpak run com.brave.Browser"
    log_info "Brave Browser resolved to Flatpak path."
fi

#########################################################
# MIME Defaults Setup
#########################################################

log_header "Setting System Default Applications (MIME)"

xdg-mime default codium.desktop text/plain
if [ -f /usr/share/applications/brave-browser.desktop ]; then
    xdg-mime default brave-browser.desktop x-scheme-handler/http x-scheme-handler/https
    xdg-mime default brave-browser.desktop x-scheme-handler/about
fi
xdg-mime default vlc.desktop video/mp4 video/x-matroska audio/mpeg
xdg-mime default org.kde.okular.desktop application/pdf
xdg-mime default thunderbird.desktop x-scheme-handler/mailto

#########################################################
# Startup Applications & Scheduled Tasks (Cron & Akregator)
#########################################################

log_header "Configuring Startup Applications & Maintenance Tasks"

# Akregator background autostart setup for KDE Full profile
if [ "$DESKTOP" = "$DESKTOP_KDE" ] && [ "$SETUP_TYPE" = "$SETUP_TYPE_FULL" ]; then
    log_info "Configuring Akregator background autostart..."
    mkdir -p "${HOME_DIR}/.config/autostart"
    cat <<EOL > "${HOME_DIR}/.config/autostart/akregator-hidden.desktop"
[Desktop Entry]
Type=Application
Name=Akregator (Background)
Exec=sh -c "/usr/bin/akregator >/dev/null 2>&1 & sleep 5 && qdbus org.kde.akregator /akregator /akregator/MainWindow_1 hide"
X-GNOME-Autostart-enabled=true
StartupNotify=false
Terminal=false
EOL
fi

# Setup weekly maintenance cron job for unused flatpak pruning and dnf cache cleaning
(crontab -l 2>/dev/null; echo "0 3 * * 0 flatpak uninstall --unused -y && dnf clean all") | crontab - || true
log_success "Scheduled weekly maintenance cron task registered."

#########################################################
# System Update Verification & Completion
#########################################################

log_header "Executing Final Package Refresh"

sudo dnf update -y && flatpak update -y

log_success "Fedora setup completed successfully!"