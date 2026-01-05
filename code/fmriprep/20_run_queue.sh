#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"

MODE="${1:-$QUEUE_MODE_DEFAULT}"    # pending|failed|all
FORCE="${2:-0}"                    # 1=强制重跑（传给 run_one）

mkdir -p "$DERIV_ROOT" "$FS_SUBJECTS_DIR" "$WORK_ROOT" "$LOGDIR" \
         "$DONE_DIR" "$FAILED_DIR" "$RUNNING_DIR" "$LOCK_DIR"

if [ ! -s "$PARTICIPANTS_TSV" ]; then
  echo "ERROR: participants list missing: $PARTICIPANTS_TSV" >&2
  echo "Run: bash $SCRIPT_DIR/10_make_participants.sh" >&2
  exit 1
fi

RUN_ONE="$SCRIPT_DIR/21_run_one_fmriprep.sh"
chmod +x "$RUN_ONE" >/dev/null 2>&1 || true

TODO_TSV="$PROJECT_ROOT/work/todo_fmriprep_${MODE}.tsv"
: > "$TODO_TSV"

while IFS=$'\t' read -r _sub label; do
  [ -n "${label:-}" ] || continue
  SUB="sub-${label}"

  DONE_FLAG="$DONE_DIR/${SUB}.DONE"
  FAIL_FLAG="$FAILED_DIR/${SUB}.FAILED"
  LOCK_PATH="$LOCK_DIR/${SUB}.lock"

  # 已锁：跳过（避免重复启动）
  [ -d "$LOCK_PATH" ] && continue

  case "$MODE" in
    pending)
      [ -f "$DONE_FLAG" ] && continue
      ;;
    failed)
      [ -f "$FAIL_FLAG" ] || continue
      ;;
    all)
      # 全部进入；DONE 会在 run_one 内跳过，除非 FORCE=1
      ;;
    *)
      echo "ERROR: unknown mode: $MODE (use pending|failed|all)" >&2
      exit 2
      ;;
  esac

  printf "%s\t%s\n" "$_sub" "$label" >> "$TODO_TSV"
done < "$PARTICIPANTS_TSV"

N_TODO="$(wc -l < "$TODO_TSV" | tr -d ' ')"
N_ALL="$(wc -l < "$PARTICIPANTS_TSV" | tr -d ' ')"

echo "Participants total: $N_ALL"
echo "Queue mode: $MODE (force=$FORCE)"
echo "To run: $N_TODO"
echo "TODO list -> $TODO_TSV"
echo "Resources: MAX_JOBS=$MAX_JOBS; NTHREADS=$NTHREADS; OMP_NTHREADS=$OMP_NTHREADS; MEM_MB=$MEM_MB"
echo "CIFTI: CIFTI_OUTPUT=${CIFTI_OUTPUT:-<disabled>}"
echo "Work cleanup: CLEAN_WORK_ON_SUCCESS=$CLEAN_WORK_ON_SUCCESS"

if [ "$N_TODO" -eq 0 ]; then
  echo "Nothing to do."
  exit 0
fi

# 优先用 GNU parallel（有 joblog）；否则用 bash 队列
if command -v parallel >/dev/null 2>&1; then
  parallel -j "$MAX_JOBS" --colsep '\t' --eta \
    --joblog "$LOGDIR/joblog_${MODE}.tsv" \
    "$RUN_ONE {2} $FORCE" \
    :::: "$TODO_TSV"
  echo "OK: joblog -> $LOGDIR/joblog_${MODE}.tsv"
  exit 0
fi

active_jobs () { jobs -rp | wc -l | tr -d ' '; }

while IFS=$'\t' read -r _sub label; do
  while (( $(active_jobs) >= MAX_JOBS )); do
    wait -n
  done
  "$RUN_ONE" "$label" "$FORCE" &
done < "$TODO_TSV"

wait
echo "OK: queue finished."
