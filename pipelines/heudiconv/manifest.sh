#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck disable=SC1090,SC1091
source "${SCRIPT_DIR}/../../lib/project.sh"
project_load "heudiconv" "$SCRIPT_DIR"

# shellcheck disable=SC1090,SC1091
source "$LIB_ROOT/core.sh"

ensure_dir "$STAGE_ROOT"

# Flags from config (defaults in config/heudiconv.env)
PY_FLAGS=()
[[ "${CLEAN_STAGE_DICOM:-1}" == "1" ]] && PY_FLAGS+=(--clean-stage)
[[ "${STOP_ON_DUPLICATES:-0}" == "1" ]] && PY_FLAGS+=(--stop-on-duplicates)
[[ "${ALLOW_OVERRIDE_OUTSIDE_SCAN:-0}" == "1" ]] && PY_FLAGS+=(--allow-override-outside-scan)

python3 "$TOOLS_ROOT/heudiconv_manifest.py" \
  --src-root "$SRC_ROOT" \
  --stage-dicom "$STAGE_DICOM" \
  --manifest "$MANIFEST" \
  --duplicates "$DUPLICATES" \
  --overrides "$OVERRIDES_TSV" \
  "${PY_FLAGS[@]}"
