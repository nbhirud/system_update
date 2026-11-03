#!/bin/sh

set -eux

sudo dnf update -y && sudo dnf upgrade -y --refresh && fastfetch

sudo reboot

sudo dnf install -y  amd-ucode-firmware htop curl wget git smartmontools nano fastfetch zsh

lsblk -o NAME,SIZE,MODEL,FSTYPE,MOUNTPOINTS

sudo dnf install e2fsprogs parted

sudo parted /dev/sdb




nbhirud@nbServer:~$ sudo blkid
/dev/sdb1: LABEL="storage1" UUID="bb83085b-020d-437a-8cf1-1f4f0ac6f4ff" BLOCK_SIZE="4096" TYPE="ext4" PARTLABEL="primary" PARTUUID="48ee3597-09f5-4c4e-918f-878f25ff30dd"
/dev/sdc1: LABEL="storage2" UUID="d9dbdf80-46b2-46c8-a2fb-929266329cc2" BLOCK_SIZE="4096" TYPE="ext4" PARTLABEL="primary" PARTUUID="1345b222-c672-4070-8774-7d6ad9806438"


sudo nano /etc/fstab
UUID=bb83085b-020d-437a-8cf1-1f4f0ac6f4ff  /srv/storage1  ext4  defaults,noatime  0 2
UUID=d9dbdf80-46b2-46c8-a2fb-929266329cc2  /srv/storage2  ext4  defaults,noatime  0 2


systemctl daemon-reload

sudo mount -a

df -h


sudo mkdir -p /srv/storage1/docker
sudo mkdir -p /srv/storage1/downloads
sudo mkdir -p /srv/storage2/media



sudo chown -R $USER:$USER /srv/storage1
sudo chown -R $USER:$USER /srv/storage2


sudo tune2fs -l /dev/sdb1 | grep -E "Mount count|Check interval"

sudo tune2fs -c 30 -i 6m /dev/sdb1
sudo tune2fs -c 30 -i 6m /dev/sdc1



sudo dnf install smartmontools

sudo systemctl enable --now smartd