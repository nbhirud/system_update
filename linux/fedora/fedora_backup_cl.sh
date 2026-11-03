#!/usr/bin/env bash
# =============================================================================
# fedora-backup.sh — pre-reinstall backup for Fedora 44 KDE (dnf5, systemd, SELinux)
#
# WHAT IT DOES
#   Builds ONE archive (tar + zstd, optionally GPG-encrypted) that contains:
#     1. Config files in /etc that you (or an installer) changed or created
#        - found automatically: "modified packaged configs" (rpm -Va) +
#          "files in /etc that no RPM owns" (repos, custom units, NM, sudoers...)
#     2. KDE Plasma / shell / dev settings from your home directory
#        (panel & widget layout, shortcuts, KWin rules, themes, mimeapps, ...)
#     3. An "_inventory/" folder of text lists: user-installed RPMs, repos, COPRs,
#        Flatpaks, enabled/disabled units, timers, SELinux changes, hardware...
#     4. Generated helper scripts in "_inventory/restore/" to re-enable COPRs,
#        reinstall packages and Flatpaks, and re-apply service enablement.
#   Next to the archive it writes a checksum, a manifest, and the logs
#   (log, log_success, log_error).
#
# WHAT IT NEVER DOES
#   It never modifies the system. Every run is fresh: new timestamped output,
#   nothing from a previous run is reused.
#
# USAGE
#   sudo ./fedora-backup.sh --output-dir /run/media/$USER/BACKUPDRIVE/fedora
#   ./fedora-backup.sh --help
# =============================================================================

# NOTE: no "set -e" on purpose. One failing step (e.g. flatpak not installed)
# must not abort the whole backup; every step is logged to success/error lists.
set -uo pipefail
umask 077   # everything we create is private (0600/0700): it may hold secrets

SCRIPT_VERSION="1.0.0"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
ORIG_ARGS=("$@")

# ------------------------------- defaults ------------------------------------
OUTPUT_DIR=""            # required, no default (see --help for why)
TARGET_USER=""           # default: the user who ran sudo
SCOPE="curated"          # curated | broad
ENCRYPT=1                # 1 = encrypt with a passphrase (GPG AES256)
INCLUDE_SECRETS=1        # 0 = leave out ssh/gpg keys, wifi passwords, wallets...
VERIFY_RPM=1             # rpm -Va finds modified configs; takes ~1 minute
ZSTD_LEVEL=10
DRY_RUN=0
EXTRA_PATHS=()

# ------------------------------- output helpers ------------------------------
if [[ -t 1 ]]; then
  C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_BLU=$'\e[34m'; C_RST=$'\e[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_RST=""
fi

LOG_FILE="/dev/null"     # replaced once the output dir exists
SUCCESS_LIST=(); ERROR_LIST=(); SKIP_LIST=()

section()     { printf '\n%s== %s ==%s\n' "$C_BLU" "$*" "$C_RST"; }
note()        { printf '%s\n' "$*"; printf '%s\n' "$*" >>"$LOG_FILE"; }
warn()        { printf '%sWARNING:%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; printf 'WARNING: %s\n' "$*" >>"$LOG_FILE"; }
die()         { printf '%sERROR:%s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }
log_success() { SUCCESS_LIST+=("$*"); printf '  %s[ok]%s   %s\n' "$C_GRN" "$C_RST" "$*"; printf '[ok] %s\n' "$*" >>"$LOG_FILE"; }
log_error()   { ERROR_LIST+=("$*");   printf '  %s[FAIL]%s %s\n' "$C_RED" "$C_RST" "$*"; printf '[FAIL] %s\n' "$*" >>"$LOG_FILE"; }
log_skip()    { SKIP_LIST+=("$*");    printf '  %s[skip]%s %s\n' "$C_YEL" "$C_RST" "$*"; printf '[skip] %s\n' "$*" >>"$LOG_FILE"; }
have()        { command -v "$1" >/dev/null 2>&1; }

usage() {
cat <<'EOF'
Usage: fedora-backup.sh --output-dir DIR [options]

Required:
  --output-dir DIR      Where the backup goes. Use an EXTERNAL drive or another
                        machine: anything on this disk dies when you format it.

Options:
  --user NAME           User whose home directory is backed up
                        (default: the user who invoked sudo)
  --scope curated|broad curated (default): KDE, shell, git, editors, themes, mime,
                          user systemd units, Flatpak overrides, keys.
                        broad: curated + ALL dot-dirs in $HOME (browser profiles,
                          app data...) minus caches/known-huge dirs. Bigger.
  --encrypt             Encrypt the archive with a passphrase (default)
  --no-encrypt          Do not encrypt (archive then contains secrets in clear!)
  --no-secrets          Leave out SSH/GPG keys, Wi-Fi/VPN credentials, KWallet,
                        keyrings, KDE Connect pairing, Bluetooth pairing, tokens
  --skip-rpm-verify     Skip "rpm -Va" (faster, but modified package configs
                        outside the unowned-file check may be missed)
  --extra-path PATH     Also back up this absolute path (repeatable)
  --zstd-level N        Compression level 1-19 (default 10)
  --dry-run             Build the inventory and file list only, no archive
  -h, --help            Show this help
Both "--opt value" and "--opt=value" work.
EOF
}

need_val() { [[ -n ${2:-} ]] || die "$1 needs a value (see --help)"; }

# ------------------------------- argument parsing ----------------------------
ARGS=()
for a in "$@"; do                       # split --opt=value into --opt value
  if [[ $a == --*=* ]]; then ARGS+=("${a%%=*}" "${a#*=}"); else ARGS+=("$a"); fi
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

while (($#)); do
  case $1 in
    --output-dir)      need_val "$@"; OUTPUT_DIR=$2; shift 2 ;;
    --user)            need_val "$@"; TARGET_USER=$2; shift 2 ;;
    --scope)           need_val "$@"; SCOPE=$2; shift 2 ;;
    --extra-path)      need_val "$@"; EXTRA_PATHS+=("$2"); shift 2 ;;
    --zstd-level)      need_val "$@"; ZSTD_LEVEL=$2; shift 2 ;;
    --encrypt)         ENCRYPT=1; shift ;;
    --no-encrypt)      ENCRYPT=0; shift ;;
    --no-secrets)      INCLUDE_SECRETS=0; shift ;;
    --skip-rpm-verify) VERIFY_RPM=0; shift ;;
    --dry-run)         DRY_RUN=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 usage >&2; die "unknown option: $1" ;;
  esac
done

[[ -n $OUTPUT_DIR ]] || { usage >&2; die "--output-dir is required"; }
[[ $SCOPE == curated || $SCOPE == broad ]] || die "--scope must be 'curated' or 'broad'"
[[ $ZSTD_LEVEL =~ ^([1-9]|1[0-9])$ ]] || die "--zstd-level must be 1-19"

# ------------------------------- become root ---------------------------------
# /etc/*, the RPM database and /var/lib/* are only readable by root.
if (( EUID != 0 )); then
  echo "Root is required (reads /etc, the RPM db, ...). Re-running with sudo..." >&2
  exec sudo -- "$SCRIPT_PATH" "${ORIG_ARGS[@]}"
fi

TARGET_USER=${TARGET_USER:-${SUDO_USER:-}}
[[ -n $TARGET_USER && $TARGET_USER != root ]] || die "cannot tell which user to back up; pass --user NAME"
getent passwd "$TARGET_USER" >/dev/null || die "no such user: $TARGET_USER"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_UID=$(id -u "$TARGET_USER")
[[ -d $TARGET_HOME ]] || die "home directory not found: $TARGET_HOME"
export PATH="$PATH:$TARGET_HOME/.local/bin:$TARGET_HOME/.cargo/bin"   # pipx, cargo...

# Run a command as the target user with a usable session environment, so that
# "systemctl --user", flatpak --user, dconf, etc. see the user's real data.
as_user() {
  runuser -u "$TARGET_USER" -- env \
    "HOME=$TARGET_HOME" "PATH=$PATH" \
    "XDG_RUNTIME_DIR=/run/user/$TARGET_UID" \
    "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$TARGET_UID/bus" "$@"
}

# ------------------------------- dependency check ----------------------------
MISSING=()
for t in tar zstd sha256sum find awk sort comm runuser rpm getent; do have "$t" || MISSING+=("$t"); done
(( ENCRYPT )) && { have gpg || MISSING+=("gpg"); }
((${#MISSING[@]})) && die "missing required tools: ${MISSING[*]}  (try: sudo dnf install tar zstd gnupg2 util-linux rpm)"
PKG_CMD=$(command -v dnf5 || command -v dnf || true)

# ------------------------------- output locations ----------------------------
STAMP=$(date +%Y%m%d-%H%M%S)
HOST=$(hostname -s 2>/dev/null || echo unknown-host)
BASE="fedora-backup-${HOST}-${STAMP}"
mkdir -p "$OUTPUT_DIR" || die "cannot create $OUTPUT_DIR"
OUTPUT_DIR=$(readlink -f "$OUTPUT_DIR")
LOG_FILE="$OUTPUT_DIR/$BASE.log"
: >"$LOG_FILE"
ARCHIVE="$OUTPUT_DIR/$BASE.tar.zst$( ((ENCRYPT)) && echo .gpg )"

# Fresh private work area in tmpfs-backed /tmp. Always deleted on exit.
WORK=$(mktemp -d /tmp/fedora-backup.XXXXXX) || die "mktemp failed"
INV="$WORK/inventory"; mkdir -p "$INV"
LIST_RAW="$WORK/files.raw.nul"; LIST="$WORK/files.nul"; EXCL="$WORK/excludes.txt"
: >"$LIST_RAW"; : >"$EXCL"
PASSPHRASE=""
cleanup() { rm -rf "$WORK"; PASSPHRASE=""; }
trap cleanup EXIT
trap 'echo; warn "interrupted"; [[ -n ${ARCHIVE:-} ]] && rm -f "$ARCHIVE"; exit 130' INT TERM

section "Fedora backup $SCRIPT_VERSION  ($HOST, user=$TARGET_USER, scope=$SCOPE)"
note "Output : $ARCHIVE"
note "Encrypt: $ENCRYPT   Secrets: $INCLUDE_SECRETS   rpm -Va: $VERIFY_RPM"

# Warn loudly if the backup sits on the disk that is about to be wiped.
out_dev=$(stat -c %d "$OUTPUT_DIR")
for p in / /home "$TARGET_HOME"; do
  [[ -d $p && $(stat -c %d "$p") == "$out_dev" ]] && {
    warn "output dir is on the same filesystem as $p — formatting will destroy it. Copy the archive elsewhere before reinstalling."
    break
  }
done

# Ask for the passphrase up front so the long part can run unattended.
if (( ENCRYPT && ! DRY_RUN )); then
  read -r -s -p "Passphrase for the archive (min 12 chars): " p1 </dev/tty; echo
  read -r -s -p "Repeat passphrase: " p2 </dev/tty; echo
  [[ $p1 == "$p2" ]] || die "passphrases do not match"
  (( ${#p1} >= 12 )) || die "passphrase too short (min 12 characters)"
  PASSPHRASE=$p1; unset p1 p2
fi

# =============================================================================
# 1. INVENTORY  (plain-text facts about this machine)
# =============================================================================
# capture NAME CMD...   run CMD, store stdout in inventory/NAME.txt, log the result
capture() {
  local name=$1; shift
  local probe=$1; [[ $probe == as_user ]] && probe=${2:-}
  if ! have "$probe"; then log_skip "$name ('$probe' not installed)"; return 0; fi
  local out="$INV/$name.txt"; mkdir -p "$(dirname "$out")"
  if "$@" >"$out" 2>>"$LOG_FILE"; then log_success "$name"; else log_error "$name (exit $?)"; fi
}
# capture_needs TOOL NAME CMD...   same, but for bash -c pipelines needing TOOL
capture_needs() {
  local tool=$1; shift
  if have "$tool"; then capture "$@"; else log_skip "$1 ('$tool' not installed)"; fi
}

# Enabled COPRs, parsed straight from the repo files (works on dnf4 and dnf5).
# Output: owner/project <TAB> enabled(1/0) <TAB> host
list_coprs() {
  local f b owner project host en
  shopt -s nullglob
  for f in /etc/yum.repos.d/_copr:*.repo; do
    b=${f##*/_copr:}; b=${b%.repo}               # host:owner:project
    IFS=: read -r host owner project <<<"$b"
    [[ $owner == group_* ]] && owner="@${owner#group_}"
    en=$(awk -F= '/^enabled=/{print $2; exit}' "$f")
    printf '%s/%s\t%s\t%s\n' "$owner" "$project" "${en:-1}" "$host"
  done
  for f in /etc/yum.repos.d/_copr_*.repo; do     # legacy file naming
    b=${f##*/_copr_}; b=${b%.repo}
    en=$(awk -F= '/^enabled=/{print $2; exit}' "$f")
    printf '%s\t%s\t%s\n' "${b/-//}" "${en:-1}" "copr.fedorainfracloud.org"
  done
}

# units whose state differs from the distro preset = what YOU changed
derive_preset_changes() {   # $1 = list-unit-files output, $2 = result
  [[ -s $1 ]] || return 0
  awk '$2=="enabled" && $3!="enabled" {print "enable "  $1}
       $2=="disabled" && $3=="enabled" {print "disable " $1}' "$1" >"$2"
}

collect_inventory() {
  section "Inventory: system"
  capture system/os-release        cat /etc/os-release
  capture system/hostnamectl       hostnamectl
  capture system/uname             uname -a
  capture system/kernel-cmdline    cat /proc/cmdline
  capture system/localectl         localectl status
  capture system/timedatectl       timedatectl
  capture system/lsblk             lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS
  capture system/blkid             blkid
  capture system/findmnt           findmnt --real
  capture system/lspci             lspci -nnk
  capture system/lsusb             lsusb
  capture system/lsmod             lsmod
  capture system/dkms-status       dkms status
  capture system/secureboot        mokutil --sb-state
  capture system/grubby            grubby --info=ALL
  capture system/alternatives      alternatives --list
  capture system/nvidia            nvidia-smi -L
  capture system/fonts-families    bash -c 'fc-list : family | sort -u'
  capture system/users             bash -c "getent passwd | awk -F: '\$3>=1000 && \$3<60000'"
  capture system/user-groups       id "$TARGET_USER"
  capture system/root-crontab      crontab -l
  capture system/user-crontab      crontab -l -u "$TARGET_USER"

  section "Inventory: network, firewall, SELinux"
  capture network/nmcli-connections nmcli -t -f NAME,TYPE,AUTOCONNECT,DEVICE connection show
  capture network/ip-addr          ip -br addr
  capture network/resolvectl       resolvectl status
  capture network/firewalld-zones  firewall-cmd --list-all-zones
  capture selinux/sestatus         sestatus
  capture selinux/booleans         getsebool -a
  capture selinux/semanage-export  semanage export        # local policy tweaks
  capture virt/virsh-domains       virsh list --all
  capture virt/virsh-networks      virsh net-list --all

  section "Inventory: packages, repos, COPRs"
  capture packages/rpm-qa          bash -c "rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\t%{VENDOR}\t%{PACKAGER}\n' | sort"
  capture packages/gpg-pubkeys     bash -c "rpm -qa 'gpg-pubkey*' --qf '%{NAME}-%{VERSION}-%{RELEASE}\t%{SUMMARY}\n'"
  # All installed package names: the always-works fallback for reinstalling
  capture packages/all-names       bash -c "rpm -qa --qf '%{NAME}\n' | sort -u"
  capture_needs "${PKG_CMD:-dnf}" packages/userinstalled-names \
          bash -c "'$PKG_CMD' -q repoquery --userinstalled --queryformat '%{name}\n' | sort -u"
  capture_needs "${PKG_CMD:-dnf}" packages/by-source-repo \
          bash -c "'$PKG_CMD' -q repoquery --installed --queryformat '%{from_repo}\t%{name}\n' | sort"
  capture_needs "${PKG_CMD:-dnf}" packages/groups-installed "$PKG_CMD" -q group list --installed
  capture_needs "${PKG_CMD:-dnf}" packages/repos-all        "$PKG_CMD" -q repo list --all
  capture_needs "${PKG_CMD:-dnf}" packages/dnf-history      "$PKG_CMD" -q history list
  capture packages/coprs           list_coprs

  section "Inventory: Flatpak"
  capture flatpak/system-apps      flatpak list --system --app --columns=origin,application
  capture flatpak/system-remotes   flatpak remotes --system --columns=name,url
  capture flatpak/user-apps        as_user flatpak list --user --app --columns=origin,application
  capture flatpak/user-remotes     as_user flatpak remotes --user --columns=name,url

  section "Inventory: systemd units and timers"
  capture systemd/system-unit-files systemctl list-unit-files --no-pager --no-legend
  capture systemd/system-timers     systemctl list-timers --all --no-pager
  capture systemd/system-failed     systemctl --failed --no-pager
  capture systemd/system-delta      systemd-delta --no-pager      # overridden/extended units
  capture systemd/default-target    systemctl get-default
  capture systemd/user-unit-files   as_user systemctl --user list-unit-files --no-pager --no-legend
  capture systemd/user-timers       as_user systemctl --user list-timers --all --no-pager
  derive_preset_changes "$INV/systemd/system-unit-files.txt" "$INV/systemd/system-changed-from-preset.txt"
  derive_preset_changes "$INV/systemd/user-unit-files.txt"   "$INV/systemd/user-changed-from-preset.txt"

  section "Inventory: KDE, user tools, containers"
  capture kde/plasmashell-version  plasmashell --version
  capture kde/plasma-widgets       as_user kpackagetool6 --list --type Plasma/Applet
  capture kde/kscreen-outputs      as_user kscreen-doctor -o
  capture kde/dconf-dump           as_user dconf dump /
  capture dev/vscode-extensions    as_user code --list-extensions
  capture dev/pip-user             as_user pip list --user --format=freeze
  capture dev/pipx                 as_user pipx list --short
  capture dev/npm-global           as_user npm ls -g --depth=0
  capture dev/cargo                as_user cargo install --list
  capture containers/podman-images as_user podman images
  capture containers/podman-ps     as_user podman ps -a
  capture containers/podman-volumes as_user podman volume ls
  capture containers/toolbox       as_user toolbox list
  capture containers/distrobox     as_user distrobox list
  capture home/appimages           bash -c "find '$TARGET_HOME' -maxdepth 3 -iname '*.AppImage' 2>/dev/null"
  capture home/size-overview       bash -c 'cd "$1" && du -xsh .[!.]* * 2>/dev/null | sort -h' _ "$TARGET_HOME"
  capture system/opt-contents      bash -c 'find /opt -mindepth 1 -maxdepth 2 2>/dev/null | sort'
}

# =============================================================================
# 2. FILE LIST  (what goes into the archive besides the inventory)
# =============================================================================
add_path() {                          # add_path /abs/path  (silently skip missing)
  local p=$1
  [[ -e $p || -L $p ]] && printf '%s\0' "${p#/}" >>"$LIST_RAW"
  return 0
}
add_home_glob() {                     # add_home_glob '.config/k*'  (relative to $HOME)
  local p
  pushd "$TARGET_HOME" >/dev/null || return 0
  for p in $1; do                     # unquoted on purpose: let the shell expand the glob
    [[ $p == . || $p == .. ]] && continue
    [[ -e $p || -L $p ]] && printf '%s\0' "${TARGET_HOME#/}/$p" >>"$LIST_RAW"
  done
  popd >/dev/null || true
}
exclude()      { printf '%s\n' "$1" >>"$EXCL"; }
exclude_tree() { printf '%s\n%s\n' "$1" "$1/*" >>"$EXCL"; }   # dir and everything below

build_excludes() {
  # --- generated, machine-bound or dangerous to restore into /etc -----------
  for f in etc/machine-id etc/shadow etc/shadow- etc/gshadow etc/gshadow- etc/passwd- \
           etc/group- etc/subuid- etc/subgid- etc/ld.so.cache etc/mtab etc/resolv.conf \
           etc/.pwd.lock etc/.updated etc/printcap etc/udev/hwdb.bin 'etc/ssh/ssh_host_*'; do
    exclude "$f"
  done
  for d in etc/alternatives etc/pki/ca-trust/extracted etc/pki/java etc/crypto-policies/back-ends \
           etc/selinux/targeted etc/selinux/mls etc/lvm/archive etc/lvm/backup etc/lvm/cache; do
    exclude_tree "$d"
  done
  # --- caches and bulk that can be re-created (applies in every scope) ------
  for d in .cache Cache 'Code Cache' GPUCache CachedData CacheStorage ShaderCache DawnCache \
           GrShaderCache Crashpad node_modules __pycache__ .venv Trash .steam .wine .npm \
           .rustup .cargo/registry .gradle .m2 .local/share/Steam .local/share/containers \
           .local/share/baloo .local/share/akonadi .local/share/flatpak/app \
           .local/share/flatpak/runtime .local/share/flatpak/repo .local/share/flatpak/appstream \
           .local/share/flatpak/exports .local/share/recently-used.xbel; do
    exclude_tree "$d"
  done
  exclude_tree '.var/app/*/cache'
  # --- secrets (only when --no-secrets) -------------------------------------
  if (( ! INCLUDE_SECRETS )); then
    for d in .ssh .gnupg .pki .aws .kube .docker kwalletd keyrings kdeconnect .config/rclone .config/gh \
             etc/NetworkManager/system-connections etc/wireguard etc/openvpn etc/ipsec.d \
             var/lib/bluetooth var/lib/fprint; do
      exclude_tree "$d"
    done
    exclude 'etc/ppp/*-secrets'
  fi
}

# Everything in /etc that is not stock: modified package configs + unowned files.
collect_etc() {
  if (( VERIFY_RPM )); then
    note "Running rpm -Va to find modified config files (about a minute)..."
    # Line format: "S.5....T.  c /etc/foo"  -> keep config files (c) whose size/mode/digest changed
    rpm -Va --nodeps --noscripts --nomtime 2>>"$LOG_FILE" \
      | awk '$1!="missing" && $1 ~ /[SM5LUG]/ && $2=="c" {sub(/^[^ ]+ +c +/, ""); print}' \
      | while IFS= read -r p; do add_path "$p"; done
    log_success "modified package configs (rpm -Va)"
  else
    log_skip "modified package configs (--skip-rpm-verify)"
  fi
  # Files under /etc not owned by any RPM: custom repos, units, NM profiles, sudoers.d, ...
  LC_ALL=C comm -23 \
      <(find /etc -xdev \( -type f -o -type l \) -print 2>/dev/null | LC_ALL=C sort -u) \
      <(rpm -qla 2>/dev/null | LC_ALL=C sort -u) \
    | while IFS= read -r p; do add_path "$p"; done
  log_success "unowned files in /etc"
}

collect_files() {
  section "Building file list"
  build_excludes
  collect_etc

  # Other system-level state worth keeping
  add_path /usr/local
  add_path /var/lib/flatpak/overrides
  add_path /var/spool/cron
  add_path "/var/lib/AccountsService/users/$TARGET_USER"
  add_path /usr/lib/sysimage/libdnf5         # dnf5 history + "user installed" reasons
  add_path /var/lib/dnf                      # dnf4-era state, if present
  add_path /var/lib/bluetooth                # paired devices (secret; see --no-secrets)
  add_path /var/lib/fprint                   # enrolled fingerprints (secret)

  # --- home directory ---------------------------------------------------------
  local g
  local -a CURATED_HOME=(
    # shell and dev dotfiles
    .bashrc .bash_profile .bash_logout .profile .zshrc .zprofile .zshenv .zlogin .zlogout
    .gitconfig .gitignore_global .vimrc .vim .tmux.conf .inputrc .nanorc .editorconfig .XCompose
    .face .face.icon .icons .themes .fonts .local/bin bin
    # secrets / identities (dropped by --no-secrets)
    .ssh .gnupg .pki .aws .kube .docker
    # KDE and Qt/GTK settings in ~/.config
    '.config/k*'                      # kdeglobals kwinrc kglobalshortcutsrc kscreenlockerrc klipperrc krunnerrc konsolerc kate* kdeconnect ...
    '.config/plasma*'                 # plasma-org.kde.plasma.desktop-appletsrc = panel and widget layout
    '.config/powerdevil*' .config/powermanagementprofilesrc
    .config/dolphinrc .config/spectaclerc .config/gwenviewrc .config/okularrc .config/okularpartrc
    .config/arkrc .config/systemsettingsrc .config/baloofilerc .config/breezerc .config/Trolltech.conf
    '.config/xdg-desktop-portal*' .config/mimeapps.list '.config/user-dirs.*' .config/menus
    .config/autostart .config/environment.d .config/systemd .config/fontconfig
    '.config/gtk-*' .config/Kvantum .config/qt5ct .config/qt6ct .config/xsettingsd .config/dconf
    # audio, terminal, editors, cli tools
    .config/pipewire .config/wireplumber .config/pulse .config/easyeffects
    .config/fish .config/git .config/nvim .config/helix .config/mpv .config/btop .config/htop
    .config/kitty .config/alacritty .config/wezterm .config/tmux .config/starship.toml .config/containers
    .config/Code/User/settings.json .config/Code/User/keybindings.json .config/Code/User/snippets
    .config/rclone .config/gh
    # ~/.local/share: themes, menu entries, MIME database, Plasma data, Konsole profiles...
    .local/share/applications .local/share/mime .local/share/icons .local/share/color-schemes
    .local/share/plasma .local/share/kwin .local/share/aurorae
    .local/share/konsole .local/share/kxmlgui5 .local/share/kxmlgui6 .local/share/kate
    .local/share/dolphin .local/share/kscreen .local/share/kactivitymanagerd
    .local/share/user-places.xbel .local/share/wallpapers .local/share/themes
    .local/share/kservices5 .local/share/kservices6 .local/share/knewstuff3
    .local/share/fish .local/share/nvim .local/share/flatpak/overrides
    .local/share/kwalletd .local/share/keyrings
    # Flatpak per-app settings
    '.var/app/*/config'
  )
  for g in "${CURATED_HOME[@]}"; do add_home_glob "$g"; done
  if [[ $SCOPE == broad ]]; then
    add_home_glob '.*'                # every dotfile/dot-dir; excludes drop caches and bulk
  fi

  local p
  for p in "${EXTRA_PATHS[@]+"${EXTRA_PATHS[@]}"}"; do
    [[ $p == /* ]] || { log_error "--extra-path must be absolute: $p"; continue; }
    [[ -e $p ]] && add_path "$p" || log_error "extra path not found: $p"
  done

  sort -zu "$LIST_RAW" >"$LIST"
  local n; n=$(tr -cd '\0' <"$LIST" | wc -c)
  log_success "file list built ($n top-level entries)"
  tr '\0' '\n' <"$LIST" >"$INV/included-paths.txt"
  cp "$EXCL" "$INV/excluded-patterns.txt"
}

# =============================================================================
# 3. RESTORE HELPERS + README  (go inside the archive, in _inventory/)
# =============================================================================
generate_restore_helpers() {
  section "Generating restore helpers"
  local r="$INV/restore"; mkdir -p "$r"

  cat >"$r/restore-coprs.sh" <<'EOF'
#!/usr/bin/env bash
# Re-enable COPR repos. Run as root on the fresh install. Review packages/coprs.txt first.
HERE="$(dirname "$(readlink -f "$0")")/.."
[[ -r $HERE/packages/coprs.txt ]] || exit 0
while IFS=$'\t' read -r repo enabled host; do
  [[ -n $repo ]] || continue
  [[ $host != copr.fedorainfracloud.org && -n $host ]] && repo="$host/$repo"
  dnf copr enable -y "$repo" || echo "FAILED: $repo (no build for this Fedora release?)"
  [[ $enabled == 0 ]] && dnf copr disable -y "$repo"
done <"$HERE/packages/coprs.txt"
EOF

  cat >"$r/restore-packages.sh" <<'EOF'
#!/usr/bin/env bash
# Reinstall everything you installed yourself. Run as root AFTER restoring
# /etc/yum.repos.d + /etc/pki/rpm-gpg (or enabling RPM Fusion / COPRs).
# Missing packages are skipped, not fatal. Edit the list first if you want a leaner system.
HERE="$(dirname "$(readlink -f "$0")")/.."
[[ -s $HERE/packages/userinstalled-names.txt ]] || { echo "no userinstalled list"; exit 1; }
xargs -a "$HERE/packages/userinstalled-names.txt" dnf install -y --skip-unavailable
EOF

  cat >"$r/restore-flatpaks.sh" <<'EOF'
#!/usr/bin/env bash
# Reinstall Flatpak apps (system-wide list). Run as root. For the per-user list use
# flatpak-user-apps with "flatpak --user" as your normal user.
HERE="$(dirname "$(readlink -f "$0")")/.."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
grep -vi '^flathub' "$HERE/flatpak/system-remotes.txt" 2>/dev/null | sed 's/^/NOTE: add this remote manually: /'
while read -r origin app _; do
  [[ -n $app ]] && { flatpak install -y --noninteractive "$origin" "$app" || echo "FAILED: $app"; }
done <"$HERE/flatpak/system-apps.txt"
EOF

  cat >"$r/restore-services-system.sh" <<'EOF'
#!/usr/bin/env bash
# Re-apply system units you enabled/disabled relative to Fedora's presets.
# Run as root AFTER packages are installed. Review systemd/system-changed-from-preset.txt first.
HERE="$(dirname "$(readlink -f "$0")")/.."
while read -r action unit; do
  [[ -n $unit ]] && { systemctl "$action" "$unit" || echo "FAILED: $action $unit"; }
done <"$HERE/systemd/system-changed-from-preset.txt"
EOF

  cat >"$r/restore-services-user.sh" <<'EOF'
#!/usr/bin/env bash
# Re-apply user units (run as your normal user, inside a graphical session).
HERE="$(dirname "$(readlink -f "$0")")/.."
while read -r action unit; do
  [[ -n $unit ]] && { systemctl --user "$action" "$unit" || echo "FAILED: $action $unit"; }
done <"$HERE/systemd/user-changed-from-preset.txt"
EOF
  chmod 700 "$r"/*.sh

  cat >"$INV/README-RESTORE.txt" <<EOF
Fedora backup from ${HOST}, made ${STAMP} by fedora-backup.sh ${SCRIPT_VERSION}
User: ${TARGET_USER}   Scope: ${SCOPE}   Secrets included: ${INCLUDE_SECRETS}

1. EXTRACT INTO A STAGING FOLDER (never straight over /):
     mkdir ~/restore && cd ~/restore
     gpg --decrypt BACKUP.tar.zst.gpg | zstd -dc | tar -x --xattrs --acls -p
   (unencrypted: zstd -dc BACKUP.tar.zst | tar -x --xattrs --acls -p)

2. SUGGESTED ORDER ON THE FRESH INSTALL
   a. sudo cp -a etc/yum.repos.d/. /etc/yum.repos.d/ ; sudo cp -an etc/pki/rpm-gpg/. /etc/pki/rpm-gpg/
      (or enable RPM Fusion + run _inventory/restore/restore-coprs.sh)
   b. sudo _inventory/restore/restore-packages.sh
   c. sudo _inventory/restore/restore-flatpaks.sh
   d. copy wanted files from etc/ into /etc (see warnings), then
      sudo _inventory/restore/restore-services-system.sh
   e. LOG OUT of Plasma (use a TTY, Ctrl+Alt+F3), copy home/${TARGET_USER}/. into your home,
      then sudo restorecon -RF /etc /home/${TARGET_USER}, and log back in.
      (Copying while Plasma runs lets it overwrite your settings on logout.)
   f. as your user: _inventory/restore/restore-services-user.sh
   g. selinux: sudo semanage import < _inventory/selinux/semanage-export.txt

3. DO NOT BLINDLY RESTORE (hardware/install specific)
   etc/fstab, etc/crypttab, etc/lvm/*, etc/mdadm.conf, etc/hostname, etc/machine-info,
   etc/NetworkManager/system-connections (fine if same Wi-Fi, but re-check), var/lib/bluetooth
   (works only with the same adapter), etc/default/grub (compare with the new one first).
   Passwords (/etc/shadow) and SSH host keys are deliberately NOT backed up.

4. REFERENCE LISTS: _inventory/ has package/repo/flatpak/systemd/hardware lists,
   included-paths.txt (everything archived) and excluded-patterns.txt.
EOF
  log_success "restore helpers and README"
}

# =============================================================================
# 4. ARCHIVE, VERIFY, CHECKSUM, MANIFEST
# =============================================================================
create_archive() {
  section "Creating archive"
  local -a tar_cmd=(
    tar --create --file=- --directory=/ --null
        --exclude-from="$EXCL" --exclude-caches-under --ignore-failed-read
        --acls --xattrs --numeric-owner
        --warning=no-file-changed --warning=no-file-removed
        --transform='s,^\.$,_inventory,SH' --transform='s,^\./,_inventory/,SH'
        --files-from="$LIST"
        --directory="$INV" .
  )
  local -a rc
  if (( ENCRYPT )); then
    "${tar_cmd[@]}" 2>>"$LOG_FILE" \
      | zstd -c -T0 -"$ZSTD_LEVEL" -q 2>>"$LOG_FILE" \
      | gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-fd 3 \
            --symmetric --cipher-algo AES256 --compress-algo none \
            --s2k-mode 3 --s2k-digest-algo SHA512 --s2k-count 65011712 \
            --output "$ARCHIVE" 3< <(printf '%s' "$PASSPHRASE") 2>>"$LOG_FILE"
    rc=("${PIPESTATUS[@]}")
  else
    "${tar_cmd[@]}" 2>>"$LOG_FILE" | zstd -c -T0 -"$ZSTD_LEVEL" -q 2>>"$LOG_FILE" >"$ARCHIVE"
    rc=("${PIPESTATUS[@]}")
  fi
  # tar exit 1 = "some files changed while reading": acceptable. 2 = fatal.
  if (( rc[0] <= 1 && rc[1] == 0 && ${rc[2]:-0} == 0 )) && [[ -s $ARCHIVE ]]; then
    log_success "archive written: $(du -h "$ARCHIVE" | cut -f1)"
    return 0
  fi
  log_error "archive creation failed (tar/zstd/gpg exit codes: ${rc[*]}) — see $LOG_FILE"
  rm -f "$ARCHIVE"
  return 1
}

verify_archive() {
  note "Verifying (decrypt + decompress + read every tar header)..."
  local -a rc
  if (( ENCRYPT )); then
    gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 3 --decrypt "$ARCHIVE" \
        3< <(printf '%s' "$PASSPHRASE") 2>>"$LOG_FILE" | zstd -dc -q | tar -tf - >/dev/null 2>>"$LOG_FILE"
    rc=("${PIPESTATUS[@]}")
  else
    zstd -dc -q "$ARCHIVE" 2>>"$LOG_FILE" | tar -tf - >/dev/null 2>>"$LOG_FILE"
    rc=("${PIPESTATUS[@]}")
  fi
  if (( ${rc[0]} == 0 && ${rc[1]:-0} == 0 && ${rc[2]:-0} == 0 )); then
    log_success "archive verified readable"
  else
    log_error "archive verification FAILED (exit codes: ${rc[*]})"
    return 1
  fi
}

write_manifest() {
  ( cd "$OUTPUT_DIR" && sha256sum "$(basename "$ARCHIVE")" >"$BASE.sha256" ) \
    && log_success "sha256 written" || log_error "sha256 failed"
  {
    echo "fedora-backup $SCRIPT_VERSION"
    echo "host: $HOST   user: $TARGET_USER   date: $STAMP"
    echo "fedora: $(cat /etc/fedora-release 2>/dev/null)   kernel: $(uname -r)"
    echo "scope: $SCOPE   encrypted: $ENCRYPT   secrets: $INCLUDE_SECRETS"
    echo "archive: $(basename "$ARCHIVE") ($(du -h "$ARCHIVE" | cut -f1))"
    echo "sha256: $(cut -d' ' -f1 "$OUTPUT_DIR/$BASE.sha256" 2>/dev/null)"
    echo "steps ok: ${#SUCCESS_LIST[@]}   failed: ${#ERROR_LIST[@]}   skipped: ${#SKIP_LIST[@]}"
  } >"$OUTPUT_DIR/$BASE.manifest.txt"
}

write_logs_and_summary() {
  printf '%s\n' "${SUCCESS_LIST[@]+"${SUCCESS_LIST[@]}"}" >"$OUTPUT_DIR/$BASE.log_success.txt"
  printf '%s\n' "${ERROR_LIST[@]+"${ERROR_LIST[@]}"}"     >"$OUTPUT_DIR/$BASE.log_error.txt"
  chown "$TARGET_USER": "$OUTPUT_DIR/$BASE".* 2>/dev/null || true   # may fail on FAT/exFAT; harmless
  section "Summary"
  printf '  %sSucceeded:%s %d   %sFailed:%s %d   %sSkipped:%s %d\n' \
    "$C_GRN" "$C_RST" "${#SUCCESS_LIST[@]}" "$C_RED" "$C_RST" "${#ERROR_LIST[@]}" "$C_YEL" "$C_RST" "${#SKIP_LIST[@]}"
  if ((${#ERROR_LIST[@]})); then
    echo "  Failed steps (details in $BASE.log_error.txt):"
    printf '    - %s\n' "${ERROR_LIST[@]}"
  fi
  echo "  Logs: $OUTPUT_DIR/$BASE.log{,_success.txt,_error.txt}"
}

# ================================== MAIN =====================================
collect_inventory
collect_files
generate_restore_helpers

if (( DRY_RUN )); then
  cp "$INV/included-paths.txt" "$OUTPUT_DIR/$BASE.dryrun-paths.txt"
  note "Dry run: path list saved to $OUTPUT_DIR/$BASE.dryrun-paths.txt (no archive made)"
  write_logs_and_summary
  exit 0
fi

STATUS=0
if create_archive; then
  verify_archive || STATUS=1
  chown "$TARGET_USER": "$ARCHIVE" 2>/dev/null || true
  write_manifest
else
  STATUS=1
fi
write_logs_and_summary

if (( STATUS == 0 )); then
  echo
  echo "  Backup:  $ARCHIVE"
  (( ENCRYPT )) && echo "  Keep the passphrase safe — without it the archive cannot be opened."
  echo "  Copy it (plus the .sha256) to a second location BEFORE you format."
fi
exit "$STATUS"


################################################################3

# sudo bash linux/fedora/fedora_backup_cl.sh --output-dir /home/nbhirud/nb/nb_script_data/backups/fedora_backup_cl --scope broad --no-encrypt


# Run it like this, using an external drive as the output:

# bash
# chmod +x fedora-backup.sh
# sudo ./fedora-backup.sh --output-dir /run/media/$USER/BACKUPDRIVE/fedora

# It produces one fedora-backup-<host>-<timestamp>.tar.zst.gpg, with a .sha256, a manifest and the logs (log, log_success, log_error) beside it. It never modifies your system.

# What gets backed up

# /etc: it finds this automatically rather than from a hand-written list. It takes every packaged config you changed (rpm -Va) plus every file no RPM owns (custom repos, GPG keys, units, timers, NetworkManager profiles, sudoers.d, firewalld, and so on).
# Other system state: /usr/local, Flatpak overrides, cron spool, dnf5 history and Bluetooth pairings.
# KDE and home:
# Plasma panel and widget layout, shortcuts, KWin, Konsole, Dolphin and themes.
# mimeapps.list and the local MIME database.
# Shell, git, editor and audio dotfiles.
# User systemd units, Flatpak per-app config, and SSH/GPG keys.
# _inventory/ text lists:
# User-installed RPMs, groups and which repo each package came from.
# Enabled COPRs, parsed straight from the repo files.
# Flatpaks and remotes.
# All units and timers, plus the ones you changed from Fedora’s presets.
# SELinux local changes, the kernel command line, hardware and disk UUIDs.
# Generated restore scripts: in _inventory/restore/ for COPRs, packages, Flatpaks and service enablement, plus a README-RESTORE.txt with the order to run them.

# How it follows your usual preferences

# It never aborts on a failed step.
# It logs successes, errors and skips separately.
# Options are named flags, not positional arguments.
# The comments are meant as learning notes.
# It asks for a passphrase up front and encrypts by default (AES256).
# --no-secrets leaves out SSH/GPG keys, Wi-Fi/VPN credentials, KWallet and similar.
# --scope broad adds all dot-dirs in your home, minus caches.
# --extra-path adds any extra folder.
# --dry-run only builds the file list.

# Things to know

# Fix: the sandbox’s /usr/local was huge, so check yours with du -sh /usr/local. If it’s big, exclude it or move things out.
# Left out on purpose: /etc/shadow, SSH host keys and machine-id.
# Restore carefully: extract into a staging folder, never straight over /. fstab, crypttab, LVM and Bluetooth pairings are machine-specific.
# Restore your home from a TTY: if Plasma is running while you copy settings back, it overwrites them on logout.
# No restore script yet: you restore with the generated helpers and the README steps. I can write a single fedora-restore.sh to do those steps if you want.
# Run it on each PC: every run is per machine, and the output name includes the hostname.


