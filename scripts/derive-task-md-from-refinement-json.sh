#!/usr/bin/env bash
# DP-230-T10: deterministic task.md body derivation from refinement.json
#
# Replaces the previous breakdown LLM-judgment task derivation. Given a
# refinement.json `tasks[]` entry, emit a canonical task.md body that passes
# `validate-task-md.sh` and `validate-breakdown-ready.sh` — without any LLM
# reasoning step in the pipeline.
#
# Inputs come exclusively from structured fields on the refinement.json task:
#   id, title, scope, allowed_files, ac_ids, estimate_points,
#   verification.detail
#
# fail-loud cases (no fallback):
#   - refinement.json file missing or invalid JSON
#   - task-id not found in `tasks[]`
#   - required field missing on the resolved task entry
#
# Usage:
#   bash scripts/derive-task-md-from-refinement-json.sh \
#     --refinement-json <path> \
#     --task-id <DP-NNN-Tn> \
#     [--repo polaris-framework]
#
# Output: task.md body on stdout.

set -euo pipefail

REFINEMENT_JSON=""
TASK_ID=""
REPO_NAME="polaris-framework"

usage() {
  cat >&2 <<'USAGE'
usage:
  derive-task-md-from-refinement-json.sh --refinement-json <path> --task-id <DP-NNN-Tn> [--repo <name>]

Emits a canonical task.md body on stdout, derived deterministically from the
structured `tasks[]` entry in the supplied refinement.json. No LLM judgment.
USAGE
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --refinement-json) REFINEMENT_JSON="${2:-}"; shift 2 ;;
    --task-id) TASK_ID="${2:-}"; shift 2 ;;
    --repo) REPO_NAME="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$REFINEMENT_JSON" && -n "$TASK_ID" ]] || usage

if [[ ! -f "$REFINEMENT_JSON" ]]; then
  echo "ERROR: refinement.json not found: $REFINEMENT_JSON" >&2
  exit 2
fi

python3 - "$REFINEMENT_JSON" "$TASK_ID" "$REPO_NAME" <<'PY'
import json
import re
import sys
import unicodedata
from pathlib import Path

refinement_path, task_id, repo_name = sys.argv[1:4]


def fail(msg, code=2):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


try:
    data = json.loads(Path(refinement_path).read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    fail(f"refinement.json is not valid JSON: {exc}")

source = data.get("source") or {}
source_id = source.get("id")
source_type = source.get("type") or "dp"
if not source_id:
    fail("refinement.json missing source.id")

tasks = data.get("tasks") or []
match = None
for entry in tasks:
    if entry.get("id") == task_id:
        match = entry
        break
if match is None:
    fail(f"task-id not found in refinement.json tasks[]: {task_id}")

required_fields = ("id", "title", "scope", "allowed_files", "verification", "estimate_points")
for field in required_fields:
    if field not in match or match[field] in (None, "", []):
        fail(f"task {task_id} missing required field: {field}")

verification = match["verification"] or {}
verify_detail = verification.get("detail") or ""
if not verify_detail.strip():
    fail(f"task {task_id} missing verification.detail")

title = str(match["title"]).strip()
scope = str(match["scope"]).strip()
points = int(match["estimate_points"])
allowed_files = list(match["allowed_files"])
ac_ids = list(match.get("ac_ids") or [])
dependencies = list(match.get("dependencies") or [])

# Tn suffix: parse "T{n}" off the tail of the canonical id (e.g. DP-230-T10 -> T10).
m = re.match(r"^(?P<src>[A-Z]+-\d+)-(?P<short>[TV]\d+)$", task_id)
if not m:
    fail(f"task id does not match canonical pattern (e.g. DP-230-T10): {task_id}")
short_id = m.group("short")

# Branch slug: deterministic, lowercase, hyphen-separated. Drop punctuation, keep
# CJK characters (refinement.json titles routinely include zh-TW). Match the
# existing convention used by sibling DP-230 task.md files.
def slugify(text: str) -> str:
    normalized = unicodedata.normalize("NFC", text).strip().lower()
    out_chars = []
    for ch in normalized:
        if ch.isalnum():
            out_chars.append(ch)
        elif ch in (" ", "-", "_", "/"):
            out_chars.append("-")
        # else: drop punctuation
    slug = "".join(out_chars)
    slug = re.sub(r"-+", "-", slug).strip("-")
    return slug or "task"


slug = slugify(title)
task_branch = f"task/{task_id}-{slug}"

# --- Build artifacts ---
allowed_files_block = "\n".join(f"- `{p}`" for p in allowed_files)

action_for = lambda path: "create" if "selftest" in path or path.endswith(".md") and "references/" in path else "modify"
# Keep change summary text deterministic: short scope prefix.
change_summary = (scope[:80] + "...") if len(scope) > 80 else scope
change_rows = []
for path in allowed_files:
    action = "create" if (
        "selftests/" in path or "/references/" in path and path.endswith(".md")
    ) else "modify"
    change_rows.append(f"| `{path}` | {action} | {change_summary} |")
change_block = "\n".join(change_rows)

# Scope Trace Matrix — one row per AC id, owning files = allowed_files joined
# Use the first allowed file as canonical owning file for simplicity; surface
# stays "framework deterministic gate / selftest contract" for DP-backed work.
owning_anchor = f"`{allowed_files[0]}`"
trace_rows = []
ac_list = ac_ids if ac_ids else ["AC-N/A"]
for ac in ac_list:
    trace_rows.append(f"| {ac} | {owning_anchor} | framework deterministic gate / selftest contract | `{verify_detail}` |")
trace_block = "\n".join(trace_rows)

depends_cell = ", ".join(dependencies) if dependencies else "N/A"

doc = f"""---
title: "{source_id} {short_id}: {title} ({points} pt)"
description: "{scope}"
draft: true
sidebar:
  hidden: true
status: IN_PROGRESS
verification:
  behavior_contract:
    applies: false
    reason: "framework deterministic gate / selftest / helper；無 runtime / UI 行為變更"
depends_on: []
---

# {short_id}: {title} ({points} pt)

> Source: {source_id} | Task: {task_id} | JIRA: N/A | Repo: {repo_name}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | {source_type} |
| Source ID | {source_id} |
| Task ID | {task_id} |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> {task_branch} |
| Task branch | {task_branch} |
| Depends on | {depends_cell} |
| References to load | - `docs-manager/src/content/docs/specs/design-plans/{source_id}-*/refinement.md`<br>- `docs-manager/src/content/docs/specs/design-plans/{source_id}-*/refinement.json` |

## Verification Handoff

framework work order；驗收委派給 {source_id}-V1（umbrella regression）。

## 目標

{scope}

## 改動範圍

| 檔案 | 動作 | 變更摘要 |
|------|------|----------|
{change_block}

## Allowed Files

{allowed_files_block}

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
{trace_block}

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | changed files all match Allowed Files | engineering |
| test | yes | `{verify_detail}` PASS | engineering |
| verify | yes | `{verify_detail}` PASS + manifest 通過 | engineering |
| ci-local | no | N/A | framework repo 無 ci-local |

## 估點理由

{points} pt — {scope}

## 測試計畫（code-level）

1. 先擴張對應 selftest，新增 failing cases 涵蓋 {', '.join(ac_list)}。
2. 實作 Allowed Files 內的 producer / hook / validator 變更。
3. 跑 `{verify_detail}` 直到 PASS。
4. 確認 manifest 登記、CHANGELOG 與 VERSION（若有）同步。

## Test Command

```bash
{verify_detail}
```

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: tmpdir + repo-tracked selftest fixtures
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
set -euo pipefail
{verify_detail}
bash scripts/check-script-manifest.sh --root . --quiet
echo "PASS: {task_id}"
```

預期輸出：`PASS: {task_id}`
"""

sys.stdout.write(doc)
PY
