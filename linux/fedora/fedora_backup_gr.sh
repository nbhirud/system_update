#!/usr/bin/env bash
################################################################################
# fedora-kde-config-backup.sh
# Robust backup of Fedora 44/45 KDE Plasma configs, repos, COPRs, systemd
# units/timers, MIME, package state, and critical /etc pieces.
# Multi-PC safe (hostname + timestamp). Educational, FOSS-first.
#
# Useful Links:
#   https://docs.fedoraproject.org/
#   https://discussion.fedoraproject.org/
#   https://github.com/fedora-copr/copr
#   man dnf5, man systemctl, man firewall-cmd
#   KDE config locations: https://github.com/shalva97/kde-configuration-files
################################################################################

set -euo pipefail
IFS=$'\n\t'

################################################################################
# User-defined
################################################################################
# Override these or pass via options

INCLUDE_SSH_PRIVATE="${INCLUDE_SSH_PRIVATE:-no}"   # yes|no
INCLUDE_GPG_PRIVATE="${INCLUDE_GPG_PRIVATE:-no}"   # yes|no
INCLUDE_FULL_LOCAL_SHARE="${INCLUDE_FULL_LOCAL_SHARE:-no}"  # yes|no (selective is safer)
DRY_RUN="${DRY_RUN:-no}"
VERIFY_ONLY="${VERIFY_ONLY:-no}"

################################################################################
# Inferred / Detection
################################################################################
SCRIPT_NAME="$(basename "$0")"
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"                    # your standard if present
# CODEPROJECTS_DIR="${HOME_DIR}/CodeProjects"
SCRIPT_DATA="${NBDIR}/nb_script_data"
BACKUP_ROOT="${SCRIPT_DATA}/backups/fedora_backup_gr"
BACKUP_DIR="${BACKUP_ROOT}/${HOSTNAME_SHORT}_${TIMESTAMP}"
LOG_FILE="${BACKUP_DIR}/backup.log"

# Detect
DISTRO="$(. /etc/os-release 2>/dev/null; echo "${ID:-unknown}")"
VERSION_ID="$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-unknown}")"
DE="unknown"
if [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]] || [[ "${DESKTOP_SESSION:-}" == *plasma* ]]; then
  DE="KDE"
fi
ARCH="$(uname -m)"
CPU_CORES="$(nproc 2>/dev/null || echo 1)"
# Simple RAM profile
MEM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
MEM_GB=$((MEM_KB / 1024 / 1024))

################################################################################
# Options (named only)
################################################################################
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --backup-root DIR          Destination root (default: $BACKUP_ROOT)
  --include-ssh-private      Include private SSH keys (default: no)
  --include-gpg-private      Include private GPG keys (default: no)
  --include-full-local-share Include entire ~/.local/share (default: selective)
  --dry-run                  Show what would be done
  --verify-setup             Check environment + write dirs, exit
  --help                     This help

Sample calls:
  $SCRIPT_NAME --verify-setup
  $SCRIPT_NAME --backup-root /mnt/external/fedora-backups
  sudo $SCRIPT_NAME --backup-root /mnt/backup --include-ssh-private
  $SCRIPT_NAME --dry-run

Environment overrides:
  BACKUP_ROOT, INCLUDE_SSH_PRIVATE=yes, INCLUDE_GPG_PRIVATE=yes,
  INCLUDE_FULL_LOCAL_SHARE=yes, DRY_RUN=yes
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-root) BACKUP_ROOT="$2"; shift 2 ;;
    --include-ssh-private) INCLUDE_SSH_PRIVATE=yes; shift ;;
    --include-gpg-private) INCLUDE_GPG_PRIVATE=yes; shift ;;
    --include-full-local-share) INCLUDE_FULL_LOCAL_SHARE=yes; shift ;;
    --dry-run) DRY_RUN=yes; shift ;;
    --verify-setup) VERIFY_ONLY=yes; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

BACKUP_DIR="${BACKUP_ROOT}/${HOSTNAME_SHORT}_${TIMESTAMP}"
LOG_FILE="${BACKUP_DIR}/backup.log"

################################################################################
# Helpers (log_*, detection, common)
################################################################################
log_info()  { echo "[INFO]  $(date '+%F %T') $*" | tee -a "${LOG_FILE:-/dev/null}"; }
log_warn()  { echo "[WARN]  $(date '+%F %T') $*" | tee -a "${LOG_FILE:-/dev/null}"; }
log_error() { echo "[ERROR] $(date '+%F %T') $*" | tee -a "${LOG_FILE:-/dev/null}" >&2; }
log_ok()    { echo "[OK]    $(date '+%F %T') $*" | tee -a "${LOG_FILE:-/dev/null}"; }

die() { log_error "$*"; exit 1; }

run() {
  if [[ "$DRY_RUN" == "yes" ]]; then
    log_info "DRY-RUN: $*"
  else
    log_info "RUN: $*"
    "$@"
  fi
}

check_root_or_sudo() {
  if [[ $EUID -ne 0 ]]; then
    log_warn "Not root. System parts (/etc, systemd system units) will be skipped or use sudo."
    return 1
  fi
  return 0
}

detect_and_report() {
  log_info "Distro: $DISTRO $VERSION_ID | DE: $DE | Arch: $ARCH | Cores: $CPU_CORES | RAM: ~${MEM_GB}G"
  log_info "Real user: $REAL_USER | HOME: $HOME_DIR"
  log_info "Backup target: $BACKUP_DIR"
  if [[ "$DISTRO" != "fedora" ]]; then
    log_warn "Not Fedora. Script is tuned for Fedora 44/45 + KDE. Continuing anyway."
  fi
  if [[ "$DE" != "KDE" ]]; then
    log_warn "KDE not detected as current desktop. KDE paths still backed up if present."
  fi
}

################################################################################
# Backup → Reset → Main structure (backup only here)
################################################################################
prepare_dirs() {
  run mkdir -p "$BACKUP_DIR"/{system,user,packages,logs,metadata}
  run mkdir -p "$BACKUP_DIR"/system/{yum.repos.d,dnf,systemd,firewalld,mime,network,etc-select}
  run mkdir -p "$BACKUP_DIR"/user/{config,local-share,dotfiles,systemd-user}
  # Ownership for non-root runs
  if [[ $EUID -eq 0 ]]; then
    run chown -R "$REAL_USER:$REAL_USER" "$BACKUP_DIR" || true
  fi
}

backup_metadata() {
  log_info "=== Metadata ==="
  {
    echo "hostname=$HOSTNAME_SHORT"
    echo "timestamp=$TIMESTAMP"
    echo "distro=$DISTRO $VERSION_ID"
    echo "de=$DE"
    echo "arch=$ARCH"
    echo "real_user=$REAL_USER"
    echo "kernel=$(uname -r)"
    echo "script=$SCRIPT_NAME"
  } > "$BACKUP_DIR/metadata/info.txt"
  run cp /etc/os-release "$BACKUP_DIR/metadata/" 2>/dev/null || true
  run uname -a > "$BACKUP_DIR/metadata/uname.txt" || true
  run hostnamectl > "$BACKUP_DIR/metadata/hostnamectl.txt" 2>/dev/null || true
}

backup_packages() {
  log_info "=== Package state (critical for restore) ==="
  local pkgdir="$BACKUP_DIR/packages"
  # Prefer dnf5 style; fallback gracefully
  if command -v dnf >/dev/null; then
    run dnf list --installed > "$pkgdir/dnf-list-installed.txt" 2>/dev/null || true
    run dnf repoquery --userinstalled > "$pkgdir/dnf-userinstalled.txt" 2>/dev/null || true
    run dnf history list --limit=50 > "$pkgdir/dnf-history-summary.txt" 2>/dev/null || true
    run dnf group list --installed > "$pkgdir/dnf-groups-installed.txt" 2>/dev/null || true
    run dnf repolist --all > "$pkgdir/dnf-repolist-all.txt" 2>/dev/null || true
    run dnf copr list > "$pkgdir/dnf-copr-list.txt" 2>/dev/null || true
  fi
  run rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > "$pkgdir/rpm-qa.txt" 2>/dev/null || true
  if command -v flatpak >/dev/null; then
    run flatpak list --app --columns=application,version,origin > "$pkgdir/flatpak-apps.txt" 2>/dev/null || true
    run flatpak list --runtime --columns=application,version,origin > "$pkgdir/flatpak-runtimes.txt" 2>/dev/null || true
  fi
  log_ok "Package lists captured"
}

backup_repos_and_dnf() {
  log_info "=== Repos + DNF + COPR files ==="
  if [[ -d /etc/yum.repos.d ]]; then
    run cp -a /etc/yum.repos.d/. "$BACKUP_DIR/system/yum.repos.d/" || log_warn "yum.repos.d copy partial"
  fi
  if [[ -d /etc/dnf ]]; then
    run cp -a /etc/dnf/. "$BACKUP_DIR/system/dnf/" 2>/dev/null || true
  fi
  # Explicit COPR list already in packages/
  log_ok "Repos and DNF config backed up"
}

backup_systemd() {
  log_info "=== Systemd units + timers ==="
  # System
  if [[ -d /etc/systemd/system ]]; then
    run find /etc/systemd/system -maxdepth 2 \( -name '*.service' -o -name '*.timer' -o -name '*.target' -o -name '*.path' \) \
      -exec cp -a --parents {} "$BACKUP_DIR/system/systemd/" \; 2>/dev/null || true
    # Also capture drop-ins
    run find /etc/systemd/system -type d -name '*.d' -exec cp -a --parents {} "$BACKUP_DIR/system/systemd/" \; 2>/dev/null || true
  fi
  # Enabled units snapshot
  run systemctl list-unit-files --type=service,timer --state=enabled > "$BACKUP_DIR/system/systemd/enabled-units.txt" 2>/dev/null || true
  run systemctl list-timers --all > "$BACKUP_DIR/system/systemd/timers-all.txt" 2>/dev/null || true

  # User units (as real user)
  local user_systemd="${HOME_DIR}/.config/systemd/user"
  if [[ -d "$user_systemd" ]]; then
    run cp -a "$user_systemd/." "$BACKUP_DIR/user/systemd-user/" || true
  fi
  # List user enabled (best effort)
  run sudo -u "$REAL_USER" systemctl --user list-unit-files --type=service,timer --state=enabled \
    > "$BACKUP_DIR/user/systemd-user/enabled-user-units.txt" 2>/dev/null || true
  log_ok "Systemd captured"
}

backup_mime() {
  log_info "=== MIME associations ==="
  # System
  [[ -f /etc/mime.types ]] && run cp -a /etc/mime.types "$BACKUP_DIR/system/mime/" || true
  [[ -d /etc/xdg ]] && run cp -a /etc/xdg/mimeapps.list "$BACKUP_DIR/system/mime/" 2>/dev/null || true
  # User
  [[ -f "${HOME_DIR}/.config/mimeapps.list" ]] && run cp -a "${HOME_DIR}/.config/mimeapps.list" "$BACKUP_DIR/user/config/" || true
  [[ -d "${HOME_DIR}/.local/share/mime" ]] && run cp -a "${HOME_DIR}/.local/share/mime" "$BACKUP_DIR/user/local-share/" || true
  [[ -d "${HOME_DIR}/.local/share/applications" ]] && run cp -a "${HOME_DIR}/.local/share/applications" "$BACKUP_DIR/user/local-share/" || true
  log_ok "MIME backed up"
}

backup_firewall_network() {
  log_info "=== Firewalld + NetworkManager (selected) ==="
  if [[ -d /etc/firewalld ]]; then
    run cp -a /etc/firewalld/. "$BACKUP_DIR/system/firewalld/" 2>/dev/null || true
  fi
  # NetworkManager connections (system)
  if [[ -d /etc/NetworkManager/system-connections ]]; then
    run mkdir -p "$BACKUP_DIR/system/network/system-connections"
    run cp -a /etc/NetworkManager/system-connections/. "$BACKUP_DIR/system/network/system-connections/" 2>/dev/null || true
  fi
  [[ -f /etc/hostname ]] && run cp -a /etc/hostname "$BACKUP_DIR/system/etc-select/" || true
  [[ -f /etc/hosts ]] && run cp -a /etc/hosts "$BACKUP_DIR/system/etc-select/" || true
  log_ok "Firewall + network selected files"
}

backup_etc_select() {
  log_info "=== Selected /etc pieces ==="
  local files=(
    /etc/environment
    /etc/locale.conf
    /etc/vconsole.conf
    /etc/security/limits.conf
    /etc/sysctl.conf
    /etc/sysctl.d
    /etc/modprobe.d
    /etc/modules-load.d
    /etc/dracut.conf.d
    /etc/default/grub
    /etc/fstab
  )
  for f in "${files[@]}"; do
    if [[ -e "$f" ]]; then
      run cp -a --parents "$f" "$BACKUP_DIR/system/etc-select/" 2>/dev/null || true
    fi
  done
  log_ok "Selected /etc done"
}

backup_kde_user() {
  log_info "=== KDE Plasma + user configs (selective, high value) ==="
  local cfg="${HOME_DIR}/.config"
  local share="${HOME_DIR}/.local/share"

  # Core KDE / Plasma files and dirs
  local kde_files=(
    plasma-org.kde.plasma.desktop-appletsrc
    plasmarc plasmashellrc plasma-localerc
    kdeglobals kwinrc kwinrulesrc kglobalshortcutsrc
    khotkeysrc krunnerrc kscreenlockerrc ksmserverrc
    kcminputrc kxkbrc kcmfonts klaunchrc
    systemsettingsrc dolphinrc konsolerc yakuakerc
    gwenviewrc spectaclerc
    mimeapps.list
    gtkrc gtkrc-2.0
  )
  for f in "${kde_files[@]}"; do
    [[ -e "${cfg}/${f}" ]] && run cp -a "${cfg}/${f}" "$BACKUP_DIR/user/config/" || true
  done

  # Directories under .config
  local kde_dirs=(
    gtk-3.0 gtk-4.0
    autostart
    kdedefaults
    kdeconnect
    plasma-workspace
    session
    xsettingsd
  )
  for d in "${kde_dirs[@]}"; do
    [[ -d "${cfg}/${d}" ]] && run cp -a "${cfg}/${d}" "$BACKUP_DIR/user/config/" || true
  done

  # Broader k* and plasma* under .config (catch-all for Plasma 6)
  if [[ -d "$cfg" ]]; then
    run find "$cfg" -maxdepth 1 \( -name 'k*' -o -name 'plasma*' -o -name 'kde*' \) \
      \( -type f -o -type d \) -exec cp -a {} "$BACKUP_DIR/user/config/" \; 2>/dev/null || true
  fi

  # .local/share selective
  local share_items=(
    plasma
    plasma-systemmonitor
    plasmoids
    icons
    color-schemes
    aurorae
    wallpapers
    konsole
    dolphin
    kscreen
    knewstuff3
    applications
    mime
  )
  for item in "${share_items[@]}"; do
    [[ -e "${share}/${item}" ]] && run cp -a "${share}/${item}" "$BACKUP_DIR/user/local-share/" || true
  done

  if [[ "$INCLUDE_FULL_LOCAL_SHARE" == "yes" ]]; then
    log_warn "Full ~/.local/share requested — this can be large"
    run rsync -a --exclude='Trash' --exclude='*.cache' --exclude='Cache' \
      "${share}/" "$BACKUP_DIR/user/local-share-full/" 2>/dev/null || true
  fi

  # Dotfiles of interest
  for dot in .bashrc .zshrc .profile .gitconfig .vimrc .editorconfig; do
    [[ -f "${HOME_DIR}/${dot}" ]] && run cp -a "${HOME_DIR}/${dot}" "$BACKUP_DIR/user/dotfiles/" || true
  done

  # SSH (public by default)
  if [[ -d "${HOME_DIR}/.ssh" ]]; then
    run mkdir -p "$BACKUP_DIR/user/dotfiles/ssh"
    run cp -a "${HOME_DIR}/.ssh/"*.pub "$BACKUP_DIR/user/dotfiles/ssh/" 2>/dev/null || true
    run cp -a "${HOME_DIR}/.ssh/config" "$BACKUP_DIR/user/dotfiles/ssh/" 2>/dev/null || true
    run cp -a "${HOME_DIR}/.ssh/known_hosts" "$BACKUP_DIR/user/dotfiles/ssh/" 2>/dev/null || true
    if [[ "$INCLUDE_SSH_PRIVATE" == "yes" ]]; then
      log_warn "Including private SSH keys"
      run cp -a "${HOME_DIR}/.ssh/" "$BACKUP_DIR/user/dotfiles/ssh-private/" || true
    fi
  fi

  # GPG
  if [[ -d "${HOME_DIR}/.gnupg" ]]; then
    run mkdir -p "$BACKUP_DIR/user/dotfiles/gnupg"
    # Public + config always
    run cp -a "${HOME_DIR}/.gnupg/pubring"* "$BACKUP_DIR/user/dotfiles/gnupg/" 2>/dev/null || true
    run cp -a "${HOME_DIR}/.gnupg/gpg.conf" "$BACKUP_DIR/user/dotfiles/gnupg/" 2>/dev/null || true
    if [[ "$INCLUDE_GPG_PRIVATE" == "yes" ]]; then
      log_warn "Including private GPG material"
      run cp -a "${HOME_DIR}/.gnupg/" "$BACKUP_DIR/user/dotfiles/gnupg-private/" || true
    fi
  fi

  log_ok "KDE + user configs done"
}

create_archive() {
  log_info "=== Creating compressed archive ==="
  local archive="${BACKUP_ROOT}/${HOSTNAME_SHORT}_${TIMESTAMP}.tar.zst"
  if command -v zstd >/dev/null; then
    run tar -C "$BACKUP_ROOT" -I 'zstd -T0 -19' -cf "$archive" "$(basename "$BACKUP_DIR")"
  else
    archive="${BACKUP_ROOT}/${HOSTNAME_SHORT}_${TIMESTAMP}.tar.gz"
    run tar -C "$BACKUP_ROOT" -czf "$archive" "$(basename "$BACKUP_DIR")"
  fi
  log_ok "Archive: $archive"
  # Optional: keep directory too
  echo "$archive" > "$BACKUP_DIR/ARCHIVE_PATH.txt"
}

verify_setup() {
  log_info "=== --verify-setup ==="
  detect_and_report
  command -v dnf >/dev/null && log_ok "dnf present" || log_warn "dnf missing"
  command -v systemctl >/dev/null && log_ok "systemctl present" || log_error "systemctl missing"
  command -v tar >/dev/null && log_ok "tar present" || die "tar required"
  [[ -d "$HOME_DIR" ]] && log_ok "HOME exists" || die "HOME not found"
  mkdir -p "$BACKUP_ROOT" 2>/dev/null || die "Cannot create BACKUP_ROOT=$BACKUP_ROOT"
  log_ok "Verify passed. Ready to backup."
  exit 0
}

################################################################################
# Main
################################################################################
main() {
  # Ensure log dir exists early
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  touch "$LOG_FILE" 2>/dev/null || true

  detect_and_report

  if [[ "$VERIFY_ONLY" == "yes" ]]; then
    verify_setup
  fi

  if [[ "$DRY_RUN" == "yes" ]]; then
    log_info "DRY-RUN mode — no changes"
  fi

  prepare_dirs
  backup_metadata
  backup_packages
  backup_repos_and_dnf
  backup_systemd
  backup_mime
  backup_firewall_network
  backup_etc_select
  backup_kde_user
  create_archive

  log_ok "Backup complete: $BACKUP_DIR"
  log_info "Archive next to it (or see ARCHIVE_PATH.txt)"
  log_info "Restore strategy: install same Fedora version → dnf install from lists → copy repos → restore units → copy user configs → logout/login"
}

main "$@"