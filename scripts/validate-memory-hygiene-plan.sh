#!/usr/bin/env bash
# validate-memory-hygiene-plan.sh — validate memory-hygiene dry-run plan artifact.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-memory-hygiene-plan.sh [--input PATH] [--format text|json]

Defaults:
  --input   stdin
  --format  text
EOF
  exit 2
}

input_path=""
format="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      input_path="${2:-}"
      shift 2
      ;;
    --format)
      format="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ "$format" != "text" && "$format" != "json" ]]; then
  echo "error: --format must be text or json" >&2
  exit 2
fi

if [[ -n "$input_path" ]]; then
  if [[ ! -f "$input_path" ]]; then
    echo "error: input file not found: $input_path" >&2
    exit 1
  fi
  python3 - "$input_path" "$format" <<'PY'
import json
import re
import sys
from pathlib import Path

plan_path = Path(sys.argv[1])
fmt = sys.argv[2]
payload_text = plan_path.read_text(encoding="utf-8")

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TOPIC_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
FILE_RE = re.compile(r"^[A-Za-z0-9._-]+\.md$")
VALID_TIERS = {"hot", "warm", "cold"}

issues = []

try:
    data = json.loads(payload_text)
except json.JSONDecodeError as exc:
    issues.append({"code": "invalid_json", "detail": str(exc)})
    data = {}

if not issues:
    if not isinstance(data, dict):
        issues.append({"code": "root_not_object", "detail": "plan root must be a JSON object"})

if not issues:
    date_value = data.get("date")
    if not isinstance(date_value, str) or not DATE_RE.match(date_value):
        issues.append({"code": "invalid_date", "detail": "date must be YYYY-MM-DD"})

    classifications = data.get("classifications")
    if not isinstance(classifications, list) or not classifications:
        issues.append({"code": "missing_classifications", "detail": "classifications must be a non-empty array"})
    else:
        seen = set()
        for idx, item in enumerate(classifications):
            prefix = f"classifications[{idx}]"
            if not isinstance(item, dict):
                issues.append({"code": "classification_not_object", "detail": prefix})
                continue
            file_name = item.get("file")
            tier = item.get("tier")
            topic = item.get("topic")
            reason = item.get("reason")
            pinned = item.get("pinned")
            archived = item.get("archived_in_index")
            trigger_count = item.get("trigger_count")

            if not isinstance(file_name, str) or not FILE_RE.match(file_name) or file_name == "MEMORY.md":
                issues.append({"code": "invalid_file", "detail": f"{prefix}.file"})
            elif file_name in seen:
                issues.append({"code": "duplicate_file", "detail": file_name})
            else:
                seen.add(file_name)

            if tier not in VALID_TIERS:
                issues.append({"code": "invalid_tier", "detail": f"{prefix}.tier={tier}"})

            if not isinstance(reason, str) or not reason.strip():
                issues.append({"code": "missing_reason", "detail": f"{prefix}.reason"})

            if not isinstance(trigger_count, int) or trigger_count < 0:
                issues.append({"code": "invalid_trigger_count", "detail": f"{prefix}.trigger_count"})

            if not isinstance(pinned, bool):
                issues.append({"code": "invalid_pinned", "detail": f"{prefix}.pinned"})

            if not isinstance(archived, bool):
                issues.append({"code": "invalid_archived_flag", "detail": f"{prefix}.archived_in_index"})

            if tier == "warm":
                if topic is not None and (not isinstance(topic, str) or not TOPIC_RE.match(topic)):
                    issues.append({"code": "invalid_warm_topic", "detail": f"{prefix}.topic"})
            else:
                if topic is not None:
                    issues.append({"code": "non_warm_topic_present", "detail": f"{prefix}.topic"})

            if pinned is True and tier != "hot":
                issues.append({"code": "pinned_not_hot", "detail": file_name})

            if archived is True and tier != "cold":
                issues.append({"code": "archived_not_cold", "detail": file_name})

result = {
    "passed": not issues,
    "issues": issues,
}

if fmt == "json":
    print(json.dumps(result, ensure_ascii=False))
else:
    if result["passed"]:
        print("PASS: memory hygiene plan valid")
    else:
        print("FAIL: memory hygiene plan invalid")
        for issue in issues:
            print(f"  - {issue['code']}: {issue['detail']}")

sys.exit(0 if result["passed"] else 1)
PY
else
  python3 - "$format" <<'PY'
import json
import re
import sys

fmt = sys.argv[1]
payload_text = sys.stdin.read()

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TOPIC_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
FILE_RE = re.compile(r"^[A-Za-z0-9._-]+\.md$")
VALID_TIERS = {"hot", "warm", "cold"}

issues = []

try:
    data = json.loads(payload_text)
except json.JSONDecodeError as exc:
    issues.append({"code": "invalid_json", "detail": str(exc)})
    data = {}

if not issues:
    if not isinstance(data, dict):
        issues.append({"code": "root_not_object", "detail": "plan root must be a JSON object"})

if not issues:
    date_value = data.get("date")
    if not isinstance(date_value, str) or not DATE_RE.match(date_value):
        issues.append({"code": "invalid_date", "detail": "date must be YYYY-MM-DD"})

    classifications = data.get("classifications")
    if not isinstance(classifications, list) or not classifications:
        issues.append({"code": "missing_classifications", "detail": "classifications must be a non-empty array"})
    else:
        seen = set()
        for idx, item in enumerate(classifications):
            prefix = f"classifications[{idx}]"
            if not isinstance(item, dict):
                issues.append({"code": "classification_not_object", "detail": prefix})
                continue
            file_name = item.get("file")
            tier = item.get("tier")
            topic = item.get("topic")
            reason = item.get("reason")
            pinned = item.get("pinned")
            archived = item.get("archived_in_index")
            trigger_count = item.get("trigger_count")

            if not isinstance(file_name, str) or not FILE_RE.match(file_name) or file_name == "MEMORY.md":
                issues.append({"code": "invalid_file", "detail": f"{prefix}.file"})
            elif file_name in seen:
                issues.append({"code": "duplicate_file", "detail": file_name})
            else:
                seen.add(file_name)

            if tier not in VALID_TIERS:
                issues.append({"code": "invalid_tier", "detail": f"{prefix}.tier={tier}"})

            if not isinstance(reason, str) or not reason.strip():
                issues.append({"code": "missing_reason", "detail": f"{prefix}.reason"})

            if not isinstance(trigger_count, int) or trigger_count < 0:
                issues.append({"code": "invalid_trigger_count", "detail": f"{prefix}.trigger_count"})

            if not isinstance(pinned, bool):
                issues.append({"code": "invalid_pinned", "detail": f"{prefix}.pinned"})

            if not isinstance(archived, bool):
                issues.append({"code": "invalid_archived_flag", "detail": f"{prefix}.archived_in_index"})

            if tier == "warm":
                if topic is not None and (not isinstance(topic, str) or not TOPIC_RE.match(topic)):
                    issues.append({"code": "invalid_warm_topic", "detail": f"{prefix}.topic"})
            else:
                if topic is not None:
                    issues.append({"code": "non_warm_topic_present", "detail": f"{prefix}.topic"})

            if pinned is True and tier != "hot":
                issues.append({"code": "pinned_not_hot", "detail": file_name})

            if archived is True and tier != "cold":
                issues.append({"code": "archived_not_cold", "detail": file_name})

result = {
    "passed": not issues,
    "issues": issues,
}

if fmt == "json":
    print(json.dumps(result, ensure_ascii=False))
else:
    if result["passed"]:
        print("PASS: memory hygiene plan valid")
    else:
        print("FAIL: memory hygiene plan invalid")
        for issue in issues:
            print(f"  - {issue['code']}: {issue['detail']}")

sys.exit(0 if result["passed"] else 1)
PY
fi
