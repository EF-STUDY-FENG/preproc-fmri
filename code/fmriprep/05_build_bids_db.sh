#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"

mkdir -p "$DERIV_ROOT" "$FS_SUBJECTS_DIR" "$WORK_ROOT" "$LOGDIR" "$BIDS_DB_DIR"

if [ "${RESET_BIDS_DB:-1}" = "1" ]; then
  rm -rf "$BIDS_DB_DIR"
  mkdir -p "$BIDS_DB_DIR"
fi

# 注意：用 exec 调用容器内 python；不要用 run（run 通常是 fmriprep 入口）
"$SING_BIN" exec \
  -B "$BIDS_ROOT":"$BIDS_ROOT" \
  -B "$BIDS_DB_DIR":"$BIDS_DB_DIR" \
  "$FMRIPREP_SIF" \
  python - <<PY
import os
from bids import BIDSLayout

# PyBIDS 新版本要求：显式构造 BIDSLayoutIndexer，而不是把 index_metadata 作为 kwargs 传给 BIDSLayout
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

echo "OK: BIDS DB ready -> $BIDS_DB_DIR"
