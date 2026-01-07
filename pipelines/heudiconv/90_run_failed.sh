#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Rerun all failed heudiconv jobs
# Usage: bash 90_run_failed.sh [FORCE]
# FORCE=1 will rerun even if already marked DONE

FORCE="${1:-0}"

bash "$SCRIPT_DIR/20_run_queue.sh" failed "$FORCE"
