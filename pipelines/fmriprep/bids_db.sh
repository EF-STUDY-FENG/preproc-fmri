#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/project.sh"
project_load "fmriprep" "$SCRIPT_DIR"

# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/core.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/container.sh"

ensure_dir "$BIDS_DB_DIR"

TOOLS_BIDS_DB="$TOOLS_ROOT/bids_db.py"
[[ -f "$TOOLS_BIDS_DB" ]] || die "Tool not found: $TOOLS_BIDS_DB"

if [[ "${RESET_BIDS_DB:-1}" == "1" ]]; then
  rm -rf "$BIDS_DB_DIR"
  ensure_dir "$BIDS_DB_DIR"
fi

# Note: run Python inside the container directly; do NOT use the image entrypoint.
exec_container "$FMRIPREP_SIF" \
  "$BIDS_ROOT:$BIDS_ROOT" \
  "$BIDS_DB_DIR:$BIDS_DB_DIR" \
  -- \
  python - "$BIDS_ROOT" "$BIDS_DB_DIR" \
    --index-metadata "${INDEX_METADATA:-1}" \
    --validate 1 \
    --reset 1 \
    <"$TOOLS_BIDS_DB"

log_info "OK: BIDS DB ready -> $BIDS_DB_DIR"
