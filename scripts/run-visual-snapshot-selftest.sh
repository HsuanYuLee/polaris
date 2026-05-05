#!/usr/bin/env bash
# Selftest for scripts/run-visual-snapshot.sh vertical slice behavior.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT_DIR/scripts/run-visual-snapshot.sh"
FIXTURE_REVIEW="$ROOT_DIR/scripts/mockoon/visual-fixture-review.mjs"
INCLUDE_MOCKOON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-mockoon) INCLUDE_MOCKOON=true; shift ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--include-mockoon]"
      exit 0
      ;;
    *) echo "run-visual-snapshot-selftest: unknown arg: $1" >&2; exit 2 ;;
  esac
done

tmpdir="$(mktemp -d -t polaris-vr-selftest.XXXXXX)"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

pick_port() {
  python3 - <<'PY'
import socket
sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
}

write_task() {
  local file="$1"
  local frontmatter="$2"
  local level="$3"
  local target="$4"
  local fixtures="${5:-N/A}"

  cat >"$file" <<EOF
---
title: "Work Order - T2: VR runner selftest (1 pt)"
description: "Fixture task for run-visual-snapshot selftest."
${frontmatter}
---

# T2: VR runner selftest (1 pt)

> Source: DP-104 | Task: DP-104-T2 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-104 |
| Task ID | DP-104-T2 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-104-T2-vr-selftest |
| Task branch | task/DP-104-T2-vr-selftest |
| Depends on | N/A |
| References to load | - task-md-schema |

## Test Environment

- **Level**: ${level}
- **Dev env config**: N/A
- **Fixtures**: ${fixtures}
- **Runtime verify target**: ${target}
- **Env bootstrap command**: N/A
EOF
}

assert_evidence_status() {
  local evidence="$1"
  local expected="$2"
  python3 - "$evidence" "$expected" <<'PY'
import json
import sys

path, expected = sys.argv[1:3]
data = json.load(open(path, encoding="utf-8"))
actual = data.get("status")
if actual != expected:
    raise SystemExit(f"expected status {expected}, got {actual}")
PY
}

port="$(pick_port)"
webroot="$tmpdir/web"
mkdir -p "$webroot"
cat >"$webroot/page.html" <<'HTML'
<!doctype html>
<html>
  <body>
    <main style="font-family: sans-serif; padding: 32px">
      <h1>Polaris VR baseline</h1>
      <p>stable visual content</p>
    </main>
  </body>
</html>
HTML

python3 -m http.server "$port" --bind 127.0.0.1 --directory "$webroot" >/dev/null 2>&1 &
server_pid="$!"

for _ in 1 2 3 4 5; do
  if curl -fsS "http://127.0.0.1:$port/page.html" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -fsS "http://127.0.0.1:$port/page.html" >/dev/null

head_sha="$(git -C "$ROOT_DIR" rev-parse HEAD)"

same_task="$tmpdir/T2-same.md"
write_task "$same_task" 'verification:
  visual_regression:
    expected: none_allowed
    pages: ["/page.html"]' "runtime" "http://127.0.0.1:$port/page.html"

same_out="$tmpdir/out-same"
bash "$RUNNER" --task-md "$same_task" --mode baseline --ticket DP-104-T2-SAME --repo "$ROOT_DIR" --output-dir "$same_out" >/dev/null
bash "$RUNNER" --task-md "$same_task" --mode compare --ticket DP-104-T2-SAME --repo "$ROOT_DIR" --output-dir "$same_out" >/dev/null
assert_evidence_status "/tmp/polaris-vr-DP-104-T2-SAME-$head_sha.json" "PASS"

changed_task="$tmpdir/T2-changed.md"
write_task "$changed_task" 'verification:
  visual_regression:
    expected: none_allowed
    pages: ["/page.html"]' "runtime" "http://127.0.0.1:$port/page.html"

changed_out="$tmpdir/out-changed"
bash "$RUNNER" --task-md "$changed_task" --mode baseline --ticket DP-104-T2-CHANGED --repo "$ROOT_DIR" --output-dir "$changed_out" >/dev/null
cat >"$webroot/page.html" <<'HTML'
<!doctype html>
<html>
  <body>
    <main style="font-family: sans-serif; padding: 32px">
      <h1>Polaris VR changed</h1>
      <p>changed visual content</p>
    </main>
  </body>
</html>
HTML
set +e
bash "$RUNNER" --task-md "$changed_task" --mode compare --ticket DP-104-T2-CHANGED --repo "$ROOT_DIR" --output-dir "$changed_out" >/dev/null
changed_rc=$?
set -e
if [[ "$changed_rc" -eq 0 ]]; then
  echo "FAIL: expected changed compare to exit non-zero"
  exit 1
fi
assert_evidence_status "/tmp/polaris-vr-DP-104-T2-CHANGED-$head_sha.json" "BLOCK"

skip_task="$tmpdir/T2-skip.md"
write_task "$skip_task" "" "static" "N/A"
bash "$RUNNER" --task-md "$skip_task" --mode baseline --ticket DP-104-T2-SKIP --repo "$ROOT_DIR" --output-dir "$tmpdir/out-skip" >/dev/null
assert_evidence_status "/tmp/polaris-vr-DP-104-T2-SKIP-$head_sha.json" "SKIP"

blocked_task="$tmpdir/T2-blocked.md"
write_task "$blocked_task" 'verification:
  visual_regression:
    expected: none_allowed
    pages: []' "static" "N/A"
set +e
bash "$RUNNER" --task-md "$blocked_task" --mode baseline --ticket DP-104-T2-BLOCKED --repo "$ROOT_DIR" --output-dir "$tmpdir/out-blocked" >/dev/null 2>&1
blocked_rc=$?
set -e
if [[ "$blocked_rc" -eq 0 ]]; then
  echo "FAIL: expected static VR declaration to exit non-zero"
  exit 1
fi
assert_evidence_status "/tmp/polaris-vr-DP-104-T2-BLOCKED-$head_sha.json" "BLOCKED_ENV"

if [[ "$INCLUDE_MOCKOON" == "true" ]]; then
  fixture_task="$tmpdir/T4-fixture.md"
  fixture_dir="$tmpdir/mockoon-fixtures"
  fixture_out="$tmpdir/out-fixture"

  cat >"$webroot/page.html" <<'HTML'
<!doctype html>
<html>
  <body>
    <main style="font-family: sans-serif; padding: 32px">
      <h1>Polaris VR fixture record</h1>
      <p>recorded deterministic fixture content</p>
    </main>
  </body>
</html>
HTML

  write_task "$fixture_task" 'verification:
  visual_regression:
    expected: none_allowed
    pages: ["/page.html"]' "runtime" "http://127.0.0.1:$port/page.html" "$fixture_dir"

  set +e
  bash "$RUNNER" --task-md "$fixture_task" --mode baseline --ticket DP-104-T4-MISSING --repo "$ROOT_DIR" --output-dir "$fixture_out" --fixture-dir "$tmpdir/missing-fixtures" >/dev/null 2>&1
  missing_rc=$?
  set -e
  if [[ "$missing_rc" -eq 0 ]]; then
    echo "FAIL: expected missing fixture replay to exit non-zero"
    exit 1
  fi
  assert_evidence_status "/tmp/polaris-vr-DP-104-T4-MISSING-$head_sha.json" "BLOCKED_ENV"

  set +e
  bash "$RUNNER" --task-md "$fixture_task" --mode record --ticket DP-104-T4-RECORD --repo "$ROOT_DIR" --output-dir "$fixture_out" --fixture-dir "$fixture_dir" >/dev/null 2>&1
  record_rc=$?
  set -e
  if [[ "$record_rc" -eq 0 ]]; then
    echo "FAIL: expected record mode to require manual review"
    exit 1
  fi
  assert_evidence_status "/tmp/polaris-vr-DP-104-T4-RECORD-$head_sha.json" "MANUAL_REQUIRED"
  node "$FIXTURE_REVIEW" --manifest "$fixture_dir/visual-fixtures.json" --assert-reviewed false >/dev/null

  set +e
  bash "$RUNNER" --task-md "$fixture_task" --mode baseline --ticket DP-104-T4-UNREVIEWED --repo "$ROOT_DIR" --output-dir "$fixture_out" --fixture-dir "$fixture_dir" >/dev/null 2>&1
  unreviewed_rc=$?
  set -e
  if [[ "$unreviewed_rc" -eq 0 ]]; then
    echo "FAIL: expected unreviewed fixture replay to exit non-zero"
    exit 1
  fi
  assert_evidence_status "/tmp/polaris-vr-DP-104-T4-UNREVIEWED-$head_sha.json" "MANUAL_REQUIRED"

  node "$FIXTURE_REVIEW" --manifest "$fixture_dir/visual-fixtures.json" --set-reviewed true --assert-reviewed true >/dev/null
  bash "$RUNNER" --task-md "$fixture_task" --mode baseline --ticket DP-104-T4-REPLAY --repo "$ROOT_DIR" --output-dir "$fixture_out" --fixture-dir "$fixture_dir" >/dev/null

  cat >"$webroot/page.html" <<'HTML'
<!doctype html>
<html>
  <body>
    <main style="font-family: sans-serif; padding: 32px">
      <h1>Polaris VR live page changed</h1>
      <p>this live variance must not affect fixture replay</p>
    </main>
  </body>
</html>
HTML

  bash "$RUNNER" --task-md "$fixture_task" --mode compare --ticket DP-104-T4-REPLAY --repo "$ROOT_DIR" --output-dir "$fixture_out" --fixture-dir "$fixture_dir" >/dev/null
  assert_evidence_status "/tmp/polaris-vr-DP-104-T4-REPLAY-$head_sha.json" "PASS"
fi

echo "PASS: visual snapshot selftest"
