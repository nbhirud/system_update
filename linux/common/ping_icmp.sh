

cat >/etc/sysctl.d/99-local-network.conf <<'EOF'
net.ipv4.icmp_echo_ignore_all=0
EOF

sysctl --system



# Allow ICMP (Allow ping)
# sudo firewall-cmd --permanent --add-icmp-block-inversion

# above might not the proper way to "allow ping." In most Fedora home setups, ping is already allowed unless you've added ICMP blocks. If after moving to the home zone ping still doesn't work, inspect:
# sudo firewall-cmd --list-icmp-blocks
# sudo nft list ruleset