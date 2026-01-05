#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"

mkdir -p "$LOGDIR" "$BIDS_ROOT"

if [ ! -s "$MANIFEST" ]; then
  echo "ERROR: manifest missing or empty: $MANIFEST" >&2
  echo "Run: bash $SCRIPT_DIR/10_make_stage.sh" >&2
  exit 1
fi

RUN_ONE="$SCRIPT_DIR/21_run_one_heudiconv.sh"
if [ ! -x "$RUN_ONE" ]; then
  chmod +x "$RUN_ONE"
fi

echo "Queue start: MAX_JOBS=$MAX_JOBS"
echo "Manifest: $MANIFEST"

# 优先使用 GNU parallel；若没有则退化为 bash 原生队列
if command -v parallel >/dev/null 2>&1; then
  parallel -j "$MAX_JOBS" --colsep '\t' --eta \
    --joblog "$LOGDIR/joblog.tsv" \
    "$RUN_ONE {1} {2}" \
    :::: "$MANIFEST"
  echo "OK: joblog -> $LOGDIR/joblog.tsv"
  exit 0
fi

echo "NOTE: GNU parallel not found; using bash queue (no joblog.tsv)."

active_jobs () { jobs -rp | wc -l | tr -d ' '; }

while IFS=$'\t' read -r sub ses; do
  [ -n "$sub" ] || continue
  [ -n "$ses" ] || continue

  while (( $(active_jobs) >= MAX_JOBS )); do
    wait -n
  done

  "$RUN_ONE" "$sub" "$ses" &
done < "$MANIFEST"

wait
echo "OK: all jobs finished."
