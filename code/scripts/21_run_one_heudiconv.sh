#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"

SUB="$1"   # 例如 001
SES="$2"   # TASK 或 REST

mkdir -p "$BIDS_ROOT" "$LOGDIR"

LOGFILE="$LOGDIR/sub-${SUB}_ses-${SES}.log"
echo "[`date '+%F %T'`] START sub-${SUB} ses-${SES}" >> "$LOGFILE"

"$SING_BIN" run \
  -B "$STAGE_DICOM":"$STAGE_DICOM" \
  -B "$BIDS_ROOT":"$BIDS_ROOT" \
  -B "$HEURISTIC":"$HEURISTIC" \
  -B "$LOGDIR":"$LOGDIR" \
  "$SIF" \
    -d "$DICOM_TEMPLATE" \
    -s "$SUB" \
    -ss "$SES" \
    -f "$HEURISTIC" \
    -c dcm2niix \
    -b \
    -o "$BIDS_ROOT" \
    --overwrite \
  >> "$LOGFILE" 2>&1

echo "[`date '+%F %T'`] DONE  sub-${SUB} ses-${SES}" >> "$LOGFILE"
