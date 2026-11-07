#!/usr/bin/env bash
#########################################################
# helper_ntfy.sh
#########################################################
# Send a notification through ntfy (https://ntfy.sh or a self-hosted server).
# (The separate ntfy.sh in the repo is for installing/configuring ntfy; this file only SENDS.)
#
# TWO WAYS TO USE IT
#   1. Sourced:    source helper_ntfy.sh; ntfy_send "Title" "Message" [priority] [tags]
#                  Reads NTFY_SERVER, NTFY_TOPIC, NTFY_TOKEN from the environment.
#                  A message of "-" reads the body from stdin.
#   2. Executable: nb-ntfy "Title" "Message" [priority] [tags]
#                  Install with: sudo install -m 0755 helper_ntfy.sh /usr/local/bin/nb-ntfy
#                  Reads /etc/nb/ntfy.env (root-only, mode 600), so systemd units, smartd and
#                  dnf5-automatic can call it.
#
# BEHAVIOR
#   - If NTFY_TOPIC is empty, ntfy_send silently does nothing (returns 0), so callers never need
#     an if-guard.
#   - Returns non-zero when the request fails; callers decide whether that matters.
#   - Privacy: use a long random topic name and/or a self-hosted server with an access token;
#     anyone who knows a public topic name can read and publish to it.
#
# REQUIRES: curl


# Sourcing Guard Rails - uses a safety guard (HELPER_XYZ_LOADED) to prevent issues if it gets sourced multiple times.
if [[ -z "${HELPER_NTFY_LOADED:-}" ]]; then
    HELPER_NTFY_LOADED=1

    ntfy_send() {
        local title="${1:-notification}" msg="${2:-}" prio="${3:-default}" tags="${4:-}"
        local server="${NTFY_SERVER:-https://ntfy.sh}" topic="${NTFY_TOPIC:-}"
        local -a headers=(-H "Title: ${title}" -H "Priority: ${prio}")

        [[ -n "$topic" ]] || return 0
        # "-" means: read the message body from stdin (used by dnf5-automatic's command emitter)
        if [[ "$msg" == "-" ]]; then msg="$(cat)"; fi
        [[ -z "$tags" ]] || headers+=(-H "Tags: ${tags}")
        [[ -z "${NTFY_TOKEN:-}" ]] || headers+=(-H "Authorization: Bearer ${NTFY_TOKEN}")
        curl -fsS --max-time 15 "${headers[@]}" -d "$msg" "${server%/}/${topic}" >/dev/null 2>&1
    }

    # Executed directly (not sourced): behave as a command-line tool.
    if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
        # shellcheck disable=SC1091
        [[ ! -r /etc/nb/ntfy.env ]] || . /etc/nb/ntfy.env
        ntfy_send "$@"
    fi

fi
