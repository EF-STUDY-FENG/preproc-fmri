#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/project.sh"
project_load "heudiconv" "$SCRIPT_DIR"

# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/core.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/state.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/container.sh"

SUB="${1:?sub required (e.g., 001)}"
SES="${2:?ses required (e.g., TASK/REST)}"
FORCE="${3:-0}"

JOB_ID="sub-${SUB}_ses-${SES}"
LOGFILE="$LOGDIR/${JOB_ID}.log"

ensure_dir "$BIDS_ROOT"
ensure_dir "$LOGDIR"

# Ensure manifest/staging exist (fail fast)
[[ -d "$STAGE_DICOM/sub-${SUB}/ses-${SES}" ]] || die "Staged DICOM missing: $STAGE_DICOM/sub-${SUB}/ses-${SES} (run: bash $SCRIPT_DIR/manifest.sh)"
[[ -s "$MANIFEST" ]] || log_warn "Manifest not found at $MANIFEST (you may want to run: bash $SCRIPT_DIR/manifest.sh)"

job_run "$JOB_ID" "$FORCE" "$LOGFILE" -- \
  run_container "$SIF" \
    "$STAGE_DICOM:$STAGE_DICOM" \
    "$BIDS_ROOT:$BIDS_ROOT" \
    "$HEURISTIC:$HEURISTIC" \
    -- \
      -d "$DICOM_TEMPLATE" \
      -s "$SUB" \
      -ss "$SES" \
      -f "$HEURISTIC" \
      -o "$BIDS_ROOT" \
      -c dcm2niix \
      -b
