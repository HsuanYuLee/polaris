#!/usr/bin/env bash
# Purpose: deterministic task.md body derivation from refinement.json (DP-230-T10).
#
# Replaces the previous breakdown LLM-judgment task derivation. Given a
# refinement.json `tasks[]` entry, emit a canonical task.md body that passes
# `validate-task-md.sh` and `validate-breakdown-ready.sh` — without any LLM
# reasoning step in the pipeline.
#
# Inputs come exclusively from structured fields on the refinement.json task:
#   id, title, scope, allowed_files, ac_ids, dependencies, estimate_points,
#   verification.detail
#
# DP-269: derive dispatches on source.type.
#   - dp   mode (default): legacy behavior unchanged — JIRA key N/A,
#            Repo polaris-framework (or --repo), Base branch main,
#            task identity = canonical DP-NNN-Tn.
#   - jira mode: task identity = real per-task `tasks[].jira_key`, Repo =
#            `source.repo`, Base branch = `source.base_branch`, JIRA key cell =
#            the real key. Fail-closes when `tasks[].jira_key` is null (no N/A
#            fallback) and when source.repo / source.base_branch are missing.
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

# DP-269: derive dispatches on source.type. dp mode keeps the legacy defaults
# (JIRA key N/A / Repo polaris-framework / Base branch main / identity DP-NNN-Tn).
# jira mode injects the real per-task jira_key as the task identity and reads
# source.repo / source.base_branch for the product repo + base branch. The CLI
# --repo flag stays authoritative only for dp mode (polaris-framework default);
# jira mode always takes Repo from source.repo and ignores --repo.
if source_type == "jira":
    jira_repo = source.get("repo")
    jira_base_branch = source.get("base_branch")
    if not jira_repo:
        fail("source_type=jira requires source.repo (product repo slug)")
    if not jira_base_branch:
        fail("source_type=jira requires source.base_branch (product base branch)")
    repo_name = jira_repo
# dp mode keeps repo_name as the CLI --repo default (polaris-framework).

tasks = data.get("tasks") or []
# DP-260 T1: tasks[].id accepts both short form (T1/V1, optionally with a-suffix)
# and full form (DP-NNN-Tn / EPIC-NNN-Vn) — derive must accept either when the
# CLI canonical id is full form. Match full id first; fall back to short id
# when the canonical id's source prefix equals source.id. Reject foreign
# prefix at the validator layer, not here.
m_cli = re.match(r"^(?P<src>[A-Z][A-Z0-9]*-\d+)-(?P<short>[TV]\d+[a-z]?)$", task_id)
if not m_cli:
    fail(f"task id does not match canonical pattern (e.g. DP-230-T10): {task_id}")
cli_short_id = m_cli.group("short")
cli_source_id = m_cli.group("src")

match = None
# Pass 1: full-form match (entry.id == task_id).
for entry in tasks:
    if entry.get("id") == task_id:
        match = entry
        break
# Pass 2: short-form fallback (entry.id == short tail) only when the CLI source
# prefix equals refinement.json source.id.
if match is None and cli_source_id == source_id:
    for entry in tasks:
        if entry.get("id") == cli_short_id:
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
# verify_command is the executable shell command form (preferred when set);
# verification.detail remains zh-TW prose used for Scope Trace / Test Plan / Gate
# rendering. The ## Verify Command fence prefers verify_command and falls back
# to detail only when verify_command is null (legacy refinement.json shape).
verify_command = (verification.get("verify_command") or "").strip()
verify_command_or_detail = verify_command or verify_detail

title = str(match["title"]).strip()
scope = str(match["scope"]).strip()
points = int(match["estimate_points"])
allowed_files = list(match["allowed_files"])
ac_ids = list(match.get("ac_ids") or [])
raw_dependencies = [str(dep).strip() for dep in list(match.get("dependencies") or []) if str(dep).strip()]

# Tn suffix: reuse the canonical CLI parse above (m_cli) for short id / mode.
short_id = cli_short_id
mode = short_id[0]

# DP-269: task identity + JIRA key cell dispatch on source.type.
#   dp   : identity = canonical task_id (DP-NNN-Tn); JIRA key cell = N/A.
#   jira : identity = real per-task jira_key; JIRA key cell = the same real key.
# jira mode fail-closes on a null jira_key — derive must NOT fall back to N/A
# (that would fail validate-task-md.sh, which requires a real key for jira
# sources). The task must already be populated with a real jira_key before
# derive (D3a). The plain JIRA key (^[A-Z][A-Z0-9]*-[0-9]+$) satisfies
# is_valid_task_identity, so the derived task.md identity validates.
if source_type == "jira":
    task_jira_key = match.get("jira_key")
    if not (isinstance(task_jira_key, str) and task_jira_key.strip()):
        fail(
            f"task {task_id} has source_type=jira but missing tasks[].jira_key; "
            "populate the real JIRA key before derive (no N/A fallback)"
        )
    task_jira_key = task_jira_key.strip()
    if not re.fullmatch(r"[A-Z][A-Z0-9]*-[0-9]+", task_jira_key):
        fail(
            f"task {task_id} jira_key is not a valid JIRA key (got: '{task_jira_key}')"
        )
    task_identity = task_jira_key
    jira_key_cell = task_jira_key
else:
    task_identity = task_id
    jira_key_cell = "N/A"

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

def short_work_item_id(value: str) -> str:
    m_short = re.fullmatch(r"[TV]\d+[a-z]?", value)
    if m_short:
        return value
    m_full = re.fullmatch(r"(?P<src>[A-Z][A-Z0-9]*-\d+)-(?P<short>[TV]\d+[a-z]?)", value)
    if m_full and m_full.group("src") == source_id:
        return m_full.group("short")
    return ""


def full_work_item_id(value: str) -> str:
    short = short_work_item_id(value)
    return f"{source_id}-{short}" if short else value


# Index tasks by normalized full id so dependency title lookup hits regardless of
# whether tasks[].id is short form (T1) or full form (DP-NNN-Tn). Keying by the raw
# entry.id would miss short-form entries when looked up by full id below, and the
# missing-entry path silently falls back to the full-id literal as the slug source.
task_by_id = {
    full_work_item_id(str(entry.get("id"))): entry
    for entry in tasks
    if isinstance(entry, dict)
}

local_dependencies = []
external_dependencies = []
for dep in raw_dependencies:
    short_dep = short_work_item_id(dep)
    if short_dep:
        local_dependencies.append(short_dep)
    else:
        # Cross-source full-form work items are allowed as source references, but
        # this DP-backed task writer cannot derive a local task branch from them.
        # Bare source ids such as DP-229 are invalid under the refinement schema
        # and should be caught before derive; keep this defensive split loud in
        # task DAG output by excluding them from task.md Depends on.
        external_dependencies.append(dep)

if mode == "T" and len(local_dependencies) > 1:
    fail(f"task {task_id} has non-linear local dependencies: {', '.join(local_dependencies)}")

full_form_dependencies = [f"{source_id}-{dep}" for dep in local_dependencies]
depends_on_frontmatter = ", ".join(full_form_dependencies)
depends_cell = ", ".join(full_form_dependencies) if full_form_dependencies else "N/A"
if local_dependencies:
    dep_full_id = f"{source_id}-{local_dependencies[-1]}"
    dep_title = str((task_by_id.get(dep_full_id) or {}).get("title") or dep_full_id)
    base_branch = f"task/{dep_full_id}-{slugify(dep_title)}"
    branch_chain = f"{base_branch} -> {task_branch}"
else:
    # DP-269: root base branch dispatches on source.type. dp mode roots at main;
    # jira mode roots at the product repo's source.base_branch (e.g. develop).
    root_base_branch = jira_base_branch if source_type == "jira" else "main"
    base_branch = root_base_branch
    branch_chain = f"{root_base_branch} -> {task_branch}"

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

if mode == "V":
    # DP-269: V-task base branch dispatches on source.type. dp V-tasks keep the
    # legacy hardcoded `main` (umbrella verification branches off main); jira
    # V-tasks root at the product repo's source.base_branch for parity.
    v_base_branch = jira_base_branch if source_type == "jira" else "main"
    ac_by_id = {
        str(item.get("id")): item
        for item in (data.get("acceptance_criteria") or [])
        if isinstance(item, dict) and item.get("id")
    }
    implementation_tasks = []
    for dep in raw_dependencies:
        short_dep = short_work_item_id(dep)
        if short_dep and short_dep.startswith("T"):
            implementation_tasks.append(short_dep)
    if not implementation_tasks:
        implementation_tasks = [
            short_work_item_id(str(entry.get("id")))
            for entry in tasks
            if isinstance(entry, dict)
            and short_work_item_id(str(entry.get("id"))).startswith("T")
        ]
    implementation_tasks = [item for item in implementation_tasks if item]
    implementation_cell = ", ".join(implementation_tasks) if implementation_tasks else "N/A"
    ac_rows = []
    for ac in ac_list:
        ac_item = ac_by_id.get(ac) or {}
        ac_text = str(ac_item.get("text") or ac)
        ac_summary = (ac_text[:80] + "...") if len(ac_text) > 80 else ac_text
        method = str((ac_item.get("verification") or {}).get("method") or verification.get("method") or "unit_test")
        ac_rows.append(f"| {ac} | {ac_summary} | {implementation_cell} | {method} |")
    if not ac_rows:
        ac_rows.append(f"| AC-N/A | {scope} | {implementation_cell} | {verification.get('method') or 'unit_test'} |")
    ac_block = "\n".join(ac_rows)

    doc = f"""---
title: "{source_id} {short_id}: {title} ({points} pt)"
description: "{scope}"
draft: true
sidebar:
  hidden: true
status: IN_PROGRESS
task_kind: {mode}
verification:
  behavior_contract:
    applies: false
    reason: "framework static AC verification；無 runtime / UI 行為變更"
depends_on: []
---

# {short_id}: {title} ({points} pt)

> Source: {source_id} | Task: {task_identity} | JIRA: {jira_key_cell} | Repo: {repo_name}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | {source_type} |
| Source ID | {source_id} |
| Task ID | {task_identity} |
| JIRA key | {jira_key_cell} |
| Implementation tasks | {implementation_cell} |
| Base branch | {v_base_branch} |
| Depends on | {depends_cell} |
| References to load | - `docs-manager/src/content/docs/specs/design-plans/{source_id}-*/refinement.md`<br>- `docs-manager/src/content/docs/specs/design-plans/{source_id}-*/refinement.json`<br>- `.claude/skills/verify-AC/SKILL.md` |

## 目標

{scope}

## 驗收項目

| AC | 摘要 | 對應實作 task | 驗證類型 |
|----|------|--------------|---------|
{ac_block}

## 估點理由

{points} pt — {scope}

## 驗收計畫（AC level）

1. 逐項讀取 `refinement.json` AC 與本 V task 的驗收項目。
2. 確認 implementation tasks 已完成且 evidence current。
3. 執行 `{verify_detail}`，逐 AC 記錄 PASS / FAIL / MANUAL_REQUIRED / UNCERTAIN。
4. 驗收結果寫回 V task lifecycle metadata。

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A
"""

    sys.stdout.write(doc)
    sys.exit(0)

# DP-272 T1: task_shape propagation (T-task only — the V-task branch returned
# above, AC2). The canonical source is planned_tasks[] (NOT tasks[]): join by
# the normalized short task id and read task_shape. Passthrough only — derive
# does not validate the enum (single classifier = validate-task-md.sh, DP-262
# AC7). No matching planned_tasks entry or empty task_shape → omit the line and
# the reader defaults to implementation (AC8 zero-shim).
planned_shape_by_short = {}
for planned_entry in (data.get("planned_tasks") or []):
    if not isinstance(planned_entry, dict):
        continue
    planned_short = short_work_item_id(str(planned_entry.get("task_id") or ""))
    if not planned_short:
        continue
    raw_shape = planned_entry.get("task_shape")
    shape = str(raw_shape).strip() if raw_shape not in (None, "") else ""
    if shape:
        planned_shape_by_short[planned_short] = shape

task_shape_value = planned_shape_by_short.get(short_id, "")
task_shape_line = f"task_shape: {task_shape_value}\n" if task_shape_value else ""

doc = f"""---
title: "{source_id} {short_id}: {title} ({points} pt)"
description: "{scope}"
draft: true
sidebar:
  hidden: true
status: IN_PROGRESS
task_kind: {mode}
{task_shape_line}verification:
  behavior_contract:
    applies: false
    reason: "framework deterministic gate / selftest / helper；無 runtime / UI 行為變更"
depends_on: [{depends_on_frontmatter}]
---

# {short_id}: {title} ({points} pt)

> Source: {source_id} | Task: {task_identity} | JIRA: {jira_key_cell} | Repo: {repo_name}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | {source_type} |
| Source ID | {source_id} |
| Task ID | {task_identity} |
| JIRA key | {jira_key_cell} |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | {base_branch} |
| Branch chain | {branch_chain} |
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
{verify_command_or_detail}
bash scripts/check-script-manifest.sh --root . --quiet
echo "PASS: {task_id}"
```

預期輸出：`PASS: {task_id}`
"""

sys.stdout.write(doc)
PY
