#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090
source "${SCRIPT_DIR}/../../lib/bootstrap.sh"
bootstrap "fmriprep" "$SCRIPT_DIR"

# Load shared libraries
# shellcheck disable=SC1091
source "$LIB_ROOT/common.sh"
# shellcheck disable=SC1091
source "$LIB_ROOT/status.sh"
# shellcheck disable=SC1091
source "$LIB_ROOT/container.sh"

LABEL="$1"                 # e.g., 001 (without sub-)
FORCE="${2:-0}"            # 1=force rerun (run even if DONE)

ensure_dir "$DERIV_ROOT"
ensure_dir "$FS_SUBJECTS_DIR"
ensure_dir "$WORK_ROOT"
ensure_dir "$LOGDIR"
init_state_dirs

SUB="sub-${LABEL}"
WORK_SUB="$WORK_ROOT/$SUB"
LOGFILE="$LOGDIR/${SUB}.log"

# DONE and not forced: skip
if is_done "$SUB" && [ "$FORCE" != "1" ]; then
  log "SKIP (DONE): $SUB"
  exit 0
fi

if is_running "$SUB"; then
  log "SKIP (RUNNING): $SUB"
  exit 0
fi

# Atomic directory lock: avoid duplicate concurrent runs for the same subject
if ! acquire_lock "$SUB"; then
  log "SKIP (LOCKED): $SUB"
  exit 0
fi

trap "release_lock '$SUB'" EXIT

# Pre-run status
log "START $SUB (force=$FORCE)" | tee -a "$LOGFILE"
mark_running "$SUB"

# Workdir policy
if [ "${WIPE_WORKDIR_ON_START:-0}" = "1" ]; then
  rm -rf "$WORK_SUB"
fi
mkdir -p "$WORK_SUB"

# Option: skip BIDS validation
SKIP_OPT=()
if [ "${SKIP_BIDS_VALIDATION:-1}" = "1" ]; then
  SKIP_OPT+=(--skip-bids-validation)
fi

# Option: CIFTI
CIFTI_OPT=()
if [ -n "${CIFTI_OUTPUT:-}" ]; then
  CIFTI_OPT+=(--cifti-output "$CIFTI_OUTPUT")
fi

# Run fmriprep
set +e
run_container "$FMRIPREP_SIF" \
  "$BIDS_ROOT":"$BIDS_ROOT" \
  "$DERIV_ROOT":"$DERIV_ROOT" \
  "$FS_SUBJECTS_DIR":"$FS_SUBJECTS_DIR" \
  "$WORK_ROOT":"$WORK_ROOT" \
  "$BIDS_DB_DIR":"$BIDS_DB_DIR" \
  "$FS_LICENSE":"$FS_LICENSE" \
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
    --output-spaces $OUTPUT_SPACES \
    "${CIFTI_OPT[@]}" \
    "${SKIP_OPT[@]}" \
    --stop-on-first-crash \
    --notrack \
  >> "$LOGFILE" 2>&1
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
  mark_done "$SUB"
  log "DONE  $SUB" | tee -a "$LOGFILE"

  # Cleanup workdir on success (free disk space)
  if [ "${CLEAN_WORK_ON_SUCCESS:-1}" = "1" ]; then
    rm -rf "$WORK_SUB"
    log "CLEAN workdir $WORK_SUB" | tee -a "$LOGFILE"
  fi
else
  mark_failed "$SUB"
  log "FAIL  $SUB (exit=$rc)" | tee -a "$LOGFILE"
fi

exit "$rc"
