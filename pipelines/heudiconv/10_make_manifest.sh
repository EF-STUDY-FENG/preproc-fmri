#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090
source "${SCRIPT_DIR}/../../lib/bootstrap.sh"
bootstrap "heudiconv" "$SCRIPT_DIR"

# shellcheck disable=SC1091
source "$LIB_ROOT/common.sh"

ensure_dir "$STAGE_ROOT"

# Optional: rebuild staging each time to avoid leftover sub/ses
if [ "${CLEAN_STAGE_DICOM:-1}" = "1" ]; then
  rm -rf "$STAGE_DICOM"
fi
mkdir -p "$STAGE_DICOM"

# Overwrite manifest outputs
: > "$MANIFEST"
: > "$DUPLICATES"

# ---------- load overrides (optional) ----------
declare -A OVERRIDE_PATH
if [ -n "${OVERRIDES_TSV:-}" ] && [ -f "$OVERRIDES_TSV" ]; then
  while IFS=$'\t' read -r sub ses path; do  # sub ses path
    [[ -z "${sub:-}" || -z "${ses:-}" || -z "${path:-}" ]] && continue
    [[ "$sub" =~ ^# ]] && continue
    # Normalize subject label to 3 digits
    sub3="$(printf "%03d" "$((10#$sub))")"
    key="${sub3}|${ses}"
    realp="$(readlink -f "$path" 2>/dev/null || true)"
    if [ -z "$realp" ] || [ ! -d "$realp" ]; then
      die "override path not found: $sub3 $ses $path"
    fi
    OVERRIDE_PATH["$key"]="$realp"
  done < "$OVERRIDES_TSV"
fi

# ---------- choose best directory per (sub, ses) ----------
declare -A BEST_PATH BEST_MTIME
declare -A SEEN_OVERRIDE_MATCH

# Scan source directories (naming like: TJNU_FJJ_EF_SUB016_..._REST/TASK/G105)
for d in "$SRC_ROOT"/TJNU_FJJ_EF_SUB*; do
  [ -d "$d" ] || continue
  base="$(basename "$d")"

  # Extract SUB###
  sub_raw="$(echo "$base" | sed -n 's/.*_SUB\([0-9]\+\)_.*/\1/p')"
  [ -n "$sub_raw" ] || { echo "SKIP(no SUB): $base" >&2; continue; }
  sub3="$(printf "%03d" "$((10#$sub_raw))")"

  # Map suffix to session (e.g., G105 -> TASK)
  suf="${base##*_}"
  case "$suf" in
    REST|rest) ses="REST" ;;
    TASK|task) ses="TASK" ;;
    G105|g105) ses="TASK" ;;
    *) echo "SKIP(unknown suffix): $base" >&2; continue ;;
  esac

  key="${sub3}|${ses}"
  path="$(readlink -f "$d")"
  mtime="$(stat -c %Y "$path" 2>/dev/null || echo 0)"

  # If override exists for this key: accept only the override path
  if [ -n "${OVERRIDE_PATH[$key]+x}" ]; then
    if [ "$path" = "${OVERRIDE_PATH[$key]}" ]; then
      SEEN_OVERRIDE_MATCH["$key"]=1
      # Force as best
      if [ -n "${BEST_PATH[$key]+x}" ] && [ "${BEST_PATH[$key]}" != "$path" ]; then
        printf "%s\t%s\tOVERRIDE_REPLACED\t%s\t%s\n" "$sub3" "$ses" "${BEST_PATH[$key]}" "$path" >> "$DUPLICATES"
      fi
      BEST_PATH["$key"]="$path"
      BEST_MTIME["$key"]="$mtime"
    else
      printf "%s\t%s\tDISCARDED_BY_OVERRIDE\t%s\t%s\n" "$sub3" "$ses" "$path" "${OVERRIDE_PATH[$key]}" >> "$DUPLICATES"
    fi
    continue
  fi

  # No override: pick the newest path by mtime
  if [ -z "${BEST_PATH[$key]+x}" ]; then
    BEST_PATH["$key"]="$path"
    BEST_MTIME["$key"]="$mtime"
  else
    old="${BEST_PATH[$key]}"
    old_m="${BEST_MTIME[$key]}"
    if [ "$path" = "$old" ]; then
      continue
    fi
    if (( mtime >= old_m )); then
      printf "%s\t%s\tREPLACED_OLD\t%s\t%s\told_mtime=%s\tnew_mtime=%s\n" \
        "$sub3" "$ses" "$old" "$path" "$old_m" "$mtime" >> "$DUPLICATES"
      BEST_PATH["$key"]="$path"
      BEST_MTIME["$key"]="$mtime"
    else
      printf "%s\t%s\tDISCARDED_NEW\t%s\t%s\told_mtime=%s\tnew_mtime=%s\n" \
        "$sub3" "$ses" "$old" "$path" "$old_m" "$mtime" >> "$DUPLICATES"
    fi
  fi
done

# If override is specified but never seen during scan, fail fast (avoid silent mis-selection)
for k in "${!OVERRIDE_PATH[@]}"; do
  if [ -z "${SEEN_OVERRIDE_MATCH[$k]+x}" ]; then
    die "override specified but not found during scan: $k -> ${OVERRIDE_PATH[$k]}"
  fi
done

# ---------- write staging links + manifest ----------
# Sort by key to keep output stable
{
  for k in "${!BEST_PATH[@]}"; do
    echo "$k"
  done
} | sort | while IFS= read -r k; do
  sub3="${k%%|*}"
  ses="${k##*|}"
  tgt="$STAGE_DICOM/sub-${sub3}/ses-${ses}"
  mkdir -p "$(dirname "$tgt")"
  ln -sfn "${BEST_PATH[$k]}" "$tgt"
  printf "%s\t%s\n" "$sub3" "$ses"
done > "$MANIFEST"

log "OK: manifest -> $MANIFEST"

if [ -s "$DUPLICATES" ]; then
  log "INFO: duplicates/decisions recorded -> $DUPLICATES"
  if [ "${STOP_ON_DUPLICATES:-0}" = "1" ]; then
    die "STOP_ON_DUPLICATES=1, stopping due to duplicates."
  fi
fi

log "Sample staged entries:"
head -n 5 "$MANIFEST" | while IFS=$'\t' read -r s ss; do
  log "  sub-$s ses-$ss -> $(readlink -f "$STAGE_DICOM/sub-$s/ses-$ss")"
done
