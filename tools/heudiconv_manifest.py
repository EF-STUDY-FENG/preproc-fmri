#!/usr/bin/env python3
"""Build a heudiconv staging tree and manifest.

This script scans a raw DICOM directory tree (directory-per-subject/session),
selects one directory per (sub, ses) key (default: newest mtime), then:
  1) creates symlinks under <stage_dicom>/sub-XXX/ses-SES -> <raw_dir>
  2) writes a 2-column TSV manifest: <sub3>\t<ses>
  3) writes a duplicates/decision TSV for auditability

It supports a simple overrides TSV with 3 columns:
  sub<TAB>ses<TAB>path

By default, an override path must also appear during the scan (fail-fast against typos).
You can relax that with --allow-override-outside-scan.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple


SUB_RE = re.compile(r"_SUB(\d+)_")

SES_MAP = {
    "REST": "REST",
    "rest": "REST",
    "TASK": "TASK",
    "task": "TASK",
    "G105": "TASK",
    "g105": "TASK",
}


@dataclass(frozen=True)
class Candidate:
    sub3: str
    ses: str
    path: Path
    mtime: int


def _sub3_from_raw(sub_raw: str) -> str:
    # Strip leading zeros safely via base-10 int; keep 3 digits.
    return f"{int(sub_raw, 10):03d}"


def read_overrides_tsv(path: Optional[Path]) -> Dict[Tuple[str, str], Path]:
    overrides: Dict[Tuple[str, str], Path] = {}
    if not path:
        return overrides
    if not path.exists():
        return overrides

    with path.open("r", encoding="utf-8") as f:
        for ln, line in enumerate(f, 1):
            line = line.rstrip("\n").rstrip("\r")
            if not line or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                raise ValueError(f"Overrides TSV line {ln}: expected 3 columns, got {len(parts)}")
            sub, ses, p = parts[0].strip(), parts[1].strip(), parts[2].strip()
            if not (sub and ses and p):
                continue
            sub3 = _sub3_from_raw(sub)
            key = (sub3, ses)
            rp = Path(p).expanduser().resolve()
            if not rp.is_dir():
                raise FileNotFoundError(f"Override path not found: sub={sub3} ses={ses} path={rp}")
            overrides[key] = rp
    return overrides


def scan_candidates(src_root: Path, glob_pat: str) -> Tuple[List[Candidate], List[str]]:
    """Return candidates and skip messages."""
    skips: List[str] = []
    cands: List[Candidate] = []

    for d in sorted(src_root.glob(glob_pat)):
        if not d.is_dir():
            continue
        base = d.name

        m = SUB_RE.search(base)
        if not m:
            skips.append(f"SKIP(no SUB): {base}")
            continue
        sub3 = _sub3_from_raw(m.group(1))

        suf = base.split("_")[-1]
        ses = SES_MAP.get(suf)
        if not ses:
            skips.append(f"SKIP(unknown suffix): {base}")
            continue

        rp = d.resolve()
        try:
            mtime = int(rp.stat().st_mtime)
        except Exception:
            mtime = 0
        cands.append(Candidate(sub3=sub3, ses=ses, path=rp, mtime=mtime))

    return cands, skips


def choose_best(
    candidates: List[Candidate],
    overrides: Dict[Tuple[str, str], Path],
    allow_override_outside_scan: bool,
) -> Tuple[Dict[Tuple[str, str], Candidate], List[str]]:
    """Pick one candidate per key; return chosen map and decision log lines."""

    decisions: List[str] = []
    best: Dict[Tuple[str, str], Candidate] = {}

    # Pre-index by key
    by_key: Dict[Tuple[str, str], List[Candidate]] = {}
    for c in candidates:
        by_key.setdefault((c.sub3, c.ses), []).append(c)

    # Enforce overrides: if override exists, accept only override path.
    for key, cand_list in by_key.items():
        if key not in overrides:
            continue
        override_path = overrides[key]
        override_real = override_path.resolve()

        matched: Optional[Candidate] = None
        for c in cand_list:
            if c.path.resolve() == override_real:
                matched = c
            else:
                decisions.append(
                    f"{key[0]}\t{key[1]}\tDISCARDED_BY_OVERRIDE\t{c.path}\t{override_real}"
                )

        if matched is None:
            if allow_override_outside_scan:
                # Create a synthetic candidate.
                mtime = int(override_real.stat().st_mtime)
                matched = Candidate(sub3=key[0], ses=key[1], path=override_real, mtime=mtime)
                decisions.append(
                    f"{key[0]}\t{key[1]}\tOVERRIDE_OUTSIDE_SCAN\tNA\t{override_real}"
                )
            else:
                raise RuntimeError(
                    f"Override specified but not found during scan: sub={key[0]} ses={key[1]} path={override_real}"
                )

        best[key] = matched

    # Non-override keys: pick newest by mtime (ties -> later path string order)
    for key, cand_list in by_key.items():
        if key in overrides:
            continue

        # Sort by (mtime, path) and pick last
        cand_list_sorted = sorted(cand_list, key=lambda c: (c.mtime, str(c.path)))
        chosen = cand_list_sorted[-1]
        best[key] = chosen

        # Record decisions when duplicates exist
        if len(cand_list_sorted) > 1:
            for c in cand_list_sorted[:-1]:
                decisions.append(
                    f"{key[0]}\t{key[1]}\tDISCARDED_OLDER\t{c.path}\t{chosen.path}\told_mtime={c.mtime}\tnew_mtime={chosen.mtime}"
                )
            decisions.append(
                f"{key[0]}\t{key[1]}\tCHOSEN_NEWEST\t{chosen.path}\tNA\tmtime={chosen.mtime}"
            )

    # Overrides with keys not present in scan
    for key, override_path in overrides.items():
        if key in best:
            continue
        override_real = override_path.resolve()
        if not allow_override_outside_scan:
            raise RuntimeError(
                f"Override specified but key not present in scan: sub={key[0]} ses={key[1]} path={override_real}"
            )
        mtime = int(override_real.stat().st_mtime)
        best[key] = Candidate(sub3=key[0], ses=key[1], path=override_real, mtime=mtime)
        decisions.append(f"{key[0]}\t{key[1]}\tOVERRIDE_ONLY\tNA\t{override_real}\tmtime={mtime}")

    return best, decisions


def write_stage_and_manifest(
    best: Dict[Tuple[str, str], Candidate],
    stage_dicom: Path,
    manifest_tsv: Path,
    clean_stage: bool,
) -> None:
    if clean_stage and stage_dicom.exists():
        shutil.rmtree(stage_dicom)
    stage_dicom.mkdir(parents=True, exist_ok=True)

    keys_sorted = sorted(best.keys(), key=lambda k: (k[0], k[1]))

    manifest_tsv.parent.mkdir(parents=True, exist_ok=True)
    with manifest_tsv.open("w", encoding="utf-8") as f:
        for sub3, ses in keys_sorted:
            c = best[(sub3, ses)]
            link = stage_dicom / f"sub-{sub3}" / f"ses-{ses}"
            link.parent.mkdir(parents=True, exist_ok=True)
            if link.exists() or link.is_symlink():
                link.unlink()
            os.symlink(str(c.path), str(link))
            f.write(f"{sub3}\t{ses}\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src-root", required=True, type=Path)
    ap.add_argument("--glob", default="TJNU_FJJ_EF_SUB*", help="glob pattern under src-root")
    ap.add_argument("--stage-dicom", required=True, type=Path)
    ap.add_argument("--manifest", required=True, type=Path)
    ap.add_argument("--duplicates", required=True, type=Path)
    ap.add_argument("--overrides", default=None, type=Path)
    ap.add_argument("--clean-stage", action="store_true")
    ap.add_argument("--stop-on-duplicates", action="store_true")
    ap.add_argument("--allow-override-outside-scan", action="store_true")

    args = ap.parse_args()

    src_root = args.src_root.expanduser().resolve()
    if not src_root.is_dir():
        raise NotADirectoryError(f"src-root not found: {src_root}")

    overrides = read_overrides_tsv(args.overrides)
    candidates, skips = scan_candidates(src_root, args.glob)

    best, decisions = choose_best(
        candidates,
        overrides,
        allow_override_outside_scan=args.allow_override_outside_scan,
    )

    write_stage_and_manifest(best, args.stage_dicom, args.manifest, clean_stage=args.clean_stage)

    args.duplicates.parent.mkdir(parents=True, exist_ok=True)
    with args.duplicates.open("w", encoding="utf-8") as f:
        for s in skips:
            f.write(f"# {s}\n")
        for d in decisions:
            f.write(d + "\n")

    n = len(best)
    print(f"OK: manifest -> {args.manifest} (N={n})")
    if decisions:
        print(f"INFO: decisions -> {args.duplicates} (N={len(decisions)})")
        if args.stop_on_duplicates:
            raise SystemExit("STOP_ON_DUPLICATES enabled and decisions were recorded.")

    # Small sample for sanity
    print("Sample staged entries:")
    for (sub3, ses) in sorted(best.keys())[:5]:
        link = args.stage_dicom / f"sub-{sub3}" / f"ses-{ses}"
        tgt = link.resolve() if link.exists() else Path("NA")
        print(f"  sub-{sub3} ses-{ses} -> {tgt}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
