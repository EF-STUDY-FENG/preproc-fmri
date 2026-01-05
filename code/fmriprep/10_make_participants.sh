#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"

mkdir -p "$(dirname "$PARTICIPANTS_TSV")"

# 输出两列：sub-XXX<TAB>XXX
find "$BIDS_ROOT" -maxdepth 1 -type d -name 'sub-*' -printf '%f\n' \
| sort \
| while IFS= read -r s; do
    printf "%s\t%s\n" "$s" "${s#sub-}"
  done \
> "$PARTICIPANTS_TSV"

if [ ! -s "$PARTICIPANTS_TSV" ]; then
  echo "ERROR: no participants found under $BIDS_ROOT" >&2
  exit 1
fi

echo "OK: participants -> $PARTICIPANTS_TSV"
head -n 10 "$PARTICIPANTS_TSV"
