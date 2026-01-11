#!/usr/bin/env bash
# state.sh
# DONE/FAILED/RUNNING/LOCK markers + a small helper to run jobs idempotently.

[[ "${__PFMRI_STATE_SH:-}" == "1" ]] && return 0
__PFMRI_STATE_SH=1

# shellcheck disable=SC1090,SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/core.sh"

_check_state_vars() {
  [[ -n "${DONE_DIR:-}" ]] || die "DONE_DIR not set"
  [[ -n "${FAILED_DIR:-}" ]] || die "FAILED_DIR not set"
  [[ -n "${RUNNING_DIR:-}" ]] || die "RUNNING_DIR not set"
  [[ -n "${LOCK_DIR:-}" ]] || die "LOCK_DIR not set"
}

init_state_dirs() {
  _check_state_vars
  ensure_dir "$DONE_DIR"
  ensure_dir "$FAILED_DIR"
  ensure_dir "$RUNNING_DIR"
  ensure_dir "$LOCK_DIR"
}

is_done()    { [[ -f "$DONE_DIR/${1:?}.DONE" ]]; }
is_failed()  { [[ -f "$FAILED_DIR/${1:?}.FAILED" ]]; }
is_running() { [[ -f "$RUNNING_DIR/${1:?}.RUNNING" ]]; }
is_locked()  { [[ -d "$LOCK_DIR/${1:?}.lock" ]]; }

acquire_lock() { mkdir "$LOCK_DIR/${1:?}.lock" 2>/dev/null; }
release_lock() { rmdir "$LOCK_DIR/${1:?}.lock" 2>/dev/null || true; }

mark_running() {
  local job_id="${1:?}"
  rm -f "$DONE_DIR/$job_id.DONE" "$FAILED_DIR/$job_id.FAILED" 2>/dev/null || true
  touch "$RUNNING_DIR/$job_id.RUNNING"
}

mark_done() {
  local job_id="${1:?}"
  rm -f "$RUNNING_DIR/$job_id.RUNNING" "$FAILED_DIR/$job_id.FAILED" 2>/dev/null || true
  printf '%s\n' "$(date -Iseconds)" >"$DONE_DIR/$job_id.DONE"
}

mark_failed() {
  local job_id="${1:?}"
  rm -f "$RUNNING_DIR/$job_id.RUNNING" "$DONE_DIR/$job_id.DONE" 2>/dev/null || true
  printf '%s\n' "$(date -Iseconds)" >"$FAILED_DIR/$job_id.FAILED"
}

# MODE: pending | failed | all
should_enqueue() {
  local job_id="${1:?job_id required}"
  local mode="${2:-pending}"

  if is_running "$job_id" || is_locked "$job_id"; then
    return 1
  fi

  case "$mode" in
    pending)
      if is_done "$job_id" || is_failed "$job_id"; then
        return 1
      fi
      return 0
      ;;
    failed)
      is_failed "$job_id"
      ;;
    all)
      return 0
      ;;
    *)
      die "Invalid mode: $mode (expected pending|failed|all)"
      ;;
  esac
}

# Run a job with lock+markers and redirect all output to LOGFILE.
# Usage:
#   job_run <job_id> <force:0|1> <logfile> -- <command...>
# Notes:
#   - If job is DONE and not forced, returns 0.
#   - If job is RUNNING/LOCKED, returns 0.
#   - On non-zero command exit, marks FAILED and returns the same code.
job_run() {
  local job_id="${1:?job_id required}"
  local force="${2:-0}"
  local logfile="${3:?logfile required}"
  shift 3
  [[ "${1:-}" == "--" ]] && shift || true

  init_state_dirs
  ensure_dir "$(dirname -- "$logfile")"

  # Make job-specific logs easy to find.
  export LOGFILE="$logfile"

  if is_done "$job_id" && [[ "$force" != "1" ]]; then
    log_info "SKIP(DONE) $job_id"
    return 0
  fi

  if is_running "$job_id"; then
    log_info "SKIP(RUNNING) $job_id"
    return 0
  fi

  if ! acquire_lock "$job_id"; then
    log_info "SKIP(LOCKED) $job_id"
    return 0
  fi

  # Ensure lock removal even if the caller exits the function early.
  trap 'release_lock "$job_id"' RETURN

  log_info "START $job_id (force=$force)"
  mark_running "$job_id"

  local errexit_was_on=0
  if shopt -qo errexit; then
    errexit_was_on=1
    set +e
  fi

  # Run the command; redirect everything into logfile.
  "$@" >>"$logfile" 2>&1
  local rc=$?

  if (( errexit_was_on )); then
    set -e
  fi

  if [[ "$rc" -eq 0 ]]; then
    mark_done "$job_id"
    log_info "DONE  $job_id"
  else
    mark_failed "$job_id"
    log_error "FAIL  $job_id (exit=$rc)"
  fi

  return "$rc"
}

summarize_failures_from_joblist() {
  # Usage: summarize_failures_from_joblist <joblog_path> <joblist_file>
  local joblog_path="${1:?joblog_path required}"
  local joblist_file="${2:?joblist_file required}"

  [[ -f "$joblist_file" ]] || die "job list file not found: $joblist_file"

  local -a failed_jobs=()
  local job_id
  while IFS= read -r job_id || [[ -n "${job_id:-}" ]]; do
    [[ -n "${job_id:-}" ]] || continue
    [[ -f "$FAILED_DIR/$job_id.FAILED" ]] && failed_jobs+=("$job_id")
  done <"$joblist_file"

  if (( ${#failed_jobs[@]} > 0 )); then
    printf 'FAILED: %s job(s). Joblog -> %s\n' "${#failed_jobs[@]}" "$joblog_path" >&2
    for job_id in "${failed_jobs[@]}"; do
      printf '  %s -> %s/%s.log\n' "$job_id" "$LOGDIR" "$job_id" >&2
    done
    return 1
  fi

  printf 'OK: all jobs finished. Joblog -> %s\n' "$joblog_path" >&2
  return 0
}
