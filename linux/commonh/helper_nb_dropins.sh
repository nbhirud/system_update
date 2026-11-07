#!/usr/bin/env bash
#########################################################
# helper_nb_dropins.sh - per-user zsh snippets (conf.d) and the single user-level update runner
#########################################################
#
# DESIGN
#   Each setup script (omz.sh, cli_tools.sh, starship.sh, atuin.sh) owns ONE small zsh snippet and, if it
#   installs something that needs updating outside dnf, ONE updater script. Nothing else knows about them.
#   Everything lives in the USER'S home and is owned by the user: no root, no sudo, no shared directories.
#
#   ~/.config/zsh/conf.d/*.zsh             snippets, sourced by ~/.zshrc in filename order
#   ~/.local/bin/nb-update-tools           runs every updater and prints one summary
#   ~/.local/share/nb/updaters.d/*.sh      one updater per tool
#   ~/.local/share/nb/helper_github_release.sh   copy of the release helper, used by the updaters
#
#   Numeric prefixes decide the snippet order:
#     10 omz  20 plugins  30 tools  40 prompt  50 atuin  90 syntax-highlighting (always last)
#
# There is no timer: updates run when you run `nbupdate` (which calls nb-update-tools) or by hand.
#
# FUNCTIONS
#   nb_ensure_conf_dirs
#   nb_install_conf   <NN-name.zsh> <content>
#   nb_remove_conf    <NN-name.zsh>
#   nb_install_updater <NN-name.sh> <content>      (content must be a complete bash script)
#   nb_remove_updater <NN-name.sh>
#   nb_ensure_update_runner                        (idempotent: runner + helper copy)
#
# NEEDS (from helper_common.sh and the caller): nb_mkdir, write_file, REAL_USER, HOME_DIR, HELPER_DIR (or
# SYSUPDATE_CODE_BASE_DIR, from which the default linux/commonh is derived).
# Works as root (files are then handed to REAL_USER) and as the user.

NB_ZSH_CONF_DIR="${HOME_DIR}/.config/zsh/conf.d"
NB_LOCAL_BIN="${HOME_DIR}/.local/bin"
NB_USER_LIB_DIR="${HOME_DIR}/.local/share/nb"
NB_UPDATERS_DIR="${NB_USER_LIB_DIR}/updaters.d"
NB_UPDATE_RUNNER="${NB_LOCAL_BIN}/nb-update-tools"

nb_ensure_conf_dirs() {
  nb_mkdir 0755 "$NB_ZSH_CONF_DIR" "$NB_LOCAL_BIN" "$NB_USER_LIB_DIR" "$NB_UPDATERS_DIR"
}

nb_install_conf() {
  nb_ensure_conf_dirs
  write_file "${NB_ZSH_CONF_DIR}/$1" "$REAL_USER" "$REAL_USER" 0644 "$2"
}

nb_remove_conf() { rm -f "${NB_ZSH_CONF_DIR}/$1"; }

nb_install_updater() {
  nb_ensure_conf_dirs
  write_file "${NB_UPDATERS_DIR}/$1" "$REAL_USER" "$REAL_USER" 0755 "$2"
}

nb_remove_updater() { rm -f "${NB_UPDATERS_DIR}/$1"; }

# ---------- The runner: executes every updater, never stops at the first failure ----------
# shellcheck disable=SC2016
IFS= read -r -d '' _NB_RUNNER_TEMPLATE <<'RUNNER' || true
#!/usr/bin/env bash
# nb-update-tools - runs every updater in @UPDATERS_DIR@ (sorted by name).
# Installed by the nb setup scripts. Runs as YOU; no sudo. Manual run: nb-update-tools
set -uo pipefail
DIR="@UPDATERS_DIR@"
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
RUNNER

nb_ensure_update_runner() {
  nb_ensure_conf_dirs
  local lib="${NB_USER_LIB_DIR}/helper_github_release.sh"
  cp "${HELPER_DIR:-${SYSUPDATE_CODE_BASE_DIR}/linux/commonh}/helper_github_release.sh" "$lib"
  chmod 0644 "$lib"
  if [[ ${EUID} -eq 0 ]]; then chown "${REAL_USER}:${REAL_USER}" "$lib"; fi
  write_file "$NB_UPDATE_RUNNER" "$REAL_USER" "$REAL_USER" 0755 "${_NB_RUNNER_TEMPLATE//@UPDATERS_DIR@/${NB_UPDATERS_DIR}}"
}
