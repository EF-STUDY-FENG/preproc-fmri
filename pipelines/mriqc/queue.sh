#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/project.sh"
project_load "mriqc" "$SCRIPT_DIR"

# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/core.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/state.sh"
# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/queue.sh"

MODE="${1:-${QUEUE_MODE_DEFAULT:-pending}}"
FORCE="${2:-0}"
validate_queue_mode "$MODE"

ensure_dir "$LOGDIR"
ensure_dir "$WORK_ROOT"
ensure_dir "$DERIV_ROOT"
init_state_dirs

[[ -s "$PARTICIPANTS_TSV" ]] || die "Participants file missing or empty: $PARTICIPANTS_TSV (run: bash $SCRIPT_DIR/manifest.sh)"

RUN_ONE="$SCRIPT_DIR/run_one.sh"
chmod +x "$RUN_ONE" 2>/dev/null || true

CMD_FILE="$WORK_ROOT/queue_${PIPELINE_NAME}_${MODE}.txt"
JOBLIST_FILE="$WORK_ROOT/todo_${PIPELINE_NAME}_${MODE}_jobs.txt"
JOBLOG_FILE="$LOGDIR/joblog_${MODE}.tsv"

queue_build_from_tsv "$PARTICIPANTS_TSV" "$MODE" "$CMD_FILE" "$JOBLIST_FILE" \
  "$RUN_ONE" "$FORCE" 'sub-%s' 1

N_TODO="$(count_nonempty_lines "$JOBLIST_FILE")"
N_ALL="$(count_nonempty_lines "$PARTICIPANTS_TSV")"
queue_say_header "$MODE" "$FORCE" "$N_TODO" "$N_ALL" "$PARTICIPANTS_TSV"

[[ "$N_TODO" -eq 0 ]] && { printf 'Nothing to do.\n' >&2; exit 0; }

run_queue "$CMD_FILE" "${MAX_JOBS:-1}" "$JOBLOG_FILE" || true
summarize_failures "$JOBLOG_FILE" "$JOBLIST_FILE" || true
