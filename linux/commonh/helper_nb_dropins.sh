#!/usr/bin/env bash
#########################################################
# helper_nb_dropins.sh - conf.d snippets and the single update runner
#########################################################
#
# DESIGN
#   Each setup script (omz.sh, starship.sh, atuin.sh, cli_tools.sh) owns ONE small zsh snippet and,
#   if it installs something that needs updating, ONE updater script. Nothing else knows about them.
#
#   /usr/local/share/zsh-nb/conf.d/        snippets loaded by EVERY zsh (user and root); root-owned
#   /usr/local/share/zsh-nb/conf.d-user/   snippets loaded only by non-root shells; root-owned
#   /usr/local/lib/nb/updaters.d/          one executable updater per tool; root-owned
#   /usr/local/sbin/nb-update-tools        runs every updater, prints one summary
#   nb-update-tools.timer                  single weekly systemd timer (sandboxed service)
#
#   ~/.zshrc and /root/.zshrc only contain a loader that sources the snippets in filename order.
#   Numeric prefixes decide the order:
#     10 omz  20 plugins  30 tools  40 prompt  50 atuin  90 syntax-highlighting (always last)
#
# WHY ROOT-OWNED: root's shell sources these files, so a normal user must not be able to edit them
# (otherwise any process running as that user could get root at the next `sudo -i`).
#
# FUNCTIONS
#   nb_ensure_conf_dirs
#   nb_install_conf   <common|user> <NN-name.zsh> <content>
#   nb_remove_conf    <common|user> <NN-name.zsh>
#   nb_install_updater <NN-name.sh> <content>      (content must be a complete bash script)
#   nb_remove_updater <NN-name.sh>
#   nb_ensure_update_runner                        (idempotent: runner, helper copy, units, timer)
#
# NEEDS (from helper_common.sh and the caller): log_*, write_file, SYSUPDATE_CODE_BASE_DIR,
# optional UPDATE_TIMER_SCHEDULE (default: weekly)

NB_ZSH_SHARED_DIR="/usr/local/share/zsh-nb"
NB_CONF_COMMON_DIR="${NB_ZSH_SHARED_DIR}/conf.d"
NB_CONF_USER_DIR="${NB_ZSH_SHARED_DIR}/conf.d-user"
NB_LIB_DIR="/usr/local/lib/nb"
NB_UPDATERS_DIR="${NB_LIB_DIR}/updaters.d"
NB_UPDATE_RUNNER="/usr/local/sbin/nb-update-tools"
NB_UPDATE_UNIT="nb-update-tools"

nb_ensure_conf_dirs() {
  install -d -o root -g root -m 0755 "$NB_ZSH_SHARED_DIR" "$NB_CONF_COMMON_DIR" "$NB_CONF_USER_DIR" \
                                      "$NB_LIB_DIR" "$NB_UPDATERS_DIR"
}

_nb_conf_dir() {
  case "$1" in
    common) printf '%s\n' "$NB_CONF_COMMON_DIR" ;;
    user)   printf '%s\n' "$NB_CONF_USER_DIR" ;;
    *)      return 1 ;;
  esac
}

nb_install_conf() {
  local dir; dir="$(_nb_conf_dir "$1")" || return 1
  nb_ensure_conf_dirs
  write_file "${dir}/$2" root root 0644 "$3"
}

nb_remove_conf() {
  local dir; dir="$(_nb_conf_dir "$1")" || return 1
  rm -f "${dir}/$2"
}

nb_install_updater() {
  nb_ensure_conf_dirs
  write_file "${NB_UPDATERS_DIR}/$1" root root 0755 "$2"
}

nb_remove_updater() { rm -f "${NB_UPDATERS_DIR}/$1"; }

# ---------- The runner: executes every updater, never stops at the first failure ----------
# shellcheck disable=SC2016
IFS= read -r -d '' _NB_RUNNER_TEMPLATE <<'EOF' || true
#!/usr/bin/env bash
# nb-update-tools - runs every updater in /usr/local/lib/nb/updaters.d (sorted by name).
# Installed by the nb setup scripts. Owned by root. Manual run: sudo /usr/local/sbin/nb-update-tools
set -uo pipefail
DIR="/usr/local/lib/nb/updaters.d"
ran=0; failed=0; failed_names=""
shopt -s nullglob
for f in "$DIR"/*.sh; do
  [[ -x "$f" ]] || continue
  name="$(basename "$f")"
  echo "== ${name}"
  ran=$((ran + 1))
  # Each updater runs as its own process: one failing or crashing cannot stop the others.
  if ! "$f"; then
    failed=$((failed + 1)); failed_names+=" ${name}"
  fi
done
echo "== summary: ${ran} updater(s), ${failed} failed${failed_names:+ (${failed_names# })}"
(( failed == 0 ))
EOF

nb_ensure_update_runner() {
  nb_ensure_conf_dirs
  install -o root -g root -m 0644 "${SYSUPDATE_CODE_BASE_DIR}/linux/commonh/helper_github_release.sh" \
    "${NB_LIB_DIR}/helper_github_release.sh"
  write_file "$NB_UPDATE_RUNNER" root root 0755 "$_NB_RUNNER_TEMPLATE"

  # Sandboxed service: the runner is root, but can only write to the places updaters need.
  cat > "/etc/systemd/system/${NB_UPDATE_UNIT}.service" <<UNIT
[Unit]
Description=Update shell tools (Oh My Zsh, Starship, Atuin, ...)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=${NB_UPDATE_RUNNER}
ProtectSystem=strict
ReadWritePaths=${NB_ZSH_SHARED_DIR} /usr/local/bin ${NB_LIB_DIR}
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
Nice=10
IOSchedulingClass=idle
UNIT

  cat > "/etc/systemd/system/${NB_UPDATE_UNIT}.timer" <<UNIT
[Unit]
Description=Weekly update of shell tools

[Timer]
OnCalendar=${UPDATE_TIMER_SCHEDULE:-weekly}
# Persistent=true: if the PC was off at the scheduled time, run at the next boot.
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
UNIT
  chown root:root "/etc/systemd/system/${NB_UPDATE_UNIT}".{service,timer}
  chmod 0644 "/etc/systemd/system/${NB_UPDATE_UNIT}".{service,timer}
  systemctl daemon-reload
  systemctl enable --now "${NB_UPDATE_UNIT}.timer" >/dev/null 2>&1
}
