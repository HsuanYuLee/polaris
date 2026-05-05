#!/usr/bin/env bash
# Selftest for validate-dispatch-bundle.sh.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="$script_dir/validate-dispatch-bundle.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

assert_ok() {
  local name="$1"
  shift
  if "$@" >/tmp/validate-dispatch-bundle-test.out 2>/tmp/validate-dispatch-bundle-test.err; then
    pass=$((pass + 1))
  else
    echo "FAIL expected ok: $name" >&2
    cat /tmp/validate-dispatch-bundle-test.err >&2 || true
    fail=$((fail + 1))
  fi
}

assert_fail() {
  local name="$1"
  shift
  if "$@" >/tmp/validate-dispatch-bundle-test.out 2>/tmp/validate-dispatch-bundle-test.err; then
    echo "FAIL expected failure: $name" >&2
    cat /tmp/validate-dispatch-bundle-test.out >&2 || true
    fail=$((fail + 1))
  else
    pass=$((pass + 1))
  fi
}

valid="$tmp/valid.md"
cat > "$valid" <<'EOF'
# Review Inbox Dispatch Context v1
## Review Flow
Use inline instructions.
## Severity And Write Rules
Evidence first.
## Submit Action
Submit the review.
## Completion Envelope
Return Status, Artifacts, Detail, Summary.
EOF

missing="$tmp/missing.md"
cat > "$missing" <<'EOF'
# Review Inbox Dispatch Context v1
## Review Flow
Only one marker.
EOF

forbidden="$tmp/forbidden.md"
cat > "$forbidden" <<'EOF'
# Review Inbox Dispatch Context v1
## Review Flow
讀取 review-pr/SKILL.md 了解完整 review flow。
## Severity And Write Rules
Evidence first.
## Submit Action
Submit the review.
## Completion Envelope
Return Status, Artifacts, Detail, Summary.
EOF

oversized="$tmp/oversized.md"
{
  cat "$valid"
  python3 - <<'PY'
print("x" * 3100)
PY
} > "$oversized"

assert_ok "valid fixture" "$validator" "$valid"
assert_fail "missing marker" "$validator" "$missing"
assert_fail "forbidden read" "$validator" "$forbidden"
assert_fail "oversized bundle" "$validator" "$oversized"

real_bundle="$script_dir/../.claude/skills/review-inbox/dispatch-context-bundle.md"
if [[ -f "$real_bundle" ]]; then
  assert_ok "real bundle" "$validator" "$real_bundle"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "validate-dispatch-bundle selftest: $pass pass, $fail fail" >&2
  exit 1
fi

echo "validate-dispatch-bundle selftest: $pass pass, $fail fail"
