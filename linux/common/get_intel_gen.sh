#!/bin/sh
# Prints the Intel generation as a number:
#   1 = before Sandy Bridge: Core 2, Nehalem/Westmere (Core i 1st gen), Pentium/Celeron of that era, Atom, GMA
#   2 = Sandy Bridge   3 = Ivy Bridge   4 = Haswell   5 = Broadwell   6 = Skylake ... 12 = Alder Lake
#  15 = Core Ultra     12 also for Arc graphics
# Prints 0 when unknown (AMD or other CPU, unrecognised model).
#   i5-2400 -> 2   i7-6700HQ -> 6   i3-6100U -> 6   i7-12700 -> 12   i7-1165G7 -> 11
#   i7 CPU 920 -> 1   Core 2 Duo E8400 + "Mobile 4 Series" graphics -> 1
#
# Order of detection
#   1. CPU model string patterns (fast, precise for Core i3/i5/i7/i9, Core m, Core Ultra)
#   2. Fallback for CPUs without such a name (Pentium, Celeron, Atom, Core 2, Xeon, AMD CPU
#      with an Intel GPU): the Intel GPU's name from lspci
# Test overrides: CPUINFO_FILE, PCI_DEVICES_DIR
here=$(dirname "$0")
model=$(sh "$here/get_cpu_model.sh")

case "$model" in *"Core(TM) Ultra"*) echo 15; exit 0 ;; esac

# Core i3/i5/i7/i9-NNNN or -NNNNN (2nd gen and newer)
parsed=$(printf '%s\n' "$model" | sed -n 's/.*i[3579]-\([0-9]\{4,5\}\)\([A-Z][A-Z0-9]*\)\{0,1\}.*/\1 \2/p')
if [ -n "$parsed" ]; then
    num=${parsed%% *}
    suffix=${parsed#* }; [ "$suffix" = "$parsed" ] && suffix=""
    if [ "${#num}" -eq 5 ]; then echo "$num" | cut -c1-2; exit 0; fi
    case "$suffix" in G[0-9]) echo 11; exit 0 ;; esac   # i7-1165G7 is 11th gen
    echo "$num" | cut -c1-1
    exit 0
fi
# Core m3/m5/m7-6Y30 (6th gen and newer low-power parts)
parsed=$(printf '%s\n' "$model" | sed -n 's/.*Core(TM) m[357]-\([0-9]\)[0-9A-Z]*.*/\1/p')
if [ -n "$parsed" ]; then echo "$parsed"; exit 0; fi
# Every Core 2 / Pentium Dual-Core / Pentium D / Pentium 4 predates Sandy Bridge
case "$model" in *"Core(TM)2"*|*"Pentium(R) Dual"*|*"Pentium(R) D "*|*"Pentium(R) 4"*) echo 1; exit 0 ;; esac
# "Core(TM) i7 CPU 920" / "i5 CPU M 520": no dash after i7 = 1st generation (Nehalem/Westmere)
case "$model" in *"Core(TM) i"[3579]" CPU"*) echo 1; exit 0 ;; esac

# Fallback: the Intel GPU's name
name=$(sh "$here/get_gpu_names.sh" | grep -i 'intel' | head -n 1)
case "$name" in
    *Arc*|*Alchemist*|*Battlemage*|*"Iris Xe"*) echo 12 ;;
    *GMA*|*"4 Series Chipset"*|*"Mobile 4 Series"*|*G41*|*G45*|*Q45*|*GM965*|*"Express Chipset"*|*Ironlake*|*Clarkdale*|*Arrandale*|*"Atom Processor"*|*Pineview*) echo 1 ;;
    *"Sandy Bridge"*|*"2nd Generation"*) echo 2 ;;
    *"Ivy Bridge"*|*"3rd Generation"*|*Valleyview*|*"Bay Trail"*) echo 3 ;;
    *Haswell*|*"4th Generation"*) echo 4 ;;
    *) echo 0 ;;
esac
