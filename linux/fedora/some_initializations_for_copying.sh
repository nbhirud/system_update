

################################
# old
################################

SCRIPT_DOWNLOADS_DIR="$HOME_DIR/nb/nb_script_downloads"

"$HOME_DIR/nb/nb_script_backups"


################################
# new
################################

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"

NBDIR="$HOME_DIR/nb"
SCRIPT_DATA_DIR="${NBDIR}/nb_script_data"

FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"



################################
# backups
################################

SCRIPT_BACKUPS_DIR="${SCRIPT_DATA_DIR}/backups"

XXXXXXXX_BACKUP_DIR_BASE="${SCRIPT_BACKUPS_DIR}/yyyyyyyyyyy"
XXXXXXXX_CURRENT_BACKUP_DIR="${XXXXXXXX_BACKUP_DIR_BASE}/yyyyyyyyyyy_${FILENAME_TIMESTAMP}"


mkdir -p "${XXXXXXXX_CURRENT_BACKUP_DIR}"
chown "${REAL_USER}":"${REAL_USER}" "${XXXXXXXX_BACKUP_DIR_BASE}" "${XXXXXXXX_CURRENT_BACKUP_DIR}"





################################
# downloads
################################

SCRIPT_DOWNLOADS_DIR="${SCRIPT_DATA_DIR}/downloads"

XXXXXXXX_DOWNLOADS_DIR_BASE="${SCRIPT_DOWNLOADS_DIR}/yyyyyyyyyyy"
XXXXXXXX_CURRENT_DOWNLOADS_DIR="${XXXXXXXX_DOWNLOADS_DIR_BASE}/yyyyyyyyyyy_${FILENAME_TIMESTAMP}"


mkdir -p "${XXXXXXXX_CURRENT_DOWNLOADS_DIR}"
chown "${REAL_USER}":"${REAL_USER}" "${XXXXXXXX_DOWNLOADS_DIR_BASE}" "${XXXXXXXX_CURRENT_DOWNLOADS_DIR}"

