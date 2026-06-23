#!/usr/bin/env bash
# Purpose: Selftest for validate-task-md.sh frontmatter-aware section parsing (DP-345 AC1).
# Inputs:  none (builds task.md fixtures + canonical snapshot in a temp dir)
# Outputs: TAP-ish lines to stdout; exit 0 on PASS, 1 on FAIL
# Side effects: writes/removes a temp dir only
#
# Driving incident: DP-344-T1's frontmatter `description` literally contained
# `## Allowed Files` / `## 改動範圍`. The old naive `text.find("## heading")`
# parsers in validate-task-md.sh matched the frontmatter literal instead of the
# real body section, parsing 0 Allowed Files and an empty create_set.
#
# This selftest asserts all THREE inline parsers in validate-task-md.sh are now
# frontmatter-aware (strip `---` block, then line-anchor `^## `):
#   1. snapshot `section()`/`allowed_files()` — Allowed Files parsed as 7 (not 0);
#      validate-task-md.sh --snapshot agrees with the canonical parse-task-md.sh.
#   2. `_section_text()` create_set — `## 改動範圍` action=create path resolved, so
#      a Verify Command referencing a to-be-created script is NOT a false error.
#   3. Required Tools `section()` — real body table parsed despite a frontmatter
#      literal `## Required Tools`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/validate-task-md.sh"
PARSER="$REPO_ROOT/scripts/parse-task-md.sh"

TOTAL=0
PASS=0
fail() { printf 'not ok %s\n' "$1" >&2; }
ok() { printf 'ok %s\n' "$1"; }
assert_eq() {
  local label="$1" got="$2" want="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then PASS=$((PASS + 1)); ok "$label"; else fail "$label: got '$got' want '$want'"; fi
}
assert_ok() {  # label, exit-code
  local label="$1" rc="$2"
  TOTAL=$((TOTAL + 1))
  if [[ "$rc" == "0" ]]; then PASS=$((PASS + 1)); ok "$label"; else fail "$label: exit $rc"; fi
}

tmpdir="$(mktemp -d -t validate-task-md-frontmatter.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# DP-344-T1 collision shape: frontmatter description literally contains the
# `## Allowed Files` and `## 改動範圍` headings. 7 Allowed Files entries; the
# Verify Command references a to-be-created script that appears in 改動範圍.
task="$tmpdir/index.md"
cat > "$task" <<'MD'
---
title: "T1: DP-344-T1 shape (5 pt)"
description: "This task edits the ## Allowed Files section and the ## 改動範圍 table and the ## Required Tools list. The naive parser bug咬到 frontmatter 字面 ## 標題 解出 0 筆。"
draft: true
sidebar:
  hidden: true
status: IN_PROGRESS
task_kind: T
task_shape: implementation
verification:
  behavior_contract:
    applies: false
    reason: "static framework gate"
depends_on: []
---

# T1: DP-344-T1 shape (5 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | feat/DP-999 |
| Branch chain | feat/DP-999 -> task/DP-999-T1-shape |
| Task branch | task/DP-999-T1-shape |
| Depends on | N/A |
| References to load | - task-md-schema |

## 目標

收斂 frontmatter section parser。

## 改動範圍

| 檔案 | 動作 | 變更摘要 |
|------|------|----------|
| `scripts/one.sh` | modify | edit one |
| `scripts/two.sh` | modify | edit two |
| `scripts/selftests/new-gate-selftest.sh` | create | new selftest |

## Allowed Files

- `scripts/one.sh`
- `scripts/two.sh`
- `scripts/three.sh`
- `scripts/four.sh`
- `scripts/five.sh`
- `scripts/six.sh`
- `scripts/selftests/new-gate-selftest.sh`

## Required Tools

| Tool | Owner | install_authority | check_command | install_command | runtime_profile | goes_to_mise | handoff_hint |
|------|-------|-------------------|---------------|-----------------|-----------------|--------------|--------------|
| `jq` | framework | root_mise | `jq --version` | `mise install` | core | true | run mise install |

## 估點理由

5 pt — 三處 inline parser 收斂。

## 測試計畫（code-level）

1. 擴張 selftest。
2. 收斂 parser。

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
bash scripts/selftests/new-gate-selftest.sh
```
MD

# ---- Surface 1: snapshot section()/allowed_files() parse 7, not 0 ----------
# Build the planner-owned baseline snapshot using the CANONICAL parser
# (parse-task-md.sh) — exactly what engineering-branch-setup.sh does.
snapshot="$tmpdir/snapshot.json"
python3 - "$PARSER" "$task" "$snapshot" <<'PY'
import hashlib, json, subprocess, sys
parser, task_md, out = sys.argv[1:4]
proc = subprocess.run(["bash", parser, task_md, "--no-resolve"],
                      text=True, stdout=subprocess.PIPE, check=True)
data = json.loads(proc.stdout)
def digest(value):
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()
planner = {
    "verify_command": data.get("verify_command") or "",
    "depends_on": (data.get("frontmatter") or {}).get("depends_on") or [],
    "base_branch": (data.get("operational_context") or {}).get("base_branch") or "",
    "allowed_files": data.get("allowed_files") or [],
}
# Sanity: canonical parser must see 7 allowed files (proves the fixture shape).
assert len(planner["allowed_files"]) == 7, planner["allowed_files"]
snapshot = {
    "schema_version": 1, "writer": "selftest", "task_id": "DP-999-T1",
    "task_md": task_md, "head_sha": "deadbeef", "planner_owned": planner,
    "hashes": {
        "verify_command_sha256": digest(planner["verify_command"]),
        "depends_on_sha256": digest(planner["depends_on"]),
        "base_branch_sha256": digest(planner["base_branch"]),
        "allowed_files_sha256": digest(planner["allowed_files"]),
    },
}
open(out, "w", encoding="utf-8").write(json.dumps(snapshot, indent=2) + "\n")
PY

# If validate-task-md.sh's own section()/allowed_files() parse the same 7 entries,
# the hashes agree and --snapshot exits 0. With the old naive find() bug it would
# parse 0 entries → hash mismatch → exit 1.
set +e
bash "$VALIDATOR" --snapshot "$snapshot" "$task" >/dev/null 2>"$tmpdir/snap.err"
snap_rc=$?
set -e
assert_ok "S1.snapshot_allowed_files_agree (7 entries, not 0)" "$snap_rc"

# Negative control: a snapshot built from a DELIBERATELY wrong (6-entry) list
# must be detected as mismatch (proves the comparator is actually live).
wrong_snapshot="$tmpdir/wrong.json"
python3 - "$snapshot" "$wrong_snapshot" <<'PY'
import hashlib, json, sys
src, out = sys.argv[1:3]
snap = json.load(open(src, encoding="utf-8"))
def digest(value):
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()
snap["hashes"]["allowed_files_sha256"] = digest(["only", "six", "entries", "not", "seven", "here"])
open(out, "w", encoding="utf-8").write(json.dumps(snap, indent=2) + "\n")
PY
set +e
bash "$VALIDATOR" --snapshot "$wrong_snapshot" "$task" >/dev/null 2>"$tmpdir/wrong.err"
wrong_rc=$?
set -e
TOTAL=$((TOTAL + 1))
if [[ "$wrong_rc" != "0" ]] && grep -q "Allowed Files" "$tmpdir/wrong.err"; then
  PASS=$((PASS + 1)); ok "S1.negative_control_detects_mismatch"
else
  fail "S1.negative_control_detects_mismatch: rc=$wrong_rc"
fi

# ---- Surfaces 2 & 3: full single-file validation, no spurious errors --------
# Full validation exercises _section_text() create_set (Verify Command references
# scripts/selftests/new-gate-selftest.sh which is action=create in 改動範圍, so it
# must NOT be flagged as a missing-script error) and Required Tools section().
# With the naive bug, the frontmatter literals would empty those sections and
# produce a false missing-script error.
set +e
bash "$VALIDATOR" "$task" >/dev/null 2>"$tmpdir/full.err"
full_rc=$?
set -e
assert_ok "S2S3.full_validation_passes (create_set + required_tools frontmatter-aware)" "$full_rc"

TOTAL=$((TOTAL + 1))
if ! grep -qi "missing repo-local script" "$tmpdir/full.err"; then
  PASS=$((PASS + 1)); ok "S2.no_false_missing_script (create_set resolved)"
else
  fail "S2.no_false_missing_script: $(cat "$tmpdir/full.err")"
fi

echo "---"
echo "$PASS/$TOTAL passed"
[[ "$PASS" -eq "$TOTAL" ]] || { echo "[selftest] FAIL"; exit 1; }
echo "[selftest] PASS"
