#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/project.sh"
project_load "heudiconv" "$SCRIPT_DIR"

# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/core.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/state.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/queue.sh"

MODE="${1:-${QUEUE_MODE_DEFAULT:-pending}}"   # pending|failed|all
FORCE="${2:-0}"                              # 1=force rerun
validate_queue_mode "$MODE"

ensure_dir "$LOGDIR"
ensure_dir "$BIDS_ROOT"
ensure_dir "$WORK_ROOT"
init_state_dirs

[[ -s "$MANIFEST" ]] || die "Manifest missing or empty: $MANIFEST (run: bash $SCRIPT_DIR/manifest.sh)"

RUN_ONE="$SCRIPT_DIR/run_one.sh"
chmod +x "$RUN_ONE" 2>/dev/null || true

CMD_FILE="$WORK_ROOT/queue_${PIPELINE_NAME}_${MODE}.txt"
JOBLIST_FILE="$WORK_ROOT/todo_${PIPELINE_NAME}_${MODE}_jobs.txt"
JOBLOG_FILE="$LOGDIR/joblog_${MODE}.tsv"

queue_build_from_tsv "$MANIFEST" "$MODE" "$CMD_FILE" "$JOBLIST_FILE" \
  "$RUN_ONE" "$FORCE" 'sub-%s_ses-%s' 1 2

N_TODO="$(count_nonempty_lines "$JOBLIST_FILE")"
N_ALL="$(count_nonempty_lines "$MANIFEST")"

queue_say_header "$MODE" "$FORCE" "$N_TODO" "$N_ALL" "$MANIFEST"

if [[ "$N_TODO" -eq 0 ]]; then
  printf 'Nothing to do.\n' >&2
  exit 0
fi

run_queue "$CMD_FILE" "${MAX_JOBS:-1}" "$JOBLOG_FILE" || true
summarize_failures_from_joblist "$JOBLOG_FILE" "$JOBLIST_FILE" || true
