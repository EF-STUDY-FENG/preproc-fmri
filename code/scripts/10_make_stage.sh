#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_config.sh"

mkdir -p "$STAGE_ROOT"

# 可选：每次重建 staging，避免残留旧的 sub/ses
if [ "${CLEAN_STAGE_DICOM:-1}" = "1" ]; then
  rm -rf "$STAGE_DICOM"
fi
mkdir -p "$STAGE_DICOM"

# 重写清单文件
: > "$MANIFEST"
: > "$DUPLICATES"

# ---------- load overrides (optional) ----------
declare -A OVERRIDE_PATH
if [ -n "${OVERRIDES_TSV:-}" ] && [ -f "$OVERRIDES_TSV" ]; then
  while IFS=$'\t' read -r sub ses path; do
    [[ -z "${sub:-}" || -z "${ses:-}" || -z "${path:-}" ]] && continue
    [[ "$sub" =~ ^# ]] && continue
    # 统一 sub 到 3 位
    sub3="$(printf "%03d" "$((10#$sub))")"
    key="${sub3}|${ses}"
    realp="$(readlink -f "$path" 2>/dev/null || true)"
    if [ -z "$realp" ] || [ ! -d "$realp" ]; then
      echo "ERROR: override path not found: $sub3 $ses $path" >&2
      exit 2
    fi
    OVERRIDE_PATH["$key"]="$realp"
  done < "$OVERRIDES_TSV"
fi

# ---------- choose best directory per (sub, ses) ----------
declare -A BEST_PATH BEST_MTIME
declare -A SEEN_OVERRIDE_MATCH

# 扫描原始目录（你的命名：TJNU_FJJ_EF_SUB016_..._REST/TASK/G105）
for d in "$SRC_ROOT"/TJNU_FJJ_EF_SUB*; do
  [ -d "$d" ] || continue
  base="$(basename "$d")"

  # 提取 SUB###
  sub_raw="$(echo "$base" | sed -n 's/.*_SUB\([0-9]\+\)_.*/\1/p')"
  [ -n "$sub_raw" ] || { echo "SKIP(no SUB): $base" >&2; continue; }
  sub3="$(printf "%03d" "$((10#$sub_raw))")"

  # 提取末尾后缀并映射 session：G105 -> TASK
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

  # 若该 key 有 override：只接受 override 指定的那条路径
  if [ -n "${OVERRIDE_PATH[$key]+x}" ]; then
    if [ "$path" = "${OVERRIDE_PATH[$key]}" ]; then
      SEEN_OVERRIDE_MATCH["$key"]=1
      # 强制设为最佳
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

  # 无 override：按 mtime 选择“最新”的那条
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

# 若有 override，但扫描中未遇到指定目录，直接报错（避免 silent wrong）
for k in "${!OVERRIDE_PATH[@]}"; do
  if [ -z "${SEEN_OVERRIDE_MATCH[$k]+x}" ]; then
    echo "ERROR: override specified but not found during scan: $k -> ${OVERRIDE_PATH[$k]}" >&2
    exit 3
  fi
done

# ---------- write staging links + manifest ----------
# 以 key 排序，保证输出稳定
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

echo "OK: manifest -> $MANIFEST"

if [ -s "$DUPLICATES" ]; then
  echo "INFO: duplicates/decisions recorded -> $DUPLICATES"
  if [ "${STOP_ON_DUPLICATES:-0}" = "1" ]; then
    echo "ERROR: STOP_ON_DUPLICATES=1, stopping due to duplicates." >&2
    exit 4
  fi
fi

echo "Sample staged entries:"
head -n 5 "$MANIFEST" | while IFS=$'\t' read -r s ss; do
  echo "  sub-$s ses-$ss -> $(readlink -f "$STAGE_DICOM/sub-$s/ses-$ss")"
done
