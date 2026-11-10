#!/usr/bin/env bash
##################################################################################
# helper_jetbrains.sh
##################################################################################
# Purpose
#   Locate a JetBrains IDE installed by the Toolbox App and read its metadata.
#   Every JetBrains IDE ships <install_dir>/product-info.json describing the
#   product: version, dataDirectoryName (e.g. "PyCharm2026.2", used for the
#   config/plugin/cache directories), launcher path, bundled plugin ids.
#
# Functions
#   jetbrains_find_install <apps_dir> <data_dir_prefix>
#       Prints the install dir of the NEWEST product whose dataDirectoryName
#       starts with <data_dir_prefix> (e.g. "PyCharm"). Returns 1 if none.
#   jetbrains_product_info <install_dir> <jq_filter>
#       Prints the value of a jq filter applied to product-info.json.
#   jetbrains_launcher <install_dir>
#       Prints the absolute path of the IDE launcher script (bin/pycharm ...).
#
# Usage
#   source "$HELPER_DIR/helper_jetbrains.sh"
#   dir="$(jetbrains_find_install "$HOME/.local/share/JetBrains/Toolbox/apps" PyCharm)"
#   ddn="$(jetbrains_product_info "$dir" '.dataDirectoryName')"
#
# Needs: jq, find. Uses version_ge from helper_version_compare.sh.
##################################################################################

if [ -n "${HELPER_JETBRAINS_LOADED:-}" ]; then
  return 0
fi
HELPER_JETBRAINS_LOADED=1

if ! declare -F version_ge >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$(dirname "${BASH_SOURCE[0]}")/helper_version_compare.sh"
fi

jetbrains_product_info() {
  jq -r "$2 // empty" "$1/product-info.json" 2>/dev/null
}

jetbrains_launcher() {
  local rel
  rel="$(jetbrains_product_info "$1" '.launch[0].launcherPath')"
  [ -n "$rel" ] && [ -x "$1/$rel" ] && printf '%s\n' "$1/$rel"
}

jetbrains_find_install() {
  local apps_dir="$1" prefix="$2"
  local pi dir ddn ver best="" best_ver=""

  [ -d "$apps_dir" ] || return 1
  # Toolbox layouts differ between versions (apps/<tool>/ or apps/<tool>/<channel>/<build>/),
  # so search a few levels deep instead of hard-coding one layout.
  while IFS= read -r pi; do
    dir="$(dirname "$pi")"
    ddn="$(jetbrains_product_info "$dir" '.dataDirectoryName')"
    case "$ddn" in "$prefix"*) ;; *) continue ;; esac
    ver="$(jetbrains_product_info "$dir" '.buildNumber')"
    [ -n "$ver" ] || ver="0"
    if [ -z "$best" ] || version_ge "$ver" "$best_ver"; then
      best="$dir"
      best_ver="$ver"
    fi
  done < <(find "$apps_dir" -maxdepth 6 -name product-info.json 2>/dev/null)

  [ -n "$best" ] || return 1
  printf '%s\n' "$best"
}
