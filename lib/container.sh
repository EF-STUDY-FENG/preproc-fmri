#!/usr/bin/env bash
# container.sh
# Singularity/Apptainer wrapper.

[[ "${__PFMRI_CONTAINER_SH:-}" == "1" ]] && return 0
__PFMRI_CONTAINER_SH=1

# shellcheck disable=SC1090,SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/core.sh"

detect_container_runtime() {
  if have_cmd apptainer; then
    echo apptainer
  elif have_cmd singularity; then
    echo singularity
  else
    die "Neither 'apptainer' nor 'singularity' found in PATH"
  fi
}

# Usage: run_container <image.sif> <bind1> [<bind2> ...] -- <container_args...>
run_container() {
  local sif="${1:?SIF path required}"
  shift

  [[ -f "$sif" ]] || die "Container image not found: $sif"

  local runtime="${SING_BIN:-$(detect_container_runtime)}"
  local -a bind_args=()

  while [[ $# -gt 0 ]] && [[ "$1" != "--" ]]; do
    bind_args+=(-B "$1")
    shift
  done
  [[ "${1:-}" == "--" ]] && shift

  "$runtime" run "${bind_args[@]}" "$sif" "$@"
}

# Usage: exec_container <image.sif> <bind1> [<bind2> ...] -- <cmd...>
exec_container() {
  local sif="${1:?SIF path required}"
  shift

  [[ -f "$sif" ]] || die "Container image not found: $sif"

  local runtime="${SING_BIN:-$(detect_container_runtime)}"
  local -a bind_args=()

  while [[ $# -gt 0 ]] && [[ "$1" != "--" ]]; do
    bind_args+=(-B "$1")
    shift
  done
  [[ "${1:-}" == "--" ]] && shift

  "$runtime" exec "${bind_args[@]}" "$sif" "$@"
}
