#!/usr/bin/env bash
#########################################################
# helper_download.sh
#########################################################
# Safe file download + malware scan policy.
#
# REQUIRES (variables from the calling script)
#   SCRIPT_DATA_DOWNLOADS  base directory with ClamAV on-access scanning enabled
#   helper_logging.sh      already sourced
#
# download_file <url> <destination_file>
#   * HTTPS only, TLS >= 1.2, retries, connect/total timeouts
#   * rejects empty files and HTML error pages (404 pages, captive portals)
#   * then calls scan_downloaded_file
#   Returns 0 on success, 1 on any failure (destination is removed on failure).
#
# scan_downloaded_file <file>
#   Policy: files inside SCRIPT_DATA_DOWNLOADS are covered by ClamAV on-access
#   scanning, so no extra scan is done. Files anywhere else are scanned with
#   clamscan. If clamscan is not installed the file is NOT blocked, but a warning
#   is printed. An infected file is deleted and 1 is returned.

scan_downloaded_file() {
    local file="$1"
    case "$file" in
        "${SCRIPT_DATA_DOWNLOADS:-/nonexistent}"/*)
            log_info "Scan skipped (inside on-access scanned directory): ${file}"
            return 0
            ;;
    esac
    if ! command -v clamscan >/dev/null 2>&1; then
        log_warn "clamscan not installed: ${file} was NOT scanned"
        return 0
    fi
    # clamscan exit codes: 0 = clean, 1 = infected, 2 = error
    local rc=0
    clamscan --no-summary --infected "$file" || rc=$?
    if [[ $rc -eq 1 ]]; then
        log_error "ClamAV flagged ${file}; removing it"
        rm -f -- "$file"
        return 1
    elif [[ $rc -ne 0 ]]; then
        log_warn "clamscan failed (exit ${rc}) on ${file}"
    fi
    return 0
}

download_file() {
    local url="$1" dest="$2" tmp
    mkdir -p -- "$(dirname -- "$dest")"
    tmp="$(mktemp "${dest}.part.XXXXXX")"
    if ! curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-delay 2 \
              --connect-timeout 15 --max-time 300 -o "$tmp" "$url"; then
        rm -f -- "$tmp"
        log_warn "download failed: ${url}"
        return 1
    fi
    if [[ ! -s "$tmp" ]]; then
        rm -f -- "$tmp"
        log_warn "empty download: ${url}"
        return 1
    fi
    # An HTML document where a script/binary is expected means an error or login page.
    if head -c 512 "$tmp" | grep -qiE '<!doctype html|<html'; then
        rm -f -- "$tmp"
        log_warn "got an HTML page instead of the file: ${url}"
        return 1
    fi
    mv -f -- "$tmp" "$dest"
    if ! scan_downloaded_file "$dest"; then
        return 1
    fi
    return 0
}
