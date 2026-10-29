#!/bin/sh
# Prints one human-readable name per display controller (one per line).
# Uses lspci when available, else falls back to the vendor name. Prints nothing if no GPU.
# Test override: PCI_DEVICES_DIR=/path/to/fake/sys/bus/pci/devices
dir="${PCI_DEVICES_DIR:-/sys/bus/pci/devices}"
for d in "$dir"/*; do
    if [ ! -r "$d/class" ] || [ ! -r "$d/vendor" ]; then continue; fi
    case "$(cat "$d/class")" in 0x03*) ;; *) continue ;; esac
    case "$(cat "$d/vendor")" in
        0x8086) fallback="Intel" ;; 0x10de) fallback="NVIDIA" ;; 0x1002) fallback="AMD" ;; *) fallback="Unknown" ;;
    esac
    name=""
    if command -v lspci >/dev/null 2>&1; then
        name=$(lspci -s "$(basename "$d")" 2>/dev/null | cut -d: -f3- | sed 's/^ *//')
    fi
    echo "${name:-$fallback}"
done
