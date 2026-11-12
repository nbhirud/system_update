#!/usr/bin/env bash

##################################################################################
# Overview and Usage
##################################################################################
# pycharm_post_launch.sh - STAGE 2, run AFTER PyCharm has been opened once.
# Read-only: it changes nothing. It checks what only a launched IDE can show and
# prints the short list of settings that exist only in the GUI.
#
# Checks
#   - the IDE created its log, and which display toolkit it really uses
#   - the JVM flags of a running PyCharm match pycharm64.vmoptions (-Xmx, toolkit)
#   - our option files and disabled_plugins.txt survived the first run
#   - the plugins are installed and AI plugins are not loaded
#   - data-sharing consent state (informational)
#
# Sample calls (assuming the caller uses the same variable names)
#   (a) all options:  bash "$COMMON_DIR/pycharm_post_launch.sh" --real-user "$REAL_USER" \
#                          --filename-timestamp "$FILENAME_TIMESTAMP"
#   (b) mandatory only: bash "$COMMON_DIR/pycharm_post_launch.sh"
#   (c) --verify-setup is accepted for consistency; this whole script IS verification.
##################################################################################

set -Eeuo pipefail
ORIGINAL_ARGS=("$@")

##################################################################################
# User defined variables
##################################################################################
VERIFY_ONLY=true   # the script is verification only; flag accepted for uniformity

##################################################################################
# Named Options processing
##################################################################################
while [ $# -gt 0 ]; do
  case "$1" in
    --real-user)             REAL_USER="${2:?--real-user needs a value}"; shift 2 ;;
    --real-user=*)           REAL_USER="${1#*=}"; shift ;;
    --filename-timestamp)    FILENAME_TIMESTAMP="${2:?--filename-timestamp needs a value}"; shift 2 ;;
    --filename-timestamp=*)  FILENAME_TIMESTAMP="${1#*=}"; shift ;;
    --verify-setup)          shift ;;
    -h|--help)               echo "Usage: pycharm_post_launch.sh [--real-user NAME] [--filename-timestamp TS] [--verify-setup]"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

##################################################################################
# Inferred variables
##################################################################################
REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update"
COMMON_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/common"
GETTER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commong"
HELPER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commonh"
SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_LOGS="${SCRIPT_DATA}/logs"

PYCHARM_LOG_DIR_BASE="${SCRIPT_DATA_LOGS}/pycharm"
PYCHARM_CURRENT_LOG_DIR="${PYCHARM_LOG_DIR_BASE}/pycharm_${FILENAME_TIMESTAMP}"
LOG_FILE="${PYCHARM_CURRENT_LOG_DIR}/pycharm_post_launch.log"
TOOLBOX_APPS_DIR="${HOME_DIR}/.local/share/JetBrains/Toolbox/apps"
USER_BIN_DIR="${HOME_DIR}/.local/bin"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

##################################################################################
# Helpers
##################################################################################
for helper in helper_logging helper_run_as_user helper_version_compare helper_script_logging helper_jetbrains; do
  if [ ! -r "${HELPER_DIR}/${helper}.sh" ]; then echo "ERROR: missing helper ${HELPER_DIR}/${helper}.sh" >&2; exit 1; fi
  # shellcheck source=/dev/null
  . "${HELPER_DIR}/${helper}.sh"
done
ensure_real_user "${ORIGINAL_ARGS[@]}"
export REAL_USER FILENAME_TIMESTAMP
start_script_logging "$LOG_FILE" "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"

VERIFY_PASS=0; VERIFY_WARN=0; VERIFY_FAIL=0
check_pass() { VERIFY_PASS=$((VERIFY_PASS + 1)); log_success "$*"; }
check_warn() { VERIFY_WARN=$((VERIFY_WARN + 1)); log_warn "$*"; }
check_fail() { VERIFY_FAIL=$((VERIFY_FAIL + 1)); log_error "$*"; }

##################################################################################
# Backup / Reset / Security
##################################################################################
# Intentionally empty: this stage is read-only (nothing to back up, reset or secure).

##################################################################################
# main setup
##################################################################################
# (read-only stage: the work happens in Verification)

##################################################################################
# Verification
##################################################################################
verify_post_launch() {
  log_header "Post-launch verification"
  local ide_dir ddn config_dir plugins_base log_file jvm_args expected_xmx f consent

  ide_dir="$(jetbrains_find_install "$TOOLBOX_APPS_DIR" PyCharm)" || { check_fail "No PyCharm under ${TOOLBOX_APPS_DIR}"; return 1; }
  ddn="$(jetbrains_product_info "$ide_dir" '.dataDirectoryName')"
  config_dir="${HOME_DIR}/.config/JetBrains/${ddn}"
  plugins_base="${HOME_DIR}/.local/share/JetBrains/${ddn}"
  log_file="${HOME_DIR}/.cache/JetBrains/${ddn}/log/idea.log"
  check_pass "PyCharm ${ddn}"

  # 1. The IDE has run and logged.
  if [ -f "$log_file" ]; then
    check_pass "IDE log exists: ${log_file}"
  else
    check_fail "No idea.log yet: open PyCharm once, wait for the welcome screen, then re-run"
    return 1
  fi

  # 2. Display toolkit actually used (documented log line "toolkit: ...").
  local toolkit
  toolkit="$(grep -m1 -oE 'toolkit: [A-Za-z.]+' "$log_file" || true)"
  case "$toolkit" in
    *WLToolkit*) check_pass "Display: native Wayland (${toolkit})" ;;
    *XToolkit*)  check_pass "Display: X11/XWayland (${toolkit})" ;;
    *)           check_warn "Toolkit not found in the log (older build or log rotated)" ;;
  esac

  # 3. Live JVM flags of a running PyCharm.
  jvm_args="$(ps -u "$REAL_USER" -o args= 2>/dev/null | grep -E 'JetBrains/Toolbox/apps/.*(PyCharm|pycharm)' | grep -m1 -- '-Xmx' || true)"
  expected_xmx="$(grep -m1 '^-Xmx' "${config_dir}/pycharm64.vmoptions" 2>/dev/null || true)"
  if [ -z "$jvm_args" ]; then
    check_warn "PyCharm is not running: JVM flags not checked (start it and re-run)"
  elif [ -n "$expected_xmx" ] && [[ "$jvm_args" == *"$expected_xmx"* ]]; then
    check_pass "Running JVM uses ${expected_xmx}"
  else
    check_warn "Running JVM flags differ from pycharm64.vmoptions (expected ${expected_xmx:-none})"
  fi

  # 4. Our files survived the first run.
  for f in options/editor-font.xml options/ui.lnf.xml options/laf.xml disabled_plugins.txt pycharm64.vmoptions; do
    [ -s "${config_dir}/${f}" ] && check_pass "Kept: ${f}" || check_warn "Missing or empty after first run: ${f}"
  done

  # 5. AI plugins must not be loaded.
  if grep -qE 'com\.intellij\.ml\.llm|org\.jetbrains\.junie' "$log_file" && grep -E 'com\.intellij\.ml\.llm|org\.jetbrains\.junie' "$log_file" | grep -qiE 'loaded|enabled|started'; then
    check_warn "idea.log mentions AI plugins as loaded: check Settings > Plugins > Installed"
  else
    check_pass "No AI plugin reported as loaded"
  fi

  # 6. Plugins present (at least the number we installed).
  local n
  n="$(find "$plugins_base" -mindepth 1 -maxdepth 2 -type d 2>/dev/null | wc -l)"
  [ "$n" -gt 0 ] && check_pass "Installed plugin directories found (${n})" || check_warn "No installed plugins found in ${plugins_base}"

  # 7. Tools the IDE integrates with.
  for f in uv ruff basedpyright shellcheck shfmt docker kubectl aws; do
    command -v "$f" >/dev/null 2>&1 || [ -x "${USER_BIN_DIR}/${f}" ] && check_pass "tool on PATH: ${f}" || check_warn "tool not on PATH: ${f}"
  done
  [ -z "${UV_PROJECT_ENVIRONMENT:-}" ] && check_pass "UV_PROJECT_ENVIRONMENT is not exported (avoids a 2026.2 uv bug)" || check_warn "UV_PROJECT_ENVIRONMENT is set: PyCharm 2026.2 cannot create uv environments with it"

  # 8. Data sharing: informational only (the file format is not documented).
  consent="${HOME_DIR}/.local/share/JetBrains/consentOptions/accepted"
  if [ -f "$consent" ]; then
    log_info "Consent file exists (${consent}). Verify in Settings > Appearance & Behavior > System Settings > Data Sharing that all boxes are OFF."
  else
    log_info "No consent file: the data-sharing dialog was not answered yet (release builds share nothing by default)."
  fi

  log_info "Result: ${VERIFY_PASS} passed, ${VERIFY_WARN} warnings, ${VERIFY_FAIL} failed"
  [ "$VERIFY_FAIL" -eq 0 ]
}

print_gui_checklist() {
  log_header "GUI-only settings (one time, about 3 minutes)"
  log_info "1. Settings > Python > Tools: enable Ruff; enable ONE type checker (basedpyright recommended)."
  log_info "   Per-project [tool.ruff]/[tool.basedpyright] in pyproject.toml are picked up automatically."
  log_info "2. Settings > Languages & Frameworks > Language Servers > + > New Language Server >"
  log_info "   template 'terraform-ls' (needs terraform-ls on PATH; free replacement for the Pro Terraform plugin)."
  log_info "3. Settings > Tools > Shell Script: set ShellCheck and shfmt paths (command -v shellcheck shfmt)."
  log_info "4. Settings > Appearance & Behavior > Appearance: confirm the dark theme was applied."
  log_info "5. AWS Toolkit: add a profile (aws configure / SSO) when you first use it."
  log_info "6. SQL: View > Tool Windows > DB Browser (Database Navigator) to add a PostgreSQL/SQLite connection."
  log_info "7. After the 30-day trial: Kubernetes, Terraform and the Pro Database tools turn off (Pro features)."
}

main() {
  verify_post_launch || log_warn "Some checks failed; see above"
  print_gui_checklist
}

main

exit 0

##################################################################################
# Notes
##################################################################################
#  - This stage is separate because these facts exist only after the IDE has run:
#    idea.log, the toolkit it picked, the live JVM arguments, the consent dialog.
#  - Log line "toolkit: sun.awt.wl.WLToolkit" / "XToolkit" is documented by JetBrains
#    (Wayland blog posts). The JVM flags are read from the process command line.
#
##################################################################################
# Useful Links
##################################################################################
# Wayland blog:        https://blog.jetbrains.com/platform/2026/02/wayland-by-default-in-2026-1-eap/
# LSP tools in PyCharm: https://www.jetbrains.com/help/pycharm/lsp-tools.html
# Data sharing:        https://www.jetbrains.com/help/idea/settings-usage-statistics.html
#
##################################################################################
# Troubleshooting/Debugging/Testing/Commands
##################################################################################
# Show the toolkit line:   grep -m1 toolkit: ~/.cache/JetBrains/PyCharm*/log/idea.log
# Live JVM flags:          ps -o args= -u "$USER" | grep -o -- '-Xmx[0-9a-z]*'
# Options rewritten?       diff <(cat ~/nb/nb_script_data/backups/pycharm/*/home/*/.config/JetBrains/*/options/laf.xml) ~/.config/JetBrains/PyCharm*/options/laf.xml
