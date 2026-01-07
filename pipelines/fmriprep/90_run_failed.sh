#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE="${1:-0}"

bash "$SCRIPT_DIR/20_run_queue.sh" failed "$FORCE"
