#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/project.sh"
project_load "fmriprep" "$SCRIPT_DIR"

# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/core.sh"

ensure_dir "$(dirname -- "$PARTICIPANTS_TSV")"

: >"$PARTICIPANTS_TSV"

shopt -s nullglob
for sub_dir in "$BIDS_ROOT"/sub-*; do
  [[ -d "$sub_dir" ]] || continue
  label="${sub_dir##*/sub-}"
  [[ -n "$label" ]] || continue
  echo "$label" >>"$PARTICIPANTS_TSV"
done
shopt -u nullglob

sort -u -o "$PARTICIPANTS_TSV" "$PARTICIPANTS_TSV"
printf 'OK: participants -> %s (N=%s)\n' \
  "$PARTICIPANTS_TSV" "$(wc -l <"$PARTICIPANTS_TSV" | tr -d ' ')" >&2
