#!/bin/sh
# Prints the first DRM render node (e.g. /dev/dri/renderD128) on which VA-API reports at
# least one decode entry point (VAEntrypointVLD). Prints "none" when vainfo is missing or
# no node works (no driver installed, no GPU, nouveau-only...).
# Nodes are tried in order; on hybrid laptops renderD128 is normally the integrated GPU,
# which is the one that renders the desktop.
# Test override: DRI_DIR=/path/to/fake/dri (directory containing renderD* files)
dir="${DRI_DIR:-/dev/dri}"
command -v vainfo >/dev/null 2>&1 || { echo none; exit 0; }
for node in "$dir"/renderD*; do
    [ -e "$node" ] || continue
    out=$(LC_ALL=C vainfo --display drm --device "$node" 2>&1) || continue
    case "$out" in
        *VAEntrypointVLD*) echo "$node"; exit 0 ;;
    esac
done
echo none
