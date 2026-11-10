#!/usr/bin/env bash
##################################################################################
# helper_script_logging.sh
##################################################################################
# Purpose
#   Make the CURRENT script log everything it prints to a file WITHOUT degrading
#   the terminal output (colors, progress bars, sudo prompts all keep working).
#
# Why not "exec > >(tee file) 2>&1"?
#   That turns stdout into a pipe. Programs (and our own log_* helpers) usually
#   check "is stdout a terminal?" and switch colors off when it is not.
#   util-linux `script` instead gives the child a pseudo-terminal (PTY), so the
#   child still believes it talks to a real terminal, while `script` copies all
#   output into the log file. The log contains raw ANSI color codes; read it
#   with `less -R` or strip them with:  sed 's/\x1b\[[0-9;]*[A-Za-z]//g' file
#
# Usage (call it early, after the log directory variables are known)
#   source "$HELPER_DIR/helper_script_logging.sh"
#   export REAL_USER FILENAME_TIMESTAMP      # so the re-run computes identical paths
#   start_script_logging "$LOG_FILE" "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"
#
#   - The function RE-EXECUTES the script once inside `script`. The second run
#     sees NB_SCRIPT_LOGGING_ACTIVE=<its own path> and simply continues.
#   - The guard stores the script path, so when a main script calls several
#     package scripts, each package script still gets its own log file.
#   - Exit status of the script is preserved (`script --return`).
##################################################################################

# Multiple-sourcing guard (same convention as the other helpers).
if [ -n "${HELPER_SCRIPT_LOGGING_LOADED:-}" ]; then
  return 0
fi
HELPER_SCRIPT_LOGGING_LOADED=1

# start_script_logging <log_file> <script_path> [script args...]
start_script_logging() {
  local log_file="$1" script_path="$2"
  shift 2

  # Already running inside the logging session started for this very script.
  if [ "${NB_SCRIPT_LOGGING_ACTIVE:-}" = "$script_path" ]; then
    return 0
  fi

  if ! command -v script >/dev/null 2>&1; then
    echo "WARNING: util-linux 'script' not found; continuing WITHOUT a log file." >&2
    return 0
  fi

  mkdir -p "$(dirname "$log_file")"

  # printf %q re-quotes every argument so spaces/quotes survive the re-exec.
  local cmd
  cmd="$(printf '%q ' bash "$script_path" "$@")"

  export NB_SCRIPT_LOGGING_ACTIVE="$script_path"
  # --quiet  : do not print "Script started/done" banners
  # --return : exit with the child's exit status
  # --append : never truncate an existing log
  # --flush  : write to the log immediately (useful if the script is interrupted)
  exec script --quiet --return --append --flush --command "$cmd" "$log_file"
}
