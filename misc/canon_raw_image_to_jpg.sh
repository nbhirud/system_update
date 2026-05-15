#!/bin/sh

set -eux

cd "/home/nbhirud/nb/nbPhotography/DCIM/100CANON"

for img in *.CR2; do
  magick "$img" -quality 95 "${img%.CR2}.jpg"
done