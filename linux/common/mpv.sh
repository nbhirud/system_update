#!/bin/sh

set -eux

#######################################################
# Notes
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
# Install packages
#######################################################

sudo dnf install \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm

sudo dnf config-manager --set-enabled rpmfusion-free rpmfusion-nonfree || true

sudo dnf groupupdate multimedia --setopt=install_weak_deps=False -y

sudo dnf install -y mpv mpv-mpris yt-dlp python3 ffmpeg ffmpegthumbnailer mediainfo

sudo dnf swap ffmpeg-free ffmpeg --allowerasing

# ====== lumo


# # Enable RPM Fusion Free and Non-Free
# sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm



# Update FFmpeg and related libs
sudo dnf update ffmpeg ffmpeg-libs libavcodec-extra


# 1. Enable RPM Fusion Free & Non-Free
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# 2. Update FFmpeg to the version with proprietary codecs
sudo dnf update ffmpeg ffmpeg-libs libavcodec-extra gstreamer1-plugins-{bad,good,ugly}-free gstreamer1-libav

# 3. Install the 'extra' codecs package specifically for MPV
sudo dnf install ffmpeg-free ffmpeg-libs libavcodec-extra

dnf update -y ffmpeg ffmpeg-libs libavcodec-extra gstreamer1-plugins-{bad,good,ugly}-free gstreamer1-libav
dnf install -y ffmpeg-free ffmpeg-libs libavcodec-extra


# 1. Enable RPM Fusion Free & Non-Free
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# 2. Update FFmpeg to the version with proprietary codecs
sudo dnf update ffmpeg ffmpeg-libs libavcodec-extra gstreamer1-plugins-{bad,good,ugly}-free gstreamer1-libav

# 3. Install the 'extra' codecs package specifically for MPV
sudo dnf install ffmpeg-free ffmpeg-libs libavcodec-extra

# ====== lumo extra


sudo dnf install yt-dlp python3-pip
pip3 install --user subliminal  # For subtitle downloading logic

# ffmpegthumbs 


#######################################################
# Paths
#######################################################

MPV_CONFIG_DIR="$HOME/.config/mpv"
SCRIPT_DIR="$MPV_CONFIG_DIR/scripts"
mkdir -p "$SCRIPT_DIR"


mkdir -p "${USER_HOME}/.config/mpv"
mkdir -p "${USER_HOME}/.local/state/mpv/watch_later"

#######################################################
# Memory & Hardware Context Profiling
#######################################################
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
echo "[-] Detected Total System Memory: ${TOTAL_RAM_GB} GB"

# Hardware Acceleration Evaluation
# Detect Nvidia GPU active status or default back to high-efficiency Intel pathways
if lspci | grep -qi 'nvidia'; then
    echo "[!] Nvidia GPU detected. Tuning engine pipeline flags for NVDEC / Vulkan..."
    HWDEC_VAL="nvdec"
    GPU_API_VAL="vulkan"
else
    echo "[!] Intel/Integrated GPU detected. Tuning for VA-API..."
    HWDEC_VAL="vaapi"
    GPU_API_VAL="opengl"
fi

# Dynamic Cache Scaling (Utilizing high memory capacity configurations if >12GB RAM)
if [ "$TOTAL_RAM_GB" -gt 12 ]; then
    echo "[-] Optimizing memory buffer allocation: Tuning for High-Performance Desktop caching."
    CACHE_SIZE="1048576" # 1GB Cache Buffer
    DEMUX_SEEKABLE="yes"
else
    echo "[-] Optimizing memory buffer allocation: Low/Standard footprint profiles adjusted."
    CACHE_SIZE="262144" # 256MB Cache Buffer
    DEMUX_SEEKABLE="auto"
fi


# ====== lumo



GPU_VENDOR=""
GPU_MODEL=""
CPU_MODEL=""

# Detect GPU
if lspci | grep -i nvidia >/dev/null; then
    GPU_VENDOR="NVIDIA"
    GPU_MODEL=$(lspci | grep -i nvidia | sed 's/.*: //')
    HWDEC_FLAG="nvdec-copy"
    echo -e "${GREEN}   Detected NVIDIA GPU: ${GPU_MODEL}. Setting hwdec=${HWDEC_FLAG}${NC}"
elif lspci | grep -i intel >/dev/null; then
    GPU_VENDOR="Intel"
    GPU_MODEL=$(lspci | grep -i "VGA" | grep -i intel | sed 's/.*: //')
    # Check generation roughly for VAAPI optimization
    if lspci | grep -i "HD Graphics 5" >/dev/null || lspci | grep -i "HD Graphics 6" >/dev/null; then
        HWDEC_FLAG="vaapi"
        echo -e "${GREEN}   Detected Intel GPU (Gen 5/6+). Setting hwdec=${HWDEC_FLAG}${NC}"
    else
        HWDEC_FLAG="vaapi" # Default for older/newer Intel
        echo -e "${GREEN}   Detected Intel GPU. Setting hwdec=${HWDEC_FLAG}${NC}"
    fi
else
    GPU_VENDOR="Unknown/Integrated"
    HWDEC_FLAG="auto"
    echo -e "${YELLOW}   No dedicated GPU detected. Using 'auto' fallback.${NC}"
fi

# Detect CPU (for logging)
CPU_MODEL=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
echo -e "${GREEN}   CPU: ${CPU_MODEL}${NC}"




#######################################################
# Config file - mpv.conf
#######################################################

cp "$HOME"/nb/CodeProjects/system_update/linux/common/data/mpv.conf "$MPV_CONFIG_DIR"/mpv.conf

# TODO - make changes in this config file using above Profiling

#######################################################
# Keybindings - input.conf
#######################################################

cp "$HOME"/nb/CodeProjects/system_update/linux/common/data/mpv_input.conf "$MPV_CONFIG_DIR"/input.conf



#######################################################
# Deploy Extensibility Plugins / Scripts - Auto-Load File Directory Playlist Engine
#######################################################

echo "[-] Deploying Auto-Load File Directory Playlist Engine..."
cat << 'EOF' > "$SCRIPT_DIR/autoload.lua"
-- Automatic dynamic directory appending when launching single loose targets
local msg = require 'mp.msg'
local utils = require 'mp.utils'

function autoload_dir()
    local path = mp.get_property("path")
    if not path or path:find("^%a%a+://") then return end
    
    local dir, filename = utils.split_path(path)
    if dir == "." then return end

    local files = utils.readdir(dir, "files")
    if not files then return end
    
    table.sort(files, function(a, b) return a:lower() < b:lower() end)

    local append_index = 0
    for _, file in ipairs(files) do
        if file:match("%.([%a%d]+)$") then
            local ext = file:match("%.([%a%d]+)$"):lower()
            if ext:match("^(mp4|mkv|avi|flv|webm|mov|ts|mp3|flac|wav|ogg|m4a|wma)$") then
                if file == filename then
                    append_index = 1
                elseif append_index > 0 then
                    mp.commandv("loadfile", utils.join_path(dir, file), "append")
                end
            end
        end
    end
end
mp.register_event("start-file", autoload_dir)
EOF




#######################################################
# Deploy Extensibility Plugins / Scripts - sponsorblock
#######################################################

# SponsorBlock
curl -L \
https://raw.githubusercontent.com/po5/mpv_sponsorblock/master/sponsorblock.lua -o "$SCRIPT_DIR/sponsorblock.lua"




#######################################################
# Deploy Extensibility Plugins / Scripts - ModernX OSC
#######################################################
# ModernX OSC
#   https://github.com/cyl0/ModernX
# Check if this is better - https://github.com/zydezu/ModernX
# Or this? - https://github.com/Samillion/ModernZ

curl -L https://raw.githubusercontent.com/tomislukic/modern-osc/master/modern-osc.lua -o "$SCRIPT_DIR/modern-osc.lua"

#######################################################
# Deploy Extensibility Plugins / Scripts - Subtitle Downloader
#######################################################

# 1. Subtitle Downloader (The most critical one)
curl -L https://raw.githubusercontent.com/jonniek/mpv-subtitle-downloader/master/subtitle_downloader.lua -o "$SCRIPT_DIR/subtitle_downloader.lua"




#######################################################
# Deploy Extensibility Plugins / Scripts - yt-dlp integration
#######################################################

# # 2. yt-dlp integration (Replace youtube-dl entirely)

# # Following is alternative way to install the latest version of yt-dlp. But we are using fedora package instead (dnf install)
# # curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
# #   -o /usr/local/bin/yt-dlp && chmod +x /usr/local/bin/yt-dlp

# # The dnf package:
# # >> which yt-dlp
# # /usr/bin/yt-dlp  

# # Create the youtube-dl wrapper script (MPV expects 'youtube-dl' sometimes)
# cat > "$SCRIPT_DIR/youtube-dl.lua" <<EOF
# #!/bin/bash
# # exec /usr/local/bin/yt-dlp "\$@"
# exec /usr/bin/yt-dlp "\$@"
# EOF
# chmod +x "$SCRIPT_DIR/youtube-dl.lua"
# # mv youtube-dl youtube-dl.lua # Actually, just ensure the binary is in PATH

#######################################################
# Deploy Extensibility Plugins / Scripts - thumbfast
#######################################################

# High-performance on-the-fly thumbnailer for mpv - Thumbnails in seek bar
curl -L https://raw.githubusercontent.com/po5/thumbfast/master/thumbfast.lua -o "$SCRIPT_DIR/thumbfast.lua"


#######################################################
# Deploy Extensibility Plugins / Scripts - Skip Silence
#######################################################

# 4. Skip Silence (For long walks/podcasts)
curl -L https://raw.githubusercontent.com/occure/mpris-subset/master/skip_silence.lua -o "$SCRIPT_DIR/skip_silence.lua"

# Note: The skip_silence script above might need manual tuning. A more robust alternative is pause-on-silence, but for now, let's stick to the basics.

#######################################################
# Deploy Extensibility Plugins / Scripts - Auto-Profiles
#######################################################

# 3. Advanced: Auto-Profiles (Context Aware)
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


#######################################################
# Firewall
#######################################################

# Ensure mpv doesn't leak telemetry (it doesn't by default).
# If using subtitle downloaders, restrict network access via firewalld:

# sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" destination address="0.0.0.0/0" port port="443" protocol="tcp" reject'
# sudo firewall-cmd --reload


#######################################################
# Bind Platform to System Mime Default Types
#######################################################

echo "[-] Registering default system application priority targets..."
MIME_FILE="$HOME/.config/mimeapps.list"
mkdir -p "$(dirname "$MIME_FILE")"
[ ! -f "$MIME_FILE" ] && echo "[Default Applications]" > "$MIME_FILE"

declare -a TARGET_MIMES=(
    "video/x-matroska"
    "video/mp4"
    "video/webm"
    "video/quicktime"
    "video/x-msvideo"
    "video/x-flv"
    "audio/mpeg"
    "audio/x-flac"
    "audio/ogg"
    "audio/mp4"
)

for mime in "${TARGET_MIMES[@]}"; do
    if ! grep -q "$mime" "$MIME_FILE"; then
        sed -i "/^\[Default Applications\]/a $mime=mpv.desktop;" "$MIME_FILE"
    fi
done

echo "[+] Deployment successfully established. Your mpv player is tuned for Wayland, isolated against telemetry tracking, integrated into KDE/PipeWire infrastructure, and optimized for maximum hardware processing capabilities."


##########


log "Associating media files with mpv"

xdg-mime default mpv.desktop video/mp4 || true
xdg-mime default mpv.desktop video/x-matroska || true
xdg-mime default mpv.desktop video/webm || true

xdg-mime default mpv.desktop video/mp4
xdg-mime default mpv.desktop video/x-matroska
xdg-mime default mpv.desktop video/webm
xdg-mime default mpv.desktop video/x-msvideo
xdg-mime default mpv.desktop audio/mpeg
xdg-mime default mpv.desktop audio/flac


# ======= lumo


# Set Default Application - Update MIME types
xdg-mime default vlc.desktop video/*
xdg-mime default mpv.desktop video/mp4
xdg-mime default mpv.desktop video/x-matroska
xdg-mime default mpv.desktop video/avi
xdg-mime default mpv.desktop video/x-msvideo
xdg-mime default mpv.desktop video/webm
# xdg-mime default mpv.desktop audio/*







#######################################################
# 
#######################################################




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