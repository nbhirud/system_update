#!/usr/bin/env bash
##################################################################################
# helper_opensnitch.sh
##################################################################################
# Purpose
#   Create OpenSnitch (process-aware egress firewall) rule files from a setup
#   script, but ONLY when OpenSnitch is actually installed.
#
# Usage
#   source "$HELPER_DIR/helper_opensnitch.sh"
#   if opensnitch_is_present; then
#     opensnitch_write_rule "allow-foo" allow false "Foo updater" \
#         '^.*/\.local/share/foo/bin/.*' '(^|\.)foo\.com$'
#   fi
#
# Arguments of opensnitch_write_rule
#   1 name         file name without .json (also the rule name shown in the UI)
#   2 action       allow | deny | reject
#   3 precedence   true | false  (true = wins over normal allow rules; use for deny)
#   4 description  free text
#   5 process_re   regex matched against the binary path ("" = any process)
#   6 host_re      regex matched against the destination host ("" = any host)
#
# Notes
#   - Paths are regexes, so a rule can be synced between machines (Syncthing)
#     even when the home directory differs: use '^.*/\.local/...' not '/home/x/...'.
#   - The daemon watches the rules directory and reloads rules automatically.
#   - Needs: jq, sudo (rules directory is root-owned).
#   - Rule JSON layout follows the OpenSnitch rule format: "operator" of type
#     "list" holds the conditions, which are ANDed together.
##################################################################################

if [ -n "${HELPER_OPENSNITCH_LOADED:-}" ]; then
  return 0
fi
HELPER_OPENSNITCH_LOADED=1

opensnitch_rules_dir() {
  printf '%s\n' "${OPENSNITCH_RULES_DIR:-/etc/opensnitchd/rules}"
}

# True when the rules directory exists (i.e. OpenSnitch daemon is installed).
opensnitch_is_present() {
  [ -d "$(opensnitch_rules_dir)" ]
}

opensnitch_write_rule() {
  local name="$1" action="$2" precedence="$3" description="$4"
  local proc_re="${5:-}" host_re="${6:-}"
  local rules_dir tmp now

  rules_dir="$(opensnitch_rules_dir)"
  [ -d "$rules_dir" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  now="$(date -u +%Y-%m-%dT%H:%M:%S.000000000Z)"
  tmp="$(mktemp)"

  # Build the condition list: one entry per non-empty regex. `data` carries the
  # same list as a JSON string, which is how OpenSnitch stores list operators.
  jq -n \
    --arg name "$name" --arg action "$action" --arg prec "$precedence" \
    --arg desc "$description" --arg proc "$proc_re" --arg host "$host_re" \
    --arg now "$now" '
    [ (if $proc != "" then {type:"regexp", operand:"process.path", sensitive:false, data:$proc} else empty end),
      (if $host != "" then {type:"regexp", operand:"dest.host",    sensitive:false, data:$host} else empty end) ] as $ops
    | { created:$now, updated:$now, name:$name, description:$desc,
        enabled:true, precedence:($prec == "true"), nolog:false,
        action:$action, duration:"always",
        operator:{ type:"list", operand:"list", sensitive:false,
                   data:($ops | tojson), list:$ops } }' >"$tmp" || { rm -f "$tmp"; return 1; }

  sudo install -D -m 0644 -o root -g root "$tmp" "$rules_dir/$name.json"
  rm -f "$tmp"
}
