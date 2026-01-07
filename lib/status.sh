#!/usr/bin/env bash
# Status markers for idempotent pipeline execution.
# Manages DONE/FAILED/RUNNING/LOCK states.

# shellcheck disable=SC1090
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

# Check if state directory variables are set
_check_state_vars() {
  [[ -n "${DONE_DIR:-}" ]] || die "DONE_DIR not set"
  [[ -n "${FAILED_DIR:-}" ]] || die "FAILED_DIR not set"
  [[ -n "${RUNNING_DIR:-}" ]] || die "RUNNING_DIR not set"
  [[ -n "${LOCK_DIR:-}" ]] || die "LOCK_DIR not set"
}

# Initialize state directories
init_state_dirs() {
  _check_state_vars
  ensure_dir "$DONE_DIR"
  ensure_dir "$FAILED_DIR"
  ensure_dir "$RUNNING_DIR"
  ensure_dir "$LOCK_DIR"
}

# Status check functions
is_done() {
  local job_id="${1:?job_id required}"
  [[ -f "$DONE_DIR/${job_id}.DONE" ]]
}

is_failed() {
  local job_id="${1:?job_id required}"
  [[ -f "$FAILED_DIR/${job_id}.FAILED" ]]
}

is_running() {
  local job_id="${1:?job_id required}"
  [[ -f "$RUNNING_DIR/${job_id}.RUNNING" ]]
}

is_locked() {
  local job_id="${1:?job_id required}"
  [[ -d "$LOCK_DIR/${job_id}.lock" ]]
}

# Acquire lock (atomic directory creation)
acquire_lock() {
  local job_id="${1:?job_id required}"
  mkdir "$LOCK_DIR/${job_id}.lock" 2>/dev/null
}

# Release lock
release_lock() {
  local job_id="${1:?job_id required}"
  rmdir "$LOCK_DIR/${job_id}.lock" 2>/dev/null || true
}

# Mark job as running
mark_running() {
  local job_id="${1:?job_id required}"
  rm -f "$DONE_DIR/${job_id}.DONE" "$FAILED_DIR/${job_id}.FAILED" 2>/dev/null || true
  touch "$RUNNING_DIR/${job_id}.RUNNING"
}

# Mark job as done
mark_done() {
  local job_id="${1:?job_id required}"
  rm -f "$RUNNING_DIR/${job_id}.RUNNING" "$FAILED_DIR/${job_id}.FAILED" 2>/dev/null || true
  printf '%s\n' "$(date -Iseconds)" >"$DONE_DIR/${job_id}.DONE"
}

# Mark job as failed
mark_failed() {
  local job_id="${1:?job_id required}"
  rm -f "$RUNNING_DIR/${job_id}.RUNNING" "$DONE_DIR/${job_id}.DONE" 2>/dev/null || true
  printf '%s\n' "$(date -Iseconds)" >"$FAILED_DIR/${job_id}.FAILED"
}

# Queue filter helper
# Returns 0 if job should be enqueued under MODE.
# MODE: pending|failed|all
should_enqueue() {
  local job_id="${1:?job_id required}"
  local mode="${2:-pending}"

  # Avoid duplicate concurrent starts
  if is_running "$job_id" || is_locked "$job_id"; then
    return 1
  fi

  case "$mode" in
    pending)
      # Default: do NOT enqueue failed jobs
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
