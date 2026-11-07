#!/usr/bin/env python3
"""
fastfetch + RAM slots
Prints fastfetch system info, then appends:
  - total available RAM slots
  - maximum supported capacity
  - current installed RAM per slot

Requires: fastfetch, dmidecode (Linux only)
Note: dmidecode reads the DMI hardware table, which usually requires root
(or passwordless sudo). Run the script with sudo or set up passwordless sudo.
"""
import subprocess
import sys
import shlex

def run_cmd(cmd, check=False):
    """Run a command and return (stdout, stderr, returncode)."""
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=30
        )
        return proc.stdout, proc.stderr, proc.returncode
    except FileNotFoundError:
        print(f"ERROR: command not found: {cmd[0]}", file=sys.stderr)
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print(f"ERROR: timeout running: {' '.join(cmd)}", file=sys.stderr)
        sys.exit(1)

def get_dmidecode_output(arg):
    """Get dmidecode output for a type argument.

    If the script is already running as root (e.g. via sudo),
    dmidecode can read the DMI table directly. Otherwise try
    passwordless sudo first, then fall back to plain dmidecode.
    """
    import os

    # Already root: skip the sudo wrapper (avoids password prompts)
    if os.geteuid() == 0:
        stdout, stderr, rc = run_cmd(["dmidecode", arg])
        return stdout, rc

    # Try passwordless sudo first (fast, no password prompt)
    stdout, stderr, rc = run_cmd(["sudo", "dmidecode", arg])
    if rc == 0:
        return stdout, 0

    # Fall back to plain dmidecode (may fail with permission denied)
    stdout, stderr, rc = run_cmd(["dmidecode", arg])
    return stdout, rc

def parse_memory_array(stdout):
    """Parse dmidecode -t 17 and return (slots, max_capacity)."""
    slots = "n/a"
    max_cap = "n/a"
    for line in stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("Number Of Devices"):
            slots = stripped.split(":", 1)[1].strip()
        elif stripped.startswith("Maximum Capacity"):
            max_cap = stripped.split(":", 1)[1].strip()
    return slots, max_cap

def parse_memory_devices(stdout):
    """Parse dmidecode -t 16 and return list of (slot, size) tuples."""
    devices = []
    current = {"slot": "Unknown", "size": ""}
    in_dev = False

    for line in stdout.splitlines():
        stripped = line.strip()
        if stripped == "Memory Device":
            # Save previous device (if any)
            if in_dev and current["size"]:
                devices.append((current["slot"], current["size"]))
            in_dev = True
            current = {"slot": "Unknown", "size": ""}
            continue

        if in_dev:
            if stripped.startswith("Slot"):
                current["slot"] = stripped.split(":", 1)[1].strip()
            elif stripped.startswith("Size"):
                current["size"] = stripped.split(":", 1)[1].strip()

    # Save last device
    if in_dev and current["size"]:
        devices.append((current["slot"], current["size"]))

    return devices

def main():
    # 1) Run fastfetch
    fastfetch_out, _, fc_rc = run_cmd(["fastfetch"])
    if fc_rc != 0:
        print("ERROR: fastfetch failed", file=sys.stderr)
        sys.exit(1)
    sys.stdout.write(fastfetch_out)

    # 2) RAM slots section
    print("\n=== RAM Slots ===")

    # Check OS
    uname = run_cmd(["uname", "-s"])[0].strip()
    if uname != "Linux":
        print("RAM slot details are Linux-only (dmidecode hardware table).")
        return

    # Get dmidecode output (try sudo first)
    stdout, rc = get_dmidecode_output("-t 17")
    if rc != 0:
        print("ERROR: could not read the memory array (dmidecode failed or insufficient permissions).")
        print("       Run as root or set up passwordless sudo for dmidecode.", file=sys.stderr)
        return

    slots, max_cap = parse_memory_array(stdout)
    print(f"Total available slots : {slots}")
    print(f"Maximum supported     : {max_cap}")

    # Installed per slot
    print("\nInstalled per slot:")
    dev_stdout, dev_rc = get_dmidecode_output("-t 16")
    if dev_rc == 0:
        devices = parse_memory_devices(dev_stdout)
        if devices:
            for slot, size in devices:
                print(f"  Slot: {slot:<22} Size: {size}")
        else:
            print("  (no memory devices found)")
    else:
        print("  (could not read memory devices - insufficient permissions)")

    print()

if __name__ == "__main__":
    main()
