
# https://superuser.com/questions/1848296/fix-a-hdd-that-got-bricked-due-to-reboot-during-formatting


The noise indicates the disk is resetting itself over and over, trying to recalibrate. If it is visible to the computer but reports its total capacity as zero, it's how some disk models say "I'm failing my own internal self tests."




################################################

### identify the device path to the hard drive or partition that you would line to clone

##############

https://www.baeldung.com/linux/find-all-storage-devices


##############
# lsblk will list all block storage devices and partitions.

lsblk

lsblk -o KNAME,TYPE,SIZE,MODEL

lsblk -d -n -oNAME,RO | grep '0$' | awk {'print $1'}

##############

# lshw -short will give you information about all of the hardware (except perhaps firewire) on the system.

lshw -class disk -class tape

lshw -class tape -class disk -class storage -short

##############

ls -l /dev /dev/mapper |grep '^b'

##############

# fdisk -l will list all of the partitions on all devices that are listed in /proc/partitions


##############

# https://github.com/openSUSE/hwinfo
# http://www.linuxintro.org/wiki/Hwinfo
# https://askubuntu.com/q/662971/44876
hwinfo --block --short
hwinfo --disk

##############

