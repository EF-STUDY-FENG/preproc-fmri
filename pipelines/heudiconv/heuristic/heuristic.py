#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import re
from collections import defaultdict


def create_key(template, outtype=("nii.gz",), annotation_classes=None):
    if not template:
        raise ValueError("Template must be a valid format string")
    return (template, outtype, annotation_classes)


# ---------- IntendedFor auto-population ----------
# Use fmap filename `_acq-` tag for matching (bold/dwi, etc.); if multiple fmap groups exist, assign by closest time.
POPULATE_INTENDED_FOR_OPTS = {
    "matching_parameters": ["ModalityAcquisitionLabel"],
    "criterion": "Closest",
}

# ---------- BIDS keys ----------
# TASK session func: task-efbattery
bold_task = create_key(
    "{bids_subject_session_dir}/func/"
    "{bids_subject_session_prefix}_task-efbattery_run-{item:02d}_bold"
)

# REST session func: task-rest
bold_rest = create_key(
    "{bids_subject_session_dir}/func/"
    "{bids_subject_session_prefix}_task-rest_run-{item:02d}_bold"
)

# anat: keep ND only (exclude derived DIS*)
t1w = create_key(
    "{bids_subject_session_dir}/anat/"
    "{bids_subject_session_prefix}_acq-mprage_T1w"
)

# fmap for BOLD (GRE field mapping)
# IMPORTANT: do NOT include {subindex}; magnitude series contains 2 echoes (2x slices), dcm2niix splits into 2 NIfTIs.
# Let heudiconv auto-number to magnitude1/magnitude2.
fmap_mag_bold = create_key(
    "{bids_subject_session_dir}/fmap/"
    "{bids_subject_session_prefix}_acq-bold_run-{item:02d}_magnitude"
)
fmap_phasediff_bold = create_key(
    "{bids_subject_session_dir}/fmap/"
    "{bids_subject_session_prefix}_acq-bold_run-{item:02d}_phasediff"
)

# dwi: keep only main DWI (non-derived)
dwi_hardi = create_key(
    "{bids_subject_session_dir}/dwi/"
    "{bids_subject_session_prefix}_acq-hardi_dir-PA_run-{item:02d}_dwi"
)

# fmap for DWI (ABI1_fieldmap_hardi)
fmap_mag_dwi = create_key(
    "{bids_subject_session_dir}/fmap/"
    "{bids_subject_session_prefix}_acq-dwi_run-{item:02d}_magnitude"
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
    task_runs = {}   # run_number -> series_id
    rest_bolds = []  # series_ids (usually single)

    # fmap for bold
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
                    task_runs[_series_num(s.series_id)] = s.series_id
            continue

        # ---------- fmap: GRE field mapping for BOLD ----------
        if "gre_field_mapping" in prot or "gre_field_mapping" in desc:
            # dicominfo shows: Magnitude series_files ~ 2 * PhaseDiff series_files -> multi-echo magnitude in ONE series
            if "p" in itype:
                fmap_phase_bold_list.append(s.series_id)
            elif "m" in itype:
                fmap_mag_bold_list.append(s.series_id)
            continue

        # ---------- fmap: fieldmap_hardi for DWI ----------
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

    # --- write fmap for bold (PAIR mag <-> phasediff to keep run indices aligned) ---
    mags = sorted(fmap_mag_bold_list, key=_series_num)
    phs = sorted(fmap_phase_bold_list, key=_series_num)
    for mag_sid, ph_sid in zip(mags, phs):
        info[fmap_mag_bold].append(mag_sid)
        info[fmap_phasediff_bold].append(ph_sid)

    # --- write dwi + its fmap ---
    info[dwi_hardi].extend(sorted(dwi_list, key=_series_num))

    mags = sorted(fmap_mag_dwi_list, key=_series_num)
    phs = sorted(fmap_phase_dwi_list, key=_series_num)
    for mag_sid, ph_sid in zip(mags, phs):
        info[fmap_mag_dwi].append(mag_sid)
        info[fmap_phasediff_dwi].append(ph_sid)

    return info
