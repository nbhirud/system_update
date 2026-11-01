#!/usr/bin/env bash
#########################################################
# helper_github_release.sh - download GitHub release assets with checksum verification
#########################################################
#
# WHAT IT DOES
#   github_latest_tag <owner/repo>
#       Prints the tag of the latest release, e.g. "v1.24.0".
#       It follows the https://github.com/<repo>/releases/latest redirect, so it
#       needs no API token and does not count against the API rate limit.
#
#   github_download_verified <owner/repo> <tag> <asset_name> <dest_dir>
#       Downloads <asset_name> and <asset_name>.sha256 from that release into
#       <dest_dir> and verifies the SHA-256. Returns non-zero on ANY problem
#       (download failure, missing checksum file, mismatch). A missing checksum
#       file is treated as a failure on purpose: unverified binaries are not
#       installed.
#
#   rust_musl_triple
#       Prints the Rust target triple for this CPU, using the statically linked
#       "musl" build: x86_64-unknown-linux-musl or aarch64-unknown-linux-musl.
#       Static binaries run on any glibc version, old or new.
#
# LIMITATION
#   Works only for projects that publish "<asset>.sha256" next to each asset
#   (Starship does). Projects with a single combined checksums file need a
#   different verification step.
#
# USAGE
#   source /path/to/helper_github_release.sh
#   tag="$(github_latest_tag starship/starship)"
#   github_download_verified starship/starship "$tag" \
#       "starship-$(rust_musl_triple).tar.gz" "$DOWNLOAD_DIR"
#
# REQUIREMENTS
#   curl, sha256sum, awk, uname


# Sourcing Guard Rails - uses a safety guard (HELPER_XYZ_LOADED) to prevent issues if it gets sourced multiple times.
if [[ -z "${HELPER_GITHUB_RELEASE_LOADED:-}" ]]; then
    HELPER_GITHUB_RELEASE_LOADED=1


  github_latest_tag() {
    local repo="$1"
    local final_url

    # -f fail on HTTP errors, -s silent, -S show errors, -L follow redirects,
    # -I HEAD request only (we need just the final URL, not the page),
    # -o /dev/null discard the body, -w print the final URL after redirects.
    final_url="$(curl -fsSLI --proto '=https' --tlsv1.2 -o /dev/null \
                      -w '%{url_effective}' \
                      "https://github.com/${repo}/releases/latest")" || return 1

    # The final URL looks like .../releases/tag/v1.24.0 ; keep what follows the last "/".
    printf '%s\n' "${final_url##*/}"
  }

  rust_musl_triple() {
    case "$(uname -m)" in
      x86_64)          printf '%s\n' "x86_64-unknown-linux-musl" ;;
      aarch64|arm64)   printf '%s\n' "aarch64-unknown-linux-musl" ;;
      *)               return 1 ;;   # unsupported CPU architecture
    esac
  }

  github_download_verified() {
    local repo="$1" tag="$2" asset="$3" dest="$4"
    local base="https://github.com/${repo}/releases/download/${tag}"
    local expected actual

    mkdir -p "$dest" || return 1

    curl -fsSL --retry 3 --proto '=https' --tlsv1.2 \
        -o "${dest}/${asset}" "${base}/${asset}" || return 1
    curl -fsSL --retry 3 --proto '=https' --tlsv1.2 \
        -o "${dest}/${asset}.sha256" "${base}/${asset}.sha256" || return 1

    # The .sha256 file may hold just the hash, or "hash  filename". The first
    # whitespace-separated field is the hash in both cases.
    expected="$(awk 'NR==1 {print $1}' "${dest}/${asset}.sha256")"
    actual="$(sha256sum "${dest}/${asset}" | awk '{print $1}')"

    if [[ -z "$expected" || "$expected" != "$actual" ]]; then
      echo "SHA-256 mismatch for ${asset}: expected '${expected}', got '${actual}'" >&2
      return 1
    fi
  }

fi
