#!/bin/sh
# Classifies the AMD/ATI GPU:  none | legacy | modern | discrete
#   legacy   = old TeraScale / early-GCN parts handled by the 'radeon' kernel driver, or whose
#              name says so (Radeon HD, Trinity...): no Vulkan, weak.   e.g. "Radeon HD 7480D"
#   discrete = RX / Navi / Radeon Pro / Radeon VII
#   modern   = everything else AMD (GCN/Vega/RDNA APUs)
# Test override: PCI_DEVICES_DIR=/path/to/fake/sys/bus/pci/devices
here=$(dirname "$0")
dir="${PCI_DEVICES_DIR:-/sys/bus/pci/devices}"
case " $(sh "$here/get_gpu_vendors.sh") " in *" amd "*) ;; *) echo none; exit 0 ;; esac

# 1) Kernel driver bound to the AMD device (works without pciutils)
for d in "$dir"/*; do
    if [ ! -r "$d/vendor" ] || [ "$(cat "$d/vendor")" != "0x1002" ]; then continue; fi
    case "$(cat "$d/class" 2>/dev/null)" in 0x03*) ;; *) continue ;; esac
    if [ -L "$d/driver" ] && [ "$(basename "$(readlink "$d/driver")")" = "radeon" ]; then echo legacy; exit 0; fi
done

# 2) Marketing name from lspci
names=$(sh "$here/get_gpu_names.sh" | grep -E 'AMD|ATI|Radeon' | head -n 1)
case "$names" in
    *"Radeon HD"*|*"Radeon(TM) HD"*|*Trinity*|*Richland*|*Kabini*|*Llano*|*Wrestler*) echo legacy ;;
    *RX*|*Navi*|*"Radeon Pro"*|*"Radeon VII"*) echo discrete ;;
    *) echo modern ;;
esac
