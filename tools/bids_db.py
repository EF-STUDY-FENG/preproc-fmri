#!/usr/bin/env python3
"""Build (or update) a PyBIDS database for a BIDS directory.

This is typically executed *inside* the fMRIPrep container where PyBIDS is
available. The bash wrapper feeds this script via stdin:

  python - < tools/bids_db.py

so we avoid bind-mounting the repository into the container.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence


def _int01(value: str) -> int:
    try:
        iv = int(value)
    except Exception as e:
        raise argparse.ArgumentTypeError(f"expected 0/1 int, got: {value!r}") from e
    if iv not in (0, 1):
        raise argparse.ArgumentTypeError(f"expected 0/1 int, got: {value!r}")
    return iv


def main(argv: Sequence[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Build PyBIDS DB")
    p.add_argument("bids_root", help="BIDS root directory")
    p.add_argument("db_dir", help="PyBIDS database directory")
    p.add_argument("--index-metadata", type=_int01, default=1)
    p.add_argument("--validate", type=_int01, default=1)
    p.add_argument("--reset", type=_int01, default=1)

    args = p.parse_args(argv)

    bids_root = Path(args.bids_root)
    db_dir = Path(args.db_dir)
    db_dir.mkdir(parents=True, exist_ok=True)

    # Import inside main so the script can exist on host without PyBIDS.
    from bids import BIDSLayout

    try:
        from bids.layout import BIDSLayoutIndexer
    except Exception:
        from bids.layout.index import BIDSLayoutIndexer

    index_metadata = bool(args.index_metadata)
    validate = bool(args.validate)
    reset_database = bool(args.reset)

    indexer = BIDSLayoutIndexer(index_metadata=index_metadata)
    layout = BIDSLayout(
        str(bids_root),
        database_path=str(db_dir),
        reset_database=reset_database,
        indexer=indexer,
        validate=validate,
    )

    subs = layout.get_subjects()
    print("PyBIDS DB built at:", str(db_dir))
    print("index_metadata:", index_metadata)
    print("validate:", validate)
    print("reset_database:", reset_database)
    print("N_subjects:", len(subs))
    print("First10:", subs[:10])

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
