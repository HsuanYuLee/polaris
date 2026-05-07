#!/usr/bin/env bash
set -euo pipefail

ROOT=""
ALLOW_SCAN_FAILURES=false
SKIP_DIRECT_SOURCE=false
SAMPLE_TASK=""

usage() {
  cat >&2 <<'EOF'
Usage:
  verify-refinement-convergence.sh --root <workspace_root> [--allow-scan-failures] [--skip-direct-source] [--sample-task <path>]

Default contract:
  - sample task frontmatter must contain explicit status
  - docs-manager direct-source contract must pass
  - canonical refinement scan must be fully green

--allow-scan-failures keeps the report deterministic but does not fail on remaining
safe_empty / needs_review / schema_error backlog. This is intended for pre-wash stages.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT="${2:-}"
      shift 2
      ;;
    --allow-scan-failures)
      ALLOW_SCAN_FAILURES=true
      shift
      ;;
    --skip-direct-source)
      SKIP_DIRECT_SOURCE=true
      shift
      ;;
    --sample-task)
      SAMPLE_TASK="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "--root is required and must exist" >&2
  exit 64
fi

ROOT="$(cd "$ROOT" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKFILL_SCRIPT="${SCRIPT_DIR}/backfill-refinement-predecessor-audit.sh"
VALIDATOR_SCRIPT="${SCRIPT_DIR}/validate-refinement-json.sh"
DIRECT_SOURCE_SCRIPT="${SCRIPT_DIR}/verify-docs-manager-direct-source.sh"

if [[ -z "$SAMPLE_TASK" ]]; then
  SAMPLE_TASK="$(python3 - "$ROOT" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
companies_root = root / "docs-manager" / "src" / "content" / "docs" / "specs" / "companies"

def has_status_frontmatter(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return False
    match = re.match(r"(?s)^---\n(.*?)\n---\n", text)
    if not match:
        return False
    return bool(re.search(r"(?m)^status:\s*\S", match.group(1)))

candidates = sorted(companies_root.glob("*/*/tasks/T1/index.md")) if companies_root.is_dir() else []
preferred = [path for path in candidates if has_status_frontmatter(path)]
selected = preferred[0] if preferred else (candidates[0] if candidates else None)
print(selected if selected else "")
PY
)"
fi

if [[ -z "$SAMPLE_TASK" ]]; then
  echo "failed to resolve representative sample task under canonical company specs" >&2
  exit 1
fi

BACKFILL_JSON="$(bash "$BACKFILL_SCRIPT" --root "$ROOT" --mode report --format json)"
SCAN_OUTPUT="$(bash "$VALIDATOR_SCRIPT" --scan "$ROOT")"

python3 - "$BACKFILL_JSON" "$SCAN_OUTPUT" "$SAMPLE_TASK" "$ALLOW_SCAN_FAILURES" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

backfill_payload = json.loads(sys.argv[1])
scan_output = sys.argv[2]
sample_task = Path(sys.argv[3])
allow_scan_failures = sys.argv[4] == "true"

summary = backfill_payload["summary"]
records = backfill_payload["records"]
status_map = {record["path"]: record["status"] for record in records}

summary_line = ""
for line in scan_output.splitlines():
    if line.startswith("refinement.json scan:"):
        summary_line = line.strip()
if not summary_line:
    print("FAIL: validator scan summary line missing", file=sys.stderr)
    raise SystemExit(1)

match = re.match(r"refinement\.json scan: (\d+) pass, (\d+) fail \(total (\d+)\)", summary_line)
if not match:
    print(f"FAIL: unexpected validator scan summary: {summary_line}", file=sys.stderr)
    raise SystemExit(1)

validator_pass = int(match.group(1))
validator_fail = int(match.group(2))
validator_total = int(match.group(3))

status_present = False
if sample_task.is_file():
    text = sample_task.read_text(encoding="utf-8")
    frontmatter_match = re.match(r"(?s)^---\n(.*?)\n---\n", text)
    if frontmatter_match:
        status_present = bool(re.search(r"(?m)^status:\s*\S", frontmatter_match.group(1)))

derived_fail = summary["safe_empty"] + summary["needs_review"] + summary["schema_error"]
scan_consistent = (
    validator_total == summary["total"]
    and validator_pass == summary["already_ok"]
    and validator_fail == derived_fail
)

print(f"root={summary['root']}")
print(f"total={summary['total']}")
print(f"already_ok={summary['already_ok']}")
print(f"safe_empty={summary['safe_empty']}")
print(f"needs_review={summary['needs_review']}")
print(f"schema_error={summary['schema_error']}")
print(f"validator_pass={validator_pass}")
print(f"validator_fail={validator_fail}")
print(f"validator_total={validator_total}")
print(f"scan_consistent={'true' if scan_consistent else 'false'}")
print(f"sample_status_frontmatter={'true' if status_present else 'false'}")
print(f"allow_scan_failures={'true' if allow_scan_failures else 'false'}")

if not status_present:
    print(f"FAIL: sample task missing explicit status frontmatter: {sample_task}", file=sys.stderr)
    raise SystemExit(1)
if not scan_consistent:
    print("FAIL: backfill classifier and validator scan are out of sync", file=sys.stderr)
    raise SystemExit(1)
if not allow_scan_failures and derived_fail > 0:
    print("FAIL: canonical refinement scan still has backlog", file=sys.stderr)
    raise SystemExit(1)
PY

if [[ "$SKIP_DIRECT_SOURCE" == true ]]; then
  echo "direct_source=SKIP"
else
  bash "$DIRECT_SOURCE_SCRIPT" >/dev/null
  echo "direct_source=PASS"
fi

echo "PASS: refinement convergence verified"
