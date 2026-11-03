#!/bin/bash

set -eux

sudo dnf copr enable -y universish/Cromite..

sudo dnf install -y cromite
