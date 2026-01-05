#!/usr/bin/env bash
# config only; do NOT set -euo pipefail here

PROJECT_ROOT="$HOME/2025EFsfMRI"

# ---- inputs ----
BIDS_ROOT="$PROJECT_ROOT/bids"

# ---- outputs ----
DERIV_ROOT="$PROJECT_ROOT/derivatives/fmriprep"
FS_SUBJECTS_DIR="$PROJECT_ROOT/derivatives/freesurfer"

# ---- work & logs ----
WORK_ROOT="$PROJECT_ROOT/work/fmriprep"
BIDS_DB_DIR="$PROJECT_ROOT/work/pybids_db"
PARTICIPANTS_TSV="$PROJECT_ROOT/work/fmriprep_participants.tsv"
LOGDIR="$PROJECT_ROOT/logs/fmriprep"

# ---- state files (DONE/FAILED/RUNNING/LOCK) ----
STATE_DIR="$LOGDIR/state"
DONE_DIR="$STATE_DIR/done"
FAILED_DIR="$STATE_DIR/failed"
RUNNING_DIR="$STATE_DIR/running"
LOCK_DIR="$STATE_DIR/lock"

# ---- container ----
FMRIPREP_SIF="$HOME/containers/fmriprep-25.2.3.sif"
SING_BIN="${SING_BIN:-singularity}"   # 若用 apptainer：export SING_BIN=apptainer

# ---- FreeSurfer license ----
FS_LICENSE="$PROJECT_ROOT/license.txt"

# ---- concurrency ----
MAX_JOBS="${MAX_JOBS:-2}"

# ---- per-job resources ----
NTHREADS="${NTHREADS:-8}"
OMP_NTHREADS="${OMP_NTHREADS:-4}"
MEM_MB="${MEM_MB:-32000}"

# ---- BIDS DB build behavior ----
RESET_BIDS_DB="${RESET_BIDS_DB:-1}"     # 1=建库前清空重建（BIDS更新后建议=1）
INDEX_METADATA="${INDEX_METADATA:-1}"   # 1=索引 metadata（更全）；0=更快但信息少

# ---- output spaces ----
# 若未来计划复用 anat fast-track 且使用 --cifti-output 等高级输出，建议包含 MNI152NLin6Asym。:contentReference[oaicite:2]{index=2}
OUTPUT_SPACES="${OUTPUT_SPACES:-MNI152NLin2009cAsym:res-2 MNI152NLin6Asym:res-2 T1w}"

# ---- CIFTI output ----
# 91k（默认、推荐）或 170k（更高分辨率、更耗时/更占空间）:contentReference[oaicite:3]{index=3}
CIFTI_OUTPUT="${CIFTI_OUTPUT:-91k}"     # 设为空字符串可禁用：export CIFTI_OUTPUT=

# ---- validation strategy ----
# 建库步骤已 validate=True，因此每个 participant 作业通常可跳过重复校验
SKIP_BIDS_VALIDATION="${SKIP_BIDS_VALIDATION:-1}"

# ---- cleanup behavior ----
CLEAN_WORK_ON_SUCCESS="${CLEAN_WORK_ON_SUCCESS:-1}"  # 成功则删 work/sub-XXX
WIPE_WORKDIR_ON_START="${WIPE_WORKDIR_ON_START:-0}"  # 每次启动前清空该被试 workdir（更稳但更慢）

# ---- queue mode default ----
QUEUE_MODE_DEFAULT="${QUEUE_MODE_DEFAULT:-pending}"   # pending|failed|all
