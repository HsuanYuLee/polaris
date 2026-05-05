#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/pr-review-thread-disposition-gate.sh"
TMPDIR="$(mktemp -d -t polaris-review-thread-gate-XXXXXX)"
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

THREADS="$TMPDIR/threads.json"
cat > "$THREADS" <<'JSON'
{
  "pullRequest": {
    "url": "https://github.com/example/repo/pull/1",
    "reviewThreads": {
      "nodes": [
        {
          "id": "PRRT_active_1",
          "isResolved": false,
          "isOutdated": false,
          "path": "src/a.ts",
          "line": 10,
          "comments": {"nodes": [{"url": "https://github.com/example/repo/pull/1#discussion_r1"}]}
        },
        {
          "id": "PRRT_resolved",
          "isResolved": true,
          "isOutdated": false,
          "path": "src/b.ts",
          "line": 20,
          "comments": {"nodes": [{"url": "https://github.com/example/repo/pull/1#discussion_r2"}]}
        },
        {
          "id": "PRRT_outdated",
          "isResolved": false,
          "isOutdated": true,
          "path": "src/c.ts",
          "line": 30,
          "comments": {"nodes": [{"url": "https://github.com/example/repo/pull/1#discussion_r3"}]}
        }
      ]
    }
  }
}
JSON

"$CHECK" --threads-json "$THREADS" --manifest "$TMPDIR/missing.json" >/tmp/pr-thread-missing.out 2>/tmp/pr-thread-missing.err
assert_rc "$?" "1" "missing manifest fails when active thread exists"

BAD="$TMPDIR/bad.json"
cat > "$BAD" <<'JSON'
{"version":1,"threads":[{"thread_id":"PRRT_active_1","disposition":"fixed","reason":"short"}]}
JSON
"$CHECK" --threads-json "$THREADS" --manifest "$BAD" >/tmp/pr-thread-bad.out 2>/tmp/pr-thread-bad.err
assert_rc "$?" "1" "short reason fails"

GOOD="$TMPDIR/good.json"
cat > "$GOOD" <<'JSON'
{
  "version": 1,
  "pr": "https://github.com/example/repo/pull/1",
  "threads": [
    {
      "thread_id": "PRRT_active_1",
      "disposition": "fixed",
      "reason": "implemented offset-preserving parser and pushed commit"
    }
  ]
}
JSON
"$CHECK" --threads-json "$THREADS" --manifest "$GOOD" >/tmp/pr-thread-good.out 2>/tmp/pr-thread-good.err
assert_rc "$?" "0" "valid disposition manifest passes"

NO_ACTIVE="$TMPDIR/no-active.json"
cat > "$NO_ACTIVE" <<'JSON'
{"pullRequest":{"reviewThreads":{"nodes":[{"id":"PRRT_old","isResolved":false,"isOutdated":true}]}}}
JSON
"$CHECK" --threads-json "$NO_ACTIVE" --manifest "$TMPDIR/nope.json" >/tmp/pr-thread-none.out 2>/tmp/pr-thread-none.err
assert_rc "$?" "0" "no active unresolved threads passes without manifest"

rm -f /tmp/pr-thread-missing.out /tmp/pr-thread-missing.err \
  /tmp/pr-thread-bad.out /tmp/pr-thread-bad.err \
  /tmp/pr-thread-good.out /tmp/pr-thread-good.err \
  /tmp/pr-thread-none.out /tmp/pr-thread-none.err

printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
