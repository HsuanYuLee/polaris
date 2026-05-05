#!/usr/bin/env bash
# Validate the decision ledger used when manually rebuilding a stacked branch.
#
# Usage:
#   stack-replay-manifest-check.sh --manifest PATH [--allow-empty-excluded]
#
# Required markdown shape:
#   # Stack Replay Manifest
#   ## Included Commits
#   - `<sha>` — reason
#   ## Excluded Commits
#   - `<sha>` — reason
#
# The script checks format only. It intentionally does not decide whether a
# commit belongs in or out; that judgment must be written in the manifest.

set -uo pipefail

MANIFEST=""
ALLOW_EMPTY_EXCLUDED=0

usage() {
  cat >&2 <<'EOF'
Usage:
  stack-replay-manifest-check.sh --manifest PATH [--allow-empty-excluded]

Validates a manual stacked-branch replay manifest with Included Commits and
Excluded Commits sections. Each non-empty section item must include a commit
SHA in backticks and a non-empty reason after an em dash or hyphen.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    --allow-empty-excluded) ALLOW_EMPTY_EXCLUDED=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "stack-replay-manifest-check: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$MANIFEST" ]]; then
  echo "stack-replay-manifest-check: --manifest is required" >&2
  usage
  exit 2
fi
if [[ ! -f "$MANIFEST" ]]; then
  echo "stack-replay-manifest-check: manifest not found: $MANIFEST" >&2
  exit 1
fi

python3 - "$MANIFEST" "$ALLOW_EMPTY_EXCLUDED" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
allow_empty_excluded = sys.argv[2] == "1"
text = path.read_text(encoding="utf-8")
lines = text.splitlines()

errors = []

if "Stack Replay Manifest" not in text:
    errors.append("missing title containing 'Stack Replay Manifest'")

heading_re = re.compile(r"^##\s+(.+?)\s*$")
sections = {}
current = None
for line in lines:
    m = heading_re.match(line)
    if m:
        current = m.group(1).strip()
        sections[current] = []
        continue
    if current:
        sections[current].append(line)

required = ["Included Commits", "Excluded Commits"]
for name in required:
    if name not in sections:
        errors.append(f"missing section: ## {name}")

item_re = re.compile(r"^\s*[-*]\s+`([0-9a-fA-F]{7,40})`\s+(?:—|-)\s+(.+?)\s*$")

def validate_items(name, allow_empty=False):
    body = sections.get(name, [])
    items = [line for line in body if line.strip().startswith(("-", "*"))]
    if not items:
        if not allow_empty:
            errors.append(f"section has no commit items: ## {name}")
        return 0
    for idx, line in enumerate(items, start=1):
        m = item_re.match(line)
        if not m:
            errors.append(
                f"invalid item in ## {name} line {idx}: expected '- `<sha>` — reason'"
            )
            continue
        reason = m.group(2).strip()
        if len(reason) < 8:
            errors.append(f"reason too short in ## {name} line {idx}")
    return len(items)

included = validate_items("Included Commits")
excluded = validate_items("Excluded Commits", allow_empty=allow_empty_excluded)

if errors:
    print("FAIL: stack replay manifest invalid", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(f"PASS: stack replay manifest valid (included={included}, excluded={excluded})")
PY
