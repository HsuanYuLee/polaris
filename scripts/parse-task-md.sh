#!/usr/bin/env bash
# parse-task-md.sh — DP-032 D8 / DP-033 D8: central parser for task.md work orders.
#
# Reads a task.md produced by breakdown and emits structured JSON capturing
# frontmatter, header, Operational Context table, Test Environment, Test
# Command, Verify Command, Allowed Files, and resolved_base (computed via
# resolve-task-base.sh). All consumers of task.md (engineering SKILL.md,
# engineer-delivery-flow.md, hooks, helper scripts) should call this parser
# rather than grep'ing rows themselves — single point of schema evolution.
#
# Usage:
#   parse-task-md.sh <path/to/task.md>                    # full JSON to stdout
#   parse-task-md.sh <path/to/task.md> --field <key>      # single value to stdout
#   parse-task-md.sh <path/to/task.md> --no-resolve       # skip resolve-task-base
#   parse-task-md.sh --key <TASK_KEY> --tasks-dir <dir>   # key-based lookup with active→pr-release fallback (DP-033 D8)
#   parse-task-md.sh --key <TASK_KEY> --tasks-dir <dir> --field <key>
#   PARSE_TASK_MD_SELFTEST=1 bash parse-task-md.sh        # run embedded selftest
#
# Key-based lookup (DP-033 D8 reader fallback):
#   Given --key T1 --tasks-dir /path/to/specs/EPIC/tasks/:
#     1. Try {tasks_dir}/T1.md  (active)
#     2. Try {tasks_dir}/pr-release/T1.md  (pr-release fallback)
#     3. If both miss → exit 2 with "broken ref" message
#
# Field keys for --field (flat alias of nested JSON paths):
#   status, task_id, summary, story_points,
#   deliverable_pr_url, deliverable_pr_state, deliverable_head_sha,
#   deliverables_changeset_package_scope,
#   deliverables_changeset_bump_level_default,
#   deliverables_changeset_filename_slug,
#   extension_deliverable_endpoint, extension_deliverable_extension_id,
#   extension_deliverable_task_head_sha, extension_deliverable_workspace_commit,
#   extension_deliverable_template_commit, extension_deliverable_version_tag,
#   extension_deliverable_release_url, extension_deliverable_completed_at,
#   extension_deliverable_evidence_ci_local, extension_deliverable_evidence_verify,
#   extension_deliverable_evidence_vr,
#   epic, jira, repo,
#   source_type, source_id, work_item_id, jira_key,
#   task_jira_key, parent_epic, test_sub_tasks, ac_verification_ticket,
#   base_branch, branch_chain, task_branch, depends_on, references_to_load,
#   level, dev_env_config, fixtures, runtime_verify_target, env_bootstrap_command,
#   verification_visual_regression_expected, verification_visual_regression_pages,
#   test_command, verify_command, verify_fallback_command, allowed_files, resolved_base
#
# Exit codes:
#   0 — success (JSON or single field on stdout)
#   1 — file parse error / unknown field
#   2 — usage error / file not found / broken ref (key-based lookup)
#
# Soft-failure model:
#   * Missing markdown sections → corresponding JSON fields are null / [].
#   * resolve-task-base.sh failure → resolved_base = null + stderr warning.
#   * Frontmatter absent → frontmatter.status = null.
#
# Internal dependency: scripts/resolve-task-base.sh (DP-028 Resolve layer).
# Contract source: skills/references/pipeline-handoff.md § Artifact Schemas.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE_TASK_BASE="${SCRIPT_DIR}/resolve-task-base.sh"

usage() {
  cat >&2 <<'USAGE'
usage: parse-task-md.sh <path/to/task.md>
       parse-task-md.sh <path/to/task.md> --field <key>
       parse-task-md.sh <path/to/task.md> --no-resolve
       parse-task-md.sh --key <TASK_KEY> --tasks-dir <dir>
       parse-task-md.sh --key <TASK_KEY> --tasks-dir <dir> --field <key>
       PARSE_TASK_MD_SELFTEST=1 bash parse-task-md.sh

Key-based lookup (DP-033 D8): resolves active tasks/{key}.md first,
  then fallback to tasks/pr-release/{key}.md. Exit 2 if both missing.

Field keys: status, task_id, summary, story_points, epic, jira, repo,
            source_type, source_id, work_item_id, jira_key,
            deliverable_pr_url, deliverable_pr_state, deliverable_head_sha,
            deliverables_changeset_package_scope,
            deliverables_changeset_bump_level_default,
            deliverables_changeset_filename_slug,
            extension_deliverable_endpoint, extension_deliverable_extension_id,
            extension_deliverable_task_head_sha,
            extension_deliverable_workspace_commit,
            extension_deliverable_template_commit,
            extension_deliverable_version_tag,
            extension_deliverable_release_url,
            extension_deliverable_completed_at,
            extension_deliverable_evidence_ci_local,
            extension_deliverable_evidence_verify,
            extension_deliverable_evidence_vr,
            task_jira_key, parent_epic, test_sub_tasks, ac_verification_ticket,
            base_branch, branch_chain, task_branch, depends_on, references_to_load,
            level, dev_env_config, fixtures, runtime_verify_target,
            env_bootstrap_command, verification_visual_regression_expected,
            verification_visual_regression_pages, test_command, verify_command,
            verify_fallback_command, allowed_files, resolved_base
USAGE
}

# ---------- core parser (Python3 inline) -------------------------------------
# Markdown structure (frontmatter, sections, tables, fenced blocks) is much
# cleaner in Python than awk/sed; bash is the orchestration layer.
emit_json() {
  local file="$1"
  local resolved_base="$2"
  python3 - "$file" "$resolved_base" <<'PYEOF'
import json
import re
import sys

path = sys.argv[1]
resolved_base = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None

try:
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
except OSError as e:
    sys.stderr.write(f"error: cannot read {path}: {e}\n")
    sys.exit(1)

lines = text.splitlines()

# ---- frontmatter -----------------------------------------------------------
def parse_scalar(value):
    value = value.strip()
    if value == "":
        return None
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    if value == "[]":
        return []
    if value.startswith("[") and value.endswith("]"):
        body = value[1:-1].strip()
        if not body:
            return []
        return [parse_scalar(part.strip()) for part in body.split(",")]
    if value == "true":
        return True
    if value == "false":
        return False
    return value

def parse_frontmatter_lines(fm_lines):
    """Parse the YAML subset used by task.md lifecycle metadata.

    This intentionally avoids a PyYAML dependency. It supports top-level
    scalars, bracket lists, 2-space nested maps, and one 4-space nested map
    level (for extension_deliverable.evidence).
    """
    out = {}
    i = 0
    while i < len(fm_lines):
        raw = fm_lines[i]
        if not raw.strip() or raw.lstrip().startswith("#") or raw[0].isspace() or ":" not in raw:
            i += 1
            continue
        key, _, value = raw.partition(":")
        key = key.strip()
        value = value.strip()
        if value:
            out[key] = parse_scalar(value)
            i += 1
            continue

        mapping = {}
        i += 1
        while i < len(fm_lines):
            child_raw = fm_lines[i]
            if not child_raw.strip():
                i += 1
                continue
            child_indent = len(child_raw) - len(child_raw.lstrip(" "))
            if child_indent == 0:
                break
            child_stripped = child_raw.strip()
            if child_indent != 2 or ":" not in child_stripped:
                i += 1
                continue
            child_key, _, child_value = child_stripped.partition(":")
            child_key = child_key.strip()
            child_value = child_value.strip()
            if child_value:
                mapping[child_key] = parse_scalar(child_value)
                i += 1
                continue

            nested = {}
            i += 1
            while i < len(fm_lines):
                nested_raw = fm_lines[i]
                if not nested_raw.strip():
                    i += 1
                    continue
                nested_indent = len(nested_raw) - len(nested_raw.lstrip(" "))
                if nested_indent <= 2:
                    break
                nested_stripped = nested_raw.strip()
                if nested_indent == 4 and ":" in nested_stripped:
                    nested_key, _, nested_value = nested_stripped.partition(":")
                    nested[nested_key.strip()] = parse_scalar(nested_value.strip())
                i += 1
            mapping[child_key] = nested
        out[key] = mapping
    return out

frontmatter = {}
body_start = 0
if lines and lines[0].strip() == "---":
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is not None:
        frontmatter = parse_frontmatter_lines(lines[1:end])
        body_start = end + 1

body_lines = lines[body_start:]


# ---- header: # T{n}[suffix]: {summary} ({SP} pt) --------------------------
header = {"task_id": None, "summary": None, "story_points": None}
header_re = re.compile(r"^#\s+(T\d+[a-z]*)\s*:\s*(.+?)\s*\(([0-9.]+)\s*pt\)\s*$")
for ln in body_lines:
    m = header_re.match(ln)
    if m:
        header["task_id"] = m.group(1)
        header["summary"] = m.group(2).strip()
        sp_str = m.group(3)
        try:
            sp = float(sp_str)
            header["story_points"] = int(sp) if sp.is_integer() else sp
        except ValueError:
            header["story_points"] = sp_str
        break


# ---- metadata quote line --------------------------------------------------
# Legacy:
#   > Epic: ... | JIRA: KEY | Repo: ...
# Canonical candidate (DP-050):
#   > Source: DP-050 | Task: DP-050-T1 | JIRA: N/A | Repo: ...
metadata = {"epic": None, "source": None, "task": None, "jira": None, "repo": None}
for ln in body_lines:
    mm = re.match(r"^>\s*(.+)$", ln)
    if not mm or ("JIRA:" not in mm.group(1) and "Task:" not in mm.group(1)):
        continue
    for p in [s.strip() for s in mm.group(1).split("|")]:
        if p.startswith("Epic:"):
            metadata["epic"] = p[len("Epic:"):].strip() or None
        elif p.startswith("Source:"):
            metadata["source"] = p[len("Source:"):].strip() or None
        elif p.startswith("Task:"):
            metadata["task"] = p[len("Task:"):].strip() or None
        elif p.startswith("JIRA:"):
            metadata["jira"] = p[len("JIRA:"):].strip() or None
        elif p.startswith("Repo:"):
            metadata["repo"] = p[len("Repo:"):].strip() or None
    break


# ---- section indexing -----------------------------------------------------
def iter_sections(lns):
    i = 0
    while i < len(lns):
        if lns[i].startswith("## "):
            heading = lns[i].rstrip()
            start = i + 1
            j = start
            while j < len(lns) and not lns[j].startswith("## "):
                j += 1
            yield heading, lns[start:j]
            i = j
        else:
            i += 1

sections = {h.strip(): body for h, body in iter_sections(body_lines)}

def section_lines(heading):
    return sections.get(heading, [])


# ---- Operational Context table -------------------------------------------
op_ctx_raw = {}
for ln in section_lines("## Operational Context"):
    if not ln.lstrip().startswith("|"):
        continue
    cells = [c.strip() for c in ln.strip().strip("|").split("|")]
    if len(cells) < 2:
        continue
    name, val = cells[0], cells[1]
    if not name or name in ("欄位",) or set(name) <= {"-", " "}:
        continue
    if val == "值":
        continue
    op_ctx_raw[name] = val

NA_SENTINELS = {"-", "N/A", "n/a", "無", "None", "none", ""}

def opf(label, allow_sentinel=False):
    v = op_ctx_raw.get(label)
    if v is None:
        return None
    if not allow_sentinel and v.strip() in NA_SENTINELS:
        return None
    return v

operational_context = {
    "task_jira_key": opf("Task JIRA key"),
    "source_type": opf("Source type"),
    "source_id": opf("Source ID"),
    "task_id": opf("Task ID"),
    "jira_key": opf("JIRA key"),
    "parent_epic": opf("Parent Epic"),
    "test_sub_tasks": opf("Test sub-tasks"),
    "ac_verification_ticket": opf("AC 驗收單"),
    "base_branch": opf("Base branch"),
    "branch_chain": opf("Branch chain"),
    "task_branch": opf("Task branch"),
    "depends_on": opf("Depends on"),
    "references_to_load": opf("References to load"),
}


# ---- Canonical identity (DP-050) -----------------------------------------
def normalize_jira(value):
    if value is None:
        return None
    v = value.strip()
    if v in NA_SENTINELS or v.upper() == "N/A":
        return None
    return v

def infer_source_type(source_id, work_item_id, jira_key):
    explicit = operational_context.get("source_type")
    if explicit:
        return explicit.lower()
    if (source_id or "").startswith("DP-") or re.match(r"^DP-\d{3}-T\d+[a-z]*$", work_item_id or ""):
        return "dp"
    if jira_key:
        return "jira"
    return None

source_id = (
    operational_context.get("source_id")
    or metadata.get("source")
    or operational_context.get("parent_epic")
    or metadata.get("epic")
)
work_item_id = (
    operational_context.get("task_id")
    or metadata.get("task")
    or operational_context.get("task_jira_key")
    or metadata.get("jira")
)
jira_key = normalize_jira(operational_context.get("jira_key") or metadata.get("jira"))
source_type = infer_source_type(source_id, work_item_id, jira_key)
if source_type == "dp":
    jira_key = normalize_jira(operational_context.get("jira_key"))
elif source_type == "jira" and jira_key is None:
    jira_key = work_item_id

identity = {
    "source_type": source_type,
    "source_id": source_id,
    "work_item_id": work_item_id,
    "jira_key": jira_key,
}

# Migration aliases. Product aliases equal the real JIRA key; DP aliases return
# work_item_id so old consumers keep resolving framework pseudo-tasks.
if operational_context["task_jira_key"] is None and work_item_id:
    operational_context["task_jira_key"] = work_item_id
if metadata["jira"] is not None and normalize_jira(metadata["jira"]) is None:
    metadata["jira"] = None


# ---- Test Environment ----------------------------------------------------
test_env = {
    "level": None,
    "dev_env_config": None,
    "fixtures": None,
    "runtime_verify_target": None,
    "env_bootstrap_command": None,
}
te_re = re.compile(r"^[\-*]?\s*\*\*([^*]+?)\*\*\s*:\s*(.+?)\s*$")
te_map = {
    "Level": "level",
    "Dev env config": "dev_env_config",
    "Fixtures": "fixtures",
    "Runtime verify target": "runtime_verify_target",
    "Env bootstrap command": "env_bootstrap_command",
}
for ln in section_lines("## Test Environment"):
    m = te_re.match(ln)
    if not m:
        continue
    label = m.group(1).strip()
    val = m.group(2).strip()
    key = te_map.get(label)
    if not key:
        continue
    if val.startswith("`") and val.endswith("`") and len(val) > 1:
        val = val[1:-1].strip()
    test_env[key] = val
if test_env["level"] is not None:
    test_env["level"] = test_env["level"].lower()
# Normalize sentinel "N/A" / "-" / empty → null on string fields. Level is an
# enum and stays as-is; consumer branches on level before reading other fields.
for k in ("dev_env_config", "fixtures", "runtime_verify_target", "env_bootstrap_command"):
    v = test_env.get(k)
    if v is not None and v.strip() in NA_SENTINELS:
        test_env[k] = None


# ---- Verification metadata ------------------------------------------------
verification_block = frontmatter.get("verification")
if not isinstance(verification_block, dict):
    verification_block = {}
visual_regression_block = verification_block.get("visual_regression")
if not isinstance(visual_regression_block, dict):
    visual_regression_block = {}

vr_expected = visual_regression_block.get("expected")
if not isinstance(vr_expected, str) or vr_expected.strip() in NA_SENTINELS:
    vr_expected = None
else:
    vr_expected = vr_expected.strip()

vr_pages = visual_regression_block.get("pages")
if isinstance(vr_pages, list):
    vr_pages = [str(page) for page in vr_pages]
else:
    vr_pages = None

verification = {
    "visual_regression": {
        "expected": vr_expected,
        "pages": vr_pages,
    }
}


# ---- first fenced code block helper --------------------------------------
def first_code_block(lns):
    in_block = False
    out = []
    for ln in lns:
        if ln.startswith("```"):
            if in_block:
                return "\n".join(out).rstrip()
            in_block = True
            continue
        if in_block:
            out.append(ln)
    return ("\n".join(out).rstrip()) if (in_block and out) else None

test_command = first_code_block(section_lines("## Test Command"))
verify_command = first_code_block(section_lines("## Verify Command"))
verify_fallback_command = first_code_block(section_lines("## Verify Fallback Command"))


# ---- Allowed Files (bullet list) -----------------------------------------
allowed_files = []
for ln in section_lines("## Allowed Files"):
    s = ln.strip()
    if s.startswith("- ") or s.startswith("* "):
        allowed_files.append(s[2:].strip())


out = {
    "task_md_path": path,
    "frontmatter": frontmatter,
    "header": header,
    "metadata": metadata,
    "identity": identity,
    "operational_context": operational_context,
    "test_environment": test_env,
    "verification": verification,
    "test_command": test_command,
    "verify_command": verify_command,
    "verify_fallback_command": verify_fallback_command,
    "allowed_files": allowed_files,
    "resolved_base": resolved_base,
}

json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
sys.stdout.write("\n")
PYEOF
}


# ---------- field selector --------------------------------------------------
# Reads JSON from stdin and prints a single field's value to stdout.
# Note: uses `python3 -c` (script via argv) so stdin stays available for the
# JSON pipe — `python3 -` (script via stdin) would conflict with the heredoc.
emit_field() {
  local field="$1"
  python3 -c '
import json
import sys

field = sys.argv[1]
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError as e:
    sys.stderr.write("error: invalid JSON from emit_json: %s\n" % e)
    sys.exit(1)

aliases = {
    "status":                  ["frontmatter", "status"],
    "deliverable_pr_url":      ["frontmatter", "deliverable", "pr_url"],
    "deliverable_pr_state":    ["frontmatter", "deliverable", "pr_state"],
    "deliverable_head_sha":    ["frontmatter", "deliverable", "head_sha"],
    "deliverables_changeset_package_scope":       ["frontmatter", "deliverables", "changeset", "package_scope"],
    "deliverables_changeset_bump_level_default":  ["frontmatter", "deliverables", "changeset", "bump_level_default"],
    "deliverables_changeset_filename_slug":       ["frontmatter", "deliverables", "changeset", "filename_slug"],
    "extension_deliverable_endpoint":          ["frontmatter", "extension_deliverable", "endpoint"],
    "extension_deliverable_extension_id":      ["frontmatter", "extension_deliverable", "extension_id"],
    "extension_deliverable_task_head_sha":     ["frontmatter", "extension_deliverable", "task_head_sha"],
    "extension_deliverable_workspace_commit":  ["frontmatter", "extension_deliverable", "workspace_commit"],
    "extension_deliverable_template_commit":   ["frontmatter", "extension_deliverable", "template_commit"],
    "extension_deliverable_version_tag":       ["frontmatter", "extension_deliverable", "version_tag"],
    "extension_deliverable_release_url":       ["frontmatter", "extension_deliverable", "release_url"],
    "extension_deliverable_completed_at":      ["frontmatter", "extension_deliverable", "completed_at"],
    "extension_deliverable_evidence_ci_local": ["frontmatter", "extension_deliverable", "evidence", "ci_local"],
    "extension_deliverable_evidence_verify":   ["frontmatter", "extension_deliverable", "evidence", "verify"],
    "extension_deliverable_evidence_vr":       ["frontmatter", "extension_deliverable", "evidence", "vr"],
    "task_id":                 ["header", "task_id"],
    "summary":                 ["header", "summary"],
    "story_points":            ["header", "story_points"],
    "epic":                    ["metadata", "epic"],
    "jira":                    ["metadata", "jira"],
    "repo":                    ["metadata", "repo"],
    "source_type":             ["identity", "source_type"],
    "source_id":               ["identity", "source_id"],
    "work_item_id":            ["identity", "work_item_id"],
    "jira_key":                ["identity", "jira_key"],
    "task_jira_key":           ["operational_context", "task_jira_key"],
    "parent_epic":             ["operational_context", "parent_epic"],
    "test_sub_tasks":          ["operational_context", "test_sub_tasks"],
    "ac_verification_ticket":  ["operational_context", "ac_verification_ticket"],
    "base_branch":             ["operational_context", "base_branch"],
    "branch_chain":            ["operational_context", "branch_chain"],
    "task_branch":             ["operational_context", "task_branch"],
    "depends_on":              ["operational_context", "depends_on"],
    "references_to_load":      ["operational_context", "references_to_load"],
    "level":                   ["test_environment", "level"],
    "dev_env_config":          ["test_environment", "dev_env_config"],
    "fixtures":                ["test_environment", "fixtures"],
    "runtime_verify_target":   ["test_environment", "runtime_verify_target"],
    "env_bootstrap_command":   ["test_environment", "env_bootstrap_command"],
    "verification_visual_regression_expected": ["verification", "visual_regression", "expected"],
    "verification_visual_regression_pages":    ["verification", "visual_regression", "pages"],
    "test_command":            ["test_command"],
    "verify_command":          ["verify_command"],
    "verify_fallback_command": ["verify_fallback_command"],
    "allowed_files":           ["allowed_files"],
    "resolved_base":           ["resolved_base"],
}

if field not in aliases:
    sys.stderr.write("error: unknown field: %s\n" % field)
    sys.stderr.write("valid fields: %s\n" % ", ".join(sorted(aliases)))
    sys.exit(1)

val = data
for k in aliases[field]:
    if isinstance(val, dict):
        val = val.get(k)
    else:
        val = None
        break

if val is None:
    sys.exit(0)
if isinstance(val, list):
    print("\n".join(str(x) for x in val))
elif isinstance(val, bool):
    print("true" if val else "false")
else:
    print(val)
' "$field"
}


# ---------- absolute path helper -------------------------------------------
abs_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    printf '%s' "$p"
  else
    printf '%s' "$(cd "$(dirname "$p")" 2>/dev/null && pwd)/$(basename "$p")"
  fi
}


# ---------- self-test -------------------------------------------------------
if [[ "${PARSE_TASK_MD_SELFTEST:-0}" == "1" ]]; then
  set +e
  tmpdir="$(mktemp -d -t parse-task-md-selftest.XXXXXX)"
  trap 'rm -rf "$tmpdir"' EXIT

  fixture="$tmpdir/T3b.md"
  cat > "$fixture" <<'MD'
---
status: IMPLEMENTED
deliverable:
  pr_url: https://github.com/example-org/example/pull/123
  pr_state: OPEN
  head_sha: abc1234
deliverables:
  changeset:
    package_scope: "@exampleco/b2c-web-main"
    bump_level_default: patch
    filename_slug: kb2cw-3900-products-dayjs
verification:
  visual_regression:
    expected: none_allowed
    pages: ["/zh-tw"]
extension_deliverable:
  endpoint: local_extension
  extension_id: example-extension
  task_head_sha: abc1234
  workspace_commit: def5678
  template_commit: fedcba9
  version_tag: v1.2.3
  release_url: https://github.com/example/template/releases/tag/v1.2.3
  completed_at: 2026-04-29T00:00:00Z
  evidence:
    ci_local: /tmp/polaris-ci-local.json
    verify: /tmp/polaris-verified.json
    vr: N/A
---

# T3b: products pages moment→dayjs 替換 (5 pt)

> Epic: EPIC-478 | JIRA: TASK-3900 | Repo: exampleco-b2c-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | TASK-3900 |
| Parent Epic | EPIC-478 |
| Test sub-tasks | TASK-3826 |
| AC 驗收單 | TASK-3713 |
| Base branch | task/TASK-3711-dayjs-infra-util |
| Branch chain | develop -> feat/EPIC-478-cwv-js-bundle -> task/TASK-3711-dayjs-infra-util -> task/TASK-3900-moment-to-dayjs-products |
| Task branch | task/TASK-3900-moment-to-dayjs-products |
| Depends on | TASK-3711 (T3a — dayjs infra) |
| References to load | - foo<br>- bar |

## Verification Handoff

AC 驗證**不在本 task 範圍**。

## 目標

替換 moment → dayjs。

## 改動範圍

| 檔案 | 動作 |
|------|------|
| apps/main/foo.ts | modify |

## Allowed Files

- `apps/main/plugins/dayjs.ts`
- `apps/main/products/**`
- 上述檔案的 test 檔

## 估點理由

5 pt — 約 30 files。

## 測試計畫（code-level）

- unit test → TASK-3826

## Test Command

```bash
pnpm --dir apps/main exec vitest run
```

## Test Environment

- **Level**: static
- **Dev env config**: `workspace-config.yaml → projects[exampleco-b2c-web].dev_environment`
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
count=$(grep -rln "from 'moment'" apps/main | wc -l | xargs); [ "$count" = "0" ] && echo PASS || echo "FAIL: $count"
```

預期輸出：`PASS`
MD

  # Fixture 2: minimal task with no frontmatter, no Depends on, runtime level
  fixture2="$tmpdir/T1.md"
  cat > "$fixture2" <<'MD'
# T1: Mockoon fixtures (2 pt)

> Epic: EPIC-478 | JIRA: TASK-3821 | Repo: exampleco-b2c-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | TASK-3821 |
| Parent Epic | EPIC-478 |
| Test sub-tasks | TASK-3823 |
| AC 驗收單 | TASK-3713 |
| Base branch | feat/EPIC-478-cwv-js-bundle |
| Branch chain | develop -> feat/EPIC-478-cwv-js-bundle -> task/TASK-3821-mockoon-fixtures |
| Task branch | task/TASK-3821-mockoon-fixtures |
| References to load | - api-contract-guard |

## Verification Handoff

委派 TASK-3713。

## 目標

確立 fixture 覆蓋。

## 改動範圍

| 檔案 | 動作 |
|------|------|
| exampleco/mockoon/fixtures/gt478/ | create |

## Allowed Files

- exampleco/mockoon/fixtures/gt478/

## 估點理由

2 pt — 4 頁 fixture。

## 測試計畫（code-level）

- build check → TASK-3823

## Test Command

```bash
pnpm --dir apps/main exec vitest run
```

## Test Environment

- **Level**: runtime
- **Dev env config**: `workspace-config.yaml → projects[exampleco-b2c-web].dev_environment`
- **Fixtures**: `specs/EPIC-478/tests/mockoon/`
- **Runtime verify target**: http://localhost:3100
- **Env bootstrap command**: bash /path/to/polaris-env.sh start exampleco

## Verify Command

```bash
curl -sf http://localhost:3100/api/activities | head -1
```
MD

  fail=0
  out_file="$(mktemp)"
  err_file="$(mktemp)"

  run_full() {
    : > "$out_file"; : > "$err_file"
    emit_json "$1" "$2" >"$out_file" 2>"$err_file"
    return $?
  }

  expect_field() {
    local file="$1"; local field="$2"; local want="$3"; local label="$4"
    local got
    got="$(emit_json "$file" "" | emit_field "$field" 2>/dev/null)"
    if [[ "$got" != "$want" ]]; then
      echo "[selftest] $label: got '$got' want '$want'"; fail=1
    fi
  }

  # ---- Fixture 1 (T3b) basic field extraction ------------------------------
  expect_field "$fixture" status                 "IMPLEMENTED"           "F1.status"
  expect_field "$fixture" deliverable_pr_url     "https://github.com/example-org/example/pull/123" "F1.deliverable_pr_url"
  expect_field "$fixture" deliverable_pr_state   "OPEN"                  "F1.deliverable_pr_state"
  expect_field "$fixture" deliverable_head_sha   "abc1234"               "F1.deliverable_head_sha"
  expect_field "$fixture" deliverables_changeset_package_scope "@exampleco/b2c-web-main" "F1.changeset_package_scope"
  expect_field "$fixture" deliverables_changeset_bump_level_default "patch" "F1.changeset_bump"
  expect_field "$fixture" deliverables_changeset_filename_slug "kb2cw-3900-products-dayjs" "F1.changeset_slug"
  expect_field "$fixture" extension_deliverable_endpoint "local_extension" "F1.extension_endpoint"
  expect_field "$fixture" extension_deliverable_extension_id "example-extension" "F1.extension_id"
  expect_field "$fixture" extension_deliverable_task_head_sha "abc1234"  "F1.extension_task_head"
  expect_field "$fixture" extension_deliverable_workspace_commit "def5678" "F1.extension_workspace_commit"
  expect_field "$fixture" extension_deliverable_template_commit "fedcba9" "F1.extension_template_commit"
  expect_field "$fixture" extension_deliverable_version_tag "v1.2.3"     "F1.extension_version_tag"
  expect_field "$fixture" extension_deliverable_release_url "https://github.com/example/template/releases/tag/v1.2.3" "F1.extension_release_url"
  expect_field "$fixture" extension_deliverable_completed_at "2026-04-29T00:00:00Z" "F1.extension_completed_at"
  expect_field "$fixture" extension_deliverable_evidence_ci_local "/tmp/polaris-ci-local.json" "F1.extension_evidence_ci"
  expect_field "$fixture" extension_deliverable_evidence_verify "/tmp/polaris-verified.json" "F1.extension_evidence_verify"
  expect_field "$fixture" extension_deliverable_evidence_vr "N/A"        "F1.extension_evidence_vr"
  expect_field "$fixture" verification_visual_regression_expected "none_allowed" "F1.vr_expected"
  expect_field "$fixture" verification_visual_regression_pages "/zh-tw" "F1.vr_pages"
  expect_field "$fixture" task_id                "T3b"                   "F1.task_id"
  expect_field "$fixture" summary                "products pages moment→dayjs 替換" "F1.summary"
  expect_field "$fixture" story_points           "5"                     "F1.story_points"
  expect_field "$fixture" epic                   "EPIC-478"                "F1.epic"
  expect_field "$fixture" jira                   "TASK-3900"            "F1.jira"
  expect_field "$fixture" repo                   "exampleco-b2c-web"         "F1.repo"
  expect_field "$fixture" source_type            "jira"                  "F1.source_type"
  expect_field "$fixture" source_id              "EPIC-478"                "F1.source_id"
  expect_field "$fixture" work_item_id           "TASK-3900"            "F1.work_item_id"
  expect_field "$fixture" jira_key               "TASK-3900"            "F1.jira_key"
  expect_field "$fixture" task_jira_key          "TASK-3900"            "F1.task_jira_key"
  expect_field "$fixture" parent_epic            "EPIC-478"                "F1.parent_epic"
  expect_field "$fixture" base_branch            "task/TASK-3711-dayjs-infra-util"          "F1.base_branch"
  expect_field "$fixture" branch_chain           "develop -> feat/EPIC-478-cwv-js-bundle -> task/TASK-3711-dayjs-infra-util -> task/TASK-3900-moment-to-dayjs-products" "F1.branch_chain"
  expect_field "$fixture" task_branch            "task/TASK-3900-moment-to-dayjs-products"  "F1.task_branch"
  expect_field "$fixture" depends_on             "TASK-3711 (T3a — dayjs infra)"            "F1.depends_on"
  expect_field "$fixture" level                  "static"                "F1.level"
  expect_field "$fixture" runtime_verify_target  ""                      "F1.runtime_target_NA"
  expect_field "$fixture" env_bootstrap_command  ""                      "F1.bootstrap_NA"
  expect_field "$fixture" fixtures               ""                      "F1.fixtures_NA"
  expect_field "$fixture" test_command           "pnpm --dir apps/main exec vitest run" "F1.test_command"

  # verify_command spans single-line; just check it's non-empty + contains key
  vc="$(emit_json "$fixture" "" | emit_field verify_command)"
  if [[ "$vc" != *"echo PASS"* ]]; then
    echo "[selftest] F1.verify_command missing 'echo PASS' in: $vc"; fail=1
  fi

  # allowed_files: 3 lines
  af="$(emit_json "$fixture" "" | emit_field allowed_files)"
  af_count=$(printf '%s\n' "$af" | wc -l | tr -d ' ')
  if [[ "$af_count" != "3" ]]; then
    echo "[selftest] F1.allowed_files expected 3 lines, got $af_count"; fail=1
  fi
  if [[ "$af" != *"apps/main/plugins/dayjs.ts"* ]]; then
    echo "[selftest] F1.allowed_files missing dayjs.ts entry"; fail=1
  fi

  # resolved_base passthrough — emit_json with explicit value
  rb_out="$(emit_json "$fixture" "feat/foo" | emit_field resolved_base)"
  if [[ "$rb_out" != "feat/foo" ]]; then
    echo "[selftest] F1.resolved_base passthrough: got '$rb_out' want 'feat/foo'"; fail=1
  fi
  # resolved_base null when empty
  rb_null="$(emit_json "$fixture" "" | emit_field resolved_base)"
  if [[ -n "$rb_null" ]]; then
    echo "[selftest] F1.resolved_base empty: expected '' got '$rb_null'"; fail=1
  fi

  # ---- Fixture 2 (T1) — no frontmatter, runtime level, no depends_on ------
  expect_field "$fixture2" status                ""                              "F2.status_absent"
  expect_field "$fixture2" task_id               "T1"                            "F2.task_id"
  expect_field "$fixture2" story_points          "2"                             "F2.story_points"
  expect_field "$fixture2" depends_on            ""                              "F2.depends_on_absent"
  expect_field "$fixture2" level                 "runtime"                       "F2.level_runtime"
  expect_field "$fixture2" runtime_verify_target "http://localhost:3100"         "F2.runtime_target"
  expect_field "$fixture2" fixtures              "specs/EPIC-478/tests/mockoon/"   "F2.fixtures"
  if [[ "$(emit_json "$fixture2" "" | emit_field env_bootstrap_command)" != "bash /path/to/polaris-env.sh start exampleco" ]]; then
    echo "[selftest] F2.env_bootstrap mismatch"; fail=1
  fi

  # ---- Fixture 3 (DP canonical identity) ---------------------------------
  fixture3="$tmpdir/T1-dp-canonical.md"
  cat > "$fixture3" <<'MD'
# T1: Canonical task identity schema, parser, and validator (5 pt)

> Source: DP-050 | Task: DP-050-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-050 |
| Task ID | DP-050-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-050-T1-canonical-task-identity |
| Task branch | task/DP-050-T1-canonical-task-identity |
| Depends on | N/A |
| References to load | - task-md-schema |

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A
MD
  expect_field "$fixture3" source_type            "dp"                    "F3.source_type"
  expect_field "$fixture3" source_id              "DP-050"                "F3.source_id"
  expect_field "$fixture3" work_item_id           "DP-050-T1"             "F3.work_item_id"
  expect_field "$fixture3" jira_key               ""                      "F3.jira_key_empty"
  expect_field "$fixture3" jira                   ""                      "F3.legacy_jira_empty"
  expect_field "$fixture3" task_jira_key          "DP-050-T1"             "F3.task_jira_key_alias"

  # ---- Fixture 4 (VR empty pages) ----------------------------------------
  fixture4="$tmpdir/T4-vr-empty-pages.md"
  cat > "$fixture4" <<'MD'
---
verification:
  visual_regression:
    expected: baseline_required
    pages: []
---

# T4: Empty VR pages (1 pt)

> Source: DP-104 | Task: DP-104-T4 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-104 |
| Task ID | DP-104-T4 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-104-T4-vr-empty-pages |
| Task branch | task/DP-104-T4-vr-empty-pages |
| Depends on | N/A |
| References to load | - task-md-schema |

## Test Environment

- **Level**: runtime
- **Dev env config**: workspace-config.yaml
- **Fixtures**: N/A
- **Runtime verify target**: http://localhost:3100
- **Env bootstrap command**: bash scripts/start-test-env.sh
MD
  expect_field "$fixture4" verification_visual_regression_expected "baseline_required" "F4.vr_expected"
  vr_pages_empty="$(emit_json "$fixture4" "" | emit_field verification_visual_regression_pages)"
  if [[ -n "$vr_pages_empty" ]]; then
    echo "[selftest] F4.vr_pages_empty: expected empty output got '$vr_pages_empty'"; fail=1
  fi

  # ---- Full JSON shape sanity (validates JSON parseability) ---------------
  if ! emit_json "$fixture" "" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    echo "[selftest] F1.full_json: invalid JSON output"; fail=1
  fi
  if ! emit_json "$fixture2" "" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    echo "[selftest] F2.full_json: invalid JSON output"; fail=1
  fi
  if ! emit_json "$fixture4" "" | python3 -c 'import json,sys; data=json.load(sys.stdin); assert data["verification"]["visual_regression"]["pages"] == []' 2>/dev/null; then
    echo "[selftest] F4.full_json: VR pages did not serialize as []"; fail=1
  fi

  # ---- File-not-found ------------------------------------------------------
  : > "$err_file"
  emit_json "$tmpdir/nope.md" "" >/dev/null 2>"$err_file"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "[selftest] missing-file: expected non-zero exit, got 0"; fail=1
  fi
  if ! grep -q 'cannot read' "$err_file"; then
    echo "[selftest] missing-file: stderr lacks 'cannot read'"; fail=1
  fi

  # ---- Unknown field -------------------------------------------------------
  : > "$err_file"
  emit_json "$fixture" "" | emit_field "bogus" >/dev/null 2>"$err_file"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "[selftest] unknown-field: expected non-zero exit, got 0"; fail=1
  fi
  if ! grep -q 'unknown field' "$err_file"; then
    echo "[selftest] unknown-field: stderr lacks 'unknown field'"; fail=1
  fi

  rm -f "$out_file" "$err_file"

  if [[ $fail -eq 0 ]]; then
    echo "[selftest] PASS"
    exit 0
  else
    echo "[selftest] FAIL"
    exit 1
  fi
fi


# ---------- argument parsing ------------------------------------------------
file=""
field=""
no_resolve=0
task_key=""
tasks_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --field)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      field="$2"
      shift 2
      ;;
    --no-resolve)
      no_resolve=1
      shift
      ;;
    --key)
      # DP-033 D8: key-based lookup with active→pr-release fallback
      [[ $# -ge 2 ]] || { usage; exit 2; }
      task_key="$2"
      shift 2
      ;;
    --tasks-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      tasks_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 2
      ;;
    --*)
      echo "error: unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      if [[ -n "$file" ]]; then
        echo "error: unexpected extra argument: $1" >&2
        usage
        exit 2
      fi
      file="$1"
      shift
      ;;
  esac
done

# DP-033 D8: key-based lookup mode
if [[ -n "$task_key" ]]; then
  if [[ -z "$tasks_dir" ]]; then
    echo "error: --key requires --tasks-dir" >&2
    usage
    exit 2
  fi
  if [[ ! -d "$tasks_dir" ]]; then
    echo "error: tasks-dir not found: $tasks_dir" >&2
    exit 2
  fi
  tasks_dir_abs="$(abs_path "$tasks_dir")"
  # Lookup order: active → pr-release fallback
  active_path="${tasks_dir_abs}/${task_key}.md"
  pr_release_path="${tasks_dir_abs}/pr-release/${task_key}.md"
  if [[ -f "$active_path" ]]; then
    file="$active_path"
  elif [[ -f "$pr_release_path" ]]; then
    file="$pr_release_path"
  else
    echo "error: broken ref — task key '${task_key}' not found in ${tasks_dir_abs}/ or ${tasks_dir_abs}/pr-release/" >&2
    exit 2
  fi
fi

if [[ -z "$file" ]]; then
  usage
  exit 2
fi

if [[ ! -f "$file" ]]; then
  echo "error: file not found: $file" >&2
  exit 2
fi

file_abs="$(abs_path "$file")"


# ---------- resolve_base via resolve-task-base.sh --------------------------
resolved_base=""
if [[ "$no_resolve" -eq 0 ]]; then
  if [[ -x "$RESOLVE_TASK_BASE" ]]; then
    if rb_out="$("$RESOLVE_TASK_BASE" "$file_abs" 2>/dev/null)" && [[ -n "$rb_out" ]]; then
      resolved_base="$rb_out"
    else
      echo "warn: resolve-task-base.sh failed for $file_abs (resolved_base=null)" >&2
    fi
  else
    echo "warn: resolve-task-base.sh not found at $RESOLVE_TASK_BASE (resolved_base=null)" >&2
  fi
fi


# ---------- emit ------------------------------------------------------------
if [[ -n "$field" ]]; then
  emit_json "$file_abs" "$resolved_base" | emit_field "$field"
  exit $?
else
  emit_json "$file_abs" "$resolved_base"
  exit $?
fi
