#!/usr/bin/env bash
#########################################################
# helper_github_release.sh - safely install/update a prebuilt binary from GitHub Releases
#########################################################
#
# WHAT IT DOES
#   github_release_pick <owner/repo> <min_age_days>
#       Prints the newest stable release tag that is at least <min_age_days> old.
#       Why the delay ("cooldown"): a malicious or broken release is usually noticed and
#       pulled within days. Waiting a few days avoids being among the first victims.
#       Uses the GitHub API for release dates. If the API is unreachable (rate limit, offline
#       proxy), it falls back to the "latest" redirect and prints a warning to stderr: the
#       install still works, only the cooldown is skipped.
#
#   github_release_asset_digest <owner/repo> <tag> <asset>
#       Prints the SHA-256 that GitHub itself computed when the asset was uploaded (immutable,
#       shown in the API). Prints nothing if the API is unavailable.
#
#   github_download_verified <owner/repo> <tag> <asset> <dest_dir>
#       Downloads <asset> and <asset>.sha256 and verifies:
#         1. the project's .sha256 sidecar matches the download (catches corruption/truncation)
#         2. GitHub's own upload-time digest matches too, when available (catches an asset
#            that was swapped after upload)
#       Any mismatch or missing sidecar = failure. Unverified binaries are never installed.
#
#   nb_install_github_binary <repo> <asset_template> <binary> <dest_path> <min_age_days> <work_dir> [installed_version]
#       Full flow: pick release -> download -> verify -> extract -> install root:root 0755.
#       <asset_template> contains @TRIPLE@, replaced by x86_64-unknown-linux-musl (or aarch64).
#       Return codes: 0 = installed (tag in NB_INSTALLED_TAG), 10 = already current, 1 = error.
#       The binary is replaced atomically (install next to target, then rename).
#
#   rust_musl_triple
#       x86_64-unknown-linux-musl | aarch64-unknown-linux-musl (static: runs on any glibc).
#
# WHAT THIS CANNOT PROTECT AGAINST
#   Checksums and digests come from the same GitHub project as the binary. They protect
#   against corruption, mirrors and post-upload tampering, not against a compromised upstream
#   release. The cooldown reduces (does not remove) that exposure.
#
# SELF-CONTAINED
#   Installed unchanged to /usr/local/lib/nb/ so root-run updaters can use it without
#   touching any user-owned directory. Does not depend on helper_common.sh.
#
# REQUIREMENTS: curl, sha256sum, awk, tar, python3, install, find


# COMPATIBILITY: supersedes the earlier helper_github_release.sh. github_latest_tag, rust_musl_triple and
# github_download_verified keep their names, arguments and return codes; everything else is new.

# Sourcing Guard Rails - uses a safety guard (HELPER_XYZ_LOADED) to prevent issues if it gets sourced multiple times.
if [[ -z "${HELPER_GITHUB_RELEASE_LOADED:-}" ]]; then
    HELPER_GITHUB_RELEASE_LOADED=1

    NB_GITHUB_API_BASE="${NB_GITHUB_API_BASE:-https://api.github.com}"   # overridable (tests mock _gh_curl instead)

    _gh_warn() { echo "github_release: $*" >&2; }

    _gh_curl() {
      # --proto/--tlsv1.2: HTTPS only, no downgrade. --retry: tolerate flaky networks.
      curl -fsSL --retry 3 --proto '=https' --tlsv1.2 "$@"
    }

    rust_musl_triple() {
      case "$(uname -m)" in
        x86_64)        printf '%s\n' "x86_64-unknown-linux-musl" ;;
        aarch64|arm64) printf '%s\n' "aarch64-unknown-linux-musl" ;;
        *)             return 1 ;;
      esac
    }

    github_latest_tag() {
      local repo="$1" final_url
      # HEAD request that follows redirects; the final URL ends in /releases/tag/<tag>.
      final_url="$(curl -fsSLI --proto '=https' --tlsv1.2 -o /dev/null -w '%{url_effective}' \
                        "https://github.com/${repo}/releases/latest")" || return 1
      printf '%s\n' "${final_url##*/}"
    }

    github_release_pick() {
      local repo="$1" min_days="$2" json tag rc
      if ! json="$(_gh_curl "${NB_GITHUB_API_BASE}/repos/${repo}/releases?per_page=20")"; then
        _gh_warn "API unavailable for ${repo}; using the latest release WITHOUT the ${min_days}-day cooldown"
        github_latest_tag "$repo"
        return $?
      fi
      tag="$(printf '%s' "$json" | python3 -c '
    import json, sys, datetime
    min_days = float(sys.argv[1])
    now = datetime.datetime.now(datetime.timezone.utc)
    for r in json.load(sys.stdin):
        if r.get("draft") or r.get("prerelease"):
            continue
        pub = datetime.datetime.fromisoformat(r["published_at"].replace("Z", "+00:00"))
        if (now - pub).total_seconds() >= min_days * 86400:
            print(r["tag_name"])
            sys.exit(0)
    sys.exit(3)
    ' "$min_days")" && rc=0 || rc=$?
      if [[ $rc -eq 0 && -n "$tag" ]]; then
        printf '%s\n' "$tag"
      elif [[ $rc -eq 3 ]]; then
        _gh_warn "no stable ${repo} release is older than ${min_days} days"
        return 1
      else
        _gh_warn "could not parse the release list for ${repo}"
        return 1
      fi
    }

    github_release_asset_digest() {
      local repo="$1" tag="$2" asset="$3" json
      json="$(_gh_curl "${NB_GITHUB_API_BASE}/repos/${repo}/releases/tags/${tag}")" || return 0
      printf '%s' "$json" | python3 -c '
    import json, sys
    name = sys.argv[1]
    for a in json.load(sys.stdin).get("assets", []):
        d = a.get("digest") or ""
        if a.get("name") == name and d.startswith("sha256:"):
            print(d[7:])
            break
    ' "$asset" 2>/dev/null || true
    }

    github_download_verified() {
      local repo="$1" tag="$2" asset="$3" dest="$4"
      local base="https://github.com/${repo}/releases/download/${tag}"
      local expected actual api_digest

      mkdir -p "$dest" || return 1
      _gh_curl -o "${dest}/${asset}" "${base}/${asset}" || return 1
      _gh_curl -o "${dest}/${asset}.sha256" "${base}/${asset}.sha256" || return 1

      # The sidecar holds "hash" or "hash  filename" or "hash *filename": the first field is the hash.
      expected="$(awk 'NR==1 {print $1}' "${dest}/${asset}.sha256")"
      actual="$(sha256sum "${dest}/${asset}" | awk '{print $1}')"
      if [[ -z "$expected" || "$expected" != "$actual" ]]; then
        _gh_warn "SHA-256 mismatch for ${asset}: sidecar '${expected}', download '${actual}'"
        return 1
      fi

      api_digest="$(github_release_asset_digest "$repo" "$tag" "$asset")"
      if [[ -n "$api_digest" && "$api_digest" != "$actual" ]]; then
        _gh_warn "GitHub's upload digest differs for ${asset}: '${api_digest}' vs '${actual}'"
        return 1
      fi
      if [[ -z "$api_digest" ]]; then
        _gh_warn "GitHub digest unavailable; verified against the project's sidecar only"
      fi
    }

    NB_INSTALLED_TAG=""
    nb_install_github_binary() {
      local repo="$1" template="$2" binary="$3" dest="$4" days="$5" work="$6" current="${7:-}"
      local tag triple asset bin

      tag="$(github_release_pick "$repo" "$days")" || return 1
      if [[ -n "$current" && ( "v${current}" == "$tag" || "$current" == "$tag" ) ]]; then
        echo "${binary} ${current} is current (${tag})"
        return 10
      fi

      triple="$(rust_musl_triple)" || { _gh_warn "unsupported CPU architecture: $(uname -m)"; return 1; }
      asset="${template//@TRIPLE@/$triple}"

      github_download_verified "$repo" "$tag" "$asset" "$work" || return 1
      mkdir -p "${work}/extracted" || return 1
      tar -xzf "${work}/${asset}" -C "${work}/extracted" || return 1
      # Archives differ: starship has the binary at the top level, atuin inside a directory.
      bin="$(find "${work}/extracted" -type f -name "$binary" -print -quit)"
      [[ -n "$bin" ]] || { _gh_warn "binary '${binary}' not found in ${asset}"; return 1; }

      # Install next to the target and rename: replacing a running binary in place can fail.
      install -o root -g root -m 0755 "$bin" "${dest}.new" || return 1
      mv -f "${dest}.new" "$dest" || return 1
      NB_INSTALLED_TAG="$tag"
      echo "${binary} installed: ${tag}"
    }

fi
