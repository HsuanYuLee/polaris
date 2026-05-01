#!/usr/bin/env bash
set -euo pipefail

# scripts/gate-pr-body-template-selftest.sh — selftest for gate-pr-body-template.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$SCRIPT_DIR/gates/gate-pr-body-template.sh"
TMPROOT="$(mktemp -d -t pr-body-template-selftest-XXXXXX)"
PASS=0
TOTAL=0

cleanup() {
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

assert_rc() {
  local label="$1"
  local got="$2"
  local want="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: got rc=%s want rc=%s\n' "$label" "$got" "$want" >&2
  fi
}

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: missing %q\n' "$label" "$needle" >&2
  fi
}

repo="$TMPROOT/repo"
mkdir -p "$repo/.github"
cat > "$repo/.github/pull_request_template.md" <<'EOF'
## Description

<!-- What changed -->

## Changed

<!-- Technical changes -->

## Screenshots (Test Plan)

<!-- Evidence -->

## Related documents

<!-- Links -->

## QA notes

<!-- QA -->
EOF

valid_body="$TMPROOT/valid.md"
cat > "$valid_body" <<'EOF'
## Description

Implement the scoped change.

## Changed

- Updated one file.

## Evidence Summary

| Layer | Status |
|-------|--------|
| A | PASS |

## Screenshots (Test Plan)

- Unit tests pass.

## Related documents

- JIRA: DEMO-1

## QA notes

- N/A
EOF

bad_body="$TMPROOT/bad.md"
cat > "$bad_body" <<'EOF'
## Summary

- Implemented the scoped change.

## Verification

- Tests pass.
EOF

escaped_body="$TMPROOT/escaped.md"
cat > "$escaped_body" <<'EOF'
## Description

\`apps/main/package.json\`

## Changed

- Updated one file.

## Screenshots (Test Plan)

- Unit tests pass.

## Related documents

- JIRA: DEMO-1

## QA notes

- N/A
EOF

set +e
out="$("$GATE" --repo "$repo" --body-file "$valid_body" 2>&1)"
rc=$?
set -e
assert_rc "valid body passes" "$rc" "0"
assert_contains "valid message" "$out" "preserves repo template headings"

set +e
out="$("$GATE" --repo "$repo" --body-file "$bad_body" 2>&1)"
rc=$?
set -e
assert_rc "summary body blocks" "$rc" "2"
assert_contains "summary body missing template" "$out" "Description"

set +e
out="$("$GATE" --repo "$repo" --body-file "$escaped_body" 2>&1)"
rc=$?
set -e
assert_rc "escaped backtick blocks" "$rc" "2"
assert_contains "escaped backtick message" "$out" "escaped Markdown backticks"

printf '\n=== pr-body-template selftest: %d/%d PASS ===\n' "$PASS" "$TOTAL"
[[ "$PASS" -eq "$TOTAL" ]]
