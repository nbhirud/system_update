#!/bin/bash

set -eux

# https://wiki.archlinux.org/title/Fail2ban
# https://christitus.com/linux-security-mistakes/
# https://linuxcapable.com/how-to-install-fail2ban-with-firewalld-on-fedora-linux/
# https://www.the-art-of-web.com/system/fail2ban-howto/
# https://www.the-art-of-web.com/system/fail2ban-filters/

# fail2ban: Watches logs (e.g., SSH) and bans IPs after repeated failed login attempts.
# Monitors logs and bans suspicious IPs automatically (especially SSH). Protects from brute-force attacks.
# It may be necessary to set LogLevel VERBOSE in /etc/ssh/sshd_config to allow full fail2ban monitoring as otherwise password failures may not be logged correctly.
# #############
# Fail2Ban reads:

#     Defaults from: /etc/fail2ban/jail.conf

#     Your changes from: /etc/fail2ban/jail.local or files in /etc/fail2ban/jail.d/*.conf

#     Never edit jail.conf directly.

# #############


# /etc/fail2ban/jail.local
#
# Install first:
# sudo apt install -y fail2ban
sudo dnf install -y fail2ban fail2ban-firewalld
sudo cp jail.local /etc/fail2ban/jail.local
sudo systemctl enable --now fail2ban
#
# This bans repeat-offender IPs at the firewalld level (via firewallcmd-rich-
# rules), on top of the 10/min rich-rule limit already set by
# setup-firewalld.sh. The rich-rule limit throttles bursts; fail2ban actually
# blocks an IP after repeated failures.

[DEFAULT]
banaction = firewallcmd-rich-rules
banaction_allports = firewallcmd-rich-rules[actiontype=<allports>]
backend = systemd

[sshd]
enabled = true
maxretry = 5
findtime = 10m
bantime = 1h
bantime.increment = true
bantime.factor = 4
bantime.maxtime = 1w
# bantime.multipliers = 1 2 4 8 16 32 64


# To prevent trusted networks from being banned, extend ignoreip in [DEFAULT]. Use documentation addresses as placeholders only; replace them with your real management network before saving:
# It may be necessary to set LogLevel VERBOSE in /etc/ssh/sshd_config to allow full fail2ban monitoring as otherwise password failures may not be logged correctly.
# If using iptables front-ends like ufw, one can use banaction = ufw instead of using iptables.
# sudo nano /etc/fail2ban/jail.d/sshd.local
# # paste the following:
# ```
# [sshd]
# enabled = true
# port    = $SSH_PORT    # <-- Replace with your SSH port
# logpath = %(sshd_log)s
# filter    = sshd
# #banaction = iptables
# banaction = ufw
# backend = systemd
# maxretry = 5
# bantime = 1h
# findtime = 10m
# ignoreip  = 127.0.0.1/8

# ```




# Service hardening
# Currently, Fail2ban must be run as root. Therefore, you may wish to consider hardening the process with systemd.
# The CapabilityBoundingSet parameters CAP_DAC_READ_SEARCH will allow Fail2ban full read access to every directory and file. CAP_NET_ADMIN and CAP_NET_RAW allow Fail2ban to operate on any firewall that has command-line shell interface. See capabilities(7) for more info.
# By using ProtectSystem=strict the filesystem hierarchy will only be read-only, ReadWritePaths allows Fail2ban to have write access on required paths. 
# Create a drop-in file for fail2ban.service: 
# /etc/systemd/system/fail2ban.service.d/override.conf
# [Service]
# PrivateDevices=yes
# PrivateTmp=yes
# ProtectHome=read-only
# ProtectSystem=strict
# ReadWritePaths=-/var/run/fail2ban
# ReadWritePaths=-/var/lib/fail2ban
# ReadWritePaths=-/var/log/fail2ban.log
# ReadWritePaths=-/var/spool/postfix/maildrop
# ReadWritePaths=-/run/xtables.lock
# CapabilityBoundingSet=CAP_AUDIT_READ CAP_DAC_READ_SEARCH CAP_NET_ADMIN CAP_NET_RAW






# Separate app specific configs in corresponding files for:
# Cockpit (port 9090)
# Nextcloud (via NGINX or Apache logs)
# Jellyfin & Home Assistant (limited support, but possible)




# The fail2ban-firewalld package writes a small override under /etc/fail2ban/jail.d/. Verify that Fail2ban will use Firewalld rich rules for normal and all-port bans:
sudo grep -E '^(banaction|banaction_allports)' /etc/fail2ban/jail.d/00-firewalld.conf
# Relevant output includes:
#     banaction = firewallcmd-rich-rules
#     banaction_allports = firewallcmd-rich-rules
# This Fedora default uses Firewalld rich rules, not Fail2ban-managed ipsets. Only switch to firewallcmd-ipset when you intentionally maintain an ipset-based policy and have tested that action on your server.




# Validate the Fail2ban configuration before restarting the service:
sudo fail2ban-client -t
# Reload fail2ban.service to apply the configuration changes. 
sudo systemctl restart fail2ban


# sudo systemctl enable fail2ban
# sudo systemctl start fail2ban
# sudo systemctl restart fail2ban

# To view all enabled jails: 
sudo fail2ban-client status

# To see specific jail:
# To check the status of a jail, e.g. for sshd: 
# systemctl is-active sshd
sudo fail2ban-client status sshd
# sudo fail2ban-client status nextcloud
# sudo fail2ban-client status cockpit


# For a compact version for all jails, including banned IPs: 
fail2ban-client banned

systemctl is-active fail2ban
systemctl is-enabled fail2ban


# # To ban or unban a specific address manually, target the jail by name:
# sudo fail2ban-client set sshd banip 203.0.113.7
# sudo fail2ban-client set sshd unbanip 203.0.113.7

# # Fail2ban writes its own log to /var/log/fail2ban.log. Use the tail command to review recent entries or follow new events:
# sudo tail -n 30 /var/log/fail2ban.log
# sudo tail -f /var/log/fail2ban.log
# # Use the grep command guide when you need stronger filtering. A quick IP lookup looks like this:
# sudo grep '203.0.113.7' /var/log/fail2ban.log

# # For SSH authentication failures, the active Fedora SSHD jail reads from the systemd journal. This check is useful when Fail2ban sees no failures but SSH login attempts are definitely happening:
# sudo journalctl -u sshd --since "1 hour ago" | grep "Failed password" | tail -n 10

# # A real SSH test should come from a second machine or VM, not from your only current admin session. Trigger a few failed logins against a non-existent test user, then stop before you lock out a legitimate account or automation source.
# ssh testuser@your-server-ip
# # After enough failed attempts to cross maxretry, check the jail and log:
# sudo fail2ban-client status sshd
# sudo tail -n 20 /var/log/fail2ban.log
# # If you used a real client address for testing, unban it when you are done:
# sudo fail2ban-client set sshd unbanip YOUR_TEST_IP
