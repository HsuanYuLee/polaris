#!/usr/bin/env bash
set -euo pipefail

PREFIX="[polaris verification-passed]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSE_TASK_MD="${SCRIPT_DIR}/parse-task-md.sh"
VALIDATE_TASK_MD="${SCRIPT_DIR}/validate-task-md.sh"
# shellcheck source=lib/verification-evidence.sh
. "${SCRIPT_DIR}/lib/verification-evidence.sh"

TASK_MD=""
REPO_OVERRIDE=""
TICKET_OVERRIDE=""
HEAD_SHA_OVERRIDE=""
FORMAT="text"

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/check-verification-passed.sh --task-md <path> [--repo <path>] [--ticket <key>] [--head-sha <sha>] [--format text|json]

Exit:
  0  verification passed
  2  blocking verification outcome / missing required artifact
  64 invalid usage / resolver failure
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --repo) REPO_OVERRIDE="${2:-}"; shift 2 ;;
    --ticket) TICKET_OVERRIDE="${2:-}"; shift 2 ;;
    --head-sha) HEAD_SHA_OVERRIDE="${2:-}"; shift 2 ;;
    --format) FORMAT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

[[ -n "$TASK_MD" ]] || { echo "$PREFIX --task-md is required" >&2; usage; exit 64; }
[[ -f "$TASK_MD" ]] || { echo "$PREFIX task.md not found: $TASK_MD" >&2; exit 64; }
[[ "$FORMAT" == "text" || "$FORMAT" == "json" ]] || { echo "$PREFIX --format must be text or json" >&2; exit 64; }

TASK_MD="$(cd "$(dirname "$TASK_MD")" && pwd)/$(basename "$TASK_MD")"

emit_result() {
  local source_id="$1"
  local head_sha="$2"
  local required="$3"
  local status="$4"
  local blocking_reason="$5"
  local artifacts_checked="$6"

  if [[ "$FORMAT" == "json" ]]; then
    python3 - "$source_id" "$head_sha" "$required" "$status" "$blocking_reason" "$artifacts_checked" <<'PY'
import json
import sys

source_id, head_sha, required_raw, status, blocking_reason, artifacts_raw = sys.argv[1:7]
required = required_raw == "true"
artifacts = [line for line in artifacts_raw.splitlines() if line]
payload = {
    "source_id": source_id,
    "head_sha": head_sha or None,
    "verification_required": required,
    "status": status,
    "blocking_reason": blocking_reason or None,
    "artifacts_checked": artifacts,
}
print(json.dumps(payload, ensure_ascii=False, indent=2))
PY
  else
    if [[ "$blocking_reason" == "pass" ]]; then
      printf 'PASS source=%s status=%s head=%s\n' "$source_id" "$status" "${head_sha:-N/A}"
    else
      printf 'BLOCKED source=%s status=%s reason=%s head=%s\n' "$source_id" "$status" "$blocking_reason" "${head_sha:-N/A}"
    fi
  fi
}

parse_field() {
  bash "$PARSE_TASK_MD" "$TASK_MD" --no-resolve --field "$1" 2>/dev/null || true
}

resolve_mode() {
  local base
  base="$(basename "$TASK_MD")"
  if [[ "$base" == "index.md" ]]; then
    base="$(basename "$(dirname "$TASK_MD")").md"
  fi
  case "$base" in
    V[0-9]*.md) printf 'V\n' ;;
    *) printf 'T\n' ;;
  esac
}

resolve_repo_path() {
  local repo_name="$1"
  if [[ -n "$REPO_OVERRIDE" ]]; then
    [[ -d "$REPO_OVERRIDE" ]] || { echo "$PREFIX --repo path not found: $REPO_OVERRIDE" >&2; exit 64; }
    (cd "$REPO_OVERRIDE" && pwd)
    return 0
  fi
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return 0
  fi

  local td probe
  td="$(cd "$(dirname "$TASK_MD")" && pwd)"
  while [[ "$td" != "/" ]]; do
    probe="$td/$repo_name"
    if [[ -d "$probe/.git" || -f "$probe/.git" ]]; then
      printf '%s\n' "$probe"
      return 0
    fi
    td="$(dirname "$td")"
  done
  return 1
}

resolve_v_status() {
  python3 - "$TASK_MD" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if not text.startswith("---\n"):
    raise SystemExit(0)
end = text.find("\n---\n", 4)
if end == -1:
    raise SystemExit(0)
frontmatter = text[4:end].splitlines()

data = {}
i = 0
while i < len(frontmatter):
    raw = frontmatter[i]
    if raw.startswith("ac_verification:"):
        i += 1
        while i < len(frontmatter):
            line = frontmatter[i]
            if not line.strip():
                i += 1
                continue
            if not line.startswith("  "):
                break
            stripped = line.strip()
            if ":" in stripped:
                key, value = stripped.split(":", 1)
                data[key.strip()] = value.strip()
            i += 1
        break
    i += 1

print(json.dumps(data, ensure_ascii=False))
PY
}

MODE="$(resolve_mode)"
SOURCE_ID="$(parse_field work_item_id)"
if [[ -z "$SOURCE_ID" ]]; then
  SOURCE_ID="$(parse_field task_jira_key)"
fi
if [[ -z "$SOURCE_ID" ]]; then
  SOURCE_ID="$(basename "$(dirname "$TASK_MD")")"
fi

REPO_NAME="$(parse_field repo)"
REPO_PATH=""
HEAD_SHA=""
if [[ -n "$REPO_NAME" ]]; then
  REPO_PATH="$(resolve_repo_path "$REPO_NAME" || true)"
fi
if [[ -n "$HEAD_SHA_OVERRIDE" ]]; then
  HEAD_SHA="$HEAD_SHA_OVERRIDE"
elif [[ -n "$REPO_PATH" ]]; then
  HEAD_SHA="$(git -C "$REPO_PATH" rev-parse HEAD 2>/dev/null || true)"
fi

artifacts_checked=()

if [[ "$MODE" == "V" ]]; then
  if ! "$VALIDATE_TASK_MD" "$TASK_MD" >/dev/null 2>&1; then
    artifacts_checked+=("$TASK_MD")
    artifacts_checked_text=$(printf '%s\n' "${artifacts_checked[@]}")
    emit_result "$SOURCE_ID" "$HEAD_SHA" "true" "FAIL" "invalid_ac_verification_schema" "$artifacts_checked_text"
    exit 2
  fi
  v_json="$(resolve_v_status)"
  v_status="$(python3 - "$v_json" <<'PY'
import json, sys
data = json.loads(sys.argv[1] or "{}")
print(data.get("status") or "")
PY
)"
  artifacts_checked+=("$TASK_MD")
  if [[ -z "$v_status" ]]; then
    artifacts_checked_text=$(printf '%s\n' "${artifacts_checked[@]}")
    emit_result "$SOURCE_ID" "$HEAD_SHA" "true" "IN_PROGRESS" "missing_ac_verification" "$artifacts_checked_text"
    exit 2
  fi
  case "$v_status" in
    PASS)
      artifacts_checked_text=$(printf '%s\n' "${artifacts_checked[@]}")
      emit_result "$SOURCE_ID" "$HEAD_SHA" "true" "PASS" "pass" "$artifacts_checked_text"
      exit 0
      ;;
    FAIL|MANUAL_REQUIRED|UNCERTAIN|BLOCKED_ENV|IN_PROGRESS)
      artifacts_checked_text=$(printf '%s\n' "${artifacts_checked[@]}")
      emit_result "$SOURCE_ID" "$HEAD_SHA" "true" "$v_status" "$(printf '%s' "$v_status" | tr '[:upper:]' '[:lower:]')" "$artifacts_checked_text"
      exit 2
      ;;
    *)
      echo "$PREFIX unsupported V-mode ac_verification.status: $v_status" >&2
      exit 64
      ;;
  esac
fi

[[ -n "$REPO_PATH" ]] || { echo "$PREFIX could not resolve repo for T-mode task: $TASK_MD" >&2; exit 64; }
[[ -n "$HEAD_SHA" ]] || { echo "$PREFIX could not resolve HEAD for repo: $REPO_PATH" >&2; exit 64; }

TASK_TICKET="$TICKET_OVERRIDE"
if [[ -z "$TASK_TICKET" ]]; then
  TASK_TICKET="$(parse_field jira_key)"
fi
if [[ -z "$TASK_TICKET" || "$TASK_TICKET" == "N/A" ]]; then
  TASK_TICKET="$(parse_field task_jira_key)"
fi
if [[ -z "$TASK_TICKET" || "$TASK_TICKET" == "N/A" ]]; then
  TASK_TICKET="$(parse_field work_item_id)"
fi
[[ -n "$TASK_TICKET" ]] || { echo "$PREFIX could not resolve ticket/work item identity for $TASK_MD" >&2; exit 64; }

layer_b_path="$(verification_evidence_resolve_existing_path "$REPO_PATH" "$TASK_TICKET" "$HEAD_SHA" 2>/dev/null || true)"
if [[ -z "$layer_b_path" ]]; then
  stale="$(verification_evidence_find_stale_path "$REPO_PATH" "$TASK_TICKET" "$HEAD_SHA" 2>/dev/null || true)"
  artifacts_checked+=("$(verification_evidence_tmp_path "$TASK_TICKET" "$HEAD_SHA")")
  artifacts_checked+=("$(verification_evidence_durable_path "$REPO_PATH" "$TASK_TICKET" "$HEAD_SHA" 2>/dev/null || true)")
  artifacts_checked_text=$(printf '%s\n' "${artifacts_checked[@]}")
  if [[ -n "$stale" ]]; then
    emit_result "$SOURCE_ID" "$HEAD_SHA" "true" "IN_PROGRESS" "stale_layer_b" "$artifacts_checked_text"
  else
    emit_result "$SOURCE_ID" "$HEAD_SHA" "true" "IN_PROGRESS" "missing_layer_b" "$artifacts_checked_text"
  fi
  exit 2
fi
artifacts_checked+=("$layer_b_path")

if ! layer_b_valid="$(verification_evidence_validate_file "$layer_b_path" "$TASK_TICKET" "$HEAD_SHA" 2>/dev/null)"; then
  layer_b_valid="${layer_b_valid:-invalid_layer_b}"
fi
if [[ "$layer_b_valid" != "valid" ]]; then
  artifacts_checked_text=$(printf '%s\n' "${artifacts_checked[@]}")
  emit_result "$SOURCE_ID" "$HEAD_SHA" "true" "FAIL" "invalid_layer_b" "$artifacts_checked_text"
  exit 2
fi
if ! layer_b_pass="$(verification_evidence_is_pass "$layer_b_path" 2>/dev/null)"; then
  layer_b_pass="${layer_b_pass:-exit_code != 0}"
fi
if [[ "$layer_b_pass" != "pass" ]]; then
  artifacts_checked_text=$(printf '%s\n' "${artifacts_checked[@]}")
  emit_result "$SOURCE_ID" "$HEAD_SHA" "true" "FAIL" "fail_layer_b" "$artifacts_checked_text"
  exit 2
fi

VR_EXPECTED="$(parse_field verification_visual_regression_expected)"
if [[ -n "$VR_EXPECTED" ]]; then
  vr_path="$(vr_evidence_resolve_existing_path "$REPO_PATH" "$TASK_TICKET" "$HEAD_SHA" 2>/dev/null || true)"
  if [[ -z "$vr_path" ]]; then
    stale="$(vr_evidence_find_stale_path "$REPO_PATH" "$TASK_TICKET" "$HEAD_SHA" 2>/dev/null || true)"
    artifacts_checked+=("$(vr_evidence_tmp_path "$TASK_TICKET" "$HEAD_SHA")")
    artifacts_checked+=("$(vr_evidence_durable_path "$REPO_PATH" "$TASK_TICKET" "$HEAD_SHA" 2>/dev/null || true)")
    artifacts_checked_text=$(printf '%s\n' "${artifacts_checked[@]}")
    if [[ -n "$stale" ]]; then
      emit_result "$SOURCE_ID" "$HEAD_SHA" "true" "IN_PROGRESS" "stale_layer_c" "$artifacts_checked_text"
    else
      emit_result "$SOURCE_ID" "$HEAD_SHA" "true" "IN_PROGRESS" "missing_layer_c" "$artifacts_checked_text"
    fi
    exit 2
  fi
  artifacts_checked+=("$vr_path")
  if ! vr_valid="$(vr_evidence_validate_file "$vr_path" "$TASK_TICKET" "$HEAD_SHA" compare 2>/dev/null)"; then
    vr_valid="${vr_valid:-invalid_layer_c}"
  fi
  if [[ "$vr_valid" != "valid" ]]; then
    artifacts_checked_text=$(printf '%s\n' "${artifacts_checked[@]}")
    emit_result "$SOURCE_ID" "$HEAD_SHA" "true" "FAIL" "invalid_layer_c" "$artifacts_checked_text"
    exit 2
  fi
  if ! vr_outcome="$(vr_evidence_normalized_outcome "$vr_path" 2>/dev/null)"; then
    vr_outcome="FAIL"
  fi
  if [[ "$vr_outcome" != "PASS" ]]; then
    artifacts_checked_text=$(printf '%s\n' "${artifacts_checked[@]}")
    emit_result "$SOURCE_ID" "$HEAD_SHA" "true" "$vr_outcome" "$(printf '%s' "$vr_outcome" | tr '[:upper:]' '[:lower:]')_layer_c" "$artifacts_checked_text"
    exit 2
  fi
fi

artifacts_checked_text=$(printf '%s\n' "${artifacts_checked[@]}")
emit_result "$SOURCE_ID" "$HEAD_SHA" "true" "PASS" "pass" "$artifacts_checked_text"
exit 0
