#!/bin/sh
# Prints the vendors of all display controllers (PCI class 0x03xxxx), space separated,
# in a stable order, from: intel nvidia amd other.   Prints "none" if no GPU is found.
# Example (hybrid laptop): "intel nvidia"
# Uses sysfs only, so it works without pciutils.
# Test override: PCI_DEVICES_DIR=/path/to/fake/sys/bus/pci/devices
dir="${PCI_DEVICES_DIR:-/sys/bus/pci/devices}"
intel=0; nvidia=0; amd=0; other=0
for d in "$dir"/*; do
    if [ ! -r "$d/class" ] || [ ! -r "$d/vendor" ]; then continue; fi
    class=$(cat "$d/class")
    case "$class" in 0x03*) ;; *) continue ;; esac
    case "$(cat "$d/vendor")" in
        0x8086) intel=1 ;;
        0x10de) nvidia=1 ;;
        0x1002) amd=1 ;;
        *) other=1 ;;
    esac
done
out=""
[ "$intel"  = 1 ] && out="$out intel"
[ "$nvidia" = 1 ] && out="$out nvidia"
[ "$amd"    = 1 ] && out="$out amd"
[ "$other"  = 1 ] && out="$out other"
out=${out# }
[ -n "$out" ] && echo "$out" || echo "none"
