#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/project.sh"
project_load "fmriprep" "$SCRIPT_DIR"

# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/core.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/state.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/container.sh"

LABEL="${1:?label required (e.g., 001)}"
FORCE="${2:-0}"

ensure_dir "$DERIV_ROOT"
ensure_dir "$FS_SUBJECTS_DIR"
ensure_dir "$WORK_ROOT"
ensure_dir "$LOGDIR"
ensure_dir "$BIDS_DB_DIR"
init_state_dirs

SUB="sub-${LABEL}"
WORK_SUB="$WORK_ROOT/$SUB"
LOGFILE="$LOGDIR/${SUB}.log"

# Build optional args
SKIP_OPT=()
[[ "${SKIP_BIDS_VALIDATION:-1}" == "1" ]] && SKIP_OPT+=(--skip-bids-validation)

CIFTI_OPT=()
[[ -n "${CIFTI_OUTPUT:-}" ]] && CIFTI_OPT+=(--cifti-output "$CIFTI_OUTPUT")

fmriprep_exec() {
  # Workdir policy
  if [[ "${WIPE_WORKDIR_ON_START:-0}" == "1" ]]; then
    rm -rf "$WORK_SUB"
  fi
  mkdir -p "$WORK_SUB"

  run_container "$FMRIPREP_SIF" \
    "$BIDS_ROOT:$BIDS_ROOT" \
    "$DERIV_ROOT:$DERIV_ROOT" \
    "$FS_SUBJECTS_DIR:$FS_SUBJECTS_DIR" \
    "$WORK_ROOT:$WORK_ROOT" \
    "$BIDS_DB_DIR:$BIDS_DB_DIR" \
    "$FS_LICENSE:$FS_LICENSE" \
    -- \
      "$BIDS_ROOT" "$DERIV_ROOT" participant \
      --participant-label "$LABEL" \
      -w "$WORK_SUB" \
      --fs-license-file "$FS_LICENSE" \
      --fs-subjects-dir "$FS_SUBJECTS_DIR" \
      --bids-database-dir "$BIDS_DB_DIR" \
      --nthreads "$NTHREADS" \
      --omp-nthreads "$OMP_NTHREADS" \
      --mem_mb "$MEM_MB" \
      --output-spaces "$OUTPUT_SPACES" \
      "${CIFTI_OPT[@]}" \
      "${SKIP_OPT[@]}" \
      --stop-on-first-crash \
      --notrack
}

job_run "$SUB" "$FORCE" "$LOGFILE" -- fmriprep_exec
rc=$?

if [[ "$rc" -eq 0 && "${CLEAN_WORK_ON_SUCCESS:-1}" == "1" ]]; then
  rm -rf "$WORK_SUB" || true
  log_info "CLEAN workdir $WORK_SUB"
fi

exit "$rc"
