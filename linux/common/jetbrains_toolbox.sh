#!/usr/bin/env bash

##################################################################################
# Overview and Usage
##################################################################################
# jetbrains_toolbox.sh - install (or update) and configure the JetBrains Toolbox
# App on Fedora, as a NORMAL USER.
#
# Why this matters: the old version unpacked Toolbox into /opt (root-owned). Toolbox
# updates itself by writing into the directory it runs from, so it could not
# update unless started with sudo. This script keeps the Toolbox program in
# ~/.local/share/JetBrains/Toolbox/bin (the location Toolbox itself uses), owned by
# you, so the autostarted Toolbox can self-update with no sudo, ever.
#
# What it does
#   1. Installs runtime dependencies with dnf.
#   2. Downloads the latest Toolbox tarball via JetBrains' release API, verifies
#      the SHA-256 checksum and scans it with ClamAV.
#   3. Backs up the useful Toolbox files, then replaces ONLY the Toolbox program.
#      Installed IDEs (apps/), your login and your settings are kept.
#   4. Removes the legacy root-owned install (/opt/jetbrains-toolbox) and fixes
#      root-owned files left behind by earlier "sudo jetbrains-toolbox" runs.
#   5. Pre-seeds Toolbox settings (automatic updates), starts Toolbox once so it
#      creates its own launcher files, then writes a clean autostart entry.
#   6. Integrates: ~/.local/bin symlink, jetbrains:// MIME handler, BleachBit
#      cleaner, optional OpenSnitch rules (only if OpenSnitch is installed).
#   7. Verifies the result (--verify-setup runs only this step).
#
# Sample calls (assuming the caller uses the same variable names)
#   (a) all options:
#       bash "$COMMON_DIR/jetbrains_toolbox.sh" --real-user "$REAL_USER" \
#            --filename-timestamp "$FILENAME_TIMESTAMP" --release-type release \
#            --auto-update true --autostart-delay 10 \
#            --ntfy-topic "$NTFY_TOPIC"
#   (b) mandatory only (nothing is mandatory; every option has a default):
#       bash "$COMMON_DIR/jetbrains_toolbox.sh"
#   (c) verification only:
#       bash "$COMMON_DIR/jetbrains_toolbox.sh" --verify-setup
#
# Run it from a terminal INSIDE your desktop session (Toolbox needs a display for
# its first start). After it finishes: accept the Toolbox agreement, decline usage
# statistics, install PyCharm from the Toolbox window, then run pycharm.sh.
##################################################################################

set -Eeuo pipefail
# NOTE: no `set -x` on purpose. The old script used `set -eux`; tracing floods the
# terminal and the log. Use `bash -x script ...` only when debugging.

ORIGINAL_ARGS=("$@")

##################################################################################
# User defined variables
##################################################################################
# Everything an operator may want to change lives here (or in the options below).
RELEASE_TYPE="${RELEASE_TYPE:-release}"                 # release | eap
TOOLBOX_AUTO_UPDATE="${TOOLBOX_AUTO_UPDATE:-true}"      # let Toolbox update itself and tools
AUTOSTART_DELAY_SECONDS="${AUTOSTART_DELAY_SECONDS:-10}" # delay after login (tray must exist first)
VERIFY_ONLY=false
NTFY_TOPIC="${NTFY_TOPIC:-}"                            # optional push notification at the end (sent with ntfy_send from helper_ntfy.sh)

TOOLBOX_PRODUCT_CODE="TBA"                              # JetBrains product code of the Toolbox App
TOOLBOX_RELEASE_API="https://data.services.jetbrains.com/products/releases"
LEGACY_OPT_DIR="/opt/jetbrains-toolbox"                 # old root-owned install location
LEGACY_BIN_LINK="/usr/local/bin/jetbrains-toolbox"

# Fedora packages. The JetBrains docs list Debian names; Fedora equivalents:
#   libxi6->libXi  libxrender1->libXrender  libxtst6->libXtst  mesa-utils->mesa-demos
#   libfontconfig->fontconfig  libgtk-3-bin->gtk-update-icon-cache
#   libxcb-keysyms1->xcb-util-keysyms  dbus-user-session->dbus-daemon
# Extras: libsecret (credential storage), jq/curl (release API), util-linux (script),
# procps-ng (pgrep), desktop-file-utils + xdg-utils (launcher/MIME handling).
TOOLBOX_DNF_DEPENDENCIES=(
  libXi libXrender libXtst mesa-demos fontconfig gtk-update-icon-cache
  tar xcb-util-keysyms dbus-daemon libsecret
  jq curl util-linux procps-ng desktop-file-utils xdg-utils
)

##################################################################################
# Named Options processing
##################################################################################
# Placed BEFORE the inferred variables because --real-user and
# --filename-timestamp feed the standard variables derived next.
print_usage() {
  cat <<'USAGE'
Usage: jetbrains_toolbox.sh [options]
  --real-user NAME            user to configure (default: sudo caller or current user)
  --filename-timestamp TS     shared timestamp for backup/download/log dirs
  --release-type TYPE         release (default) | eap
  --auto-update true|false    Toolbox automatic updates (default: true)
  --autostart-delay SECONDS   delay of the autostart entry (default: 10)
  --ntfy-topic TOPIC          send a push notification via ntfy when done (default: off)
  --verify-setup              only run the verification section
  -h, --help                  show this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --real-user)             REAL_USER="${2:?--real-user needs a value}"; shift 2 ;;
    --real-user=*)           REAL_USER="${1#*=}"; shift ;;
    --filename-timestamp)    FILENAME_TIMESTAMP="${2:?--filename-timestamp needs a value}"; shift 2 ;;
    --filename-timestamp=*)  FILENAME_TIMESTAMP="${1#*=}"; shift ;;
    --release-type)          RELEASE_TYPE="${2:?--release-type needs a value}"; shift 2 ;;
    --release-type=*)        RELEASE_TYPE="${1#*=}"; shift ;;
    --auto-update)           TOOLBOX_AUTO_UPDATE="${2:?--auto-update needs a value}"; shift 2 ;;
    --auto-update=*)         TOOLBOX_AUTO_UPDATE="${1#*=}"; shift ;;
    --autostart-delay)       AUTOSTART_DELAY_SECONDS="${2:?--autostart-delay needs a value}"; shift 2 ;;
    --autostart-delay=*)     AUTOSTART_DELAY_SECONDS="${1#*=}"; shift ;;
    --ntfy-topic)            NTFY_TOPIC="${2:?--ntfy-topic needs a value}"; shift 2 ;;
    --ntfy-topic=*)          NTFY_TOPIC="${1#*=}"; shift ;;
    --verify-setup)          VERIFY_ONLY=true; shift ;;
    -h|--help)               print_usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; print_usage >&2; exit 2 ;;
  esac
done

case "$RELEASE_TYPE" in release|eap) ;; *) echo "--release-type must be release or eap" >&2; exit 2 ;; esac
case "$TOOLBOX_AUTO_UPDATE" in true|false) ;; *) echo "--auto-update must be true or false" >&2; exit 2 ;; esac
case "$AUTOSTART_DELAY_SECONDS" in ''|*[!0-9]*) echo "--autostart-delay must be a number" >&2; exit 2 ;; esac

##################################################################################
# Inferred variables
##################################################################################
# --- standard variables (identical in every script of the project) ---
REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update"
COMMON_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/common"
GETTER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commong"
HELPER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commonh"
SECURITY_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/security"
FEDORA_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/fedora"
SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"
SCRIPT_DATA_LOGS="${SCRIPT_DATA}/logs"

# --- per-package directories (package = jetbrains_toolbox) ---
JETBRAINS_TOOLBOX_DOWNLOAD_DIR_BASE="${SCRIPT_DATA_DOWNLOADS}/jetbrains_toolbox"
JETBRAINS_TOOLBOX_CURRENT_DOWNLOAD_DIR="${JETBRAINS_TOOLBOX_DOWNLOAD_DIR_BASE}/jetbrains_toolbox_${FILENAME_TIMESTAMP}"
JETBRAINS_TOOLBOX_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/jetbrains_toolbox"
JETBRAINS_TOOLBOX_CURRENT_BACKUP_DIR="${JETBRAINS_TOOLBOX_BACKUP_DIR_BASE}/jetbrains_toolbox_${FILENAME_TIMESTAMP}"
JETBRAINS_TOOLBOX_LOG_DIR_BASE="${SCRIPT_DATA_LOGS}/jetbrains_toolbox"
JETBRAINS_TOOLBOX_CURRENT_LOG_DIR="${JETBRAINS_TOOLBOX_LOG_DIR_BASE}/jetbrains_toolbox_${FILENAME_TIMESTAMP}"

# --- Toolbox paths (all under the user's home: nothing here needs root) ---
TOOLBOX_DIR="${HOME_DIR}/.local/share/JetBrains/Toolbox"
TOOLBOX_BIN_DIR="${TOOLBOX_DIR}/bin"
TOOLBOX_BIN="${TOOLBOX_BIN_DIR}/jetbrains-toolbox"
TOOLBOX_SETTINGS_FILE="${TOOLBOX_DIR}/.settings.json"
AUTOSTART_FILE="${HOME_DIR}/.config/autostart/jetbrains-toolbox.desktop"
APP_DESKTOP_FILE="${HOME_DIR}/.local/share/applications/jetbrains-toolbox.desktop"
JETBRAINSD_DESKTOP="${HOME_DIR}/.local/share/applications/jetbrainsd.desktop"
USER_BIN_DIR="${HOME_DIR}/.local/bin"
USER_BIN_LINK="${USER_BIN_DIR}/jetbrains-toolbox"
# Directories that may contain root-owned leftovers from "sudo jetbrains-toolbox".
JETBRAINS_USER_DIRS=("${HOME_DIR}/.local/share/JetBrains" "${HOME_DIR}/.config/JetBrains" "${HOME_DIR}/.cache/JetBrains")

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
LOG_FILE="${JETBRAINS_TOOLBOX_CURRENT_LOG_DIR}/jetbrains_toolbox.log"
ARCH="$(uname -m)"
TOOLBOX_PROC_PATTERN='jetbrains-toolbox/bin/jetbrains-toolbox|JetBrains/Toolbox/bin/jetbrains-toolbox'

# Hardware/desktop getters (reused, tested code; see GETTER_DIR). "unknown" if missing.
run_getter() { if [ -r "${GETTER_DIR}/$1.sh" ]; then sh "${GETTER_DIR}/$1.sh" 2>/dev/null || echo unknown; else echo unknown; fi; }
DESKTOP="$(run_getter get_desktop_env)"
PC_TYPE="$(run_getter get_pc_type)"

##################################################################################
# Helpers
##################################################################################
for helper in helper_logging helper_run_as_user helper_dnf helper_download helper_backup \
              helper_version_compare helper_mimeapps helper_script_logging \
              helper_opensnitch helper_bleachbit helper_ntfy; do
  if [ ! -r "${HELPER_DIR}/${helper}.sh" ]; then
    echo "ERROR: missing helper ${HELPER_DIR}/${helper}.sh" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  . "${HELPER_DIR}/${helper}.sh"
done

# Becomes REAL_USER if started through sudo; refuses to continue as root.
ensure_real_user "${ORIGINAL_ARGS[@]}"
export REAL_USER FILENAME_TIMESTAMP
start_script_logging "$LOG_FILE" "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"

# Sleep-free polling helper: wait until a path exists (or time runs out).
wait_for_path() {
  local path="$1" timeout="$2" waited=0
  while [ ! -e "$path" ] && [ "$waited" -lt "$timeout" ]; do
    sleep 1
    waited=$((waited + 1))
  done
  [ -e "$path" ]
}

has_display() { [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; }

##################################################################################
# Backup
##################################################################################
# Only the USEFUL bits are saved (settings, launchers, MIME defaults, listings).
# The installation itself (several GB of IDEs) is deliberately not copied.
backup_existing() {
  log_header "Backup of existing Toolbox files"
  umask 077
  mkdir -p "$JETBRAINS_TOOLBOX_CURRENT_BACKUP_DIR"

  local f
  for f in "$TOOLBOX_SETTINGS_FILE" "${TOOLBOX_DIR}/.storage.json" "${TOOLBOX_DIR}/environment.json" \
           "$AUTOSTART_FILE" "$APP_DESKTOP_FILE" "$JETBRAINSD_DESKTOP" "$USER_BIN_LINK" \
           "${HOME_DIR}/.config/mimeapps.list"; do
    if [ -e "$f" ] || [ -L "$f" ]; then
      backup_path_parents "$f" "$JETBRAINS_TOOLBOX_CURRENT_BACKUP_DIR"
    fi
  done

  # State records (text files) that explain what the machine looked like before.
  if [ -d "${TOOLBOX_DIR}/apps" ]; then
    backup_record "$JETBRAINS_TOOLBOX_CURRENT_BACKUP_DIR" installed_tools ls -la "${TOOLBOX_DIR}/apps"
  fi
  if [ -d "$LEGACY_OPT_DIR" ]; then
    backup_record "$JETBRAINS_TOOLBOX_CURRENT_BACKUP_DIR" legacy_opt_listing ls -laR "$LEGACY_OPT_DIR"
  fi
  backup_record "$JETBRAINS_TOOLBOX_CURRENT_BACKUP_DIR" toolbox_processes pgrep -af 'jetbrains-toolbox' || true
  umask 022
  log_success "Backup written to ${JETBRAINS_TOOLBOX_CURRENT_BACKUP_DIR}"
}

##################################################################################
# Reset
##################################################################################
# Fresh start for everything that belongs to the Toolbox PROGRAM. Toolbox DATA
# (installed IDEs, account, settings) is kept, because "install or update" must
# not uninstall your IDEs. Full wipe: see Troubleshooting at the bottom.
stop_toolbox() {
  if pgrep -u "$REAL_USER" -f "$TOOLBOX_PROC_PATTERN" >/dev/null 2>&1; then
    log_info "Stopping running Toolbox (user)"
    pkill -u "$REAL_USER" -f "$TOOLBOX_PROC_PATTERN" || true
    local i
    for i in $(seq 1 20); do
      pgrep -u "$REAL_USER" -f "$TOOLBOX_PROC_PATTERN" >/dev/null 2>&1 || break
      sleep 1
    done
    pkill -KILL -u "$REAL_USER" -f "$TOOLBOX_PROC_PATTERN" 2>/dev/null || true
  fi
  # A copy started with "sudo" (the old update workaround) runs as root.
  if pgrep -u root -f "$TOOLBOX_PROC_PATTERN" >/dev/null 2>&1; then
    log_info "Stopping Toolbox running as root"
    sudo pkill -u root -f "$TOOLBOX_PROC_PATTERN" || true
  fi
}

reset_toolbox_program() {
  log_header "Reset (Toolbox program, launchers, legacy install)"
  stop_toolbox

  # 1. Legacy root-owned install and its global symlink.
  if [ -d "$LEGACY_OPT_DIR" ]; then
    log_info "Removing legacy install ${LEGACY_OPT_DIR}"
    sudo rm -rf "$LEGACY_OPT_DIR"
  fi
  if [ -L "$LEGACY_BIN_LINK" ] && [[ "$(readlink "$LEGACY_BIN_LINK")" == *jetbrains-toolbox* ]]; then
    sudo rm -f "$LEGACY_BIN_LINK"
  fi

  # 2. Root-owned files inside the user's JetBrains directories break self-update.
  local offenders
  offenders="$(find "${JETBRAINS_USER_DIRS[@]}" -xdev ! -user "$REAL_USER" -print -quit 2>/dev/null || true)"
  if [ -n "$offenders" ]; then
    log_warn "Found files not owned by ${REAL_USER} (e.g. ${offenders}); fixing ownership"
    local d
    for d in "${JETBRAINS_USER_DIRS[@]}"; do
      [ -d "$d" ] && sudo chown -R "${REAL_USER}:$(id -gn "$REAL_USER")" "$d"
    done
  fi

  # 3. Launcher files (Toolbox rewrites them on start). The program directory bin/
  #    is NOT deleted here: install_toolbox_program swaps it atomically, so a
  #    failed install can never leave you without a working Toolbox.
  rm -f "$AUTOSTART_FILE" "$APP_DESKTOP_FILE" "$USER_BIN_LINK"
  log_success "Reset done"
}

##################################################################################
# Security
##################################################################################
# Egress rules for OpenSnitch. Skipped silently when OpenSnitch is not installed.
# firewalld is not involved: Toolbox only makes outbound connections.
setup_opensnitch_rules() {
  if ! opensnitch_is_present; then
    log_info "OpenSnitch not installed: skipping egress rules"
    return 0
  fi
  log_header "OpenSnitch rules"
  # Toolbox binary -> JetBrains domains only. Unknown destinations still trigger
  # the OpenSnitch prompt, which is the point of an egress filter.
  opensnitch_write_rule "jetbrains-toolbox-allow" allow false \
    "Toolbox App: JetBrains update, download and account servers" \
    '^.*/\.local/share/JetBrains/Toolbox/bin/.*' '(^|\.)jetbrains\.com$'
  # JetBrains AI endpoints (listed in the AI Assistant documentation). Denied for
  # every process; precedence=true so no allow rule can override it.
  opensnitch_write_rule "jetbrains-ai-deny" deny true \
    "JetBrains AI Assistant / Grazie endpoints (AI is disabled on purpose)" \
    "" '^(api\.jetbrains\.ai|api\.ai\.jetbrains\.com\.cn|api\.app\.prod\.grazie\.aws\.intellij\.net)$'
  log_success "OpenSnitch rules written (daemon reloads them automatically)"
}

##################################################################################
# main setup
##################################################################################
preflight() {
  log_header "Preflight"
  require_fedora
  case "$ARCH" in x86_64|aarch64) ;; *) log_die "Unsupported CPU architecture: ${ARCH}" ;; esac
  if [ "$PC_TYPE" = "server" ]; then
    log_die "Headless server detected: Toolbox is a desktop (GUI) application"
  fi
  case "$DESKTOP" in
    *kde*|*plasma*|*gnome*) log_info "Desktop: ${DESKTOP} (officially supported)" ;;
    *) log_warn "Desktop '${DESKTOP}' is not officially supported by Toolbox (GNOME and KDE Plasma are)" ;;
  esac
  if [ "$(id -u)" -eq 0 ]; then log_die "Run as a normal user (the script uses sudo only where needed)"; fi
  # The tarball and its extracted copy need roughly 0.5 GB; IDEs installed later
  # by Toolbox need several GB more.
  local free_kb
  free_kb="$(df --output=avail -k "$HOME_DIR" 2>/dev/null | tail -1 | tr -dc '0-9')"
  if [ -n "$free_kb" ] && [ "$free_kb" -lt $((2 * 1024 * 1024)) ]; then
    log_die "Less than 2 GB free under ${HOME_DIR}: free some space and retry"
  fi
  sudo -v
}

install_dependencies() {
  log_header "Dependencies"
  local missing=() pkg
  for pkg in "${TOOLBOX_DNF_DEPENDENCIES[@]}"; do
    rpm_is_installed "$pkg" || missing+=("$pkg")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    log_info "Installing: ${missing[*]}"
    # --skip-unavailable: a renamed package must not abort the whole install
    # (dnf5 on Fedora 42+). Anything still missing is reported below.
    sudo dnf install -y --skip-unavailable "${missing[@]}"
  fi
  for pkg in "${TOOLBOX_DNF_DEPENDENCIES[@]}"; do
    rpm_is_installed "$pkg" || log_warn "Package not installed: ${pkg} (renamed or unavailable?)"
  done
}

download_and_verify_toolbox() {
  log_header "Download and verify Toolbox"
  mkdir -p "$JETBRAINS_TOOLBOX_CURRENT_DOWNLOAD_DIR"
  local json="${JETBRAINS_TOOLBOX_CURRENT_DOWNLOAD_DIR}/release.json"
  local key="linux"
  [ "$ARCH" = "aarch64" ] && key="linuxARM64"

  download_file "${TOOLBOX_RELEASE_API}?code=${TOOLBOX_PRODUCT_CODE}&latest=true&type=${RELEASE_TYPE}" "$json"

  local jqsel=(--arg code "$TOOLBOX_PRODUCT_CODE" --arg key "$key")
  TB_URL="$(jq -r "${jqsel[@]}" '.[$code][0].downloads[$key].link // empty' "$json")"
  TB_SHA_URL="$(jq -r "${jqsel[@]}" '.[$code][0].downloads[$key].checksumLink // empty' "$json")"
  TB_VERSION="$(jq -r --arg code "$TOOLBOX_PRODUCT_CODE" '.[$code][0].version // "unknown"' "$json")"
  [ -n "$TB_URL" ] && [ -n "$TB_SHA_URL" ] || log_die "Release API returned no download/checksum link (see ${json})"

  TB_TARBALL="${JETBRAINS_TOOLBOX_CURRENT_DOWNLOAD_DIR}/$(basename "$TB_URL")"
  log_info "Toolbox ${TB_VERSION}: ${TB_URL}"
  download_file "$TB_URL" "$TB_TARBALL"
  download_file "$TB_SHA_URL" "${TB_TARBALL}.sha256"

  # The checksum file reads "<sha256>  <filename>"; compare only the hash so a
  # different local file name cannot cause a false mismatch.
  local expected actual
  expected="$(awk '{print $1; exit}' "${TB_TARBALL}.sha256")"
  actual="$(sha256sum "$TB_TARBALL" | awk '{print $1}')"
  [ -n "$expected" ] && [ "$expected" = "$actual" ] || log_die "SHA-256 mismatch for ${TB_TARBALL}"
  log_success "SHA-256 verified"

  # Helper scan (skips on-access-scanned dirs) plus an explicit scan in case the
  # on-access scanner is down.
  scan_downloaded_file "$TB_TARBALL"
  if command -v clamscan >/dev/null 2>&1; then
    local rc=0
    clamscan --no-summary "$TB_TARBALL" || rc=$?
    if [ "$rc" -eq 1 ]; then log_die "ClamAV flagged ${TB_TARBALL}"; fi
    if [ "$rc" -gt 1 ]; then log_warn "clamscan failed (exit ${rc}); checksum already verified"; fi
  else
    log_warn "clamscan not installed: skipped explicit scan"
  fi
}

install_toolbox_program() {
  log_header "Install Toolbox program"
  local extract_dir="${JETBRAINS_TOOLBOX_CURRENT_DOWNLOAD_DIR}/extracted" bin_found src_root
  mkdir -p "$extract_dir"
  tar -xzf "$TB_TARBALL" -C "$extract_dir"

  # The archive has one top-level directory containing bin/jetbrains-toolbox.
  # Locate it instead of assuming the directory name or --strip-components.
  bin_found="$(find "$extract_dir" -maxdepth 3 -type f -name jetbrains-toolbox -path '*/bin/*' -print -quit)"
  [ -n "$bin_found" ] || log_die "bin/jetbrains-toolbox not found inside the tarball"
  src_root="$(dirname "$(dirname "$bin_found")")"

  mkdir -p "$TOOLBOX_DIR"
  # Atomic swap (idea from another script): stage the new program next to the old
  # one, validate it, then rename. A failure before the rename leaves the old
  # installation untouched.
  local staged="${TOOLBOX_DIR}/bin.new.$$"
  rm -rf "$staged"
  cp -a "${src_root}/bin" "$staged"
  [ -f "${staged}/jetbrains-toolbox" ] || { rm -rf "$staged"; log_die "Staged copy has no jetbrains-toolbox binary"; }
  chmod 0755 "${staged}/jetbrains-toolbox"
  rm -rf "${TOOLBOX_BIN_DIR}.old"
  [ -d "$TOOLBOX_BIN_DIR" ] && mv "$TOOLBOX_BIN_DIR" "${TOOLBOX_BIN_DIR}.old"
  mv "$staged" "$TOOLBOX_BIN_DIR"
  rm -rf "${TOOLBOX_BIN_DIR}.old"
  # Anything else shipped next to bin/ (if the layout ever grows) is copied too.
  find "$src_root" -mindepth 1 -maxdepth 1 ! -name bin -exec cp -a {} "${TOOLBOX_DIR}/" \;
  log_success "Installed to ${TOOLBOX_BIN_DIR}"

  mkdir -p "$USER_BIN_DIR"
  ln -sfn "$TOOLBOX_BIN" "$USER_BIN_LINK"
}

# Toolbox reads .settings.json at start-up, so it is written BEFORE the first
# launch. Key "update.install_automatically" is the documented switch for
# automatic updates (YouTrack TBX-10887); other keys are preserved.
seed_toolbox_settings() {
  log_header "Toolbox settings"
  mkdir -p "$TOOLBOX_DIR"
  local tmp
  tmp="$(mktemp)"
  if [ -s "$TOOLBOX_SETTINGS_FILE" ] && jq -e . "$TOOLBOX_SETTINGS_FILE" >/dev/null 2>&1; then
    jq --argjson v "$TOOLBOX_AUTO_UPDATE" '.update.install_automatically = $v' "$TOOLBOX_SETTINGS_FILE" >"$tmp"
  else
    [ -s "$TOOLBOX_SETTINGS_FILE" ] && log_warn "Existing settings were not valid JSON (backed up); recreating"
    jq -n --argjson v "$TOOLBOX_AUTO_UPDATE" '{update:{install_automatically:$v}}' >"$tmp"
  fi
  install -m 0600 "$tmp" "$TOOLBOX_SETTINGS_FILE"
  rm -f "$tmp"
  log_success "update.install_automatically = ${TOOLBOX_AUTO_UPDATE}"
}

first_launch() {
  log_header "First launch"
  if has_display; then
    log_info "Starting Toolbox in your session (accept the agreement in its window)"
    # setsid -f: detach completely so closing this terminal does not kill it.
    setsid -f "$TOOLBOX_BIN" >/dev/null 2>&1 </dev/null
  else
    # Without a display Toolbox still writes its launcher files, logs a
    # "headless environment" message and exits (verified on Fedora 45).
    log_warn "No graphical session detected: running Toolbox headless to create its files"
    timeout 60 "$TOOLBOX_BIN" >/dev/null 2>&1 </dev/null || true
  fi
  wait_for_path "$APP_DESKTOP_FILE" 60 || log_warn "Toolbox did not create ${APP_DESKTOP_FILE} within 60 s"
  wait_for_path "$JETBRAINSD_DESKTOP" 10 || true
}

# Own, deterministic autostart entry. Same fields Toolbox writes itself, plus the
# delay keys. Rewritten on every run (idempotent).
write_autostart_entry() {
  log_header "Autostart"
  mkdir -p "$(dirname "$AUTOSTART_FILE")"
  local icon="${TOOLBOX_DIR}/toolbox.svg"
  [ -e "$icon" ] || icon="jetbrains-toolbox"
  cat >"$AUTOSTART_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=JetBrains Toolbox
Comment=Manage and update JetBrains IDEs
Exec=${TOOLBOX_BIN} --minimize
Icon=${icon}
Terminal=false
StartupNotify=false
Categories=Development;IDE;
StartupWMClass=jetbrains-toolbox
MimeType=x-scheme-handler/jetbrains;
X-GNOME-Autostart-enabled=true
# Wait N seconds after login so the system tray exists (honored by GNOME and by
# the systemd XDG autostart generator used by Plasma).
X-GNOME-Autostart-Delay=${AUTOSTART_DELAY_SECONDS}
# KDE: start after the panel/tray is up.
X-KDE-autostart-after=panel
EOF
  chmod 0644 "$AUTOSTART_FILE"
  desktop-file-validate "$AUTOSTART_FILE" || log_warn "desktop-file-validate reported warnings (usually harmless)"
  log_success "Wrote ${AUTOSTART_FILE}"
}

setup_mime_handler() {
  log_header "MIME: jetbrains:// links"
  # jetbrainsd.desktop is created by Toolbox; it opens jetbrains:// links
  # (browser extension "Open in IDE", git clone buttons, ...).
  if [ -e "$JETBRAINSD_DESKTOP" ]; then
    mimeapps_check_default jetbrainsd.desktop x-scheme-handler/jetbrains \
      || mimeapps_set_default jetbrainsd.desktop x-scheme-handler/jetbrains
  else
    log_warn "jetbrainsd.desktop not found; jetbrains:// links will work after Toolbox has started once"
  fi
  update-desktop-database "${HOME_DIR}/.local/share/applications" 2>/dev/null || true
}

# BleachBit cleaner: only logs and regenerable caches, never settings or plugins.
# CleanerML syntax: https://docs.bleachbit.org/doc/cleanerml.html
setup_bleachbit_cleaner() {
  log_header "BleachBit cleaner"
  local dir
  if ! dir="$(bleachbit_cleaner_dir)"; then
    log_info "BleachBit not installed (dnf or flatpak): skipping"
    return 0
  fi
  mkdir -p "$dir"
  cat >"${dir}/jetbrains.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<cleaner id="jetbrains" os="linux">
  <label>JetBrains IDEs and Toolbox</label>
  <description>Logs and caches written by the Toolbox App and JetBrains IDEs</description>
  <option id="logs">
    <label>Logs</label>
    <description>Toolbox App logs and IDE logs (idea.log)</description>
    <action command="delete" search="walk.files" path="~/.local/share/JetBrains/Toolbox/logs"/>
    <action command="delete" search="glob" path="~/.cache/JetBrains/*/log/idea.log*"/>
  </option>
  <option id="toolbox_cache">
    <label>Toolbox cache</label>
    <description>Downloaded update data kept by the Toolbox App</description>
    <action command="delete" search="walk.all" path="~/.cache/JetBrains/Toolbox"/>
  </option>
  <option id="ide_caches">
    <label>IDE caches and indexes</label>
    <description>Safe to delete, but every project is re-indexed on next start. Close all IDEs first.</description>
    <warning>All IDEs must be closed. Projects will be re-indexed.</warning>
    <action command="delete" search="walk.all" path="~/.cache/JetBrains/PyCharm*"/>
  </option>
</cleaner>
EOF
  chmod 0644 "${dir}/jetbrains.xml"
  log_success "Cleaner installed: ${dir}/jetbrains.xml"
}

main_setup() {
  preflight
  install_dependencies
  backup_existing
  download_and_verify_toolbox
  reset_toolbox_program
  install_toolbox_program
  seed_toolbox_settings
  first_launch
  write_autostart_entry
  setup_mime_handler
  setup_bleachbit_cleaner
  setup_opensnitch_rules
}

##################################################################################
# Verification
##################################################################################
VERIFY_PASS=0; VERIFY_WARN=0; VERIFY_FAIL=0
check_pass() { VERIFY_PASS=$((VERIFY_PASS + 1)); log_success "$*"; }
check_warn() { VERIFY_WARN=$((VERIFY_WARN + 1)); log_warn "$*"; }
check_fail() { VERIFY_FAIL=$((VERIFY_FAIL + 1)); log_error "$*"; }

verify_setup() {
  log_header "Verification"
  local pkg f

  # Program: present, executable, user-owned.
  if [ -x "$TOOLBOX_BIN" ]; then check_pass "Toolbox binary: ${TOOLBOX_BIN}"; else check_fail "Toolbox binary missing: ${TOOLBOX_BIN}"; fi
  [ ! -d "$LEGACY_OPT_DIR" ] && check_pass "No legacy install in ${LEGACY_OPT_DIR}" || check_fail "Legacy root-owned install still exists: ${LEGACY_OPT_DIR}"

  # Self-update prerequisite: everything the user's Toolbox touches is writable.
  if [ -w "$TOOLBOX_BIN_DIR" ] && [ -z "$(find "${JETBRAINS_USER_DIRS[@]}" -xdev ! -user "$REAL_USER" -print -quit 2>/dev/null || true)" ]; then
    check_pass "Toolbox directories are user-owned and writable (self-update works without sudo)"
  else
    check_fail "Root-owned or read-only files under JetBrains directories: self-update would fail"
  fi

  # Settings
  if [ -f "$TOOLBOX_SETTINGS_FILE" ] && [ "$(jq -r '.update.install_automatically // "unset"' "$TOOLBOX_SETTINGS_FILE" 2>/dev/null)" = "$TOOLBOX_AUTO_UPDATE" ]; then
    check_pass "Automatic updates setting = ${TOOLBOX_AUTO_UPDATE}"
  else
    check_warn "update.install_automatically is not '${TOOLBOX_AUTO_UPDATE}' in ${TOOLBOX_SETTINGS_FILE} (Toolbox may have rewritten it; check Settings > Tools in the GUI)"
  fi

  # Launchers
  if [ -f "$AUTOSTART_FILE" ] && grep -q "^Exec=${TOOLBOX_BIN} --minimize" "$AUTOSTART_FILE"; then check_pass "Autostart entry points at the user install"; else check_fail "Autostart entry missing or wrong: ${AUTOSTART_FILE}"; fi
  [ -f "$APP_DESKTOP_FILE" ] && check_pass "App launcher exists" || check_warn "App launcher ${APP_DESKTOP_FILE} missing (start Toolbox once)"
  [ -L "$USER_BIN_LINK" ] && check_pass "Terminal command: ${USER_BIN_LINK}" || check_warn "Symlink ${USER_BIN_LINK} missing"
  if mimeapps_check_default jetbrainsd.desktop x-scheme-handler/jetbrains >/dev/null 2>&1; then check_pass "jetbrains:// handled by jetbrainsd.desktop"; else check_warn "jetbrains:// handler not set"; fi

  # Dependencies and credential storage
  for pkg in "${TOOLBOX_DNF_DEPENDENCIES[@]}"; do
    rpm_is_installed "$pkg" || check_warn "Package missing: ${pkg}"
  done
  if busctl --user list --no-pager 2>/dev/null | grep -q org.freedesktop.secrets; then
    check_pass "Secret Service provider available (KWallet/GNOME Keyring): login can be stored"
  else
    check_warn "No Secret Service provider: Toolbox cannot store a JetBrains account login (not needed for the free tier)"
  fi

  # Optional integrations
  if f="$(bleachbit_cleaner_dir)"; then
    [ -f "${f}/jetbrains.xml" ] && check_pass "BleachBit cleaner present" || check_warn "BleachBit installed but cleaner missing"
  fi
  if opensnitch_is_present; then
    [ -f "$(opensnitch_rules_dir)/jetbrains-toolbox-allow.json" ] && check_pass "OpenSnitch rules present" || check_warn "OpenSnitch installed but rules missing"
  fi

  # Informational
  pgrep -u "$REAL_USER" -f "$TOOLBOX_PROC_PATTERN" >/dev/null 2>&1 && log_info "Toolbox is running" || log_info "Toolbox is not running (starts at next login)"
  log_info "Result: ${VERIFY_PASS} passed, ${VERIFY_WARN} warnings, ${VERIFY_FAIL} failed"
  [ "$VERIFY_FAIL" -eq 0 ]
}

print_next_steps() {
  log_header "Next steps (GUI, one time)"
  log_info "1. In the Toolbox window: accept the agreement and UNTICK usage statistics."
  log_info "2. Toolbox menu > Settings > Tools: confirm 'Update all tools automatically' is ON."
  log_info "   Also set 'Shell scripts location' to ${USER_BIN_DIR} so 'pycharm' works in zsh."
  log_info "   (Toolbox only edits ~/.bash_profile and ~/.profile, which zsh does not read.)"
  log_info "3. Install 'PyCharm' from the tools list (JetBrains no longer ships a separate Community build)."
  log_info "4. Do NOT open PyCharm yet. Run: bash \"${COMMON_DIR}/pycharm.sh\""
}

main() {
  if [ "$VERIFY_ONLY" = true ]; then
    verify_setup
    return
  fi
  main_setup
  if verify_setup; then
    ntfy_send "JetBrains Toolbox ready" "jetbrains_toolbox.sh finished on $(hostname): ${VERIFY_PASS} ok, ${VERIFY_WARN} warnings" default white_check_mark || true
  else
    log_warn "Verification reported failures; see above"
    ntfy_send "JetBrains Toolbox: failures" "jetbrains_toolbox.sh on $(hostname): ${VERIFY_FAIL} failed checks" high warning || true
  fi
  print_next_steps
}

main

exit 0

##################################################################################
# Notes
##################################################################################
# Design decisions
#  - User-level install. Toolbox updates itself by writing next to its own
#    binary. In /opt that fails for a normal user, hence the old "sudo ... then
#    click update" workaround. Running a GUI as root also leaves root-owned files
#    in $HOME (cleaned up by reset_toolbox_program).
#  - Data vs program. Only bin/ and launcher files are replaced. apps/ (IDEs),
#    scripts/, account storage and settings survive, so the script is safe as an
#    "install or update" tool. This deliberately differs from the usual
#    "wipe everything" rule: wiping would uninstall every IDE and log you out.
#  - Tarball, not AppImage. Since Toolbox 2.6.3 the Linux download is a tarball
#    with a native binary; FUSE (libfuse2) is no longer needed.
#  - Official support list: Ubuntu 22.04/24.04, Fedora 42/43, Amazon Linux 2023,
#    GNOME and KDE Plasma. Fedora 45 works (tested by third parties), but is not on
#    the official list yet.
#  - Auto update: the documented key is update.install_automatically in
#    ~/.local/share/JetBrains/Toolbox/.settings.json. It is seeded before first
#    launch. Whether the separate GUI switch "Update all tools automatically"
#    shares this key is not documented: verify it once in the GUI.
#  - Autostart delay: .desktop "Exec" lines are NOT run through a shell, so the
#    old trick "Exec=sleep 60;/path/toolbox" can never work (there is no shell to
#    interpret ';'). Use the X-GNOME-Autostart-Delay key, or wrap explicitly:
#    Exec=sh -c 'sleep 60; exec /path/jetbrains-toolbox --minimize'
#  - No CLI to install IDEs: only an experimental Java-based "tb-cli.jar" meant
#    for remote hosts exists. IDE installs therefore stay a GUI step.
#  - Rejected after review of other implementations:
#      * systemd --user unit instead of XDG autostart: Toolbox's own "Run at login"
#        switch and the unit would fight each other, and IDEs started from Toolbox
#        become children of the service's cgroup. XDG autostart is what Toolbox
#        itself writes, so the GUI switch keeps working. If Toolbox ever rewrites
#        the entry (the verification step would show it), re-run this script.
#      * A ".installed-version" marker file: Toolbox updates itself in place, so the
#        marker goes stale and the script would wrongly "update" or report outdated.
#      * Editing ~/.zshrc / ~/.bashrc to extend PATH: the zsh setup script owns
#        those files; a symlink into ~/.local/bin is enough.
#      * libfuse2 and glx-utils: FUSE is not needed since Toolbox 2.6.3, and
#        glx-utils was renamed mesa-demos on current Fedora.
#      * Writing keys such as "privacy.send_usage_statistics" or "shell_scripts" into
#        .settings.json: no such keys are documented, and overwriting the whole
#        file would also erase real settings. Only the documented key is merged.
#  - Replaced old code (previous script): it unpacked into /opt with sudo, parsed
#    the checksum inline, ran Toolbox in the foreground (blocking the script) and
#    slept 15 s. The new flow verifies the checksum, runs Toolbox detached, and
#    waits for the launcher files instead of sleeping blindly.
#
# Carried over from the previous script's notes
#  - Debian/Ubuntu: "sudo apt install libfuse2" was needed for the AppImage era.
#  - Alternatives that were considered: flatpak com.jetbrains.PyCharm-Community
#    (sandbox cannot see host tools), COPR phracek/PyCharm, JetBrains tarball.
#  - Uninstall: https://toolbox-support.jetbrains.com/hc/en-us/articles/115001313270
#    and https://www.jetbrains.com/help/pycharm/uninstall.html
#  - Toolbox settings once used by hand: enable auto update; PyCharm instance
#    settings: auto update and a larger memory limit (pycharm.sh now does the
#    memory part from detected RAM).
#  - Dracula theme for JetBrains IDEs: https://draculatheme.com/jetbrains
#  - Old advice "avoid PyCharm on old/slow machines, use VSCodium there" is
#    superseded: pycharm.sh tunes heap, toolkit and plugins from the hardware.
#  - Startup Applications: open "Startup Applications" (GNOME) or System
#    Settings > Autostart (KDE) to review autostart entries.
#
##################################################################################
# Useful Links
##################################################################################
# Toolbox installation (tarball, deps, supported distros): https://www.jetbrains.com/help/toolbox-app/installation.html
# Toolbox CLI (experimental):   https://www.jetbrains.com/help/toolbox-app/toolbox-app-cli.html
# environment.json options:     https://www.jetbrains.com/help/toolbox-app/add-remote-ide-to-tba.html
# Auto-update key (.settings.json): https://youtrack.jetbrains.com/projects/TBX/issues/TBX-10887
# Updating IDEs via Toolbox:    https://www.jetbrains.com/help/idea/update.html
# Fedora 45 walk-through:       https://computingforgeeks.com/install-intellij-idea-fedora/
# Release API used here:        https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release
# XDG autostart spec:           https://specifications.freedesktop.org/autostart-spec/latest/
# systemd XDG autostart generator: man systemd-xdg-autostart-generator
# BleachBit CleanerML:          https://docs.bleachbit.org/doc/cleanerml.html
# OpenSnitch rules:             https://github.com/evilsocket/opensnitch/wiki/Rules
#
##################################################################################
# Troubleshooting/Debugging/Testing/Commands
##################################################################################
# Toolbox log:              tail -f ~/.local/share/JetBrains/Toolbox/logs/toolbox.latest.log
# This script's log:        ls -t ~/nb/nb_script_data/logs/jetbrains_toolbox/*/ ; less -R <file>
# Is it running / from where: pgrep -af jetbrains-toolbox
# Self-update test:         find ~/.local/share/JetBrains ~/.config/JetBrains ~/.cache/JetBrains ! -user "$USER"
#                           (must print nothing)
# No tray icon on Plasma:   increase --autostart-delay, or start Toolbox manually once.
# Login fails / keychain error: busctl --user list | grep secrets ; start KWallet (kwalletmanager6)
# Last resort without keychain: add "preferredKeychain": "linux-fallback" to
#                           ~/.local/share/JetBrains/Toolbox/.storage.json (stores credentials in a
#                           file encrypted with a static key: weaker, use only if unavoidable)
# Pin / disable Toolbox self-update: set update.install_automatically=false in .settings.json
# Autostart not honored:    systemctl --user list-units 'app-*jetbrains*'
#                           Alternative Exec: sh -c 'sleep 30; exec ~/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox --minimize'
# Full wipe (removes ALL IDEs, plugins, settings of every JetBrains product):
#   pkill -f jetbrains-toolbox; pkill jetbrainsd
#   rm -rf ~/.local/share/JetBrains ~/.cache/JetBrains ~/.config/JetBrains
#   rm -f ~/.config/autostart/jetbrains-toolbox.desktop ~/.local/share/applications/jetbrains*.desktop
# Restore a backup:         cp -a ~/nb/nb_script_data/backups/jetbrains_toolbox/<stamp>/home/<user>/. ~/
# BleachBit check:          bleachbit --list-cleaners | grep jetbrains ; bleachbit --preview jetbrains.logs
# SELinux denials:          sudo ausearch -m avc -ts recent
# OpenSnitch rules:         ls /etc/opensnitchd/rules/ | grep jetbrains






# ##################################################################################
# # Original code
# ##################################################################################

# #!/bin/bash

# set -eux

# # https://www.jetbrains.com/help/pycharm/installation-guide.html#toolbox
# # https://docs.fedoraproject.org/en-US/quick-docs/installing-from-source/

# # TODO - Make this an "Install, or update if already installed" script
# # Need to run this to open toolbox and then click update and then restart the app: 
# # '''sudo /opt/jetbrains-toolbox/bin/jetbrains-toolbox'''

# # RELEASE_TYPE=release

# HOME_DIR=$(getent passwd $USER | cut -d: -f6)

# JT_DOWNLOAD_DIR="$HOME_DIR/nb/Downloads/Jetbrains/jt_$(date +%Y-%m-%d_%H-%M-%S)"
# JT_INSTALL_DEST="/opt/jetbrains-toolbox"

# mkdir -p $JT_DOWNLOAD_DIR
# sudo mkdir -p $JT_INSTALL_DEST

# cd $JT_DOWNLOAD_DIR

# # TARBALL_URL=$(curl -s 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=${RELEASE_TYPE}' | jq -r '.TBA[0].downloads.linux.link')
# TARBALL_URL=$(curl -s 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' | jq -r '.TBA[0].downloads.linux.link')

# TARBALL_FILENAME=$(basename $TARBALL_URL)

# # TARBALL_SHA_URL=$(curl -s 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=$RELEASE_TYPE' | jq -r '.TBA[0].downloads.linux.checksumLink')
# TARBALL_SHA_URL=$(curl -s 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' | jq -r '.TBA[0].downloads.linux.checksumLink')

# JT_SHA_LONG=$(curl $TARBALL_SHA_URL )

# # JT_SHA=$(echo $JT_SHA_LONG | awk '{ print $1}')

# # echo "TARBALL_URL = $TARBALL_URL"
# # echo "TARBALL_FILENAME = $TARBALL_FILENAME"
# # echo "TARBALL_SHA_URL = $TARBALL_SHA_URL"
# # echo "JT_SHA_LONG = $JT_SHA_LONG"
# # echo "JT_SHA = $JT_SHA"

# # Download the tarball:
# wget -O "$JT_DOWNLOAD_DIR/$TARBALL_FILENAME" "$TARBALL_URL"

# # Check SHA-256 checksum:
# echo $JT_SHA_LONG | sha256sum -c

# # De-Compress (unzip) the tarball in destination dir
# sudo tar -xzvf "$TARBALL_FILENAME" --directory="$JT_INSTALL_DEST/" --strip-components=1

# # Make jetbrains-toolbox aqn executable
# sudo chmod +x "$JT_INSTALL_DEST/bin/jetbrains-toolbox"

# # Run jetbrains-toolbox for the first time to initialize it
# $JT_INSTALL_DEST/bin/jetbrains-toolbox

# # The above will initialize various Toolbox application files in the application directory:
# # ~/.local/share/JetBrains/Toolbox


# mkdir -p /home/nbhirud/.local/share/JetBrains/Toolbox/apps
# mkdir -p /home/nbhirud/.local/share/JetBrains/Toolbox/scripts
# # Upon the first launch, the Toolbox App will also create a .desktop entry file in ~/.local/share/applications.

# # The above will add it to app drawer as well as to auto-start


# sleep 15s

# ###########################################################################################
# # Old notes
# ###########################################################################################

# # # flatpak install -y flathub com.jetbrains.PyCharm-Community
# # # flatpak run com.jetbrains.PyCharm-Community
# # # https://copr.fedorainfracloud.org/coprs/phracek/PyCharm/


# # ###########################################

# # # Install jetbrains toolbox

# # # Follow instructions here: https://www.jetbrains.com/help/pycharm/installation-guide.html
# # # May need to run the following if opening toolbox app gives error:
# # # sudo apt install -y libfuse2
# # # TLDR:
# # sudo apt install libfuse2

# # cd /opt/
# # sudo tar -xvzf ~/Downloads/jetbrains-toolbox-1.xx.xxxx.tar.gz
# # sudo mv jetbrains-toolbox-1.xx.xxxx jetbrains
# # jetbrains/jetbrains-toolbox # Open JetBrains Toolbox (and installs?)

# # # # Install Pycharm (Avoid on old/slow machines, and use VSCodium there instead): 
# # # # If toolbox not needed, go for "Standalone installation" of pycharm. Remember to download Pycharm community edition
# # # sudo tar xzf pycharm-*.tar.gz -C /opt/
# # # cd /opt/pycharm-professional-2024.1/bin
# # # sh pycharm.sh

# # # If the above standalone installation doesn't seem to work, install pycharm flatpak (try to avoid snap Pycharm, it's slower)

# # ### Pycharm Un-install:
# # # https://toolbox-support.jetbrains.com/hc/en-us/articles/115001313270-How-to-uninstall-Toolbox-App
# # # https://www.jetbrains.com/help/pycharm/uninstall.html


# # ##### Jetbrains Toolbox
# # # login to the toolbox app
# # # Toolbox -> Settings -> Enable auto update
# # # Toolbox -> Install Pycharm Community
# # # Toolbox -> Pycharm Community Settings -> Auto update, larger memory 


# # ###########################################

# # # Open app "Startup Applications" -> Check if alright

# # # To delay opening of start-up applicarions,

# # # Find the .desktop file that corresponds with your application
# # # in /home/nbhirud/.config/autostart/ directoryand open it in a text editor:

# # # For example, for jetbrains toolbox:
# # # /home/nbhirud/.config/autostart/jetbrains-toolbox.desktop
# # # gedit ~/.config/autostart/jetbrains-toolbox.desktop
# # # Append/Edit the following line to the file:
# # #X-GNOME-Autostart-Delay=90
# # #where 90 is the time in seconds you want to delay the application launch by

# # #### Another method that doesn't seem to work:
# # # For apps that you want to delay startup, append "sleep" <space> <seconds> <semicolon> before the existing command there
# # # Example: Change the following in command box for jetbrains toolbox startup entry:
# # # /home/nbhirud/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox --minimize
# # # To the following
# # # sleep 60;/home/nbhirud/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox --minimize
# # # This did not work - find out why

# # #############################################

# # # https://draculatheme.com/jetbrains


# # ##### pycharm
# # # Set "JetbrainsMono Nerd Font" as default editor font
# # # set latest python as interpreter

