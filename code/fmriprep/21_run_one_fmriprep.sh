#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"

LABEL="$1"                 # 例如 001（不带 sub-）
FORCE="${2:-0}"            # 1=强制重跑（即使DONE也执行）

mkdir -p "$DERIV_ROOT" "$FS_SUBJECTS_DIR" "$WORK_ROOT" "$LOGDIR" \
         "$DONE_DIR" "$FAILED_DIR" "$RUNNING_DIR" "$LOCK_DIR"

SUB="sub-${LABEL}"
WORK_SUB="$WORK_ROOT/$SUB"
LOGFILE="$LOGDIR/${SUB}.log"

DONE_FLAG="$DONE_DIR/${SUB}.DONE"
FAIL_FLAG="$FAILED_DIR/${SUB}.FAILED"
RUN_FLAG="$RUNNING_DIR/${SUB}.RUNNING"
LOCK_PATH="$LOCK_DIR/${SUB}.lock"

# 已完成且不强制：跳过
if [ -f "$DONE_FLAG" ] && [ "$FORCE" != "1" ]; then
  echo "SKIP (DONE): $SUB"
  exit 0
fi

# 原子目录锁：避免同一被试并发重复跑
if ! mkdir "$LOCK_PATH" 2>/dev/null; then
  echo "SKIP (LOCKED): $SUB"
  exit 0
fi

cleanup_lock() { rmdir "$LOCK_PATH" 2>/dev/null || true; }
trap cleanup_lock EXIT

# 启动前状态
rm -f "$RUN_FLAG" "$DONE_FLAG" "$FAIL_FLAG"
echo "[`date '+%F %T'`] START $SUB (force=$FORCE)" >> "$LOGFILE"
touch "$RUN_FLAG"

# workdir 策略
if [ "${WIPE_WORKDIR_ON_START:-0}" = "1" ]; then
  rm -rf "$WORK_SUB"
fi
mkdir -p "$WORK_SUB"

# 参数：跳过重复校验
SKIP_OPT=()
if [ "${SKIP_BIDS_VALIDATION:-1}" = "1" ]; then
  SKIP_OPT+=(--skip-bids-validation)
fi

# 参数：CIFTI
CIFTI_OPT=()
if [ -n "${CIFTI_OUTPUT:-}" ]; then
  CIFTI_OPT+=(--cifti-output "$CIFTI_OUTPUT")
fi

# 执行 fmriprep
set +e
"$SING_BIN" run \
  -B "$BIDS_ROOT":"$BIDS_ROOT" \
  -B "$DERIV_ROOT":"$DERIV_ROOT" \
  -B "$FS_SUBJECTS_DIR":"$FS_SUBJECTS_DIR" \
  -B "$WORK_ROOT":"$WORK_ROOT" \
  -B "$BIDS_DB_DIR":"$BIDS_DB_DIR" \
  -B "$FS_LICENSE":"$FS_LICENSE" \
  "$FMRIPREP_SIF" \
    "$BIDS_ROOT" "$DERIV_ROOT" participant \
    --participant-label "$LABEL" \
    -w "$WORK_SUB" \
    --fs-license-file "$FS_LICENSE" \
    --fs-subjects-dir "$FS_SUBJECTS_DIR" \
    --bids-database-dir "$BIDS_DB_DIR" \
    --nthreads "$NTHREADS" \
    --omp-nthreads "$OMP_NTHREADS" \
    --mem_mb "$MEM_MB" \
    --output-spaces $OUTPUT_SPACES \
    "${CIFTI_OPT[@]}" \
    "${SKIP_OPT[@]}" \
    --stop-on-first-crash \
    --notrack \
  >> "$LOGFILE" 2>&1
rc=$?
set -e

rm -f "$RUN_FLAG"

if [ "$rc" -eq 0 ]; then
  touch "$DONE_FLAG"
  echo "[`date '+%F %T'`] DONE  $SUB" >> "$LOGFILE"

  # 成功后清理 workdir（释放空间）
  if [ "${CLEAN_WORK_ON_SUCCESS:-1}" = "1" ]; then
    rm -rf "$WORK_SUB"
    echo "[`date '+%F %T'`] CLEAN workdir $WORK_SUB" >> "$LOGFILE"
  fi
else
  touch "$FAIL_FLAG"
  echo "[`date '+%F %T'`] FAIL  $SUB (exit=$rc)" >> "$LOGFILE"
fi

exit "$rc"
