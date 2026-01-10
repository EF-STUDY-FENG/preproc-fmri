#!/usr/bin/env bash
# core.sh
# Core utilities (logging, errors, filesystem helpers). Safe to source multiple times.

[[ "${__PFMRI_CORE_SH:-}" == "1" ]] && return 0
__PFMRI_CORE_SH=1

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
_ts() { date '+%Y-%m-%d %H:%M:%S'; }

_default_logfile() {
  local base="${TMPDIR:-/tmp}/preproc-fmri"
  mkdir -p -- "$base" 2>/dev/null || true
  printf '%s\n' "$base/preproc-fmri.log"
}

# LOGFILE is the file path for log lines produced by these helpers.
# Pipeline scripts typically set LOGFILE to the per-job log file.
: "${LOGFILE:=$(_default_logfile)}"

# Print to stderr and append to LOGFILE (best-effort).
_log_line() {
  local level="${1:?level required}"; shift
  local msg="$*"
  local line
  line="[$(_ts)] ${level}: ${msg}"
  printf '%s\n' "$line" >&2
  printf '%s\n' "$line" >>"$LOGFILE" 2>/dev/null || true
}

log_info() { _log_line INFO "$*"; }
log_warn() { _log_line WARN "$*"; }
log_error() { _log_line ERROR "$*"; }

die() {
  log_error "$*"
  exit 1
}

# -----------------------------------------------------------------------------
# Shell / command helpers
# -----------------------------------------------------------------------------
have_cmd() { command -v "$1" >/dev/null 2>&1; }

require_cmd() {
  have_cmd "$1" || die "Missing required command: $1"
}

# -----------------------------------------------------------------------------
# Filesystem helpers
# -----------------------------------------------------------------------------
ensure_dir() {
  local d="${1:?dir required}"
  mkdir -p -- "$d"
}

script_dir() {
  local src="${1:?path required}"
  cd -- "$(dirname -- "$src")" >/dev/null 2>&1 && pwd -P
}

realpath_safe() {
  local p="${1:?path required}"
  if have_cmd realpath; then
    realpath "$p"
  elif have_cmd readlink; then
    readlink -f "$p" 2>/dev/null || python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$p"
  else
    python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$p"
  fi
}

strip_crlf_file() {
  # Print file to stdout with CRLF stripped.
  local f="${1:?file required}"
  if have_cmd sed; then
    sed 's/\r$//' "$f"
  else
    cat "$f"
  fi
}

# Shell-quote helper (for building command files)
shq() {
  python3 -c "import shlex,sys; print(shlex.quote(sys.argv[1]))" "$1"
}
