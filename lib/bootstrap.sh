#!/usr/bin/env bash
# Bootstrapping (project root detection + .env loading).
# Source this file, then call: bootstrap "<pipeline_name>" "<caller_script_dir>"

# shellcheck disable=SC1090
BOOTSTRAP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${BOOTSTRAP_DIR}/common.sh"

_find_project_root() {
  local start_dir="${1:?start_dir required}"
  local d
  d="$(realpath_safe "$start_dir")"
  while [[ "$d" != "/" ]]; do
    if [[ -f "$d/config/project.env" ]]; then
      printf '%s\n' "$d"
      return 0
    fi
    d="$(dirname -- "$d")"
  done
  return 1
}

_load_env_file() {
  local f="${1:?env file required}"
  [[ -f "$f" ]] || die "Config file not found: $f"
  # Allow CRLF env files on Windows.
  if have_cmd sed; then
    # shellcheck disable=SC1090
    source <(sed 's/\r$//' "$f")
  else
    # shellcheck disable=SC1090
    source "$f"
  fi
}

bootstrap() {
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

  : "${CONFIG_ROOT:=$PROJECT_ROOT/config}"
  : "${LIB_ROOT:=$PROJECT_ROOT/lib}"
  : "${PIPELINES_ROOT:=$PROJECT_ROOT/pipelines}"

  _load_env_file "$CONFIG_ROOT/project.env"
  _load_env_file "$CONFIG_ROOT/${pipeline}.env"

  : "${LOG_ROOT:=$PROJECT_ROOT/logs}"
  : "${WORK_ROOT:=$PROJECT_ROOT/work}"
  : "${BIDS_ROOT:=$PROJECT_ROOT/bids}"
  : "${DERIV_ROOT:=$PROJECT_ROOT/derivatives}"
  : "${STAGE_ROOT:=$PROJECT_ROOT/stage}"
  : "${CONTAINERS_ROOT:=$HOME/containers}"

  : "${LOGDIR:=$LOG_ROOT/$PIPELINE_NAME}"

  ensure_dir "$LOGDIR"

  # Status dir defaults if not provided by pipeline env
  : "${STATE_DIR:=$LOGDIR/state}"
  : "${DONE_DIR:=$STATE_DIR/done}"
  : "${FAILED_DIR:=$STATE_DIR/failed}"
  : "${RUNNING_DIR:=$STATE_DIR/running}"
  : "${LOCK_DIR:=$STATE_DIR/lock}"

  # Prevent accidental export (minimal environment pollution)
  export -n PROJECT_ROOT PIPELINE_NAME CONFIG_ROOT LIB_ROOT PIPELINES_ROOT LOGDIR STATE_DIR DONE_DIR FAILED_DIR RUNNING_DIR LOCK_DIR 2>/dev/null || true
}
