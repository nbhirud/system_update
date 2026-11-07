#!/bin/bash

# set -eux
set -euo pipefail

# # RAM_GB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
# RAM_MB=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)
# # RAM_GB=$(( RAM_MB / 1024 ))

# echo $RAM_MB

UNIT="MB"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --unit)
            UNIT="${2:-}"
            shift 2
            ;;
        --unit=*)
            UNIT="${1#*=}"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--unit MB|GB]"
            echo "  --unit   Output unit (MB or GB). Default: MB"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

UNIT=$(echo "$UNIT" | tr '[:lower:]' '[:upper:]')

if [[ "$UNIT" != "MB" && "$UNIT" != "GB" ]]; then
    echo "Error: --unit must be MB or GB" >&2
    exit 1
fi

RAM_MB=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)

if [[ "$UNIT" == "GB" ]]; then
    # Integer GB (floor)
    echo $(( RAM_MB / 1024 ))
else
    echo "$RAM_MB"
fi