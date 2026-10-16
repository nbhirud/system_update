#!/bin/sh

set -eux

df -h

#  to show only the filesystem and the used percentage
df -h | awk '{print $1, $5}'

# Monitoring Filesystem Usage over time in a loop
while true; do
    df -h
    sleep 60
done