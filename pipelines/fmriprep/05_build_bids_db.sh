#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/bootstrap.sh"
bootstrap "fmriprep" "$SCRIPT_DIR"

# shellcheck disable=SC1091
source "$LIB_ROOT/common.sh"
# shellcheck disable=SC1091
source "$LIB_ROOT/container.sh"

ensure_dir "$DERIV_ROOT"
ensure_dir "$FS_SUBJECTS_DIR"
ensure_dir "$WORK_ROOT"
ensure_dir "$LOGDIR"
ensure_dir "$BIDS_DB_DIR"

if [ "${RESET_BIDS_DB:-1}" = "1" ]; then
  rm -rf "$BIDS_DB_DIR"
  mkdir -p "$BIDS_DB_DIR"
fi

# Note: use exec to run Python inside the container; do not use "run" (typically the fmriprep entrypoint)
exec_container "$FMRIPREP_SIF" \
  "$BIDS_ROOT":"$BIDS_ROOT" \
  "$BIDS_DB_DIR":"$BIDS_DB_DIR" \
  -- \
  python - <<PY
import os
from bids import BIDSLayout

# Newer PyBIDS requires constructing BIDSLayoutIndexer explicitly (instead of passing index_metadata via kwargs)
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
    validate=True
)

subs = layout.get_subjects()
print("PyBIDS DB built at:", db_dir)
print("index_metadata:", index_metadata)
print("N_subjects:", len(subs))
print("First10:", subs[:10])
PY

log "OK: BIDS DB ready -> $BIDS_DB_DIR"
