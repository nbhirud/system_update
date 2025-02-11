
### ddrescue
sudo dnf install ddrescue
ddrescue [options] infile outfile [logfile]


# https://www.gnu.org/software/ddrescue/manual/ddrescue_manual.html#Invoking-ddrescue
# -d = option will force ddrescue to ignore the kernel’s cache and instead access the disk directly.
# -rN =  try N times to rescue the block
# -f   Force ddrescue to run even if the destination file already exists (this is required when writing to a disk). It will overwrite.
# -n   Short for’–no-scrape’. This option prevents ddrescue from running through the scraping phase, essentially preventing the utility from spending too much time attempting to recreate heavily damaged areas of a file.


# Other common options:

    # -r3   Tells ddrescue to keep retrying damaged areas until 3 passes have been completed. If you set ‘r=-1’, the utility will make infinite attempts. However, this can be destructive, and ddrescue will rarely restore anything new after three complete passes.
    # -D   Short for ‘–synchronous’. This issues an fsync call after every write.
    # -d   Short for ‘–delete-if-done’. Deletes the given logfile “if all the blocks in the rescue domain have been successfully recovered.”
    # -e [+]n   Short for ‘–max-errors=[+]n’. This sets the maximum number of error areas allowed before ddrescue gives up, and it can be used to prevent the utility from running infinitely.
    # -v   Short for ‘–verbose’. This sets “verbose” mode, providing additional details. Can be useful for diagnosing issues.
    # -S   Short for ‘–sparse.’ This compels ddrescue to use sparse writes — blocks of zeroes aren’t allocated on the disk, which can save space. However, it can only be used for regular files, and it is not an available option on all operating systems.

    # -n   Short for’–no-scrape’. Prevents ddrescue from running through the scraping phase, essentially preventing the utility from spending too much time attempting to recreate heavily damaged areas of a file.
    # -r3   Tells ddrescue to keep retrying damaged areas until 3 passes have been completed. If you set ‘r=-1’, the utility will make infinite attempts. However, this can be destructive, and ddrescue will rarely restore anything new after three complete passes.  
    # -D   Short for ‘–synchronous’. This issues an fsync call after every write.
    # -d   Short for ‘–delete-if-done’. Deletes the given logfile “if all the blocks in the rescue domain have been successfully recovered.”
    # -e [+]n   Short for ‘–max-errors=[+]n’. This sets the maximum number of error areas allowed before ddrescue gives up, and it can be used to prevent the utility from running infinitely.
    # -v   Short for ‘–verbose’. This sets “verbose” mode, providing additional details. Can be useful for diagnosing issues.
    # -S   Short for ‘–sparse.’ This compels ddrescue to use sparse writes — blocks of zeroes aren’t allocated on the disk, which can save space. However, it can only be used for regular files, and it is not an available option on all operating systems.


### from a disk to file
sudo ddrescue -d -r3 /dev/sdc /home/nbhirud/nb/recovered_from_USB_ddrescue/flashdrive.img /home/nbhirud/nb/recovered_from_USB_ddrescue/flashdrive.log

ddrescue -f -n /dev/[baddrive] /root/[imagefilename].img /root/recovery.log




### from a file to a disk

# using dd
sudo dd if=backup.img of=/dev/sdX

# using ddrescue
sudo ddrescue -f backup.img /dev/sdX clone.logfile




### from a disk to another disk
sudo ddrescue -d -f /dev/sdX1 /dev/sdX2 clone.logfile

ddrescue -r3 -n /dev/[baddrive] /dev/[gooddrive] recovery.log

ddrescue -f -n /dev/[baddrive] /dev/[gooddrive] /root/recovery.log

sudo ddrescue -r3 -n -d -f  /dev/sdd /dev/sdc /home/nbhirud/nb/DataRecoveryCustomerXYZ/ddrescue_recovery.log


##################################################3

sudo ddrescue -d -f -n -r3 -v /dev/sdc /dev/sdd1 /home/nbhirud/nb/DataRecoveryCustomerXYZ/clone.logfile
