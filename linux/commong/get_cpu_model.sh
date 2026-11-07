#!/bin/sh
# Prints the CPU model string, e.g. "Intel(R) Core(TM) i5-2400 CPU @ 3.10GHz"
# Prints "unknown" if it cannot be determined.
# Test override: CPUINFO_FILE=/path/to/fake_cpuinfo
cpuinfo="${CPUINFO_FILE:-/proc/cpuinfo}"
model=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' "$cpuinfo" 2>/dev/null | head -n 1)
[ -n "$model" ] && echo "$model" || echo "unknown"
