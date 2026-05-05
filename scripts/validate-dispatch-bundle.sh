#!/usr/bin/env bash
# validate-dispatch-bundle.sh — Validate review-inbox dispatch context bundles and prompts.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-dispatch-bundle.sh <bundle-or-prompt-path>

Validates:
  - file exists
  - byte size <= 3072
  - required dispatch markers are present
  - forbidden full-reference read instructions are absent
EOF
  exit 2
}

if [[ $# -ne 1 ]]; then
  usage
fi

target="$1"
if [[ ! -f "$target" ]]; then
  echo "error: file not found: $target" >&2
  exit 2
fi

size=$(wc -c < "$target" | tr -d '[:space:]')
if [[ "$size" -gt 3072 ]]; then
  echo "error: dispatch bundle is too large: ${size} bytes (max 3072): $target" >&2
  exit 1
fi

required_patterns=(
  "Review Flow"
  "Severity And Write Rules"
  "Submit Action"
  "Completion Envelope"
)

for pattern in "${required_patterns[@]}"; do
  if ! rg -q --fixed-strings "$pattern" "$target"; then
    echo "error: missing required marker '$pattern': $target" >&2
    exit 1
  fi
done

if python3 - "$target" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
patterns = [
    r"(讀取|讀|Read|read|load|Load).{0,80}review-pr/SKILL\.md",
    r"(讀取|讀|Read|read|load|Load).{0,80}review-pr-[A-Za-z0-9_-]+-flow\.md",
    r"(讀取|讀|Read|read|load|Load).{0,80}repo-handbook\.md",
]
for pattern in patterns:
    if re.search(pattern, text, re.IGNORECASE | re.DOTALL):
        sys.exit(0)
sys.exit(1)
PY
then
  echo "error: forbidden full-reference read instruction found: $target" >&2
  exit 1
fi

echo "PASS: dispatch bundle valid: $target"
