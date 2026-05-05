#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/stack-replay-manifest-check.sh"
TMPDIR="$(mktemp -d -t polaris-stack-replay-selftest-XXXXXX)"
PASS=0
FAIL=0

cleanup() {
  rm -rf "$TMPDIR" 2>/dev/null || true
}
trap cleanup EXIT

assert_rc() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAIL] %s: want rc=%s got=%s\n' "$label" "$want" "$got"
  fi
}

VALID="$TMPDIR/valid.md"
cat > "$VALID" <<'EOF'
# Stack Replay Manifest

## Included Commits

- `abc1234` — feature migration commit kept for task scope
- `def567890` - review fix kept because it changes migrated call sites

## Excluded Commits

- `1111111` — unrelated type baseline recovery outside task scope
EOF

"$CHECK" --manifest "$VALID" >/tmp/stack-replay-valid.out 2>/tmp/stack-replay-valid.err
assert_rc "$?" "0" "valid manifest passes"

INVALID="$TMPDIR/invalid.md"
cat > "$INVALID" <<'EOF'
# Stack Replay Manifest

## Included Commits

- abc1234 no reason
EOF

"$CHECK" --manifest "$INVALID" >/tmp/stack-replay-invalid.out 2>/tmp/stack-replay-invalid.err
assert_rc "$?" "1" "invalid manifest fails"

EMPTY_EXCLUDED="$TMPDIR/empty-excluded.md"
cat > "$EMPTY_EXCLUDED" <<'EOF'
# Stack Replay Manifest

## Included Commits

- `abc1234` — single clean feature commit included

## Excluded Commits

N/A
EOF

"$CHECK" --manifest "$EMPTY_EXCLUDED" --allow-empty-excluded >/tmp/stack-replay-empty.out 2>/tmp/stack-replay-empty.err
assert_rc "$?" "0" "empty excluded section can be explicit"

rm -f /tmp/stack-replay-valid.out /tmp/stack-replay-valid.err \
  /tmp/stack-replay-invalid.out /tmp/stack-replay-invalid.err \
  /tmp/stack-replay-empty.out /tmp/stack-replay-empty.err

printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
