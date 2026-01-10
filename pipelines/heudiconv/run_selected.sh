#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/bootstrap.sh"
bootstrap "heudiconv" "$SCRIPT_DIR"

# shellcheck disable=SC1090,SC1091
source "${LIB_ROOT}/common.sh"
# shellcheck disable=SC1090,SC1091
source "${LIB_ROOT}/status.sh"
# shellcheck disable=SC1090,SC1091
source "${LIB_ROOT}/queue.sh"
# shellcheck disable=SC1090,SC1091
source "${LIB_ROOT}/selected.sh"

# Usage: bash run_selected.sh [FORCE] <sub ses> [<sub ses> ...]
# Example: bash run_selected.sh 0 001 TASK 001 REST 002 TASK

FORCE="0"
if [[ "${1:-}" =~ ^[01]$ ]]; then
  FORCE="$1"
  shift
fi

(( $# >= 2 )) || die "Usage: bash run_selected.sh [FORCE] <sub ses> [<sub ses> ...]"

ARGS=("$@")

RUN_ONE="${SCRIPT_DIR}/run_one.sh"
chmod +x "$RUN_ONE" >/dev/null 2>&1 || true

cmd_file="${WORK_ROOT:-$PROJECT_ROOT/work}/selected_heudiconv_commands.txt"
selected_pairs_to_cmd_file "$RUN_ONE" "$FORCE" "$cmd_file" "$@"

JOBLIST_FILE="${WORK_ROOT:-$PROJECT_ROOT/work}/selected_heudiconv_jobs.txt"
: >"$JOBLIST_FILE"
for ((i=0; i<${#ARGS[@]}; i+=2)); do
  sub="${ARGS[i]}"
  ses="${ARGS[i+1]}"
  printf 'sub-%s_ses-%s\n' "$sub" "$ses" >>"$JOBLIST_FILE"
done

run_queue "$cmd_file" "${MAX_JOBS:-1}" "${LOGDIR}/joblog_selected.tsv"

summarize_failures_from_joblist "${LOGDIR}/joblog_selected.tsv" "$JOBLIST_FILE" || true
