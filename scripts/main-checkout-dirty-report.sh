#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/main-checkout.sh
. "${SCRIPT_DIR}/lib/main-checkout.sh"

usage() {
  cat <<'EOF' >&2
Usage:
  scripts/main-checkout-dirty-report.sh [--repo <path>] [--base-ref <ref>] [--format text|json]

Read-only classifier for the maintainer main checkout. It reports:
  - divergence against a base ref
  - tracked dirty files that also changed upstream
  - tracked dirty files that are local-only
EOF
}

die() {
  echo "[main-checkout-dirty-report] ERROR: $1" >&2
  exit 2
}

collect_into_array() {
  local array_name="$1"
  shift
  local line
  local values=()
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    values+=("$line")
  done < <("$@")
  eval "$array_name=()"
  local quoted=()
  local item
  for item in ${values[@]+"${values[@]}"}; do
    quoted+=("$(printf '%q' "$item")")
  done
  if [[ "${#quoted[@]}" -gt 0 ]]; then
    eval "$array_name=(${quoted[*]})"
  else
    eval "$array_name=()"
  fi
}

array_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

START_REPO="$(pwd)"
BASE_REF="origin/main"
FORMAT="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      START_REPO="${2:-}"
      shift 2
      ;;
    --base-ref)
      BASE_REF="${2:-}"
      shift 2
      ;;
    --format)
      FORMAT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown argument: $1"
      ;;
  esac
done

[[ "$FORMAT" == "text" || "$FORMAT" == "json" ]] || die "--format must be text or json"
[[ -d "$START_REPO" ]] || die "--repo must be a directory: $START_REPO"

MAIN_CHECKOUT="$(resolve_main_checkout "$START_REPO" 2>/dev/null || true)"
[[ -n "$MAIN_CHECKOUT" ]] || die "failed to resolve main checkout from: $START_REPO"
git -C "$MAIN_CHECKOUT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repo: $MAIN_CHECKOUT"

CURRENT_BRANCH="$(git -C "$MAIN_CHECKOUT" branch --show-current 2>/dev/null || true)"
[[ -n "$CURRENT_BRANCH" ]] || CURRENT_BRANCH="DETACHED"

BASE_REF_PRESENT=false
AHEAD_COUNT=0
BEHIND_COUNT=0
if git -C "$MAIN_CHECKOUT" rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null 2>&1; then
  BASE_REF_PRESENT=true
  DIVERGENCE="$(git -C "$MAIN_CHECKOUT" rev-list --left-right --count HEAD..."$BASE_REF")"
  AHEAD_COUNT="$(awk '{print $1}' <<<"$DIVERGENCE")"
  BEHIND_COUNT="$(awk '{print $2}' <<<"$DIVERGENCE")"
fi

collect_into_array DIRTY_FILES bash -c '
  {
    git -C "$1" diff --name-only
    git -C "$1" diff --cached --name-only
  } | sed "/^$/d" | sort -u
' _ "$MAIN_CHECKOUT"

UPSTREAM_CHANGED_FILES=()
if [[ "$BASE_REF_PRESENT" == true ]]; then
  collect_into_array UPSTREAM_CHANGED_FILES bash -c '
    git -C "$1" diff --name-only HEAD.."$2" | sed "/^$/d" | sort -u
  ' _ "$MAIN_CHECKOUT" "$BASE_REF"
fi

OVERLAP_FILES=()
LOCAL_ONLY_FILES=()
for path in ${DIRTY_FILES[@]+"${DIRTY_FILES[@]}"}; do
  if array_contains "$path" ${UPSTREAM_CHANGED_FILES[@]+"${UPSTREAM_CHANGED_FILES[@]}"}; then
    OVERLAP_FILES+=("$path")
  else
    LOCAL_ONLY_FILES+=("$path")
  fi
done

TRACKED_DIRTY_COUNT="${#DIRTY_FILES[@]}"
OVERLAP_COUNT="${#OVERLAP_FILES[@]}"
LOCAL_ONLY_COUNT="${#LOCAL_ONLY_FILES[@]}"

ACTION_HINTS=()
if [[ "$BEHIND_COUNT" -gt 0 ]]; then
  ACTION_HINTS+=("main checkout 落後 ${BASE_REF}；若要讓 root checkout 反映已 release 內容，之後請在主 checkout 自行 pull。")
fi
if [[ "$OVERLAP_COUNT" -gt 0 ]]; then
  ACTION_HINTS+=("有 ${OVERLAP_COUNT} 個 tracked dirty 檔案也被 upstream 改過；先人工比對，再決定 pull / stash / reset。")
fi
if [[ "$LOCAL_ONLY_COUNT" -gt 0 ]]; then
  ACTION_HINTS+=("有 ${LOCAL_ONLY_COUNT} 個 local-only tracked dirty 檔案；保留、整理或暫存都應由 maintainer 自行決定。")
fi
if [[ "$TRACKED_DIRTY_COUNT" -eq 0 && "$BEHIND_COUNT" -eq 0 && "$AHEAD_COUNT" -eq 0 ]]; then
  ACTION_HINTS+=("main checkout 目前無 tracked dirty，且與 base ref 無 divergence。")
fi

if [[ "$FORMAT" == "json" ]]; then
  dirty_serialized="$(printf '%s\n' ${DIRTY_FILES[@]+"${DIRTY_FILES[@]}"})"
  overlap_serialized="$(printf '%s\n' ${OVERLAP_FILES[@]+"${OVERLAP_FILES[@]}"})"
  local_only_serialized="$(printf '%s\n' ${LOCAL_ONLY_FILES[@]+"${LOCAL_ONLY_FILES[@]}"})"
  hints_serialized="$(printf '%s\n' ${ACTION_HINTS[@]+"${ACTION_HINTS[@]}"})"
  python3 - "$MAIN_CHECKOUT" "$CURRENT_BRANCH" "$BASE_REF" "$BASE_REF_PRESENT" "$AHEAD_COUNT" "$BEHIND_COUNT" "$dirty_serialized" "$overlap_serialized" "$local_only_serialized" "$hints_serialized" <<'PY'
import json
import sys

main_checkout, current_branch, base_ref, base_ref_present, ahead, behind, dirty, overlap, local_only, hints = sys.argv[1:11]

def splitlines(blob):
    return [line for line in blob.splitlines() if line]

payload = {
    "main_checkout": main_checkout,
    "current_branch": current_branch,
    "base_ref": base_ref,
    "base_ref_present": base_ref_present == "true",
    "ahead": int(ahead),
    "behind": int(behind),
    "dirty_files": splitlines(dirty),
    "overlap_dirty_files": splitlines(overlap),
    "local_only_dirty_files": splitlines(local_only),
    "action_hints": splitlines(hints),
}
payload["tracked_dirty_count"] = len(payload["dirty_files"])
payload["overlap_dirty_count"] = len(payload["overlap_dirty_files"])
payload["local_only_dirty_count"] = len(payload["local_only_dirty_files"])
print(json.dumps(payload, ensure_ascii=False, indent=2))
PY
  exit 0
fi

echo "main_checkout: ${MAIN_CHECKOUT}"
echo "current_branch: ${CURRENT_BRANCH}"
echo "base_ref: ${BASE_REF}"
echo "base_ref_present: ${BASE_REF_PRESENT}"
echo "ahead: ${AHEAD_COUNT}"
echo "behind: ${BEHIND_COUNT}"
echo "tracked_dirty_count: ${TRACKED_DIRTY_COUNT}"
echo "overlap_dirty_count: ${OVERLAP_COUNT}"
echo "local_only_dirty_count: ${LOCAL_ONLY_COUNT}"

if [[ "$OVERLAP_COUNT" -gt 0 ]]; then
  echo "overlap_dirty_files:"
  printf '  - %s\n' ${OVERLAP_FILES[@]+"${OVERLAP_FILES[@]}"}
fi

if [[ "$LOCAL_ONLY_COUNT" -gt 0 ]]; then
  echo "local_only_dirty_files:"
  printf '  - %s\n' ${LOCAL_ONLY_FILES[@]+"${LOCAL_ONLY_FILES[@]}"}
fi

if [[ "${#ACTION_HINTS[@]}" -gt 0 ]]; then
  echo "action_hints:"
  printf '  - %s\n' ${ACTION_HINTS[@]+"${ACTION_HINTS[@]}"}
fi
