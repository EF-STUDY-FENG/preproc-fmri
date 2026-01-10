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

if [[ "${RESET_BIDS_DB:-1}" == "1" ]]; then
  rm -rf "$BIDS_DB_DIR"
  ensure_dir "$BIDS_DB_DIR"
fi

# Note: run Python inside the container directly; do NOT use the image entrypoint.
exec_container "$FMRIPREP_SIF" \
  "$BIDS_ROOT:$BIDS_ROOT" \
  "$BIDS_DB_DIR:$BIDS_DB_DIR" \
  -- \
  python - <<PY
from bids import BIDSLayout

try:
    from bids.layout import BIDSLayoutIndexer
except Exception:
    from bids.layout.index import BIDSLayoutIndexer

bids_root = "$BIDS_ROOT"
db_dir = "$BIDS_DB_DIR"
index_metadata = bool(int("$INDEX_METADATA"))

indexer = BIDSLayoutIndexer(index_metadata=index_metadata)
layout = BIDSLayout(
    bids_root,
    database_path=db_dir,
    reset_database=True,
    indexer=indexer,
    validate=True,
)
subs = layout.get_subjects()
print("PyBIDS DB built at:", db_dir)
print("index_metadata:", index_metadata)
print("N_subjects:", len(subs))
print("First10:", subs[:10])
PY

log_info "OK: BIDS DB ready -> $BIDS_DB_DIR"
