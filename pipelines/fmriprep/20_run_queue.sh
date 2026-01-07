#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090
source "${SCRIPT_DIR}/../../lib/bootstrap.sh"
bootstrap "fmriprep" "$SCRIPT_DIR"

# shellcheck disable=SC1091
source "$LIB_ROOT/common.sh"
# shellcheck disable=SC1091
source "$LIB_ROOT/status.sh"
# shellcheck disable=SC1091
source "$LIB_ROOT/queue.sh"

MODE="${1:-$QUEUE_MODE_DEFAULT}"    # pending|failed|all
FORCE="${2:-0}"                    # 1=force rerun (passed to run_one)

ensure_dir "$DERIV_ROOT"
ensure_dir "$FS_SUBJECTS_DIR"
ensure_dir "$WORK_ROOT"
ensure_dir "$LOGDIR"
init_state_dirs

if [ ! -s "$PARTICIPANTS_TSV" ]; then
  die "participants list missing: $PARTICIPANTS_TSV. Run: bash $SCRIPT_DIR/10_make_manifest.sh"
fi

RUN_ONE="$SCRIPT_DIR/run_one.sh"
chmod +x "$RUN_ONE" >/dev/null 2>&1 || true

TODO_TSV="$PROJECT_ROOT/work/todo_fmriprep_${MODE}.tsv"
: > "$TODO_TSV"

while IFS=$'\t' read -r _sub label; do
  [ -n "${label:-}" ] || continue
  SUB="sub-${label}"

  should_enqueue "$SUB" "$MODE" || continue

  printf "%s\t%s\n" "$_sub" "$label" >> "$TODO_TSV"
done < "$PARTICIPANTS_TSV"

N_TODO="$(wc -l < "$TODO_TSV" | tr -d ' ')"
N_ALL="$(wc -l < "$PARTICIPANTS_TSV" | tr -d ' ')"

log "Participants total: $N_ALL"
log "Queue mode: $MODE (force=$FORCE)"
log "To run: $N_TODO"
log "TODO list -> $TODO_TSV"
log "Resources: MAX_JOBS=$MAX_JOBS; NTHREADS=$NTHREADS; OMP_NTHREADS=$OMP_NTHREADS; MEM_MB=$MEM_MB"
log "CIFTI: CIFTI_OUTPUT=${CIFTI_OUTPUT:-<disabled>}"
log "Work cleanup: CLEAN_WORK_ON_SUCCESS=$CLEAN_WORK_ON_SUCCESS"

if [ "$N_TODO" -eq 0 ]; then
  log "Nothing to do."
  exit 0
fi

# Build command file for queue
CMD_FILE="$PROJECT_ROOT/work/queue_fmriprep_${MODE}.txt"
: > "$CMD_FILE"

while IFS=$'\t' read -r _sub label; do
  printf 'bash %q %q %q\n' "$RUN_ONE" "$label" "$FORCE" >> "$CMD_FILE"
done < "$TODO_TSV"

# Run the queue
run_queue "$CMD_FILE" "$MAX_JOBS" "$LOGDIR/joblog_${MODE}.tsv"
log "OK: queue finished. Joblog -> $LOGDIR/joblog_${MODE}.tsv"
