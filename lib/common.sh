#!/usr/bin/env bash
# Common utilities for all pipelines.
# Safe to source from interactive shells or scripts.

log() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '[%s] %s\n' "$ts" "$*" >>"${LOGFILE:-${TMPDIR:-/tmp}/preproc-fmri.log}" 2>&1
}

# Terminal output (queue progress/summary).
say() {
  printf '%s\n' "$*" >&2
}

die() {
  log "ERROR: $*"
  say "ERROR: $*"
  exit 1
}

warn() {
  log "WARN: $*"
  say "WARN: $*"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  have_cmd "$1" || die "Missing required command: $1"
}

ensure_dir() {
  local d="${1:?}"
  mkdir -p -- "$d"
}

# Get the absolute directory of a script
script_dir() {
  local src="${1:?Usage: script_dir path}"
  cd -- "$(dirname -- "$src")" >/dev/null 2>&1 && pwd -P
}

# Portable realpath
realpath_safe() {
  local p="${1:?}"
  if have_cmd realpath; then
    realpath "$p"
  elif have_cmd readlink; then
    readlink -f "$p" 2>/dev/null || python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$p"
  else
    python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$p"
  fi
}

# Shell-quote helper (for generating command lists)
shq() {
  python3 -c "import shlex,sys; print(shlex.quote(sys.argv[1]))" "$1"
}
