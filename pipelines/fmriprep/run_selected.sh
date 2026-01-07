#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/bootstrap.sh"
bootstrap "fmriprep" "$SCRIPT_DIR"

# shellcheck disable=SC1090,SC1091
source "${LIB_ROOT}/common.sh"
# shellcheck disable=SC1090,SC1091
source "${LIB_ROOT}/queue.sh"
# shellcheck disable=SC1090,SC1091
source "${LIB_ROOT}/selected.sh"

# Usage: bash run_selected.sh [FORCE] <sub_label...>
# Example: bash run_selected.sh 0 001 002 003

FORCE="0"
if [[ "${1:-}" =~ ^[01]$ ]]; then
  FORCE="$1"
  shift
fi

(( $# >= 1 )) || die "Usage: bash run_selected.sh [FORCE] <sub_label...>"

RUN_ONE="${SCRIPT_DIR}/run_one.sh"
chmod +x "$RUN_ONE" >/dev/null 2>&1 || true

cmd_file="${WORK_ROOT:-$PROJECT_ROOT/work}/selected_fmriprep_commands.txt"
selected_list_to_cmd_file "$RUN_ONE" "$FORCE" "$cmd_file" "$@"

run_queue "$cmd_file" "${MAX_JOBS:-1}" "${LOGDIR}/joblog_selected.tsv"
