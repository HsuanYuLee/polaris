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
#   parse-task-md.sh --key <TASK_KEY> --tasks-dir <dir>   # key-based lookup with active→complete fallback (DP-033 D8)
#   parse-task-md.sh --key <TASK_KEY> --tasks-dir <dir> --field <key>
#   PARSE_TASK_MD_SELFTEST=1 bash parse-task-md.sh        # run embedded selftest
#
# Key-based lookup (DP-033 D8 reader fallback):
#   Given --key T1 --tasks-dir /path/to/specs/EPIC/tasks/:
#     1. Try {tasks_dir}/T1.md  (active)
#     2. Try {tasks_dir}/complete/T1.md  (completed fallback)
#     3. If both miss → exit 2 with "broken ref" message
#
# Field keys for --field (flat alias of nested JSON paths):
#   status, task_id, summary, story_points,
#   epic, jira, repo,
#   task_jira_key, parent_epic, test_sub_tasks, ac_verification_ticket,
#   base_branch, branch_chain, task_branch, depends_on, references_to_load,
#   level, dev_env_config, fixtures, runtime_verify_target, env_bootstrap_command,
#   test_command, verify_command, allowed_files, resolved_base
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
  then fallback to tasks/complete/{key}.md. Exit 2 if both missing.

Field keys: status, task_id, summary, story_points, epic, jira, repo,
            task_jira_key, parent_epic, test_sub_tasks, ac_verification_ticket,
            base_branch, branch_chain, task_branch, depends_on, references_to_load,
            level, dev_env_config, fixtures, runtime_verify_target,
            env_bootstrap_command, test_command, verify_command,
            allowed_files, resolved_base
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
frontmatter = {}
body_start = 0
if lines and lines[0].strip() == "---":
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is not None:
        for raw in lines[1:end]:
            if ":" in raw:
                k, _, v = raw.partition(":")
                frontmatter[k.strip()] = v.strip()
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


# ---- metadata quote line: > Epic: ... | JIRA: KEY | Repo: ... -------------
metadata = {"epic": None, "jira": None, "repo": None}
for ln in body_lines:
    mm = re.match(r"^>\s*(.+)$", ln)
    if not mm or "JIRA:" not in mm.group(1):
        continue
    for p in [s.strip() for s in mm.group(1).split("|")]:
        if p.startswith("Epic:"):
            metadata["epic"] = p[len("Epic:"):].strip() or None
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
    "parent_epic": opf("Parent Epic"),
    "test_sub_tasks": opf("Test sub-tasks"),
    "ac_verification_ticket": opf("AC 驗收單"),
    "base_branch": opf("Base branch"),
    "branch_chain": opf("Branch chain"),
    "task_branch": opf("Task branch"),
    "depends_on": opf("Depends on"),
    "references_to_load": opf("References to load"),
}


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


# ---- Allowed Files (bullet list) -----------------------------------------
allowed_files = []
for ln in section_lines("## Allowed Files"):
    s = ln.strip()
    if s.startswith("- ") or s.startswith("* "):
        allowed_files.append(s[2:].strip())


out = {
    "task_md_path": path,
    "frontmatter": {
        "status": frontmatter.get("status") or None,
    },
    "header": header,
    "metadata": metadata,
    "operational_context": operational_context,
    "test_environment": test_env,
    "test_command": test_command,
    "verify_command": verify_command,
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
    "task_id":                 ["header", "task_id"],
    "summary":                 ["header", "summary"],
    "story_points":            ["header", "story_points"],
    "epic":                    ["metadata", "epic"],
    "jira":                    ["metadata", "jira"],
    "repo":                    ["metadata", "repo"],
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
    "test_command":            ["test_command"],
    "verify_command":          ["verify_command"],
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
---

# T3b: products pages moment→dayjs 替換 (5 pt)

> Epic: GT-478 | JIRA: KB2CW-3900 | Repo: kkday-b2c-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | KB2CW-3900 |
| Parent Epic | GT-478 |
| Test sub-tasks | KB2CW-3826 |
| AC 驗收單 | KB2CW-3713 |
| Base branch | task/KB2CW-3711-dayjs-infra-util |
| Branch chain | develop -> feat/GT-478-cwv-js-bundle -> task/KB2CW-3711-dayjs-infra-util -> task/KB2CW-3900-moment-to-dayjs-products |
| Task branch | task/KB2CW-3900-moment-to-dayjs-products |
| Depends on | KB2CW-3711 (T3a — dayjs infra) |
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

- unit test → KB2CW-3826

## Test Command

```bash
pnpm -C apps/main vitest run
```

## Test Environment

- **Level**: static
- **Dev env config**: `workspace-config.yaml → projects[kkday-b2c-web].dev_environment`
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

> Epic: GT-478 | JIRA: KB2CW-3821 | Repo: kkday-b2c-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | KB2CW-3821 |
| Parent Epic | GT-478 |
| Test sub-tasks | KB2CW-3823 |
| AC 驗收單 | KB2CW-3713 |
| Base branch | feat/GT-478-cwv-js-bundle |
| Branch chain | develop -> feat/GT-478-cwv-js-bundle -> task/KB2CW-3821-mockoon-fixtures |
| Task branch | task/KB2CW-3821-mockoon-fixtures |
| References to load | - api-contract-guard |

## Verification Handoff

委派 KB2CW-3713。

## 目標

確立 fixture 覆蓋。

## 改動範圍

| 檔案 | 動作 |
|------|------|
| kkday/mockoon/fixtures/gt478/ | create |

## Allowed Files

- kkday/mockoon/fixtures/gt478/

## 估點理由

2 pt — 4 頁 fixture。

## 測試計畫（code-level）

- build check → KB2CW-3823

## Test Command

```bash
pnpm -C apps/main vitest run
```

## Test Environment

- **Level**: runtime
- **Dev env config**: `workspace-config.yaml → projects[kkday-b2c-web].dev_environment`
- **Fixtures**: `specs/GT-478/tests/mockoon/`
- **Runtime verify target**: http://localhost:3100
- **Env bootstrap command**: bash /path/to/polaris-env.sh start kkday

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
  expect_field "$fixture" task_id                "T3b"                   "F1.task_id"
  expect_field "$fixture" summary                "products pages moment→dayjs 替換" "F1.summary"
  expect_field "$fixture" story_points           "5"                     "F1.story_points"
  expect_field "$fixture" epic                   "GT-478"                "F1.epic"
  expect_field "$fixture" jira                   "KB2CW-3900"            "F1.jira"
  expect_field "$fixture" repo                   "kkday-b2c-web"         "F1.repo"
  expect_field "$fixture" task_jira_key          "KB2CW-3900"            "F1.task_jira_key"
  expect_field "$fixture" parent_epic            "GT-478"                "F1.parent_epic"
  expect_field "$fixture" base_branch            "task/KB2CW-3711-dayjs-infra-util"          "F1.base_branch"
  expect_field "$fixture" branch_chain           "develop -> feat/GT-478-cwv-js-bundle -> task/KB2CW-3711-dayjs-infra-util -> task/KB2CW-3900-moment-to-dayjs-products" "F1.branch_chain"
  expect_field "$fixture" task_branch            "task/KB2CW-3900-moment-to-dayjs-products"  "F1.task_branch"
  expect_field "$fixture" depends_on             "KB2CW-3711 (T3a — dayjs infra)"            "F1.depends_on"
  expect_field "$fixture" level                  "static"                "F1.level"
  expect_field "$fixture" runtime_verify_target  ""                      "F1.runtime_target_NA"
  expect_field "$fixture" env_bootstrap_command  ""                      "F1.bootstrap_NA"
  expect_field "$fixture" fixtures               ""                      "F1.fixtures_NA"
  expect_field "$fixture" test_command           "pnpm -C apps/main vitest run" "F1.test_command"

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
  expect_field "$fixture2" fixtures              "specs/GT-478/tests/mockoon/"   "F2.fixtures"
  if [[ "$(emit_json "$fixture2" "" | emit_field env_bootstrap_command)" != "bash /path/to/polaris-env.sh start kkday" ]]; then
    echo "[selftest] F2.env_bootstrap mismatch"; fail=1
  fi

  # ---- Full JSON shape sanity (validates JSON parseability) ---------------
  if ! emit_json "$fixture" "" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    echo "[selftest] F1.full_json: invalid JSON output"; fail=1
  fi
  if ! emit_json "$fixture2" "" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    echo "[selftest] F2.full_json: invalid JSON output"; fail=1
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
      # DP-033 D8: key-based lookup with active→complete fallback
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
  # Lookup order: active → complete fallback
  active_path="${tasks_dir_abs}/${task_key}.md"
  complete_path="${tasks_dir_abs}/complete/${task_key}.md"
  if [[ -f "$active_path" ]]; then
    file="$active_path"
  elif [[ -f "$complete_path" ]]; then
    file="$complete_path"
  else
    echo "error: broken ref — task key '${task_key}' not found in ${tasks_dir_abs}/ or ${tasks_dir_abs}/complete/" >&2
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
