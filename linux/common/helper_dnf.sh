#!/usr/bin/env bash
#########################################################
# helper_dnf.sh
#########################################################
# Fedora package installation helpers (DNF5 and DNF4 compatible commands).
#
# REQUIRES: helper_logging.sh, and DISTRO set from get_distro_name.sh
#
# require_fedora            aborts when DISTRO is not fedora
# rpm_is_installed <pkg>    0 when the RPM is installed
# dnf_available_names <pkg>...
#                           prints those names a configured repository offers
# dnf_install_packages <pkg>...
#                           installs the missing ones (skips installed, warns about
#                           names no repository offers) in ONE transaction without
#                           removing anything
# dnf_install_replacing <pkg>...
#                           same, but with --allowerasing, for packages that replace
#                           installed ones (e.g. ffmpeg replacing ffmpeg-free). The
#                           planned transaction is printed first (dry run), then run.
#
# Why filter against the repositories first: `dnf install a b c` aborts the whole
# transaction when ONE name does not exist (renamed/removed packages, repo not enabled).
# Filtering turns that into a warning for the one package.

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/helper_array.sh"

require_fedora() {
    if [[ "${DISTRO,,}" != *fedora* ]]; then
        log_die "This step uses dnf/RPM Fusion and only supports Fedora (detected: ${DISTRO:-unknown})."
    fi
}

rpm_is_installed() { rpm -q --quiet "$1" 2>/dev/null; }

dnf_available_names() {
    dnf repoquery --quiet --available --queryformat '%{name}\n' "$@" 2>/dev/null | sort -u || true
}

# Internal: build the list of packages that still need installing and are available.
_dnf_missing_available() {
    local -a wanted=("$@") offered=() result=()
    local pkg
    mapfile -t offered < <(dnf_available_names "${wanted[@]}")
    if (( ${#offered[@]} == 0 )); then
        log_die "'dnf repoquery' returned nothing: check network and repository configuration."
    fi
    for pkg in "${wanted[@]}"; do
        if rpm_is_installed "$pkg"; then
            continue
        fi
        if array_contains "$pkg" "${offered[@]}"; then
            result+=("$pkg")
        else
            log_warn "Package not available in enabled repositories, skipping: ${pkg}" >&2
        fi
    done
    # printf with an EMPTY array still prints one blank line, which mapfile would turn into a
    # single empty-string "package"; only print when there is something to print.
    if (( ${#result[@]} )); then
        printf '%s\n' "${result[@]}"
    fi
}

# Internal: remove empty entries from the array named by $1 (belt and braces for the case above).
_dnf_drop_empty() {
    local -n _arr="$1"
    local -a kept=()
    local item
    for item in "${_arr[@]}"; do
        if [[ -n "$item" ]]; then kept+=("$item"); fi
    done
    _arr=("${kept[@]}")
}

dnf_install_packages() {
    require_fedora
    local -a todo=()
    mapfile -t todo < <(_dnf_missing_available "$@")
    _dnf_drop_empty todo
    if (( ${#todo[@]} == 0 )); then
        log_success "Nothing to install (all present or unavailable): $(array_join_space "$@")"
        return 0
    fi
    log_info "Installing: $(array_join_space "${todo[@]}")"
    sudo dnf install -y "${todo[@]}"
}

dnf_install_replacing() {
    require_fedora
    local -a todo=()
    mapfile -t todo < <(_dnf_missing_available "$@")
    _dnf_drop_empty todo
    if (( ${#todo[@]} == 0 )); then
        log_success "Nothing to install (all present or unavailable): $(array_join_space "$@")"
        return 0
    fi
    log_info "Planned transaction (dry run) for: $(array_join_space "${todo[@]}")"
    sudo dnf install --assumeno --allowerasing "${todo[@]}" || true   # --assumeno exits 1 by design
    log_info "Installing (may replace conflicting packages): $(array_join_space "${todo[@]}")"
    sudo dnf install -y --allowerasing "${todo[@]}"
}
