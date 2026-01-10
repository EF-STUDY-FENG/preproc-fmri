#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# Usage: bash rerun_failed.sh [FORCE]
bash "$SCRIPT_DIR/queue.sh" failed "${1:-0}"
