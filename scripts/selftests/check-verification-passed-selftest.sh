#!/usr/bin/env bash
# Selftest for shared Layer B/Layer C and V-task verification disposition gates.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/check-verification-passed.sh"
RUN_VERIFY="$ROOT_DIR/scripts/run-verify-command.sh"

tmpdir="$(mktemp -d -t check-verification-passed-selftest.XXXXXX)"
cleanup() {
  if [[ "${DEBUG:-}" == "1" ]]; then
    echo "DEBUG: preserving fixture at $tmpdir" >&2
    return
  fi
  rm -rf "$tmpdir"
  rm -f /tmp/polaris-verified-CHK-* /tmp/polaris-vr-CHK-* 2>/dev/null || true
}
trap cleanup EXIT
rm -f /tmp/polaris-verified-CHK-* /tmp/polaris-vr-CHK-* 2>/dev/null || true

repo="$tmpdir/fake-repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email "polaris@example.invalid"
git -C "$repo" config user.name "Polaris Selftest"
printf 'fixture\n' >"$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -q -m "init"
head_sha="$(git -C "$repo" rev-parse HEAD)"

write_t_task() {
  local file="$1"
  local frontmatter="$2"
  cat >"$file" <<EOF
---
title: "Work Order - T1: verification gate fixture (1 pt)"
description: "Task-centric verification gate fixture."
${frontmatter}
---

# T1: verification gate fixture (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: CHK-1 | Repo: fake-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | CHK-1 |
| Test sub-tasks | N/A |
| AC 驗收單 | N/A |
| Base branch | main |
| Branch chain | main -> task/DP-999-T1-fixture |
| Task branch | task/DP-999-T1-fixture |
| Depends on | N/A |
| References to load | - \`skills/references/task-md-schema.md\` |

## Verification Handoff

驗證交給 shared gate。

## 目標

驗證 shared verification gate。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| README.md | modify | fixture |

## Allowed Files

- README.md

## 估點理由

1 pt - selftest fixture。

## 測試計畫（code-level）

- verify gate fixture

## Test Command

\`\`\`bash
echo PASS
\`\`\`

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

\`\`\`bash
echo PASS
\`\`\`
EOF
}

write_v_task() {
  local file="$1"
  local ac_block="$2"
  cat >"$file" <<EOF
---
title: "Work Order - V1: verification gate fixture (1 pt)"
description: "V-mode verification gate fixture."
status: IN_PROGRESS
${ac_block}
---

# V1: verification gate fixture (1 pt)

> Epic: EP-999 | JIRA: CHK-9 | Repo: fake-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | CHK-9 |
| Parent Epic | EP-999 |
| Implementation tasks | T1 |
| Base branch | feat/ep-999-fixture |
| Depends on | N/A |
| References to load | - \`skills/references/task-md-schema.md\` |

## Verification Handoff

驗收委派 verify-AC。

## 目標

驗證 V-mode verification gate。

## 驗收項目

- AC-1: fixture

## 估點理由

1 pt - selftest fixture。

## 驗收計畫（AC level）

- 驗證 ac_verification lifecycle。

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## 驗收步驟

\`\`\`bash
echo "verify-AC executes this fixture"
\`\`\`
EOF
}

write_layer_b() {
  local ticket="$1"
  local expected_exit="$2"
  local task_md="$3"
  local actual_exit=0

  set +e
  "$RUN_VERIFY" --task-md "$task_md" --ticket "$ticket" --repo "$repo" >/dev/null 2>&1
  actual_exit=$?
  set -e

  if [[ "$expected_exit" -eq 0 && "$actual_exit" -ne 0 ]]; then
    echo "FAIL: expected run-verify-command to pass for $ticket, got $actual_exit" >&2
    exit 1
  fi
  if [[ "$expected_exit" -ne 0 && "$actual_exit" -eq 0 ]]; then
    echo "FAIL: expected run-verify-command to fail for $ticket" >&2
    exit 1
  fi
}

write_layer_c() {
  local ticket="$1"
  local status="$2"
  python3 - "$ticket" "$head_sha" "$status" <<'PY'
import json
import sys
from datetime import datetime, timezone

ticket, head_sha, status = sys.argv[1:4]
payload = {
    "writer": "run-visual-snapshot.sh",
    "ticket": ticket,
    "head_sha": head_sha,
    "mode": "compare",
    "status": status,
    "at": datetime.now(timezone.utc).isoformat(),
}
with open(f"/tmp/polaris-vr-{ticket}-{head_sha}.json", "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
PY
}

assert_json_field() {
  local file="$1"
  local field="$2"
  local expected="$3"
  python3 - "$file" "$field" "$expected" <<'PY'
import json
import sys

path, field, expected = sys.argv[1:4]
value = json.load(open(path, encoding="utf-8")).get(field)
if str(value).lower() != expected.lower():
    raise SystemExit(f"expected {field}={expected}, got {value}")
PY
}

expect_pass() {
  local label="$1"
  shift
  local out="$tmpdir/$label.out"
  if ! "$SCRIPT" "$@" >"$out"; then
    echo "FAIL: expected pass for $label" >&2
    cat "$out" >&2
    exit 1
  fi
}

expect_block_contains() {
  local label="$1"
  local needle="$2"
  shift 2
  local out="$tmpdir/$label.out"
  set +e
  "$SCRIPT" "$@" >"$out"
  local rc=$?
  set -e
  if [[ "$rc" -ne 2 ]]; then
    echo "FAIL: expected block exit 2 for $label, got $rc" >&2
    cat "$out" >&2
    exit 1
  fi
  if ! grep -q "$needle" "$out"; then
    echo "FAIL: expected $label output to contain '$needle'" >&2
    cat "$out" >&2
    exit 1
  fi
}

t_task="$tmpdir/T1.md"
write_t_task "$t_task" ""

write_layer_b "CHK-1" 0 "$t_task"
expect_pass "t-pass" --task-md "$t_task" --repo "$repo"

cp "$t_task" "$tmpdir/T1.original.md"
python3 - "$t_task" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text(encoding="utf-8").replace("echo PASS", "echo DRIFT"), encoding="utf-8")
PY
expect_block_contains "t-command-drift" "stale_layer_b_identity" --task-md "$t_task" --repo "$repo"
cp "$tmpdir/T1.original.md" "$t_task"

rm -f /tmp/polaris-verified-CHK-2-* 2>/dev/null || true
t_missing="$tmpdir/T2.md"
sed 's/CHK-1/CHK-2/g' "$t_task" >"$t_missing"
expect_block_contains "t-missing-layer-b" "missing_layer_b" --task-md "$t_missing" --repo "$repo"

t_fail="$tmpdir/T3.md"
sed 's/CHK-1/CHK-3/g' "$t_task" >"$t_fail"
python3 - "$t_fail" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text(encoding="utf-8").replace("echo PASS", "exit 1"), encoding="utf-8")
PY
write_layer_b "CHK-3" 1 "$t_fail"
expect_block_contains "t-fail-layer-b" "fail_layer_b" --task-md "$t_fail" --repo "$repo"

t_vr="$tmpdir/T4.md"
write_t_task "$t_vr" 'verification:
  visual_regression:
    expected: none_allowed
    pages: ["/page.html"]'
sed -i '' 's/CHK-1/CHK-4/g' "$t_vr" 2>/dev/null || python3 - "$t_vr" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text(encoding="utf-8").replace("CHK-1", "CHK-4"), encoding="utf-8")
PY
write_layer_b "CHK-4" 0 "$t_vr"
expect_block_contains "t-missing-layer-c" "missing_layer_c" --task-md "$t_vr" --repo "$repo"

write_layer_c "CHK-4" "BLOCKED_ENV"
expect_block_contains "t-blocked-env-layer-c" "blocked_env_layer_c" --task-md "$t_vr" --repo "$repo"

write_layer_c "CHK-4" "PASS"
expect_pass "t-pass-layer-c" --task-md "$t_vr" --repo "$repo" --format json
assert_json_field "$tmpdir/t-pass-layer-c.out" "status" "PASS"

v_missing="$tmpdir/V1/index.md"
mkdir -p "$(dirname "$v_missing")"
write_v_task "$v_missing" ""
expect_block_contains "v-missing" "missing_ac_verification" --task-md "$v_missing" --repo "$repo"

v_pass="$tmpdir/V2/index.md"
mkdir -p "$(dirname "$v_pass")"
write_v_task "$v_pass" 'ac_verification:
  status: PASS
  last_run_at: 2026-05-08T00:00:00Z
  ac_total: 1
  ac_pass: 1
  ac_fail: 0
  ac_manual_required: 0
  ac_uncertain: 0'
expect_pass "v-pass" --task-md "$v_pass" --repo "$repo"

v_invalid="$tmpdir/V4/index.md"
mkdir -p "$(dirname "$v_invalid")"
write_v_task "$v_invalid" 'ac_verification:
  status: PASS'
expect_block_contains "v-invalid-schema" "invalid_ac_verification_schema" --task-md "$v_invalid" --repo "$repo"

v_blocked="$tmpdir/V3/index.md"
mkdir -p "$(dirname "$v_blocked")"
write_v_task "$v_blocked" 'ac_verification:
  status: BLOCKED_ENV
  last_run_at: 2026-05-08T00:00:00Z
  ac_total: 1
  ac_pass: 0
  ac_fail: 0
  ac_manual_required: 0
  ac_uncertain: 1
  human_disposition: deferred'
expect_block_contains "v-blocked" "status=BLOCKED_ENV" --task-md "$v_blocked" --repo "$repo"

echo "PASS: check-verification-passed selftest"
