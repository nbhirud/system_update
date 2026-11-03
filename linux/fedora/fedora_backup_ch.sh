#!/usr/bin/env bash
# Fedora KDE configuration and migration backup
# Run as the logged-in desktop user (NOT with sudo). The script uses sudo only
# for reading system-owned configuration and cron/SELinux state.
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_VERSION="1.1"
DEFAULT_DEST="${HOME}/fedora-migration-backups"
DEST="$DEFAULT_DEST"

usage() {
  cat <<'USAGE'
Usage:
  ./fedora-kde-backup.sh [--dest DIRECTORY]

Options:
  --dest DIRECTORY  Write the backup folder to this location (for example,
                    a mounted external drive).
  -h, --help        Show this help.

Run as your normal desktop user, not via sudo. You will be prompted for sudo
once so the script can read system configuration files.
USAGE
}

while (($#)); do
  case "$1" in
    --dest)
      [[ $# -ge 2 ]] || { echo "ERROR: --dest requires a directory" >&2; exit 2; }
      DEST="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if (( EUID == 0 )); then
  echo "ERROR: Do not run this script with sudo. Run it as your normal KDE user." >&2
  exit 1
fi

if [[ ! -d "$HOME" ]]; then
  echo "ERROR: HOME does not exist: $HOME" >&2
  exit 1
fi

for required in tar sha256sum find sort; do
  command -v "$required" >/dev/null 2>&1 || {
    echo "ERROR: Required command not found: $required" >&2
    exit 1
  }
done

command -v sudo >/dev/null 2>&1 || {
  echo "ERROR: sudo is required to read system configuration." >&2
  exit 1
}

printf 'This backup can contain Wi-Fi passwords, browser sessions, SSH/GPG keys,\n'
printf 'KWallet data, tokens, certificates, and other secrets. Store it securely.\n\n'
sudo -v

mkdir -p -- "$DEST"
chmod 700 -- "$DEST" 2>/dev/null || true
HOST="$(hostname -s 2>/dev/null || hostname)"
HOST_SAFE="$(printf '%s' "$HOST" | tr -cs 'A-Za-z0-9._-' '_')"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="$(mktemp -d -- "$DEST/fedora-kde-${HOST_SAFE}-${STAMP}-XXXXXX")"
chmod 700 -- "$OUT" 2>/dev/null || true
mkdir -p -- "$OUT/archives" "$OUT/inventory" "$OUT/logs"

LOG="$OUT/logs/backup.log"
WARNINGS="$OUT/WARNINGS.txt"
: > "$WARNINGS"
ERRORS=0

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }
warn() {
  printf '[WARNING] %s\n' "$*" | tee -a "$WARNINGS" "$LOG" >&2
}
error() {
  ERRORS=$((ERRORS + 1))
  printf '[ERROR] %s\n' "$*" | tee -a "$WARNINGS" "$LOG" >&2
}

# Save output from a command without aborting the whole backup if an optional
# command is missing or unavailable. The failed command and exit code are noted.
capture_cmd() {
  local output="$1"; shift
  mkdir -p -- "$(dirname -- "$output")"
  {
    printf '# Command:'
    printf ' %q' "$@"
    printf '\n\n'
  } > "$output"
  if "$@" >> "$output" 2>&1; then
    :
  else
    local rc=$?
    printf '\n[Command returned exit code %s]\n' "$rc" >> "$output"
    warn "Command failed (exit $rc): $*"
  fi
}

capture_shell_block() {
  local output="$1"
  shift
  # The supplied body is a function name; execute it in a non-fatal subshell.
  if ( set +e; "$@" ) > "$output" 2>&1; then
    :
  else
    warn "Some commands in $(basename -- "$output") returned errors; see that file."
  fi
}

log "Starting Fedora KDE backup v${SCRIPT_VERSION}"
log "User: $(id -un) | Home: $HOME | Host: $HOST | Destination: $OUT"

if [[ -r /etc/fedora-release ]]; then
  log "Detected: $(cat /etc/fedora-release)"
else
  warn "This does not appear to be a Fedora installation (/etc/fedora-release missing)."
fi

# Pick a compressor. zstd is faster/smaller when installed; gzip is the fallback.
if command -v zstd >/dev/null 2>&1; then
  COMPRESS_ARGS=(--use-compress-program='zstd -T0 -8')
  ARCHIVE_EXT="tar.zst"
else
  COMPRESS_ARGS=(--gzip)
  ARCHIVE_EXT="tar.gz"
fi

# ---------------------------------------------------------------------------
# 1. System configuration: /etc contains DNF repos/COPRs, DNF5 overrides,
#    MIME defaults, NetworkManager connections, systemd units/drop-ins,
#    cron config, SSH host identity, firewall, SELinux, boot config, etc.
#    /usr/local contains locally installed scripts and custom unit files.
# ---------------------------------------------------------------------------
SYSTEM_PATHS=(etc opt usr/local root)
# Include the systemd unit search directories and DNF5 vendor repository files
# too. Package-owned files will be reinstalled with their RPMs, but capturing
# them also preserves locally modified/hand-installed definitions for review.
for path in \
  usr/lib/systemd/system usr/lib/systemd/user \
  usr/share/dnf5/repos.d usr/share/dnf5/vars.d \
  var/spool/cron var/lib/selinux \
  var/lib/flatpak/repo/config var/lib/flatpak/overrides; do
  [[ -e "/$path" || -L "/$path" ]] && SYSTEM_PATHS+=("$path")
done
SYSTEM_ARCHIVE="$OUT/archives/system-files.$ARCHIVE_EXT"
log "Archiving system configuration (this includes sensitive files under /etc and /root)."
if sudo tar --create "${COMPRESS_ARGS[@]}" --file="$SYSTEM_ARCHIVE" \
    --directory=/ --numeric-owner --acls --xattrs --selinux \
    --exclude='root/.cache' --exclude='root/.local/share/Trash' \
    "${SYSTEM_PATHS[@]}"; then
  if sudo chown "$(id -u):$(id -g)" "$SYSTEM_ARCHIVE"; then
    chmod 600 -- "$SYSTEM_ARCHIVE" 2>/dev/null || true
    log "Created $SYSTEM_ARCHIVE"
  else
    warn "Could not change archive ownership; use sudo to access $SYSTEM_ARCHIVE."
  fi
else
  error "System configuration archive failed."
  rm -f -- "$SYSTEM_ARCHIVE"
fi

# ---------------------------------------------------------------------------
# 2. User settings/data: Plasma/KWin/KDE app config, user MIME associations,
#    autostart entries, user systemd units, themes/icons/fonts/wallpapers,
#    Flatpak per-app data, dotfiles, SSH/GPG, browser and mail profiles.
#    Caches and downloaded Flatpak runtimes are excluded to reduce size.
# ---------------------------------------------------------------------------
USER_PATHS=(
  .config .local .var .kde .themes .icons .fonts .ssh .gnupg .pki
  .mozilla .thunderbird
  .bashrc .bash_profile .profile .zshrc .zprofile .zshenv .inputrc
  .vimrc .gitconfig .gitignore .git-credentials .netrc
)
EXISTING_USER_PATHS=()
for path in "${USER_PATHS[@]}"; do
  if [[ -e "$HOME/$path" || -L "$HOME/$path" ]]; then
    EXISTING_USER_PATHS+=("$path")
  fi
done
USER_ARCHIVE="$OUT/archives/user-configs.$ARCHIVE_EXT"
log "Archiving user configuration for $(id -un)."
if ((${#EXISTING_USER_PATHS[@]})); then
  if tar --create "${COMPRESS_ARGS[@]}" --file="$USER_ARCHIVE" \
      --directory="$HOME" --acls --xattrs \
      --exclude='.cache' --exclude='*/.cache' \
      --exclude='.local/share/Trash' --exclude='.local/share/baloo' \
      --exclude='.local/share/flatpak' \
      --exclude='.var/app/*/cache' --exclude='.var/app/*/data/*/cache' \
      --exclude='*/Cache' --exclude='*/Cache/*' \
      --exclude='*/Code Cache' --exclude='*/GPUCache' \
      --exclude='*/shadercache' \
      "${EXISTING_USER_PATHS[@]}"; then
    chmod 600 -- "$USER_ARCHIVE" 2>/dev/null || true
    log "Created $USER_ARCHIVE"
  else
    error "User configuration archive failed."
    rm -f -- "$USER_ARCHIVE"
  fi
else
  warn "No recognized user configuration paths found in $HOME."
fi

# ---------------------------------------------------------------------------
# 3. Inventory and state reports. These are text files intended to make
#    rebuilding the machines easier; they do not replace the file archives.
# ---------------------------------------------------------------------------
log "Collecting OS, hardware, package, repository, Flatpak, service and timer inventories."

collect_system_overview() {
  echo '=== BACKUP CONTEXT ==='
  date --iso-8601=seconds
  printf 'Hostname: '; hostname 2>/dev/null || true
  printf 'User: '; id 2>/dev/null || true
  printf '\n=== FEDORA RELEASE ===\n'
  cat /etc/fedora-release 2>/dev/null || true
  cat /etc/os-release 2>/dev/null || true
  printf '\n=== KERNEL / ARCHITECTURE ===\n'
  uname -a 2>/dev/null || true
  printf '\n=== KDE / PLASMA ===\n'
  plasmashell --version 2>&1 || true
  kwin --version 2>&1 || true
  kf6-config --version 2>&1 || true
  printf '\n=== HOST / LOCALE / TIME ===\n'
  hostnamectl 2>&1 || true
  localectl status 2>&1 || true
  timedatectl 2>&1 || true
  printf '\n=== CPU / MEMORY / STORAGE ===\n'
  lscpu 2>&1 || true
  free -h 2>&1 || true
  lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS 2>&1 || lsblk 2>&1 || true
  findmnt 2>&1 || true
  printf '\n=== PCI / USB ===\n'
  lspci -nnk 2>&1 || true
  lsusb 2>&1 || true
  printf '\n=== BOOT ===\n'
  sudo efibootmgr -v 2>&1 || true
  bootctl status 2>&1 || true
  sudo grubby --info=ALL 2>&1 || true
}
capture_shell_block "$OUT/inventory/system-overview.txt" collect_system_overview

capture_cmd "$OUT/inventory/rpm-all-installed.txt" \
  rpm -qa --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\t%{ARCH}\n'
if command -v dnf >/dev/null 2>&1; then
  DNF=(dnf)
elif command -v dnf5 >/dev/null 2>&1; then
  DNF=(dnf5)
else
  DNF=()
fi
if ((${#DNF[@]})); then
  capture_cmd "$OUT/inventory/dnf-user-installed.txt" \
    "${DNF[@]}" repoquery --userinstalled --queryformat '%{name}\t%{reason}\t%{arch}\n'
  capture_cmd "$OUT/inventory/dnf-repositories-all.txt" \
    "${DNF[@]}" repolist --all
  capture_cmd "$OUT/inventory/copr-repositories.txt" \
    "${DNF[@]}" copr list
  capture_cmd "$OUT/inventory/dnf-history.txt" \
    "${DNF[@]}" history list
  capture_cmd "$OUT/inventory/dnf-groups-installed.txt" \
    "${DNF[@]}" group list --installed
else
  warn "Neither dnf nor dnf5 was found; package/repository inventories are incomplete."
fi

capture_cmd "$OUT/inventory/rpm-gpg-keys-installed.txt" \
  rpm -qa 'gpg-pubkey*' --qf '%{NAME}-%{VERSION}-%{RELEASE}\n'

capture_cmd "$OUT/inventory/flatpak-apps-all.txt" \
  flatpak list --app --columns=application,ref,origin,installation
capture_cmd "$OUT/inventory/flatpak-remotes-all.txt" \
  flatpak remotes --show-details
capture_cmd "$OUT/inventory/flatpak-apps-user.txt" \
  flatpak list --user --app --columns=application,ref,origin,installation
capture_cmd "$OUT/inventory/flatpak-apps-system.txt" \
  flatpak list --system --app --columns=application,ref,origin,installation
capture_cmd "$OUT/inventory/flatpak-user-overrides.txt" flatpak override --show
capture_cmd "$OUT/inventory/flatpak-system-overrides.txt" flatpak override --system --show

collect_systemd() {
  echo '=== SYSTEM SERVICES: UNIT FILES ==='
  systemctl list-unit-files --type=service --all --no-pager 2>&1 || true
  echo '\n=== SYSTEM SERVICES: CURRENT STATE ==='
  systemctl list-units --type=service --all --no-pager 2>&1 || true
  echo '\n=== SYSTEM TIMERS: UNIT FILES ==='
  systemctl list-unit-files --type=timer --all --no-pager 2>&1 || true
  echo '\n=== SYSTEM TIMERS: SCHEDULES / NEXT RUNS ==='
  systemctl list-timers --all --no-pager 2>&1 || true
  echo '\n=== SYSTEM FAILED UNITS ==='
  systemctl --failed --no-pager 2>&1 || true
}
capture_shell_block "$OUT/inventory/systemd-system.txt" collect_systemd

collect_user_systemd() {
  echo '=== USER SERVICES: UNIT FILES ==='
  systemctl --user list-unit-files --type=service --all --no-pager 2>&1 || true
  echo '\n=== USER SERVICES: CURRENT STATE ==='
  systemctl --user list-units --type=service --all --no-pager 2>&1 || true
  echo '\n=== USER TIMERS: UNIT FILES ==='
  systemctl --user list-unit-files --type=timer --all --no-pager 2>&1 || true
  echo '\n=== USER TIMERS: SCHEDULES / NEXT RUNS ==='
  systemctl --user list-timers --all --no-pager 2>&1 || true
  echo '\n=== USER FAILED UNITS ==='
  systemctl --user --failed --no-pager 2>&1 || true
}
capture_shell_block "$OUT/inventory/systemd-user.txt" collect_user_systemd

collect_other_state() {
  echo '=== USER CRONTAB ==='
  crontab -l 2>&1 || true
  echo '\n=== ROOT CRONTAB ==='
  sudo crontab -l -u root 2>&1 || true
  echo '\n=== NETWORKMANAGER CONNECTIONS (names and metadata only) ==='
  nmcli -f NAME,UUID,TYPE,DEVICE connection show 2>&1 || true
  echo '\n=== NETWORKMANAGER DEVICES ==='
  nmcli device status 2>&1 || true
  echo '\n=== IP ADDRESSES / ROUTES ==='
  ip -brief address 2>&1 || true
  ip route 2>&1 || true
  echo '\n=== FIREWALLD ZONES ==='
  sudo firewall-cmd --list-all-zones 2>&1 || true
  echo '\n=== NFTABLES RULESET ==='
  sudo nft list ruleset 2>&1 || true
  echo '\n=== SELINUX ==='
  getenforce 2>&1 || true
  sudo semodule -lfull 2>&1 || true
  echo '\n=== PRINTERS ==='
  lpstat -t 2>&1 || true
  echo '\n=== USB / INPUT DEVICES ==='
  lsusb 2>&1 || true
  echo '\n=== USER / GROUP IDS ==='
  id 2>&1 || true
  getent passwd 2>&1 || true
  getent group 2>&1 || true
  echo '\n=== RPM TRANSACTION HISTORY (summary) ==='
  rpm -qa --last 2>&1 | head -n 100 || true
}
capture_shell_block "$OUT/inventory/services-network-security.txt" collect_other_state

collect_mime_and_desktop() {
  echo '=== XDG DIRECTORIES ==='
  xdg-user-dir DESKTOP 2>&1 || true
  xdg-user-dir DOCUMENTS 2>&1 || true
  xdg-user-dir DOWNLOAD 2>&1 || true
  xdg-user-dir MUSIC 2>&1 || true
  xdg-user-dir PICTURES 2>&1 || true
  xdg-user-dir VIDEOS 2>&1 || true
  echo '\n=== MIME DEFAULTS (common types) ==='
  for mime in text/plain text/html application/pdf image/png; do
    printf '%s: ' "$mime"
    xdg-mime query default "$mime" 2>&1 || true
  done
  echo '\n=== USER MIME ASSOCIATION FILES ==='
  for f in "$HOME/.config/mimeapps.list" "$HOME/.local/share/applications/mimeapps.list"; do
    if [[ -f "$f" ]]; then
      echo "--- $f ---"
      cat "$f"
    fi
  done
  echo '\n=== GTK/DBUS DCONF SETTINGS ==='
  dconf dump / 2>&1 || true
}
capture_shell_block "$OUT/inventory/mime-desktop-settings.txt" collect_mime_and_desktop

# Save a concise map of relevant configuration paths, including important
# folders that users may want to migrate selectively.
cat > "$OUT/INCLUDED-CONTENT.txt" <<'NOTES'
SYSTEM ARCHIVE
  /etc                 All system configuration: DNF5 repositories and overrides,
                       COPR .repo files, RPM GPG keys, MIME defaults, NetworkManager,
                       systemd units/drop-ins/enabled symlinks, cron, SSH host keys,
                       firewall, SELinux, fstab/crypttab, boot/dracut/modprobe/sysctl,
                       sudoers, users/groups, certificates, and more.
  /opt                 Manually installed third-party applications, when present.
  /usr/local           Locally installed scripts, binaries, libraries and custom units.
  /usr/lib/systemd     System/vendor service, timer and user-unit definitions.
  /usr/share/dnf5      Fedora/vendor DNF5 repo definitions and variables.
  /root                Root user's home/configuration (cache and Trash excluded).
  /var/spool/cron      Per-user cron spool, when present.
  /var/lib/selinux     SELinux policy/module store, when present.
  /var/lib/flatpak     System Flatpak repo config and overrides only, when present.

USER ARCHIVE (existing paths only)
  ~/.config            KDE Plasma/KWin/KDE application settings, autostart,
                       file associations, user systemd unit files, etc.
  ~/.local             User applications, MIME database, desktop entries, icons,
                       themes, fonts, wallpapers, scripts, and other local state.
  ~/.var               Flatpak per-application user data/settings.
  ~/.themes ~/.icons ~/.fonts, ~/.kde, ~/.ssh, ~/.gnupg, ~/.pki
  Browser/mail profiles and common shell/editor/Git dotfiles, when present.

INVENTORIES
  RPM package list; DNF user-installed package list, repositories, COPRs, groups
  and history; Flatpak apps/remotes; system and user services/timers; hardware,
  boot, network, firewall, SELinux, printers, MIME defaults and dconf settings.

Excluded to reduce size: user/root caches, KDE Baloo index, Trash, user Flatpak
runtime installation (~/.local/share/flatpak), and common browser/app cache folders.
NOTES

cat > "$OUT/RESTORE-CAUTIONS.txt" <<'NOTES'
IMPORTANT RESTORE NOTES

1. This is a backup, not an automatic restore script. Inspect the inventories and
   selectively restore settings after installing the target Fedora/KDE system.

2. Do NOT blindly extract all of /etc or /root onto a different PC. These contain
   machine-specific settings, user/group IDs, secrets, certificates, SSH host keys,
   network settings, fstab/crypttab entries, boot configuration and other identity
   or hardware-dependent data. In particular, never copy SSH host keys or a machine
   identity from one PC to another.

3. For same-machine recovery, compare files first, then restore only what is needed.
   Example archive inspection:
     tar -tzf archives/system-files.tar.gz | less
     tar -tzf archives/user-configs.tar.gz | less
   For .tar.zst archives, use:
     tar --use-compress-program=unzstd -tf archives/system-files.tar.zst | less

4. User settings can usually be selectively restored while logged out of KDE. Back
   up the fresh install's current ~/.config and ~/.local before replacing anything.
   Preserve ownership as the target user; do not restore a user archive as root.

5. Reinstall applications from rpm-all-installed.txt / dnf-user-installed.txt,
   re-add repositories/COPRs from the inventory, and reinstall Flatpaks using the
   recorded app IDs/remotes. Review third-party repositories for Fedora 44 support
   before enabling them; do not blindly reuse old repo definitions.

6. System services and timers: custom definitions/drop-ins and enablement symlinks
   are included in the system archive (/etc and /usr/local). Review unit files,
   paths and dependencies before enabling them on another machine.

7. The backup contains secrets: Wi-Fi credentials, browser/mail sessions, SSH/GPG
   material, KWallet data, tokens, keys, certificates and possibly password hashes.
   Keep it on an encrypted drive or encrypt it before cloud storage/sharing.

8. External files referenced by settings (custom wallpapers outside ~/.local/share,
   scripts stored elsewhere, app-specific data outside the included paths, VM images,
   containers, databases and personal documents) are not necessarily included.
NOTES

# Record versions and file sizes for quick identification.
{
  printf 'Script version: %s\n' "$SCRIPT_VERSION"
  printf 'Created: %s\n' "$(date --iso-8601=seconds)"
  printf 'Hostname: %s\n' "$HOST"
  printf 'User: %s (%s)\n' "$(id -un)" "$(id -u)"
  printf 'Home: %s\n' "$HOME"
  printf 'Fedora: %s\n' "$(cat /etc/fedora-release 2>/dev/null || echo unknown)"
  printf 'Kernel: %s\n' "$(uname -r)"
  printf 'Compressor: %s\n' "$ARCHIVE_EXT"
  printf '\nFiles created:\n'
  find "$OUT" -maxdepth 2 -type f -printf '%P\t%s bytes\n' | sort
} > "$OUT/BACKUP-SUMMARY.txt"

# Checksums cover the archives, inventories, notes and log.
(
  cd "$OUT"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 -r sha256sum > SHA256SUMS
)
chmod 600 -- "$OUT"/archives/* "$OUT"/inventory/* "$OUT"/logs/* \
  "$OUT"/WARNINGS.txt "$OUT"/INCLUDED-CONTENT.txt \
  "$OUT"/RESTORE-CAUTIONS.txt "$OUT"/BACKUP-SUMMARY.txt "$OUT"/SHA256SUMS 2>/dev/null || true

log "Backup finished. Errors: $ERRORS"
log "Output directory: $OUT"
log "Verify integrity with: (cd '$OUT' && sha256sum -c SHA256SUMS)"

if (( ERRORS > 0 )); then
  echo "Backup completed with errors. Review: $WARNINGS" >&2
  exit 1
fi

echo
echo "Backup completed successfully:"
echo "  $OUT"
echo
echo "Verify checksums with:"
echo "  cd '$OUT' && sha256sum -c SHA256SUMS"



#########################################################################################


# bash linux/fedora/fedora_backup_ch.sh --dest "/home/nbhirud/nb/nb_script_data/backups/fedora_backup_ch"

# What it backs up
# Category	Coverage
# System configuration	Entire /etc, including network, security, boot and application settings
# DNF5	Repository definitions, overrides, variables and GPG keys
# COPR	Configured projects and repository inventory
# Systemd	System and user service definitions, drop-ins, enablement states and timers
# KDE Plasma	Plasma, KWin, Dolphin, Konsole, shortcuts, themes and desktop layout
# MIME	MIME database, default applications and file associations
# User configuration	.config, .local, .var, shell settings and dotfiles
# Security	SSH, GPG, certificates, KWallet-related data and credentials
# Other	Cron jobs, SELinux, firewall, printers, Flatpak, installed RPMs and hardware information

# The DNF5 repository and COPR handling follows the current DNF5 command/configuration structure. 
# dnf5 documentation+2
#  Systemd unit directories are also included, covering the standard system and user unit search locations. 
# Freedesktop

# Running it
# Run this as your normal KDE user, not with sudo.
# chmod +x fedora-kde-backup.sh

# ./fedora-kde-backup.sh


# To save directly to an external drive:
# ./fedora-kde-backup.sh --dest "/run/media/$USER/BackupDrive"


# The script requests sudo access when necessary.
# What gets generated
# Each PC gets its own uniquely named backup directory, containing:
# fedora-kde-HOSTNAME-DATE/
# │
# ├── archives/
# │   ├── system-files.tar.zst
# │   └── user-configs.tar.zst
# │
# ├── inventory/
# │   ├── rpm-all-installed.txt
# │   ├── dnf-user-installed.txt
# │   ├── dnf-repositories-all.txt
# │   ├── copr-repositories.txt
# │   ├── flatpak-apps-all.txt
# │   ├── systemd-system.txt
# │   ├── systemd-user.txt
# │   ├── services-network-security.txt
# │   ├── mime-desktop-settings.txt
# │   └── system-overview.txt
# │
# ├── BACKUP-SUMMARY.txt
# ├── INCLUDED-CONTENT.txt
# ├── RESTORE-CAUTIONS.txt
# ├── WARNINGS.txt
# └── SHA256SUMS


# It uses Zstandard compression when available, otherwise gzip.
# Important precautions before formatting
# 1. Protect the backup. It contains passwords, Wi-Fi credentials, private keys, browser sessions and other sensitive information. Use an encrypted external drive.
# 2. Check the archives. Run sha256sum -c SHA256SUMS and inspect both archives before formatting.
# 3. Keep PC backups separate. Never blindly restore one PC's complete /etc, machine identity or SSH host keys onto another PC.
# 4. This is a configuration backup, not a full disk backup. Personal documents, VM images, container volumes and arbitrary application databases outside the selected locations are not comprehensively included.
# I've checked the script's Bash syntax and help output. I haven't executed it on an actual Fedora 44 machine, so review the first backup and its warnings before relying on it for the other PCs.

# A useful safeguard is to verify each PC's backup before erasing its installation.