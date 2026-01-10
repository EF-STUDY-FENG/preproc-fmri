#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

bash "$SCRIPT_DIR/queue.sh" failed "${1:-0}"
