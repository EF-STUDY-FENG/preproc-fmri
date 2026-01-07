#!/usr/bin/env bash
# Container execution wrapper for Singularity/Apptainer.

# shellcheck disable=SC1090
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

# Detect container runtime
detect_container_runtime() {
  if have_cmd apptainer; then
    printf '%s\n' apptainer
  elif have_cmd singularity; then
    printf '%s\n' singularity
  else
    die "Neither 'singularity' nor 'apptainer' found in PATH"
  fi
}

# Run container command
# Usage: run_container <sif_path> <bind_mounts...> -- <container_args...>
run_container() {
  local sif="${1:?SIF path required}"
  shift

  [[ -f "$sif" ]] || die "Container image not found: $sif"

  local runtime="${SING_BIN:-$(detect_container_runtime)}"
  local -a bind_args=()

  # Collect bind mounts until we hit --
  while [[ $# -gt 0 ]] && [[ "$1" != "--" ]]; do
    bind_args+=(-B "$1")
    shift
  done

  # Skip the -- separator
  [[ "$1" == "--" ]] && shift

  # Run the container
  "$runtime" run "${bind_args[@]}" "$sif" "$@"
}

# Exec into container (for utilities like python)
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

  [[ "$1" == "--" ]] && shift

  "$runtime" exec "${bind_args[@]}" "$sif" "$@"
}
