#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/bootstrap.sh"
bootstrap "heudiconv" "$SCRIPT_DIR"

# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/common.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/status.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/queue.sh"

ensure_dir "$LOGDIR"
ensure_dir "$BIDS_ROOT"
init_state_dirs

# Queue mode: pending (default) / failed / all
MODE="${1:-pending}"
FORCE="${2:-0}"

case "$MODE" in
  pending|failed|all) ;;
  *) die "Invalid mode: $MODE. Use pending/failed/all" ;;
esac

if [ ! -s "$MANIFEST" ]; then
  die "manifest missing or empty: $MANIFEST. Run: bash $SCRIPT_DIR/10_make_manifest.sh"
fi

RUN_ONE="$SCRIPT_DIR/run_one.sh"
chmod +x "$RUN_ONE" >/dev/null 2>&1 || true

log "Queue mode=$MODE force=$FORCE MAX_JOBS=$MAX_JOBS"
log "Manifest: $MANIFEST"

# Build command file
CMD_FILE="$PROJECT_ROOT/work/queue_heudiconv.txt"
: > "$CMD_FILE"

while IFS=$'\t' read -r sub ses; do
  [ -n "$sub" ] || continue
  [ -n "$ses" ] || continue

  JOB_ID="sub-${sub}_ses-${ses}"

  # Check if the job should be enqueued
  should_enqueue "$JOB_ID" "$MODE" || continue

  # Additional guard: skip RUNNING/LOCKED (avoid duplicate concurrent start)
  if is_running "$JOB_ID" || is_locked "$JOB_ID"; then
    continue
  fi

  # pending (default): run only jobs that are neither DONE nor FAILED
  if [ "$MODE" = "pending" ]; then
    if is_done "$JOB_ID" || is_failed "$JOB_ID"; then
      continue
    fi
  fi

  # failed: run only FAILED jobs (RUNNING/LOCKED already skipped above)
  if [ "$MODE" = "failed" ]; then
    if ! is_failed "$JOB_ID"; then
      continue
    fi
  fi

  # all: enqueue everything; run_one decides via FORCE
  printf 'bash %q %q %q %q\n' "$RUN_ONE" "$sub" "$ses" "$FORCE" >> "$CMD_FILE"
done < "$MANIFEST"

# Run the queue
run_queue "$CMD_FILE" "$MAX_JOBS" "$LOGDIR/joblog.tsv"
log "OK: all jobs finished. Joblog -> $LOGDIR/joblog.tsv"
