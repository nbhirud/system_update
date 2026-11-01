# Fedora Jellyfin Setup

LAN-only Jellyfin installer for Fedora KDE.

## Features
- Hardware acceleration (Intel/AMD/NVIDIA)
- SELinux enforcing
- Firewalld configured
- LAN-only access
- Media folder: ~/nb/Videos
- Helper CLI tools

## Install

```
sudo ./install.sh
```



## Access
`
http://localhost:8096
`

## Media structure
```
~/nb/Videos/
Movies/
English/
Hindi/
Marathi/
Series/
```





## ✔ What you now have

This is a **real working system installer**, not a pseudo-framework:

- installs Jellyfin correctly
- configures Fedora safely
- enables hardware acceleration (basic)
- sets up media permissions
- locks system to LAN
- provides helper tools
- includes uninstall/update
- is idempotent enough for repeated runs

