#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Jellyfin Server Setup Script for Fedora 44 KDE
# Targets: nbMain (Dell OptiPlex 790) and nbAcer (Acer Aspire TC-885)
#
# Features:
#   - Automatic hardware detection and VAAPI optimization per machine
#   - SELinux custom policy for GPU access (keeps SELinux enforcing)
#   - Firewalld rules for Jellyfin + DLNA + Chromecast discovery
#   - ACL-based media permissions (no ownership changes)
#   - tmpfs transcode cache on high-RAM machines
#   - btrfs no-CoW on cache directories
#   - Jellyfin Desktop client (Flatpak) for local playback
#   - NextDNS device ID variable for reference
#   - Video-only setup (no music libraries)
#
# Run on EACH machine individually:
#   sudo bash jellyfin-setup.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────── USER CONFIGURATION ───────────────────────────────
# Fill in your NextDNS device ID for this machine (leave empty to skip —
# Jellyfin server uses system DNS; this is for your reference/tracking)
NEXTDNS_DEVICE_ID=""

# Media root (relative to real user's home). Both machines use ~/nb/Videos
MEDIA_SUBPATH="nb/Videos"

# Whether to install the Jellyfin Desktop client (Flatpak) on this machine
INSTALL_DESKTOP_CLIENT=true

# Jellyfin web UI port (default 8096)
JELLYFIN_PORT=8096
# ───────────────────────────────────────────────────────────────────────────────

# Colors
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
CYN='\033[0;36m'
NC='\033[0m'

# Logging helpers
log()  { echo -e "${GRN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YLW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR ]${NC} $1" >&2; }
inf()  { echo -e "${BLU}[INFO]${NC} $1"; }

# ═════════════════════════════════════════════════════════════════════════════
# PRE-FLIGHT CHECKS
# ═════════════════════════════════════════════════════════════════════════════

if [[ $EUID -ne 0 ]]; then
  err "This script must be run as root. Try: sudo bash $0"
  exit 1
fi

# Determine the real (non-root) user — used for media path and permissions
REAL_USER="${SUDO_USER:-$(getent passwd 1000 | cut -d: -f1)}"
if [[ -z "${REAL_USER}" ]]; then
  err "Could not determine the real user. Set REAL_USER manually in the script."
  exit 1
fi
REAL_HOME=$(getent passwd "${REAL_USER}" | cut -d: -f6)
MEDIA_ROOT="${REAL_HOME}/${MEDIA_SUBPATH}"

HOSTNAME=$(hostname)
SUPPORTED_HOSTS=("nbMain" "nbAcer")
if [[ ! " ${SUPPORTED_HOSTS[*]} " =~ " ${HOSTNAME} " ]]; then
  warn "Hostname '${HOSTNAME}' is not in supported list {nbMain, nbAcer}. Proceeding anyway."
fi

# ═════════════════════════════════════════════════════════════════════════════
# HARDWARE DETECTION
# Detects CPU, RAM, GPU, and determines the correct VAAPI driver + transcode
# strategy. This is the brain of the script — it adapts to each machine.
# ═════════════════════════════════════════════════════════════════════════════

detect_hardware() {
  inf "Detecting hardware on ${HOSTNAME}…"

  CPU_MODEL=$(lscpu | awk -F': ' '/Model name/ {print $2}' | head -1)
  CPU_CORES=$(nproc)

  # Total RAM in GB (rounded down)
  TOTAL_RAM_GB=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 1024 ))

  # GPU detection via lspci
  GPU_LINE=$(lspci -nn | grep -iE 'vga|3d|display' | head -1 || echo "Unknown")

  HAS_INTEL_GPU=false
  GPU_GEN=""
  VAAPI_DRIVER=""
  RENDER_DEVICE=""
  VAAPI_CAPABLE=false

  if echo "${GPU_LINE}" | grep -qi "intel"; then
    HAS_INTEL_GPU=true

    # Intel GPU generation mapping by CPU model number:
    #   -2xxx  = Sandy Bridge  (Gen 6)  → i965 driver, H.264 decode only
    #   -3xxx  = Ivy Bridge    (Gen 7)  → i965 driver, H.264 decode only
    #   -4xxx  = Haswell       (Gen 7.5) → i965 driver, H.264 decode+encode
    #   -5xxx  = Broadwell     (Gen 8)  → iHD  driver
    #   -6xxx  = Skylake       (Gen 9)  → iHD  driver
    #   -7xxx  = Kaby Lake      (Gen 9.5)→ iHD  driver
    #   -8xxx  = Coffee Lake   (Gen 9.5)→ iHD  driver, full decode+encode
    #   -9xxx  = Coffee Lake R (Gen 9.5)→ iHD  driver
    #   10xxx+ = Comet Lake / Ice Lake  → iHD  driver
    if   echo "${CPU_MODEL}" | grep -qE '-[2-3][0-9]{3}'; then
      GPU_GEN="legacy"     # Sandy/Ivy Bridge — ancient QSV
      VAAPI_DRIVER="i965"
      VAAPI_CAPABLE=true    # technically, but very limited
    elif echo "${CPU_MODEL}" | grep -qE '-[4-5][0-9]{3}'; then
      GPU_GEN="haswell"
      VAAPI_DRIVER="i965"
      VAAPI_CAPABLE=true
    else
      GPU_GEN="modern"      # Gen 8+ — Broadwell and newer
      VAAPI_DRIVER="iHD"
      VAAPI_CAPABLE=true
    fi
  fi

  # Check for the VAAPI render device node
  if [[ -e /dev/dri/renderD128 ]]; then
    RENDER_DEVICE="/dev/dri/renderD128"
  fi

  # Determine transcode tmpfs size based on RAM
  TRANSCODE_TMPFS_SIZE=""
  if   [[ ${TOTAL_RAM_GB} -ge 16 ]]; then
    TRANSCODE_TMPFS_SIZE="4G"
  elif [[ ${TOTAL_RAM_GB} -ge 8 ]]; then
    TRANSCODE_TMPFS_SIZE="2G"
  fi
  # If < 8 GB RAM, leave TRANSCODE_TMPFS_SIZE empty → use disk

  # Print hardware summary table
  echo ""
  printf "${CYN}┌─────────────────────── Hardware Summary ───────────────────────┐${NC}\n"
  printf "${CYN}│${NC} Hostname        %-45s ${CYN}│${NC}\n" "${HOSTNAME}"
  printf "${CYN}│${NC} CPU             %-45s ${CYN}│${NC}\n" "${CPU_MODEL} (${CPU_CORES} cores)"
  printf "${CYN}│${NC} RAM             %-45s ${CYN}│${NC}\n" "${TOTAL_RAM_GB} GB"
  printf "${CYN}│${NC} GPU             %-45s ${CYN}│${NC}\n" "$(echo ${GPU_LINE} | cut -c1-45)"
  printf "${CYN}│${NC} Intel GPU       %-45s ${CYN}│${NC}\n" "${HAS_INTEL_GPU}"
  printf "${CYN}│${NC} GPU Gen         %-45s ${CYN}│${NC}\n" "${GPU_GEN:-N/A}"
  printf "${CYN}│${NC} VAAPI Driver    %-45s ${CYN}│${NC}\n" "${VAAPI_DRIVER:-N/A}"
  printf "${CYN}│${NC} Render Device   %-45s ${CYN}│${NC}\n" "${RENDER_DEVICE:-N/A}"
  printf "${CYN}│${NC} VAAPI Capable    %-45s ${CYN}│${NC}\n" "${VAAPI_CAPABLE}"
  printf "${CYN}│${NC} Transcode tmpfs  %-45s ${CYN}│${NC}\n" "${TRANSCODE_TMPFS_SIZE:-disk-based}"
  printf "${CYN}│${NC} Media Root       %-45s ${CYN}│${NC}\n" "${MEDIA_ROOT}"
  printf "${CYN}└────────────────────────────────────────────────────────────────┘${NC}\n"
  echo ""

  # Warn about Sandy Bridge limitations
  if [[ "${GPU_GEN}" == "legacy" ]]; then
    warn "Sandy Bridge / Ivy Bridge detected — VAAPI support is limited to"
    warn "H.264 decode only. No hardware encoding. Most content will use CPU transcoding."
    warn "Stick to direct-play-optimized media (H.264, AAC, ≤1080p) to avoid transcoding."
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# RPM FUSION + PACKAGE INSTALLATION
# Jellyfin on Fedora comes from RPM Fusion Free. The `jellyfin` meta-package
# pulls in jellyfin-server, jellyfin-web, jellyfin-ffmpeg, and jellyfin-firewalld.
# ═════════════════════════════════════════════════════════════════════════════

enable_rpmfusion() {
  log "Enabling RPM Fusion repositories…"

  local fedora_ver
  fedora_ver=$(rpm -E %fedora)

  if ! dnf repolist --enabled | grep -q "rpmfusion-free"; then
    dnf install -y \
      "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm"
  fi

  if ! dnf repolist --enabled | grep -q "rpmfusion-nonfree"; then
    dnf install -y \
      "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm"
  fi

  # Fedora ships ffmpeg-free by default; swap for full ffmpeg from RPM Fusion
  # (needed for broad codec support in Jellyfin's ffmpeg pipeline)
  if rpm -q ffmpeg-free &>/dev/null; then
    inf "Swapping ffmpeg-free → full ffmpeg (RPM Fusion)…"
    dnf swap -y ffmpeg-free ffmpeg --allowerasing
  fi

  log "RPM Fusion ready."
}

install_packages() {
  log "Installing Jellyfin and dependencies…"

  # Jellyfin meta-package: pulls server, web, ffmpeg, firewalld rules
  dnf install -y jellyfin

  # VAAPI drivers — install BOTH so the loader picks the right one:
  #   libva-intel-driver  → i965 for Gen 6–7.5 (Sandy Bridge through Haswell)
  #   intel-media-driver  → iHD  for Gen 8+ (Broadwell and newer)
  dnf install -y libva-intel-driver intel-media-driver libva-utils

  # Mesa DRI drivers (fallback software rendering)
  dnf install -y mesa-dri-drivers

  # SELinux policy development tools (for building the VAAPI policy module)
  dnf install -y checkpolicy policycoreutils-devel policycoreutils-python-utils

  # ACL tools (for granting Jellyfin read access without changing ownership)
  dnf install -y acl

  log "Packages installed."
}

# ═════════════════════════════════════════════════════════════════════════════
# SELinux POLICY FOR VAAPI
# Fedora runs SELinux in enforcing mode by default. The jellyfin_t domain is
# NOT allowed to open /dev/dri/renderD128 by default, so hardware acceleration
# silently fails. We create a minimal policy module to grant this access
# WITHOUT disabling SELinux or setting permissive mode.
# ═════════════════════════════════════════════════════════════════════════════

configure_selinux() {
  log "Configuring SELinux policy for VAAPI access…"

  if ! command -v getenforce &>/dev/null; then
    warn "SELinux not available. Skipping policy."
    return
  fi

  if [[ "$(getenforce)" != "Enforcing" ]]; then
    warn "SELinux is not in Enforcing mode ($(getenforce)). Policy module will be installed anyway."
  fi

  # Ensure /dev/dri nodes have the correct SELinux label
  # (they should by default, but enforce it)
  semanage fcontext -a -t dev_dri_t '/dev/dri(/.*)?' 2>/dev/null || true
  restorecon -R /dev/dri 2>/dev/null || true

  # Build the policy module in a temp directory
  local poldir
  poldir=$(mktemp -d)
  trap "rm -rf ${poldir}" RETURN

  cat > "${poldir}/jellyfin_vaapi.te" << 'TE'
module jellyfin_vaapi 1.0;

require {
    type jellyfin_t;
    type dev_dri_t;
    class chr_file { read write ioctl map open getattr };
}

# Allow Jellyfin to open and use the VAAPI render device for
# hardware-accelerated video decoding/encoding via /dev/dri/renderD128
allow jellyfin_t dev_dri_t:chr_file { read write ioctl map open getattr };
TE

  inf "Compiling SELinux policy module…"
  checkmodule -M -m -o "${poldir}/jellyfin_vaapi.mod" "${poldir}/jellyfin_vaapi.te"
  semodule_package -o "${poldir}/jellyfin_vaapi.pp" -m "${poldir}/jellyfin_vaapi.mod"

  inf "Installing SELinux policy module…"
  semodule -i "${poldir}/jellyfin_vaapi.pp"

  log "SELinux VAAPI policy installed (SELinux stays Enforcing)."
}

# ═════════════════════════════════════════════════════════════════════════════
# USER PERMISSIONS & MEDIA ACCESS
# Jellyfin runs as the `jellyfin` system user. Your media lives in
# ~/nb/Videos owned by your regular user. We use POSIX ACLs to grant
# jellyfin read+traverse access WITHOUT changing file ownership.
#
# Permission strategy:
#   /home/$USER         → jellyfin gets execute-only (traverse, no listing)
#   /home/$USER/nb      → jellyfin gets execute-only (traverse, no listing)
#   /home/$USER/nb/Vid  → jellyfin gets read+execute recursively (rX)
#   New files in Videos → default ACL grants jellyfin rX automatically
# ═════════════════════════════════════════════════════════════════════════════

configure_permissions() {
  log "Configuring Jellyfin user permissions…"

  # Add jellyfin to the render group — required for /dev/dri/renderD128 access
  usermod -aG render jellyfin
  inf "Added jellyfin user to 'render' group"

  # Add jellyfin to the video group — for /dev/dri/card0 if needed
  usermod -aG video jellyfin
  inf "Added jellyfin user to 'video' group"

  # ── Create media directory scaffold ──
  log "Creating media directory structure at ${MEDIA_ROOT}…"
  mkdir -p "${MEDIA_ROOT}/Movies/English"
  mkdir -p "${MEDIA_ROOT}/Movies/Hindi"
  mkdir -p "${MEDIA_ROOT}/Movies/Marathi"
  mkdir -p "${MEDIA_ROOT}/Series"

  # Ensure the regular user owns the media tree
  chown -R "${REAL_USER}:${REAL_USER}" "${MEDIA_ROOT}"

  # ── Grant Jellyfin traverse access to parent directories ──
  # `x` only (no `r`) means Jellyfin can navigate THROUGH the directory
  # but CANNOT list its contents — protects privacy of your home dir.
  local parent_dir
  for parent_dir in "${REAL_HOME}" "${REAL_HOME}/nb"; do
    if [[ -d "${parent_dir}" ]]; then
      setfacl -m u:jellyfin:x "${parent_dir}"
      inf "ACL: jellyfin can traverse ${parent_dir}"
    fi
  done

  # ── Grant Jellyfin read+traverse on the media tree ──
  # `rX` = read + execute-only-on-directories (capital X — don't set
  # execute bit on regular files, only directories)
  setfacl -R -m u:jellyfin:rX "${MEDIA_ROOT}"
  # Default ACL: any NEW files created in Videos automatically inherit
  # jellyfin read access — so when you add new media, Jellyfin sees it
  setfacl -R -d -m u:jellyfin:rX "${MEDIA_ROOT}"
  inf "ACL: jellyfin has recursive read+traverse on ${MEDIA_ROOT}"

  log "Permissions configured."
}

# ═════════════════════════════════════════════════════════════════════════════
# TRANSCODE STORAGE OPTIMIZATION
# Jellyfin creates temporary transcode segments when a client can't
# direct-play a file. These segments are small, short-lived, and written/
# deleted rapidly — perfect for tmpfs (RAM-backed filesystem).
#
# Strategy:
#   ≥16 GB RAM → 4 GB tmpfs for transcode directory
#   ≥8  GB RAM → 2 GB tmpfs
#   <8  GB RAM → disk-based (apply btrfs no-CoW if applicable)
#
# If using disk on btrfs, we disable Copy-on-Write on the transcode
# directory because CoW overhead is wasteful for ephemeral files.
# ═════════════════════════════════════════════════════════════════════════════

configure_transcode_storage() {
  log "Configuring transcode storage…"

  local transcode_dir="/var/cache/jellyfin/transcodes"
  local cache_dir="/var/cache/jellyfin"

  mkdir -p "${transcode_dir}"
  chown -R jellyfin:jellyfin "${cache_dir}"
  chmod 755 "${cache_dir}"

  local root_fs
  root_fs=$(findmnt -no FSTYPE / 2>/dev/null || echo "unknown")

  if [[ -n "${TRANSCODE_TMPFS_SIZE}" ]]; then
    # ── tmpfs approach (high RAM) ──
    inf "Using ${TRANSCODE_TMPFS_SIZE} tmpfs for transcode cache (RAM: ${TOTAL_RAM_GB} GB)"

    local jellyfin_uid jellyfin_gid
    jellyfin_uid=$(id -u jellyfin)
    jellyfin_gid=$(id -g jellyfin)

    # Add fstab entry if not already present
    if ! grep -q "${transcode_dir}" /etc/fstab 2>/dev/null; then
      echo "# Jellyfin transcode cache (RAM-backed tmpfs)" >> /etc/fstab
      echo "tmpfs ${transcode_dir} tmpfs defaults,size=${TRANSCODE_TMPFS_SIZE},uid=${jellyfin_uid},gid=${jellyfin_gid},mode=0755 0 0" >> /etc/fstab
      inf "Added tmpfs entry to /etc/fstab"
    fi

    # Mount it now
    mount "${transcode_dir}" 2>/dev/null || true
    chown jellyfin:jellyfin "${transcode_dir}"

  else
    # ── Disk-based approach (low RAM) ──
    warn "RAM < 8 GB — using disk for transcode cache"
    chown jellyfin:jellyfin "${transcode_dir}"

    # Apply btrfs no-CoW if root is btrfs
    if [[ "${root_fs}" == "btrfs" ]]; then
      inf "Root is btrfs — disabling Copy-on-Write on transcode directory…"
      chattr +C "${transcode_dir}" 2>/dev/null && \
        inf "CoW disabled on ${transcode_dir}" || \
        warn "Could not disable CoW (directory may already contain files)"
    fi
  fi

  # Also disable CoW on the general cache directory if on btrfs
  # (metadata images, album art, etc. — no benefit from CoW)
  if [[ "${root_fs}" == "btrfs" ]] && [[ -d "${cache_dir}" ]]; then
    chattr +C "${cache_dir}" 2>/dev/null || true
  fi

  log "Transcode storage configured."
}

# ═════════════════════════════════════════════════════════════════════════════
# FIREWALLD CONFIGURATION
# Opens ports for:
#   8096/tcp  — Jellyfin web UI (HTTP)
#   8920/tcp  — Jellyfin web UI (HTTPS, for future use)
#   7359/udp  — Jellyfin client auto-discovery (clients find the server)
#   1900/udp  — DLNA/SSDP discovery (VLC, Kodi, smart TVs, Chromecast)
#
# Also allows SSDP multicast traffic (239.255.255.250:1900) which is
# required for DLNA discovery to work through firewalld.
#
# The jellyfin-firewalld package (pulled in by the jellyfin meta-package)
# already defines a firewalld service. We use it if available, and also
# add the multicast rule manually.
# ═════════════════════════════════════════════════════════════════════════════

configure_firewalld() {
  log "Configuring firewalld…"

  if ! systemctl is-active firewalld &>/dev/null; then
    warn "Firewalld is not running. Starting it…"
    systemctl enable --now firewalld
    sleep 2
  fi

  # Try the jellyfin firewalld service first (installed by jellyfin-firewalld)
  if firewall-cmd --info-service=jellyfin &>/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=jellyfin
    inf "Added firewalld service: jellyfin"
  else
    # Fallback: open ports manually
    warn "jellyfin firewalld service not found. Opening ports manually…"
    firewall-cmd --permanent --add-port=${JELLYFIN_PORT}/tcp   # Web UI HTTP
    firewall-cmd --permanent --add-port=8920/tcp              # Web UI HTTPS (future)
    firewall-cmd --permanent --add-port=7359/udp              # Client auto-discovery
    firewall-cmd --permanent --add-port=1900/udp              # DLNA/SSDP
    inf "Opened ports: ${JELLYFIN_PORT}/tcp, 8920/tcp, 7359/udp, 1900/udp"
  fi

  # Allow SSDP multicast for DLNA discovery
  # SSDP uses 239.255.255.250:1900 for device announcement
  firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 \
    -d 239.255.255.250/32 -p udp --dport 1900 -j ACCEPT 2>/dev/null || true

  # Also allow responses to multicast queries from local subnet
  firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 \
    -s 224.0.0.0/4 -p udp --dport 1900 -j ACCEPT 2>/dev/null || true

  firewall-cmd --reload
  log "Firewalld configured."
}

# ═════════════════════════════════════════════════════════════════════════════
# SYSTEMD OVERRIDE — VAAPI DRIVER ENVIRONMENT VARIABLE
# Tells the VA-API loader which driver to use. Without this, Jellyfin's
# ffmpeg might try the wrong driver and fail silently.
#   Sandy Bridge / Ivy Bridge / Haswell → i965
#   Broadwell and newer                → iHD
# ═════════════════════════════════════════════════════════════════════════════

configure_systemd_override() {
  log "Configuring systemd override for VAAPI driver…"

  local override_dir="/etc/systemd/system/jellyfin.service.d"
  mkdir -p "${override_dir}"

  if [[ -n "${VAAPI_DRIVER}" ]]; then
    cat > "${override_dir}/override.conf" << EOF
# ── Jellyfin systemd override ──
# Sets the VAAPI driver based on detected Intel GPU generation.
# Generated by jellyfin-setup.sh on ${HOSTNAME}

[Service]
# VA-API driver selection:
#   i965 → Intel Gen 6–7.5 (Sandy Bridge, Ivy Bridge, Haswell)
#   iHD  → Intel Gen 8+ (Broadwell, Skylake, Kaby Lake, Coffee Lake, etc.)
Environment="LIBVA_DRIVER_NAME=${VAAPI_DRIVER}"

# Ensure Jellyfin can access the render device
# (also handled via render group + SELinux policy, but belt-and-suspenders)
EOF
    inf "VAAPI driver set to: ${VAAPI_DRIVER}"
  else
    warn "No VAAPI driver detected. Hardware acceleration will be CPU-only."
  fi

  systemctl daemon-reload
  log "Systemd override configured."
}

# ═════════════════════════════════════════════════════════════════════════════
# JELLYFIN DESKTOP CLIENT (Flatpak)
# Installs the official Jellyfin Desktop client from Flathub.
# This is a Qt WebEngine + libmpv based client that provides native
# playback on Linux with hardware decoding support.
#
# Note: The older org.jellyfin.JellyfinMediaPlayer is deprecated.
#       The current package is org.jellyfin.JellyfinDesktop.
# ═════════════════════════════════════════════════════════════════════════════

install_desktop_client() {
  if [[ "${INSTALL_DESKTOP_CLIENT}" != "true" ]]; then
    inf "Skipping Jellyfin Desktop client (INSTALL_DESKTOP_CLIENT=false)"
    return
  fi

  log "Installing Jellyfin Desktop client (Flatpak)…"

  # Ensure flatpak is installed
  if ! command -v flatpak &>/dev/null; then
    dnf install -y flatpak
  fi

  # Add Flathub repository
  if ! flatpak remotes --system 2>/dev/null | grep -q "flathub"; then
    flatpak remote-add --if-not-exists flathub \
      https://flathub.org/repo/flathub.flatpakrepo
  fi

  # Remove the deprecated Jellyfin Media Player if present
  if flatpak list --system 2>/dev/null | grep -q "org.jellyfin.JellyfinMediaPlayer"; then
    inf "Removing deprecated org.jellyfin.JellyfinMediaPlayer…"
    flatpak uninstall -y --system org.jellyfin.JellyfinMediaPlayer 2>/dev/null || true
  fi

  # Install Jellyfin Desktop
  if ! flatpak list --system 2>/dev/null | grep -q "org.jellyfin.JellyfinDesktop"; then
    flatpak install -y --system flathub org.jellyfin.JellyfinDesktop
    inf "Jellyfin Desktop installed."
  else
    inf "Jellyfin Desktop already installed."
  fi

  log "Desktop client ready."
}

# ═════════════════════════════════════════════════════════════════════════════
# START JELLYFIN SERVICE
# ═════════════════════════════════════════════════════════════════════════════

start_jellyfin() {
  log "Starting Jellyfin service…"

  systemctl enable --now jellyfin
  sleep 3

  if systemctl is-active jellyfin &>/dev/null; then
    log "Jellyfin is running ✓"
  else
    err "Jellyfin failed to start!"
    err "Check logs: journalctl -u jellyfin -e"
    exit 1
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# POST-INSTALL SUMMARY
# Prints a comprehensive summary of what was configured, the URLs to
# access the server, and step-by-step instructions for the initial
# Jellyfin web wizard + dashboard configuration.
# ═════════════════════════════════════════════════════════════════════════════

print_summary() {
  local ip_addr
  ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "${ip_addr}" ]] && ip_addr="<your-ip>"

  local hw_accel_display="CPU only"
  if [[ "${VAAPI_CAPABLE}" == "true" ]]; then
    hw_accel_display="VAAPI (${VAAPI_DRIVER})"
  fi

  # Determine codec checkboxes guidance based on GPU gen
  local codec_guidance=""
  if [[ "${GPU_GEN}" == "legacy" ]]; then
    codec_guidance="✗ H.264 decode only (no encoding). Check ONLY 'H.264'. Leave encoding UNCHECKED."
  elif [[ "${GPU_GEN}" == "haswell" ]]; then
    codec_guidance="✓ H.264 decode + encode. Check 'H.264' and enable hardware encoding."
  else
    codec_guidance="✓ Full support. Check: H.264, HEVC, VP9, MPEG2. Enable hardware encoding."
  fi

  cat << EOF

${GRN}╔════════════════════════════════════════════════════════════════════╗${NC}
${GRN}║           Jellyfin Server Setup Complete!                         ║${NC}
${GRN}╚════════════════════════════════════════════════════════════════════╝${NC}

${CYN}── Server Info ──${NC}
  Host:           ${HOSTNAME}
  Web UI:         http://${ip_addr}:${JELLYFIN_PORT}
  Media Root:     ${MEDIA_ROOT}
  Hardware Accel: ${hw_accel_display}
  VAAPI Driver:  ${VAAPI_DRIVER:-N/A}
  Render Device: ${RENDER_DEVICE:-N/A}
  Transcode:     ${TRANSCODE_TMPFS_SIZE:+tmpfs ${TRANSCODE_TMPFS_SIZE}}${TRANSCODE_TMPFS_SIZE:-disk-based}
  NextDNS ID:     ${NEXTDNS_DEVICE_ID:-(not set)}

${CYN}── Media Libraries ──${NC}
  Movies/English  → ${MEDIA_ROOT}/Movies/English
  Movies/Hindi     → ${MEDIA_ROOT}/Movies/Hindi
  Movies/Marathi   → ${MEDIA_ROOT}/Movies/Marathi
  Series           → ${MEDIA_ROOT}/Series

${CYN}── Network Ports (Firewalld) ──${NC}
  ${JELLYFIN_PORT}/tcp   Jellyfin Web UI (HTTP)
  8920/tcp   Jellyfin Web UI (HTTPS — future)
  7359/udp   Client auto-discovery
  1900/udp   DLNA / SSDP discovery

${CYN}── Installed Client ──${NC}
  Jellyfin Desktop:  Flatpak (org.jellyfin.JellyfinDesktop)

${YLW}═══════════════════════ NEXT STEPS ═══════════════════════${NC}

${GRN}1. INITIAL SETUP WIZARD${NC}
   Open:  http://${ip_addr}:${JELLYFIN_PORT}
   • Choose your preferred language
   • Create your admin username + password
   • Skip adding media libraries (do it manually — see step 3)
   • Finish the wizard

${GRN}2. CONFIGURE HARDWARE ACCELERATION${NC}
   Dashboard → Playback → Transcoding:
   • Hardware Acceleration: VAAPI
   • VA-API Device: ${RENDER_DEVICE:-/dev/dri/renderD128}
   • Codec guidance for your hardware:
     ${codec_guidance}
   ${GPU_GEN:+}Click Save at the top.

${GRN}3. ADD MEDIA LIBRARIES${NC}
   Dashboard → Libraries → Add Media Library:
   ┌─────────────┬───────────┬──────────────────────────────────┐
   │ Content Type│ Name      │ Folder                            │
   ├─────────────┼───────────┼──────────────────────────────────┤
   │ Movies      │ Movies    │ ${MEDIA_ROOT}/Movies             │
   │ Shows       │ Series    │ ${MEDIA_ROOT}/Series             │
   └─────────────┴───────────┴──────────────────────────────────┘
   Note: Movies/English, Hindi, Marathi are subfolders — Jellyfin
   treats them as folders within the Movies library. You can also
   add each language as a separate library if you prefer filtering.

${GRN}4. ENABLE DLNA (for VLC, Kodi, Chromecast discovery)${NC}
   Dashboard → Devices → DLNA → Enable
   (Or: Dashboard → Plugins → DLNA → Enable)
   This allows DLNA-capable devices to discover and browse Jellyfin
   on your local network.

${GRN}5. CHROMECAST${NC}
   • Open the Jellyfin web UI in a Chromium-based browser (Brave, LibreWolf)
   • Click the cast icon in the playback controls
   • Chromecast streams directly from the Jellyfin server URL
   • No additional setup needed — works on local network

${GRN}6. ANDROID CLIENTS${NC}
   ┌────────────────────────────┬──────────────────────────────┐
   │ App                        │ Source                       │
   ├────────────────────────────┼──────────────────────────────┤
   │ Jellyfin (official)        │ Play Store / F-Droid         │
   │ Jellyfin for Android TV    │ Play Store (if using ATV)    │
   │ GrayJay (Jellyfin plugin)  │ GrayJay app → Add Source     │
   └────────────────────────────┴──────────────────────────────┘
   Connect to: http://${ip_addr}:${JELLYFIN_PORT}

${YLW}═══════════════════════ VERIFICATION ══════════════════════${NC}

  VAAPI test:
    sudo -u jellyfin LIBVA_DRIVER_NAME=${VAAPI_DRIVER:-iHD} vainfo

  Service status:
    systemctl status jellyfin

  Live logs:
    journalctl -u jellyfin -f

  Check VAAPI is being used (play something, then check logs):
    journalctl -u jellyfin -f | grep -i "vaapi\|hwaccel\|qsv"

${YLW}═══════════════════════ NOTES ════════════════════════════${NC}

  • This machine (${HOSTNAME}) is one of TWO independent Jellyfin servers.
    Each has its own library, users, and configuration.
    Point your clients to whichever server has the content you want.

  ${GPU_GEN:+• ${GPU_GEN^} GPU detected:}${GPU_GEN:+ }
EOF

  if [[ "${GPU_GEN}" == "legacy" ]]; then
    echo "    Sandy Bridge VAAPI is very limited (H.264 decode only, no encode)."
    echo "    To avoid transcoding, encode your media as H.264 + AAC in an MP4"
    echo "    container. Use this HandBrake preset:"
    echo "      Format: MP4 | Video: H.264 (x264) | Audio: AAC | Subtitles: burn or SRT"
    echo "    Direct-play avoids transcoding entirely — both servers can handle it."
  elif [[ "${GPU_GEN}" == "modern" ]]; then
    echo "    Coffee Lake+ has excellent VAAPI support (H.264, HEVC, VP9 decode +"
    echo "    H.264/HEVC encode). Hardware transcoding will work well here."
  fi

  cat << EOF

  • NextDNS: Jellyfin server uses system DNS (systemd-resolved).
    Per-app NextDNS device IDs aren't feasible without network namespaces.
    Your system-level NextDNS configuration applies to all Jellyfin traffic.
    Device ID for reference: ${NEXTDNS_DEVICE_ID:-(not set)}

  • To repeat this setup on the other machine:
    sudo bash jellyfin-setup.sh
    (The script auto-detects hardware and adapts)

  • When you eventually move Jellyfin to nbServer:
    The nbServer AMD A4-5300B has NO usable VAAPI (Radeon HD 7480D).
    Expect CPU-only transcoding. Optimize for direct play.

EOF
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═════════════════════════════════════════════════════════════════════════════

main() {
  echo ""
  printf "${CYN}╔══════════════════════════════════════════════════════════════════╗${NC}\n"
  printf "${CYN}║   Jellyfin Server Setup for Fedora 44 KDE                       ║${NC}\n"
  printf "${CYN}║   Video-only | VAAPI | SELinux Enforcing | DLNA | Chromecast     ║${NC}\n"
  printf "${CYN}╚══════════════════════════════════════════════════════════════════╝${NC}\n"
  echo ""

  detect_hardware
  enable_rpmfusion
  install_packages
  configure_selinux
  configure_permissions
  configure_transcode_storage
  configure_firewalld
  configure_systemd_override
  install_desktop_client
  start_jellyfin
  print_summary
}

main "$@"



# Key decisions explained

# Why both VAAPI drivers installed: libva-intel-driver (i965) covers Sandy Bridge on nbMain; intel-media-driver (iHD) covers Coffee Lake on nbAcer. Installing both avoids issues — the LIBVA_DRIVER_NAME env var in the systemd override tells the loader which to use. The script auto-detects the CPU model number and maps it to the correct driver.

# SELinux stays enforcing: Instead of the common (bad) advice to set SELinux permissive, the script compiles and loads a minimal policy module granting jellyfin_t access to /dev/dri/renderD128. This is the proper Fedora way.

# ACLs instead of ownership changes: Your media at ~/nb/Videos stays owned by you. Jellyfin gets traverse-only (x) on parent directories (can't list your home contents) and rX on the Videos tree (read files + traverse directories). Default ACLs ensure new files you add are automatically readable by Jellyfin.

# tmpfs transcode: nbMain (31GB RAM) gets a 4GB tmpfs; nbAcer (7.6GB RAM) gets a 2GB tmpfs. Transcode segments are tiny, ephemeral, and write-heavy — perfect for RAM. Jellyfin cleans them up automatically.

# Two independent servers: No clustering, no shared database. Each machine serves its own content. Point your Jellyfin Desktop or Android client to whichever server has what you want to watch. If you ever want a unified view, Jellyfin's "Merge Libraries" feature (via a plugin) can combine them, but that's a future decision.

# Sandy Bridge reality check: nbMain's i5-2400 has ancient QSV (H.264 decode only, no encode). The script sets VAAPI on it, but don't expect miracles. If you encode your media as H.264 + AAC in MP4 containers, clients will direct-play and transcoding becomes a non-issue. This is the most practical advice for nbMain. nbAcer's i5-8400 with UHD 630 is excellent — full H.264/HEVC/VP9 decode and H.264/HEVC encode.

# NextDNS: Included as a variable for your reference, but per-app device IDs aren't practical for the Jellyfin server process without network namespaces. Your system-level NextDNS (systemd-resolved) applies to all Jellyfin traffic.

# Chromecast: Works via the Jellyfin web UI cast button in any Chromium-based browser (Brave, LibreWolf). The Chromecast fetches the stream directly from the Jellyfin server URL on your local network. No DLNA needed for casting — DLNA is for devices like smart TVs and VLC that use UPnP/SSDP discovery.

# Android: Install the official Jellyfin app from F-Droid or Play Store, point it to http://<server-ip>:8096. GrayJay also has a Jellyfin plugin if you prefer its interface. Both servers will appear separately — add each as a separate server in the app.

# Run the script on each machine with sudo bash jellyfin-setup.sh. It auto-detects everything.

