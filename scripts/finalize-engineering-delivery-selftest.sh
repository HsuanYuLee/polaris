#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FINALIZE="$SCRIPT_DIR/finalize-engineering-delivery.sh"
REFRESH_SNAPSHOT="$SCRIPT_DIR/refresh-baseline-snapshot.sh"
MARK_SPEC="$SCRIPT_DIR/mark-spec-implemented.sh"
TMPROOT="$(mktemp -d -t finalize-baseline-selftest-XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

write_task() {
  local workspace="$1"
  mkdir -p "$workspace/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-baseline/tasks/T1"
  cat > "$workspace/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-baseline/tasks/T1/index.md" <<'EOF'
---
status: IN_PROGRESS
depends_on: []
---

# T1: finalize baseline fixture (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: example

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Task branch | task/DP-999-T1-finalize-baseline |

## Allowed Files

- `scripts/**`

## Test Command

```bash
echo ok
```

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
echo ok
```
EOF
}

write_mismatch_snapshot() {
  local repo="$1"
  local head
  head="$(git -C "$repo" rev-parse HEAD)"
  mkdir -p "$repo/.polaris/evidence/baseline-snapshot"
  python3 - "$repo/.polaris/evidence/baseline-snapshot/DP-999-T1-${head}.json" "$head" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()

planner_owned = {
    "verify_command": "echo changed",
    "depends_on": [],
    "base_branch": "main",
    "allowed_files": ["`scripts/**`"],
}
payload = {
    "schema_version": 1,
    "writer": "finalize-engineering-delivery-selftest",
    "task_id": "DP-999-T1",
    "head_sha": sys.argv[2],
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
}

repo="$TMPROOT/workspace"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" checkout -q -b task/DP-999-T1-finalize-baseline
git -C "$repo" config user.email "polaris@example.test"
git -C "$repo" config user.name "Polaris Selftest"
echo init > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -q -m init
write_task "$repo"

set +e
out="$("$FINALIZE" --repo "$repo" --ticket DP-999-T1 --workspace "$repo" 2>&1)"
rc=$?
set -e
[[ "$rc" == "2" ]]
grep -q "missing planner-owned baseline snapshot" <<<"$out"

write_mismatch_snapshot "$repo"
set +e
out="$("$FINALIZE" --repo "$repo" --ticket DP-999-T1 --workspace "$repo" 2>&1)"
rc=$?
set -e
[[ "$rc" == "2" ]]
grep -q "planner-owned task.md fields changed" <<<"$out"

# Post-archive revision closeout must resolve the authoritative task from the
# archive namespace and pass the planner-owned baseline gate. It may fail later
# because this minimal fixture has no remote deliverable, but archive resolution
# itself must not be the blocker.
active_container="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-baseline"
archive_root="$repo/docs-manager/src/content/docs/specs/design-plans/archive"
mkdir -p "$archive_root"
mv "$active_container" "$archive_root/"
archived_task="$archive_root/DP-999-finalize-baseline/tasks/T1/index.md"
bash "$REFRESH_SNAPSHOT" \
  --repo "$repo" \
  --task-md "$archived_task" \
  --head-sha "$(git -C "$repo" rev-parse HEAD)" >/dev/null

set +e
out="$($FINALIZE --repo "$repo" --ticket DP-999-T1 --workspace "$repo" 2>&1)"
rc=$?
set -e
[[ "$rc" == "2" ]]
grep -q "planner-owned baseline snapshot passed" <<<"$out"
if grep -q "unable to resolve task.md" <<<"$out"; then
  echo "archived task resolution failed before completion gate" >&2
  exit 1
fi

# An explicit archived task path is accepted only when its parsed work-item
# identity matches the requested ticket.
set +e
out="$(POLARIS_COMPLETION_TASK_MD="$archived_task" \
  "$FINALIZE" --repo "$repo" --ticket DP-998-T1 --workspace "$repo" 2>&1)"
rc=$?
set -e
[[ "$rc" == "2" ]]
grep -q "unable to resolve task.md for planner-owned baseline snapshot check" <<<"$out"

# The exact archived task anchor remains authoritative even if a same-key active
# source is recreated. The lifecycle writer must update archived A and leave
# active B untouched.
active_collision="$repo/docs-manager/src/content/docs/specs/design-plans/DP-997-active-collision"
archived_collision="$archive_root/DP-997-archived-collision"
mkdir -p "$active_collision/tasks/T1" "$archived_collision/tasks/pr-release/T1"
for task_file in "$active_collision/tasks/T1/index.md" "$archived_collision/tasks/pr-release/T1/index.md"; do
  cat >"$task_file" <<'EOF'
---
status: IN_PROGRESS
---

# T1

> Source: DP-997 | Task: DP-997-T1 | JIRA: N/A | Repo: example
EOF
done
bash "$MARK_SPEC" DP-997-T1 \
  --task-anchor "$archived_collision/tasks/pr-release/T1/index.md" \
  --status IMPLEMENTED --workspace "$repo" --no-auto-archive >/dev/null
grep -q '^status: IMPLEMENTED$' "$archived_collision/tasks/pr-release/T1/index.md"
grep -q '^status: IN_PROGRESS$' "$active_collision/tasks/T1/index.md"

# Invalid DP slugs and company/source mismatches are not canonical containers,
# even when their task prose claims the requested work-item identity.
invalid_dp="$repo/docs-manager/src/content/docs/specs/design-plans/not-a-dp/tasks/T1"
mkdir -p "$invalid_dp"
cat >"$invalid_dp/index.md" <<'EOF'
---
status: IN_PROGRESS
---

# T1

> Source: DP-995 | Task: DP-995-T1 | JIRA: N/A | Repo: example
EOF
if bash "$MARK_SPEC" DP-995-T1 --task-anchor "$invalid_dp/index.md" \
  --status IMPLEMENTED --workspace "$repo" --no-auto-archive >/dev/null 2>&1; then
  echo "invalid DP task-anchor container was accepted" >&2
  exit 1
fi
grep -q '^status: IN_PROGRESS$' "$invalid_dp/index.md"

invalid_company="$repo/docs-manager/src/content/docs/specs/companies/acme/OTHER-996/tasks/T1"
mkdir -p "$invalid_company"
cat >"$invalid_company/index.md" <<'EOF'
---
status: IN_PROGRESS
---

# T1

> Source: EPIC-996 | Task: EPIC-996-T1 | JIRA: N/A | Repo: example
EOF
if bash "$MARK_SPEC" EPIC-996-T1 --task-anchor "$invalid_company/index.md" \
  --status IMPLEMENTED --workspace "$repo" --no-auto-archive >/dev/null 2>&1; then
  echo "mismatched company task-anchor container was accepted" >&2
  exit 1
fi
grep -q '^status: IN_PROGRESS$' "$invalid_company/index.md"

valid_company="$repo/docs-manager/src/content/docs/specs/companies/acme/archive/EXCO-700/tasks/pr-release/T1"
mkdir -p "$valid_company"
cat >"$valid_company/index.md" <<'EOF'
---
status: IN_PROGRESS
---

# T1

> Source: EXCO-700 | Task: EXCO-700-T1 | JIRA: EXCO-712 | Repo: example

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EXCO-700 |
| Work item ID | EXCO-700-T1 |
| Task ID | T1 |
| JIRA key | EXCO-712 |
EOF
bash "$MARK_SPEC" EXCO-712 --task-anchor "$valid_company/index.md" \
  --status IMPLEMENTED --workspace "$repo" --no-auto-archive >/dev/null
grep -q '^status: IMPLEMENTED$' "$valid_company/index.md"

stem_mismatch="$repo/docs-manager/src/content/docs/specs/companies/acme/archive/EXCO-701/tasks/T1"
mkdir -p "$stem_mismatch"
cat >"$stem_mismatch/index.md" <<'EOF'
---
status: IN_PROGRESS
---

# T1

> Source: EXCO-701 | Task: EXCO-701-T2 | JIRA: EXCO-713 | Repo: example

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EXCO-701 |
| Work item ID | EXCO-701-T2 |
| Task ID | T1 |
| JIRA key | EXCO-713 |
EOF
if bash "$MARK_SPEC" EXCO-713 --task-anchor "$stem_mismatch/index.md" \
  --status IMPLEMENTED --workspace "$repo" --no-auto-archive >/dev/null 2>&1; then
  echo "task-anchor path stem/work_item_id mismatch was accepted" >&2
  exit 1
fi
grep -q '^status: IN_PROGRESS$' "$stem_mismatch/index.md"

legacy_company="$repo/docs-manager/src/content/docs/specs/companies/acme/archive/EXCO-702/tasks/pr-release/T1"
mkdir -p "$legacy_company"
cat >"$legacy_company/index.md" <<'EOF'
---
status: IN_PROGRESS
---

# T1

> Source: EXCO-702 | Task: EXCO-714 | JIRA: EXCO-714 | Repo: example

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EXCO-702 |
| Task ID | EXCO-714 |
| JIRA key | EXCO-714 |
EOF
bash "$MARK_SPEC" EXCO-714 --task-anchor "$legacy_company/index.md" \
  --status IMPLEMENTED --workspace "$repo" --no-auto-archive >/dev/null
grep -q '^status: IMPLEMENTED$' "$legacy_company/index.md"

bug_mismatch="$repo/docs-manager/src/content/docs/specs/companies/acme/archive/BUG-101/tasks/T1"
mkdir -p "$bug_mismatch"
cat >"$bug_mismatch/index.md" <<'EOF'
---
status: IN_PROGRESS
---

# T1

> Source: BUG-101 | Task: BUG-101-T2 | JIRA: BUG-101-T2 | Repo: example

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | bug |
| Source ID | BUG-101 |
| Task ID | BUG-101-T2 |
| JIRA key | BUG-101-T2 |
EOF
if bash "$MARK_SPEC" BUG-101-T2 --task-anchor "$bug_mismatch/index.md" \
  --status IMPLEMENTED --workspace "$repo" --no-auto-archive >/dev/null 2>&1; then
  echo "non-JIRA legacy task stem mismatch was accepted" >&2
  exit 1
fi
grep -q '^status: IN_PROGRESS$' "$bug_mismatch/index.md"

blank_work_item="$repo/docs-manager/src/content/docs/specs/companies/acme/archive/EXCO-703/tasks/T1"
mkdir -p "$blank_work_item"
cat >"$blank_work_item/index.md" <<'EOF'
---
status: IN_PROGRESS
---

# T1

> Source: EXCO-703 | Task: EXCO-715 | JIRA: EXCO-715 | Repo: example

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EXCO-703 |
| Work item ID | |
| Task ID | EXCO-715 |
| JIRA key | EXCO-715 |
EOF
if bash "$MARK_SPEC" EXCO-715 --task-anchor "$blank_work_item/index.md" \
  --status IMPLEMENTED --workspace "$repo" --no-auto-archive >/dev/null 2>&1; then
  echo "blank current Work item ID row was treated as legacy" >&2
  exit 1
fi
grep -q '^status: IN_PROGRESS$' "$blank_work_item/index.md"

repeated_context="$repo/docs-manager/src/content/docs/specs/companies/acme/archive/EXCO-704/tasks/T1"
mkdir -p "$repeated_context"
cat >"$repeated_context/index.md" <<'EOF'
---
status: IN_PROGRESS
---

# T1

> Source: EXCO-704 | Task: EXCO-716 | JIRA: EXCO-716 | Repo: example

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EXCO-704 |
| Task ID | EXCO-716 |
| JIRA key | EXCO-716 |

## Notes

Legacy-looking first section must not override the parser-selected last section.

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EXCO-704 |
| Work item ID | EXCO-716 |
| Task ID | EXCO-716 |
| JIRA key | EXCO-716 |
EOF
if bash "$MARK_SPEC" EXCO-716 --task-anchor "$repeated_context/index.md" \
  --status IMPLEMENTED --workspace "$repo" --no-auto-archive >/dev/null 2>&1; then
  echo "repeated Operational Context bypassed current work-item stem binding" >&2
  exit 1
fi
grep -q '^status: IN_PROGRESS$' "$repeated_context/index.md"

echo "PASS: finalize-engineering-delivery baseline snapshot selftest"
