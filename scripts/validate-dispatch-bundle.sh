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

if python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_dispatch_bundle_1.py" "$target"
then
  echo "error: forbidden full-reference read instruction found: $target" >&2
  exit 1
fi

echo "PASS: dispatch bundle valid: $target"
