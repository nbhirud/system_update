
sudo dnf install gsmartcontrol

# identify the correct drive letter
lsblk



# Long SMART test. This should take about 2 hours, but it may take longer depending on the size of the drive.
sudo smartctl -t long /dev/sdc

# To view the results of smartctl.log.txt:
sudo smartctl -a /dev/sdc