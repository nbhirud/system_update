#!/bin/sh
# Prints the video codecs the VA-API device can DECODE in hardware, space separated, from:
#   mpeg2 vc1 h264 hevc vp9 av1          (prints "none" when there is no working VA-API)
# Example: Skylake -> "mpeg2 vc1 h264 hevc"; Tiger Lake -> "mpeg2 vc1 h264 hevc vp9 av1"
# Test override: DRI_DIR=/path/to/fake/dri
here=$(dirname "$0")
node=$(sh "$here/get_vaapi_device.sh")
[ "$node" != none ] || { echo none; exit 0; }
out=$(LC_ALL=C vainfo --display drm --device "$node" 2>&1)
has() { printf '%s\n' "$out" | grep -E "$1.*VAEntrypointVLD" >/dev/null 2>&1; }
codecs=""
has 'VAProfileMPEG2'        && codecs="$codecs mpeg2"
has 'VAProfileVC1'          && codecs="$codecs vc1"
has 'VAProfileH264'         && codecs="$codecs h264"
has 'VAProfileHEVCMain'     && codecs="$codecs hevc"
has 'VAProfileVP9Profile0'  && codecs="$codecs vp9"
has 'VAProfileAV1Profile0'  && codecs="$codecs av1"
codecs=${codecs# }
[ -n "$codecs" ] && echo "$codecs" || echo none
