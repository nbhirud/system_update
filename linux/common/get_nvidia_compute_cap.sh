#!/bin/sh
# Prints the CUDA compute capability MAJOR number of the first NVIDIA GPU
# (5 = Maxwell, 6 = Pascal, 7 = Volta/Turing, 8 = Ampere/Ada, 9 = Hopper, 10+ = Blackwell).
# Prints 0 when there is no NVIDIA GPU, nvidia-smi is missing, or the driver is too old to
# report it. Video decode generations roughly follow it: >=6 adds full HEVC/VP9, >=8 adds AV1.
command -v nvidia-smi >/dev/null 2>&1 || { echo 0; exit 0; }
cc=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n 1 | cut -d. -f1 | tr -d ' ')
case "$cc" in
    ''|*[!0-9]*) echo 0 ;;
    *) echo "$cc" ;;
esac
