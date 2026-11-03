#!/bin/bash

set -eux

sudo dnf config-manager addrepo --from-repofile=https://download.opensuse.org/repositories/isv:/BrowserWorks/Fedora_44/isv:BrowserWorks.repo

sudo dnf install -y waterfox
