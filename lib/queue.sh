#!/usr/bin/env bash
# Queue processing utilities for parallel job execution.

# shellcheck disable=SC1090
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

# Run with GNU parallel
_run_with_parallel() {
  local cmd_file="${1:?}"
  local jobs="${2:?}"
  local joblog="${3:?}"

  require_cmd parallel
  parallel --jobs "$jobs" --joblog "$joblog" --colsep '\t' --eta <"$cmd_file"
}

# Fallback: run with bash background job pool
_run_with_bg_pool() {
  local cmd_file="${1:?}"
  local jobs="${2:?}"
  local joblog="${3:?}"

  ensure_dir "$(dirname -- "$joblog")"
  : >"$joblog"

  local n=0
  local -a pids=()

  local active_jobs
  active_jobs() { jobs -rp | wc -l | tr -d ' '; }

  while IFS=$'\t' read -r cmd || [[ -n "$cmd" ]]; do
    [[ -z "$cmd" ]] && continue

    # Wait if queue is full
    while (( $(active_jobs) >= jobs )); do
      wait -n
    done

    # Log and execute
    printf '%s\t%s\n' "$(date -Iseconds)" "$cmd" >>"$joblog"
    bash -c "$cmd" &
    pids+=("$!")
  done <"$cmd_file"

  # Wait for all remaining jobs
  wait
}

# Main queue runner
# Usage: run_queue <cmd_file> <max_jobs> [joblog]
run_queue() {
  local cmd_file="${1:?command file required}"
  local jobs="${2:-1}"
  local joblog="${3:-}"

  [[ -f "$cmd_file" ]] || die "Command file not found: $cmd_file"
  [[ "$jobs" =~ ^[0-9]+$ ]] || die "jobs must be an integer: $jobs"
  (( jobs >= 1 )) || die "jobs must be >= 1"

  if [[ -z "$joblog" ]]; then
    joblog="$(dirname -- "$cmd_file")/joblog.tsv"
  fi

  if have_cmd parallel; then
    _run_with_parallel "$cmd_file" "$jobs" "$joblog"
  else
    warn "GNU parallel not found; using bash background job pool (limited logging)"
    _run_with_bg_pool "$cmd_file" "$jobs" "$joblog"
  fi
}
