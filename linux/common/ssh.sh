# # Key-based SSH (no passwords)

# # On main PC:
# ssh-keygen
# ssh-copy-id user@OtherPC.local

# # Then disable password auth later if you want a hardened setup.

# systemctl enable --now sshd