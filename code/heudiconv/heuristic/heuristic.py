#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import re
from collections import defaultdict


def create_key(template, outtype=("nii.gz",), annotation_classes=None):
    if not template:
        raise ValueError("Template must be a valid format string")
    return (template, outtype, annotation_classes)


# ---------- IntendedFor auto-population ----------
# ModalityAcquisitionLabel：根据 fmap 文件名中的 _acq- 标签推断匹配到 func/dwi 等模态。:contentReference[oaicite:5]{index=5}
# criterion=Closest：当同一 session 有多组 fmap（如 TASK session 的前后两组）时，按时间接近原则分配。:contentReference[oaicite:6]{index=6}
POPULATE_INTENDED_FOR_OPTS = {
    "matching_parameters": ["ModalityAcquisitionLabel"],
    "criterion": "Closest",
}

# ---------- BIDS keys (robust for optional sessions) ----------
# TASK session 的 func：task-efbattery
bold_task = create_key(
    "{bids_subject_session_dir}/func/"
    "{bids_subject_session_prefix}_task-efbattery_run-{item:02d}_bold"
)

# REST session 的 func：task-rest（即使静息态也需要 task 实体）:contentReference[oaicite:7]{index=7}
bold_rest = create_key(
    "{bids_subject_session_dir}/func/"
    "{bids_subject_session_prefix}_task-rest_run-{item:02d}_bold"
)

# anat：keep nd only (exclude gdc)
t1w = create_key(
    "{bids_subject_session_dir}/anat/"
    "{bids_subject_session_prefix}_acq-mprage_T1w"
)

# fmap for BOLD (GRE field mapping) — 用 _acq-bold 以便 IntendedFor 匹配到 func :contentReference[oaicite:8]{index=8}
fmap_mag_bold = create_key(
    "{bids_subject_session_dir}/fmap/"
    "{bids_subject_session_prefix}_acq-bold_run-{item:02d}_magnitude{subindex}"
)
fmap_phasediff_bold = create_key(
    "{bids_subject_session_dir}/fmap/"
    "{bids_subject_session_prefix}_acq-bold_run-{item:02d}_phasediff"
)

# dwi：仅保留主 DWI（非 DERIVED），这里加 run 以便未来扩展
dwi_hardi = create_key(
    "{bids_subject_session_dir}/dwi/"
    "{bids_subject_session_prefix}_acq-hardi_dir-PA_run-{item:02d}_dwi"
)

# fmap for DWI — 用 _acq-dwi 以便 IntendedFor 匹配到 dwi :contentReference[oaicite:9]{index=9}
fmap_mag_dwi = create_key(
    "{bids_subject_session_dir}/fmap/"
    "{bids_subject_session_prefix}_acq-dwi_run-{item:02d}_magnitude{subindex}"
)
fmap_phasediff_dwi = create_key(
    "{bids_subject_session_dir}/fmap/"
    "{bids_subject_session_prefix}_acq-dwi_run-{item:02d}_phasediff"
)


def _series_num(series_id: str) -> int:
    """e.g., '6-sms_bold_2mm_run1' -> 6; used to sort by acquisition order."""
    try:
        return int(series_id.split("-", 1)[0])
    except Exception:
        return 10**9


def _is_derived(seq) -> bool:
    """Robust derived detection across heudiconv versions."""
    v = getattr(seq, "is_derived", None)
    if v is not None:
        return bool(v)
    itype = tuple(x.lower() for x in (getattr(seq, "image_type", None) or ()))
    return "derived" in itype


def infotodict(seqinfos):
    info = defaultdict(list)

    # func
    task_runs = {}         # run_number -> series_id
    rest_bolds = []        # series_ids (usually single)

    # fmap for bold (TASK has 2 groups; REST has 1 group)
    fmap_mag_bold_list = []
    fmap_phase_bold_list = []

    # dwi + its fmap
    dwi_list = []
    fmap_mag_dwi_list = []
    fmap_phase_dwi_list = []

    for s in seqinfos:
        prot = (getattr(s, "protocol_name", "") or "").lower()
        desc = (getattr(s, "series_description", "") or "").lower()
        itype = tuple(x.lower() for x in (getattr(s, "image_type", None) or ()))
        dim4 = int(getattr(s, "dim4", 1) or 1)

        # ---------- anat: T1 MPRAGE ----------
        if ("mprage" in prot) or ("t1_mprage" in prot):
            if "nd" in itype:
                info[t1w].append(s.series_id)
            continue

        # ---------- func: BOLD ----------
        if ("bold" in prot or "bold" in desc) and ("mosaic" in itype) and (dim4 > 1):
            if "rest" in prot or "rest" in desc:
                rest_bolds.append(s.series_id)
            else:
                m = re.search(r"run(\d+)", prot) or re.search(r"run(\d+)", desc)
                if m:
                    task_runs[int(m.group(1))] = s.series_id
                else:
                    # fallback: acquisition order as pseudo-run
                    task_runs[_series_num(s.series_id)] = s.series_id
            continue

        # ---------- fmap: GRE field mapping for BOLD ----------
        if "gre_field_mapping" in prot or "gre_field_mapping" in desc:
            if "p" in itype:
                fmap_phase_bold_list.append(s.series_id)
            elif "m" in itype:
                fmap_mag_bold_list.append(s.series_id)
            continue

        # ---------- fmap: hardi fieldmap (for DWI) ----------
        if "fieldmap_hardi" in prot or "fieldmap_hardi" in desc:
            if "p" in itype:
                fmap_phase_dwi_list.append(s.series_id)
            elif "m" in itype:
                fmap_mag_dwi_list.append(s.series_id)
            continue

        # ---------- dwi: keep only non-derived main series ----------
        if ("diff" in prot or "diff" in desc) and ("hardi" in prot or "hardi" in desc):
            if (not _is_derived(s)) and (dim4 > 1):
                dwi_list.append(s.series_id)
            continue

    # --- write func ---
    for r in sorted(task_runs.keys()):
        info[bold_task].append(task_runs[r])

    for sid in sorted(rest_bolds, key=_series_num):
        info[bold_rest].append(sid)

    # --- write fmap for bold (run order by series number) ---
    info[fmap_mag_bold].extend(sorted(fmap_mag_bold_list, key=_series_num))
    info[fmap_phasediff_bold].extend(sorted(fmap_phase_bold_list, key=_series_num))

    # --- write dwi + its fmap ---
    info[dwi_hardi].extend(sorted(dwi_list, key=_series_num))
    info[fmap_mag_dwi].extend(sorted(fmap_mag_dwi_list, key=_series_num))
    info[fmap_phasediff_dwi].extend(sorted(fmap_phase_dwi_list, key=_series_num))

    return info
