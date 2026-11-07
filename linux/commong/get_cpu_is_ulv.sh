#!/bin/sh
# Prints "true" if the CPU is an ultra-low-voltage / low-power chip, else "false".
#   Intel suffix U or Y (i3-6100U), G1..G7 (i7-1165G7), Core m3/m5/m7 (Core m3-6Y30),
#   Atom and the low-power Celeron/Pentium N/J series.
# Test override: CPUINFO_FILE=/path/to/fake_cpuinfo
here=$(dirname "$0")
model=$(sh "$here/get_cpu_model.sh")
case "$model" in
    *"Core(TM) m"[357]-*|*Atom*) echo true; exit 0 ;;
    *"Celeron(R) CPU N"*|*"Celeron(R) N"*|*"Pentium(R) CPU N"*|*"Pentium(R) Silver"*) echo true; exit 0 ;;
esac
suffix=$(printf '%s\n' "$model" | sed -n 's/.*i[3579]-[0-9]\{4,5\}\([A-Z][A-Z0-9]*\)\{0,1\}.*/\1/p')
case "$suffix" in
    *U|*Y) echo true ;;
    G[0-9]) echo true ;;
    *) echo false ;;
esac
