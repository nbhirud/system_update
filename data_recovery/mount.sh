#!/bin/sh

set -eux

mount

# to find only the ext4 filesystems
mount | grep ext4