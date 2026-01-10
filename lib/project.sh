#!/usr/bin/env bash
# project.sh
# Project bootstrapping: find PROJECT_ROOT, load config, define standard dirs.

[[ "${__PFMRI_PROJECT_SH:-}" == "1" ]] && return 0
__PFMRI_PROJECT_SH=1

# shellcheck disable=SC1090,SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/core.sh"

_find_project_root() {
  local start_dir="${1:?start_dir required}"
  local d
  d="$(realpath_safe "$start_dir")"
  while [[ "$d" != "/" ]]; do
    [[ -f "$d/config/project.env" ]] && { printf '%s\n' "$d"; return 0; }
    d="$(dirname -- "$d")"
  done
  return 1
}

_source_env() {
  local f="${1:?env file required}"
  [[ -f "$f" ]] || die "Config file not found: $f"
  # shellcheck disable=SC1090
  source <(strip_crlf_file "$f")
}

project_load() {
  # Usage: project_load <pipeline_name> [caller_dir]
  local pipeline="${1:?pipeline name required}"
  local caller_dir="${2:-}"

  if [[ -z "$caller_dir" ]]; then
    if [[ "${#BASH_SOURCE[@]}" -ge 2 ]]; then
      caller_dir="$(script_dir "${BASH_SOURCE[1]}")"
    else
      caller_dir="$(pwd -P)"
    fi
  fi

  PROJECT_ROOT="$(_find_project_root "$caller_dir")" || die "Cannot locate PROJECT_ROOT from: $caller_dir (expected config/project.env)"
  PIPELINE_NAME="$pipeline"

  CONFIG_ROOT="${PROJECT_ROOT}/config"
  LIB_ROOT="${PROJECT_ROOT}/lib"
  PIPELINES_ROOT="${PROJECT_ROOT}/pipelines"
  TOOLS_ROOT="${PROJECT_ROOT}/tools"

  _source_env "$CONFIG_ROOT/project.env"
  _source_env "$CONFIG_ROOT/${pipeline}.env"

  # Standard dirs (can be overridden by env)
  : "${LOG_ROOT:=$PROJECT_ROOT/logs}"
  : "${WORK_ROOT:=$PROJECT_ROOT/work}"
  : "${BIDS_ROOT:=$PROJECT_ROOT/bids}"
  : "${DERIV_ROOT:=$PROJECT_ROOT/derivatives}"
  : "${STAGE_ROOT:=$PROJECT_ROOT/stage}"
  : "${CONTAINERS_ROOT:=$HOME/containers}"

  LOGDIR="${LOG_ROOT}/${PIPELINE_NAME}"

  # State markers
  : "${STATE_DIR:=$LOGDIR/state}"
  : "${DONE_DIR:=$STATE_DIR/done}"
  : "${FAILED_DIR:=$STATE_DIR/failed}"
  : "${RUNNING_DIR:=$STATE_DIR/running}"
  : "${LOCK_DIR:=$STATE_DIR/lock}"

  ensure_dir "$LOGDIR"
  ensure_dir "$WORK_ROOT"

  # Minimize accidental environment export (best-effort)
  export -n PROJECT_ROOT PIPELINE_NAME CONFIG_ROOT LIB_ROOT PIPELINES_ROOT TOOLS_ROOT \
    LOG_ROOT WORK_ROOT BIDS_ROOT DERIV_ROOT STAGE_ROOT CONTAINERS_ROOT LOGDIR \
    STATE_DIR DONE_DIR FAILED_DIR RUNNING_DIR LOCK_DIR 2>/dev/null || true
}
