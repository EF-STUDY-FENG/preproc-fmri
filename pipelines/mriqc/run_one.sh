#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/project.sh"
project_load "mriqc" "$SCRIPT_DIR"

# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/core.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/state.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/container.sh"

LABEL="${1:?label required (e.g., 001)}"
FORCE="${2:-0}"

ensure_dir "$DERIV_ROOT"
ensure_dir "$WORK_ROOT"
ensure_dir "$LOGDIR"
init_state_dirs

SUB="sub-${LABEL}"
WORK_SUB="$WORK_ROOT/$SUB"
LOGFILE="$LOGDIR/${SUB}.log"

# Workdir policy
if [[ "${WIPE_WORKDIR_ON_START:-0}" == "1" ]]; then
  rm -rf "$WORK_SUB"
fi
mkdir -p "$WORK_SUB"

# Build optional args
NO_SUB_OPT=()
[[ "${NO_SUB:-1}" == "1" ]] && NO_SUB_OPT+=(--no-sub)

BIDS_DB_OPT=()
if [[ "${MRIQC_USE_BIDS_DB:-1}" == "1" ]]; then
  ensure_dir "$BIDS_DB_DIR"
  BIDS_DB_OPT+=(--bids-database-dir "$BIDS_DB_DIR")
  [[ "${MRIQC_BIDS_DB_WIPE:-0}" == "1" ]] && BIDS_DB_OPT+=(--bids-database-wipe)
fi

MODALITIES_OPT=()
if [[ -n "${MRIQC_MODALITIES:-}" ]]; then
  read -r -a _MODS_ARR <<<"${MRIQC_MODALITIES}"
  (( ${#_MODS_ARR[@]} > 0 )) && MODALITIES_OPT=(-m "${_MODS_ARR[@]}")
fi

BINDS=(
  "$BIDS_ROOT:$BIDS_ROOT"
  "$DERIV_ROOT:$DERIV_ROOT"
  "$WORK_ROOT:$WORK_ROOT"
)
if [[ "${MRIQC_USE_BIDS_DB:-1}" == "1" ]]; then
  BINDS+=("$BIDS_DB_DIR:$BIDS_DB_DIR")
fi

job_run "$SUB" "$FORCE" "$LOGFILE" -- \
  run_container "$MRIQC_SIF" \
    "${BINDS[@]}" \
    -- \
      "$BIDS_ROOT" "$DERIV_ROOT" participant \
      --participant-label "$LABEL" \
      -w "$WORK_SUB" \
      --nprocs "$NPROCS" \
      --omp-nthreads "$OMP_NTHREADS" \
      --mem_gb "$MEM_GB" \
      "${MODALITIES_OPT[@]}" \
      "${BIDS_DB_OPT[@]}" \
      "${NO_SUB_OPT[@]}" \
      --notrack \
      ${MRIQC_EXTRA_ARGS:-}
rc=$?

if [[ "$rc" -eq 0 && "${CLEAN_WORK_ON_SUCCESS:-1}" == "1" ]]; then
  rm -rf "$WORK_SUB" || true
  log_info "CLEAN workdir $WORK_SUB"
fi

exit "$rc"
