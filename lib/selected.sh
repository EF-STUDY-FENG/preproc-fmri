#!/usr/bin/env bash
# Helpers for running a selected subset of jobs by building a command file.

# shellcheck disable=SC1090,SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

selected_list_to_cmd_file() {
  local run_one="${1:?run_one required}"
  local force="${2:-0}"
  local cmd_file="${3:?cmd_file required}"
  shift 3

  : >"$cmd_file"
  local label
  for label in "$@"; do
    [[ -n "$label" ]] || continue
    printf 'bash %q %q %q\n' "$run_one" "$label" "$force" >>"$cmd_file"
  done
}

# Args after cmd_file are pairs: sub ses sub ses ...
selected_pairs_to_cmd_file() {
  local run_one="${1:?run_one required}"
  local force="${2:-0}"
  local cmd_file="${3:?cmd_file required}"
  shift 3

  (( ($# % 2) == 0 )) || die "Expected even number of args (sub ses pairs). Got: $#"

  : >"$cmd_file"
  while (( $# > 0 )); do
    local sub="$1"; shift
    local ses="$1"; shift
    [[ -n "$sub" && -n "$ses" ]] || continue
    printf 'bash %q %q %q %q\n' "$run_one" "$sub" "$ses" "$force" >>"$cmd_file"
  done
}
