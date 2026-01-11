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

FORCE="0"
if [[ "${1:-}" =~ ^[01]$ ]]; then
  FORCE="$1"; shift
fi

(( $# >= 1 )) || die "Usage: bash run_selected.sh [FORCE] <label> [<label> ...]"

ensure_dir "$WORK_ROOT"
ensure_dir "$LOGDIR"
init_state_dirs

SEL_TSV="$WORK_ROOT/selected_${PIPELINE_NAME}.tsv"
: >"$SEL_TSV"
for label in "$@"; do
  echo "$label" >>"$SEL_TSV"
done

RUN_ONE="$SCRIPT_DIR/run_one.sh"
chmod +x "$RUN_ONE" 2>/dev/null || true

CMD_FILE="$WORK_ROOT/queue_selected_${PIPELINE_NAME}.txt"
JOBLIST_FILE="$WORK_ROOT/selected_${PIPELINE_NAME}_jobs.txt"
JOBLOG_FILE="$LOGDIR/joblog_selected.tsv"

queue_build_from_tsv "$SEL_TSV" all "$CMD_FILE" "$JOBLIST_FILE" \
  "$RUN_ONE" "$FORCE" 'sub-%s' 1

N_TODO="$(count_nonempty_lines "$JOBLIST_FILE")"
N_ALL="$(count_nonempty_lines "$SEL_TSV")"
queue_say_header all "$FORCE" "$N_TODO" "$N_ALL" "$SEL_TSV"

[[ "$N_TODO" -eq 0 ]] && { printf 'Nothing to do.\n' >&2; exit 0; }

run_queue "$CMD_FILE" "${MAX_JOBS:-1}" "$JOBLOG_FILE" || true
summarize_failures "$JOBLOG_FILE" "$JOBLIST_FILE" || true
