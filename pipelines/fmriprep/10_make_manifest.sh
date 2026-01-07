#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/bootstrap.sh"
bootstrap "fmriprep" "$SCRIPT_DIR"

# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/common.sh"

ensure_dir "$(dirname "$PARTICIPANTS_TSV")"

# Output two columns: sub-XXX<TAB>XXX
find "$BIDS_ROOT" -maxdepth 1 -type d -name 'sub-*' -printf '%f\n' \
| sort \
| while IFS= read -r s; do
    printf "%s\t%s\n" "$s" "${s#sub-}"
  done \
> "$PARTICIPANTS_TSV"

if [ ! -s "$PARTICIPANTS_TSV" ]; then
  die "no participants found under $BIDS_ROOT"
fi

log "OK: manifest -> $PARTICIPANTS_TSV"
head -n 10 "$PARTICIPANTS_TSV"
