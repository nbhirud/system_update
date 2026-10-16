#!/bin/sh

set -eux

#########################################################
# RAM (Memory)
#########################################################


# Provides overview of RAM supported by the system
# with useful info like Maximum Capacity (64/32... GiB), Number of Devices (4/2, ...)
# So if max capacity is 64 and number of devices is 4, then There are 4 RAM slots, and each slot supports 64/4 = 16 GiB RAM each.
sudo dmidecode --type=16


# Provides details per RAM slot. So if there are 4 slots, it will show 4 seperate sections 
# with useful info like size (8/16 GiB...), type (ddr3/4...), speed (3200.../2666 MT/s)
sudo dmidecode --type=17


#########################################################
# PCI/M.2 Slots
#########################################################

# 1. "Designations" and "Types" are not at all standardized and different manufacturers use them differently. But it will always show up in type=9
# 2. "Designation" key:
#   a. IF value has something like "M.2x80 Slot" it means you have 1 M.2 slot supporting up to 80mm long cards (M.2 2280 format), 
#       which is the standard physical size for M.2 SSDs.
#   b. IF value has something like "M.2x80 Slot" it means you have 1 short M.2 slot supporting 30mm cards (M.2 2230 format).
#   c. There are more Designations like PCIE16X, PCIE1X, PCI Express 2 x16, PCI Express 2, PCI
#   d. Some manufacturers (or older PCs maybe) just name the Designations as "Slot1", "Slot2", "Slot3", etc.
# 3. "Type" key:
#   a. "M.2 Socket 2" - Typically keyed for SATA or PCIe x2 NVMe drives
#   b. "M.2 Socket 1-SD" - Intended for Wi-Fi, Bluetooth, or SD/cellular modules, usually Key-E or Key-A
# 4. "Current Usage" key: Value "Available" means that it is not in use, and "In Use" means something is plugged into the slot
sudo dmidecode --type=9


#########################################################
# TPM
#########################################################

# Windows 11 requires Specification Version to be 2.0 (older PCs don't return anything or have 1.xx)
sudo dmidecode --type=43



#########################################################
# CPU info
#########################################################

# 
sudo dmidecode --type=4








