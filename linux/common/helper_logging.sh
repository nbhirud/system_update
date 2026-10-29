#!/usr/bin/env bash
#########################################################
# helper_logging.sh
#########################################################
# Standard colored logging functions shared by all setup scripts.
#
# USAGE
#   source "${SYSUPDATE_CODE_BASE_DIR}/linux/common/helper_logging.sh"
#   log_header "Section title"      # blank line + cyan banner
#   log_info "something happened"   # blue   [INFO]
#   log_success "it worked"         # green  [✓]
#   log_warn "careful"              # yellow [!]  (stdout)
#   log_error "it failed"           # red    [✗]  (stderr, continues)
#   log_die "fatal"                 # red    [✗]  (stderr, exits 1)
#
# The colour constants are declared readonly. Re-declaring a readonly variable is an
# error in bash, so the block below is guarded: sourcing this file twice (for example
# from a helper that is itself sourced by the main script) is harmless.

if [[ -z "${HELPER_LOGGING_LOADED:-}" ]]; then
    HELPER_LOGGING_LOADED=1
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly RED='\033[0;31m'
    readonly NC='\033[0m' # No Color
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
fi

log_header() { echo -e "\n${CYAN}==================== $* ====================${NC}\n"; }
log_info() { echo -e "${BLUE}[INFO] $* ${NC}"; }
log_success() { echo -e "${GREEN}[✓] $* ${NC}"; }
log_warn() { echo -e "${YELLOW}[!] $* ${NC}"; }
log_error() { echo -e "${RED}[✗] $* ${NC}" >&2; }
log_die() { echo -e "${RED}[✗] $* ${NC}" >&2; exit 1; }
