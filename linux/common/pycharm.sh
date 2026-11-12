#!/usr/bin/env bash

##################################################################################
# Overview and Usage
##################################################################################
# pycharm.sh - STAGE 1: configure a Toolbox-installed PyCharm on Fedora, before
# its first launch. It does NOT install PyCharm (do that in the Toolbox window;
# Toolbox has no supported CLI for installing IDEs).
#
# Order of the whole procedure
#   1. jetbrains_toolbox.sh        install/configure Toolbox
#   2. Toolbox window              install "PyCharm" (do NOT open it yet)
#   3. pycharm.sh        (this)    config, VM options, plugins, companion tools
#   4. Open PyCharm once           accept/decline the data-sharing dialog
#   5. pycharm_post_launch.sh      verifies what only a running IDE can show
#
# What it configures (all derived from the detected hardware where relevant)
#   - Heap size (-Xmx) from total RAM; display toolkit (native Wayland vs XWayland)
#     from the GPU tier / CPU class; crash/heap dumps redirected to a private dir.
#   - Disables JetBrains AI (AI Assistant, Junie), Code With Me and, on low-RAM
#     machines, some heavy bundled plugins.
#   - Installs recommended plugins headlessly (`pycharm installPlugins`).
#   - Writes IDE options: dark theme, JetBrains Mono Nerd Font in the editor,
#     Noto Sans UI font, no start-up tips, newline at end of file.
#   - Installs companion tools used by the IDE (ShellCheck, shfmt, ruff,
#     basedpyright, cfn-lint, checkov, sqlfluff, OpenTofu/tflint where available).
#   - Integrations: `pycharm` command in ~/.local/bin, BleachBit and OpenSnitch.
#
# Sample calls (assuming the caller uses the same variable names)
#   (a) all options:
#       bash "$COMMON_DIR/pycharm.sh" --real-user "$REAL_USER" \
#            --filename-timestamp "$FILENAME_TIMESTAMP" --toolkit auto --heap-mb 3072 \
#            --wait-minutes 30 --ntfy-topic "$NTFY_TOPIC"
#   (b) mandatory only (nothing is mandatory; every option has a default):
#       bash "$COMMON_DIR/pycharm.sh"
#   (c) verification only:
#       bash "$COMMON_DIR/pycharm.sh" --verify-setup
#
# IMPORTANT: PyCharm must not be running. Re-running wipes the PyCharm config
# directory of the detected version (useful files are backed up first). Caches
# (~/.cache/JetBrains) are kept to avoid re-indexing.
#
# Licensing reality (2026): Community Edition no longer exists. Toolbox installs the
# unified "PyCharm": a free core tier plus a 30-day Pro trial. Kubernetes,
# Terraform and the built-in Database/SQL tools are Pro features: they work during
# the trial, then switch off. See Notes for the free-tier alternatives configured
# here (LSP4IJ for Terraform, AWS Toolkit for CloudFormation, Database Navigator
# for SQL).
##################################################################################

set -Eeuo pipefail

ORIGINAL_ARGS=("$@")

##################################################################################
# User defined variables
##################################################################################
TOOLKIT_MODE="${TOOLKIT_MODE:-auto}"     # auto | wayland | x11
HEAP_MB_OVERRIDE="${HEAP_MB_OVERRIDE:-}" # empty = computed from RAM
VERIFY_ONLY=false
WAIT_MINUTES="${WAIT_MINUTES:-30}"       # how long to wait for you to install PyCharm in Toolbox (0 = do not wait)
NTFY_TOPIC="${NTFY_TOPIC:-}"             # optional push notification at the end (sent with ntfy_send from helper_ntfy.sh)

# Fonts: first installed family wins (checked with fontconfig via helper_fonts.sh).
EDITOR_FONT_CANDIDATES=("JetBrainsMono Nerd Font Mono" "JetBrainsMono Nerd Font" "JetBrainsMono NF" "JetBrains Mono")
UI_FONT_CANDIDATES=("Noto Sans" "Noto Sans Display")
EDITOR_FONT_SIZE=14
UI_FONT_SIZE=13

# Python used for `uv tool install` of CLI tools. Fedora 45 ships Python 3.15, which
# many tool dependencies do not support yet; pin a mature version (uv fetches it).
UV_TOOL_PYTHON="${UV_TOOL_PYTHON:-3.15}"

# Plugins to install: "plugin.xml id|Display name|description".
# Every id is checked against the JetBrains Marketplace before installing; if the id
# is unknown, the plugin is looked up by its display name instead. Anything still
# unresolved is reported at the end and skipped (never fatal).
PLUGINS_CORE=(
  "com.redhat.devtools.lsp4ij|LSP4IJ|Language Server client (terraform-ls etc.; works in the free tier)"
  "aws.toolkit|AWS Toolkit|CloudFormation language server (cfn-lint + Guard), SAM, explorer"
  "DBN|Database Navigator|SQL editor + database browser (PostgreSQL, SQLite, any JDBC); free replacement for the Pro-only Database tools"
  "ru.adelf.idea.dotenv|.env files support|.env file support"
  "mobi.hsz.idea.gitignore|.ignore|.gitignore/.dockerignore support"
  "net.seesharpsoft.intellij.plugins.csv|CSV Editor|CSV/TSV editor"
  "com.koxudaxi.pydantic|Pydantic|FastAPI/pydantic models"
  "name.kropp.intellij.makefile|Makefile Language|Makefile support"
  "Key Promoter X|Key Promoter X|Shows the keyboard shortcut for actions you click"
)
# Installed only when RAM is not low (each costs memory/indexing time).
PLUGINS_HEAVY=(
  "zielu.gittoolbox|GitToolBox|Inline blame, branch status"
  "com.intellij.mermaid|Mermaid|Mermaid diagrams in Markdown"
)
# Optional and good, but NOT installed. Uncomment to install.
PLUGINS_OPTIONAL=(
  # "IdeaVIM|IdeaVim|Vim emulation (you use the default keymap, so off)"
  # "org.sonarlint.idea|SonarQube for IDE|Local static analysis"
  # "com.github.lppedd.idea-conventional-commit|Conventional Commit|Conventional commit helper"
  # "izhangzhihao.rainbow.brackets|Rainbow Brackets|Colored bracket pairs"
  # "com.nasller.CodeGlancePro|CodeGlance Pro|Minimap"
  # "String Manipulation|String Manipulation|Case conversion, sorting, encoding helpers"
)

# Disabled for privacy/performance. Ids that are not bundled are skipped.
DISABLED_PLUGINS_ALWAYS=(
  "com.intellij.ml.llm"          # JetBrains AI Assistant
  "org.jetbrains.junie"          # Junie agent
  "com.intellij.junie"           # alternative Junie id seen in other sources (skipped if not bundled)
  "com.jetbrains.codeWithMe"     # Code With Me (remote pairing)
)
# Only on low-RAM machines (bundled but not part of your stack).
DISABLED_PLUGINS_LOW_RAM=(
  "intellij.jupyter"             # Jupyter notebooks
)
# Ids matching this regex are reported (not disabled) so you can review new AI plugins.
AI_PLUGIN_REPORT_REGEX='llm|junie|codeWithMe|copilot|agent'

# Companion tools. dnf names that do not exist in Fedora are skipped and reported.
DNF_TOOLS=(ShellCheck shfmt yamllint opentofu tflint terraform terraform-ls)
UV_TOOLS=(ruff basedpyright cfn-lint checkov sqlfluff)
# UV_TOOLS_OPTIONAL: ty (Astral, beta), pyrefly (Meta, fast), mypy.

##################################################################################
# Named Options processing
##################################################################################
print_usage() {
  cat <<'USAGE'
Usage: pycharm.sh [options]
  --real-user NAME            user to configure (default: sudo caller or current user)
  --filename-timestamp TS     shared timestamp for backup/download/log dirs
  --toolkit auto|wayland|x11  display toolkit (default: auto, decided by hardware)
  --heap-mb N                 maximum heap in MB (default: computed from RAM)
  --wait-minutes N            wait up to N minutes for PyCharm to be installed in Toolbox (default: 30)
  --ntfy-topic TOPIC          send a push notification via ntfy when done (default: off)
  --verify-setup              only run the verification section
  -h, --help                  show this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --real-user)             REAL_USER="${2:?--real-user needs a value}"; shift 2 ;;
    --real-user=*)           REAL_USER="${1#*=}"; shift ;;
    --filename-timestamp)    FILENAME_TIMESTAMP="${2:?--filename-timestamp needs a value}"; shift 2 ;;
    --filename-timestamp=*)  FILENAME_TIMESTAMP="${1#*=}"; shift ;;
    --toolkit)               TOOLKIT_MODE="${2:?--toolkit needs a value}"; shift 2 ;;
    --toolkit=*)             TOOLKIT_MODE="${1#*=}"; shift ;;
    --heap-mb)               HEAP_MB_OVERRIDE="${2:?--heap-mb needs a value}"; shift 2 ;;
    --heap-mb=*)             HEAP_MB_OVERRIDE="${1#*=}"; shift ;;
    --wait-minutes)          WAIT_MINUTES="${2:?--wait-minutes needs a value}"; shift 2 ;;
    --wait-minutes=*)        WAIT_MINUTES="${1#*=}"; shift ;;
    --ntfy-topic)            NTFY_TOPIC="${2:?--ntfy-topic needs a value}"; shift 2 ;;
    --ntfy-topic=*)          NTFY_TOPIC="${1#*=}"; shift ;;
    --verify-setup)          VERIFY_ONLY=true; shift ;;
    -h|--help)               print_usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; print_usage >&2; exit 2 ;;
  esac
done

case "$WAIT_MINUTES" in ''|*[!0-9]*) echo "--wait-minutes must be a number" >&2; exit 2 ;; esac
case "$TOOLKIT_MODE" in auto|wayland|x11) ;; *) echo "--toolkit must be auto, wayland or x11" >&2; exit 2 ;; esac
case "$HEAP_MB_OVERRIDE" in ''|*[!0-9]*) [ -z "$HEAP_MB_OVERRIDE" ] || { echo "--heap-mb must be a number" >&2; exit 2; } ;; esac

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
SECURITY_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/security"
FEDORA_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/fedora"
SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"
SCRIPT_DATA_LOGS="${SCRIPT_DATA}/logs"

PYCHARM_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/pycharm"
PYCHARM_CURRENT_BACKUP_DIR="${PYCHARM_BACKUP_DIR_BASE}/pycharm_${FILENAME_TIMESTAMP}"
PYCHARM_LOG_DIR_BASE="${SCRIPT_DATA_LOGS}/pycharm"
PYCHARM_CURRENT_LOG_DIR="${PYCHARM_LOG_DIR_BASE}/pycharm_${FILENAME_TIMESTAMP}"

TOOLBOX_DIR="${HOME_DIR}/.local/share/JetBrains/Toolbox"
TOOLBOX_APPS_DIR="${TOOLBOX_DIR}/apps"
USER_BIN_DIR="${HOME_DIR}/.local/bin"
CRASH_DUMP_DIR="${HOME_DIR}/.cache/JetBrains/crash-dumps"

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
LOG_FILE="${PYCHARM_CURRENT_LOG_DIR}/pycharm.log"

run_getter() { if [ -r "${GETTER_DIR}/$1.sh" ]; then sh "${GETTER_DIR}/$1.sh" "${@:2}" 2>/dev/null || echo "${RUN_GETTER_DEFAULT:-unknown}"; else echo "${RUN_GETTER_DEFAULT:-unknown}"; fi; }
RAM_MB="$(RUN_GETTER_DEFAULT=4096 run_getter get_ram_size)"
RAM_PROFILE="$(run_getter get_ram_profile)"
CPU_CORES="$(RUN_GETTER_DEFAULT=2 run_getter get_cpu_cores)"
GPU_TIER="$(run_getter get_gpu_tier)"
CPU_IS_ULV="$(run_getter get_cpu_is_ulv)"
SSD_PRESENT="$(run_getter get_ssd_present)"

##################################################################################
# Helpers
##################################################################################
for helper in helper_logging helper_run_as_user helper_dnf helper_backup helper_version_compare \
              helper_fonts helper_script_logging helper_opensnitch helper_bleachbit helper_jetbrains helper_ntfy; do
  if [ ! -r "${HELPER_DIR}/${helper}.sh" ]; then
    echo "ERROR: missing helper ${HELPER_DIR}/${helper}.sh" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  . "${HELPER_DIR}/${helper}.sh"
done

ensure_real_user "${ORIGINAL_ARGS[@]}"
export REAL_USER FILENAME_TIMESTAMP
start_script_logging "$LOG_FILE" "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"

# Locate the newest PyCharm installed by Toolbox and derive every IDE path from
# product-info.json (dataDirectoryName is e.g. "PyCharm2026.2").
locate_pycharm() {
  IDE_DIR="$(jetbrains_find_install "$TOOLBOX_APPS_DIR" PyCharm)" || return 1
  IDE_DATA_NAME="$(jetbrains_product_info "$IDE_DIR" '.dataDirectoryName')"
  IDE_VERSION="$(jetbrains_product_info "$IDE_DIR" '.version')"
  IDE_LAUNCHER="$(jetbrains_launcher "$IDE_DIR")" || return 1
  CONFIG_DIR="${HOME_DIR}/.config/JetBrains/${IDE_DATA_NAME}"
  PLUGINS_BASE="${HOME_DIR}/.local/share/JetBrains/${IDE_DATA_NAME}"
  SYSTEM_DIR="${HOME_DIR}/.cache/JetBrains/${IDE_DATA_NAME}"
  VMOPTIONS_FILE="${CONFIG_DIR}/pycharm64.vmoptions"
  OPTIONS_DIR="${CONFIG_DIR}/options"
}

# Is a plugin id bundled with this IDE? (product-info.json lists bundled ids; the
# grep also works if the file layout changes.)
is_bundled_plugin() { grep -q "\"$1\"" "${IDE_DIR}/product-info.json" 2>/dev/null; }

# Number of plugin directories (supports both the flat and the plugins/ layout).
count_plugin_dirs() {
  local n=0 d
  for d in "$PLUGINS_BASE" "$PLUGINS_BASE/plugins"; do
    [ -d "$d" ] && n=$((n + $(find "$d" -mindepth 1 -maxdepth 1 | wc -l)))
  done
  echo "$n"
}

##################################################################################
# Backup
##################################################################################
backup_existing_config() {
  log_header "Backup of existing PyCharm configuration"
  umask 077
  mkdir -p "$PYCHARM_CURRENT_BACKUP_DIR"
  local item
  # Only the useful, hand-made parts (not caches, not the IDE itself).
  for item in options keymaps codestyles colors templates fileTemplates inspection \
              pycharm64.vmoptions disabled_plugins.txt; do
    if [ -e "${CONFIG_DIR}/${item}" ]; then
      backup_path_parents "${CONFIG_DIR}/${item}" "$PYCHARM_CURRENT_BACKUP_DIR"
    fi
  done
  if [ -d "$PLUGINS_BASE" ]; then
    backup_record "$PYCHARM_CURRENT_BACKUP_DIR" installed_plugins ls -1 "$PLUGINS_BASE"
  fi
  [ -e "${HOME_DIR}/.config/JetBrains/CodeWithMe/config.json" ] && backup_path_parents "${HOME_DIR}/.config/JetBrains/CodeWithMe/config.json" "$PYCHARM_CURRENT_BACKUP_DIR"
  [ -L "${USER_BIN_DIR}/pycharm" ] && backup_path_parents "${USER_BIN_DIR}/pycharm" "$PYCHARM_CURRENT_BACKUP_DIR"
  umask 022
  log_success "Backup written to ${PYCHARM_CURRENT_BACKUP_DIR}"
}

##################################################################################
# Reset
##################################################################################
reset_config() {
  log_header "Reset PyCharm configuration"
  rm -rf "$CONFIG_DIR" "$PLUGINS_BASE"
  mkdir -p "$OPTIONS_DIR"
  log_success "Fresh config directory: ${CONFIG_DIR}"
}

##################################################################################
# Security
##################################################################################
# - Heap/crash dumps can contain passwords and tokens (process memory). They stay
#   enabled for diagnosing out-of-memory problems, but go to a private 0700 dir.
# - OpenSnitch: deny JetBrains AI endpoints for every process (only if installed).
setup_security() {
  log_header "Security"
  install -d -m 0700 "$CRASH_DUMP_DIR"
  log_success "Private crash/heap dump directory: ${CRASH_DUMP_DIR}"

  # Code With Me host switch (documented XDG location); defense in depth on top of
  # the plugin being disabled.
  install -d -m 0755 "${HOME_DIR}/.config/JetBrains/CodeWithMe"
  printf '{ "isCodeWithMeHostEnabled" : "false" }\n' >"${HOME_DIR}/.config/JetBrains/CodeWithMe/config.json"

  if opensnitch_is_present; then
    opensnitch_write_rule "jetbrains-ai-deny" deny true \
      "JetBrains AI Assistant / Grazie endpoints (AI is disabled on purpose)" \
      "" '^(api\.jetbrains\.ai|api\.ai\.jetbrains\.com\.cn|api\.app\.prod\.grazie\.aws\.intellij\.net)$'
    log_success "OpenSnitch AI-deny rule written"
  else
    log_info "OpenSnitch not installed: no egress rules"
  fi
}

##################################################################################
# main setup
##################################################################################
has_display() { [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; }

# If PyCharm is not installed yet, start Toolbox and poll until the install shows
# up (installing needs a click in the Toolbox window; there is no supported CLI).
# Idea taken from another script's "poll until installed" loop.
wait_for_pycharm() {
  locate_pycharm && return 0
  [ "$WAIT_MINUTES" -gt 0 ] || return 1
  has_display || return 1
  [ -x "$TOOLBOX_BIN" ] || return 1

  log_warn "PyCharm is not installed yet."
  log_info "In the Toolbox window click 'Install' next to PyCharm. Do NOT open PyCharm afterwards."
  pgrep -u "$REAL_USER" -f 'JetBrains/Toolbox/bin/jetbrains-toolbox' >/dev/null 2>&1 \
    || setsid -f "$TOOLBOX_BIN" >/dev/null 2>&1 </dev/null
  local waited=0 limit=$((WAIT_MINUTES * 60))
  while [ "$waited" -lt "$limit" ]; do
    if locate_pycharm; then
      # Toolbox may still be finalizing files right after the install appears.
      sleep 10
      locate_pycharm && return 0
    fi
    sleep 10
    waited=$((waited + 10))
    [ $((waited % 60)) -eq 0 ] && log_info "...still waiting for the PyCharm install (${waited}s of ${limit}s)"
  done
  return 1
}

preflight() {
  log_header "Preflight"
  require_fedora
  if [ "$(id -u)" -eq 0 ]; then log_die "Run as a normal user"; fi
  command -v jq >/dev/null 2>&1 || log_die "jq missing: run jetbrains_toolbox.sh first"
  wait_for_pycharm || log_die "No PyCharm found under ${TOOLBOX_APPS_DIR}. Install 'PyCharm' from the Toolbox window, then re-run."
  if pgrep -u "$REAL_USER" -f 'JetBrains/Toolbox/apps/.*[Pp]y[Cc]harm' >/dev/null 2>&1; then
    log_die "PyCharm is running. Close it completely and re-run."
  fi
  log_info "PyCharm ${IDE_VERSION} at ${IDE_DIR}"
  log_info "Hardware: RAM ${RAM_MB} MB (${RAM_PROFILE}), ${CPU_CORES} cores, GPU tier ${GPU_TIER}, ULV CPU ${CPU_IS_ULV}, SSD ${SSD_PRESENT}"
  sudo -v
}

# Heap = RAM/4 clamped to 1536..4096 MB (1024 below ~4.5 GB), rounded to 256.
# More heap rarely helps an IDE; it just delays garbage collection and steals
# page cache that indexing needs.
compute_heap_mb() {
  if [ -n "$HEAP_MB_OVERRIDE" ]; then HEAP_MB="$HEAP_MB_OVERRIDE"; return; fi
  local mb="$RAM_MB"
  case "$mb" in ''|*[!0-9]*) mb=4096 ;; esac
  if [ "$mb" -lt 4500 ]; then
    HEAP_MB=1024
  else
    HEAP_MB=$(( mb / 4 / 256 * 256 ))
    [ "$HEAP_MB" -lt 1536 ] && HEAP_MB=1536
    [ "$HEAP_MB" -gt 4096 ] && HEAP_MB=4096
  fi
}

# Display toolkit. JetBrains enables native Wayland by default since 2026.1, but
# its own knowledge base documents that the native pipeline currently renders on
# the CPU (software) and scrolls poorly on weak integrated graphics; the Vulkan
# pipeline is still in progress (JBR-7558). So weak hardware gets XWayland.
decide_toolkit() {
  case "$TOOLKIT_MODE" in
    wayland) TOOLKIT_RESULT="wayland" ;;
    x11)     TOOLKIT_RESULT="x11" ;;
    auto)
      if [ "$GPU_TIER" = "low" ] || [ "$CPU_IS_ULV" = "true" ]; then
        TOOLKIT_RESULT="x11"
      else
        TOOLKIT_RESULT="default"   # IDE decides: native Wayland on Wayland, X11 otherwise
      fi ;;
  esac
}

# Marketplace lookups (idea from another script: do not trust remembered plugin ids).
#  1. Documented endpoint https://plugins.jetbrains.com/plugins/list?pluginId=<xmlId>
#     answers with XML that contains an <idea-plugin> element when the id exists.
#  2. Fallback: /api/searchPlugins?search=<name> (JSON {plugins:[{name,xmlId}]}), exact
#     name match only, so a wrong plugin is never installed by accident.
# Prints the id to install; returns 1 when nothing could be resolved. When the
# Marketplace cannot be reached at all, the id is used unchanged (installPlugins
# then reports the real problem).
marketplace_resolve_id() {
  local id="$1" name="$2" body found
  body="$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 20 \
          "https://plugins.jetbrains.com/plugins/list?pluginId=$(printf '%s' "$id" | jq -sRr @uri)" 2>/dev/null)" || { printf '%s\n' "$id"; return 0; }
  if printf '%s' "$body" | grep -q '<idea-plugin'; then
    printf '%s\n' "$id"; return 0
  fi
  found="$(curl -fsSL --proto '=https' --tlsv1.2 --max-time 20 \
          "https://plugins.jetbrains.com/api/searchPlugins?search=$(printf '%s' "$name" | jq -sRr @uri)&max=10" 2>/dev/null \
          | jq -r --arg n "$name" '[.plugins[]? | select((.name // "") | ascii_downcase == ($n | ascii_downcase))][0].xmlId // empty' 2>/dev/null)" || true
  [ -n "$found" ] || return 1
  printf '%s\n' "$found"
}

# Plugins are installed on the clean config directory, BEFORE our files are
# written, because the IDE may rewrite option files while running headless.
install_plugins() {
  log_header "Plugins"
  local entries=("${PLUGINS_CORE[@]}") entry id desc before after failed=()
  if [ "$RAM_PROFILE" != "low" ]; then entries+=("${PLUGINS_HEAVY[@]}"); else log_info "Low RAM: skipping heavy plugins"; fi
  entries+=("${PLUGINS_OPTIONAL[@]}")

  for entry in "${entries[@]}"; do
    id="${entry%%|*}"; desc="${entry#*|}"
    before="$(count_plugin_dirs)"
    log_info "Installing ${id} (${desc})"
    # Headless command; the IDE must be closed. Time-boxed, no stdin.
    timeout 300 "$IDE_LAUNCHER" installPlugins "$id" </dev/null || log_warn "installPlugins exited non-zero for ${id}"
    after="$(count_plugin_dirs)"
    if [ "$after" -gt "$before" ]; then
      log_success "Installed ${id}"
    else
      log_warn "No new plugin directory after ${id}: wrong id, incompatible with ${IDE_VERSION}, or already bundled"
      failed+=("$id")
    fi
  done
  [ "${#failed[@]}" -gt 0 ] && log_warn "Plugins to check manually: ${failed[*]}"
  return 0
}

write_vmoptions() {
  log_header "VM options"
  compute_heap_mb
  decide_toolkit
  local toolkit_line toolkit_note
  case "$TOOLKIT_RESULT" in
    x11)     toolkit_line="-Dawt.toolkit.name=XToolkit";  toolkit_note="XWayland/X11 toolkit (weak GPU/ULV CPU, or forced)" ;;
    wayland) toolkit_line="-Dawt.toolkit.name=WLToolkit"; toolkit_note="native Wayland toolkit (forced)" ;;
    *)       toolkit_line="# (none: JetBrains default = native Wayland on Wayland sessions)"; toolkit_note="JetBrains default" ;;
  esac

  cat >"$VMOPTIONS_FILE" <<EOF
# Custom VM options for ${IDE_DATA_NAME}, written by pycharm.sh on $(date +%F).
# This file is APPENDED to the IDE's bundled defaults, so later lines win.
# Edit via Help > Edit Custom VM Options. Re-running pycharm.sh regenerates it.
# Detected hardware: RAM ${RAM_MB} MB, ${CPU_CORES} cores, GPU tier ${GPU_TIER}, ULV CPU ${CPU_IS_ULV}, SSD ${SSD_PRESENT}.

# Maximum heap: RAM/4 clamped to 1536-4096 MB (1024 on very small machines).
-Xmx${HEAP_MB}m

# Display toolkit: ${toolkit_note}
${toolkit_line}

# GPU rendering on native Wayland (Vulkan) is beta and has lag reports. Try only
# on a mid/high GPU with Vulkan drivers, together with the native toolkit:
# -Dsun.java2d.vulkan=true

# Toolbox manages updates; the IDE's own updater stays off.
-Dide.no.platform.update=true

# Crash and heap dumps can contain secrets: keep them in a private directory.
-XX:ErrorFile=${CRASH_DUMP_DIR}/java_error_in_pycharm_%p.log
-XX:HeapDumpPath=${CRASH_DUMP_DIR}
EOF
  chmod 0644 "$VMOPTIONS_FILE"
  log_success "Xmx=${HEAP_MB}m, toolkit: ${toolkit_note}"
}

write_disabled_plugins() {
  log_header "Disabled plugins"
  local ids=("${DISABLED_PLUGINS_ALWAYS[@]}") id out=() cand
  [ "$RAM_PROFILE" = "low" ] && ids+=("${DISABLED_PLUGINS_LOW_RAM[@]}")
  for id in "${ids[@]}"; do
    if is_bundled_plugin "$id"; then out+=("$id"); else log_info "Not bundled in this build, skipped: ${id}"; fi
  done
  # One id per line is the documented format of disabled_plugins.txt.
  if [ "${#out[@]}" -gt 0 ]; then printf '%s\n' "${out[@]}" >"${CONFIG_DIR}/disabled_plugins.txt"; else : >"${CONFIG_DIR}/disabled_plugins.txt"; fi
  log_success "disabled_plugins.txt: ${out[*]:-none}"

  # Review aid: bundled ids that look AI/agent related but are NOT disabled.
  grep -oE "\"[A-Za-z0-9_.-]*(${AI_PLUGIN_REPORT_REGEX})[A-Za-z0-9_.-]*\"" "${IDE_DIR}/product-info.json" 2>/dev/null | tr -d '"' | sort -u | while read -r cand; do
    printf '%s\n' "${out[@]:-}" | grep -qx "$cand" || log_info "Review (AI/agent related, not disabled): ${cand}"
  done
}

write_options() {
  log_header "IDE options"
  local editor_font ui_font
  editor_font="$(first_installed_font "${EDITOR_FONT_CANDIDATES[@]}" || true)"
  ui_font="$(first_installed_font "${UI_FONT_CANDIDATES[@]}" || true)"
  [ -n "$editor_font" ] || { editor_font="JetBrains Mono"; log_warn "No JetBrains Mono family found; run the Nerd Fonts setup"; }
  [ -n "$ui_font" ] || { ui_font="Noto Sans"; log_warn "Noto Sans not found in fontconfig"; }

  cat >"${OPTIONS_DIR}/editor-font.xml" <<EOF
<application>
  <component name="DefaultFont">
    <option name="FONT_FAMILY" value="${editor_font}" />
    <option name="FONT_SIZE" value="${EDITOR_FONT_SIZE}" />
    <option name="FONT_SIZE_2D" value="${EDITOR_FONT_SIZE}.0" />
    <option name="USE_LIGATURES" value="true" />
  </component>
</application>
EOF
  cat >"${OPTIONS_DIR}/ui.lnf.xml" <<EOF
<application>
  <component name="UISettings">
    <option name="OVERRIDE_NONIDEA_LAF_FONTS" value="true" />
    <option name="FONT_FACE" value="${ui_font}" />
    <option name="FONT_SIZE" value="${UI_FONT_SIZE}" />
    <option name="FONT_SIZE_2D" value="${UI_FONT_SIZE}.0" />
  </component>
</application>
EOF
  # Dark theme. BEST EFFORT: the theme id for "Dark" changed with the New UI and
  # the Islands theme; an unknown id falls back silently to the default. Check
  # Settings > Appearance & Behavior > Appearance once.
  cat >"${OPTIONS_DIR}/laf.xml" <<'EOF'
<application>
  <component name="LafManager" autodetect="false">
    <laf themeId="ExperimentalDark" />
  </component>
</application>
EOF
  cat >"${OPTIONS_DIR}/ide.general.xml" <<'EOF'
<application>
  <component name="GeneralSettings">
    <option name="showTipsOnStartup" value="false" />
  </component>
</application>
EOF
  cat >"${OPTIONS_DIR}/editor.xml" <<'EOF'
<application>
  <component name="EditorSettings">
    <option name="ENSURE_NEWLINE_AT_EOF" value="true" />
  </component>
</application>
EOF
  chmod 0644 "${OPTIONS_DIR}"/*.xml
  log_success "Options written (editor font: ${editor_font}, UI font: ${ui_font})"
}

install_companion_tools() {
  log_header "Companion tools"
  local pkg uv_bin tool
  sudo dnf install -y --skip-unavailable "${DNF_TOOLS[@]}" || log_warn "dnf reported problems"
  for pkg in "${DNF_TOOLS[@]}"; do
    if rpm_is_installed "$pkg"; then
      log_success "dnf: ${pkg}"
    else
      case "$pkg" in
        terraform)    log_warn "terraform: not in Fedora repos (HashiCorp licence). Use OpenTofu, or add the HashiCorp repo: https://developer.hashicorp.com/terraform/install" ;;
        tflint)       log_warn "tflint: not in Fedora repos. Release binary: https://github.com/terraform-linters/tflint/releases" ;;
        terraform-ls) log_warn "terraform-ls: not in Fedora repos. Release binary: https://releases.hashicorp.com/terraform-ls/" ;;
        opentofu)     log_warn "opentofu: not in Fedora repos. See https://opentofu.org/docs/intro/install/rpm/" ;;
        *)            log_warn "${pkg}: not available via dnf" ;;
      esac
    fi
  done

  uv_bin="$(command -v uv || true)"
  [ -n "$uv_bin" ] || { [ -x "${USER_BIN_DIR}/uv" ] && uv_bin="${USER_BIN_DIR}/uv"; }
  if [ -z "$uv_bin" ]; then
    log_warn "uv not found: run the Python setup (part 1) and re-run this script to install: ${UV_TOOLS[*]}"
    return 0
  fi
  for tool in "${UV_TOOLS[@]}"; do
    # --force reinstalls from scratch (clean-start rule); --python pins a mature interpreter.
    if "$uv_bin" tool install --force --python "$UV_TOOL_PYTHON" "$tool"; then
      log_success "uv tool: ${tool}"
    else
      log_warn "uv tool install failed: ${tool}"
    fi
  done
}

setup_launcher_link() {
  log_header "Terminal command"
  local script
  script="$(find "${TOOLBOX_DIR}/scripts" -maxdepth 1 -name 'pycharm*' -print -quit 2>/dev/null || true)"
  mkdir -p "$USER_BIN_DIR"
  if [ -n "$script" ]; then
    # Toolbox's own script keeps working after IDE updates; the versioned bin/ path would not.
    ln -sfn "$script" "${USER_BIN_DIR}/pycharm"
    log_success "pycharm -> ${script}"
  else
    log_warn "No Toolbox launcher script yet (Toolbox generates it after install). Check Toolbox > PyCharm > Settings > Shell script name."
  fi
}

main_setup() {
  preflight
  backup_existing_config
  reset_config
  install_plugins
  write_vmoptions
  write_disabled_plugins
  write_options
  setup_security
  install_companion_tools
  setup_launcher_link
}

##################################################################################
# Verification
##################################################################################
VERIFY_PASS=0; VERIFY_WARN=0; VERIFY_FAIL=0
check_pass() { VERIFY_PASS=$((VERIFY_PASS + 1)); log_success "$*"; }
check_warn() { VERIFY_WARN=$((VERIFY_WARN + 1)); log_warn "$*"; }
check_fail() { VERIFY_FAIL=$((VERIFY_FAIL + 1)); log_error "$*"; }

verify_setup() {
  log_header "Verification"
  local f t dir
  locate_pycharm || { check_fail "PyCharm not found under ${TOOLBOX_APPS_DIR}"; return 1; }
  check_pass "PyCharm ${IDE_VERSION} (${IDE_DATA_NAME})"

  [ -f "$VMOPTIONS_FILE" ] && grep -q '^-Xmx' "$VMOPTIONS_FILE" && check_pass "VM options: $(grep '^-Xmx' "$VMOPTIONS_FILE")" || check_fail "VM options missing: ${VMOPTIONS_FILE}"
  [ -f "${CONFIG_DIR}/disabled_plugins.txt" ] && check_pass "disabled_plugins.txt: $(tr '\n' ' ' <"${CONFIG_DIR}/disabled_plugins.txt")" || check_fail "disabled_plugins.txt missing"
  for f in editor-font ui.lnf laf ide.general editor; do
    if [ ! -f "${OPTIONS_DIR}/${f}.xml" ]; then
      check_fail "options/${f}.xml missing"
    elif ! command -v xmllint >/dev/null 2>&1; then
      check_pass "options/${f}.xml present (xmllint not installed: not validated)"
    elif xmllint --noout "${OPTIONS_DIR}/${f}.xml" 2>/dev/null; then
      check_pass "options/${f}.xml is valid XML"
    else
      check_fail "options/${f}.xml is not valid XML"
    fi
  done
  [ "$(count_plugin_dirs)" -gt 0 ] && check_pass "Plugin directories installed: $(count_plugin_dirs)" || check_warn "No plugins installed"
  [ -d "$CRASH_DUMP_DIR" ] && [ "$(stat -c %a "$CRASH_DUMP_DIR")" = "700" ] && check_pass "Crash dump dir is private (0700)" || check_warn "Crash dump dir missing or not 0700"
  [ -L "${USER_BIN_DIR}/pycharm" ] && check_pass "pycharm command available" || check_warn "pycharm command link missing"
  ls "${HOME_DIR}/.local/share/applications"/jetbrains-pycharm*.desktop >/dev/null 2>&1 && check_pass "Application launcher present" || check_warn "No jetbrains-pycharm*.desktop launcher (Toolbox creates it)"

  for t in shellcheck shfmt yamllint tofu terraform tflint terraform-ls; do
    command -v "$t" >/dev/null 2>&1 && check_pass "tool: ${t}" || check_warn "tool missing: ${t}"
  done
  for t in ruff basedpyright cfn-lint checkov sqlfluff; do
    command -v "$t" >/dev/null 2>&1 || [ -x "${USER_BIN_DIR}/${t}" ] && check_pass "tool: ${t}" || check_warn "tool missing: ${t}"
  done
  if dir="$(bleachbit_cleaner_dir)"; then [ -f "${dir}/jetbrains.xml" ] && check_pass "BleachBit cleaner present" || check_warn "BleachBit cleaner missing (run jetbrains_toolbox.sh)"; fi
  if opensnitch_is_present; then [ -f "$(opensnitch_rules_dir)/jetbrains-ai-deny.json" ] && check_pass "OpenSnitch AI-deny rule present" || check_warn "OpenSnitch AI-deny rule missing"; fi
  log_info "Result: ${VERIFY_PASS} passed, ${VERIFY_WARN} warnings, ${VERIFY_FAIL} failed"
  [ "$VERIFY_FAIL" -eq 0 ]
}

print_next_steps() {
  log_header "Next steps"
  log_info "1. Open PyCharm once (Toolbox or 'pycharm'). Decline 'Data Sharing' (applies to all JetBrains IDEs)."
  log_info "2. A 30-day Pro trial starts automatically; afterwards the free core tier remains."
  log_info "3. Run: bash \"${COMMON_DIR}/pycharm_post_launch.sh\" to verify what only a running IDE shows"
  log_info "   and to get the short list of GUI-only settings (type checker, terraform-ls, ShellCheck)."
}

main() {
  if [ "$VERIFY_ONLY" = true ]; then verify_setup; return; fi
  main_setup
  if verify_setup; then
    ntfy_send "PyCharm configured" "pycharm.sh finished on $(hostname): ${VERIFY_PASS} ok, ${VERIFY_WARN} warnings" default white_check_mark || true
  else
    log_warn "Verification reported failures; see above"
    ntfy_send "PyCharm setup: failures" "pycharm.sh on $(hostname): ${VERIFY_FAIL} failed checks" high warning || true
  fi
  print_next_steps
}

main

exit 0

##################################################################################
# Notes
##################################################################################
# Design decisions
#  - Two stages. Nothing requires an initial IDE launch: the config, plugin and
#    cache directories can be created beforehand, and `installPlugins` is a
#    headless command. Only the data-sharing dialog and log-based checks need a
#    running IDE, so those live in pycharm_post_launch.sh.
#  - Plugin order: plugins first (clean config), our files second, because a
#    headless IDE start may rewrite option files.
#  - Free tier. PyCharm Community 2025.2 was the last standalone release; since
#    2025.3 there is one product. Free core keeps Python, Jupyter, Docker/Compose
#    (limited), Git, HTML/XML/JSON/YAML/Markdown, the LSP API and (2026.1+) basic
#    JS/TS/CSS. Pro-only: Kubernetes, Terraform, Database/SQL, remote
#    interpreters, framework tooling, full Jupyter.
#  - Free-tier replacements configured or recommended here:
#      Terraform/OpenTofu : LSP4IJ + terraform-ls (LSP4IJ ships a "terraform-ls"
#                           user-defined server template; add it in the GUI once)
#      CloudFormation     : AWS Toolkit (CloudFormation language server, cfn-lint)
#      Kubernetes/YAML    : built-in YAML + JSON schemas; kubectl/helm from the shell
#      SQL                : Database Navigator (plugin id DBN): free for personal and
#                           commercial use, runs in free-tier PyCharm, supports
#                           PostgreSQL, SQLite and any JDBC driver. Not as polished
#                           as the Pro Database tools, and its compatibility with the
#                           newest IDE builds can lag (check the install report).
#                           Other options: DataGrip (free for NON-commercial use only,
#                           with mandatory non-configurable data sharing, a privacy
#                           trade-off), DBeaver (FOSS) or psql.
#      Python tooling     : built-in Ruff, basedpyright/Pyright, ty, Pyrefly (2025.3+,
#                           Settings > Python > Tools), uv as default env manager.
#  - Type checker "what is best": per-project choice. basedpyright is the mature,
#    strict, CI-friendly default installed here; Pyrefly (fast, zero config) and
#    ty (Astral, beta) are optional. Old projects keep their own
#    [tool.basedpyright]/mypy settings in pyproject.toml, which the IDE reads;
#    no global type-checker config is forced.
#  - Wayland: JetBrains makes native Wayland the default from 2026.1, but documents
#    CPU-only rendering and weak scrolling on integrated graphics until the
#    Vulkan pipeline matures. Hence XWayland on low GPU tier/ULV CPUs and the
#    default (native) elsewhere. Flip per machine with --toolkit.
#  - uv + IDE bug: 2026.2 cannot create uv environments when UV_PROJECT_ENVIRONMENT
#    is exported globally. Do not export it in shell profiles.
#  - Prefer pyproject.toml over IDE settings for ruff/format/type rules: the same
#    config then drives CLI, CI and the IDE.
#  - NextDNS: JetBrains IDEs only support HTTP proxies, not per-app DNS, so no
#    per-app NextDNS device id can be set. SELinux: the IDE runs unconfined in
#    the user's home; no policy changes needed.
#  - Things written in "best effort" form (verify once in the GUI): laf.xml theme
#    id, option-file keys for fonts. Unknown keys are ignored by the IDE.
#  - Not written because the file format is undocumented: data-sharing consent
#    (release builds default to off; you decline once in the dialog), LSP4IJ
#    server definitions, ShellCheck/shfmt paths.
#
# Carried over from the previous notes
#  - Set "JetBrainsMono Nerd Font" as the default editor font (done: editor-font.xml).
#  - Use the latest Python as interpreter: with uv, PyCharm suggests it itself.
#  - PyCharm uninstall: https://www.jetbrains.com/help/pycharm/uninstall.html
#
##################################################################################
# Useful Links
##################################################################################
# Unified PyCharm FAQ:            https://www.jetbrains.com/help/pycharm/unified-pycharm.html
# What's new 2025.3 (LSP tools):  https://www.jetbrains.com/pycharm/whatsnew/2025-3/
# LSP tools (Ruff/ty/Pyright):    https://www.jetbrains.com/help/pycharm/lsp-tools.html
# installPlugins CLI:             https://www.jetbrains.com/help/pycharm/install-plugins-from-the-command-line.html
# IDE directories:                https://www.jetbrains.com/help/pycharm/directories-used-by-the-ide-to-store-settings-caches-plugins-and-logs.html
# Wayland by default (2026.1):    https://blog.jetbrains.com/platform/2026/02/wayland-by-default-in-2026-1-eap/
# Native Wayland performance KB:  https://youtrack.jetbrains.com/projects/PY/articles/SUPPORT-A-3748/Wayland-native-mode-poor-scrolling-and-rendering-performance
# Vulkan pipeline (JBR-7558):     https://youtrack.jetbrains.com/projects/JBR/issues/JBR-7558
# LSP API free in unified IDEs:   https://blog.jetbrains.com/platform/2025/09/the-lsp-api-is-now-available-to-all-intellij-idea-users-and-plugin-developers/
# LSP4IJ:                         https://plugins.jetbrains.com/plugin/23257-lsp4ij
# AWS Toolkit for JetBrains:      https://github.com/aws/aws-toolkit-jetbrains
# Database Navigator (DBN):       https://plugins.jetbrains.com/plugin/1800-database-navigator
# Marketplace plugin details API: https://plugins.jetbrains.com/docs/marketplace/plugin-details.html
# Data sharing / AI endpoints:    https://www.jetbrains.com/help/idea/settings-usage-statistics.html
# Disable AI Assistant:           https://www.jetbrains.com/help/pycharm/disable-ai-assistant.html
# DataGrip non-commercial:        https://blog.jetbrains.com/datagrip
# Fedora 45 walk-through:         https://computingforgeeks.com/install-intellij-idea-fedora/
#
##################################################################################
# Troubleshooting/Debugging/Testing/Commands
##################################################################################
# IDE log:                 less ~/.cache/JetBrains/PyCharm*/log/idea.log
# Which toolkit is used:   grep -m1 'toolkit:' ~/.cache/JetBrains/PyCharm*/log/idea.log
#                          (sun.awt.wl.WLToolkit = native Wayland, XToolkit = XWayland)
# Slow scrolling:          re-run with --toolkit x11 ; blurry text: --toolkit wayland
# Window never appears on Wayland (regression reports in 2026.3): --toolkit x11
# Applied JVM flags:       ps -o args= -C java | grep -o -- '-Xmx[0-9a-z]*'
# Change heap quickly:     pycharm.sh --heap-mb 3072   (or Help > Change Memory Settings)
# Start without plugins:   pycharm disableNonBundledPlugins
# List installed plugins:  ls ~/.local/share/JetBrains/PyCharm*/
# Reinstall one plugin:    pycharm installPlugins <id>   (IDE closed)
# Find a plugin id:        marketplace page > Additional Information > Plugin ID
# IDE cannot find uv/ruff: start it from a terminal, or ensure ~/.local/bin is in the
#                          session PATH (login shell profile read by the display manager)
# Config backup/restore:   ls ~/nb/nb_script_data/backups/pycharm/ ; cp -a <backup>/home/<user>/. ~/
# Reset only caches:       rm -rf ~/.cache/JetBrains/PyCharm*/ (re-indexes projects)
# Crash dumps:             ls -la ~/.cache/JetBrains/crash-dumps   (delete after use)
# BleachBit cleaner check: bleachbit --preview jetbrains.logs
# Pro trial expired:       Kubernetes/Terraform/Database features switch off by design
