#!/usr/bin/env bash
# 注意：该文件可被交互式 shell source；不要在这里 set -euo pipefail / set -u

# ---- project root ----
PROJECT_ROOT="$HOME/2025EFsfMRI"

# ---- raw input root ----
SRC_ROOT="$PROJECT_ROOT/Data/fmriData"

# ---- staging outputs ----
STAGE_ROOT="$PROJECT_ROOT/stage"
STAGE_DICOM="$STAGE_ROOT/dicom"
MANIFEST="$STAGE_ROOT/manifest.tsv"
DUPLICATES="$STAGE_ROOT/duplicates.tsv"
# 是否每次都重建 stage/dicom（建议保持 1）
CLEAN_STAGE_DICOM="${CLEAN_STAGE_DICOM:-1}"
# 遇到重复时是否直接退出（0=自动处理并记录；1=发现重复就停止）
STOP_ON_DUPLICATES="${STOP_ON_DUPLICATES:-0}"
# 可选：显式指定某些 sub+ses 取哪个目录（用于 SUB016 这种“已知应保留第二次”的场景）
# 文件格式：sub<TAB>ses<TAB>absolute_path
OVERRIDES_TSV="${OVERRIDES_TSV:-$STAGE_ROOT/overrides.tsv}"

# ---- BIDS outputs ----
BIDS_ROOT="$PROJECT_ROOT/bids"
LOGDIR="$PROJECT_ROOT/logs/heudiconv"

# ---- heuristic ----
HEURISTIC="$PROJECT_ROOT/code/heuristic/heuristic.py"

# ---- singularity/apptainer ----
SIF="$HOME/containers/heudiconv-1.3.4.sif"   # 改成你的容器路径
SING_BIN="${SING_BIN:-singularity}"            # 若是 apptainer：export SING_BIN=apptainer

# ---- concurrency ----
MAX_JOBS="${MAX_JOBS:-4}"

# ---- DICOM template (你的结构：session目录下还有两级目录，DICOM为 .IMA) ----
# staged: $STAGE_DICOM/sub-001/ses-TASK/<study>/<series>/*.IMA
# 用 */*/* 兜底，不依赖扩展名
DICOM_TEMPLATE="$STAGE_DICOM/sub-{subject}/ses-{session}/*/*/*"
