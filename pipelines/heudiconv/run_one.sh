#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/bootstrap.sh"
bootstrap "heudiconv" "$SCRIPT_DIR"

# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/common.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/status.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/container.sh"

SUB="$1"   # e.g., 001
SES="$2"   # TASK or REST
FORCE="${3:-0}"  # 1=force rerun (run even if DONE)

ensure_dir "$BIDS_ROOT"
ensure_dir "$LOGDIR"
init_state_dirs

JOB_ID="sub-${SUB}_ses-${SES}"
LOGFILE="$LOGDIR/${JOB_ID}.log"

# DONE and not forced: skip
if is_done "$JOB_ID" && [ "$FORCE" != "1" ]; then
  log "SKIP (DONE): $JOB_ID"
  exit 0
fi

# Already running: skip
if is_running "$JOB_ID"; then
  log "SKIP (RUNNING): $JOB_ID"
  exit 0
fi

# Atomic directory lock: avoid duplicate concurrent runs
if ! acquire_lock "$JOB_ID"; then
  log "SKIP (LOCKED): $JOB_ID"
  exit 0
fi

trap 'release_lock "$JOB_ID"' EXIT

# Pre-run status
log "START $JOB_ID (force=$FORCE)"
mark_running "$JOB_ID"

set +e
run_container "$SIF" \
  "$STAGE_DICOM":"$STAGE_DICOM" \
  "$BIDS_ROOT":"$BIDS_ROOT" \
  "$HEURISTIC":"$HEURISTIC" \
  "$LOGDIR":"$LOGDIR" \
  -- \
    -d "$DICOM_TEMPLATE" \
    -s "$SUB" \
    -ss "$SES" \
    -f "$HEURISTIC" \
    -c dcm2niix \
    -b \
    -o "$BIDS_ROOT" \
    --overwrite \
  >> "$LOGFILE" 2>&1

rc=$?
set -e

if [ "$rc" -eq 0 ]; then
  log "DONE: $JOB_ID (rc=$rc)"
  mark_done "$JOB_ID"
else
  log "FAILED: $JOB_ID (rc=$rc)"
  mark_failed "$JOB_ID"
fi

exit "$rc"
