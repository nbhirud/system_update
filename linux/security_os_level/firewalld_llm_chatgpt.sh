#!/usr/bin/env bash
set -euo pipefail

echo "[+] Installing firewalld (if not present)..."
sudo dnf install -y firewalld

echo "[+] Enabling and starting firewalld..."
sudo systemctl enable --now firewalld

echo "[+] Setting default zone to public..."
sudo firewall-cmd --set-default-zone=public

echo "[+] Resetting public zone to a clean state..."
sudo firewall-cmd --permanent --zone=public --remove-service=dhcpv6-client || true
sudo firewall-cmd --permanent --zone=public --remove-service=ssh || true
sudo firewall-cmd --permanent --zone=public --remove-service=cockpit || true

# -----------------------------
# Default policy (IMPORTANT)
# -----------------------------
echo "[+] Setting default target to DROP (deny incoming)..."
sudo firewall-cmd --permanent --zone=public --set-target=DROP

# -----------------------------
# Allow essential outbound (stateful, so replies work automatically)
# -----------------------------
# firewalld allows outbound by default; no change needed

# -----------------------------
# SSH (rate-limited like ufw limit)
# -----------------------------
echo "[+] Adding rate-limited SSH access..."
# sudo firewall-cmd --permanent --add-rich-rule='
# rule family="ipv4"
# service name="ssh"
# limit value="10/m"
# accept
# '
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" service name="ssh" limit value="10/m" accept'

# -----------------------------
# Web (Nextcloud etc.)
# -----------------------------
echo "[+] Allowing HTTP/HTTPS..."
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https

# -----------------------------
# Radicale
# -----------------------------
echo "[+] Allowing Radicale (5232)..."
sudo firewall-cmd --permanent --add-port=5232/tcp

# -----------------------------
# OpenHAB
# -----------------------------
echo "[+] Allowing OpenHAB ports..."
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --permanent --add-port=8443/tcp
sudo firewall-cmd --permanent --add-port=5007/tcp

# -----------------------------
# KDE Connect (local network only ideally)
# -----------------------------
echo "[+] Allowing KDE Connect..."
sudo firewall-cmd --permanent --add-service=kdeconnect

# -----------------------------
# Optional: Restrict KDE Connect to local subnet (better privacy)
# Uncomment and adjust subnet if needed
# -----------------------------
# sudo firewall-cmd --permanent --remove-service=kdeconnect
# sudo firewall-cmd --permanent --add-rich-rule='
# rule family="ipv4"
# source address="192.168.0.0/16"
# service name="kdeconnect"
# accept
# '

# -----------------------------
# Reload firewall
# -----------------------------
echo "[+] Reloading firewall..."
sudo firewall-cmd --reload

# -----------------------------
# Show final config
# -----------------------------
echo "[+] Final firewall configuration:"
sudo firewall-cmd --list-all

echo "[✓] Firewall hardened and configured."