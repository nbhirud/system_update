#!/bin/sh
# Prints which driver an NVIDIA GPU uses:  proprietary | nouveau | none
# "none" = no NVIDIA GPU present.
# If the proprietary driver is installed but not yet loaded (no reboot since install)
# it still reports "proprietary".
here=$(dirname "$0")
case " $(sh "$here/get_gpu_vendors.sh") " in *" nvidia "*) ;; *) echo none; exit 0 ;; esac
if [ -e /proc/driver/nvidia/version ]; then echo proprietary
elif lsmod 2>/dev/null | grep -q '^nouveau'; then echo nouveau
elif rpm -q --quiet akmod-nvidia 2>/dev/null || rpm -q --quiet xorg-x11-drv-nvidia 2>/dev/null; then echo proprietary
else echo nouveau
fi
