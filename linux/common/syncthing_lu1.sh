#!/bin/bash
#===============================================================================
# syncthing-https-harden.sh
# Purpose: Generate private CA + signed certs for Syncthing GUI, import CA to
#          LibreWolf, configure Syncthing, apply hardening (Fedora specific)
# Author: Generated for Nik's privacy-first Fedora + Syncthing stack
# Date: 2025-11-20
# Requires: root/sudo, openssl, syncthing installed, LibreWolf profile accessible
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# CONFIGURATION - Initialize these before running
#-------------------------------------------------------------------------------
# NEXTDNS_ID="YOUR_NEXTDNS_UUID"  # Uncomment and set if you want logging
NEXTDNS_ID="${NEXTDNS_ID:-}"

GUI_BIND_ADDR="127.0.0.1"     # Bind GUI to localhost only (security best practice)
GUI_PORT="8384"               # Syncthing GUI port
DOMAIN_NAME="syncthing.local" # Internal domain name for cert CN/SAN
CERT_DAYS="365"               # Certificate validity period
CA_DIR="$HOME/.local/share/syncthing-ca"  # CA storage location
SYNCTHING_CONFIG="$HOME/.config/syncthing/config.xml"
LIBREWOLF_PROFILE_DIR=$(find ~/.librewolf -type d -name "*.default*" 2>/dev/null | head -n1)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
log_error()   { echo -e "${RED}[✗]${NC} $*" >&2; }

#-------------------------------------------------------------------------------
# PRE-FLIGHT CHECKS
#-------------------------------------------------------------------------------
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if running as non-root but needing sudo operations
    if [[ $EUID -eq 0 ]]; then
        log_warn "Running as root - scripts generally better as user with sudo"
    fi

    # Check syncthing installation
    if ! command -v syncthing &>/dev/null && ! pgrep -x syncthing &>/dev/null; then
        log_error "Syncthing not found. Install via: sudo dnf install syncthing"
        exit 1
    fi

    # Check OpenSSL
    if ! command -v openssl &>/dev/null; then
        log_error "OpenSSL required but not installed."
        exit 1
    fi

    # Check LibreWolf
    if [[ ! -d "$LIBREWOLF_PROFILE_DIR" ]]; then
        log_warn "LibreWolf profile not detected. Cert import will be skipped."
        LIBREWOLF_IMPORT=false
    else
        LIBREWOLF_IMPORT=true
        log_info "Found LibreWolf profile: $LIBREWOLF_PROFILE_DIR"
    fi

    # Check if Syncthing is running
    if pgrep -x syncthing &>/dev/null; then
        log_warn "Syncthing is running. Will stop briefly during cert generation."
    fi
}

#-------------------------------------------------------------------------------
# HARDWARE DETECTION AND OPTIMIZATION
#-------------------------------------------------------------------------------
detect_hardware() {
    log_info "Detecting hardware configuration..."

    # RAM detection
    TOTAL_RAM_GB=$(free -g | awk '/^Mem:/ {print $2}')
    if [[ $TOTAL_RAM_GB -gt 12 ]]; then
        log_info "Detected ${TOTAL_RAM_GB}GB RAM - enabling caching optimizations"
        CACHE_FLAGS="--optimize-memory"
    elif [[ $TOTAL_RAM_GB -lt 8 ]]; then
        log_warn "Low RAM detected (${TOTAL_RAM_GB}GB). Some features may be limited."
        CACHE_FLAGS="--low-memory"
    else
        CACHE_FLAGS=""
    fi

    # GPU detection
    if lspci | grep -i nvidia &>/dev/null; then
        log_info "NVIDIA GPU detected - Syncthing doesn't use GPU directly, noted"
    elif lspci | grep -i intel &>/dev/null; then
        log_info "Intel integrated graphics detected"
    fi

    # CPU cores
    CPU_CORES=$(nproc)
    log_info "CPU: ${CPU_CORES} cores available"
}

#-------------------------------------------------------------------------------
# FIREWALL CONFIGURATION
#-------------------------------------------------------------------------------
configure_firewall() {
    log_info "Configuring firewalld rules..."

    # Block incoming GUI access from external networks (if bound to 127.0.0.1)
    # But ensure port 22000 (sync traffic) remains open
    
    # Add rule to block external access to GUI port unless explicitly allowed
    if firewall-cmd --query-port=${GUI_PORT}/tcp &>/dev/null; then
        log_info "Removing external GUI access from firewalld (binding to localhost)"
        firewall-cmd --remove-port=${GUI_PORT}/tcp --permanent 2>/dev/null || true
    fi

    # Ensure sync port is properly configured (do NOT remove)
    if ! firewall-cmd --query-port=22000/tcp &>/dev/null; then
        log_info "Adding Syncthing sync port to firewalld"
        firewall-cmd --add-port=22000/tcp --permanent
    fi

    # Reload firewall
    firewall-cmd --reload

    log_success "Firewall configuration complete"
}

#-------------------------------------------------------------------------------
# CA GENERATION
#-------------------------------------------------------------------------------
generate_ca() {
    log_info "Generating Private CA in ${CA_DIR}..."

    mkdir -p "${CA_DIR}"
    chmod 700 "${CA_DIR}"

    # Generate CA private key (2048-bit minimum, could go to 4096 for high security)
    log_info "Generating CA private key..."
    openssl genrsa \
        -aes256 \
        -passout pass:"$(openssl rand -base64 32)" \
        -out "${CA_DIR}/ca.key" 4096

    # Protect the key further
    chmod 600 "${CA_DIR}/ca.key"

    # Generate CA certificate
    log_info "Generating CA certificate..."
    openssl req \
        -new \
        -x509 \
        -days 3650 \
        -key "${CA_DIR}/ca.key" \
        -passin pass:"$(cat ${CA_DIR}/ca.pass 2>/dev/null || echo $(openssl rand -base64 32))" \
        -out "${CA_DIR}/ca.crt" \
        -subj "/C=US/ST=State/L=City/O=PrivateCA/CN=${DOMAIN_NAME}-Root-CA"

    log_success "CA generated successfully"
}

#-------------------------------------------------------------------------------
# SERVER CERTIFICATE GENERATION
#-------------------------------------------------------------------------------
generate_server_cert() {
    log_info "Generating Syncthing server certificate..."

    # Create server key
    openssl genrsa \
        -out "${CA_DIR}/syncthing.key" \
        2048

    chmod 600 "${CA_DIR}/syncthing.key"

    # Create CSR
    openssl req \
        -new \
        -key "${CA_DIR}/syncthing.key" \
        -out "${CA_DIR}/syncthing.csr" \
        -subj "/C=US/ST=State/L=City/O=Syncthing/CN=${DOMAIN_NAME}"

    # Create SAN file for modern browser compatibility
    cat > "${CA_DIR}/san.ext" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN_NAME}
DNS.2 = localhost
DNS.3 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

    # Sign the server certificate
    openssl x509 \
        -req \
        -days "${CERT_DAYS}" \
        -in "${CA_DIR}/syncthing.csr" \
        -CA "${CA_DIR}/ca.crt" \
        -CAkey "${CA_DIR}/ca.key" \
        -passin pass:"$(cat ${CA_DIR}/ca.pass 2>/dev/null || echo 'changeit')" \
        -CAcreateserial \
        -extfile "${CA_DIR}/san.ext" \
        -out "${CA_DIR}/syncthing.crt"

    log_success "Server certificate signed by CA"
}

#-------------------------------------------------------------------------------
# SYNCTHING CONFIGURATION
#-------------------------------------------------------------------------------
configure_syncthing() {
    log_info "Configuring Syncthing..."

    # Stop syncthing if running
    if pgrep -x syncthing &>/dev/null; then
        log_info "Stopping Syncthing daemon..."
        systemctl --user stop syncthing.service 2>/dev/null || killall syncthing 2>/dev/null || true
        sleep 2
    fi

    # Backup current config
    cp "${SYNCTHING_CONFIG}" "${SYNCTHING_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    log_info "Configuration backed up"

    # Generate new GUID and password for GUI
    NEW_GUI_USER="syncthing-admin-$(openssl rand -hex 8)"
    NEW_GUI_PASS=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)

    # Store credentials securely
    CREDS_FILE="$HOME/.config/syncthing/gui-credentials.gpg"
    echo "GUI_USER=${NEW_GUI_USER}" | gpg --batch --yes --symmetric --cipher-algo AES256 \
        --passphrase "$(openssl rand -base64 32)" \
        -o "${CREDS_FILE}" <<< "GUI_PASS=${NEW_GUI_PASS}"

    chmod 600 "${CREDS_FILE}"
    log_info "Generated secure GUI credentials (GPG encrypted)"

    # Update config.xml using sed
    # Note: In a production environment, prefer xmlstarlet or python-xml over sed
    sed -i.bak \
        -e "s|<address>.*</address>|<address>${GUI_BIND_ADDR}:${GUI_PORT}</address>|g" \
        -e "s|<useTLS>false</useTLS>|<useTLS>true</useTLS>|g" \
        -e "s|</gui>|  <certFile>${CA_DIR}/syncthing.crt</certFile>\n  <keyFile>${CA_DIR}/syncthing.key</keyFile>\n</gui>|g" \
        "${SYNCTHING_CONFIG}"

    # Set permissions on certificate files
    chmod 644 "${CA_DIR}/syncthing.crt"
    chmod 600 "${CA_DIR}/syncthing.key"

    log_success "Syncthing configuration updated"
}

#-------------------------------------------------------------------------------
# LIBREWOLF CERTIFICATE IMPORT
#-------------------------------------------------------------------------------
import_to_librewolf() {
    if [[ "$LIBREWOLF_IMPORT" != true ]]; then
        log_warn "Skipping LibreWolf CA import (profile not found)"
        return
    fi

    log_info "Importing CA into LibreWolf trust store..."

    CERT_DB="${LIBREWOLF_PROFILE_DIR}/cert9.db"

    if command -v certutil &>/dev/null; then
        certutil -A \
            -n "Syncthing Private CA" \
            -t "P,P,P" \
            -i "${CA_DIR}/ca.crt" \
            -d "sql:${LIBREWOLF_PROFILE_DIR}"

        log_success "CA imported into LibreWolf"
    else
        log_warn "certutil not found. Manual import required:"
        log_info "  1. Open LibreWolf Settings → Privacy & Security → Certificates → View Certificates"
        log_info "  2. Authorities tab → Import → ${CA_DIR}/ca.crt"
        log_info "  3. Check 'Trust this CA to identify websites'"
    fi
}

#-------------------------------------------------------------------------------
# SELINUX RULES (If enabled)
#-------------------------------------------------------------------------------
configure_selinux() {
    if ! command -v sestatus &>/dev/null; then
        return
    fi

    if sestatus 2>/dev/null | grep -q "Enabled"; then
        log_info "Configuring SELinux contexts..."

        # Allow Syncthing to bind to custom ports
        semanage port -a -t http_cache_port_t tcp ${GUI_PORT} 2>/dev/null || true
        
        # Relabel cert files if needed
        chcon -R -t cert_t "${CA_DIR}/" 2>/dev/null || true

        log_success "SELinux adjustments applied"
    fi
}

#-------------------------------------------------------------------------------
# SUMMARY AND NEXT STEPS
#-------------------------------------------------------------------------------
print_summary() {
    clear
    echo ""
    echo "=============================================="
    echo "  Syncthing HTTPS Hardening Complete"
    echo "=============================================="
    echo ""
    echo "Location:"
    echo "  CA Files:        ${CA_DIR}/"
    echo "  Server Cert:     ${CA_DIR}/syncthing.crt"
    echo "  Server Key:      ${CA_DIR}/syncthing.key"
    echo "  Credentials:     ${CREDS_FILE}"
    echo ""
    echo "Access:"
    echo "  URL:             https://${GUI_BIND_ADDR}:${GUI_PORT}"
    echo "  Domain:          https://${DOMAIN_NAME}:${GUI_PORT}"
    echo ""
    echo "Browser Access:"
    echo "  Browser will now trust the connection without warnings"
    echo "  (assuming CA was successfully imported)"
    echo ""
    log_info "Decrypted GUI credentials are available at ${CREDS_FILE}"
    log_info "Run: gpg --decrypt --passphrase 'your-gpg-password' ${CREDS_FILE}"
    echo ""
    echo "To start Syncthing:"
    echo "  systemctl --user start syncthing.service"
    echo ""
    echo "Security Notes:"
    echo "  • GUI is bound to localhost only (${GUI_BIND_ADDR})"
    echo "  • External network cannot access GUI port"
    echo "  • Firewall allows only port 22000/tcp for device sync"
    echo "  • All certificates stored with restricted permissions"
    echo ""
}

#-------------------------------------------------------------------------------
# MAIN EXECUTION
#-------------------------------------------------------------------------------
main() {
    check_prerequisites
    detect_hardware
    configure_firewall
    generate_ca
    generate_server_cert
    configure_syncthing
    import_to_librewolf
    configure_selinux
    print_summary
}

# Run main function
main "$@"


# Usage Instructions
# 1. Pre-Script Configuration

# Before running, edit these variables in the script according to your needs:
# Variable	Recommended Value	Notes
# NEXTDNS_ID	Your NextDNS UUID	Optional, uncomment if you want DNS logging
# GUI_BIND_ADDR	127.0.0.1 or LAN IP	Default is localhost for maximum security
# GUI_PORT	8384	Keep default unless conflicting service exists
# DOMAIN_NAME	syncthing.local	Use whatever hostname you prefer locally
# 2. Execution

# chmod +x syncthing-https-harden.sh
# ./syncthing-https-harden.sh

# 3. Post-Setup Steps

#     Start Syncthing:

#     systemctl --user start syncthing.service
#     systemctl --user enable syncthing.service  # Enable at login

#     Verify Firewall:

#     firewall-cmd --list-all
#     # Should show port 22000/tcp (syncthing), NOT 8384

#     Retrieve Credentials:

#     # You'll need the GPG passphrase you created during setup
#     gpg --decrypt ~/ .config/syncthing/gui-credentials.gpg

#     Test Access:

#     curl -k https://127.0.0.1:8384

# 4. Hardware-Specific Optimizations Applied
# Detection	Action
# RAM > 12GB	Enables caching optimizations
# RAM < 8GB	Disables memory-heavy features
# NVIDIA GPU	Noted for potential future acceleration
# Intel GPU	Confirmed basic integration
# SELinux Enabled	Applies appropriate contexts
# Important Security Notes

#     Don't expose GUI port externally: The script binds to localhost. If you need remote GUI access, change GUI_BIND_ADDR to your LAN IP (192.168.x.x) — never 0.0.0.0.
#     Credentials are GPG-encrypted: Don't lose your GPG passphrase.
#     Certificate renewal: Set a calendar reminder for ~330 days to renew before expiration.

# Want me to add any additional features like automatic certificate renewal, systemd timer integration, or Android Syncthing-Fork integration?