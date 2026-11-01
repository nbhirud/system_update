#!/usr/bin/env bash
##########################################################################
# fonts.sh - install Nerd Fonts for ONE user on Fedora (KDE or GNOME)
#
# Installs the font families listed in FONT_LIST (edit it below, in this file)
# into ~/.local/share/fonts/nerd-fonts using ONE of three download
# methods, chosen by DOWNLOAD_METHOD below (or --method on the command line):
#
#   archive - download only the per-font release archive (<Font>.tar.xz) and
#             verify it against the release's SHA-256.txt.   FASTEST, and the
#             only method that has a checksum check. (default)
#   sparse  - git partial+sparse clone of the release tag; only the
#             patched-fonts/<Font> folders you listed are fetched.
#   full    - shallow (depth 1) clone of the release tag, everything.
#             SLOWEST (the repo is multi-GB; Noto alone is ~1.1 GB).
#
# Design rules (see the "Why" notes next to each section):
#   * One failing font NEVER stops the run. It is logged and skipped.
#   * Only the CONFIG files we modify are backed up (not the fonts: they are
#     GBs). Downloads are deleted as soon as the new fonts are in place.
#   * New fonts are built in a staging folder and swapped in only at the end,
#     so a failed run can never leave you with an empty fonts folder.
#   * Everything is reported at the end: log_success list + log_error list.
#
# Usage:
#   bash linux/common/fonts.sh                       # defaults
#   bash linux/common/fonts.sh --method sparse
#   bash linux/common/fonts.sh --version v3.5.1 --no-default-fonts
#   bash linux/common/fonts.sh --help
#
# Exit codes: 0 = everything OK, 1 = finished but something failed, 2 = fatal.
##########################################################################

# This script uses bash features (arrays, [[ ]], ${var,,}). Your old header
# said it had been run as `sh fonts.sh`; on Fedora `sh` is bash in POSIX mode,
# where some of these features are disabled. So: if we were started by a
# different shell, re-run ourselves under bash.
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

# Why NOT `set -e` (your old script used `set -eux`):
#   -e makes the whole script die on the first failing command, which is the
#   opposite of "skip the font that failed and continue". We check the
#   commands that matter ourselves.
# Why NOT `-x`: it prints every command (including noisy loops) to the screen.
#   Run `DEBUG=1 bash fonts.sh` if you want it.
#   -u : using an unset variable is an error (catches typos like $DEST_DRI)
#   -o pipefail : a pipeline fails if ANY command in it fails, not just the last
set -uo pipefail
[ "${DEBUG:-0}" = "1" ] && set -x

##########################################################################
# >>>>>>>>>>>>>>>>>>>>>>>>  THE MAIN SWITCH  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
##########################################################################
# Choose exactly one: "archive" | "sparse" | "full"
# (can be overridden at run time with --method)
DOWNLOAD_METHOD="archive"

##########################################################################
# Settings
##########################################################################

# Delete downloaded intermediate data (git clone, archives) when finished.
# Leave this true: the data is GBs and can always be downloaded again.
CLEANUP_DELETE_LATER=true

# The fonts to install: edit this list. One Nerd Fonts family name per line,
# exactly as named in the release (the archive is <Name>.tar.xz and the repo
# folder is patched-fonts/<Name>). Lines starting with # are ignored.
# Names are validated (letters, digits, . _ - only) before they are used in
# URLs and paths. Duplicates are ignored.
FONT_LIST=(
    CascadiaCode
    CascadiaMono
    CodeNewRoman
    ComicShannsMono
    FiraCode
    FiraMono
    GoogleSansCode
    Hack
    IBMPlexMono
    Inconsolata
    InconsolataGo
    InconsolataLGC
    IntelOneMono
    JetBrainsMono
    Meslo
    NerdFontsSymbolsOnly
    Noto
    RobotoMono
    SourceCodePro
    Ubuntu
    UbuntuMono
    UbuntuSans
)

# Apply the Nerd Font UI / monospace fonts to the desktop at the end.
SET_DEFAULT_FONTS=true

# Which Nerd Fonts release to use:
#   "latest"  -> resolved at run time from GitHub's /releases/latest redirect
#   "v3.5.1"  -> pin an exact release (reproducible; same bytes on every PC)
# All three methods use the SAME release, so they give the same fonts.
NF_VERSION="latest"
# Used only if "latest" cannot be resolved (offline GitHub API, etc.).
NF_VERSION_FALLBACK="v3.5.1"

# Security: refuse to install an archive whose SHA-256 we cannot verify.
# (archive method only; the git methods rely on git's own object hashing.)
# Set to false only if you knowingly want to install unverified archives.
REQUIRE_CHECKSUM=true

# If the git methods (full/sparse) cannot find a font folder in the repo,
# try that single font via the verified archive instead of failing it.
FALLBACK_TO_ARCHIVE=true

# If a font fails to download this time but an older copy is installed, keep
# the older copy instead of deleting it. (Fonts are NOT backed up, so this is
# what protects you from losing a font because of a bad download.)
KEEP_OLD_COPY_ON_FAILURE=true

# How many timestamped config backups (small files) to keep.
KEEP_BACKUPS=5

# Desktop font choices. These are *family names as fontconfig sees them*.
# The script checks they are really installed before applying them
# (find the exact name with:  fc-list : family | sort -u | grep -i noto )
KDE_UI_FONT_FAMILY="NotoSans Nerd Font"
KDE_UI_FONT_SIZE=10
GNOME_UI_FONT_FAMILY="Ubuntu Nerd Font"
GNOME_UI_FONT_SIZE=11
MONO_FONT_FAMILY="JetBrainsMono Nerd Font"
KDE_MONO_FONT_SIZE=10
GNOME_MONO_FONT_SIZE=10

KEEP_WORK_DIR=false   # --keep-work-dir : keep downloads for debugging
DEST_DIR=""             # --dest        : default ~/.local/share/fonts/nerd-fonts

REPO_URL="https://github.com/ryanoasis/nerd-fonts.git"
RELEASE_BASE_URL="https://github.com/ryanoasis/nerd-fonts/releases"

##########################################################################
# Command line (named options instead of positional arguments)
##########################################################################
usage() {
    sed -n '2,/^####/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' | head -n -1
    cat <<'EOF'

Options:
  --method archive|sparse|full   choose the download method
  --version vX.Y.Z | latest      Nerd Fonts release to install
  --dest PATH                    install folder (default ~/.local/share/fonts/nerd-fonts)
  --no-default-fonts             do not change the desktop's default fonts
  --keep-work-dir                keep the download/clone folder
  --allow-missing-checksum       install archives even if SHA-256 cannot be checked (NOT recommended)
  -h, --help                     this text
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --method)       DOWNLOAD_METHOD="${2:-}"; shift 2 || { echo "--method needs a value" >&2; exit 2; } ;;
        --version)      NF_VERSION="${2:-}"; shift 2 || { echo "--version needs a value" >&2; exit 2; } ;;
        --dest)         DEST_DIR="${2:-}"; shift 2 || { echo "--dest needs a value" >&2; exit 2; } ;;
        --no-default-fonts) SET_DEFAULT_FONTS=false; shift ;;
        --keep-work-dir)    KEEP_WORK_DIR=true; shift ;;
        --allow-missing-checksum) REQUIRE_CHECKSUM=false; shift ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
done

##########################################################################
# Paths
##########################################################################
# Where is this script? Works no matter which directory you run it from,
# which fixes the old "rigid file structure" TODO.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Home directory of the current user. `id -un` is used instead of $USER because
# $USER can be unset (cron, some sudo setups). Quoted everywhere: your old
# `getent passwd $USER` was unquoted.
HOME_DIR="$(getent passwd "$(id -un)" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || HOME_DIR="${HOME:-}"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
# Config backups + the log of this run live together in one small folder:
#   ~/nb/nb_script_data/fonts/fonts_<timestamp>/
# (kept OUTSIDE ~/.local/share/fonts, which fontconfig scans.)
DATA_ROOT="$HOME_DIR/nb/nb_script_data/fonts"
BACKUP_DIR="$DATA_ROOT/fonts_$RUN_ID"
LOG_FILE="$BACKUP_DIR/fonts.log"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME_DIR/.cache}/system_update"

[ -n "$DEST_DIR" ] || DEST_DIR="$HOME_DIR/.local/share/fonts/nerd-fonts"

# Work areas (created later). The staging dir is a hidden SIBLING of DEST_DIR so
# the final swap is a same-filesystem `mv` (fast, effectively atomic).
WORK_DIR=""
STAGE_DIR="$(dirname -- "$DEST_DIR")/.nerd-fonts-staging-$RUN_ID"

##########################################################################
# Logging: log_info / log_warn / log_success / log_error
##########################################################################
# log_success and log_error also remember the item, so the final summary can
# list everything that worked and everything that failed.
SUCCEEDED=()
FAILED=()
WARNINGS=()
LAST_ERROR=""   # helper functions put the reason for a failure here

mkdir -p "$BACKUP_DIR" 2>/dev/null || true
: >"$LOG_FILE" 2>/dev/null || LOG_FILE=/dev/null

# Everything goes to stderr (so command substitutions like $(resolve_version)
# are never polluted by log lines) and is appended to the log file.
_log() {
    local line
    line="[$(date +%H:%M:%S)] $*"
    printf '%s\n' "$line" >&2
    printf '%s\n' "$line" >>"$LOG_FILE" 2>/dev/null
}
log_info()    { _log "INFO    $*"; }
log_warn()    { WARNINGS+=("$*"); _log "WARN    $*"; }
log_success() { SUCCEEDED+=("$1${2:+ - $2}"); _log "SUCCESS $1${2:+ - $2}"; }
log_error()   { FAILED+=("$1${2:+ - $2}");    _log "ERROR   $1${2:+ - $2}"; }
die()         { log_error "FATAL" "$*"; exit 2; }

print_summary() {
    local i
    echo >&2
    echo "==================== SUMMARY ====================" >&2
    {
        echo "Method: $DOWNLOAD_METHOD   Release: ${NF_TAG:-unknown}"
        echo "Install dir: $DEST_DIR"
        echo "Backup dir:  $BACKUP_DIR"
        echo "Log file:    $LOG_FILE"
        echo
        echo "log_success - installed OK (${#SUCCEEDED[@]}):"
        for i in "${SUCCEEDED[@]+"${SUCCEEDED[@]}"}"; do echo "  + $i"; done
        echo
        echo "log_error - FAILED (${#FAILED[@]}):"
        for i in "${FAILED[@]+"${FAILED[@]}"}"; do echo "  ! $i"; done
        if [ "${#WARNINGS[@]}" -gt 0 ]; then
            echo
            echo "warnings (${#WARNINGS[@]}):"
            for i in "${WARNINGS[@]}"; do echo "  ~ $i"; done
        fi
    } | tee -a "$LOG_FILE" >&2
}

##########################################################################
# Cleanup (runs on exit, Ctrl-C, or kill)
##########################################################################
cleanup() {
    # The staging folder is only ever left over after a crash/abort.
    if [ -n "$STAGE_DIR" ] && [ -d "$STAGE_DIR" ]; then rm -rf -- "$STAGE_DIR"; fi
    if [ "$CLEANUP_DELETE_LATER" = true ] && [ "$KEEP_WORK_DIR" = false ] \
       && [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        rm -rf -- "$WORK_DIR"
    fi
}
trap cleanup EXIT
trap 'log_error "INTERRUPTED" "stopped by signal"; print_summary; exit 2' INT TERM

##########################################################################
# Safety helpers
##########################################################################

# rm -rf on a variable is how people delete their home directory. Your old
# `rm -rf $DEST_DIR` was unquoted and unchecked. This refuses anything that is
# not a plausible, deep, absolute path.
safe_rm_rf() {
    local p="$1" depth
    case "$p" in /*) ;; *) log_error "safe_rm_rf" "refusing non-absolute path '$p'"; return 1 ;; esac
    depth=$(awk -F/ '{print NF-1}' <<<"$p")
    if [ "$p" = "/" ] || [ "$p" = "$HOME_DIR" ] || [ "$depth" -lt 3 ]; then
        log_error "safe_rm_rf" "refusing to delete '$p'"
        return 1
    fi
    rm -rf -- "$p"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found ($2)"
}

# Tiny wrapper around curl with the secure settings we want everywhere:
#   --fail             HTTP errors (404, 500...) are failures, not "saved an error page"
#   --proto =https     refuse plain http, also after redirects (--proto-redir)
#   --tlsv1.2          minimum TLS version
#   --retry ...        survive transient network errors
download_file() {  # usage: download_file URL OUTPUT
    curl --fail --silent --show-error --location \
         --proto '=https' --proto-redir '=https' --tlsv1.2 \
         --retry 3 --retry-delay 2 --retry-connrefused \
         --connect-timeout 20 --max-time 1800 \
         --output "$2" "$1"
}

##########################################################################
# Pre-flight checks
##########################################################################
preflight() {
    [ -n "$HOME_DIR" ] && [ -d "$HOME_DIR" ] || die "cannot determine home directory"
    [ "$(id -u)" -ne 0 ] || die "do not run as root/sudo: fonts are installed per-user and desktop settings are per-user"

    case "$DOWNLOAD_METHOD" in
        archive|sparse|full) ;;
        *) die "DOWNLOAD_METHOD must be archive, sparse or full (got '$DOWNLOAD_METHOD')" ;;
    esac
    if [ "$NF_VERSION" != "latest" ] && ! [[ $NF_VERSION =~ ^v[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        die "--version must look like v3.5.1 or 'latest' (got '$NF_VERSION')"
    fi

    require_cmd curl "dnf install curl"
    require_cmd tar "dnf install tar"
    require_cmd xz "dnf install xz"
    require_cmd sha256sum "dnf install coreutils"
    require_cmd fc-cache "dnf install fontconfig"
    require_cmd flock "dnf install util-linux"
    # git is only needed by the two git-based methods.
    if [ "$DOWNLOAD_METHOD" != "archive" ]; then require_cmd git "dnf install git"; fi

    # Only one copy of this script at a time (two runs would fight over the
    # same folders). The lock is released automatically when we exit.
    exec 9>"$DATA_ROOT/fonts.lock"
    flock -n 9 || die "another fonts.sh run is already in progress"
}

# Rough free-space warning. Noto is huge: ~1.1 GB in the repo.
check_free_space() {
    local need_mb free_mb
    case "$DOWNLOAD_METHOD" in full) need_mb=6000 ;; sparse) need_mb=3000 ;; *) need_mb=2000 ;; esac
    free_mb=$(df -Pm "$CACHE_ROOT" 2>/dev/null | awk 'NR==2{print $4}')
    if [ -n "$free_mb" ] && [ "$free_mb" -lt "$need_mb" ]; then
        log_warn "only ${free_mb} MB free under $CACHE_ROOT; '$DOWNLOAD_METHOD' may need ~${need_mb} MB"
    fi
}

##########################################################################
# Input: the list of fonts
##########################################################################
FONTS=()
read_font_list() {
    local line seen=" "
    for line in "${FONT_LIST[@]}"; do
        line="${line//$'\r'/}"                               # tolerate stray CRs
        line="${line#"${line%%[![:space:]]*}"}"              # trim leading space
        line="${line%"${line##*[![:space:]]}"}"              # trim trailing space
        [ -n "$line" ] || continue
        # SECURITY: a name becomes part of a URL and a file path. Only allow
        # plain family names so "../../x" or "a;rm -rf" can never get through.
        if ! [[ $line =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
            log_error "FONT_LIST entry '$line'" "invalid font name, skipped"
            continue
        fi
        case "$seen" in *" $line "*) continue ;; esac        # de-duplicate
        seen+="$line "
        FONTS+=("$line")
    done
    [ "${#FONTS[@]}" -gt 0 ] || die "no usable font names in FONT_LIST"
    log_info "${#FONTS[@]} font families requested"
}

##########################################################################
# Release version
##########################################################################
NF_TAG=""
resolve_version() {
    # GitHub redirects /releases/latest to /releases/tag/<tag>. Reading that
    # redirect needs no API token and has no API rate limit.
    local url tag
    if [ "$NF_VERSION" != "latest" ]; then NF_TAG="$NF_VERSION"; return 0; fi
    url=$(curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
               --tlsv1.2 --max-time 30 --output /dev/null --write-out '%{url_effective}' \
               "$RELEASE_BASE_URL/latest" 2>/dev/null) || url=""
    tag="${url##*/}"
    if [[ $tag =~ ^v[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        NF_TAG="$tag"
    else
        log_warn "could not resolve the latest release; using fallback $NF_VERSION_FALLBACK"
        NF_TAG="$NF_VERSION_FALLBACK"
    fi
    log_info "Nerd Fonts release: $NF_TAG"
}

##########################################################################
# Shared per-font post-processing
##########################################################################

# A font folder only counts as "installed" if it really contains font files.
has_font_files() {
    find "$1" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print -quit 2>/dev/null | grep -q .
}

# Remove docs we do not need and normalise permissions (archives can carry odd
# modes/owners; fonts should be plain 644 files in 755 folders).
finalize_font_dir() {
    local d="$1"
    find "$d" -type f \( -iname '*.md' -o -iname '*.txt' -o -iname 'LICENSE*' \
                         -o -iname 'README*' -o -name '.uuid' \) -delete
    find "$d" -type d -exec chmod 755 {} +
    find "$d" -type f -exec chmod 644 {} +
    # NOTE: removing LICENSE files is fine for personal use. If you ever
    # redistribute these fonts, the SIL OFL requires shipping the license.
}

##########################################################################
# Method 1: ARCHIVE (release .tar.xz + SHA-256.txt)
##########################################################################
CHECKSUM_FILE=""
CHECKSUMS_TRIED=false
DL_DIR=""

# Download SHA-256.txt once (lazily, so the git methods only fetch it if they
# need the archive fallback).
ensure_checksums() {
    if [ "$CHECKSUMS_TRIED" = true ]; then [ -s "$CHECKSUM_FILE" ]; return; fi
    CHECKSUMS_TRIED=true
    CHECKSUM_FILE="$WORK_DIR/SHA-256.txt"
    if download_file "$RELEASE_BASE_URL/download/$NF_TAG/SHA-256.txt" "$CHECKSUM_FILE" && [ -s "$CHECKSUM_FILE" ]; then
        return 0
    fi
    log_warn "could not download SHA-256.txt for $NF_TAG"
    return 1
}

install_font_archive() {  # usage: install_font_archive FONT  (extracts into $STAGE_DIR/FONT)
    local font="$1" file="$1.tar.xz" archive expected actual
    archive="$DL_DIR/$file"

    # Look up the expected hash. awk compares the filename column EXACTLY
    # (a grep for "Hack" would also match "HackGen"...). A leading '*' is the
    # sha256sum "binary mode" marker and is stripped.
    expected=""
    if ensure_checksums; then
        expected=$(awk -v f="$file" '{n=$2; sub(/^\*/,"",n); if (n==f) {print tolower($1); exit}}' "$CHECKSUM_FILE")
    fi
    if [ -n "$expected" ] && ! [[ $expected =~ ^[0-9a-f]{64}$ ]]; then expected=""; fi

    if [ -z "$expected" ]; then
        if [ "$REQUIRE_CHECKSUM" = true ]; then
            LAST_ERROR="no SHA-256 listed for $file in release $NF_TAG (refusing unverified download)"
            return 1
        fi
        log_warn "$font: no checksum available, installing UNVERIFIED (--allow-missing-checksum)"
    fi

    log_info "downloading $file"
    if ! download_file "$RELEASE_BASE_URL/download/$NF_TAG/$file" "$archive"; then
        LAST_ERROR="download failed ($file)"; rm -f -- "$archive"; return 1
    fi

    # Verify BEFORE extracting anything.
    if [ -n "$expected" ]; then
        actual=$(sha256sum -- "$archive" | awk '{print $1}')
        if [ "$actual" != "$expected" ]; then
            LAST_ERROR="SHA-256 MISMATCH for $file (expected $expected, got $actual)"
            rm -f -- "$archive"; return 1
        fi
        log_info "$font: SHA-256 verified"
    fi

    # Archives are flat (no top-level folder), so extract into <stage>/<Font>/
    # to get the same layout the git methods produce.
    #   --no-same-owner / --no-same-permissions : do not trust owner/modes in the tarball
    # GNU tar already refuses absolute paths and ".." members by default.
    mkdir -p "$STAGE_DIR/$font"
    if ! tar -xJf "$archive" -C "$STAGE_DIR/$font" --no-same-owner --no-same-permissions; then
        LAST_ERROR="extraction failed ($file)"; rm -f -- "$archive"; return 1
    fi
    rm -f -- "$archive"   # free disk space early (Noto is large)
    return 0
}

##########################################################################
# Methods 2 + 3: GIT (sparse / full)
##########################################################################
REPO_DIR=""

prepare_repo() {
    REPO_DIR="$WORK_DIR/nerd-fonts"
    # "Start fresh": always a new clone of an exact release TAG (not the moving
    # master branch), so you get what the release shipped and the result matches
    # the archive method. We do not `git pull` an old checkout any more.
    #   transfer.fsckObjects=true : git verifies every received object
    #   --depth 1                 : no history
    log_info "cloning $REPO_URL @ $NF_TAG ($DOWNLOAD_METHOD)"
    if [ "$DOWNLOAD_METHOD" = "sparse" ]; then
        # --filter=blob:none : download no file contents yet (only metadata)
        # --sparse           : check out only top-level files; we add folders later
        git -c transfer.fsckObjects=true clone --quiet --depth 1 --filter=blob:none --sparse \
            --branch "$NF_TAG" "$REPO_URL" "$REPO_DIR" 2>>"$LOG_FILE"
    else
        git -c transfer.fsckObjects=true clone --quiet --depth 1 \
            --branch "$NF_TAG" "$REPO_URL" "$REPO_DIR" 2>>"$LOG_FILE"
    fi
}

# return 0 = installed, 1 = failed, 3 = font folder does not exist in the repo
install_font_git() {  # usage: install_font_git FONT
    local font="$1" src
    src="$REPO_DIR/patched-fonts/$font"
    if [ "$DOWNLOAD_METHOD" = "sparse" ]; then
        # One folder at a time: if THIS fetch fails, only THIS font fails.
        # (git silently ignores a path that does not exist, so we check below.)
        if ! git -C "$REPO_DIR" sparse-checkout add "patched-fonts/$font" 2>>"$LOG_FILE"; then
            LAST_ERROR="git sparse-checkout failed"; return 1
        fi
    fi
    if [ ! -d "$src" ]; then LAST_ERROR="no patched-fonts/$font folder in repo $NF_TAG"; return 3; fi
    mkdir -p "$STAGE_DIR/$font"
    # "/." copies the folder CONTENTS (including dotfiles) into the target.
    if ! cp -a "$src/." "$STAGE_DIR/$font/"; then LAST_ERROR="copy failed"; return 1; fi
    return 0
}

##########################################################################
# Install ONE font with the selected method (+ optional fallback)
##########################################################################
install_one_font() {  # returns 0 on success; reason in LAST_ERROR
    local font="$1" rc=0
    LAST_ERROR=""
    rm -rf -- "${STAGE_DIR:?}/$font"

    case "$DOWNLOAD_METHOD" in
        archive)
            install_font_archive "$font" || rc=$? ;;
        sparse|full)
            if [ -z "$REPO_DIR" ] || [ ! -d "$REPO_DIR/.git" ]; then
                LAST_ERROR="git clone of $NF_TAG failed earlier"; rc=1
            else
                install_font_git "$font" || rc=$?
            fi
            # Font not in the repo (or the repo is unusable): try the verified archive.
            if [ "$rc" -ne 0 ] && [ "$FALLBACK_TO_ARCHIVE" = true ]; then
                log_warn "$font: $LAST_ERROR -> trying release archive instead"
                rm -rf -- "${STAGE_DIR:?}/$font"
                rc=0
                install_font_archive "$font" || rc=$?
            fi ;;
    esac
    [ "$rc" -eq 0 ] || { rm -rf -- "${STAGE_DIR:?}/$font"; return 1; }

    finalize_font_dir "$STAGE_DIR/$font"
    if ! has_font_files "$STAGE_DIR/$font"; then
        LAST_ERROR="no .ttf/.otf files found after install"
        rm -rf -- "${STAGE_DIR:?}/$font"; return 1
    fi
    return 0
}

##########################################################################
# Backups
##########################################################################
backup_everything() {
    # Only the CONFIG files this script may modify. Fonts are deliberately not
    # backed up (GBs); they can be re-downloaded at any time.
    mkdir -p "$BACKUP_DIR" || die "cannot create backup dir $BACKUP_DIR"
    log_info "config backup folder: $BACKUP_DIR"

    # KDE Plasma: font settings live in ~/.config/kdeglobals
    if [ -f "$HOME_DIR/.config/kdeglobals" ]; then
        cp -a -- "$HOME_DIR/.config/kdeglobals" "$BACKUP_DIR/kdeglobals" \
            || log_warn "could not back up kdeglobals"
    fi
    # GNOME: font settings live in dconf (restore with: dconf load / < file)
    if command -v dconf >/dev/null 2>&1; then
        dconf dump /org/gnome/desktop/interface/ >"$BACKUP_DIR/gnome-interface.dconf" 2>/dev/null || true
        dconf dump /org/gnome/desktop/wm/preferences/ >"$BACKUP_DIR/gnome-wm-preferences.dconf" 2>/dev/null || true
        # remove empty dumps (dconf not running / not GNOME)
        find "$BACKUP_DIR" -maxdepth 1 -name '*.dconf' -empty -delete
    fi

    # Prune old backups, keep the newest KEEP_BACKUPS (this run's folder counts).
    local old
    while IFS= read -r old; do
        [ -n "$old" ] && safe_rm_rf "$old"
    done < <(find "$DATA_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'fonts_*' | sort -r | tail -n +"$((KEEP_BACKUPS + 1))")
}

##########################################################################
# Desktop default fonts
##########################################################################
detect_desktop() {
    local d=""
    # Prefer your own helper if present; fall back to the standard variable.
    if [ -r "$SCRIPT_DIR/get_desktop_env.sh" ]; then
        d="$(sh "$SCRIPT_DIR/get_desktop_env.sh" 2>/dev/null)" || d=""
    fi
    [ -n "$d" ] || d="${XDG_CURRENT_DESKTOP:-}"
    d="${d,,}"
    case "$d" in
        *kde*|*plasma*) echo kde ;;
        *gnome*)        echo gnome ;;
        *)              echo "${d:-unknown}" ;;
    esac
}

FC_FAMILIES=""
font_family_present() {  # exact family-name match against fontconfig's list
    [ -n "$FC_FAMILIES" ] || FC_FAMILIES="$(fc-list : family | tr ',' '\n' | sed 's/^ *//' | sort -u)"
    grep -Fxq -- "$1" <<<"$FC_FAMILIES"
}

# Qt6 / Plasma 6 font string:
#   Family,PointSize,PixelSize(-1),StyleHint(5),Weight(400=Regular),Italic,Underline,StrikeOut,FixedPitch,...
# (Your old string used weight 50, which is the Qt5 scale; Qt6 uses 100-900.)
kde_font_string() { printf '%s,%s,-1,5,400,0,0,0,0,0,0,0,0,0,0,1' "$1" "$2"; }

# IMPORTANT: always pass --file kdeglobals. Without --file, kwriteconfig6 writes
# to its OWN config (~/.config/kwriteconfig6rc), which does nothing for Plasma.
# That was a real bug in the old script.
kde_set() {  # usage: kde_set GROUP KEY VALUE
    kwriteconfig6 --file kdeglobals --group "$1" --key "$2" "$3"
}

apply_kde_fonts() {
    command -v kwriteconfig6 >/dev/null 2>&1 || { log_error "default fonts (KDE)" "kwriteconfig6 not found"; return; }
    local ok=true ui mono
    if font_family_present "$KDE_UI_FONT_FAMILY"; then
        ui="$(kde_font_string "$KDE_UI_FONT_FAMILY" "$KDE_UI_FONT_SIZE")"
        kde_set General font "$ui" || ok=false
        kde_set General menuFont "$ui" || ok=false
        kde_set General toolBarFont "$ui" || ok=false
        kde_set WM activeFont "$ui" || ok=false
        kde_set General smallestReadableFont "$(kde_font_string "$KDE_UI_FONT_FAMILY" 8)" || ok=false
    else
        log_error "default UI font (KDE)" "family '$KDE_UI_FONT_FAMILY' not installed (check: fc-list : family | grep -i noto)"
        ok=false
    fi
    if font_family_present "$MONO_FONT_FAMILY"; then
        mono="$(kde_font_string "$MONO_FONT_FAMILY" "$KDE_MONO_FONT_SIZE")"
        kde_set General fixed "$mono" || ok=false
    else
        log_error "default monospace font (KDE)" "family '$MONO_FONT_FAMILY' not installed"
        ok=false
    fi
    [ "$ok" = true ] && log_success "default fonts (KDE)" "written to ~/.config/kdeglobals; log out/in to apply everywhere"
}

apply_gnome_fonts() {
    command -v dconf >/dev/null 2>&1 || { log_error "default fonts (GNOME)" "dconf not found"; return; }
    local ok=true
    if font_family_present "$GNOME_UI_FONT_FAMILY"; then
        dconf write /org/gnome/desktop/interface/font-name "'$GNOME_UI_FONT_FAMILY $GNOME_UI_FONT_SIZE'" || ok=false
        dconf write /org/gnome/desktop/interface/document-font-name "'$GNOME_UI_FONT_FAMILY $GNOME_UI_FONT_SIZE'" || ok=false
        dconf write /org/gnome/desktop/wm/preferences/titlebar-font "'$GNOME_UI_FONT_FAMILY Bold $GNOME_UI_FONT_SIZE'" || ok=false
    else
        log_error "default UI font (GNOME)" "family '$GNOME_UI_FONT_FAMILY' not installed"; ok=false
    fi
    if font_family_present "$MONO_FONT_FAMILY"; then
        dconf write /org/gnome/desktop/interface/monospace-font-name "'$MONO_FONT_FAMILY $GNOME_MONO_FONT_SIZE'" || ok=false
    else
        log_error "default monospace font (GNOME)" "family '$MONO_FONT_FAMILY' not installed"; ok=false
    fi
    [ "$ok" = true ] && log_success "default fonts (GNOME)" "applied via dconf"
}

apply_default_fonts() {
    local desktop; desktop="$(detect_desktop)"
    log_info "desktop environment: $desktop"
    case "$desktop" in
        kde)   apply_kde_fonts ;;
        gnome) apply_gnome_fonts ;;
        *)     log_warn "unknown desktop '$desktop': fonts installed but defaults not changed" ;;
    esac
}

##########################################################################
# Main
##########################################################################
main() {
    preflight
    log_info "method=$DOWNLOAD_METHOD  dest=$DEST_DIR"
    read_font_list
    resolve_version

    mkdir -p "$CACHE_ROOT" || die "cannot create $CACHE_ROOT"
    WORK_DIR="$(mktemp -d "$CACHE_ROOT/fonts.XXXXXX")" || die "mktemp failed"
    DL_DIR="$WORK_DIR/downloads"; mkdir -p "$DL_DIR"
    check_free_space

    # Nothing has been modified so far. Back up, THEN build the new set.
    backup_everything
    mkdir -p "$STAGE_DIR" || die "cannot create staging dir $STAGE_DIR"

    # Git methods need the repo once up front. If the clone fails we do NOT
    # abort: each font will fall back to the verified archive (if allowed).
    if [ "$DOWNLOAD_METHOD" != "archive" ]; then
        if ! prepare_repo; then
            log_error "git clone ($DOWNLOAD_METHOD)" "clone of $NF_TAG failed"
            REPO_DIR=""
        fi
    fi

    local font
    for font in "${FONTS[@]}"; do
        log_info "----- $font -----"
        if install_one_font "$font"; then
            log_success "$font" "$DOWNLOAD_METHOD, $NF_TAG"
        else
            log_error "$font" "${LAST_ERROR:-unknown error}"
            # Keep what you had rather than ending up with nothing for this font.
            if [ "$KEEP_OLD_COPY_ON_FAILURE" = true ] && [ -d "$DEST_DIR/$font" ]; then
                if cp -a -- "$DEST_DIR/$font" "$STAGE_DIR/$font"; then
                    log_warn "$font: kept previously installed copy"
                fi
            fi
        fi
    done

    # All downloads are done: free the (possibly multi-GB) clone/archives NOW,
    # before the swap, instead of waiting for the exit trap.
    if [ "$CLEANUP_DELETE_LATER" = true ] && [ "$KEEP_WORK_DIR" = false ]; then
        safe_rm_rf "$WORK_DIR" && WORK_DIR=""
    fi

    # Swap in the new set only if at least one font really succeeded.
    if [ "${#SUCCEEDED[@]}" -eq 0 ]; then
        log_error "install" "no font installed successfully; existing $DEST_DIR left untouched"
    else
        mkdir -p -- "$(dirname -- "$DEST_DIR")"
        # Swap safely: move the old set aside, move the new set in, and only
        # then delete the old set. If the second step fails, move the old set
        # back, so you can never end up with no fonts.
        local old_dir swapped=false
        old_dir="$(dirname -- "$DEST_DIR")/.nerd-fonts-old-$RUN_ID"
        if [ -e "$DEST_DIR" ] && ! mv -- "$DEST_DIR" "$old_dir"; then
            log_error "install" "could not move old $DEST_DIR aside; old fonts left untouched"
        elif mv -- "$STAGE_DIR" "$DEST_DIR"; then
            swapped=true
            [ -d "$old_dir" ] && safe_rm_rf "$old_dir"
        else
            [ -d "$old_dir" ] && mv -- "$old_dir" "$DEST_DIR"
            log_error "install" "could not move new fonts into $DEST_DIR; old fonts restored"
        fi
        if [ "$swapped" = true ]; then
            log_info "installed new font set into $DEST_DIR"
            # Rebuild the font cache for OUR folder only. Your old `fc-cache -fr`
            # rescanned every font on the system, which is slow and unnecessary.
            if fc-cache -f "$DEST_DIR"; then
                log_success "font cache" "refreshed"
            else
                log_error "font cache" "fc-cache failed"
            fi
            [ "$SET_DEFAULT_FONTS" = true ] && apply_default_fonts
        fi
    fi

    print_summary
    [ "${#FAILED[@]}" -eq 0 ] || exit 1
    exit 0
}

main

##########################################################################
# Notes:
##########################################################################
# Finding a font family name after installation:
#   fc-list : family | sort -u | grep -i noto
#   fc-list | grep -i nerd | grep -i sans | grep -i regular | grep -vi condensed \
#       | grep -vi bold | grep -vi italic | grep -vi propo | grep -vi light \
#       | grep -vi thin | grep -v Medium | grep -vi black | grep -i noto
#
# grep options worth remembering:
#   -v  invert match           -e PATTERN  (repeatable)
#   -r  recursive              -R  recursive, follows symlinks
#   --include=GLOB / --exclude=GLOB / --exclude-dir=DIR
#
# Reference: https://docs.fedoraproject.org/en-US/quick-docs/fonts/


##########################################################################
# Verification:
##########################################################################

# kreadconfig6 --file kdeglobals --group General --key font
# NotoSans Nerd Font,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1

#  kreadconfig6 --file kdeglobals --group General --key fixed
# JetBrainsMono Nerd Font,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1

#  ls -a ~/.local/share/fonts ~/.cache/system_updatenbMain
# /home/nbhirud/.cache/system_update:
# .  ..
# /home/nbhirud/.local/share/fonts:
# .  ..  nerd-fonts     

