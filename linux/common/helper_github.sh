#!/usr/bin/env bash
#########################################################
# helper_github.sh
#########################################################
# Resolve "latest" versions of GitHub projects without the REST API (the API is rate
# limited to 60 requests/hour per IP for anonymous callers).
#
# github_latest_tag <owner/repo>
#   Prints the tag of the latest *release*, or nothing when the project has no releases.
#   Method: https://github.com/<owner>/<repo>/releases/latest redirects to
#   .../releases/tag/<tag>. The final URL after redirects is read with curl's
#   %{url_effective}; for projects without releases the redirect ends at
#   .../releases, so the result does not contain "/tag/" and nothing is printed.
#
# github_raw_url <owner/repo> <ref> <path>
#   Prints the raw-content URL of <path> at <ref> (a tag, a commit, or HEAD for the
#   default branch).

github_latest_tag() {
    local repo="$1" final
    final="$(curl --proto '=https' --tlsv1.2 -fsSL --retry 2 --connect-timeout 15 --max-time 30 \
                  -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest" 2>/dev/null || true)"
    if [[ "$final" == */releases/tag/* ]]; then
        printf '%s\n' "${final##*/}"
    fi
    return 0
}

github_raw_url() {
    printf 'https://raw.githubusercontent.com/%s/%s/%s\n' "$1" "$2" "$3"
}
