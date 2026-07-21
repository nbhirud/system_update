#!/bin/bash

set -eux

# SSH Key Authentication - Why do this?
# Either remember the ssh paraphrase by entering it once, or else enter the server password everytime

# user defined constants
SERVER_IP_ADDRESS=""
SERVERNAME=""
SERVER_ADMIN_USER="${USER}"
SERVER_SSH_PORT="22"

# Generated constants
# HOSTNAME=$(sudo hostnamectl hostname)
HOSTNAME=$(hostname)
HOME_DIR=$(getent passwd "${USER}" | cut -d: -f6)
SSH_KEY_PATH="${HOME_DIR}/.ssh"
SSH_KEY_FILENAME="${SSH_KEY_PATH}/id_ed25519_${HOSTNAME}_${SERVERNAME}"

SSH_CONFIG_FILE="${SSH_KEY_PATH}/config"


# Check user defined constants


# if [[ -z "$SERVER_IP_ADDRESS" ]]; then
if [ "$SERVER_IP_ADDRESS" = "" ]; then
  echo "Please set SERVER_IP_ADDRESS and run again"
  exit 1
fi

if [ "$SERVERNAME" = "" ]; then
  echo "Please set SERVERNAME and run again"
  exit 1
fi

if [ "$SERVER_ADMIN_USER" = "" ]; then
  echo "Please set SERVER_ADMIN_USER and run again"
  exit 1
fi

if [ "$SERVER_SSH_PORT" = "" ]; then
  echo "Please set SERVER_SSH_PORT and run again"
  exit 1
fi

# Check if AES-NI is available on the current CPU
CPUINFO=$(grep -m1 aes /proc/cpuinfo)
AES_NI_AVAILABLE=false
# Check if CPUINFO contains aes
if [[ "${CPUINFO}" == *"aes"* ]]; then
    AES_NI_AVAILABLE=true
fi

# Decide cipher based on AES_NI_AVAILABLE
Z_PRIVATE_KEY_ENCRYPTION_CIPHER=chacha20-poly1305@openssh.com
if ${AES_NI_AVAILABLE}; then
    Z_PRIVATE_KEY_ENCRYPTION_CIPHER=aes256-gcm@openssh.com
fi

# Ensure that the .ssh directory exists
mkdir -p "${SSH_KEY_PATH}"
chmod 700 "${SSH_KEY_PATH}"

# Generate an SSH key pair. It will ask for passphrase. Don't forget the passphrase that you enter here. Set a strong passphrase for the key.

# ssh-keygen -t rsa -b 4096
# ssh-keygen -t ecdsa -b 521
# ssh-keygen -t ed25519 -a 100 -C user@hostname -f ~/.ssh/id_ed25519_hostname_servername

ssh-keygen -t ed25519 -a 100 -C "ssh_from_${HOSTNAME}_to_${SERVERNAME}" -f "${SSH_KEY_FILENAME}" -Z "${Z_PRIVATE_KEY_ENCRYPTION_CIPHER}"

# Copy the public key to the server. Enter the SERVER_ADMIN_USER password when prompted.
ssh-copy-id -p "${SERVER_SSH_PORT}" -i "${SSH_KEY_FILENAME}".pub "${SERVER_ADMIN_USER}"@"${SERVER_IP_ADDRESS}"


# Note: using multiple aliases (Host ${SERVERNAME} ${SERVER_IP_ADDRESS}) so that both of these work: 
# 1. ssh $SERVERNAME
# 2. ssh $SERVER_ADMIN_USER@$SERVER_IP_ADDRESS
cat > "${SSH_CONFIG_FILE}" <<EOL_SSH_CONFIG
Host ${SERVERNAME} ${SERVER_IP_ADDRESS}
    HostName ${SERVER_IP_ADDRESS}
    User ${SERVER_ADMIN_USER}
    Port ${SERVER_SSH_PORT}
    IdentityFile ${SSH_KEY_FILENAME}
    IdentitiesOnly yes
EOL_SSH_CONFIG

chmod 600 "${SSH_CONFIG_FILE}"

# At this point, we have eleminated the need to enter server password. But it will now ask for the passphrase used for encrypting the keys (in ssh-keygen command) every time we try to login. To eliminate this, we need to make use of SSH agent. If there is SSH agent holding the decrypted key in memory, SSH does not have to ask again. You'll enter the passphrase once. It will not ask again until the agent is cleared or you log out.

if [ -S "$SSH_AUTH_SOCK" ]; then
    
    # This will load only one specific key
    ssh-add "${SSH_KEY_FILENAME}"

    # This will load all keys matching the pattern. You'll enter each passphrase once per login session, and after that all SSH, Git, scp, rsync, and similar tools will work without prompting again.
    # ssh-add ~/.ssh/id_ed25519_* 
fi

# Test remote access:
# ssh -p "${SERVER_SSH_PORT}" "${SERVER_ADMIN_USER}"@"${SERVER_IP_ADDRESS}"
ssh "${SERVERNAME}"

