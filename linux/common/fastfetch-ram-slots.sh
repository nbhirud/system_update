#!/usr/bin/env bash
# =============================================================================
# fastfetch + RAM slots
# Prints fastfetch system info, then appends:
#   - total available RAM slots
#   - maximum supported capacity
#   - current installed RAM per slot
#
# Dependencies : fastfetch, dmidecode
# Note         : RAM slot details come from the DMI hardware table
#               (dmidecode), which typically requires root or a
#               passwordless sudo setup.
# =============================================================================
set -euo pipefail

# --- Dependency checks -------------------------------------------------------
for cmd in fastfetch dmidecode; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: '$cmd' not found in PATH." >&2
        exit 1
    fi
done

# Run fastfetch
fastfetch

# --- RAM slots ---------------------------------------------------------------
echo
echo "=== RAM Slots ==="

case "$(uname -s)" in
    Linux*) ;;
    *)
        echo "RAM slot details are Linux-only (dmidecode hardware table)."
        exit 0
        ;;
esac

# dmidecode helper: use passwordless sudo when available, else plain
get_dmidecode() {
    if sudo -n true 2>/dev/null; then
        sudo dmidecode "$@"
    else
        dmidecode "$@"
    fi
}

# --- Summary: total slots + max capacity (Memory Array, type 17) -------------
array_out="$(get_dmidecode -t 17 2>/dev/null)" || true
if [[ -z "$array_out" ]]; then
    echo "ERROR: could not read the memory array (dmidecode failed or insufficient permissions)."
    echo "       Run as root or set up passwordless sudo for dmidecode."
    exit 0
fi

slots="$(printf '%s\n' "$array_out" | awk -F': ' '{ sub(/^[ \t]+/, ""); if ($1 == "Number Of Devices") print $2 }')"
max_cap="$(printf '%s\n' "$array_out" | awk -F': ' '{ sub(/^[ \t]+/, ""); if ($1 == "Maximum Capacity") print $2 }')"

echo "Total available slots : ${slots:-n/a}"
echo "Maximum supported     : ${max_cap:-n/a}"

# --- Installed RAM per slot (Memory Device, type 16) -------------------------
echo
echo "Installed per slot:"
get_dmidecode -t 16 2>/dev/null | awk -F': ' '
    BEGIN { in_dev = 0; printed = 0 }
    /^Memory Device/ {
        if (in_dev && printed) printf "  Slot: %-22s Size: %s\n", slot, size
        in_dev = 1; slot = "Unknown"; size = ""; printed = 0; next
    }
    in_dev && /^$/ { in_dev = 0; printed = 0; next }
    in_dev {
        if (/Slot:/) slot = $2
        if (/Size:/) size = $2
        printed = 1
    }
    END { if (in_dev && printed) printf "  Slot: %-22s Size: %s\n", slot, size }
' || true

echo
