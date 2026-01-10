#!/usr/bin/env bash
# queue.sh
# Queue utilities: build command files from TSV manifests and execute them.

[[ "${__PFMRI_QUEUE_SH:-}" == "1" ]] && return 0
__PFMRI_QUEUE_SH=1

# shellcheck disable=SC1090,SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/core.sh"
# shellcheck disable=SC1090,SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/state.sh"

validate_queue_mode() {
  local mode="${1:-}"
  case "$mode" in
    pending|failed|all) return 0 ;;
    *) die "Invalid mode: $mode. Use pending/failed/all" ;;
  esac
}

count_nonempty_lines() {
  local file="${1:?file required}"
  [[ -f "$file" ]] || { echo 0; return 0; }
  awk 'NF{n++} END{print n+0}' "$file"
}

# Build a GNU-parallel-compatible command file from a TSV manifest.
#
# Usage:
#   queue_build_from_tsv <tsv> <mode> <cmd_file> <joblist_file> <run_one> <force> <job_id_fmt> <col1> [<col2> ...]
#
# Notes:
#   - Selected columns are passed to run_one (as positional args), and also used
#     to format the job id (printf-style job_id_fmt).
queue_build_from_tsv() {
  local tsv="${1:?tsv required}"; shift
  local mode="${1:?mode required}"; shift
  local cmd_file="${1:?cmd_file required}"; shift
  local joblist_file="${1:?joblist_file required}"; shift
  local run_one="${1:?run_one required}"; shift
  local force="${1:-0}"; shift
  local job_id_fmt="${1:?job_id_fmt required}"; shift

  validate_queue_mode "$mode"
  [[ -f "$tsv" ]] || die "TSV not found: $tsv"
  (( $# >= 1 )) || die "At least one column index required"

  : >"$cmd_file"
  : >"$joblist_file"

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    line="${line%$'\r'}"

    local -a fields=()
    IFS=$'\t' read -r -a fields <<<"$line"

    local -a args=()
    local col idx
    for col in "$@"; do
      [[ "$col" =~ ^[0-9]+$ ]] || die "Invalid column index: $col"
      (( col >= 1 )) || die "Column indices must be >= 1: $col"
      idx=$((col - 1))
      args+=("${fields[$idx]:-}")
    done

    # Require all args non-empty
    local a
    for a in "${args[@]}"; do
      [[ -n "$a" ]] || { args=(); break; }
    done
    (( ${#args[@]} > 0 )) || continue

    local job_id
    # shellcheck disable=SC2059
    job_id="$(printf "$job_id_fmt" "${args[@]}")"
    [[ -n "$job_id" ]] || continue

    should_enqueue "$job_id" "$mode" || continue

    printf 'bash %q' "$run_one" >>"$cmd_file"
    for a in "${args[@]}"; do
      printf ' %q' "$a" >>"$cmd_file"
    done
    printf ' %q\n' "$force" >>"$cmd_file"

    printf '%s\n' "$job_id" >>"$joblist_file"
  done <"$tsv"
}

_run_with_parallel() {
  local cmd_file="${1:?}"
  local jobs="${2:?}"
  local joblog="${3:?}"

  require_cmd parallel
  parallel --jobs "$jobs" --joblog "$joblog" --colsep '\t' --eta <"$cmd_file"
}

_run_with_bg_pool() {
  local cmd_file="${1:?}"
  local jobs="${2:?}"
  local joblog="${3:?}"

  ensure_dir "$(dirname -- "$joblog")"
  : >"$joblog"

  active_jobs() { jobs -rp | wc -l | tr -d ' '; }

  local cmd
  while IFS=$'\t' read -r cmd || [[ -n "$cmd" ]]; do
    [[ -n "$cmd" ]] || continue

    while (( $(active_jobs) >= jobs )); do
      wait -n
    done

    printf '%s\t%s\n' "$(date -Iseconds)" "$cmd" >>"$joblog"
    bash -c "$cmd" &
  done <"$cmd_file"

  wait
}

# Run a command file with either GNU parallel or a built-in background pool.
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
    log_warn "GNU parallel not found; using bash background pool (limited job control)"
    _run_with_bg_pool "$cmd_file" "$jobs" "$joblog"
  fi
}

queue_say_header() {
  local mode="${1:?mode required}"
  local force="${2:-0}"
  local n_todo="${3:-0}"
  local n_total="${4:-0}"
  local list_path="${5:-}"

  log_info "Input total: $n_total"
  [[ -n "$list_path" ]] && log_info "Input list: $list_path"
  log_info "Queue mode: $mode (force=$force)"
  log_info "To run: $n_todo"

  local -a parts=()
  [[ -n "${MAX_JOBS:-}" ]] && parts+=("MAX_JOBS=$MAX_JOBS")
  [[ -n "${NTHREADS:-}" ]] && parts+=("NTHREADS=$NTHREADS")
  [[ -n "${OMP_NTHREADS:-}" ]] && parts+=("OMP_NTHREADS=$OMP_NTHREADS")
  [[ -n "${MEM_MB:-}" ]] && parts+=("MEM_MB=$MEM_MB")
  (( ${#parts[@]} > 0 )) && log_info "Resources: ${parts[*]}"
}
