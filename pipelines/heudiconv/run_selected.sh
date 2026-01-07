#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck disable=SC1090
source "${SCRIPT_DIR}/../../lib/bootstrap.sh"
bootstrap "heudiconv" "$SCRIPT_DIR"

# shellcheck disable=SC1090
source "${LIB_ROOT}/common.sh"
# shellcheck disable=SC1090
source "${LIB_ROOT}/queue.sh"
# shellcheck disable=SC1090
source "${LIB_ROOT}/selected.sh"

# Usage: bash run_selected.sh [FORCE] <sub ses> [<sub ses> ...]
# Example: bash run_selected.sh 0 001 TASK 001 REST 002 TASK

FORCE="0"
if [[ "${1:-}" =~ ^[01]$ ]]; then
  FORCE="$1"
  shift
fi

(( $# >= 2 )) || die "Usage: bash run_selected.sh [FORCE] <sub ses> [<sub ses> ...]"

RUN_ONE="${SCRIPT_DIR}/run_one.sh"
chmod +x "$RUN_ONE" >/dev/null 2>&1 || true

cmd_file="${WORK_ROOT:-$PROJECT_ROOT/work}/selected_heudiconv_commands.txt"
selected_pairs_to_cmd_file "$RUN_ONE" "$FORCE" "$cmd_file" "$@"

run_queue "$cmd_file" "${MAX_JOBS:-1}" "${LOGDIR}/joblog_selected.tsv"
