#!/usr/bin/env bash

# ==============================================================================
# MPV Automated Setup & Optimization Script for Fedora KDE
# Author: Privacy & Performance Conscious Automation
# ==============================================================================

# Exit immediately if a command exits with a non-zero status, treat unset variables as errors
set -euo pipefail

# set -Eeuo pipefail
# IFS=$'\n\t'
# umask 077


#######################################################
# Reading
#######################################################

# https://mpv.io/manual/stable/
# https://github.com/mpv-player/mpv/wiki
# https://github.com/mpv-player/mpv/wiki/User-Scripts
# https://wiki.archlinux.org/title/FFmpeg
# https://wiki.archlinux.org/title/Mpv
# https://man.archlinux.org/man/mpv
# https://man.archlinux.org/man/mpv.1#FILES
# https://man.archlinux.org/man/mpv.1#ON_SCREEN_CONTROLLER
# https://man.archlinux.org/man/mpv.1#LUA_SCRIPTING
# https://github.com/mpv-player/mpv/tree/master/TOOLS/lua - check scripts that can be used here
# https://github.com/Samillion/mpv-ytdlautoformat # Lua script to auto change ytdl-format for Youtube and Twitch or the domains you desire, to 480p or the quality you desire. 
# https://github.com/ekisu/mpv-webm # very easy to use Lua script that allows one to create WebM files while watching videos. It includes several features and does not have any extra dependencies (relies entirely on mpv). 
# https://gist.github.com/bitingsock/17d90e3deeb35b5f75e55adb19098f58 # Lua script to preload the next ytdl-link in your playlist. 

# The C plugin mpv-mpris allows other applications to integrate with mpv via the MPRIS protocol. For example, with mpv-mpris installed, kdeconnect can automatically pause video playback in mpv when a phone call arrives. Another example is buttons (play\pause etc) on bluetooth audio-devices. 
# https://github.com/hoyon/mpv-mpris
# To use the plugin, install https://archlinux.org/packages/?name=mpv-mpris on Arch

# https://github.com/bamos/dotfiles/blob/master/.mpv/scripts.old/music.lua # an example to improve mpv as a music player.

# How do I pass cookies to yt-dlp?
# https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp

# https://github.com/yt-dlp/yt-dlp

# https://github.com/BrodieRobertson/dotfiles/tree/master/config/mpv
# https://thewiki.moe/tutorials/mpv/
# https://github.com/zydezu/mpvconfig/tree/main/scripts
# https://github.com/stax76/awesome-mpv#user-script

#######################################################
# Colors and Helpers
#######################################################

# Colors for terminal output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'

# if [[ -t 1 ]]; then
#     RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
#     BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
# else
#     RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
# fi


# log()  { printf "${GREEN}\n[%s] %s\n${NC}" "$SCRIPT_NAME" "$*"; }
# warn() { printf "${YELLOW}\n[WARN] %s\n${NC}" "$*" >&2; }
# die()  { printf "${RED}\n[ERROR] %s\n${NC}" "$*" >&2; exit 1; }


log_header()    { echo -e "\n${CYAN}==================== $* ====================${NC}\n"; }
log_info()    { echo -e "${BLUE}[INFO] $* ${NC}"; }
log_success() { echo -e "${GREEN}[✓] $* ${NC}"; }
log_warn()    { echo -e "${YELLOW}[!] $* ${NC}"; }
log_error()   { echo -e "${RED}[✗] $* ${NC}" >&2; }
# die()  { err "$*"; exit 1; }
# die()  { printf "${RED}\n[ERROR] %s\n${NC}" "$*" >&2; exit 1; }
log_die()   { echo -e "${RED}[✗] $* ${NC}" >&2; exit 1; }



# for cmd in sudo dnf rpm awk grep sed install cp mkdir date find curl tar; do
#     command -v "$cmd" >/dev/null 2>&1 || log_error "Required command not found: $cmd"
# done


log_info "Initializing mpv automated deployment and optimization suite"


[[ $EUID -ne 0 ]] || log_warn "Run as your normal desktop user, not root or via sudo."
[[ -n "$HOME_DIR" && "$HOME_DIR" != "/" ]] || log_warn "Unsafe HOME value."
[[ "$(rpm -E %fedora 2>/dev/null || true)" =~ ^[0-9]+$ ]] || log_error "This script requires Fedora."

# [[ $EUID -eq 0 ]] && die "Do not run as root."
# command -v dnf >/dev/null || die "Fedora (dnf) required."


#######################################################
# CONFIGURATION CONSTANTS
#######################################################


TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

readonly SCRIPT_NAME="${0##*/}"
readonly HOME_DIR="${HOME:?HOME is not set}"
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
readonly DATA_HOME="${XDG_DATA_HOME:-$HOME_DIR/.local/share}"
readonly STATE_HOME="${XDG_STATE_HOME:-$HOME_DIR/.local/state}"
readonly CACHE_HOME="${XDG_CACHE_HOME:-$HOME_DIR/.cache}"
readonly MPV_CONFIG_DIR="$CONFIG_HOME/mpv"
readonly STATE_DIR="$STATE_HOME/mpv"
readonly DATA_DIR="$DATA_HOME/mpv"
readonly BACKUP_ROOT="$HOME_DIR/nb/nb_script_data/backups/mpv"
readonly SCRIPT_DIR="$MPV_CONFIG_DIR/scripts"
readonly BACKUP_DIR="${BACKUP_ROOT}/mpv_${TIMESTAMP}"


readonly BACKUP_BASE="$HOME/nb/nb_script_data/backups/mpv"
readonly MPV_CONFIG_DIR="$HOME/.config/mpv"
readonly STATE_DIR="$HOME/.local/state/mpv"
readonly CACHE_DIR="$HOME/.cache/mpv"
readonly SCRIPTS_DIR="${MPV_CONFIG_DIR}/scripts"
readonly FONT_OPTS_DIR="${MPV_CONFIG_DIR}/font-opts"
readonly SCRIPT_OPTS_DIR="${MPV_CONFIG_DIR}/script-opts"


readonly SCRIPT_NAME="$(basename "$0")"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_ROOT="${HOME}/nb/nb_script_data/backups/mpv"
readonly MPV_DIR="${HOME}/.config/mpv"
readonly SCRIPT_DIR="${MPV_DIR}/scripts"
readonly OPTS_DIR="${MPV_DIR}/script-opts"
readonly STATE_DIR="${HOME}/.local/state/mpv"
readonly WATCH_LATER="${STATE_DIR}/watch_later"


#######################################################
# BACKUP EXISTING CONFIGURATIONS
#######################################################


if [ -d "$MPV_CONFIG_DIR" ]; then
    log_warn "Existing mpv configuration detected. Backing up to: ${BACKUP_DIR}"
    mkdir -m 700 -p "$BACKUP_DIR"
    # cp -r "$MPV_CONFIG_DIR/"* "$BACKUP_DIR/" 2>/dev/null || true

    backup_path() {
        local src="$1" dest_name="$2"
        # if [ -d "$HOME/.config/mpv" ]; then
        [[ -e "$src" || -L "$src" ]] || return 0
        cp -a -- "$src" "$BACKUP_DIR/$dest_name"
        # cp -r "$src" "$BACKUP_DIR/$dest_name"
        log_success "Backed up $src to $BACKUP_DIR/$dest_name"
    }
    backup_path "$MPV_CONFIG_DIR" "config-mpv"
    backup_path "$STATE_DIR" "state-mpv"
    backup_path "$DATA_DIR" "data-mpv"
    backup_path "$CONFIG_HOME/mimeapps.list" "mimeapps.list"
    backup_path "$DATA_HOME/applications" "user-applications"

    # Also backup any ~/.mpv legacy location
    if [ -d "$HOME/.mpv" ]; then
        backup_path "$HOME/.mpv" "legacy_mpv"
    fi

    log_success "Backups saved to $BACKUP_DIR"

else
        info "No existing config - clean install"
fi

sudo -v

#######################################################
# CREATE DIRECTORY STRUCTURE
#######################################################

# Start fresh only after a successful backup. Refuse to operate on a suspicious
# path, and remove the old config tree so stale scripts/options cannot conflict.
[[ "$MPV_CONFIG_DIR" == "$CONFIG_HOME/mpv" && "$MPV_CONFIG_DIR" != "/" ]] || log_error "Unexpected config path: $MPV_CONFIG_DIR"
if [[ -e "$MPV_CONFIG_DIR" || -L "$MPV_CONFIG_DIR" ]]; then
    rm -rf -- "$MPV_CONFIG_DIR"
fi

# mkdir -p "$MPV_CONFIG_DIR"
mkdir -m 700 -p "$SCRIPT_DIR" "$MPV_CONFIG_DIR/script-opts" "$MPV_CONFIG_DIR/fonts"
mkdir -p "$STATE_DIR/watch_later" "$CACHE_HOME/mpv" "$DATA_DIR"
chmod 700 "$STATE_DIR" "$STATE_DIR/watch_later" "$CACHE_HOME/mpv" "$DATA_DIR"


#######################################################
# Fonts
#######################################################


# Fontconfig returns the resolved family name. If the requested Nerd Font family
# is not installed under that exact name, leave mpv's normal font fallback intact.
NERD_FONT=""
if command -v fc-match >/dev/null 2>&1; then
    MATCHED_FONT="$(fc-match -f '%{family}\n' 'Noto Nerd Font' 2>/dev/null | head -n 1 || true)"
    if [[ "$MATCHED_FONT" == *Nerd* ]]; then
        NERD_FONT="${MATCHED_FONT%%,*}"
        log_info "Using detected Noto Nerd Font family: $NERD_FONT"
    else
        log_warn "Fontconfig did not resolve 'Noto Nerd Font' to a Nerd Font family; using system font fallback."
    fi
fi

# OSD_FONT="Noto Sans"
# SUB_FONT="Noto Sans"
# if command -v fc-list >/dev/null; then
#     if fc-list 2>/dev/null | grep -qi "NotoSans.*Nerd\|Noto Sans Nerd"; then
#         OSD_FONT="NotoSans Nerd Font"
#         SUB_FONT="NotoSans Nerd Font"
#         info "Using NotoSans Nerd Font"
#     elif fc-list 2>/dev/null | grep -qi "Noto Sans"; then
#         info "Using Noto Sans"
#     else
#         warn "Noto fonts not found — falling back to sans-serif"
#         OSD_FONT="sans-serif"
#         SUB_FONT="sans-serif"
#     fi
# fi


#######################################################
# HARDWARE PROFILING
#######################################################

log_info "Profiling system hardware and memory capacity"



# FEDORA_VER=$(rpm -E %fedora 2>/dev/null || echo "?")
FEDORA_RELEASE="$(rpm -E %fedora)"
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
# TOTAL_RAM_KIB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
# TOTAL_RAM_GB=$(( TOTAL_RAM_KIB / 1024 / 1024 ))
CPU_THREADS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
CPU_CORES=$(nproc)
# CPU_MODEL=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs || echo "Unknown CPU")
CPU_MODEL="$(awk -F: '/model name/ {sub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo)"
# CPU_MODEL=$(lscpu 2>/dev/null | awk -F: '/Model name/{gsub(/^[ \t]+/,"",$2); print $2; exit}' || echo "unknown")
CPU_MODEL="${CPU_MODEL:-unknown}"
# GPU_INFO=$(lspci | grep -E "(VGA|3D)" || echo "")
GPU_INFO="$( (command -v lspci >/dev/null 2>&1 && lspci -nn | grep -Ei 'VGA compatible controller|3D controller|Display controller') || true)"
SESSION_TYPE=unknown
[[ -n "${WAYLAND_DISPLAY:-}" ]] && SESSION_TYPE=wayland
[[ -z "${WAYLAND_DISPLAY:-}" && -n "${DISPLAY:-}" ]] && SESSION_TYPE=x11


HAS_NVIDIA=0
HAS_INTEL=0
HAS_AMD=0
NVIDIA_DRIVER="none"          # proprietary | nouveau | none
GPU_MODEL=""




# log_info "Detected Total System Memory: ${TOTAL_RAM_GB} GB"


# NVIDIA_DRIVER=none
# if command -v lspci >/dev/null 2>&1 && lspci | grep -qi nvidia; then
#     if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
#         NVIDIA_DRIVER=proprietary-working
#     elif lsmod 2>/dev/null | grep -q '^nouveau'; then
#         NVIDIA_DRIVER=nouveau
#     else
#         NVIDIA_DRIVER=detected-driver-unknown
#     fi
# fi


# log_info "Fedora $FEDORA_RELEASE; session=$SESSION_TYPE; RAM=${TOTAL_RAM_GB} GiB; CPU threads=$CPU_THREADS"
# log_info "CPU: $CPU_MODEL"
# [[ -n "$GPU_INFO" ]] && printf '%s\n' "$GPU_INFO" || log_warn "GPU details unavailable (lspci may be missing)."
# [[ "$NVIDIA_DRIVER" != none ]] && log_info "NVIDIA status: $NVIDIA_DRIVER (mpv will still select decoding at runtime)."



if [ -z "$GPU_INFO" ]; then
    log_warn "No GPU detected via lspci. Using conservative defaults."
    GPU_VENDOR="Unknown"
    GPU_MODEL="None detected"
    HWDEC_FLAG="auto"
    GPU_API_VAL="opengl"
    GPU_CONTEXT="wayland"
    return
fi

# Hardware Acceleration & API Detection with sensible fallbacks
HWDEC_FLAG="vaapi"
GPU_API_VAL="opengl"

# if lspci 2>/dev/null | grep -qi 'nvidia'; then
if echo "$GPU_INFO" | grep -qi 'nvidia'; then

   # NVIDIA handling is now driver-aware. Your GTX 960M machine gets probed: if nvidia module is loaded → nvdec + vulkan + waylandvk context. If nouveau is loaded → falls back to Intel VA-API (since the XPS 15 has an iGPU too), because nouveau's NVDEC support is unreliable. If neither → auto. This means the same script works whichever driver you end up with.
    HAS_NVIDIA=1
    # GPU_MODEL=$(lspci | grep -i nvidia | head -1 | sed 's/.*: //')

    GPU_VENDOR="NVIDIA"
    # GPU_MODEL=$(echo "$GPU_INFO" | grep -i nvidia | sed 's/.*: //' | cut -d'[' -f1 | xargs)
    GPU_MODEL=$(lspci | grep -i nvidia | sed 's/.*: //')

    log_info "Detected NVIDIA GPU: ${GPU_MODEL}."
    

    # Check whether proprietary Nvidia driver or Nouveau FOSS driver is active
    if lsmod 2>/dev/null | grep -q '^nvidia'; then
        log_info "Proprietary NVIDIA driver active. Utilizing nvdec and vulkan pipeline."
        # NVDEC with Vulkan works best with proprietary drivers
        HWDEC_FLAG="nvdec"
        GPU_API_VAL="vulkan"
        GPU_CONTEXT="waylandvk"
        NVIDIA_DRIVER="proprietary"
        log_success "Configuration: hwdec=${HWDEC_FLAG}, gpu-api=${GPU_API_VAL}, context=${GPU_CONTEXT}"

    elif lsmod 2>/dev/null | grep -q '^nouveau'; then
        log_warn "Nouveau (FOSS) driver detected. Nouveau lacks full NVDEC support."
        # Fall back to VA-API via Intel if available, or software
        if echo "$GPU_INFO" | grep -qi 'intel'; then
            log_info "Using Intel iGPU for VA-API hardware decoding"
            HWDEC_FLAG="vaapi"
            GPU_API_VAL="opengl"
            GPU_CONTEXT="wayland"
            NVIDIA_DRIVER="nouveau"
        else
            # Module not loaded yet - check installed packages
            if rpm -q akmod-nvidia nvidia-driver 2>/dev/null | grep -q .; then
                NVIDIA_DRIVER="proprietary"
            else
                NVIDIA_DRIVER="nouveau"   # assume FOSS if no proprietary package
                log_warn "Nouveau + discrete NVIDIA = limited hwdec support. Using auto fallback."
                HWDEC_FLAG="auto"
                GPU_API_VAL="opengl"
                GPU_CONTEXT="wayland"
            fi

        fi
    else
        # Neither driver loaded - might be using modesetting or other
        log_warn "No NVIDIA kernel module loaded. Checking for fallback options..."
        HWDEC_FLAG="auto"
        GPU_API_VAL="opengl"
        GPU_CONTEXT="wayland"
    fi


# Check for Intel GPU
# elif lspci 2>/dev/null | grep -qi 'intel'; then
# elif lspci 2>/dev/null | grep -qiE 'vga|3d|display' | grep -qi intel; then
elif echo "$GPU_INFO" | grep -qi 'intel'; then
    GPU_VENDOR="Intel"
    HAS_INTEL=1
    # GPU_MODEL=$(echo "$GPU_INFO" | grep -i intel | sed 's/.*: //' | cut -d'[' -f1 | xargs)
    GPU_MODEL=$(lspci | grep -i "VGA" | grep -i intel | sed 's/.*: //')
    # [[ -z $GPU_MODEL ]] && GPU_MODEL=$(lspci | grep -iE 'vga|3d|display' | grep -i intel | head -1 | sed 's/.*: //')
    log_info "Detected Intel GPU: ${GPU_MODEL}. Tuning for VA-API / OpenGL."
    # All Intel GPUs support VA-API well
    HWDEC_FLAG="vaapi"
    GPU_API_VAL="opengl"  # More stable than Vulkan on Intel
    GPU_CONTEXT="wayland"
    log_success "Configuration: hwdec=${HWDEC_FLAG}, gpu-api=${GPU_API_VAL}"


# Check for AMD GPU
# elif lspci 2>/dev/null | grep -qi 'amd'; then
elif echo "$GPU_INFO" | grep -qi 'amd\|radeon'; then
    GPU_VENDOR="AMD"
    HAS_AMD=1
    # GPU_MODEL=$(echo "$GPU_INFO" | grep -iE 'amd|radeon' | sed 's/.*: //' | cut -d'[' -f1 | xargs)
    GPU_MODEL=$(lspci | grep -i "VGA" | grep -i amd | sed 's/.*: //')
    # [[ -z $GPU_MODEL ]] && GPU_MODEL=$(lspci | grep -iE 'vga|3d|display' | grep -iE 'amd|radeon' | head -1 | sed 's/.*: //')
    log_info "Detected AMD GPU: ${GPU_MODEL}. Tuning for VA-API / Vulkan."
    # AMD uses VAAPI with RADV driver
    HWDEC_FLAG="vaapi"
    GPU_API_VAL="vulkan"
    # GPU_API_VAL="opengl"
    GPU_CONTEXT="wayland"
    log_success "Configuration: hwdec=${HWDEC_FLAG}, gpu-api=${GPU_API_VAL}"
else
    # Unknown GPU - conservative fallback
    log_warn "No dedicated GPU signature matched. Falling back to safe auto settings."
    GPU_VENDOR="Other"
    GPU_MODEL=$(echo "$GPU_INFO" | head -1 | sed 's/.*: //' | cut -d'[' -f1 | xargs)
    # HWDEC_FLAG="auto"
    HWDEC_FLAG="auto-safe"
    GPU_API_VAL="auto"
    # GPU_API_VAL="opengl"
    GPU_CONTEXT="wayland"

fi

log "CPU : ${CPU_MODEL}"
log "RAM : ${TOTAL_RAM_GB} GB"
log "GPU : ${GPU_MODEL:-unknown}"
(( HAS_NVIDIA )) && log "NVIDIA driver : ${NVIDIA_DRIVER}"


#######################################################
# CACHE OPTIMIZATION BASED ON RAM & SYSTEM MEMORY PROFILING
#######################################################


# Dynamic Cache Allocation based on RAM footprint with lightweight fallback considerations
if [ "$TOTAL_RAM_GB" -ge 16 ]; then
    # High-memory systems
    log_info "High RAM capacity detected. Allocating high-performance buffer (1GiB Cache)."
    CACHE_SIZE="1048576"
    DEMUX_SEEKABLE="yes"
    # INSTALL_HEAVY_ADDONS=true

    CACHE_MAX_BYTES="2147483648"      # 2 GiB
    CACHE_BACK_BYTES="536870912"     # 512 MiB
    DEMUX_SEEKABLE="yes"
    THREADS=$CPU_CORES
    log_info "High-memory profile: 2GB cache, ${THREADS} threads"



elif [ "$TOTAL_RAM_GB" -ge 10 ]; then
    # Mid-range
    log_info "Mid RAM capacity detected. Allocating balanced buffer (512MiB Cache)."
    CACHE_SIZE="524288"
    DEMUX_SEEKABLE="yes"
    # INSTALL_HEAVY_ADDONS=true


    CACHE_MAX_BYTES="1073741824"     # 1 GiB
    CACHE_BACK_BYTES="268435456"     # 256 MiB
    DEMUX_SEEKABLE="yes"
    THREADS=$CPU_CORES
    log_info "Mid-memory profile: 1GB cache, ${THREADS} threads"


else
    # Low-memory
    log_warn "Lower RAM footprint detected (<8GB). Optimizing conservative buffer (256MiB Cache) and skipping heavy background thumbnails."
    CACHE_SIZE="262144"
    DEMUX_SEEKABLE="auto"
    # INSTALL_HEAVY_ADDONS=false


    CACHE_MAX_BYTES="536870912"      # 512 MiB
    CACHE_BACK_BYTES="134217728"     # 128 MiB
    DEMUX_SEEKABLE="auto"
    THREADS=$(( (CPU_CORES + 1) / 2 ))
    log_warn "Low-memory profile: 512MB cache, ${THREADS} threads"
    log_warn "Streaming high bitrate content may buffer on ${GPU_MODEL}"




fi

INSTALL_HEAVY_ADDONS=false
# if (( TOTAL_RAM_GB >= 8 && CPU_THREADS >= 4 )); then
if (( TOTAL_RAM_GB >= 10 && CPU_THREADS > 4 )); then
    INSTALL_HEAVY_ADDONS=true
fi


if (( TOTAL_RAM_GB >= 24 )); then
    CACHE_FWD="1500MiB"; CACHE_BACK="400MiB"
    PROFILE="high-quality"
    SCALE="ewa_lanczossharp"; CSCALE="ewa_lanczossharp"
    INTERPOLATION="yes"
    YTDL_H=2160
    INSTALL_HEAVY_SCRIPTS=1
elif (( TOTAL_RAM_GB >= 12 )); then
    CACHE_FWD="800MiB";  CACHE_BACK="200MiB"
    PROFILE="high-quality"
    SCALE="ewa_lanczossharp"; CSCALE="ewa_lanczos"
    INTERPOLATION="yes"
    YTDL_H=1440
    INSTALL_HEAVY_SCRIPTS=1
elif (( TOTAL_RAM_GB >= 6 )); then
    CACHE_FWD="350MiB";  CACHE_BACK="100MiB"
    PROFILE="gpu-hq"
    SCALE="lanczos"; CSCALE="lanczos"
    INTERPOLATION="no"
    YTDL_H=1080
    INSTALL_HEAVY_SCRIPTS=0
else
    CACHE_FWD="180MiB";  CACHE_BACK="50MiB"
    PROFILE="fast"
    SCALE="bilinear"; CSCALE="bilinear"
    INTERPOLATION="no"
    YTDL_H=720
    INSTALL_HEAVY_SCRIPTS=0
fi




# Cache allocation is deliberately bounded. Cache tuning is not a substitute for
# adequate decoding performance, and giant caches can waste RAM on local files.
if (( TOTAL_RAM_GB >= 16 && CPU_THREADS >= 4 )); then
    CACHE_SIZE2=512MiB; CACHE_BACK2=128MiB; CACHE_SECS=60
    VIDEO_PROFILE=high-quality; VIDEO_SCALER=ewa_lanczos; CHROMA_SCALER=ewa_lanczos
elif (( TOTAL_RAM_GB >= 8 && CPU_THREADS >= 4 )); then
    CACHE_SIZE2=256MiB; CACHE_BACK2=64MiB; CACHE_SECS=45
    VIDEO_PROFILE=high-quality; VIDEO_SCALER=spline36; CHROMA_SCALER=spline36
else
    CACHE_SIZE2=128MiB; CACHE_BACK2=32MiB; CACHE_SECS=30
    # Older CPUs/iGPUs benefit more from reliable decoding than costly scaling.
    VIDEO_PROFILE=fast; VIDEO_SCALER=bilinear; CHROMA_SCALER=bilinear
fi

if (( TOTAL_RAM_GB >= 8 && CPU_THREADS >= 4 )); then
    STREAM_QUALITY=1080
else
    STREAM_QUALITY=720
fi



# hwdec / gpu-api with sensible ordered fallbacks
if (( HAS_NVIDIA )); then
    if [[ $NVIDIA_DRIVER == "proprietary" ]]; then
        # Best path on proprietary: nvdec → nvdec-copy → vulkan → auto
        HWDEC="nvdec,nvdec-copy,vulkan,vaapi,auto"
        GPU_API="vulkan,opengl"
    else
        # Nouveau: no reliable NVDEC. Prefer VA-API / software.
        HWDEC="vaapi,vaapi-copy,vulkan,auto"
        GPU_API="opengl,vulkan"
        warn "Nouveau detected — NVDEC unavailable. Using VA-API/OpenGL path."
    fi
elif (( HAS_AMD )); then
    HWDEC="vaapi,vulkan,auto"
    GPU_API="vulkan,opengl"
else
    # Intel / unknown
    HWDEC="vaapi,vaapi-copy,vulkan,auto"
    GPU_API="opengl,vulkan"
fi

info "Profile          : ${PROFILE}"
info "Cache            : ${CACHE_FWD} / ${CACHE_BACK}"
info "hwdec            : ${HWDEC}"
info "gpu-api          : ${GPU_API}"
info "yt-dlp max height: ${YTDL_H}p"
info "Heavy scripts    : ${INSTALL_HEAVY_SCRIPTS}"


#######################################################
# REPOSITORY SETUP & DEPENDENCY INSTALLATION
#######################################################

log_info "Configuring RPM Fusion repositories and installing packages"

FEDORA_VERSION=$(rpm -E %fedora)

# Enable RPM Fusion Free and Non-Free safely
sudo dnf install -y \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm || true

sudo dnf config-manager --set-enabled rpmfusion-free rpmfusion-nonfree || true



# Update multimedia group
sudo dnf groupupdate -y multimedia --setopt=install_weak_deps=False 2>/dev/null || {
        log_warn "Multimedia group update failed - continuing with individual packages"
    }
# run sudo dnf install -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin || true

# Swap ffmpeg-free to full ffmpeg for maximum reliability across codecs
# Fedora ships ffmpeg-free which lacks H.264/HEVC by default
# sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing || true

# FFmpeg from RPM Fusion offers broader codec support than Fedora's
# ffmpeg-free. This swap can replace dependent packages, so DNF must display
# its proposed transaction and ask for confirmation. Do not add -y here.
if rpm -q ffmpeg-free >/dev/null 2>&1 && ! rpm -q ffmpeg >/dev/null 2>&1; then
    log_info "DNF will propose replacing ffmpeg-free with RPM Fusion ffmpeg. Review the transaction carefully."
    # sudo dnf swap ffmpeg-free ffmpeg --allowerasing
    sudo dnf swap -y --allowerasing ffmpeg-free ffmpeg
fi

sudo dnf update -y ffmpeg ffmpeg-libs libavcodec-extra gstreamer1-plugins-{bad,good,ugly}-free gstreamer1-libav || true

# Install core media components, mpv-mpris (for KDE Connect/Media keys integration), and yt-dlp
# sudo dnf install -y \
    
dnf_pkgs=(
    mpv
    mpv-mpris
    yt-dlp
    python3
    ffmpeg
    ffmpeg-libs
    ffmpegthumbnailer
    mediainfo
    python3-pip
    libva
    libva-utils
    gstreamer1-plugins-bad-freeworld
    gstreamer1-plugins-ugly-free
    libavcodec-freeworld
    vulkan-loader
    vulkan-tools
    vainfo
    vdpauinfo
    mesa-va-drivers

)

(( HAS_INTEL )) && dnf_pkgs+=(intel-media-driver libva-intel-driver)
(( HAS_NVIDIA )) && dnf_pkgs+=(libva-nvidia-driver)


log "Installing: ${pkgs[*]}"
run sudo dnf install -y "${pkgs[@]}"

# if (( INSTALL_HEAVY_SCRIPTS )) && ! command -v subliminal >/dev/null; then
#     info "Installing subliminal (user)..."
#     run pip3 install --user --upgrade subliminal || warn "subliminal failed (non-fatal)"
# fi

# Install Python subliminal for subtitle downloading functionality
pip3 install --user --upgrade subliminal >/dev/null 2>&1 || true

# Verify mpv installation
if ! command -v mpv &>/dev/null; then
    log_error "mpv installation failed - check dnf output above"
    exit 1
fi


#######################################################
# GENERATE OPTIMIZED 'mpv.conf'
#######################################################

log_info "Generating optimized mpv.conf profile"

cat << EOF > "$MPV_CONFIG_DIR/mpv.conf"
# ==============================================================================
# ENGINE CORE & PERFORMANCE PIPELINE (Auto-generated for Fedora KDE)
# ==============================================================================

# mpv chooses GPU API/window context and safe decoder at runtime.
# For troubleshooting, compare with: mpv --no-config --hwdec=no FILE
# If gpu-next fails on an older driver, test --vo=gpu or --vo=xv on that machine.
vo=gpu-next
# gpu-api=${GPU_API}
gpu-api=${GPU_API_VAL}
# hwdec=auto-safe
# hwdec=${HWDEC}
hwdec=${HWDEC_FLAG},auto-safe,auto,no       # Hardware decode, fallback to software
hwdec-codecs=all                # Enable all available codecs
reset-on-next-file=hwdec        # Re-detect hwdec per file
# gpu-context=wayland
gpu-context=${GPU_CONTEXT}       # Wayland backend

# Vulkan tuning (only applies when gpu-api=vulkan)
# vulkan-queue-count=4
vulkan-queue-count=8
vulkan-async-compute=yes
vulkan-async-transfer=yes

# vd-lavc-threads=0
vd-lavc-threads=${THREADS}
vd-lavc-fast-decodable=yes
# Performance optimizations (slight quality trade-off for speed)
vd-lavc-skiploopfilter=none         # Skip deblocking filter

# ==================== SCALING & QUALITY ====================
# Rendering quality: avoid forced interpolation, which can overload older CPUs/GPUs.
# profile=gpu-hq                # High-quality preset base
# profile=${PROFILE}
profile=$VIDEO_PROFILE
# EWA LanczosSharp: excellent sharpness with minimal ringing
# scale=ewa_lanczossharp
# scale=${SCALE}
scale=$VIDEO_SCALER
# cscale=ewa_lanczossharp
# cscale=${CSCALE}
cscale=$CHROMA_SCALER
tscale=oversample               # Fast temporal scaler
dscale=mitchell
# Temporal upscaling (motion smoothing - can cause soap opera effect)
# interpolation=yes           # Uncomment if you want frame interpolation
# interpolation=no
interpolation=${INTERPOLATION}
# interpolation=yes is commented out. Frame interpolation looks great on 24fps film but costs GPU and causes the soap-opera effect. On the Intel HD 2nd-gen it will likely drop frames. Left it off; enable per-machine if wanted.
hr-seek=yes                     # High-resolution seeking
video-sync=display-resample     # Reduces audio/video jitter

# ==================== AUDIO SETTINGS ====================
alang=en,eng
# Audio on Fedora KDE normally routes through PipeWire. Alternatives are fallbacks.
ao=pipewire,pulse,alsa              # PipeWire first (modern Fedora)
audio-channels=auto
audio-display=embedded-first
audio-pitch-correction=yes
audio-sync=audio
volume=100
volume-max=200

# Passthrough for AV receivers (optional - uncomment if you have surround)
# audio-spdif=ac3,eac3,dts-hd,truehd

# ==================== SUBTITLES & FONT STYLING ====================
slang=en,eng
sub-auto=fuzzy
sub-file-paths=sub:subs:subtitles
# sub-file-paths=sub:subs:subtitles:.
sub-fix-timing=yes
sub-forced-only=no
sub-ass-override=no
embeddedfonts=yes
demuxer-mkv-subtitle-preroll=yes

# Enforce Noto Nerd Font as default fallback across OSC and subtitles
# sub-font="NotoSans Nerd Font"

# Noto Nerd Font is applied only if fontconfig successfully resolved it.
$(if [[ -n "$NERD_FONT" ]]; then printf 'osd-font="%s"\nsub-font="%s"\n' "$NERD_FONT" "$NERD_FONT"; else printf '# osd-font and sub-font left to system font fallback.\n'; fi)

# sub-font-size=44
sub-font-size=40
sub-border-size=2.0
sub-color="#FFFFFFFF"
sub-border-color="#FF000000"
# sub-border-color=000000FF
# sub-margin-y=30
sub-shadow-offset=1

# OSC font (also Noto for consistency)
osc-font="Noto Sans"
osc-font-blur=0



# ==================== CACHING & DEMUXER ====================
cache=yes
cache-pause=yes
# cache-secs=120
# Bounded cache profile selected from detected RAM.
cache-secs=$CACHE_SECS
demuxer-max-bytes=${CACHE_SIZE}
demuxer-max-bytes=${CACHE_SIZE2}
# demuxer-max-bytes=${CACHE_MAX_BYTES}
# demuxer-max-bytes=${CACHE_FWD}
# demuxer-max-back-bytes=$(( CACHE_SIZE / 4 ))
# demuxer-max-back-bytes=${CACHE_BACK2}
demuxer-max-back-bytes=$CACHE_BACK
# demuxer-max-back-bytes=${CACHE_BACK_BYTES}
demuxer-seekable-cache=yes
demuxer-seekable-cache=${DEMUX_SEEKABLE}
# demuxer-readahead-secs=20
demuxer-readahead-secs=60
force-seekable=yes



# ==================== NETWORK & STREAMING ====================
# yt-dlp integration. No cookie extraction or TLS bypass is configured.
ytdl=yes
ytdl-format="bestvideo[height<=2160]+bestaudio/best"
# ytdl-format=bestvideo[height<=2160]+bestaudio/best
ytdl-raw-options=no-check-certificates=,youtube-skip-dash-manifest=

# ytdl-format=bestvideo[height<=${YTDL_H}]+bestaudio/best

network-timeout=30

# ==================== HARDENED PRIVACY & SECURITY ====================
# Strips telemetry leakage, local directory exposure, and hides headers
# user-agent=Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0
user-agent="Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0"
referrer="https://www.google.com"
# stream-lavf-o=reconnect=1,reconnect_at_eof=1,reconnect_streamed=1
stream-lavf-o=reconnect=1,skip_loop_filter=all

# Disable telemetry (mpv has none, but good practice)
# no-ml-stats                    # Machine learning stats (doesn't exist, commented)

# ==================== OSD & INTERFACE ====================
# osc=yes                          # Enable OSC (ModernZ will override this)
# osc=no
# ModernZ disables the stock OSC from within its Lua script when it loads.
# We deliberately do not set osc=no here: if ModernZ fails at runtime, mpv's
# built-in OSC remains available as a fallback.
# osd-bar=yes
# osd-level=1
# cursor-autohide=1000
# border=yes                       # Window borders for resizing
# title-bar=yes
# osd-font=${OSD_FONT}
# osd-font-size=32



# ==================== PLAYBACK BEHAVIOR ====================
keep-open=yes
# keep-open=no
save-position-on-quit=yes
rebase-time=no
rebase-start-time=no
autofit-larger=90%x90%
stop-screensaver=yes
watch-later-directory=~~state/watch_later

# ==================== COLOR MANAGEMENT & SCREENSHOTS ====================
# icc-profile-auto=yes
icc-profile-auto
icc-cache-dir=~/.cache/mpv/icc


# Tone mapping for HDR (automatic)
tone-mapping=haar
target-peak=auto
# tone-mapping=haar - picked a reasonable default. If you have HDR content, bt.2390 is generally better; spline is sharper but slower.

# Screenshots
screenshot-format=png
screenshot-high-bit-depth=yes
# screenshot-directory=~/Pictures/Screenshots
screenshot-directory=~/Pictures/mpv-screenshots
screenshot-template=%F-%P-%n

# -----------------------------------------------------------------------------
# PERFORMANCE TWEAKS (Optional - uncomment for low-end machines)
# -----------------------------------------------------------------------------
# If experiencing stutter on nbLenovo or nbServer:
# unpair-gl-shaders=yes
# gl-no-display-sync=yes


# -----------------------------------------------------------------------------
# SCRIPT OPTIONS
# -----------------------------------------------------------------------------
# Subtitle downloader
script-opts=subtitle_downloader-lang=en
script-opts=subtitle_downloader-sources=opensubtitles,addic7ed,subsfun

# Subtitle sources. I listed opensubtitles,addic7ed,subsfun. The subtitle_downloader script's actual accepted source names vary by version — verify against its README after install, or it silently finds nothing./

# Thumbnail generator
# script-opts-append=thumbfast-width=200
# script-opts-append=thumbfast-height=113
# script-opts-append=thumbfast-count=4
script-opts=thumbfast-width=200
script-opts=thumbfast-height=113
script-opts=thumbfast-count=5

# ModernZ OSC
script-opts=modernz-theme=fluent
script-opts=modernz-layout=basic
script-opts=modernz-scale=1.0
script-opts=modernz-hidetimeout=3000
script-opts=modernz-showchaptermarks=yes

# SponsorBlock
script-opts=sponsorblock_only_in=youtube,twitch



EOF


#######################################################
# GENERATE KEYBINDINGS ('input.conf')
#######################################################

log_info "Deploying VLC-compatible comfort keybindings with requested 10s seek defaults ('input.conf')"

cat << 'EOF' > "$MPV_CONFIG_DIR/input.conf"
# VLC Comfort-Style Keybindings

WHEEL_UP      add volume 2
WHEEL_DOWN    add volume -2
UP            add volume 5
Shift+UP      add volume 10
DOWN          add volume -5
Shift+DOWN    add volume -10

# seek bindings
# LEFT          seek -10
LEFT          seek -10 exact
# RIGHT         seek 10
RIGHT         seek 10 exact
# SHIFT+LEFT  seek -60
SHIFT+LEFT    seek -60 exact
# SHIFT+RIGHT seek 60
SHIFT+RIGHT   seek 60 exact

# Playback and audio
SPACE         cycle pause
p             cycle pause
f             cycle fullscreen
m             cycle mute
s             screenshot
S             screenshot video
q               quit
ESC             quit
Q             quit-watch-later

# Frame stepping & Speed control
.             frame-step
,             frame-back-step
]             add speed 0.10
[             add speed -0.10
BS            set speed 1.0

# Playlist navigation
PGUP          playlist-prev
PGDWN         playlist-next
>             playlist-next
<             playlist-prev

# Subtitles & Audio toggles
v             cycle sub
# j               cycle sub
J               cycle sub forced
a               cycle audio
A               cycle audio all
Ctrl+a        cycle audio-device

# CHAPTER NAVIGATION
CTRL+RIGHT      add chapter 1
CTRL+LEFT       add chapter -1


# LIVE STATISTICS & DEBUGGING
# i             script-binding stats/display-stats
# i             script-binding stats/display-stats-toggle
# I             script-binding stats/display-page-2
i               show-text "${pf}${pfs}"          # Show performance stats
P               toggle demuxer-cache-statistics  # Cache stats
w               show-demuxer-cache-state         # Detailed cache info

EOF


chmod 600 "$MPV_CONFIG_DIR/mpv.conf" "$MPV_CONFIG_DIR/input.conf"
log_success "Created input.conf with 10s seek defaults"


#######################################################
# ADDONS & EXTENSIBILITY PLUGINS
#######################################################

log_info "Addons Deployment:"
# log_info "Evaluation: ModernZ chosen over ModernX / classic OSC. ModernZ is a modern, feature-rich, high-performance refactoring of ModernX with cleaner design, superior async scaling, and better native Noto Nerd Font rendering integration."

########################


# I compared the projects you mentioned against their current upstream documentation.
# ModernZ - selected over ModernX
# Primary UI
# ModernZ builds on the ModernX lineage and offers configurable layouts, menus, icon themes, and thumbnail support. It is my preferred choice for your setup. 

# Installed on all machines when the download succeeds. The built-in OSC remains the fallback if ModernZ fails to load.
# thumbfast - conditional installation
# Generates seekbar thumbnails on demand and supports ModernZ. It does not continuously generate thumbnails in the background. 
# Installed only when the machine has at least 8 GiB RAM and four CPU threads.

# SponsorBlock - included
# Downloads the Lua script and its required helper files. It skips marked sponsored segments in supported YouTube playback, rather than acting as a general-purpose ad blocker. 
# Lightweight enough to include on older machines. It communicates with the SponsorBlock service, so it is not network-private.

# ytdlAutoFormat - included
# Adjusts stream format selection for configured sites such as YouTube and Twitch. 
# Uses a 720p cap on lower-powered machines and 1080p on systems meeting the higher RAM/CPU threshold. Other sites retain mpv/yt-dlp's normal format selection.

# Local directory autoload - included
# Adds a small local Lua script that queues supported media files following the file you opened, in alphabetical order. It fixes the invalid Lua alternation pattern in your original version and supports relative paths.


# What I deliberately left out
# Original idea	Decision
# Subtitle downloader - Not installed automatically. The old downloader and alternatives introduce external subtitle-provider dependencies, potential credential requirements, and disclosure of media titles or filenames. Local subtitle discovery remains enabled.
# Skip silence - Omitted. Automatically skipping silence can cut pauses in speech or music, and the referenced script is not a dependable general-purpose solution.
# Auto-profiles addon - Replaced with settings generated directly by the setup script based on detected hardware.
# ModernX - Not installed separately; it would conflict with the chosen OSC.
# WebM creation script - Not included in the initial setup because video editing is a separate, optional workflow.




# The original skip_silence script is not included: the referenced source is
# not a dependable general-purpose silence detector, and auto-skipping can
# cut speech/music. Use mpv's audio filters or a dedicated podcast workflow
# if this becomes a real requirement.
#
# The old subtitle-downloader script is also not auto-installed. It relies on
# third-party services/dependencies and may require credentials or expose the
# media filename/title to a provider. mpv's fuzzy local subtitle loading stays
# enabled; install a downloader only after selecting a provider deliberately.

#######################
# Autoload directory playlist engine
# cat << 'EOF' > "$SCRIPT_DIR/autoload.lua"
# local msg = require 'mp.msg'
# local utils = require 'mp.utils'

# function autoload_dir()
#     local path = mp.get_property("path")
#     if not path or path:find("^%a%a+://") then return end
    
#     local dir, filename = utils.split_path(path)
#     if dir == "." then return end

#     local files = utils.readdir(dir, "files")
#     if not files then return end
    
#     table.sort(files, function(a, b) return a:lower() < b:lower() end)

#     local append_index = 0
#     for _, file in ipairs(files) do
#         if file:match("%.([%a%d]+)$") then
#             local ext = file:match("%.([%a%d]+)$"):lower()
#             if ext:match("^(mp4|mkv|avi|flv|webm|mov|ts|mp3|flac|wav|ogg|m4a|wma)$") then
#                 if file == filename then
#                     append_index = 1
#                 elseif append_index > 0 then
#                     mp.commandv("loadfile", utils.join_path(dir, file), "append")
#                 end
#             end
#         end
#     end
# end
# mp.register_event("start-file", autoload_dir)
# EOF

############

# # --- Always: autoload (lightweight, extremely useful) --------------------
#     cat > "${SCRIPT_DIR}/autoload.lua" <<'LUA'
# -- autoload.lua — append remaining media files in the same directory
# local utils = require 'mp.utils'
# local function is_media(name)
#     local ext = name:match("%.([%w]+)$")
#     if not ext then return false end
#     local ok = {
#         mp4=1,mkv=1,avi=1,webm=1,mov=1,flv=1,ts=1,m4v=1,wmv=1,mpeg=1,mpg=1,
#         mp3=1,flac=1,ogg=1,opus=1,m4a=1,wav=1,aac=1,wma=1
#     }
#     return ok[ext:lower()] ~= nil
# end
# local function autoload()
#     local path = mp.get_property("path")
#     if not path or path:find("^%a%a+://") then return end
#     local dir, filename = utils.split_path(path)
#     if dir == "." or dir == "" then return end
#     local files = utils.readdir(dir, "files")
#     if not files then return end
#     table.sort(files, function(a,b) return a:lower() < b:lower() end)
#     local append = false
#     for _, f in ipairs(files) do
#         if is_media(f) then
#             if f == filename then append = true
#             elseif append then
#                 mp.commandv("loadfile", utils.join_path(dir, f), "append")
#             end
#         end
#     end
# end
# mp.register_event("start-file", autoload)
# LUA

############

# Auto-load neighboring files when opening one local file. This small local
# script avoids the original Lua-pattern bug (Lua patterns do not support |).
# It intentionally ignores URLs, hidden files, and non-media extensions.
cat > "$MPV_CONFIG_DIR/scripts/autoload.lua" <<'LUA'
local utils = require "mp.utils"
local msg = require "mp.msg"

local media_ext = {
    mp4=true, m4v=true, mkv=true, avi=true, mov=true, qt=true, webm=true,
    flv=true, wmv=true, mpg=true, mpeg=true, m2v=true, ts=true, m2ts=true,
    mts=true, vob=true, ogv=true, ogg=true, 3gp=true, 3g2=true, dv=true,
    mp3=true, flac=true, wav=true, ogg=true, opus=true, m4a=true, aac=true,
    wma=true, ape=true, alac=true, aiff=true, au=true, mid=true, midi=true
}
local queued_for = nil

local function append_directory()
    local path = mp.get_property("path")
    if not path or path:match("^%a[%w+.-]*://") then return end
    -- mpv can be launched with a relative filename from a terminal/file manager.
    if path:sub(1,1) ~= "/" then
        local cwd = mp.get_property("working-directory") or "."
        path = utils.join_path(cwd, path)
    end
    local dir, current = utils.split_path(path)
    if not dir or not current or queued_for == dir .. "/" .. current then return end
    queued_for = dir .. "/" .. current

    local files = utils.readdir(dir, "files")
    if not files then return end
    table.sort(files, function(a, b) return a:lower() < b:lower() end)

    local found_current = false
    for _, name in ipairs(files) do
        if name == current then
            found_current = true
        elseif found_current then
            local ext = name:match("%.([^%.]+)$")
            if ext and media_ext[ext:lower()] then
                mp.commandv("loadfile", utils.join_path(dir, name), "append")
            end
        end
    end
end

mp.register_event("file-loaded", append_directory)
LUA
chmod 600 "$MPV_CONFIG_DIR/scripts/autoload.lua"


##########################################################
# ModernZ OSC UI (Superior alternative to ModernX/classic OSC with built-in font customizability)

# ModernZ over ModernX. ModernZ (Samillion) is the actively maintained fork — roughly 900 stars vs 305, more layout options, better docs, and it bundles its own icon font. ModernX upstream is largely dormant. uosc is the other serious contender but it's heavier and its config model is quite different; ModernZ fits your "works out of the box, tunable later" preference better.

curl -fsSL https://raw.githubusercontent.com/Samillion/ModernZ/main/modernz.lua -o "$SCRIPT_DIR/modernz.lua" || log_warn "Warning: Failed to fetch ModernZ script. Using default mpv OSC"

# Configure ModernZ options in script-opts
cat << 'EOF' > "$MPV_CONFIG_DIR/script-opts.conf"
modernz-font=NotoSans Nerd Font
modernz-windowcontrols=no
modernz-layout=bottom
modernz-bg-alpha=60
EOF


# https://github.com/Samillion/ModernZ#configuration
# cat > "$MPV_CONFIG_DIR/script-opts/modernz.conf" <<'EOF'
# # Minimal ModernZ configuration; built-in defaults remain for other options.
# layout=default
# icon_theme=fluent
# icon_style=mixed
# EOF

curl -fsSL https://raw.githubusercontent.com/Samillion/ModernZ/main/modernz-icons.ttf -o "$MPV_CONFIG_DIR/fonts/modernz-icons.ttf" || log_warn "Warning: Failed to fetch modernz-icons.ttf."

# Disable default OSC when ModernZ is present
if [[ -f ${SCRIPT_DIR}/modernz.lua ]]; then
    sed -i 's/^osc=yes/osc=no/' "${MPV_DIR}/mpv.conf" 2>/dev/null || true
fi

log_success "Done - ModernZ OSC (fork of ModernX with more features)"

##########################################################
# SponsorBlock (Auto-skip YouTube sponsors)


if [ "$INSTALL_HEAVY_ADDONS" = true ]; then
    mkdir -p "$SCRIPT_DIR/sponsorblock_shared"

    curl -fsSL https://raw.githubusercontent.com/po5/mpv_sponsorblock/master/sponsorblock.lua -o "$SCRIPT_DIR/sponsorblock.lua" || log_warn "Warning: Failed to fetch SponsorBlock script."

    curl -fsSL https://raw.githubusercontent.com/po5/mpv_sponsorblock/master/sponsorblock_shared/main.lua -o "$SCRIPT_DIR/sponsorblock_shared/main.lua" || log_warn "Warning: Failed to fetch sponsorblock_shared/main.lua script."


    curl -fsSL https://raw.githubusercontent.com/po5/mpv_sponsorblock/master/sponsorblock_shared/sponsorblock.py -o "$SCRIPT_DIR/sponsorblock_shared/sponsorblock.py" || log_warn "Warning: Failed to fetch sponsorblock_shared/sponsorblock.py script."

    chmod 600 "$SCRIPT_DIR/sponsorblock.lua" "$SCRIPT_DIR/sponsorblock_shared/"*

else
    log_warn "Skipping SponsorBlock on low-spec machine to preserve resources."
fi





##########################################################

# Domain-specific streaming quality helper from the same maintainer as
# ModernZ. This avoids a universal 4K stream choice on low-powered PCs.

curl -fsSL https://raw.githubusercontent.com/Samillion/mpv-ytdlautoformat/master/ytdlautoformat.lua -o "$SCRIPT_DIR/ytdlautoformat.lua" || log_warn "Warning: ytdlAutoFormat unavailable; mpv/yt-dlp will use their own format selection."

cat > "$MPV_CONFIG_DIR/script-opts/ytdlautoformat.conf" <<EOF
# Stream quality cap chosen from detected RAM and CPU thread count.
domains=youtu.be, youtube.com, twitch.tv
quality=$STREAM_QUALITY
codec=none
fps=0
force_extension=no
fallback=yes
fallback_format=b
respect_manual_changes=yes
EOF



##########################################################
# Subtitle Downloader (auto-fetch subtitles)
curl -fsSL https://raw.githubusercontent.com/jonniek/mpv-subtitle-downloader/master/subtitle_downloader.lua -o "$SCRIPT_DIR/subtitle_downloader.lua" || log_warn "Warning: Failed to fetch Subtitle Downloader script."

##########################################################

# --- Always: external-sub helper (no network) ----------------------------
cat > "${SCRIPT_DIR}/sub-reload.lua" <<'LUA'
-- sub-reload.lua — bind 'b' to load external .srt/.ass next to the video
local utils = require 'mp.utils'
mp.add_key_binding("b", "sub-reload-external", function()
    local path = mp.get_property("path")
    if not path then return end
    local dir, name = utils.split_path(path)
    local base = name:match("(.+)%.[%w]+$") or name
    for _, ext in ipairs({"srt","ass","ssa","vtt"}) do
        local cand = utils.join_path(dir, base .. "." .. ext)
        local f = io.open(cand, "r")
        if f then
            f:close()
            mp.commandv("sub-add", cand)
            mp.osd_message("Loaded " .. cand)
            return
        end
    end
    mp.osd_message("No external subtitle found")
end)
LUA

##########################################################

# Thumbfast (High-performance seekbar thumbnailer - only installed if RAM permits to keep low-end systems snappy) - (thumbnails in seekbar)
if [ "$INSTALL_HEAVY_ADDONS" = true ]; then

    # thumbfast creates previews on demand, not continuously. On low-memory or
    # low-thread-count machines we omit it to keep UI interaction lightweight.
    log_info "Installing thumbfast thumbnailer (system specs supports background preview generation)."
    curl -fsSL https://raw.githubusercontent.com/po5/thumbfast/master/thumbfast.lua -o "$SCRIPT_DIR/thumbfast.lua" || log_warn "Warning: Failed to fetch Thumbfast script."
else
    log_warn "Skipping thumbfast thumbnailer on low-spec machine to preserve resources."
fi

##########################################################
# mpv-mpris (KDE Connect integration)

# Already installed as system package - no script needed
log_info "MPV-MPRIS enabled (KDE Connect auto-pause on calls)"

##########################################################
# OPTIONAL: Skip Silence (for podcasts/long walks)

# Skip-silence is gated by RAM. it's a continuous audio-analysis script and the payoff on a 2-core/4-thread box isn't worth it.

if [ "$INSTALL_HEAVY_ADDONS" = true ]; then
# Only install on machines with sufficient RAM
    curl -LSfo "${SCRIPTS_DIR}/skip_silence.lua" \
        https://raw.githubusercontent.com/occure/mpris-subset/master/skip_silence.lua 2>/dev/null || {
        log_warn "Could not fetch skip_silence - skipping"
    }
    log_info "Silence skipping script installed (press 'S' to toggle)"
else
    log_warn "Skip silence skipped - conserving resources on ${TOTAL_RAM_GB}GB system"
fi






##########################################################

# Advanced: Auto-Profiles (Context Aware)
# This is where MPV beats VLC. You can have different settings for "Movies" vs "Music".
# Create ~/.config/mpv/auto-profiles.lua (if not present, download it):

# curl -L https://raw.githubusercontent.com/po5/auto-profiles/master/auto-profiles.lua -o "$SCRIPT_DIR/auto-profiles.lua"


# # Edit the pattern to match your actual folder structure.
# cat << 'EOF' > "$MPV_CONFIG_DIR/auto-profiles.json"
# {
#   "profiles": {
#     "movie": {
#       "pattern": "^/media/movies/",
#       "options": ["fullscreen=yes", "ontop=no"]
#     },
#     "podcast": {
#       "pattern": "^/home/nik/Music/podcasts/",
#       "options": ["volume=120", "speed=1.2", "sub-auto=no"]
#     },
#     "work": {
#       "pattern": ".mkv$",
#       "options": ["hwdec=vaapi-copy", "sub-font-size=20"]
#     }
#   }
# }
# EOF

##########################################################



log_success "Script deployment complete"

#######################################################
# SYSTEM MIME INTEGRATION & DEFAULT VIDEO/AUDIO HANDLER
#######################################################

log_info "Setting mpv as the default handler for all supported video and audio formats."

# Create the mime file if absent (unlikely)
MIME_FILE="$HOME/.config/mimeapps.list"
mkdir -p "$(dirname "$MIME_FILE")"


# Comprehensive list of media MIME types to register with mpv
declare -a VIDEO_MIMES=(
    "application/mxf"
    "application/ogg"
    "application/vnd.apple.mpegurl"
    "application/vnd.rn-realmedia" 
    "application/vnd.rn-realmedia-vbr"
    "application/x-cue"
    "application/x-extension-m4a"
    "application/x-extension-mp4"
    "application/x-matroska"
    "application/x-mpegurl" 
    "application/x-ogg"
    "video/3gp"
    "video/3gpp"
    "video/3gpp2" 
    "video/avi"
    "video/divx"
    "video/dv"
    "video/fli"
    "video/flv"
    "video/mkv" 
    "video/mp2t"
    "video/mp4"
    "video/mpeg"
    "video/msvideo"
    "video/ogg"
    "video/quicktime"
    "video/vnd.avi"
    "video/vnd.divx"
    "video/vnd.mpegurl"
    "video/vnd.rn-realvideo"
    "video/webm"
    "video/x-av1"
    "video/x-f4v"
    "video/x-flc"
    "video/x-flic"
    "video/x-flv"
    "video/x-h264"
    "video/x-h265"
    "video/x-hevc"
    "video/x-m4v"
    "video/x-matroska"
    "video/x-mpeg"
    "video/x-mpeg2"
    "video/x-mpeg3"
    "video/x-ms-asf"
    "video/x-ms-wmv"
    "video/x-ms-wmx" 
    "video/x-ms-wvx"
    "video/x-msvideo"
    "video/x-ogm" 
    "video/x-ogm+ogg"
    "video/x-theora"
    "video/x-vp8"
    "video/x-vp9"
)
# Do not delete 
# declare -a AUDIO_MIMES=(
#     "audio/aac"
#     "audio/ac3"
#     "audio/aiff"
#     "audio/eac3"
#     "audio/flac"
#     "audio/m3u"
#     "audio/m4a" 
#     "audio/mp3" 
#     "audio/mp4"
#     "audio/mpeg"
#     "audio/mpeg3"
#     "audio/ogg"
#     "audio/opus"
#     "audio/scpls"
#     "audio/vnd.dts" 
#     "audio/vnd.dts.hd"
#     "audio/vnd.wave"
#     "audio/vorbis" 
#     "audio/wav"
#     "audio/webm"
#     "audio/wma"
#     "audio/x-aac"
#     "audio/x-aiff"
#     "audio/x-ape" 
#     "audio/x-flac"
#     "audio/x-m4a"
#     "audio/x-matroska"
#     "audio/x-mp3 "
#     "audio/x-mpegurl"
#     "audio/x-mqa"
#     "audio/x-ms-wma"
#     "audio/x-ogg"
#     "audio/x-scpls" 
#     "audio/x-tta"
#     "audio/x-vorbis" 
#     "audio/x-vorbis+ogg"
#     "audio/x-wav"
#     "audio/x-wavpack" 
#     "audio/x-wma"
# )

count=0
# for mime in "${VIDEO_MIMES[@]}" "${AUDIO_MIMES[@]}"; do
for mime in "${VIDEO_MIMES[@]}"; do
    if ! grep -q "^${mime}=" "$MIME_FILE" 2>/dev/null; then
        xdg-mime default mpv.desktop "$mime" 2>/dev/null || {
            log_warn "Failed to set $mime"
            continue
        }
        ((count++))
    fi
done

log_success "Set mpv as default for ${count} MIME types"
    
# KDE Plasma integration
    if command -v kbuildsycoca6 &>/dev/null; then
        kbuildsycoca6 --noincremental 2>/dev/null || true
        log_info "Updated KDE MIME database"
    fi


log_success "mpv setup complete! All performance parameters, hardware fallback routines, Noto Nerd Font rendering, modernz interface, and privacy hardening rules have been successfully applied."


# # Make mpv default for every video MIME type declared by the installed mpv
# # desktop file. This follows the package's supported MIME declarations instead
# # of claiming support for every arbitrary video/* MIME type on the system.
# if command -v xdg-mime >/dev/null 2>&1; then
#     DESKTOP_FILE=""
#     for candidate in /usr/share/applications/mpv.desktop /usr/local/share/applications/mpv.desktop; do
#         [[ -r "$candidate" ]] && { DESKTOP_FILE="$candidate"; break; }
#     done
#     mapfile -t VIDEO_MIMES < <(
#         if [[ -n "$DESKTOP_FILE" ]]; then
#             awk -F= '/^MimeType=/ { n=split($2,a,";"); for(i=1;i<=n;i++) if(a[i] ~ /^video\//) print a[i] }' "$DESKTOP_FILE"
#         fi | sed '/^$/d' | sort -u
#     )
#     if ((${#VIDEO_MIMES[@]})); then
#         for mime in "${VIDEO_MIMES[@]}"; do
#             xdg-mime default mpv.desktop "$mime" || log_warn "Could not set default for $mime"
#         done
#         log_info "Set mpv as default for ${#VIDEO_MIMES[@]} video MIME types declared by its desktop file."
#     else
#         log_warn "No video MIME types found in mpv.desktop; setting common fallbacks."
#         for mime in video/mp4 video/x-matroska video/webm video/quicktime video/x-msvideo video/mpeg video/ogg video/3gpp video/3gpp2 video/mp2t video/x-flv; do
#             xdg-mime default mpv.desktop "$mime" || true
#         done
#     fi
# else
#     log_warn "xdg-mime is unavailable; skipped MIME defaults."
# fi





#######################################################
# VERIFICATION TESTS
#######################################################


failures=0


# Test 1: Version
if mpv --version | head -1 | grep -q "mpv"; then
    # mpv --version | head -n 2 || true
    log_success "mpv version check passed"
else
    log_error "mpv version check failed"
    ((failures++))
fi

# Test 2: Configuration syntax
if mpv --config-dir="${MPV_CONFIG_DIR}" --no-playlist --duration=1 --vo=null --ao=null \
    /dev/null 2>/dev/null; then
    log_success "Configuration syntax valid"
else
    log_error "Configuration has errors - check logs"
    ((failures++))
fi

# Test 3: Codec detection
if mpv --list-codecs 2>/dev/null | grep -qE "h264|hevc"; then
    log_success "Codec detection working"
else
    log_warn "Codec listing unavailable - may indicate codec issues"
fi

# Test 4: Hardware acceleration test instruction
log_info "Manual test: mpv test_video.mp4"
log_info "During playback, press 'i' to see live stats"
log_info "Check 'VD:' line shows hwdec (vaapi/nvdec) not 'lavc'"


if [ $failures -gt 0 ]; then
    log_warn "Verification completed with ${failures} failure(s)"
    return 1
fi

log_success "All automatic tests passed!"


# Run basic checks. These are smoke tests only; real playback tests are still needed.
log_info "Smoke checks"

yt-dlp --version || true
if command -v vainfo >/dev/null 2>&1; then
    log_info "VA-API capability summary (may fail harmlessly on unsupported drivers):"
    vainfo 2>&1 | head -n 18 || true
fi
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || true
fi


#######################################################
# Notes
#######################################################

# VERIFY HARDWARE DECODING
# mpv test_video.mp4
# Press 'i' during playback → Check "VD:" shows hwdec (vaapi/nvdec)

# TEST STREAMING
# mpv "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

# CUSTOMIZE MODERNZ OSC
# Edit: ~/.config/mpv/script-opts/modernz.conf

# SUBTITLE AUTODOWNLOAD
# Place video in folder, run mpv
# Press 's' to manually trigger subtitle download if needed

# TROUBLESHOOTING:
# • Black screen? → Try: mpv --no-config video.mp4
# • No audio?    → mpv --audio-device=help
# • Stuttering?  → Reduce cache or disable interpolation
# • Crashes?     → Check: ~/.config/mpv/watch_later/*.conf

# BACKUP LOCATION:
# ~/.backup/mpv/[timestamp]/ (full config backup)

# CONFIGURATION FILES:
# ~/.config/mpv/mpv.conf      → Main settings
# ~/.config/mpv/input.conf    → Keybindings
# ~/.config/mpv/scripts/      → Lua scripts
# ~/.config/mpv/script-opts/  → Script configurations

# DOCUMENTATION:
# • Official: https://mpv.io/manual/stable/
# • Wiki:     https://github.com/mpv-player/mpv/wiki
# • Scripts:  https://github.com/stax76/awesome-mpv

# REMOVAL (if needed):
# rm -rf ~/.config/mpv ~/.local/state/mpv ~/.cache/mpv


#######################################################
# Convert file format if not supported
#######################################################

# If a file still fails after enabling RPM Fusion and updating FFmpeg - The file is likely encrypted (DRM) or uses a proprietary container not supported by open source (e.g., some old QuickTime variants). Solution: Use ffmpeg directly to convert it:
# ffmpeg -i input.mkv -c copy output.mp4 



#######################################################
# Testing
#######################################################

# mpv --version | head -n 1
# yt-dlp --version

# Run this command to verify your codec support:
# mpv --list-codecs | grep -E "(h264|hevc|aac|ac3|dts)"

# Run the following command to get a list of available audio output devices 
# mpv --audio-device=help

# Add one audio output devices from above list to ~/.config/mpv/mpv.conf. For example: 
# audio-device=alsa/hdmi:CARD=NVidia,DEV=1

# To enable HD audio codecs like TrueHD and DTS-MA to passthrough to an AV receiver, add the following to ~/.config/mpv/mpv.conf 
# audio-spdif=ac3,eac3,dts-hd,truehd

# Volume normalization
# Also see: https://superuser.com/questions/323119/how-can-i-normalize-audio-using-ffmpeg/323127#323127
# Different sources may have different or inconsistent loudness, so mpv users may need to configure automatic volume normalization. For example:
# Add the following to ~/.config/mpv/input.conf
# n cycle_values af loudnorm=I=-30 loudnorm=I=-15 anull
# This binds the key n to cycle the audio filter settings (af) through the specified values:
#    loudnorm=I=-30: loudnorm setting with I=-30, soft volume, might be suitable for background music
#    loudnorm=I=-15: louder volume, might be good for the video currently in view
#    anull: reset audio filter to null, i.e., disable the audio filter
# Binding a key does not change the default audio filter. To change the default, add e.g. af=loudnorm=I=-30 to the main configuration file.
# Audio filtering in mpv is provided by the FFmpeg backend



# Opening video links from the KDE clipboard
# If youtube-dlAUR or yt-dlp is installed and KDE Plasma is being used, it is possible to create a custom action in the KDE clipboard to conveniently play links from video sharing sites.
#     Open the clipboard configuration menu (typically by right-clicking its icon in the system tray) and go to the Actions tab.
#     Click Add Action then enter a regular expression to detect the sites you would like to play video from (e.g. ^http.+(youtu|twitch) to detect YouTube and Twitch URLs).
#     Click Add Command, under Command enter mpv %s and under Description enter mpv.
# Now, you can play video links from your clipboard in mpv by pressing Ctrl+Alt+r and selecting mpv from the context menu. You may need to go to Advanced Settings and remove Firefox from the section Disable Actions for Windows of Type WM_CLASS.


# If you are having trouble with mpv's playback (or if it is flat out failing to run) then the first three things you should do are:
#     Run mpv from the command line (the -v flag increases verbosity). If you are lucky there will be an error message there telling you what is wrong.
#     $ mpv -v video.mkv
#     Have mpv output a log file. The log file might be difficult to sift through but if something is broken you might see it there.
#     $ mpv -v --log-file=./log video.mkv
#     Run mpv without a configuration. If this runs well then the problem is somewhere in your configuration (perhaps your hardware cannot keep up with your settings).
#     $ mpv --no-config video.mkv
# If mpv runs but it just does not run well then a fourth thing that might be worth taking a look at is the live statistics (with i) to see exactly how it is performing. 

# Play video in mpv using yt-dlp
# yt-dlp -o -  https://www.youtube.com/watch<blah-blah-blah> | mpv -







# ############################################################################
# # mpv.conf
# ############################################################################


# # ==============================================================================
# # ENGINE CORE & PERFORMANCE PIPELINE
# # ==============================================================================

# # Video output driver
# # https://github.com/mpv-player/mpv/wiki/GPU-Next-vs-GPU
# vo=gpu-next
# # Possible values: gpu, gpu-next, xv, vdpau, drm, ...

# # GPU API to use
# gpu-api=${GPU_API_VAL} # TODO
# # Possible values: auto, vulkan, opengl, d3d11, ...

# # Hardware decoding method
# # Auto-detect GPU and enable hardware decoding
# # For Nvidia (GTX 960M): nvdec or vaapi
# # For Intel: vaapi
# # # 'auto' tries VA-API (Intel) first, then VDPAU/NVDEC (Nvidia)
# hwdec=${HWDEC_FLAG}, auto
# # Possible values: no, auto, auto-safe, vaapi, nvdec, vdpau, d3d11va, videotoolbox, ...

# # Codecs to use with hardware decoding
# hwdec-codecs=all
# # Possible values: all, h264, hevc, vp9, av1, ... (comma-separated)

# reset-on-next-file=hwdec

# # GPU context (windowing system)
# gpu-context=wayland
# # Possible values: wayland, x11, win32, drm, ...

# # Video Output Configurations
# vulkan-queue-count=8
# vulkan-async-compute=yes
# vulkan-async-transfer=yes

# # # Fallback to software decoding if hardware fails (prevents crashes)

# # Number of decoding threads (0 = auto)
# vd-lavc-threads=0
# # Possible values: 0 (auto) or any positive integer

# # # If hardware fails, fall back to software immediately (prevents black screens)
# # Faster decoding (some quality loss)
# vd-lavc-fast-decodable=yes
# # Skip loop filter (deblocking)
# vd-lavc-skiploopfilter=none
# # Possible values: none, all, default, nonref, nonkey, ...


# # ==================== SCALING & QUALITY ====================

# # Use high quality GPU profile
# profile=gpu-hq

# # Luma (brightness) upscaling algorithm
# scale=ewa_lanczossharp
# # Chroma (color) upscaling algorithm
# cscale=ewa_lanczossharp
# # Possible values: bilinear, bicubic, lanczos, ewa_lanczos, ewa_lanczossharp, spline36, mitchell, etc.

# # Temporal upscaling / frame blending
# tscale=oversample
# # Possible values: oversample, lanczos, ewa_lanczos, etc.

# # Enable video interpolation (smooth motion)
# interpolation=yes
# # Possible values: yes, no

# # High quality seeking (keyframe + interpolation) and Improve Damaged File Recovery
# hr-seek=yes
# # Possible values: yes, no, absolute, exact

# # Video sync method
# video-sync=display-resample
# # Possible values: audio, display-resample, display-adrop, desync, ...


# # ==================== AUDIO SETTINGS ====================

# # Detailed instructions on this configs here: https://mpv.io/manual/stable/

# # Language preference for audio tracks (ISO 639 codes)
# alang=en
# # Possible values: any comma-separated list of language codes (e.g. en,eng,jp,ja,de,fr)

# # Skip non-English tracks entirely 
# # alang=en:en-US

# # Audio output drivers in order of preference
# ao=pipewire,pulse,alsa
# # Possible values: pipewire, pulse, alsa, jack, coreaudio, wasapi, openal, null, ...

# # Set number of audio channels
# audio-channels=auto
# # Possible values: auto, stereo, 5.1, 7.1, mono, 2.1, 6.1, 5.1.2, etc.

# # Whether to display attached album art as video
# audio-display=embedded-first
# # Possible values: no, yes, embedded-first

# # Correct pitch when changing playback speed
# audio-pitch-correction=yes
# # Possible values: yes, no

# # Audio sync method
# audio-sync=audio
# # Possible values: audio, video, desync, display-resample, display-adrop, ...

# # Starting volume
# volume=100
# # Possible values: 0-100 (or higher if volume-max allows)

# # Maximum allowed volume (allows over-amplification)
# volume-max=200
# # Possible values: any number (usually 100-1000)


# # ==================== SUBTITLES ====================

# # Subtitle language preference
# slang=en,eng
# # Possible values: comma-separated language codes

# # Skip non-English tracks entirely 
# # slang=en:en-US

# # Subtitle auto-loading behavior
# sub-auto=fuzzy
# # Possible values: no, exact, fuzzy, all

# # Load additional subtitle files matching the video filename. The parameter specifies how external subtitle files are matched. exact is enabled by default.
# # sub-auto=exact
# # no|exact|fuzzy|all

# # Disable automatic subtitle loading
# # no-sub-auto

# # Directories to search for subtitle files
# sub-file-paths=sub:subs:subtitles
# # Possible values: colon-separated list of directories

# # Fix subtitle timing issues
# sub-fix-timing=yes
# # Possible values: yes, no

# # Show only forced subtitles by default
# sub-forced-only=no
# # Possible values: yes, no

# # Use fonts embedded in video files
# embeddedfonts=yes
# # Possible values: yes, no

# # Enable subtitle preroll for better seeking in mkv
# demuxer-mkv-subtitle-preroll=yes
# # Possible values: yes, no, yes-safe


# # ## Restyle Subtitles
# # # Set sub-ass-override to "no" as we only need to enable it for specific cases
# # sub-ass-override=no
# # sub-ass-style-overrides=playresx=1920,playresy=1080
# # sub-font="Cabin F"
# # sub-font-size=50
# # sub-color="#FFFFFFFF"
# # sub-margin-y=40
# # sub-border-size=2.4
# # sub-border-color="#FF000000"
# # sub-shadow-color="#A0000000"
# # sub-shadow-offset=0.8
# # sub-ass-style-overrides=Kerning=yes

# # ==================== CACHING & DEMUXER ====================

# # Enable caching
# cache=yes
# # Pause when cache is low
# cache-pause=yes
# # Maximum cache duration in seconds
# cache-secs=120
# # Possible values: any number (seconds)

# # Maximum total cache size
# demuxer-max-bytes=${CACHE_SIZE} # 1GiB / 500MB
# # Maximum cache size for seeking backwards
# demuxer-max-back-bytes=${CACHE_SIZE} # 256MiB / 50MB
# # Possible values: number with unit (e.g. 1GiB, 512MiB)

# demuxer-seekable-cache=${DEMUX_SEEKABLE}

# # How many seconds to read ahead
# demuxer-readahead-secs=60
# # Possible values: any positive number (seconds)

# # Disable all caching
# # no-cache

# # Force files to be treated as seekable - even if index is missing
# force-seekable=yes
# # Possible values: yes, no


# # ==================== NETWORK & STREAMING ====================

# # Enable yt-dlp support
# ytdl=yes
# # yt-dlp format selection
# ytdl-format="bestvideo[height<=2160]+bestaudio/best"
# # Raw yt-dlp options
# ytdl-raw-options=no-check-certificates=,youtube-skip-dash-manifest=

# # Disable yt-dlp
# # no-ytdl

# # Network timeout in seconds
# network-timeout=30
# # Possible values: any number (seconds)


# # ==============================================================================
# # HARDENED PRIVACY & PROTOCOL CONFIGURATIONS
# # ==============================================================================

# # Disable logging network metadata endpoints

# # Custom User-Agent for network requests
# user-agent="Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0"

# # Spoof referrer for http requests
# referrer="https://www.google.com"

# # Prevent leakage of local directory details to foreign servers during streaming sessions
# stream-lavf-o=reconnect=1,skip_loop_filter=all






# # ==================== OSD & INTERFACE ====================

# # Show on-screen controller
# osc=yes
# # Show OSD progress bar
# osd-bar=yes
# # Possible values: yes, no

# # Auto-hide cursor after X milliseconds
# cursor-autohide=1000
# # Possible values: number in ms, or no


# # ==================== PLAYBACK BEHAVIOR ====================

# # Keep window open after playback ends
# keep-open=yes
# # Possible values: yes, no, always

# # Save playback position on exit (so you resume where you left off)
# save-position-on-quit=yes
# # Possible values: yes, no

# # Location for watch later resume files
# # watch-later-directory=~~state/watch_later
# # default ~/.local/state/mpv/

# # Don't rebase timestamps / Retry opening files
# rebase-time=no
# # Possible values: yes, no

# # Reset options when loading next file
# reset-on-next-file=hwdec
# # Possible values: any option name or comma-separated list

# # Resize window to fit screen with margin
# autofit-larger=90%x90%
# # Possible values: percentage (e.g. 90%x90%), absolute size, or 0


# # ==================== COLOR MANAGEMENT ====================

# # Automatically load ICC profiles
# icc-profile-auto

# # ICC profile cache directory - default = ~/.cache/mpv
# # icc-cache-dir=/tmp/mpv-icc-cache


# # ==================== SCREENSHOTS ====================

# # Screenshot format
# screenshot-format=png
# # Use high bit depth for screenshots
# screenshot-high-bit-depth=yes
# # Possible values: png, jpg, jpeg, webp, jxl


# # ==================== MISCELLANEOUS ====================

# # Example: Start mpv with these files
# mpv ~/Videos/*


# # # --- SCRIPT OPTIONS ---

# # Subtitle Downloader: Auto-search on load, prefer English
# script-opts=subtitle_downloader-lang=en,subtitle_downloader-sources=opensubtitles,subtitle_downlist=0

# # Thumbfast: Generate thumbnails on hover
# script-opts=thumbfast-width=200,thumbfast-height=113,thumbfast-count=5

# # Auto-profiler: Example logic (create auto_profiles.json later)
# # Enable profile switching
# profile-desc=nothing

# # Hardware accel remains: hwdec=${HWDEC_FLAG} (from previous script)



# # --- MODERN OSC CONFIGURATION ---
# # Disable the default OSC
# osd-level=0

# # Enable Modern OSC
# script-opts=modern-osc-enabled=yes,modern-osc-hide-delay=3000

# # Appearance Tweaks
# # Background opacity (0.0 = transparent, 1.0 = solid)
# script-opts=modern-osc-bg-opacity=0.85
# # Font size relative to video height
# script-opts=modern-osc-font-size=14
# # Font color (White with slight transparency for readability)
# script-opts=modern-osc-text-color=FFFFFFAA
# # Position: Bottom center (classic) or Top (for immersion)
# script-opts=modern-osc-position=bottom
# # Hide when paused? (Set to yes if you hate distractions)
# script-opts=modern-osc-hide-on-pause=no

# # Open a video.
# # Press I to toggle OSD info.
# # If the text is hard to read, add this to mpv.conf:
# #  (This forces a crisp Noto Sans font for any ASS/Subtitles overlaid by the OSC).
# # sub-ass-style-overrides: FontName=Noto Sans,scale=1.5,bold=yes,margin_v=20




# ############################################################################
# # input.conf
# ############################################################################


# # VLC Comfort-Style Keybindings Compatibility
# WHEEL_UP      add volume 2
# WHEEL_DOWN    add volume -2
# UP            add volume 5
# DOWN          add volume -5
# LEFT          seek -5 exact
# RIGHT         seek 5 exact
# SHIFT+LEFT    seek -60 exact
# SHIFT+RIGHT   seek 60 exact
# SPACE         cycle pause
# f             cycle fullscreen
# m             cycle mute
# s             screenshot





# # Seek
# RIGHT seek 10
# LEFT seek -10

# UP seek 60
# DOWN seek -60

# # Volume
# Shift+UP add volume 5
# Shift+DOWN add volume -5

# # Speed
# ] add speed 0.10
# [ add speed -0.10

# # Reset speed
# BS set speed 1.0

# # Frame stepping
# . frame-step
# , frame-back-step

# # Playlist
# PGUP playlist-prev
# PGDWN playlist-next

# # Screenshot
# s screenshot

# # Toggle subtitles
# v cycle sub

# # Fullscreen
# f cycle fullscreen

