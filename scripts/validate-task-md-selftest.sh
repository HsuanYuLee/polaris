#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATE="$SCRIPT_DIR/validate-task-md.sh"
TMPROOT="$(mktemp -d -t validate-task-md-snapshot-XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

task="$TMPROOT/task.md"
snapshot="$TMPROOT/snapshot.json"

cat >"$task" <<'EOF'
---
depends_on: [T1]
---

# T2: snapshot selftest (1 pt)

> Source: DP-999 | Task: DP-999-T2 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Base branch | task/DP-999-T1-upstream |

## Allowed Files

- `scripts/example.sh`

## Verify Command

```bash
echo ok
```
EOF

python3 - "$snapshot" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()

planner_owned = {
    "verify_command": "echo ok",
    "depends_on": ["T1"],
    "base_branch": "task/DP-999-T1-upstream",
    "allowed_files": ["`scripts/example.sh`"],
}
payload = {
    "schema_version": 1,
    "writer": "validate-task-md-selftest",
    "task_id": "DP-999-T2",
    "planner_owned": planner_owned,
    "hashes": {
        "verify_command_sha256": digest(planner_owned["verify_command"]),
        "depends_on_sha256": digest(planner_owned["depends_on"]),
        "base_branch_sha256": digest(planner_owned["base_branch"]),
        "allowed_files_sha256": digest(planner_owned["allowed_files"]),
    },
}
Path(sys.argv[1]).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

bash "$VALIDATE" --snapshot "$snapshot" "$task" >/dev/null

perl -0pi -e 's/echo ok/echo changed/' "$task"
if bash "$VALIDATE" --snapshot "$snapshot" "$task" >/tmp/validate-task-md-selftest.out 2>&1; then
  echo "validate-task-md-selftest: expected snapshot mismatch to fail" >&2
  exit 1
fi
grep -q "Verify Command changed" /tmp/validate-task-md-selftest.out

echo "PASS: validate-task-md snapshot selftest"

# ===========================================================================
# DP-369 GapA: Env bootstrap command executability gate.
# verify_command_static_smoke (kind=env_bootstrap) must:
#   AC1     — fail a prose / non-executable Env bootstrap command (runtime).
#   AC2     — pass a legitimate pipe-free shell chain whose binaries
#             (colima / docker-compose / pnpm) are absent from the gate host
#             (shape check, never binary existence) at runtime AND build levels.
#   AC-NEG1 — leave static + N/A and build + N/A tasks untouched (no-op).
#   AC-NEG3 — reuse the verify_command_static_smoke primitive; no second
#             env-bootstrap executability parser exists in the script.
# ===========================================================================

# write_env_task <file> <level> <runtime_target> <env_bootstrap> <verify_cmd>
# Emits a complete, otherwise-valid T-mode task.md so the ONLY variable under
# test is the Env bootstrap command value. Runtime verify target host must
# match the Verify Command URL host (§ 5.1 rule 4).
write_env_task() {
  local file="$1" level="$2" target="$3" bootstrap="$4" verify_cmd="$5"
  cat >"$file" <<EOF
---
title: "Work Order - T1: env bootstrap fixture (1 pt)"
description: "env bootstrap executability validator fixture."
status: IN_PROGRESS
verification:
  behavior_contract:
    applies: false
    reason: "framework static work order; selftest fixture"
---

# T1: env bootstrap fixture (1 pt)

> Source: DP-369 | Task: DP-369-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-369 |
| Task ID | DP-369-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-369-T1-fixture |
| Task branch | task/DP-369-T1-fixture |
| Depends on | N/A |
| References to load | - \`scripts/validate-task-md.sh\` |

## 目標

env bootstrap executability fixture。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| scripts/validate-task-md.sh | modify | fixture only |

## Allowed Files

- \`scripts/validate-task-md.sh\`

## 估點理由

1 pt - validator fixture。

## 測試計畫（code-level）

- validator fixture。

## Test Command

\`\`\`bash
echo PASS
\`\`\`

## Test Environment

- **Level**: ${level}
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: ${target}
- **Env bootstrap command**: ${bootstrap}

## Verify Command

\`\`\`bash
${verify_cmd}
\`\`\`
EOF
}

env_marker="Env bootstrap command executability"

# AC1 — prose env_bootstrap (real DEMO-646-style Chinese prose) at runtime → FAIL.
ac1="$TMPROOT/env-AC1-prose.md"
write_env_task "$ac1" runtime \
  "https://app.example.test/en/product/123" \
  "啟動 app.example.test 三層 stack（colima + nginx + dev server）" \
  "curl -sf https://app.example.test/en/product/123"
if bash "$VALIDATE" "$ac1" >"$TMPROOT/env-AC1.out" 2>&1; then
  echo "validate-task-md-selftest AC1: expected prose Env bootstrap command to FAIL" >&2
  cat "$TMPROOT/env-AC1.out" >&2
  exit 1
fi
grep -q "$env_marker" "$TMPROOT/env-AC1.out" || {
  echo "validate-task-md-selftest AC1: missing env executability error marker" >&2
  cat "$TMPROOT/env-AC1.out" >&2
  exit 1
}
echo "PASS: validate-task-md env-bootstrap AC1 (prose fails)"

# AC2 — legitimate pipe-free chain referencing absent host binaries → PASS (runtime).
ac2="$TMPROOT/env-AC2-missing-binary.md"
write_env_task "$ac2" runtime \
  "https://app.example.test/en/product/123" \
  "colima start; docker-compose up -d; pnpm dev" \
  "curl -sf https://app.example.test/en/product/123"
if ! bash "$VALIDATE" "$ac2" >"$TMPROOT/env-AC2.out" 2>&1; then
  echo "validate-task-md-selftest AC2: legit missing-binary chain must PASS (shape, not existence)" >&2
  cat "$TMPROOT/env-AC2.out" >&2
  exit 1
fi
echo "PASS: validate-task-md env-bootstrap AC2 (missing-binary chain passes, runtime)"

# AC2b — build level with a missing-binary install/build chain → PASS.
ac2b="$TMPROOT/env-AC2b-build.md"
write_env_task "$ac2b" build \
  "N/A" \
  "pnpm install; pnpm -C packages/foo build" \
  "echo build-ok"
if ! bash "$VALIDATE" "$ac2b" >"$TMPROOT/env-AC2b.out" 2>&1; then
  echo "validate-task-md-selftest AC2b: build-level missing-binary chain must PASS" >&2
  cat "$TMPROOT/env-AC2b.out" >&2
  exit 1
fi
echo "PASS: validate-task-md env-bootstrap AC2b (missing-binary chain passes, build)"

# AC-NEG1a — static + N/A → PASS (no-op, no env executability error).
neg1a="$TMPROOT/env-NEG1a-static.md"
write_env_task "$neg1a" static "N/A" "N/A" "echo static-ok"
if ! bash "$VALIDATE" "$neg1a" >"$TMPROOT/env-NEG1a.out" 2>&1; then
  echo "validate-task-md-selftest AC-NEG1a: static + N/A must remain valid" >&2
  cat "$TMPROOT/env-NEG1a.out" >&2
  exit 1
fi
if grep -q "$env_marker" "$TMPROOT/env-NEG1a.out"; then
  echo "validate-task-md-selftest AC-NEG1a: static N/A must not trigger env executability smoke" >&2
  exit 1
fi
echo "PASS: validate-task-md env-bootstrap AC-NEG1a (static N/A no-op)"

# AC-NEG1b — build + N/A → PASS (no-op).
neg1b="$TMPROOT/env-NEG1b-build.md"
write_env_task "$neg1b" build "N/A" "N/A" "echo build-ok"
if ! bash "$VALIDATE" "$neg1b" >"$TMPROOT/env-NEG1b.out" 2>&1; then
  echo "validate-task-md-selftest AC-NEG1b: build + N/A must remain valid" >&2
  cat "$TMPROOT/env-NEG1b.out" >&2
  exit 1
fi
if grep -q "$env_marker" "$TMPROOT/env-NEG1b.out"; then
  echo "validate-task-md-selftest AC-NEG1b: build N/A must not trigger env executability smoke" >&2
  exit 1
fi
echo "PASS: validate-task-md env-bootstrap AC-NEG1b (build N/A no-op)"

# AC-NEG3 — reuse primitive: the Python production module must route
# env_bootstrap through the same smoke helper and must not define a second
# standalone executable classifier.
VALIDATE_MODULE="$SCRIPT_DIR/lib/validate_task_md.py"
if ! grep -Eq 'helper\("smoke".*normalized_bootstrap.*"env_bootstrap"' "$VALIDATE_MODULE"; then
  echo "validate-task-md-selftest AC-NEG3: env_bootstrap check must reuse verify_command_static_smoke primitive" >&2
  exit 1
fi
echo "PASS: validate-task-md env-bootstrap AC-NEG3 (reuses primitive)"
