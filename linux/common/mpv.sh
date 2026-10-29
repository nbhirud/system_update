#!/usr/bin/env bash
#########################################################
# Useful Links
#########################################################
# --- mpv: manual, options, release notes -----------------------------------------
#   https://mpv.io/manual/stable/                                         (manual; options, input commands, Lua API)
#   https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst    (option reference incl. hwdec/gpu-api semantics)
#   https://github.com/mpv-player/mpv/blob/master/DOCS/interface-changes.rst (renamed/removed options per version)
#   https://github.com/mpv-player/mpv/wiki                                (wiki index)
#   https://github.com/mpv-player/mpv/wiki/GPU-Next-vs-GPU                (renderer comparison)
#   https://github.com/mpv-player/mpv/wiki/User-Scripts                   (catalogue of user scripts)
#   https://github.com/mpv-player/mpv/tree/master/TOOLS/lua               (official example scripts, incl. autoload.lua)
#   https://github.com/mpv-player/mpv/blob/master/player/lua/ytdl_hook.lua (how mpv calls yt-dlp)
#   https://www.linuxtoday.com/blog/mpv-0-41-open-source-video-player-released-with-improved-wayland-support/ (0.41: gpu-next default, Wayland)
#   https://man.archlinux.org/man/mpv.1#FILES                             (config/script/font directories)
#   https://thewiki.moe/tutorials/mpv/                                    (community configuration guide)
#   https://github.com/stax76/awesome-mpv                                 (curated scripts list)
# --- distribution documentation -----------------------------------------------------
#   https://wiki.archlinux.org/title/Mpv                                  (Arch: mpv)
#   https://wiki.archlinux.org/title/Hardware_video_acceleration          (Arch: VA-API/VDPAU/NVDEC driver matrix per GPU generation)
#   https://wiki.archlinux.org/title/FFmpeg                               (Arch: ffmpeg)
#   https://wiki.archlinux.org/title/Xdg-mime                             (Arch: MIME defaults, mimeapps.list)
#   https://wiki.gentoo.org/wiki/Mpv                                      (Gentoo: mpv; scripts shipped by the distro)
#   https://wiki.gentoo.org/wiki/VAAPI                                    (Gentoo: VA-API driver selection)
#   https://wiki.debian.org/HardwareVideoAcceleration                     (Debian: i965 for pre-Broadwell, iHD for Broadwell+)
#   https://rpmfusion.org/Howto/Multimedia                                (Fedora: full ffmpeg, hardware codec drivers)
#   https://docs.fedoraproject.org/en-US/quick-docs/installing-plugins-for-playing-movies-and-music/ (Fedora codecs)
#   https://packages.fedoraproject.org/pkgs/mpv/mpv-libs/fedora-44.html   (mpv is in Fedora main; 0.41 on Fedora 44)
#   https://discussion.fedoraproject.org/t/swapping-mesa-for-freeworld/190405 (Fedora 44: freeworld Mesa installs in parallel, no swap)
#   https://computingforgeeks.com/rpm-fusion-fedora-44-codecs/            (Fedora 44 codec walkthrough)
#   https://download1.rpmfusion.org/nonfree/fedora/releases/44/Everything/x86_64/os/repoview/intel-media-driver.html (intel-media-driver is nonfree)
# --- hardware video decoding -------------------------------------------------------
#   https://github.com/intel/media-driver                                 (iHD VA-API driver: Broadwell and newer)
#   https://github.com/intel/intel-vaapi-driver                           (i965 VA-API driver: GMA 4500 .. Coffee Lake)
#   https://github.com/intel/libva-utils                                  (vainfo)
#   https://developer.nvidia.com/video-encode-and-decode-gpu-support-matrix-new (NVDEC codec support per GPU generation)
# --- yt-dlp and YouTube --------------------------------------------------------------
#   https://github.com/yt-dlp/yt-dlp/wiki/EJS                             (JS challenge solver: runtimes, which builds bundle it)
#   https://github.com/yt-dlp/yt-dlp/issues/14404                         (announcement: external JS runtime now required)
#   https://bugzilla.redhat.com/show_bug.cgi?id=2476441                   (Fedora's yt-dlp RPM ships without EJS)
#   https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/jsc/_builtin/node.py (how Node is sandboxed)
#   https://nodejs.org/api/permissions.html                               (Node permission model)
#   https://github.com/yt-dlp/yt-dlp/releases                             (official release builds + SHA2-256SUMS)
#   https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp (cookies, deliberately not configured)
# --- addons ---------------------------------------------------------------------------
#   https://github.com/Samillion/ModernZ#configuration                    (on-screen controller)
#   https://github.com/po5/thumbfast                                      (seekbar thumbnails)
#   https://github.com/po5/mpv_sponsorblock                               (SponsorBlock client; options in sponsorblock.lua)
#   https://wiki.sponsor.ajay.app/w/API_Docs                              (SponsorBlock API: hash-prefix lookups)
#   https://github.com/ferreum/mpv-skipsilence                            (speeds through silence)
#   https://github.com/hoyon/mpv-mpris                                    (MPRIS: media keys, KDE Connect)
#   https://github.com/ekisu/mpv-webm                                     (not installed: WebM clip maker)
# --- desktop integration and system -------------------------------------------------------
#   https://specifications.freedesktop.org/mime-apps-spec/latest-single   (mimeapps.list semantics, [Removed Associations])
#   https://www.freedesktop.org/software/systemd/man/latest/tmpfiles.d.html (age-based cleanup of watch_later)
#   https://docs.clamav.net/manual/OnAccess.html                          (on-access scanning of the downloads directory)

#########################################################
# Overview and usage
#########################################################
# mpv setup for Fedora KDE (Wayland or X11): hardware-aware, privacy-first, re-runnable.
#
# WHAT IT DOES
#   1. Detects hardware through the shared mini scripts in linux/common/ and picks a tier
#   2. Backs up every file it touches, plus locations older setups may have used
#   3. Installs packages (mpv, full ffmpeg, GPU video drivers, KDE helpers); a failure here
#      leaves the existing setup untouched
#   4. Resets (removes) the previous mpv setup completely and starts fresh
#   5. Installs the latest official yt-dlp and selects a JavaScript runtime for YouTube
#   6. Probes what the GPU can decode in hardware and tunes mpv.conf to it
#   7. Installs addons (latest versions) and removes any that fail to load
#   8. Registers mpv as the default player for VIDEO MIME types (not audio)
#   9. Verifies the result (also runnable alone with --verify-setup)
#
# NAMED OPTIONS (all optional; defaults come from the "User defined" section)
#   --audio-langs <list>          preferred audio languages, e.g. "en,eng,hi"
#   --sub-langs <list>            preferred subtitle languages
#   --seek-step <seconds>         arrow-key seek step (default 10; Shift+arrow is 6x)
#   --sponsorblock <yes|no>       install SponsorBlock (contacts a third-party server)
#   --tls-verify <yes|no>         verify HTTPS certificates (self-signed LAN servers need "no")
#   --js-runtime <auto|node|deno|quickjs|none>   JavaScript runtime used by yt-dlp
#   --user-agent <string>         User-Agent for plain http(s) streams
#   --watch-later-max-age <age>   prune resume positions older than this (e.g. 90d)
#   --ytdl-max-height <auto|N>    cap for streamed video height
#   --verify-setup                run only the verification section
#   --help
#
# SAMPLE CALLS (assuming the calling script uses the same variable names)
#   Only mandatory options (there are none; every option has a default):
#     bash "$SYSUPDATE_CODE_BASE_DIR/linux/mpv_setup.sh"
#   All options:
#     bash "$SYSUPDATE_CODE_BASE_DIR/linux/mpv_setup.sh" \
#         --audio-langs "en,eng,hi" --sub-langs "en,eng" --seek-step 10 \
#         --sponsorblock yes --tls-verify yes --js-runtime auto \
#         --user-agent "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0" \
#         --watch-later-max-age 90d --ytdl-max-height auto
#   Verification only:
#     bash "$SYSUPDATE_CODE_BASE_DIR/linux/mpv_setup.sh" --verify-setup
#
# Started with sudo, the script re-runs itself as the invoking user (see helper_run_as_user.sh)
# so every file in the home directory has the right owner; dnf is called through sudo.

set -Eeuo pipefail
IFS=$'\n\t'
umask 077   # new files are private by default; modes are then set explicitly where more access is needed
trap 'echo -e "\n\033[0;31m[✗] failed at line ${LINENO}: ${BASH_COMMAND}\033[0m" >&2' ERR

#########################################################
# Standard directories
#########################################################
REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects" # Path for all code projects
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update" # Path for linux setup project

SCRIPT_DATA="${NBDIR}/nb_script_data" # Base dir for all stuff created by scripts

# Downloads dir (ClamAV on-access scanning is enabled for this directory)
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads" # Base dir for all downloads by scripts
MPV_DOWNLOADS_DIR_BASE="${SCRIPT_DATA_DOWNLOADS}/mpv"
MPV_CURRENT_DOWNLOADS_DIR="${MPV_DOWNLOADS_DIR_BASE}/mpv_${FILENAME_TIMESTAMP}" # use this to download anything

# Backups dir
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups" # Base dir for all backups by scripts
MPV_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/mpv"
MPV_CURRENT_BACKUP_DIR="${MPV_BACKUP_DIR_BASE}/mpv_${FILENAME_TIMESTAMP}" # use this to backup everything

COMMON_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/common"

#########################################################
# User defined
#########################################################
# Values that may be changed before running. Most can also be set with a named option.

# Preferred audio / subtitle languages (comma separated, mpv syntax)
MPV_AUDIO_LANGS="en,eng"
MPV_SUB_LANGS="en,eng"

# Font families tried in order; the first one fontconfig reports is used for the on-screen
# display, subtitles and ModernZ. If none is installed, mpv's default fallback stays active.
MPV_FONT_CANDIDATES=("NotoSans Nerd Font" "Noto Sans")

# Arrow-key seek step in seconds (Shift+arrow seeks six times this).
MPV_SEEK_STEP=10
# "exact" lands on the requested frame (slower on long-GOP files); "keyframes" is faster but approximate.
MPV_SEEK_PRECISION="exact"

# Addons. "auto" decides from the detected hardware; "yes"/"no" force.
MPV_INSTALL_SPONSORBLOCK="yes"   # PRIVACY CHOICE, see Notes: contacts sponsor.ajay.app with a 4-hex-char hash prefix
MPV_INSTALL_THUMBFAST="auto"     # seekbar thumbnails (spawns a helper mpv): needs RAM profile > low, SSD, >= 4 CPUs
MPV_INSTALL_SKIPSILENCE="auto"   # speeds through silence (podcasts, lectures): not on the low tier

# SECURITY CHOICE, see Notes: "yes" verifies HTTPS certificates. Self-signed servers (a LAN Jellyfin,
# for example) then fail; either use a real/Tailscale certificate, or override per stream with
# `mpv --tls-verify=no URL`. Setting "no" here disables verification for everything.
MPV_TLS_VERIFY="yes"

# JavaScript runtime yt-dlp needs for YouTube: auto | node | deno | quickjs | none
# auto prefers an installed deno (strongest sandbox), then nodejs >= 22 (run by yt-dlp inside
# Node's permission sandbox), then quickjs.
MPV_JS_RUNTIME="auto"

# User-Agent for plain http(s) streams. Generic and recent is less unique than the default "libmpv".
MPV_USER_AGENT="Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"

# Resume positions (watch_later) older than this are pruned by a systemd user timer.
MPV_WATCH_LATER_MAX_AGE="90d"

# Streamed video height cap: "auto" (from hardware) or a number such as 1080.
MPV_YTDL_MAX_HEIGHT="auto"

# Subtitle look (base size is relative to a 720p window)
MPV_SUB_FONT_SIZE=44
MPV_SUB_BORDER_SIZE=2.2

# Volume ceiling in percent (mpv allows up to 1000; default 130)
MPV_VOLUME_MAX=150

# GStreamer codec extras so other KDE applications (not mpv) also play everything
MPV_INSTALL_GSTREAMER_EXTRAS="yes"

# Desktop file of the player and the MIME types it is registered for (video only)
MPV_DESKTOP_ID="mpv.desktop"
MPV_EXTRA_VIDEO_MIME_TYPES=(application/x-matroska application/mxf application/vnd.rn-realmedia
                            application/x-extension-mp4 application/x-flash-video)

#########################################################
# Helpers
#########################################################
# Reusable helpers live in linux/common/helper_*.sh (documented in each file).
# Functions below are specific to this script.

for _helper in helper_logging helper_array helper_version_compare helper_fonts helper_github \
               helper_download helper_backup helper_dnf helper_run_as_user helper_mimeapps; do
    if [[ ! -r "${COMMON_DIR}/${_helper}.sh" ]]; then
        echo "[✗] Missing helper: ${COMMON_DIR}/${_helper}.sh (is SYSUPDATE_CODE_BASE_DIR correct?)" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "${COMMON_DIR}/${_helper}.sh"
done
unset _helper

# is_kde: true on a KDE Plasma session as reported by get_desktop_env.sh
is_kde() { [[ "${DESKTOP,,}" == *kde* || "${DESKTOP,,}" == *plasma* ]]; }

# word_in_list <word> <space separated list>: exact word match without a pipe
word_in_list() { [[ " $2 " == *" $1 "* ]]; }

# mpv_accepts <option>...: does THIS mpv build parse these options? (plays 0.1 s of nothing)
mpv_accepts() {
    timeout 20 mpv --no-config --no-terminal --vo=null --ao=null --length=0.1 "$@" \
        'av://lavfi:color=c=black:duration=1' >/dev/null 2>&1
}

# mpv_has_profile <name>: does THIS mpv know the built-in profile?
mpv_has_profile() { mpv --no-config --show-profile="$1" >/dev/null 2>&1; }

# ---- mpv defaults (to write default-valued options as commented lines) ---------------
# `mpv --list-options` prints "--name  Type (default: VALUE) [range]" for every option of the
# INSTALLED mpv, so "equals the default" is evaluated against the right version.
# MPV_KNOWN holds EVERY option name the installed mpv has, so an option that a newer mpv removed or
# renamed (for example --sub-forced-only) is never written as an active line: mpv refuses to start
# on an unknown option in mpv.conf.
declare -A MPV_DEFAULTS=()
declare -A MPV_KNOWN=()
load_mpv_defaults() {
    local line name re_default='\(default: ([^)]*)\)( \[.*\])?$' re_name='^ --([a-z0-9-]+)[ ]'
    MPV_DEFAULTS=()
    MPV_KNOWN=()
    while IFS= read -r line; do
        if [[ "$line" =~ $re_name ]]; then
            name="${BASH_REMATCH[1]}"
            MPV_KNOWN["$name"]=1
            if [[ "$line" =~ $re_default ]]; then MPV_DEFAULTS["$name"]="${BASH_REMATCH[1]}"; fi
        fi
    done < <(mpv --no-config --list-options 2>/dev/null || true)
}

# option_known <key>: true when the installed mpv has this option (list suffixes like -append and
# -remove are ignored). If the option list could not be read at all, everything is assumed known.
option_known() {
    local base="${1%-append}"
    base="${base%-remove}"; base="${base%-add}"; base="${base%-pre}"; base="${base%-set}"
    (( ${#MPV_KNOWN[@]} == 0 )) || [[ -n "${MPV_KNOWN[$base]+x}" ]]
}

# normalize_value <text>: canonical form for comparisons ("150.000 MiB" == "150MiB", "3.0" == "3")
normalize_value() {
    local v="${1,,}"
    v="${v//\"/}"
    v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
    if [[ "$v" =~ ^([0-9]+(\.[0-9]+)?)\ ?(kib|mib|gib)$ ]]; then
        awk -v n="${BASH_REMATCH[1]}" -v u="${BASH_REMATCH[3]}" \
            'BEGIN { m = (u=="kib") ? 1024 : (u=="mib") ? 1048576 : 1073741824; printf "%.0f", n*m }'
    elif [[ "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        awk -v n="$v" 'BEGIN { printf "%g", n }'
    else
        printf '%s' "$v"
    fi
}

#########################################################
# Named Options processing
#########################################################
VERIFY_ONLY=0

print_usage() { sed -n '/^# Overview and usage/,/^set -Eeuo/p' "$0" | sed -e '1,2d;$d' -e 's/^# \{0,1\}//'; }

# Accepts both "--name value" and "--name=value". Anything else (positional arguments) is an error.
parse_named_options() {
    local arg name value
    while (( $# )); do
        arg="$1"; shift
        case "$arg" in
            --verify-setup) VERIFY_ONLY=1; continue ;;
            --help|-h)      print_usage; exit 0 ;;
            --*=*)          name="${arg%%=*}"; value="${arg#*=}" ;;
            --*)            name="$arg"
                            (( $# )) || log_die "Option ${name} requires a value (see --help)"
                            value="$1"; shift ;;
            *)              log_die "Unexpected argument '${arg}'. Use named options (see --help)." ;;
        esac
        case "$name" in
            --audio-langs)         MPV_AUDIO_LANGS="$value" ;;
            --sub-langs)           MPV_SUB_LANGS="$value" ;;
            --seek-step)           MPV_SEEK_STEP="$value" ;;
            --sponsorblock)        MPV_INSTALL_SPONSORBLOCK="$value" ;;
            --tls-verify)          MPV_TLS_VERIFY="$value" ;;
            --js-runtime)          MPV_JS_RUNTIME="$value" ;;
            --user-agent)          MPV_USER_AGENT="$value" ;;
            --watch-later-max-age) MPV_WATCH_LATER_MAX_AGE="$value" ;;
            --ytdl-max-height)     MPV_YTDL_MAX_HEIGHT="$value" ;;
            *)                     log_die "Unknown option: ${name} (see --help)" ;;
        esac
    done

    # Validate values so mistakes fail early, before anything is changed.
    [[ "$MPV_SEEK_STEP" =~ ^[0-9]+$ && "$MPV_SEEK_STEP" -ge 1 ]] || log_die "--seek-step must be a whole number of seconds"
    [[ "$MPV_INSTALL_SPONSORBLOCK" =~ ^(yes|no)$ ]] || log_die "--sponsorblock must be yes or no"
    [[ "$MPV_TLS_VERIFY" =~ ^(yes|no)$ ]] || log_die "--tls-verify must be yes or no"
    [[ "$MPV_JS_RUNTIME" =~ ^(auto|node|deno|quickjs|none)$ ]] || log_die "--js-runtime must be auto, node, deno, quickjs or none"
    [[ "$MPV_WATCH_LATER_MAX_AGE" =~ ^[0-9]+[smhdw]$ ]] || log_die "--watch-later-max-age must look like 90d"
    [[ "$MPV_YTDL_MAX_HEIGHT" =~ ^(auto|[0-9]+)$ ]] || log_die "--ytdl-max-height must be auto or a number"
}

#########################################################
# Inferred variables
#########################################################
# Everything below is detected at run time, never typed in. Hardware detection lives in the
# shared mini scripts (POSIX sh, one value each); this script only consumes them.

infer_paths() {
    XDG_CONFIG="${XDG_CONFIG_HOME:-${HOME_DIR}/.config}"
    XDG_DATA="${XDG_DATA_HOME:-${HOME_DIR}/.local/share}"
    XDG_STATE="${XDG_STATE_HOME:-${HOME_DIR}/.local/state}"
    XDG_CACHE="${XDG_CACHE_HOME:-${HOME_DIR}/.cache}"
    MPV_CONFIG_DIR="${XDG_CONFIG}/mpv"
    MPV_SCRIPTS_DIR="${MPV_CONFIG_DIR}/scripts"
    MPV_OPTS_DIR="${MPV_CONFIG_DIR}/script-opts"
    MPV_FONTS_DIR="${MPV_CONFIG_DIR}/fonts"
    MPV_STATE_DIR="${XDG_STATE}/mpv"
    MPV_WATCH_LATER_DIR="${MPV_STATE_DIR}/watch_later"
    MPV_MANIFEST="${MPV_CONFIG_DIR}/.setup_manifest"
    LOCAL_BIN="${HOME_DIR}/.local/bin"
    YTDLP_BIN="${LOCAL_BIN}/yt-dlp"
    CLIPBOARD_LAUNCHER="${LOCAL_BIN}/mpv-clipboard"
    APPLICATIONS_DIR="${XDG_DATA}/applications"
    TMPFILES_USER_DIR="${XDG_CONFIG}/user-tmpfiles.d"
    # Only an interactive-looking value; the localized "Pictures" folder is resolved through xdg-user-dirs.
    local pictures
    pictures="$(xdg-user-dir PICTURES 2>/dev/null || true)"
    if [[ -z "$pictures" || "$pictures" == "$HOME_DIR" ]]; then pictures="${HOME_DIR}/Pictures"; fi
    MPV_SCREENSHOT_DIR="${pictures}/mpv-screenshots"
    # A session bus makes the MPRIS check possible even when started from a non-login context.
    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "/run/user/$(id -u)/bus" ]]; then
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
        export DBUS_SESSION_BUS_ADDRESS
    fi
}

infer_system_variables() {
    # DISTRO is read by require_fedora() in helper_dnf.sh
    # shellcheck disable=SC2034
    DISTRO=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_distro_name.sh)           # fedora, etc
    DISTRO_VERSION=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_distro_version.sh) # 44
    DESKTOP=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_desktop_env.sh)          # kde/gnome/cosmic/etc
    PC_TYPE=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_pc_type.sh)              # laptop or desktop or server
    CPU_CORES=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_cpu_cores.sh)          # logical CPUs (nproc)
    RAM_MB=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_ram_size.sh)              # total RAM in MB
    RAM_PROFILE=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_ram_profile.sh)      # low or mid or high
    SSD_PRESENT=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_ssd_present.sh)      # true or false
    CPU_MODEL=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_cpu_model.sh)
    GPU_VENDORS=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_gpu_vendors.sh)      # e.g. "intel nvidia"
    GPU_NAMES=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_gpu_names.sh)          # one per line
    NVIDIA_DRIVER=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_nvidia_driver.sh)  # proprietary | nouveau | none
    INTEL_GENERATION=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_intel_gen.sh)   # 1 (pre-2011) .. 15; 0 unknown
    CPU_IS_ULV=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_cpu_is_ulv.sh)        # true | false
    AMD_GPU_CLASS=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_amd_gpu_class.sh)  # none | legacy | modern | discrete
    GPU_TIER=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_gpu_tier.sh)            # low | mid | high

    [[ "$CPU_CORES" =~ ^[0-9]+$ ]] || log_die "get_cpu_cores.sh returned a non-number: '${CPU_CORES}'"
    [[ "$RAM_MB" =~ ^[0-9]+$ ]]    || log_die "get_ram_size.sh returned a non-number: '${RAM_MB}'"
    [[ "$INTEL_GENERATION" =~ ^[0-9]+$ ]] || INTEL_GENERATION=0
    [[ "$GPU_TIER" =~ ^(low|mid|high)$ ]] || log_die "get_gpu_tier.sh returned '${GPU_TIER}' (expected low|mid|high)"

    HAS_INTEL=0; HAS_NVIDIA=0; HAS_AMD=0
    if word_in_list intel  "$GPU_VENDORS"; then HAS_INTEL=1;  fi
    if word_in_list nvidia "$GPU_VENDORS"; then HAS_NVIDIA=1; fi
    if word_in_list amd    "$GPU_VENDORS"; then HAS_AMD=1;    fi

    # The GPU tier is graphics only. With fewer than 4 logical CPUs one step is subtracted: the
    # software fallback paths (and subtitles, thumbnails) need CPU headroom.
    PERF_TIER="$GPU_TIER"
    if (( CPU_CORES < 4 )); then
        case "$PERF_TIER" in high) PERF_TIER="mid" ;; mid) PERF_TIER="low" ;; esac
    fi

    # Demuxer cache sizes by RAM. The cache lives in RAM only (cache-on-disk stays off, so nothing
    # is written to disk); sizes are bounded because a huge cache only wastes memory on local files.
    if   (( RAM_MB >= 24000 )); then CACHE_FWD="1024MiB"; CACHE_BACK="512MiB"; CACHE_SECS=600
    elif (( RAM_MB >= 12000 )); then CACHE_FWD="512MiB";  CACHE_BACK="256MiB"; CACHE_SECS=300
    elif (( RAM_MB >=  6000 )); then CACHE_FWD="256MiB";  CACHE_BACK="128MiB"; CACHE_SECS=180
    elif (( RAM_MB >=  3000 )); then CACHE_FWD="128MiB";  CACHE_BACK="64MiB";  CACHE_SECS=90
    else                             CACHE_FWD="64MiB";   CACHE_BACK="32MiB";  CACHE_SECS=45; fi
    DEC_THREADS=$(( CPU_CORES > 8 ? 8 : CPU_CORES ))   # software-decode threads, capped at 8

    # Addon gating by capability
    WANT_SPONSORBLOCK=0; WANT_THUMBFAST=0; WANT_SKIPSILENCE=0
    [[ "$MPV_INSTALL_SPONSORBLOCK" == "yes" ]] && WANT_SPONSORBLOCK=1
    case "$MPV_INSTALL_THUMBFAST" in
        yes)  WANT_THUMBFAST=1 ;;
        auto) if [[ "$RAM_PROFILE" != "low" && "$SSD_PRESENT" == "true" ]] && (( CPU_CORES >= 4 )); then WANT_THUMBFAST=1; fi ;;
    esac
    case "$MPV_INSTALL_SKIPSILENCE" in
        yes)  WANT_SKIPSILENCE=1 ;;
        auto) if [[ "$PERF_TIER" != "low" ]]; then WANT_SKIPSILENCE=1; fi ;;
    esac
    return 0
}

validate_environment() {
    # Distribution: this script installs through dnf/RPM Fusion.
    require_fedora
    # Headless machines have nothing to show video on.
    if [[ "$PC_TYPE" == "server" ]]; then
        log_die "Server/headless machine detected (get_pc_type.sh): mpv is a GUI player. Aborting."
    fi
    # Desktop: only the KDE-specific parts are skipped elsewhere, so this is a warning.
    if ! is_kde; then
        log_warn "Desktop reported as '${DESKTOP:-unknown}', not KDE: kdialog, Dolphin thumbnails and KDE cache refresh are skipped."
    fi
    if [[ "$DISTRO_VERSION" =~ ^[0-9]+$ ]] && (( DISTRO_VERSION < 41 )); then
        log_warn "Fedora ${DISTRO_VERSION} predates DNF5 (Fedora 41); package steps use commands valid for both but are untested there."
    fi
    log_success "Fedora ${DISTRO_VERSION}, ${PC_TYPE}, desktop: ${DESKTOP}, user ${REAL_USER}"
    if [[ "$MPV_TLS_VERIFY" == "no" ]]; then
        log_warn "TLS verification is DISABLED (tls-verify=no): HTTPS streams can be silently altered by anyone on the network path. Prefer a per-stream override: mpv --tls-verify=no URL."
    fi
}

print_hardware_summary() {
    log_info "CPU : ${CPU_MODEL} (${CPU_CORES} logical CPUs)   SSD: ${SSD_PRESENT}"
    log_info "RAM : ${RAM_MB} MB (profile: ${RAM_PROFILE}) -> cache ${CACHE_FWD} ahead / ${CACHE_BACK} back / ${CACHE_SECS}s"
    log_info "GPU : $(printf '%s' "${GPU_NAMES:-none detected}" | paste -sd';' - | sed 's/;/; /g')"
    if (( HAS_INTEL )); then log_info "Intel generation: ${INTEL_GENERATION} (ULV: ${CPU_IS_ULV})"; fi
    if (( HAS_NVIDIA )); then log_info "NVIDIA driver: ${NVIDIA_DRIVER}"; fi
    if (( HAS_AMD )); then log_info "AMD class: ${AMD_GPU_CLASS}"; fi
    log_info "GPU tier: ${GPU_TIER} -> performance tier (after CPU adjustment): ${PERF_TIER}"
    log_info "Addons: sponsorblock=${WANT_SPONSORBLOCK} thumbfast=${WANT_THUMBFAST} skipsilence=${WANT_SKIPSILENCE}"
    if (( HAS_INTEL && HAS_NVIDIA )); then
        log_info "Hybrid laptop: decoding and rendering stay on the Intel iGPU (the compositor runs there; the NVIDIA card would need PRIME offload and costs battery)."
    fi
}

#########################################################
# Backup
#########################################################
# Everything the setup touches is copied to MPV_CURRENT_BACKUP_DIR first, together with the
# places an older setup (this script's earlier versions, manual installs, Flatpak/Snap mpv,
# pipx/pip yt-dlp...) may have written to.

backup_existing_setup() {
    mkdir -p "$MPV_CURRENT_BACKUP_DIR"
    chmod 700 "$MPV_CURRENT_BACKUP_DIR"

    # --- mpv configuration, state and legacy locations
    backup_path "$MPV_CONFIG_DIR"                       "$MPV_CURRENT_BACKUP_DIR" "config-mpv"
    backup_path "${HOME_DIR}/.mpv"                      "$MPV_CURRENT_BACKUP_DIR" "legacy-dot-mpv"
    backup_path "/etc/mpv"                              "$MPV_CURRENT_BACKUP_DIR" "etc-mpv"
    backup_path "$MPV_STATE_DIR"                        "$MPV_CURRENT_BACKUP_DIR" "state-mpv"
    backup_path "${XDG_DATA}/mpv"                       "$MPV_CURRENT_BACKUP_DIR" "data-mpv"
    backup_path "${HOME_DIR}/.var/app/io.mpv.Mpv/config" "$MPV_CURRENT_BACKUP_DIR" "flatpak-mpv-config"
    backup_path "${HOME_DIR}/snap/mpv"                  "$MPV_CURRENT_BACKUP_DIR" "snap-mpv"
    # --- yt-dlp: configuration is read by mpv's ytdl hook too, so a stale one changes behaviour
    backup_path "${XDG_CONFIG}/yt-dlp"                  "$MPV_CURRENT_BACKUP_DIR" "config-yt-dlp"
    backup_path "${HOME_DIR}/yt-dlp.conf"               "$MPV_CURRENT_BACKUP_DIR" "home-yt-dlp.conf"
    backup_path "/etc/yt-dlp.conf"                      "$MPV_CURRENT_BACKUP_DIR" "etc-yt-dlp.conf"
    backup_path "/etc/yt-dlp"                           "$MPV_CURRENT_BACKUP_DIR" "etc-yt-dlp"
    backup_path "$YTDLP_BIN"                            "$MPV_CURRENT_BACKUP_DIR" "bin-yt-dlp"
    backup_path "$CLIPBOARD_LAUNCHER"                   "$MPV_CURRENT_BACKUP_DIR" "bin-mpv-clipboard"
    # --- desktop integration: launchers, MIME defaults, timers/services
    local f
    for f in "${APPLICATIONS_DIR}"/mpv*.desktop; do
        [[ -e "$f" ]] && backup_path "$f" "$MPV_CURRENT_BACKUP_DIR" "applications-$(basename "$f")"
    done
    backup_path "${XDG_CONFIG}/mimeapps.list"           "$MPV_CURRENT_BACKUP_DIR" "mimeapps.list"
    backup_path "${APPLICATIONS_DIR}/mimeapps.list"     "$MPV_CURRENT_BACKUP_DIR" "applications-mimeapps.list"
    backup_path "$TMPFILES_USER_DIR"                    "$MPV_CURRENT_BACKUP_DIR" "user-tmpfiles.d"
    for f in "${XDG_CONFIG}"/systemd/user/mpv*; do
        [[ -e "$f" ]] && backup_path "$f" "$MPV_CURRENT_BACKUP_DIR" "systemd-user-$(basename "$f")"
    done

    # --- package and repository state (rollback: `sudo dnf history undo <ID>`)
    rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort > "${MPV_CURRENT_BACKUP_DIR}/rpm-qa.txt" || true
    dnf history list 2>/dev/null | head -20 > "${MPV_CURRENT_BACKUP_DIR}/dnf-history-before.txt" || true
    dnf repolist --enabled 2>/dev/null > "${MPV_CURRENT_BACKUP_DIR}/dnf-repolist.txt" || true
    cat > "${MPV_CURRENT_BACKUP_DIR}/RESTORE.txt" <<EOF
Backup taken ${FILENAME_TIMESTAMP}
  mpv config   : rm -rf "${MPV_CONFIG_DIR}" && cp -a "${MPV_CURRENT_BACKUP_DIR}/config-mpv" "${MPV_CONFIG_DIR}"
  resume state : cp -a "${MPV_CURRENT_BACKUP_DIR}/state-mpv/." "${MPV_STATE_DIR}/"
  MIME defaults: cp -a "${MPV_CURRENT_BACKUP_DIR}/mimeapps.list" "${XDG_CONFIG}/mimeapps.list"
  yt-dlp       : cp -a "${MPV_CURRENT_BACKUP_DIR}/bin-yt-dlp" "${YTDLP_BIN}"
  packages     : sudo dnf history list | head ; sudo dnf history undo <ID>   (see dnf-history-before.txt)
EOF
    log_success "Backup complete: ${MPV_CURRENT_BACKUP_DIR} ($(du -sh "$MPV_CURRENT_BACKUP_DIR" | cut -f1))"
}

#########################################################
# Reset
#########################################################
# Starts from a clean slate instead of patching whatever an earlier run left behind. Runs only
# after the backup above has been verified AND the package step has succeeded. Deliberately KEPT: resume positions in
# ~/.local/state/mpv/watch_later (user data, not configuration) and the user's own packages.
# MIME defaults need no reset step: set-default (see MIME defaults) replaces the defaults for the
# video types and clears blacklisting entries in one pass.

reset_existing_setup() {
    local f
    rm -rf -- "$MPV_CONFIG_DIR" "${HOME_DIR}/.mpv" "${XDG_CACHE}/mpv" "${XDG_CACHE}/yt-dlp"
    # A leftover yt-dlp config could silently override the TLS and runtime settings written below.
    if [[ -e "${XDG_CONFIG}/yt-dlp" || -e "${HOME_DIR}/yt-dlp.conf" ]]; then
        log_warn "Removing existing yt-dlp configuration (it was backed up; it would override mpv's yt-dlp options)."
        rm -rf -- "${XDG_CONFIG}/yt-dlp" "${HOME_DIR}/yt-dlp.conf"
    fi
    rm -f -- "$YTDLP_BIN" "$CLIPBOARD_LAUNCHER"
    for f in "${APPLICATIONS_DIR}"/mpv*.desktop; do
        [[ -e "$f" ]] && rm -f -- "$f"
    done
    rm -rf -- "$TMPFILES_USER_DIR/mpv.conf"
    local had_units=0
    for f in "${XDG_CONFIG}"/systemd/user/mpv*; do
        if [[ -e "$f" ]]; then rm -rf -- "$f"; had_units=1; fi
    done
    if (( had_units )) && command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi

    # Things that are NOT removed but may shadow or conflict with the fresh setup:
    if [[ -e /etc/yt-dlp.conf || -d /etc/yt-dlp ]]; then
        log_warn "System-wide yt-dlp configuration exists (/etc/yt-dlp*); review it if downloads behave oddly."
    fi
    if command -v flatpak >/dev/null 2>&1 && flatpak list --app 2>/dev/null | grep -q 'io.mpv.Mpv'; then
        log_warn "A Flatpak mpv (io.mpv.Mpv) is installed; it ignores this configuration. Uninstall it if the native mpv should be the only player."
    fi
    for f in /usr/local/bin/yt-dlp "${HOME_DIR}/.local/pipx/venvs/yt-dlp" "${XDG_DATA}/pipx/venvs/yt-dlp"; do
        [[ -e "$f" ]] && log_warn "Another yt-dlp install exists at ${f}; mpv is pointed at ${YTDLP_BIN} explicitly."
    done
    log_success "Previous mpv setup removed (backup: ${MPV_CURRENT_BACKUP_DIR})"
    return 0
}

#########################################################
# Packages
#########################################################
# Two dnf transactions: A installs plain packages and never removes anything; B contains packages
# that REPLACE installed ones (full ffmpeg replaces ffmpeg-free, intel-media-driver replaces
# Fedora's limited libva-intel-media-driver). B prints its dry-run plan before executing.

install_packages() {
    require_fedora
    sudo -v    # authenticate once up front so later prompts do not interrupt the run

    # --- RPM Fusion: "free" provides full ffmpeg and libva-intel-driver; "nonfree" provides
    #     intel-media-driver. Each release package enables its own repository.
    local -a rpmfusion=()
    if ! rpm_is_installed rpmfusion-free-release; then
        rpmfusion+=("https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${DISTRO_VERSION}.noarch.rpm")
    fi
    if (( HAS_INTEL )) && (( INTEL_GENERATION == 0 || INTEL_GENERATION >= 5 )) && ! rpm_is_installed rpmfusion-nonfree-release; then
        rpmfusion+=("https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${DISTRO_VERSION}.noarch.rpm")
    fi
    if (( ${#rpmfusion[@]} )); then
        log_info "Enabling RPM Fusion: $(array_join_space "${rpmfusion[@]}")"
        sudo dnf install -y "${rpmfusion[@]}"
    fi

    # --- Transaction A: ordinary packages
    local -a pkgs_a=(mpv mpv-mpris curl python3 libva-utils vulkan-tools mesa-vulkan-drivers
                     wl-clipboard libnotify fontconfig xdg-utils xdg-user-dirs pciutils desktop-file-utils)
    if is_kde; then pkgs_a+=(kdialog ffmpegthumbs); fi        # file dialogs; Dolphin video thumbnails
    case "$MPV_JS_RUNTIME" in
        auto)    if ! command -v deno >/dev/null 2>&1 && ! command -v node >/dev/null 2>&1; then pkgs_a+=(nodejs); fi ;;
        node)    pkgs_a+=(nodejs) ;;
        quickjs) pkgs_a+=(quickjs) ;;
    esac
    dnf_install_packages "${pkgs_a[@]}"

    # --- Transaction B: packages that replace others
    local -a pkgs_b=(ffmpeg)
    if (( HAS_INTEL )); then
        # iHD = Broadwell (gen 5) and newer; i965 = GMA 4500 .. Coffee Lake. libva tries iHD first
        # and falls back to i965, so an unknown generation gets both.
        if (( INTEL_GENERATION == 0 || INTEL_GENERATION >= 5 )); then pkgs_b+=(intel-media-driver); fi
        if (( INTEL_GENERATION == 0 || INTEL_GENERATION <= 4 )); then pkgs_b+=(libva-intel-driver); fi
    fi
    # AMD: Fedora's Mesa has the H.264/HEVC/VC-1 VA-API codecs removed. The freeworld build restores
    # them. On Fedora 44+ it installs ALONGSIDE the stock driver; older releases replace it.
    if (( HAS_AMD )); then pkgs_b+=(mesa-va-drivers-freeworld); fi
    if [[ "$MPV_INSTALL_GSTREAMER_EXTRAS" == "yes" ]]; then
        pkgs_b+=(gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly gstreamer1-plugin-libav gstreamer1-plugin-openh264)
    fi
    dnf_install_replacing "${pkgs_b[@]}"

    command -v mpv >/dev/null 2>&1 || log_die "mpv is not installed after the package step."
    return 0
}

#########################################################
# yt-dlp and JavaScript runtime
#########################################################
# The distribution RPM is not used: it ships WITHOUT the YouTube JS-challenge solver (yt-dlp-ejs)
# and lags upstream, while YouTube changes break yt-dlp every few weeks. The official single-file
# build bundles the solver and updates itself (`yt-dlp -U`). Integrity: the SHA2-256SUMS file of the
# same release is checked.

install_ytdlp() {
    local dir="${MPV_CURRENT_DOWNLOADS_DIR}/yt-dlp" base="https://github.com/yt-dlp/yt-dlp/releases/latest/download"
    local want got
    mkdir -p "$dir" "$LOCAL_BIN"
    chmod 755 "$LOCAL_BIN"
    if download_file "${base}/yt-dlp" "${dir}/yt-dlp" && download_file "${base}/SHA2-256SUMS" "${dir}/SHA2-256SUMS"; then
        want="$(awk '$2 ~ /^\*?yt-dlp$/ {print $1; exit}' "${dir}/SHA2-256SUMS")"
        got="$(sha256sum "${dir}/yt-dlp" | cut -d' ' -f1)"
        if [[ -n "$want" && "$want" == "$got" ]]; then
            install -m 755 "${dir}/yt-dlp" "$YTDLP_BIN"
            log_success "yt-dlp $("$YTDLP_BIN" --version 2>/dev/null || echo '?') installed (checksum verified)"
        else
            log_warn "yt-dlp checksum mismatch; NOT installed."
        fi
    else
        log_warn "Could not download yt-dlp; YouTube and similar sites will not work until it is installed."
    fi
    if [[ ! -x "$YTDLP_BIN" ]]; then
        YTDLP_BIN="$(command -v yt-dlp || true)"
        if [[ -n "$YTDLP_BIN" ]]; then log_warn "Using system yt-dlp (${YTDLP_BIN}); it may lack the YouTube solver."; fi
    fi
    return 0
}

# select_js_runtime: sets JS_RUNTIME_ARG to "<runtime>:<absolute path>" (yt-dlp --js-runtimes syntax),
# or leaves it empty. Absolute paths are used because GUI-launched mpv may lack ~/.local/bin or
# /usr/local/bin in PATH. ALWAYS returns 0 (a failing last `[[ ]] &&` would otherwise abort under set -e).
select_js_runtime() {
    JS_RUNTIME_ARG=""
    local want="$MPV_JS_RUNTIME" p="" major=0
    try_runtime() {
        case "$1" in
            deno)
                p="$(command -v deno || true)"
                if [[ -z "$p" && -x "${HOME_DIR}/.deno/bin/deno" ]]; then p="${HOME_DIR}/.deno/bin/deno"; fi
                if [[ -n "$p" ]]; then JS_RUNTIME_ARG="deno:${p}"; fi ;;
            node)
                p="$(command -v node || true)"
                if [[ -n "$p" ]]; then
                    major="$("$p" -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
                    if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 22 )); then JS_RUNTIME_ARG="node:${p}"
                    else log_warn "node (major '${major}') is older than 22, which yt-dlp requires"; fi
                fi ;;
            quickjs)
                p="$(command -v qjs || true)"
                if [[ -n "$p" ]]; then JS_RUNTIME_ARG="quickjs:${p}"; fi ;;
        esac
    }
    case "$want" in
        auto)
            try_runtime deno
            if [[ -z "$JS_RUNTIME_ARG" ]]; then try_runtime node; fi
            if [[ -z "$JS_RUNTIME_ARG" ]]; then try_runtime quickjs; fi ;;
        none) ;;
        *)  try_runtime "$want" ;;
    esac
    if [[ -n "$JS_RUNTIME_ARG" ]]; then
        log_success "JavaScript runtime for yt-dlp: ${JS_RUNTIME_ARG}"
    elif [[ "$want" != "none" ]]; then
        log_warn "No usable JavaScript runtime found: YouTube playback will be degraded. Install nodejs (>= 22) and re-run."
    fi
    return 0
}

#########################################################
# Decoder probe
#########################################################
# Runs after the packages are installed: asks the system what it can REALLY decode in hardware,
# then derives the video pipeline. Detection of hardware identity is in the shared scripts; this
# section only interprets it.

infer_decoder_variables() {
    MPV_VERSION="$(mpv --version | awk 'NR==1 {print $2}')"; MPV_VERSION="${MPV_VERSION#v}"
    load_mpv_defaults

    VAAPI_DEVICE=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_vaapi_device.sh)    # render node or "none"
    VAAPI_CODECS=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_vaapi_codecs.sh)    # "h264 hevc vp9 av1" or "none"
    NVIDIA_COMPUTE_CAP=$(sh "$SYSUPDATE_CODE_BASE_DIR"/linux/common/get_nvidia_compute_cap.sh)

    # NVDEC only when the NVIDIA card is the ONLY GPU (desktop). On hybrid machines the Intel/AMD
    # iGPU renders the desktop and does the decoding.
    USE_NVIDIA=0
    if (( HAS_NVIDIA )) && [[ "$NVIDIA_DRIVER" == "proprietary" ]] && (( HAS_INTEL == 0 && HAS_AMD == 0 )); then
        USE_NVIDIA=1
    fi

    # hwdec priority list. The last entry "auto" is mpv's own safe whitelist, and mpv falls back to
    # software decoding by itself when every entry fails: a broken driver never means "no video".
    if (( USE_NVIDIA )); then
        HWDEC_LIST="nvdec,nvdec-copy,auto"
        DECODE_DESC="NVIDIA NVDEC (compute capability ${NVIDIA_COMPUTE_CAP}.x)"
    elif [[ "$VAAPI_DEVICE" != "none" ]]; then
        HWDEC_LIST="vaapi,vaapi-copy,auto"
        DECODE_DESC="VA-API on ${VAAPI_DEVICE} (${VAAPI_CODECS})"
    else
        HWDEC_LIST="auto"
        DECODE_DESC="software (no working hardware decoder detected)"
    fi
    if (( HAS_NVIDIA )) && [[ "$NVIDIA_DRIVER" == "nouveau" ]]; then
        log_warn "nouveau has no usable video decode; the other GPU or software decoding is used."
    fi
    if (( HAS_INTEL )) && [[ "$VAAPI_DEVICE" == "none" ]]; then
        log_warn "Intel GPU present but VA-API reports no decoder. A reboot may be needed after the driver install; check with 'vainfo'."
    fi
    log_info "Decoder: ${DECODE_DESC}"

    # Streamed-video codec: ask for what THIS machine decodes in hardware. yt-dlp's default sort
    # prefers AV1 > VP9 > H.264; codecs that would fall to slow software decoding are filtered out.
    local hw_h264=0 hw_vp9=0 hw_av1=0
    if word_in_list h264 "$VAAPI_CODECS" || (( USE_NVIDIA )); then hw_h264=1; fi
    if word_in_list vp9  "$VAAPI_CODECS" || (( USE_NVIDIA && NVIDIA_COMPUTE_CAP >= 6 )); then hw_vp9=1; fi
    if word_in_list av1  "$VAAPI_CODECS" || (( USE_NVIDIA && NVIDIA_COMPUTE_CAP >= 8 )); then hw_av1=1; fi
    if   (( hw_av1 )); then CODEC_FILTER=""
    elif (( hw_vp9 )); then CODEC_FILTER='[vcodec!^=av01]'
    elif (( hw_h264 )); then CODEC_FILTER='[vcodec^=avc1]'
    elif (( CPU_CORES >= 6 )); then CODEC_FILTER='[vcodec!^=av01]'   # strong CPU: VP9 in software is fine
    else CODEC_FILTER='[vcodec^=avc1]'; fi                           # weak CPU: H.264 only

    # Height cap: by tier, lowered without hardware decode or with little RAM/CPU.
    case "$PERF_TIER" in low) YT_MAX=1080 ;; mid) YT_MAX=1440 ;; high) YT_MAX=2160 ;; esac
    if (( hw_h264 == 0 )); then
        if (( YT_MAX > 720 )); then YT_MAX=720; fi
        if (( CPU_CORES <= 2 )); then YT_MAX=480; fi
    fi
    if (( RAM_MB < 4000 && YT_MAX > 720 )); then YT_MAX=720; fi
    if [[ "$MPV_YTDL_MAX_HEIGHT" != "auto" ]]; then YT_MAX="$MPV_YTDL_MAX_HEIGHT"; fi
    YTDL_FORMAT="bestvideo[height<=?${YT_MAX}]${CODEC_FILTER}+bestaudio/bestvideo[height<=?${YT_MAX}]+bestaudio/best[height<=?${YT_MAX}]/best"
    log_info "Streaming: max ${YT_MAX}p, codec filter '${CODEC_FILTER:-none}'"

    # gpu-api accepts a priority LIST only in newer mpv (0.41); older builds take a single value.
    GPU_API="opengl,vulkan"
    mpv_accepts --gpu-api=opengl,vulkan || GPU_API="opengl"

    # Renderer and scaling by tier. gpu-next (libplacebo) is the default since mpv 0.41; the classic
    # "gpu" renderer is lighter on very old GPUs. A comma list makes mpv fall back to the second.
    QUALITY_OPTS=()
    case "$PERF_TIER" in
        low)
            VO_LIST="gpu,gpu-next"
            QUALITY_OPTS=(profile=fast scale=bilinear cscale=bilinear dscale=bilinear video-sync=audio
                          interpolation=no deband=no vd-lavc-skiploopfilter=nonref)
            ;;
        mid)
            VO_LIST="gpu-next,gpu"
            QUALITY_OPTS=(scale=spline36 cscale=spline36 dscale=mitchell correct-downscaling=yes
                          video-sync=display-resample interpolation=no tscale=oversample)
            ;;
        high)
            VO_LIST="gpu-next,gpu"
            # "high-quality" is the current profile name (gpu-hq is its older name).
            local hq=""
            if mpv_has_profile high-quality; then hq="high-quality"; elif mpv_has_profile gpu-hq; then hq="gpu-hq"; fi
            if [[ -n "$hq" ]]; then QUALITY_OPTS+=("profile=${hq}"); fi
            QUALITY_OPTS+=(scale=ewa_lanczossharp cscale=ewa_lanczossharp dscale=mitchell
                           video-sync=display-resample interpolation=yes tscale=oversample)
            ;;
    esac
    # Laptops: continuous frame blending keeps the GPU busy (battery, fan noise).
    if [[ "$PC_TYPE" == "laptop" ]]; then
        local i
        for i in "${!QUALITY_OPTS[@]}"; do
            if [[ "${QUALITY_OPTS[$i]}" == "interpolation=yes" ]]; then QUALITY_OPTS[i]="interpolation=no"; fi
        done
    fi

    UI_FONT="$(first_installed_font "${MPV_FONT_CANDIDATES[@]}")"
    if [[ -n "$UI_FONT" ]]; then log_success "UI/subtitle font: ${UI_FONT}"
    else log_warn "None of the candidate fonts is installed; mpv's default font fallback stays active."; fi
    return 0
}

#########################################################
# Configuration
#########################################################
# mpv.conf is assembled from small functions:
#   conf_opt        writes "key=value", or "#key=value" when the value equals the installed mpv's
#                   own default (kept as documentation of what is effectively set)
#   conf_opt_always same, but never commented out (security-relevant values must stay explicit,
#                   because defaults differ between mpv builds)
#   conf_skip       a commented-out option that is deliberately NOT set, with the reason and the
#                   value that would be ideal if it were enabled
# Every function takes ONE argument per text line (IFS is newline/tab in this script, so "$*"
# would join arguments with newlines).

CONF_TEXT=""
conf_add() { CONF_TEXT+="${1}"$'\n'; }
conf_section() { conf_add ""; conf_add "# ------------------------------ ${1} ------------------------------"; }
conf_note() { conf_add "# ${1}"; }

conf_opt() {  # conf_opt <key> <value> [note]
    local key="$1" value="$2" note="${3:-}" lookup="${1%-append}"
    if [[ -n "$note" ]]; then conf_note "$note"; fi
    if ! option_known "$key"; then
        conf_add "#${key}=${value}   # NOT SET: option unknown to mpv ${MPV_VERSION} (renamed or removed)"
        log_warn "mpv ${MPV_VERSION} has no option '${key}': written as a comment only."
    elif [[ "$key" == "$lookup" && -n "${MPV_DEFAULTS[$lookup]+x}" ]] \
       && [[ "$(normalize_value "${MPV_DEFAULTS[$lookup]}")" == "$(normalize_value "$value")" ]]; then
        conf_add "#${key}=${value}   # mpv default (${MPV_VERSION}); written for documentation"
    else
        conf_add "${key}=${value}"
    fi
}

conf_opt_always() {  # conf_opt_always <key> <value> [note]
    if [[ -n "${3:-}" ]]; then conf_note "$3"; fi
    if option_known "$1"; then
        conf_add "${1}=${2}"
    else
        conf_add "#${1}=${2}   # NOT SET: option unknown to mpv ${MPV_VERSION} (renamed or removed)"
        log_warn "mpv ${MPV_VERSION} has no option '${1}': written as a comment only."
    fi
}

conf_skip() {  # conf_skip <key> <value> <reason> <ideal value when enabled>
    conf_add "# SKIPPED ${1}"
    conf_add "#   Why  : ${3}"
    conf_add "#   Ideal: ${4}"
    conf_add "#${1}=${2}"
}

write_mpv_conf() {
    CONF_TEXT=""
    conf_add "# =============================================================================="
    conf_add "# mpv.conf - generated by mpv_setup.sh on $(date -Iseconds)"
    conf_add "# Host   : $(hostname)   performance tier: ${PERF_TIER}   mpv ${MPV_VERSION}"
    conf_add "# CPU    : ${CPU_MODEL} (${CPU_CORES} logical CPUs)   RAM: ${RAM_MB} MB"
    conf_add "# GPU    : $(printf '%s' "${GPU_NAMES:-none detected}" | paste -sd';' - | sed 's/;/; /g')"
    conf_add "# Decoder: ${DECODE_DESC}"
    conf_add "# Lines starting with '#key=value' either equal mpv's default (noted as such) or are"
    conf_add "# options deliberately not set (marked SKIPPED, with the reason and the ideal value)."
    conf_add "# Regenerate by re-running the setup script; the previous file is backed up first."
    conf_add "# =============================================================================="

    conf_section "video output"
    conf_opt vo "$VO_LIST" "Priority list: mpv falls back to the next entry if one cannot start."
    conf_opt gpu-api "$GPU_API" "OpenGL first (most stable on Intel/AMD/NVIDIA), Vulkan as fallback."
    conf_opt hwdec "$HWDEC_LIST" "Decoder priority; 'auto' (safe whitelist) last, then automatic software fallback."
    conf_opt vd-lavc-threads "$DEC_THREADS" "Software-decode threads (0 = mpv decides); only used when hwdec is not."
    conf_skip gpu-context "waylandvk" \
        "Automatic selection picks wayland or x11egl, so one config works in both Plasma sessions." \
        "waylandvk on a Wayland-only machine when HDR output is wanted (color management needs Vulkan)"
    conf_skip hwdec-codecs "all" \
        "Hardware decoding of every codec, including ones drivers handle poorly (MPEG-4, VC-1 on old chips)." \
        "the default list; restrict it on NVIDIA to codecs the GPU generation supports (avoids slow probing)"
    conf_skip reset-on-next-file "hwdec" \
        "Pointless here: hwdec is not changed per file." \
        "unset"
    conf_skip vulkan-queue-count "8" \
        "No measurable benefit; the default (1) is the most compatible." \
        "1 (default). vulkan-async-compute/transfer likewise stay at their defaults"
    conf_skip vd-lavc-fast "yes" \
        "Non-compliant decoding shortcuts cause artifacts. (An earlier revision used a non-existent option 'vd-lavc-fast-decodable'.)" \
        "yes, but only on very weak CPUs that must decode in software"
    conf_skip hr-seek "yes" \
        "Seeks are made exact by the explicit 'exact' flag in input.conf; a global value would also slow chapter and absolute seeks." \
        "yes (precise seeking everywhere) on fast storage and CPUs"
    conf_skip icc-profile-auto "yes" \
        "Plasma 6 manages colors itself; automatic ICC use has no effect on Wayland and can double-correct." \
        "yes in an X11 session with a calibrated display"
    conf_skip tone-mapping "auto" \
        "The default already adapts to the display. (An earlier revision used the invalid value 'haar'.)" \
        "auto (default); target-peak is likewise left to auto-detection"

    conf_section "quality (${PERF_TIER} tier)"
    local kv
    for kv in "${QUALITY_OPTS[@]}"; do conf_opt "${kv%%=*}" "${kv#*=}"; done

    conf_section "audio"
    conf_opt ao "pipewire,pulse,alsa" "PipeWire (Fedora default), then the PulseAudio API, then ALSA."
    conf_opt alang "$MPV_AUDIO_LANGS"
    conf_opt volume "100"
    conf_opt volume-max "$MPV_VOLUME_MAX"
    conf_opt audio-display "embedded-first" "Show embedded cover art for audio files."
    conf_opt audio-pitch-correction "yes" "Keep pitch constant when playing at other speeds."
    conf_skip audio-channels "auto" \
        "The default (auto-safe) downmixes to what the device reports as safe; 'auto' can send 5.1/7.1 to a stereo device." \
        "auto, when a multichannel receiver is connected over HDMI"
    conf_skip audio-sync "audio" \
        "Not an mpv option (earlier revision). The real A/V offset option is --audio-delay." \
        "audio-delay=<seconds> for a permanent offset on a device with latency"
    conf_skip replaygain "track" \
        "Only useful for tagged music libraries." \
        "track (or album for whole albums)"

    conf_section "subtitles and on-screen text"
    conf_opt slang "$MPV_SUB_LANGS"
    conf_opt sub-auto "fuzzy" "Loads external subtitles whose name contains the video's name."
    conf_opt sub-file-paths "sub:subs:subtitles:Sub:Subs:Subtitles" "Extra folders searched for subtitles."
    conf_opt sub-fix-timing "yes"
    conf_opt sub-font-size "$MPV_SUB_FONT_SIZE"
    conf_opt sub-border-size "$MPV_SUB_BORDER_SIZE"
    conf_opt sub-shadow-offset "1"
    conf_opt sub-ass-override "no" "Leave ASS/SSA styling (anime, fansubs) untouched; font and size apply to plain SRT."
    conf_opt demuxer-mkv-subtitle-preroll "yes" "Correct subtitle text right after seeking in MKV."
    conf_opt embeddedfonts "yes"
    # Renamed to sub-forced-events-only in mpv 0.38; the old name was removed later.
    if [[ -n "${MPV_KNOWN[sub-forced-events-only]+x}" ]]; then conf_opt sub-forced-events-only "no"; else conf_opt sub-forced-only "no"; fi
    if [[ -n "$UI_FONT" ]]; then
        conf_opt osd-font "\"${UI_FONT}\""
        conf_opt sub-font "\"${UI_FONT}\""
    else
        conf_note "osd-font / sub-font left to mpv's fallback: none of the candidate fonts is installed."
    fi

    conf_section "cache (RAM only)"
    conf_opt cache "yes" "Also cache local files (read-ahead helps spinning disks)."
    conf_opt cache-secs "$CACHE_SECS"
    conf_opt demuxer-max-bytes "$CACHE_FWD" "Sizes follow installed RAM (${RAM_MB} MB)."
    conf_opt demuxer-max-back-bytes "$CACHE_BACK"
    conf_opt demuxer-seekable-cache "yes" "Allow seeking backwards inside the cache for streams."
    conf_opt cache-pause "yes"
    conf_opt cache-on-disk "no" "Nothing is written to disk."
    conf_skip demuxer-readahead-secs "60" \
        "cache-secs overrides it whenever the cache is enabled." \
        "equal to cache-secs if the cache were disabled"
    conf_skip force-seekable "yes" \
        "Forcing seeking on non-seekable streams can hang playback." \
        "yes, per file, only for broken containers: mpv --force-seekable=yes FILE"

    conf_section "network, TLS and yt-dlp"
    conf_opt_always tls-verify "$MPV_TLS_VERIFY" "HTTPS certificates are verified (mpv's own default differs between builds)."
    if [[ -r /etc/pki/tls/certs/ca-bundle.crt ]]; then conf_opt_always tls-ca-file "/etc/pki/tls/certs/ca-bundle.crt"; fi
    conf_opt network-timeout "30"
    conf_opt_always user-agent "\"${MPV_USER_AGENT}\"" "Generic recent browser identity for plain http(s) streams (yt-dlp sends its own)."
    conf_opt_always stream-lavf-o "reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5" \
        "Reconnect after dropped connections (reconnect_at_eof is avoided: it can loop at a real end of file)."
    conf_opt ytdl "yes"
    conf_opt_always ytdl-format "\"${YTDL_FORMAT}\"" "Chosen from what this machine decodes in hardware; see Notes."
    if [[ -n "$JS_RUNTIME_ARG" ]]; then
        conf_opt_always ytdl-raw-options-append "js-runtimes=${JS_RUNTIME_ARG}" "JavaScript runtime for YouTube (see Notes)."
    else
        conf_note "No JavaScript runtime found at setup time: install nodejs (>= 22) and re-run for full YouTube support."
    fi
    conf_skip ytdl-raw-options "cookies-from-browser=librewolf" \
        "Giving yt-dlp the browser's cookies exposes the whole login session to a subprocess." \
        "per run, only when needed (age-restricted videos): mpv --ytdl-raw-options=cookies-from-browser=librewolf URL"
    conf_skip referrer "\"https://www.google.com\"" \
        "A forged referrer is deceptive and breaks sites that check it; sending none is the most private." \
        "unset"
    conf_skip ytdl-raw-options "no-check-certificates=,youtube-skip-dash-manifest=" \
        "REMOVED for good: no-check-certificates disables TLS verification; the DASH-manifest switch is obsolete." \
        "never"
    conf_skip load-unsafe-playlists "yes" \
        "Playlists may reference arbitrary local files and protocols; keeping mpv's safe default." \
        "no (default)"
    conf_skip input-ipc-server "~~/ipc.sock" \
        "A control socket lets any process of this user drive mpv; nothing here needs it." \
        "a path inside a 0700 directory, only when an external controller needs it"

    conf_section "behaviour"
    conf_opt keep-open "yes" "Stay open on the last frame instead of closing."
    conf_opt autofit-larger "90%x90%"
    conf_opt stop-screensaver "yes" "Idle inhibition while playing (KDE honours it on Wayland)."
    conf_opt screenshot-format "png"
    conf_opt screenshot-dir "${MPV_SCREENSHOT_DIR}"
    conf_opt screenshot-template "\"%F-%P-%n\""
    conf_opt screenshot-high-bit-depth "yes"
    conf_opt cursor-autohide "1000"
    conf_skip osd-level "0" \
        "Would hide every on-screen message, including volume and seek feedback." \
        "1 (default)"
    conf_skip rebase-time "no" \
        "Not an mpv option (earlier revision); the related option is rebase-start-time." \
        "unset"

    conf_section "resume playback"
    conf_opt save-position-on-quit "yes"
    conf_opt watch-later-dir "${MPV_WATCH_LATER_DIR}"
    conf_opt watch-later-options-remove "sub-pos" "ModernZ recommends not persisting these two."
    conf_opt watch-later-options-remove "osd-margin-y"
    conf_skip write-filename-in-watch-later-config "yes" \
        "Writes the file's path into every resume file (a viewing history on disk)." \
        "no (default)"

    conf_add ""
    conf_add "# =============================================================================="
    conf_add "# PROFILES (mpv --profile=NAME ...). They must stay at the END of this file: every"
    conf_add "# line after a [section] header belongs to that profile."
    conf_add "# =============================================================================="
    conf_add "# Applied automatically by URL scheme"
    conf_add "[protocol.http]"
    conf_add "cache-pause-initial=yes"
    conf_add "[protocol.https]"
    conf_add "cache-pause-initial=yes"
    conf_add ""
    conf_add "# Streaming quality presets"
    conf_add "[ytdl-720p]"
    conf_add "ytdl-format=\"bestvideo[height<=?720]${CODEC_FILTER}+bestaudio/bestvideo[height<=?720]+bestaudio/best[height<=?720]/best\""
    conf_add "[ytdl-1080p]"
    conf_add "ytdl-format=\"bestvideo[height<=?1080]${CODEC_FILTER}+bestaudio/bestvideo[height<=?1080]+bestaudio/best[height<=?1080]/best\""
    conf_add "[ytdl-best]"
    conf_add "ytdl-format=\"bestvideo+bestaudio/best\""

    printf '%s' "$CONF_TEXT" > "${MPV_CONFIG_DIR}/mpv.conf"
}

write_input_conf() {
    local big=$(( MPV_SEEK_STEP * 6 ))
    {
        cat <<EOF
# =============================================================================
# input.conf - generated by mpv_setup.sh
# Only OVERRIDES are listed; mpv's built-in bindings stay active (SPACE pause, f fullscreen,
# m mute, s screenshot, i stats, ESC leave fullscreen, Ctrl+h toggle hwdec, . and , frame step,
# PGUP/PGDWN chapters, BS reset speed, < and > playlist).
# =============================================================================

# Seeking: ${MPV_SEEK_STEP}s with the arrow keys, ${big}s with Shift. Precision: ${MPV_SEEK_PRECISION}.
LEFT         seek -${MPV_SEEK_STEP} ${MPV_SEEK_PRECISION}
RIGHT        seek ${MPV_SEEK_STEP} ${MPV_SEEK_PRECISION}
Shift+LEFT   seek -${big} ${MPV_SEEK_PRECISION}
Shift+RIGHT  seek ${big} ${MPV_SEEK_PRECISION}

# Volume (VLC-like)
UP           add volume 5
DOWN         add volume -5
Shift+UP     add volume 10
Shift+DOWN   add volume -10
#WHEEL_UP    add volume 2     # mpv default
#WHEEL_DOWN  add volume -2    # mpv default

# Tracks (VLC habits): v = subtitle track, b = audio track, V = subtitles on/off
v            cycle sub
b            cycle audio
V            cycle sub-visibility

# Chapters
Ctrl+RIGHT   add chapter 1
Ctrl+LEFT    add chapter -1

# Fine speed steps (mpv's defaults multiply by 1.1)
[            add speed -0.1
]            add speed 0.1

# Loudness normalisation toggle (quiet podcasts, loud ads)
n            cycle-values af "lavfi=[loudnorm=I=-16:TP=-1.5:LRA=11]" ""
EOF
        if (( WANT_SPONSORBLOCK )); then
            cat <<'EOF'

# SponsorBlock: the segment SUBMISSION and voting keys are disabled, so a stray key press can never
# send data to a third-party server.
g            ignore
G            ignore
h            ignore
H            ignore
EOF
        fi
        cat <<'EOF'

# -----------------------------------------------------------------------------
# SKIPPED (present in earlier revisions, deliberately not bound)
# -----------------------------------------------------------------------------
# ESC quit                  one slip closes the player. Ideal: leave ESC at mpv's default (leave fullscreen).
# UP seek 60 / DOWN seek -60  clashes with the volume keys above. Ideal: bind to Shift+arrows if wanted.
# SPACE cycle pause, f cycle fullscreen, m cycle mute, s screenshot, . frame-step, , frame-back-step,
# BS set speed 1.0          identical to mpv's built-in defaults, nothing to override.
# PGUP playlist-prev / PGDWN playlist-next  shadows the default chapter keys; < and > already do this.
# cycle sub forced / cycle audio all        not valid arguments (cycle takes up|down). Ideal: "cycle sub down".
# P toggle demuxer-cache-statistics / w show-demuxer-cache-state  not valid commands or properties;
#                           the built-in "i" statistics page (cache page: press i, then 2) replaces them.
EOF
    } > "${MPV_CONFIG_DIR}/input.conf"
}

write_script_opts() {
    {
        echo "# Use the user-level official yt-dlp by absolute path: GUI-launched mpv (Dolphin, KRunner)"
        echo "# does not always have ~/.local/bin in PATH."
        echo "ytdl_path=${YTDLP_BIN:-}"
    } > "${MPV_OPTS_DIR}/ytdl_hook.conf"

    cat > "${MPV_OPTS_DIR}/autoload.conf" <<'EOF'
# Opening one file queues its siblings, only of the same type (videos with videos).
images=no
videos=yes
audio=yes
same_type=yes
ignore_hidden=yes
directory_mode=auto
EOF

    {
        echo "# Option names taken from ModernZ's own modernz.conf"
        echo "layout=default"
        echo "icon_theme=fluent"
        echo "icon_style=mixed"
        if [[ -n "$UI_FONT" ]]; then echo "font=${UI_FONT}"; fi
        echo "jump_amount=${MPV_SEEK_STEP}"
        echo "jump_more_amount=$(( MPV_SEEK_STEP * 6 ))"
        echo "jump_mode=exact"
        echo "idlescreen=no"
        echo "greenandgrumpy=yes"
        echo "hidetimeout=2000"
    } > "${MPV_OPTS_DIR}/modernz.conf"

    if (( WANT_THUMBFAST )); then
        local size=240
        if [[ "$PERF_TIER" == "high" ]]; then size=320; fi
        cat > "${MPV_OPTS_DIR}/thumbfast.conf" <<EOF
max_width=${size}
max_height=${size}
# No thumbnails for streams: avoids a second connection per hover (bandwidth and privacy).
network=no
audio=no
hwdec=no
# Free the helper mpv process when idle.
quit_after_inactivity=45
EOF
    fi

    if (( WANT_SPONSORBLOCK )); then
        cat > "${MPV_OPTS_DIR}/sponsorblock.conf" <<'EOF'
# PRIVACY-HARDENED. Segments are requested with only the first 4 hex characters of
# sha256(video id) (k-anonymity: the server cannot tell which video of ~65k is meant).
sha256_length=4
# Do not tell the server about every skip (script default: yes).
report_views=no
auto_upvote=no
# No multi-GB local database download.
local_database=no
auto_update=no
server_fallback=yes
skip_categories=sponsor
make_chapters=yes
skip_once=yes
EOF
    fi
}

generate_mpv_configuration() {
    mkdir -p "$MPV_CONFIG_DIR" "$MPV_SCRIPTS_DIR" "$MPV_OPTS_DIR" "$MPV_FONTS_DIR" \
             "$MPV_WATCH_LATER_DIR" "$MPV_SCREENSHOT_DIR"
    write_mpv_conf
    write_input_conf
    write_script_opts
    log_success "mpv.conf, input.conf and script-opts written to ${MPV_CONFIG_DIR}"
}

#########################################################
# Addons
#########################################################
# Always the latest version: tagged release where a project publishes releases, otherwise the
# default branch. Downloads land in MPV_CURRENT_DOWNLOADS_DIR (on-access scanned by ClamAV).
# Any addon that fails to load is removed again by addon_health_check.

ADDON_FAILURES=0

# fetch_addon <name> <destination> <url>...   tries each URL in order
fetch_addon() {
    local name="$1" dest="$2" tmp url
    shift 2
    tmp="${MPV_CURRENT_DOWNLOADS_DIR}/${name}/$(basename "$dest")"
    for url in "$@"; do
        if download_file "$url" "$tmp"; then
            install -D -m 600 "$tmp" "$dest"
            return 0
        fi
    done
    log_warn "Could not install ${dest}"
    return 1
}

# Raw URLs for a GitHub project: its latest release tag first, then the default branch.
addon_urls() {  # addon_urls <owner/repo> <path-in-repo> -> prints URLs, best first
    local tag
    tag="$(github_latest_tag "$1")"
    if [[ -n "$tag" ]]; then github_raw_url "$1" "$tag" "$2"; fi
    github_raw_url "$1" "HEAD" "$2"
}

install_addon_autoload() {
    # mpv's own official script. The copy shipped with the distribution matches the installed mpv
    # exactly, so it is preferred; otherwise the script of the matching mpv release is downloaded.
    local system_copy="" candidate
    for candidate in /usr/share/mpv/scripts/autoload.lua /usr/share/mpv/lua/autoload.lua \
                     /usr/share/doc/mpv/autoload.lua /usr/share/doc/mpv/examples/lua/autoload.lua; do
        if [[ -r "$candidate" ]]; then system_copy="$candidate"; break; fi
    done
    if [[ -z "$system_copy" ]]; then
        system_copy="$(rpm -ql mpv mpv-libs 2>/dev/null | grep -E '/autoload\.lua$' | head -n1 || true)"
    fi
    if [[ -n "$system_copy" && -r "$system_copy" ]]; then
        install -D -m 600 "$system_copy" "${MPV_SCRIPTS_DIR}/autoload.lua"
        log_success "autoload.lua copied from the installed mpv package (${system_copy})"
        return 0
    fi
    fetch_addon autoload "${MPV_SCRIPTS_DIR}/autoload.lua" \
        "$(github_raw_url mpv-player/mpv "v${MPV_VERSION}" TOOLS/lua/autoload.lua)" \
        "$(github_raw_url mpv-player/mpv HEAD TOOLS/lua/autoload.lua)"
}

install_addon_modernz() {
    # ModernZ uses the 'escape-ass' command, added in mpv 0.38.
    if ! version_ge "$MPV_VERSION" 0.38; then
        log_warn "mpv ${MPV_VERSION} is older than 0.38: ModernZ skipped, the stock on-screen controller stays."
        return 0
    fi
    local -a lua_urls=() font_urls=()
    mapfile -t lua_urls  < <(addon_urls Samillion/ModernZ modernz.lua)
    mapfile -t font_urls < <(addon_urls Samillion/ModernZ modernz-icons.ttf)
    fetch_addon modernz "${MPV_SCRIPTS_DIR}/modernz.lua" "${lua_urls[@]}" \
        && fetch_addon modernz "${MPV_FONTS_DIR}/modernz-icons.ttf" "${font_urls[@]}"
}

install_addon_thumbfast() {
    local -a urls=()
    mapfile -t urls < <(addon_urls po5/thumbfast thumbfast.lua)
    fetch_addon thumbfast "${MPV_SCRIPTS_DIR}/thumbfast.lua" "${urls[@]}"
}

install_addon_sponsorblock() {
    # Unmaintained since 2023 but still works against the live API; privacy features are set in
    # sponsorblock.conf. Three files: the Lua entry point, a Lua helper and a Python helper.
    local base="po5/mpv_sponsorblock" u1 u2 u3
    mapfile -t u1 < <(addon_urls "$base" sponsorblock.lua)
    mapfile -t u2 < <(addon_urls "$base" sponsorblock_shared/main.lua)
    mapfile -t u3 < <(addon_urls "$base" sponsorblock_shared/sponsorblock.py)
    fetch_addon sponsorblock "${MPV_SCRIPTS_DIR}/sponsorblock.lua" "${u1[@]}" \
        && fetch_addon sponsorblock "${MPV_SCRIPTS_DIR}/sponsorblock_shared/main.lua" "${u2[@]}" \
        && fetch_addon sponsorblock "${MPV_SCRIPTS_DIR}/sponsorblock_shared/sponsorblock.py" "${u3[@]}" \
        && python3 -m py_compile "${MPV_SCRIPTS_DIR}/sponsorblock_shared/sponsorblock.py"
}

install_addon_skipsilence() {
    local -a urls=()
    mapfile -t urls < <(addon_urls ferreum/mpv-skipsilence skipsilence.lua)
    fetch_addon skipsilence "${MPV_SCRIPTS_DIR}/skipsilence.lua" "${urls[@]}"
}

install_addons() {
    install_addon_autoload || ADDON_FAILURES=$((ADDON_FAILURES + 1))
    install_addon_modernz  || ADDON_FAILURES=$((ADDON_FAILURES + 1))
    if (( WANT_THUMBFAST )); then
        install_addon_thumbfast || ADDON_FAILURES=$((ADDON_FAILURES + 1))
    else
        log_info "thumbfast skipped on this machine (needs RAM profile above low, an SSD and >= 4 CPUs)."
    fi
    if (( WANT_SPONSORBLOCK )); then
        install_addon_sponsorblock || ADDON_FAILURES=$((ADDON_FAILURES + 1))
    fi
    if (( WANT_SKIPSILENCE )); then
        install_addon_skipsilence || ADDON_FAILURES=$((ADDON_FAILURES + 1))
    else
        log_info "skipsilence skipped on this machine (low performance tier)."
    fi
    return 0
}

# addon_health_check: starts mpv once with the final configuration and removes every addon whose
# own log prefix reports an error (typically an API mismatch with the installed mpv), so a
# faulty addon can never leave the player half-broken. The stock controller returns if ModernZ goes.
addon_health_check() {
    local log name
    log="$(mktemp)"
    timeout 40 mpv --config-dir="$MPV_CONFIG_DIR" --no-terminal --keep-open=no --ytdl=no \
        --vo=null --ao=null --log-file="$log" --msg-level=all=warn --length=0.5 \
        'av://lavfi:testsrc=duration=2:size=320x240:rate=10' >/dev/null 2>&1 || true
    for name in modernz thumbfast sponsorblock sponsorblock_shared skipsilence autoload kde_dialogs; do
        if grep -qE "\]\[e\]\[${name}\]" "$log"; then
            log_warn "Addon '${name}' reported errors with mpv ${MPV_VERSION}; removing it:"
            grep -E "\]\[e\]\[${name}\]" "$log" | head -3 >&2 || true
            case "$name" in
                modernz)      rm -f "${MPV_SCRIPTS_DIR}/modernz.lua" "${MPV_FONTS_DIR}/modernz-icons.ttf" ;;
                sponsorblock|sponsorblock_shared) rm -rf "${MPV_SCRIPTS_DIR}/sponsorblock.lua" "${MPV_SCRIPTS_DIR}/sponsorblock_shared" ;;
                kde_dialogs)  rm -f "${MPV_SCRIPTS_DIR}/kde-dialogs.lua" ;;
                *)            rm -f "${MPV_SCRIPTS_DIR}/${name}.lua" ;;
            esac
            ADDON_FAILURES=$((ADDON_FAILURES + 1))
        fi
    done
    rm -f "$log"
    return 0
}

#########################################################
# Desktop integration
#########################################################
# KDE-specific parts (kdialog, KDE cache refresh) run only on a KDE session; the rest follows
# freedesktop standards and works on any desktop.

install_kde_dialogs() {
    if ! is_kde; then return 0; fi
    if ! command -v kdialog >/dev/null 2>&1; then
        log_warn "kdialog not found: native KDE file dialogs skipped."
        return 0
    fi
    # Our own, fully local script. Arguments go to kdialog as an argv ARRAY (never through a shell),
    # so file names or URLs cannot inject commands.
    cat > "${MPV_SCRIPTS_DIR}/kde-dialogs.lua" <<'LUA'
-- kde-dialogs.lua : native KDE pickers through kdialog.
--   Ctrl+o        open file(s)        Ctrl+n  open network URL (http, https, rtsp, mms)
--   Ctrl+Shift+o  add subtitle file
local utils = require "mp.utils"

local function kdialog(args, callback)
    local argv = { "kdialog" }
    for _, a in ipairs(args) do argv[#argv + 1] = a end
    mp.command_native_async({
        name = "subprocess", args = argv, capture_stdout = true, playback_only = false,
    }, function(success, res)
        if not success or not res or res.status ~= 0 or not res.stdout then return end  -- cancelled / no kdialog
        local out = res.stdout:gsub("%s+$", "")
        if out ~= "" then callback(out) end
    end)
end

local function start_dir()
    local p = mp.get_property("path")
    if p and not p:find("^%a[%w+.-]*://") then
        local dir = utils.split_path(p)
        if dir and dir ~= "" then return dir end
    end
    return os.getenv("HOME") or "/"
end

mp.add_key_binding("Ctrl+o", "open-file", function()
    kdialog({ "--title", "mpv: open media", "--multiple", "--separate-output",
              "--getopenfilename", start_dir(), "*|All files" }, function(out)
        local first = true
        for line in out:gmatch("[^\n]+") do
            mp.commandv("loadfile", line, first and "replace" or "append")
            first = false
        end
    end)
end)

mp.add_key_binding("Ctrl+n", "open-url", function()
    kdialog({ "--title", "mpv: open network stream", "--inputbox", "URL (http, https, rtsp, ...):", "" }, function(url)
        if url:find("^https?://%S+$") or url:find("^rtsps?://%S+$") or url:find("^mms://%S+$") then
            mp.commandv("loadfile", url, "replace")
        else
            mp.osd_message("Not a supported URL")
        end
    end)
end)

mp.add_key_binding("Ctrl+Shift+o", "add-subtitle", function()
    kdialog({ "--title", "mpv: add subtitle", "--getopenfilename", start_dir(),
              "*.srt *.ass *.ssa *.vtt *.sub|Subtitles" }, function(file)
        mp.commandv("sub-add", file)
        mp.osd_message("Subtitle added")
    end)
end)
LUA
    log_success "kde-dialogs.lua installed (Ctrl+o, Ctrl+n, Ctrl+Shift+o)"
}

install_mpris() {
    # The mpv-mpris RPM provides a C plugin. mpv only loads it from a scripts directory. If the
    # package already links it into /etc/mpv/scripts it is loaded system-wide (loading it a second
    # time from the user directory would register the player twice); otherwise it is linked into
    # the user's scripts directory.
    if ! rpm_is_installed mpv-mpris; then
        log_warn "mpv-mpris is not installed: no KDE media keys or KDE Connect control."
        return 0
    fi
    if [[ -e /etc/mpv/scripts/mpris.so ]]; then
        log_info "mpris.so is provided system-wide via /etc/mpv/scripts"
        return 0
    fi
    local so
    so="$(rpm -ql mpv-mpris 2>/dev/null | grep -E '/mpris\.so$' | grep -v '^/etc/' | head -n1 || true)"
    if [[ -n "$so" && -e "$so" ]]; then
        ln -sf "$so" "${MPV_SCRIPTS_DIR}/mpris.so"
        log_success "mpv-mpris linked: ${so}"
    else
        log_warn "mpv-mpris is installed but its mpris.so was not found."
    fi
    return 0
}

install_clipboard_launcher() {
    mkdir -p "$LOCAL_BIN" "$APPLICATIONS_DIR"
    chmod 755 "$LOCAL_BIN"
    # "Play clipboard URL in mpv": app menu and KRunner entry. Only http(s) URLs are accepted, and
    # mpv is started with '--' so clipboard text beginning with '-' can never become an option.
    cat > "$CLIPBOARD_LAUNCHER" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
url="$(wl-paste --no-newline 2>/dev/null || true)"
if [[ ! "$url" =~ ^https?://[^[:space:]]+$ ]]; then
    notify-send -a mpv "mpv" "Clipboard does not contain an http(s) URL." 2>/dev/null || true
    exit 1
fi
exec mpv --force-window=immediate -- "$url"
SH
    chmod 755 "$CLIPBOARD_LAUNCHER"
    cat > "${APPLICATIONS_DIR}/mpv-clipboard.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Play Clipboard URL in mpv
Comment=Play the video link currently in the clipboard
Exec=${CLIPBOARD_LAUNCHER}
Icon=mpv
Terminal=false
Categories=AudioVideo;Video;Player;
Keywords=mpv;clipboard;youtube;url;
EOF
    chmod 644 "${APPLICATIONS_DIR}/mpv-clipboard.desktop"
    log_success "Launcher 'Play Clipboard URL in mpv' installed (app menu / KRunner)"
}

install_tmpfiles_rule() {
    # systemd-tmpfiles removes resume files older than MPV_WATCH_LATER_MAX_AGE (a viewing history
    # should not live forever). "d" = create the directory if missing, then age-clean its contents.
    mkdir -p "$TMPFILES_USER_DIR"
    chmod 700 "$TMPFILES_USER_DIR"
    printf '# mpv resume files: prune entries older than %s\nd %s 0700 - - %s\n' \
        "$MPV_WATCH_LATER_MAX_AGE" "$MPV_WATCH_LATER_DIR" "$MPV_WATCH_LATER_MAX_AGE" > "${TMPFILES_USER_DIR}/mpv.conf"
    chmod 600 "${TMPFILES_USER_DIR}/mpv.conf"
    local help_text
    help_text="$(systemd-tmpfiles --help 2>&1 || true)"
    if ! command -v systemd-tmpfiles >/dev/null 2>&1; then
        log_warn "systemd-tmpfiles not found; resume files will not be pruned."
    elif ! grep -q -- '--dry-run' <<<"$help_text"; then
        log_info "tmpfiles rule written (this systemd cannot dry-run it)."
    elif systemd-tmpfiles --user --dry-run --clean "${TMPFILES_USER_DIR}/mpv.conf" >/dev/null 2>&1; then
        log_success "tmpfiles rule valid: watch_later pruned after ${MPV_WATCH_LATER_MAX_AGE}"
    else
        log_warn "tmpfiles rule failed validation; resume files will not be pruned."
    fi
}

#########################################################
# MIME defaults
#########################################################
# Video types ONLY (audio files keep their current player). The list is what the installed
# mpv.desktop declares for video/*, plus a few video containers that live under application/*.

mpv_desktop_file() {
    local candidate
    for candidate in "/usr/share/applications/${MPV_DESKTOP_ID}" "/usr/local/share/applications/${MPV_DESKTOP_ID}" \
                     "${APPLICATIONS_DIR}/${MPV_DESKTOP_ID}"; do
        if [[ -r "$candidate" ]]; then printf '%s\n' "$candidate"; return 0; fi
    done
    return 0
}

compute_video_mime_types() {
    local desktop_file
    desktop_file="$(mpv_desktop_file)"
    {
        if [[ -n "$desktop_file" ]]; then
            sed -n 's/^MimeType=//p' "$desktop_file" | tr ';' '\n' | grep -E '^video/' || true
        fi
        printf '%s\n' "${MPV_EXTRA_VIDEO_MIME_TYPES[@]}"
    } | sort -u
}

set_mime_defaults() {
    if [[ -z "$(mpv_desktop_file)" ]]; then
        log_warn "${MPV_DESKTOP_ID} not found: MIME defaults skipped."
        return 0
    fi
    mapfile -t MIME_TYPES < <(compute_video_mime_types)
    # Python helper: sets the only default, removes blacklisting entries, preserves everything else.
    mimeapps_set_default "$MPV_DESKTOP_ID" "${MIME_TYPES[@]}"
    mkdir -p "$APPLICATIONS_DIR"
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
    fi
    if is_kde && command -v kbuildsycoca6 >/dev/null 2>&1; then
        kbuildsycoca6 --noincremental >/dev/null 2>&1 || true    # refresh KDE's application cache
    fi
    log_success "${MPV_DESKTOP_ID} is now the default for ${#MIME_TYPES[@]} video MIME types (audio untouched)"
}

integration_hints() {
    if is_kde; then
        if rpm_is_installed kdeconnectd || command -v kdeconnect-cli >/dev/null 2>&1; then
            log_info "KDE Connect is installed: enable 'Pause media during calls' for the phone; the phone's multimedia remote controls mpv through MPRIS."
        fi
        log_info "Optional Klipper action (manual): Clipboard settings -> Actions -> command  mpv -- %s"
    fi
}

#########################################################
# Permissions and manifest
#########################################################

apply_permissions() {
    local group
    group="$(id -gn "$REAL_USER")"
    find "$MPV_CONFIG_DIR" -type d -exec chmod 700 {} +
    find "$MPV_CONFIG_DIR" -type f -exec chmod 600 {} +
    chown -R "${REAL_USER}:${group}" "$MPV_CONFIG_DIR" "$MPV_STATE_DIR" "$MPV_CURRENT_BACKUP_DIR" "$MPV_CURRENT_DOWNLOADS_DIR"
    chmod 700 "$MPV_STATE_DIR" "$MPV_WATCH_LATER_DIR"
    if [[ -x "$YTDLP_BIN" && "$YTDLP_BIN" == "${LOCAL_BIN}/"* ]]; then chmod 755 "$YTDLP_BIN"; fi
    chmod 755 "$CLIPBOARD_LAUNCHER"
    log_success "Ownership (${REAL_USER}:${group}) and permissions applied"
}

# The manifest records what this run installed, so --verify-setup can check against intent.
write_manifest() {
    local addons="" name
    for name in modernz autoload kde-dialogs thumbfast sponsorblock skipsilence; do
        if [[ -e "${MPV_SCRIPTS_DIR}/${name}.lua" ]]; then addons+="${name} "; fi
    done
    {
        echo "SETUP_TIMESTAMP=${FILENAME_TIMESTAMP}"
        echo "MPV_VERSION=${MPV_VERSION}"
        echo "PERF_TIER=${PERF_TIER}"
        echo "HWDEC_LIST=${HWDEC_LIST}"
        echo "DECODE_DESC=${DECODE_DESC}"
        echo "ADDONS=${addons% }"
        echo "MIME_TYPES=$(array_join_space "${MIME_TYPES[@]:-}")"
        echo "BACKUP_DIR=${MPV_CURRENT_BACKUP_DIR}"
    } > "$MPV_MANIFEST"
    chmod 600 "$MPV_MANIFEST"
}

#########################################################
# Verification
#########################################################
# Self-check of the finished setup; run alone with --verify-setup. Judges the CURRENT state of the
# machine against what the last setup run recorded in the manifest.

VERIFY_FAILS=0
verify_ok()   { log_success "$1"; }
verify_warn() { log_warn "$1"; }
verify_fail() { log_error "$1"; VERIFY_FAILS=$((VERIFY_FAILS + 1)); }

manifest_value() { sed -n "s/^$1=//p" "$MPV_MANIFEST" 2>/dev/null | head -n1 || true; }

verify_setup() {
    log_header "Verification"
    VERIFY_FAILS=0
    local log version bad f

    # --- installation and configuration files
    if command -v mpv >/dev/null 2>&1; then
        version="$(mpv --version | awk 'NR==1 {print $2}')"; verify_ok "mpv ${version#v} installed"
    else
        verify_fail "mpv is not installed"; return 1
    fi
    for f in mpv.conf input.conf; do
        if [[ -s "${MPV_CONFIG_DIR}/${f}" ]]; then verify_ok "${f} present"; else verify_fail "${f} missing in ${MPV_CONFIG_DIR}"; fi
    done
    if [[ -s "$MPV_MANIFEST" ]]; then verify_ok "setup manifest present (tier $(manifest_value PERF_TIER))"
    else verify_warn "no setup manifest: run the setup once"; fi
    if [[ -e "${HOME_DIR}/.mpv" ]]; then verify_fail "legacy ${HOME_DIR}/.mpv exists and would shadow the XDG config"; fi

    # --- ownership and permissions: nothing in the config may be readable by group/other
    bad="$(find "$MPV_CONFIG_DIR" \( -perm /077 -o ! -user "$REAL_USER" \) ! -type l 2>/dev/null | head -n3 || true)"
    if [[ -z "$bad" ]]; then verify_ok "config ownership and permissions are private"
    else verify_fail "loose permissions or wrong owner: $(echo "$bad" | tr '\n' ' ')"; fi

    # --- mpv starts with the configuration; no option or script errors
    log="$(mktemp)"
    if timeout 40 mpv --config-dir="$MPV_CONFIG_DIR" --no-terminal --keep-open=no --ytdl=no --vo=null --ao=null \
        --log-file="$log" --msg-level=all=warn --length=0.5 'av://lavfi:testsrc=duration=2:size=320x240:rate=10' >/dev/null 2>&1; then
        verify_ok "mpv starts and plays with the generated configuration"
    else
        verify_fail "mpv failed to start with the configuration"; tail -8 "$log" >&2
    fi
    if grep -Eiq 'error parsing|unknown option|option not found|invalid value|lua error|failed to (load|run)|Error loading|\]\[e\]\[' "$log"; then
        verify_fail "mpv reports option or script errors:"
        grep -Ei 'error parsing|unknown option|option not found|invalid value|lua error|failed to|Error loading|\]\[e\]\[' "$log" | head -8 >&2
    else
        verify_ok "no option or script errors in mpv's log"
    fi
    rm -f "$log"

    # --- codecs and hardware decoding
    local vd_list ad_list
    vd_list="$(mpv --no-config --vd=help 2>/dev/null || true)"; ad_list="$(mpv --no-config --ad=help 2>/dev/null || true)"
    if grep -Eqi 'hevc' <<<"$vd_list" && grep -Eqi 'aac' <<<"$ad_list"; then verify_ok "HEVC and AAC decoders present"
    else verify_fail "HEVC/AAC decoders missing: full ffmpeg (not ffmpeg-free) must be installed"; fi
    verify_hwdec_runtime

    # --- yt-dlp and its JavaScript runtime
    local ytdlp js_arg js_path
    ytdlp="$(sed -n 's/^ytdl_path=//p' "${MPV_OPTS_DIR}/ytdl_hook.conf" 2>/dev/null | head -n1 || true)"
    if [[ -n "$ytdlp" && -x "$ytdlp" ]] && "$ytdlp" --version >/dev/null 2>&1; then verify_ok "yt-dlp $("$ytdlp" --version) runs (${ytdlp})"
    else verify_fail "yt-dlp is missing or does not run (ytdl_path='${ytdlp}')"; fi
    js_arg="$(sed -n 's/^ytdl-raw-options-append=js-runtimes=//p' "${MPV_CONFIG_DIR}/mpv.conf" 2>/dev/null | head -n1 || true)"
    if [[ -n "$js_arg" ]]; then
        js_path="${js_arg#*:}"
        if [[ -x "$js_path" ]]; then verify_ok "JavaScript runtime executable: ${js_arg}"; else verify_fail "JavaScript runtime not executable: ${js_arg}"; fi
    else
        verify_warn "no JavaScript runtime configured: YouTube playback may fail"
    fi

    # --- addons recorded by the setup must still be present
    local addon
    local -a addon_list=()
    IFS=' ' read -r -a addon_list <<<"$(manifest_value ADDONS)"
    for addon in "${addon_list[@]:-}"; do
        [[ -n "$addon" ]] || continue
        if [[ -s "${MPV_SCRIPTS_DIR}/${addon}.lua" ]]; then verify_ok "addon ${addon} present"; else verify_fail "addon ${addon} missing"; fi
    done

    # --- MPRIS on the session bus. Started WITHOUT --config-dir on purpose: that option makes mpv
    #     ignore /etc/mpv, where the mpv-mpris RPM may install mpris.so.
    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && command -v busctl >/dev/null 2>&1; then
        local mpris_log pid bus_list
        mpris_log="$(mktemp)"
        mpv --idle=yes --force-window=no --no-terminal --vo=null --ao=null --log-file="$mpris_log" --msg-level=all=v >/dev/null 2>&1 &
        pid=$!
        sleep 3
        bus_list="$(busctl --user --no-pager list 2>/dev/null || true)"
        if grep -q 'org.mpris.MediaPlayer2.mpv' <<<"$bus_list"; then
            verify_ok "MPRIS registered on D-Bus (KDE media keys / KDE Connect see mpv)"
        else
            verify_fail "MPRIS did not register; mpv's log says:"
            { grep -i -E 'mpris|cplugin|c plugin|\.so' "$mpris_log" | head -6 || true; } >&2
        fi
        kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
        rm -f "$mpris_log"
    else
        log_info "No D-Bus session available: MPRIS check skipped."
    fi

    # --- MIME defaults (video only)
    local -a types=()
    IFS=' ' read -r -a types <<<"$(manifest_value MIME_TYPES)"
    if (( ${#types[@]} == 0 )); then mapfile -t types < <(compute_video_mime_types); fi
    if (( ${#types[@]} )); then
        bad="$(mimeapps_check_default "$MPV_DESKTOP_ID" "${types[@]}" 2>/dev/null || true)"
        if [[ -z "$bad" ]]; then verify_ok "${MPV_DESKTOP_ID} is the default for all ${#types[@]} video MIME types"
        else verify_fail "not defaulting to mpv: $(echo "$bad" | tr '\n' ' ')"; fi
    fi

    # --- desktop and system integration
    if [[ -x "$CLIPBOARD_LAUNCHER" && -s "${APPLICATIONS_DIR}/mpv-clipboard.desktop" ]]; then verify_ok "clipboard launcher installed"
    else verify_fail "clipboard launcher missing"; fi
    if command -v desktop-file-validate >/dev/null 2>&1; then
        if desktop-file-validate "${APPLICATIONS_DIR}/mpv-clipboard.desktop" >/dev/null 2>&1; then verify_ok "launcher .desktop file is valid"
        else verify_warn "desktop-file-validate reported issues for mpv-clipboard.desktop"; fi
    fi
    if [[ -s "${TMPFILES_USER_DIR}/mpv.conf" ]]; then verify_ok "watch_later pruning rule present"; else verify_fail "tmpfiles rule missing"; fi
    local backup_dir
    backup_dir="$(manifest_value BACKUP_DIR)"
    if [[ -n "$backup_dir" ]]; then
        if [[ -d "$backup_dir" ]]; then verify_ok "backup exists: ${backup_dir}"; else verify_warn "backup directory no longer exists: ${backup_dir}"; fi
    fi

    if (( VERIFY_FAILS == 0 )); then log_success "Verification passed"; else log_error "Verification found ${VERIFY_FAILS} problem(s)"; fi
    return $(( VERIFY_FAILS > 0 ? 1 : 0 ))
}

# verify_hwdec_runtime: really decodes a short H.264 clip with the configured hardware API.
# "-copy" variants are used because they work without a window (vo=null).
verify_hwdec_runtime() {
    local list first api tmpdir out
    list="$(sed -n 's/^hwdec=//p' "${MPV_CONFIG_DIR}/mpv.conf" 2>/dev/null | head -n1 || true)"
    first="${list%%,*}"
    case "$first" in
        vaapi|nvdec) api="${first}-copy" ;;
        *) log_info "Hardware decoding: none configured (software); runtime test skipped."; return 0 ;;
    esac
    if ! command -v ffmpeg >/dev/null 2>&1; then verify_warn "ffmpeg missing: hardware decode runtime test skipped"; return 0; fi
    tmpdir="$(mktemp -d)"
    if ffmpeg -v error -f lavfi -i testsrc=size=640x360:rate=25:duration=2 -c:v libx264 -pix_fmt yuv420p "${tmpdir}/t.mp4" 2>/dev/null; then
        out="$(timeout 40 mpv --no-config --vo=null --ao=null --hwdec="$api" --msg-level=vd=v --length=1 "${tmpdir}/t.mp4" 2>&1 || true)"
        if grep -qi 'Using hardware decoding' <<<"$out"; then verify_ok "hardware decoding works (${api})"
        else verify_warn "hardware decoding via ${api} did not engage (software decoding is used); see Troubleshooting"; fi
    else
        verify_warn "no H.264 encoder in ffmpeg: hardware decode runtime test skipped"
    fi
    rm -rf "$tmpdir"
    return 0
}

#########################################################
# Main
#########################################################

print_summary() {
    log_header "Summary"
    cat <<EOF
  Config      : ${MPV_CONFIG_DIR}
  Backup      : ${MPV_CURRENT_BACKUP_DIR} (see RESTORE.txt there)
  Tier/decoder: ${PERF_TIER} / ${DECODE_DESC}
  Addons      : $(manifest_value ADDONS)
  Keys        : Ctrl+o open file | Ctrl+n open URL | Ctrl+Shift+o subtitles | n loudnorm | i statistics
  Try         : mpv some-video.mkv  (press i: 'hwdec' should show the hardware API)
  YouTube     : yt-dlp breaks every few weeks; run  yt-dlp -U  when streams fail.
  Android     : mpv-android (F-Droid) plays the same files; KDE Connect's multimedia remote controls mpv here.
EOF
}

main() {
    ensure_real_user "$@"          # re-runs as the real user when started with sudo
    parse_named_options "$@"
    log_header "mpv setup"
    infer_paths
    infer_system_variables

    if (( VERIFY_ONLY )); then
        local rc=0
        verify_setup || rc=$?
        exit "$rc"
    fi

    log_header "Pre-flight"
    validate_environment
    print_hardware_summary

    log_header "Backup"
    backup_existing_setup
    mkdir -p "$MPV_CURRENT_DOWNLOADS_DIR"
    chmod 700 "$MPV_CURRENT_DOWNLOADS_DIR"

    # Packages first: if dnf fails (network, repositories), the existing setup is still untouched.
    log_header "Packages"
    install_packages

    log_header "Reset"
    reset_existing_setup

    log_header "yt-dlp and JavaScript runtime"
    install_ytdlp
    select_js_runtime

    log_header "Decoder probe"
    infer_decoder_variables

    log_header "Configuration"
    generate_mpv_configuration

    log_header "Addons"
    install_addons
    install_kde_dialogs
    install_mpris
    addon_health_check

    log_header "Desktop integration"
    install_clipboard_launcher
    install_tmpfiles_rule
    set_mime_defaults
    integration_hints

    log_header "Permissions"
    apply_permissions
    write_manifest

    local rc=0
    verify_setup || rc=$?
    print_summary
    if (( rc != 0 || ADDON_FAILURES > 0 )); then
        log_warn "Finished WITH problems (verification failures: ${VERIFY_FAILS}, addon problems: ${ADDON_FAILURES}). Read the messages above."
        exit 1
    fi
    log_success "All checks passed."
}

main "$@"
exit 0

#########################################################
# Notes
#########################################################
# DESIGN DECISIONS
#   * Tiers (low/mid/high). The GPU tier comes from get_gpu_tier.sh, then one step is subtracted
#     when fewer than 4 logical CPUs exist. The tier selects the renderer order, scalers,
#     video-sync mode and whether frame blending is used; it does not change what is safe.
#   * hwdec is a priority LIST ("vaapi,vaapi-copy,auto"). vaapi = zero-copy; vaapi-copy = copies
#     frames back (works when zero-copy interop fails); auto = mpv's whitelist of safe APIs.
#     mpv falls back to software decoding by itself, so a broken driver never stops playback.
#   * VA-API driver choice (Debian/Arch/RPM Fusion agree): iHD (intel-media-driver) for Broadwell
#     and newer, i965 (libva-intel-driver) for GMA 4500 .. Coffee Lake. libva tries iHD first and
#     falls back to i965, so an unknown generation installs both.
#   * Hybrid Intel+NVIDIA laptops decode and render on the Intel iGPU: the compositor lives
#     there, and NVIDIA would need PRIME offload (battery, complexity). NVDEC is used only when the
#     NVIDIA card is the sole GPU and runs the proprietary driver. VDPAU is not used: it does not
#     work on Wayland.
#   * AMD: Fedora's Mesa has the H.264/HEVC/VC-1 VA-API codecs removed; mesa-va-drivers-freeworld
#     restores them. On Fedora 44 it installs alongside the stock driver (the package
#     mesa-va-drivers no longer exists); on older releases it replaces it, which transaction B handles.
#   * Streamed video: ytdl-format is computed per machine. YouTube serves AV1, VP9 and H.264; the
#     list below drops codecs the hardware cannot decode, because software AV1/VP9 on an old CPU
#     stutters. Height is capped by tier, lowered without hardware decode or with little RAM.
#   * Latest versions, no pins: addons come from the latest GitHub release tag (or the default
#     branch for projects without releases), yt-dlp from the latest release. Trade-off accepted:
#     a compromised upstream would be installed. Mitigations: HTTPS only, HTML/empty-download
#     rejection, ClamAV on-access scanning of the downloads directory, the yt-dlp checksum file,
#     and addon_health_check, which removes any addon that errors with the installed mpv.
#   * autoload.lua: the copy shipped in the mpv package is used when present (exact match to the
#     installed mpv); else the script of the SAME mpv release is downloaded, else the default branch.
#   * yt-dlp is the official build, not the RPM: the RPM ships without the EJS solver
#     (bugzilla 2476441) and lags upstream. The binary is called by absolute path from
#     ytdl_hook.conf because GUI-launched mpv may lack ~/.local/bin in PATH.
#   * script-opts: one file per script in script-opts/. Repeating `script-opts=` in mpv.conf
#     REPLACES the previous value each time, so only the last line would take effect.
#   * resume files are kept by the reset step (user data), and pruned by an age rule.
#
# PRIVACY AND SECURITY CHOICES THAT CAN BREAK FUNCTIONALITY (each can be changed)
#   1. TLS verification (MPV_TLS_VERIFY=yes). mpv's own default differs between builds and may be
#      off. With "yes", HTTPS servers with self-signed certificates fail, e.g. a LAN Jellyfin or
#      Nextcloud. Recommendation: keep "yes"; give the server a real certificate (Tailscale
#      certificates, Let's Encrypt) or override once: mpv --tls-verify=no URL. Setting "no" globally
#      allows silent man-in-the-middle substitution of streams.
#   2. SponsorBlock (MPV_INSTALL_SPONSORBLOCK=yes). Convenience: skips sponsor segments on
#      YouTube. Cost: a request to sponsor.ajay.app per video containing only the first 4 hex
#      characters of sha256(video id) (k-anonymity), no skip reporting, no database download,
#      submission keys disabled. The script is unmaintained since 2023. Recommendation: "yes" only
#      if skipping is wanted; "no" removes the third-party contact entirely.
#   3. JavaScript runtime. YouTube needs one. yt-dlp runs Node inside Node's permission sandbox,
#      Deno with no permissions; QuickJS has weaker isolation. Preference: deno > node >= 22 >
#      quickjs. Remote solver downloads (--remote-components) are NOT enabled.
#   4. User-Agent. A generic browser identity avoids the unique "libmpv" fingerprint; a forged
#      Referer is deliberately not sent. Some sites that sniff browsers may behave differently.
#   5. No browser cookies for yt-dlp (age-restricted videos then fail). Opt in per run with
#      --ytdl-raw-options=cookies-from-browser=librewolf.
#   6. No IPC socket, no persistent file names in resume files, cache only in RAM, thumbnails not
#      generated for network streams.
#
# SECURITY SECTION OMITTED
#   mpv is a pure client: it opens no listening socket (the IPC server is off), so no firewalld
#   rule is needed. It runs unconfined as the user without SELinux denials in normal use. Its
#   downloads go to the on-access scanned directory, so no ClamAV inclusion/exclusion is needed.
#
# INTEGRATIONS
#   * NextDNS: mpv, ffmpeg and yt-dlp resolve names through glibc and therefore systemd-resolved;
#     none can speak DNS-over-HTTPS itself, so there is no per-application device ID to set. mpv
#     appears under the machine's existing NextDNS device.
#   * Syncthing: the generated configuration is tuned per machine; syncing it would overwrite the
#     tuning. Resume positions are keyed by file path hashes and only make sense for identical paths.
#   * Android: mpv-android (F-Droid) for playback; KDE Connect's multimedia remote controls this mpv
#     through MPRIS. Brave/LibreWolf "open in mpv" extensions can pass URLs to the clipboard launcher.
#   * Flatpak mpv would be more strongly sandboxed, but codecs, hardware decoding, yt-dlp and
#     MPRIS then need extra permissions and extensions; the native package was chosen deliberately.
#
# REPLACED APPROACHES (earlier revisions of this setup)
#   * Hand-written autoload.lua: appended only files after the current one, in directory order.
#     The official script also loads earlier files, sorts naturally, skips hidden files.
#   * `script-opts=` lines for ModernZ/thumbfast with invented prefixes (modern-osc-*, thumbfast-width):
#     those option names do not exist; ModernZ reads modernz.conf (layout, icon_theme, font,
#     jump_amount...), thumbfast reads thumbfast.conf (max_width, max_height, network...).
#   * ytdlautoformat.lua: switched formats per site at run time; replaced by a computed ytdl-format
#     and three profiles (ytdl-720p, ytdl-1080p, ytdl-best).
#   * sub-reload.lua and a subtitle-downloader script: replaced by kdialog pickers; online subtitle
#     services need accounts or leak file hashes, so none is installed.
#   * po5/auto-profiles.lua: mpv has built-in automatic profiles ([protocol.http], [extension.mkv],
#     profile-cond=...), so no addon is needed.
#   * `dnf swap mesa-va-drivers ...`, `dnf groupupdate`, `dnf config-manager --set-enabled`: removed
#     or changed in DNF5/Fedora 44; plain `dnf install` with filtered package lists is used.
#   * `libva-nvidia-driver`/`vainfo` packages: mpv uses NVDEC directly; the tool is in libva-utils.
#   * xdg-mime default: replaced by helper_mimeapps.py (see that file for the reasons).
#   * mpv-mpris "installed, nothing to do": nothing loads the plugin until it sits in a scripts dir.
#   * Hardcoded gpu-context=wayland/waylandvk: breaks X11 sessions; automatic selection is used.
#   * Pinned commits with SHA-256 per addon file (an intermediate revision): removed on request;
#     the latest versions are installed instead.
#
# MPV BASICS (for readers new to mpv)
#   * "~~/" in mpv paths is the configuration directory (~/.config/mpv). Scripts in ~~/scripts/
#     load automatically; fonts in ~~/fonts/ are available to the on-screen display.
#   * Options set in mpv.conf can be overridden on the command line (mpv --hwdec=no FILE).
#   * Lines in mpv.conf after a [name] header belong to that profile (applied with --profile=name,
#     or automatically for built-in names such as protocol.https).
#   * mpv.conf: a list option written twice REPLACES the earlier line unless "-append" is used.
#     That is why per-script settings live in script-opts/*.conf.

#########################################################
# Troubleshooting/Debugging
#########################################################
# RE-CHECK EVERYTHING
#   bash linux/mpv_setup.sh --verify-setup
#
# MPV ITSELF
#   mpv --no-config FILE                       is it the configuration? (no config at all)
#   mpv -v FILE 2>&1 | less                    verbose log; look for [e] (error) and [w] lines
#   mpv --log-file=/tmp/mpv.log FILE           keep the log for later
#   mpv --msg-level=all=trace,ytdl_hook=trace URL   trace the yt-dlp hook
#   mpv --list-options | grep -i NAME          does this mpv know the option, and its default?
#   mpv --show-profile=high-quality            what a built-in profile sets
#   mpv --vo=help ; mpv --hwdec=help ; mpv --gpu-api=help ; mpv --ao=help
#   In the player: i = statistics (page 1: "hwdec"/"Hardware decoding"; 2-4 more pages),
#   Ctrl+h cycles hardware decoding on/off, ` (backtick) opens the console.
#   After the first run: error "Error parsing option X" = a name or value this mpv version does not
#   have; the option reference of the installed version is `man mpv`.
#
# HARDWARE DECODING
#   vainfo                                     lists profiles; "VAEntrypointVLD" = decode support
#   vainfo --display drm --device /dev/dri/renderD128   pick a specific GPU (try renderD129 ...)
#   LIBVA_DRIVER_NAME=iHD vainfo ; LIBVA_DRIVER_NAME=i965 vainfo    force one Intel driver
#   LIBVA_MESSAGING_LEVEL=2 vainfo             libva's own diagnostics
#   mpv --hwdec=vaapi -v FILE 2>&1 | grep -i -E "hwdec|vaapi"      what happened on load
#   mpv --hwdec=vaapi-copy FILE                works when zero-copy interop fails
#   intel_gpu_top (intel-gpu-tools) / nvidia-smi dmon / radeontop      is the GPU actually busy?
#   sh linux/common/get_vaapi_codecs.sh ; sh linux/common/get_gpu_tier.sh   what the setup saw
#   vulkaninfo --summary                       is Vulkan available at all (old GPUs: no)
#   Wayland vs X11: echo $XDG_SESSION_TYPE
#   NVIDIA proprietary + Wayland: needs the nvidia-drm.modeset=1 kernel parameter (RPM Fusion sets it).
#   Codecs missing (HEVC/AAC): rpm -q ffmpeg ffmpeg-free ; sudo dnf install --allowerasing ffmpeg
#
# YT-DLP / YOUTUBE
#   yt-dlp --version ; yt-dlp -U               update; do this FIRST when YouTube stops working
#   yt-dlp -v --js-runtimes node:/usr/bin/node -F URL    list formats with the runtime in use
#   "n challenge solving failed" / "Signature solving failed"   no JS runtime, or one older than required
#   node --version                             needs >= 22
#   mpv --ytdl-raw-options=cookies-from-browser=librewolf URL   age-restricted videos (opt-in)
#   mpv --profile=ytdl-720p URL                lower quality on a slow link
#   Fedora's yt-dlp RPM is NOT used; `which -a yt-dlp` shows every copy on PATH.
#
# ADDONS
#   ls ~/.config/mpv/scripts ~/.config/mpv/script-opts
#   mpv -v FILE 2>&1 | grep -E "\[(modernz|thumbfast|sponsorblock|autoload|skipsilence|kde_dialogs)\]"
#   An addon that errors is removed by the setup; re-run the setup after upgrading mpv to retry it.
#   Stock controller back: delete scripts/modernz.lua (ModernZ switches the stock one off itself).
#
# INTEGRATION
#   busctl --user list | grep mpris            player visible on D-Bus (KDE media keys)
#   ls -l /etc/mpv/scripts ~/.config/mpv/scripts    where mpris.so is loaded from; never both
#   NOTE: `mpv --config-dir=...` makes mpv ignore /etc/mpv, so a plugin installed there is not loaded.
#   xdg-mime query default video/mp4           which application the system thinks is the default
#   gio mime video/mp4                         same question through GIO
#   python3 linux/common/helper_mimeapps.py get-default --mime-type video/mp4 --file ~/.config/mimeapps.list
#   kbuildsycoca6 --noincremental              refresh KDE's application cache after MIME changes
#   systemd-tmpfiles --user --clean --dry-run  what the resume-file pruning would delete
#   systemctl --user list-timers | grep tmpfiles   is the clean-up timer active
#   Dolphin shows no video thumbnails: install ffmpegthumbs, then enable Video in Dolphin > Configure > General > Previews.
#
# PACKAGES AND ROLLBACK
#   sudo dnf history list | head ; sudo dnf history info <ID> ; sudo dnf history undo <ID>
#   dnf repolist --enabled | grep -i rpmfusion ; rpm -q rpmfusion-free-release rpmfusion-nonfree-release
#   dnf repoquery --available 'mesa-va-drivers*'        which Mesa VA-API packages exist on this release
#   rpm -V mpv                                 verify installed files against the RPM
#
# SECURITY CHECKS
#   sudo ausearch -m avc -ts recent | grep -i mpv       SELinux denials (none expected)
#   ss -tulpn | grep mpv                       must print nothing: mpv opens no listening socket
#
# RESTORING THE PREVIOUS STATE
#   cat ~/nb/nb_script_data/backups/mpv/<newest>/RESTORE.txt
