#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/project.sh"
project_load "mriqc" "$SCRIPT_DIR"

# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/core.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/container.sh"

ensure_dir "$DERIV_ROOT"
ensure_dir "$WORK_ROOT"
ensure_dir "$LOGDIR"

LOGFILE="$LOGDIR/group.log"
WORK_GROUP="$WORK_ROOT/group"
mkdir -p "$WORK_GROUP"

BIDS_DB_OPT=()
if [[ "${MRIQC_USE_BIDS_DB:-1}" == "1" ]]; then
  ensure_dir "$BIDS_DB_DIR"
  BIDS_DB_OPT+=(--bids-database-dir "$BIDS_DB_DIR")
  [[ "${MRIQC_BIDS_DB_WIPE:-0}" == "1" ]] && BIDS_DB_OPT+=(--bids-database-wipe)
fi

NO_SUB_OPT=()
[[ "${NO_SUB:-1}" == "1" ]] && NO_SUB_OPT+=(--no-sub)

BINDS=(
  "$BIDS_ROOT:$BIDS_ROOT"
  "$DERIV_ROOT:$DERIV_ROOT"
  "$WORK_ROOT:$WORK_ROOT"
)
if [[ "${MRIQC_USE_BIDS_DB:-1}" == "1" ]]; then
  BINDS+=("$BIDS_DB_DIR:$BIDS_DB_DIR")
fi

# Group level typically requires participant outputs already present in output_dir.
run_container "$MRIQC_SIF" \
  "${BINDS[@]}" \
  -- \
    "$BIDS_ROOT" "$DERIV_ROOT" group \
    -w "$WORK_GROUP" \
    --nprocs "$NPROCS" \
    --omp-nthreads "$OMP_NTHREADS" \
    --mem_gb "$MEM_GB" \
    "${BIDS_DB_OPT[@]}" \
    "${NO_SUB_OPT[@]}" \
    --notrack \
    ${MRIQC_EXTRA_ARGS:-} \
  >>"$LOGFILE" 2>&1

printf 'OK: MRIQC group report -> %s\n' "$DERIV_ROOT" >&2
