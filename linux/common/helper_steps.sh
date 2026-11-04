#!/usr/bin/env bash
#########################################################
# helper_steps.sh
#########################################################
# A small "step runner" for long, multi-stage setup scripts.
#
# WHAT IT GIVES
#   1. Every stage runs in its own subshell with strict mode ON, so a failure inside a stage
#      aborts only that stage, not the whole script.
#   2. Results are recorded and summarized at the end (print_step_summary).
#   3. Completed stages are written to a state file, so re-running after a failure or a
#      mandatory reboot skips what is already done.
#
# FUNCTIONS
#   run_step <name> <command> [args...]
#       Runs the command (a shell function or any program) as one named stage.
#   step_is_done <name> / step_mark_done <name>
#       Query / record a stage in the state file.
#   print_step_summary
#       Prints one line per stage; returns 1 if any stage failed.
#
# REQUIRED VARIABLES (set by the caller BEFORE calling run_step; the helper stops with a clear
# message instead of failing with "unbound variable" when they are missing)
#   STATE_FILE   file recording completed steps (one "DONE:<name>" line each)
#
# REQUIRES: log_info, log_header, log_success, log_error (helper_logging.sh)
#
# WHY A SUBSHELL AND NOT `if func; then`?
#   Bash silently DISABLES `set -e` inside any function called as the condition of an `if`,
#   `&&` or `||`. Running the stage as a plain command in a subshell, with errexit temporarily
#   off in the parent, keeps `set -e` fully active inside the stage.
#
# TRACING
#   The stage subshell inherits `set -x` when the caller enabled it, so a traced run stays traced.


# Sourcing Guard Rails - uses a safety guard (HELPER_XYZ_LOADED) to prevent issues if it gets sourced multiple times.
if [[ -z "${HELPER_STEPS_LOADED:-}" ]]; then
    HELPER_STEPS_LOADED=1

    STEP_RESULTS=()   # entries: "name|status|seconds"

    step_is_done()   { [[ -f "${STATE_FILE:?STATE_FILE must be set}" ]] && grep -qx "DONE:$1" "${STATE_FILE}"; }
    step_mark_done() { echo "DONE:$1" >> "${STATE_FILE:?STATE_FILE must be set}"; }

    run_step() {
        local name="$1" rc start
        shift
        : "${STATE_FILE:?STATE_FILE must be set before run_step}"

        if step_is_done "$name"; then
            log_info "Skipping '${name}' (completed earlier in this run)"
            STEP_RESULTS+=("${name}|skipped|0")
            return 0
        fi

        log_header "${name}"
        start=$SECONDS
        set +e                                  # let the subshell's exit code come back to us
        ( set -Eeuo pipefail; "$@" )            # the stage itself, with strict mode re-enabled
        rc=$?
        set -e

        if [[ "$rc" -eq 0 ]]; then
            step_mark_done "$name"
            STEP_RESULTS+=("${name}|ok|$((SECONDS - start))")
            log_success "${name} finished"
        else
            STEP_RESULTS+=("${name}|FAILED|$((SECONDS - start))")
            log_error "${name} FAILED (exit ${rc}). It will be retried on the next run."
        fi
        return 0                                # a failed stage never aborts the orchestrator
    }

    print_step_summary() {
        local entry name status secs failed=0
        log_header "Summary"
        for entry in "${STEP_RESULTS[@]}"; do
            IFS='|' read -r name status secs <<< "$entry"
            case "$status" in
                ok)      log_success "$(printf '%-34s %s (%ss)' "$name" "$status" "$secs")" ;;
                skipped) log_info    "$(printf '%-34s %s' "$name" "$status")" ;;
                *)       log_error   "$(printf '%-34s %s (%ss)' "$name" "$status" "$secs")"; failed=1 ;;
            esac
        done
        return "$failed"
    }

fi
