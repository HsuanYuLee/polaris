#!/usr/bin/env bash
# Purpose: Refinement LOCK-time breakdown-ready preflight (DP-262 T4, DP-296 T3).
#          Reads refinement.json canonical tasks[], synthesizes an ephemeral
#          placeholder task.md per task, and runs the real
#          validate-breakdown-ready.sh against each. A task whose declared
#          deliverable shape would fail breakdown readiness (e.g. an
#          implementation task that plans a specs-only deliverable) makes the
#          preflight fail-stop (exit 2), naming the offending task.
# Inputs:  <refinement.json path | source-container dir> (positional)
#          --self-test : run the embedded smoke test
# Outputs: stdout PASS line; exit 0 PASS, exit 1 usage/IO error,
#          exit 2 contract violation (one or more tasks not ready)
# Side effects: writes/removes a tmpdir of synthesized placeholder task.md files
#
# Design (DP-262 AC5 / AC-NEG3 / AC7; DP-296 AC2 / AC-NEG1):
# - The preflight does NOT reimplement the specs-only / task_shape carve-out
#   classification. It composes a minimal schema-valid placeholder task.md per
#   task and delegates the verdict to validate-breakdown-ready.sh, the single
#   source of truth shared with breakdown / engineering (AC7).
# - DP-296 T3: task_shape / tracked_deliverable_hint are read from the canonical
#   first-class tasks[] fields (the legacy top-level shape array read is removed,
#   AC2 / AC-NEG1). tracked_deliverable_hint drives the placeholder Allowed Files
#   shape: "specs_only" yields a specs-only entry, "tracked" (default) yields a
#   tracked entry. An implementation task with a specs_only hint therefore fails
#   validate-breakdown-ready exactly as a real implementation task would
#   (AC-NEG3), with no preflight-side relaxation.
# - Missing tasks[] (or non-array) is a no-op PASS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_BREAKDOWN_READY="$SCRIPT_DIR/validate-breakdown-ready.sh"
# DP-316 T2: the projection from refinement test_environment.level onto the
# task.md Level enum lives in exactly one place — derive-task-md-from-refinement-json.sh
# (DP-316 T1, AC4 single-source). The preflight reuses it by invoking the derive
# bridge, never by copying a second mapping table.
DERIVE_TASK_MD="$SCRIPT_DIR/derive-task-md-from-refinement-json.sh"

usage() {
  cat >&2 <<'EOF'
usage: validate-refinement-lock-preflight.sh <refinement.json|source-container>
       validate-refinement-lock-preflight.sh --self-test

Reads refinement.json canonical tasks[], synthesizes one placeholder task.md per
task, and runs validate-breakdown-ready.sh against each. Fails (exit 2)
when any task's declared deliverable shape would not pass breakdown
readiness, naming the offending task.
EOF
}

# resolve_refinement_json <arg> -> echoes the refinement.json path
# Accepts either a refinement.json file or a source-container directory.
resolve_refinement_json() {
  local arg="$1"
  if [[ -d "$arg" ]]; then
    printf '%s\n' "$arg/refinement.json"
    return 0
  fi
  printf '%s\n' "$arg"
}

# project_planned_level <source_id> <task_id> <raw_level>
# DP-316 T2 (AC3 / AC4): project a planned task's declared refinement
# test_environment.level onto the task.md Level enum through the SINGLE canonical
# projection owned by derive-task-md-from-refinement-json.sh. We synthesize a
# minimal one-task refinement.json carrying the raw level and run the real derive
# bridge, then read back the `- **Level**:` line it emits. The projected value
# therefore equals what a real derive would produce for the same input (parity by
# construction), and no second mapping table lives in this file. An unknown level
# makes the derive bridge fail-loud (exit non-zero); we propagate that as a
# failure so the preflight refuses to silently fall back to static (AC-NEG1).
# Echoes the projected Level on success; returns non-zero on projection failure.
project_planned_level() {
  local source_id="$1"
  local task_id="$2"
  local raw_level="$3"

  if [[ ! -f "$DERIVE_TASK_MD" ]]; then
    echo "validate-refinement-lock-preflight: missing derive bridge at $DERIVE_TASK_MD" >&2
    return 1
  fi

  local proj_dir proj_json derived projected
  proj_dir="$(mktemp -d -t validate-refinement-lock-preflight-level.XXXXXX)"
  proj_json="$proj_dir/refinement.json"

  # Minimal canonical one-task refinement.json the derive bridge accepts. The
  # derive bridge's id contract requires the short id to be Tn/Vn form, so the
  # probe task is T1 and we invoke it as the full-form ${source_id}-T1. This is a
  # throwaway projection probe — the real planned task id is irrelevant here; only
  # the level mapping output matters.
  cat >"$proj_json" <<JSON
{
  "source": { "type": "dp", "id": "${source_id}" },
  "acceptance_criteria": [ { "id": "AC1", "text": "lock preflight level projection" } ],
  "tasks": [
    {
      "id": "T1",
      "kind": "T",
      "title": "lock preflight level projection",
      "scope": "project ${raw_level} onto the task.md Level enum",
      "task_shape": "implementation",
      "tracked_deliverable_hint": "tracked",
      "allowed_files": ["scripts/lock-preflight-level-probe.sh"],
      "modules": ["scripts/lock-preflight-level-probe.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "lock preflight level projection",
        "behavior_contract": { "applies": false, "reason": "framework lock preflight level projection" },
        "test_environment": { "level": "${raw_level}" },
        "verify_command": "echo PASS",
        "references": []
      }
    }
  ]
}
JSON

  if ! derived="$(bash "$DERIVE_TASK_MD" --refinement-json "$proj_json" \
      --task-id "${source_id}-T1" 2>/dev/null)"; then
    rm -rf "$proj_dir"
    return 1
  fi
  rm -rf "$proj_dir"

  projected="$(printf '%s\n' "$derived" \
    | grep -E '^- \*\*Level\*\*:' | head -n 1 \
    | sed -E 's/^- \*\*Level\*\*:[[:space:]]*//')"
  if [[ -z "$projected" ]]; then
    return 1
  fi
  printf '%s\n' "$projected"
}

# write_placeholder_task <dir> <task_id> <task_shape> <deliverable_hint> <title> <level>
# Synthesizes a folder-native T{n}/index.md placeholder that satisfies
# validate-task-md.sh's minimum T-task schema, so that validate-breakdown-ready
# evaluates the real task_shape / Allowed Files contract rather than tripping on
# the placeholder itself (DP-262 EC2). The <level> arg is the already-projected
# task.md Level (DP-316 T2); when empty the placeholder keeps the static default
# (backward compat for tasks that declare no test_environment.level).
write_placeholder_task() {
  local dir="$1"
  local task_id="$2"
  local task_shape="$3"
  local hint="$4"
  local title="${5:-}"
  local level="${6:-static}"

  local shape_fm=""
  if [[ -n "$task_shape" ]]; then
    shape_fm="task_shape: $task_shape"
  fi

  # DP-294 T7 / AC9: the summary line carries the real planned title so the
  # existing validate-task-md.sh summary-language guard evaluates it. A title-less
  # planned task falls back to a CJK summary, which keeps the guard a no-op (there
  # is no asserted title to language-check). No second classifier lives here — the
  # verdict comes from validate-task-md.sh via validate-breakdown-ready.sh.
  local summary_line
  if [[ -n "$title" ]]; then
    summary_line="$title"
  else
    summary_line="LOCK 前置佔位"
  fi

  # Choose a placeholder Allowed Files / owning file per declared deliverable
  # hint. "specs_only" exercises the specs-only carve-out path; anything else
  # (default "tracked") declares a tracked file so an implementation task can
  # legitimately pass.
  local allowed_entry owning_file
  if [[ "$hint" == "specs_only" ]]; then
    allowed_entry="docs-manager/src/content/docs/specs/design-plans/DP-262-example/index.md"
    owning_file="docs-manager/src/content/docs/specs/design-plans/DP-262-example/index.md"
  else
    allowed_entry="scripts/${task_id}-placeholder.sh"
    owning_file="scripts/${task_id}-placeholder.sh"
  fi

  # DP-316 T2: keep the Test Environment block self-consistent for the projected
  # Level so validate-task-md's Level-specific cross-field rules evaluate the
  # placeholder as a real task.md would. A Level=runtime task.md requires a
  # non-N/A http Runtime verify target, a non-N/A Env bootstrap command, and a
  # Verify Command fence whose live URL host matches the target. Non-runtime
  # levels (static / build) keep the N/A defaults.
  # The probe host is a non-8080 local port so it is treated as a generic runtime
  # target, not the docs-manager viewer (which would additionally require a
  # /docs-manager/ path). Target host and Verify Command host match (DP-023).
  local te_runtime_target="N/A" te_bootstrap="N/A" verify_block="echo PASS"
  if [[ "$level" == "runtime" ]]; then
    te_runtime_target="http://127.0.0.1:9999/lock-preflight-placeholder"
    te_bootstrap="echo bootstrap"
    verify_block="curl -fsS http://127.0.0.1:9999/lock-preflight-placeholder"
  fi

  mkdir -p "$dir"
  cat >"$dir/index.md" <<EOF
---
title: "Work Order - ${task_id}: refinement LOCK preflight placeholder"
description: "Ephemeral placeholder synthesized by validate-refinement-lock-preflight."
status: IN_PROGRESS
task_kind: T
${shape_fm}
verification:
  behavior_contract:
    applies: false
    reason: "framework deterministic gate / preflight placeholder; no runtime behavior"
depends_on: []
---

# ${task_id}: ${summary_line} (1 pt)

> Source: DP-262 | Task: DP-262-${task_id} | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-262 |
| Task ID | DP-262-${task_id} |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-262-${task_id}-placeholder |
| Task branch | task/DP-262-${task_id}-placeholder |
| Depends on | N/A |
| References to load | - refinement.json tasks |

## Verification Handoff

AC 驗證不在本 task 範圍。

## 目標

LOCK preflight placeholder for planned task ${task_id}.

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| ${owning_file} | modify | planned deliverable |

## Allowed Files

- ${allowed_entry}

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| planned deliverable proof | ${owning_file} | framework deterministic gate | bash scripts/validate-refinement-lock-preflight.sh fixture |

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | Allowed Files 全為 path/glob | refinement |
| test | yes | preflight pass | refinement |
| verify | yes | preflight pass | refinement |
| ci-local | no | N/A - no repo CI required | refinement |

## 估點理由

1 pt - LOCK preflight placeholder。

## 測試計畫（code-level）

- preflight placeholder。

## Test Command

\`\`\`bash
echo PASS
\`\`\`

## Test Environment

- **Level**: ${level}
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: ${te_runtime_target}
- **Env bootstrap command**: ${te_bootstrap}

## Verify Command

\`\`\`bash
${verify_block}
\`\`\`
EOF
}

run_preflight() {
  local refinement_json
  refinement_json="$(resolve_refinement_json "$1")"

  if [[ ! -f "$refinement_json" ]]; then
    echo "validate-refinement-lock-preflight: refinement.json not found: $refinement_json" >&2
    return 1
  fi
  if [[ ! -x "$VALIDATE_BREAKDOWN_READY" && ! -f "$VALIDATE_BREAKDOWN_READY" ]]; then
    echo "validate-refinement-lock-preflight: missing validate-breakdown-ready.sh at $VALIDATE_BREAKDOWN_READY" >&2
    return 1
  fi

  # Extract the canonical source id once; the level projection synthesizes a
  # one-task refinement.json whose source id must match the derive bridge's
  # full-form task id contract (DP-NNN-Tn). Default keeps the embedded smoke /
  # legacy fixtures working when source.id is absent.
  local source_id
  source_id="$(python3 - "$refinement_json" <<'PY'
import json
import sys
from pathlib import Path

try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    print("DP-262")
    raise SystemExit(0)
print(str((data.get("source") or {}).get("id") or "DP-262").strip() or "DP-262")
PY
)"

  # DP-316 T2 test-observability seam: when POLARIS_LOCK_PREFLIGHT_KEEP_TMPDIR is
  # set to a writable directory, keep the synthesized placeholders there (and do
  # not auto-remove) so the selftest can read the placeholder Level and assert
  # projection parity. Unset (the production path) uses an auto-removed mktemp dir.
  local tmpdir keep_tmpdir="${POLARIS_LOCK_PREFLIGHT_KEEP_TMPDIR:-}"
  if [[ -n "$keep_tmpdir" ]]; then
    mkdir -p "$keep_tmpdir"
    tmpdir="$keep_tmpdir"
  else
    tmpdir="$(mktemp -d -t validate-refinement-lock-preflight.XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" RETURN
  fi

  # DP-294 T7 / AC9: synthesize a hermetic mini-workspace so validate-task-md.sh's
  # summary-language guard activates against the placeholders. The guard walks up
  # from each placeholder index.md for a workspace-config.yaml `language:`; without
  # it the guard would silently skip and English-only planned titles would slip
  # through LOCK. Mirror the LIVE workspace policy (not a hardcode) so a non-zh-TW
  # source repo keeps its own contract under source parity. Reading the policy
  # scalar is not a second language classifier — the CJK verdict stays in
  # validate-task-md.sh.
  # Source the live workspace language policy by walking up from the source
  # container (same resolution semantics as validate-task-md), then copy only the
  # `language:` line into the mini-workspace so validate-task-md reads the real
  # policy value verbatim. No second parser, no other config fields that could
  # perturb validate-breakdown-ready's directory scan. No config found -> nothing
  # written -> guard skips (correct for a no-language workspace).
  local probe live_config=""
  probe="$(cd "$(dirname "$refinement_json")" && pwd)"
  while [[ -n "$probe" && "$probe" != "/" ]]; do
    if [[ -f "$probe/workspace-config.yaml" ]]; then
      live_config="$probe/workspace-config.yaml"
      break
    fi
    probe="$(dirname "$probe")"
  done
  if [[ -n "$live_config" ]]; then
    grep -E '^[[:space:]]*language[[:space:]]*:' "$live_config" >"$tmpdir/workspace-config.yaml" 2>/dev/null || true
  fi

  # DP-296 T3 / DP-316 T2: Extract canonical tasks[] as
  # <task_id><US><task_shape><US><hint><US><title><US><level> rows, where <US> is
  # the ASCII unit separator (\x1f). task_shape and tracked_deliverable_hint are
  # first-class tasks[] fields (canonical home, migrated from the removed legacy
  # top-level shape array, AC2 / AC-NEG1). level is the raw declared
  # verification.test_environment.level (DP-316 T2), passed to the single
  # canonical projection before it lands in the placeholder. A non-whitespace
  # separator is required so `read` preserves an empty task_shape / level field
  # (a missing field defaults downstream) instead of collapsing consecutive
  # whitespace delimiters.
  # task_id is the short work-item form (T1/V1) derived from tasks[].id, which may
  # be short (T1) or full (DP-NNN-Tn) form per the canonical schema.
  # Missing tasks[] (or non-array) yields no rows -> no-op PASS.
  local rows
  rows="$(python3 - "$refinement_json" <<'PY'
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except (json.JSONDecodeError, OSError) as exc:
    print(f"PARSE_ERROR\t{exc}", file=sys.stderr)
    raise SystemExit(3)


def short_work_item_id(value, fallback):
    """Normalize a tasks[].id (short T1/V1 or full DP-NNN-Tn) to its short form."""
    value = str(value or "").strip()
    if re.fullmatch(r"[TV][0-9]+[a-z]?", value):
        return value
    m = re.fullmatch(r"[A-Z][A-Z0-9]*-[0-9]+-([TV][0-9]+[a-z]?)", value)
    if m:
        return m.group(1)
    return fallback


tasks = data.get("tasks")
if not isinstance(tasks, list):
    raise SystemExit(0)

for idx, entry in enumerate(tasks):
    if not isinstance(entry, dict):
        print(f"BADENTRY\t{idx}", file=sys.stderr)
        raise SystemExit(3)
    task_id = short_work_item_id(entry.get("id"), f"PT{idx + 1}")
    task_shape = str(entry.get("task_shape") or "").strip()
    hint = str(entry.get("tracked_deliverable_hint") or "tracked").strip() or "tracked"
    # DP-294 T7 / AC9: carry the real planned title so the placeholder summary
    # line triggers the validate-task-md summary-language guard per task. May be
    # empty when title-less tasks fall back to a CJK summary downstream so the
    # guard stays a no-op (backward compat).
    title = str(entry.get("title") or "").strip()
    # DP-316 T2: the raw declared test_environment.level (test-pyramid value). It
    # is projected onto the task.md Level enum through the single canonical
    # projection before reaching the placeholder. Empty when the task declares no
    # test_environment.level (placeholder keeps the static default downstream).
    level = str(
        ((entry.get("verification") or {}).get("test_environment") or {}).get("level")
        or ""
    ).strip()
    # The unit separator / newline would corrupt the row contract; reject early.
    if any("\x1f" in v or "\n" in v for v in (task_id, task_shape, hint, title, level)):
        print(f"BADFIELD\t{idx}", file=sys.stderr)
        raise SystemExit(3)
    print(f"{task_id}\x1f{task_shape}\x1f{hint}\x1f{title}\x1f{level}")
PY
)" || {
    echo "validate-refinement-lock-preflight: failed to parse tasks[] in $refinement_json" >&2
    return 1
  }

  if [[ -z "$rows" ]]; then
    echo "validate-refinement-lock-preflight.sh PASS - no tasks[] to preflight ($refinement_json)"
    return 0
  fi

  local failures=()
  local task_id task_shape hint title raw_level placeholder_dir err
  while IFS=$'\x1f' read -r task_id task_shape hint title raw_level; do
    [[ -z "$task_id" ]] && continue

    # DP-316 T2: project the declared level through the single canonical
    # projection. A declared-but-unknown level fail-louds in the derive bridge;
    # we surface it as a per-task failure (no silent fallback to static, AC-NEG1).
    # A task with no declared level keeps the static placeholder default.
    local projected_level=""
    if [[ -n "$raw_level" ]]; then
      if ! projected_level="$(project_planned_level "$source_id" "$task_id" "$raw_level")"; then
        failures+=("task '$task_id' declares test_environment.level='$raw_level' which is not a projectable level (derive bridge fail-loud); refusing to silently fall back to static")
        continue
      fi
    fi

    placeholder_dir="$tmpdir/$task_id"
    write_placeholder_task "$placeholder_dir" "$task_id" "$task_shape" "$hint" "$title" "$projected_level"
    err="$tmpdir/$task_id.err"
    if ! bash "$VALIDATE_BREAKDOWN_READY" "$placeholder_dir/index.md" >/dev/null 2>"$err"; then
      local detail
      detail="$(head -n 3 "$err" | tr '\n' ' ')"
      failures+=("task '$task_id' (task_shape='${task_shape:-implementation}', deliverable_hint='$hint') not breakdown-ready: $detail")
    fi
  done <<<"$rows"

  if ((${#failures[@]} > 0)); then
    echo "validate-refinement-lock-preflight.sh FAIL - $refinement_json" >&2
    local f
    for f in "${failures[@]}"; do
      echo "  - $f" >&2
    done
    echo "POLARIS_REFINEMENT_LOCK_PREFLIGHT_FAILED:$refinement_json" >&2
    return 2
  fi

  # DP-274 D4: delegate the source-level delivery-unit shape gate to the same
  # validate-breakdown-ready.sh. The synthesized placeholders live as folder-native
  # $tmpdir/T{n}/index.md, so running the validator against $tmpdir (directory mode)
  # exercises the identical research-unit / dispatch-theme-unit detection that
  # breakdown will hit later — LOCK fails-stop here instead of waiting for breakdown.
  # We do NOT reimplement the classifier; we reuse validate-breakdown-ready's own.
  local shape_err shape_rc
  shape_err="$tmpdir/__delivery_unit_shape.err"
  set +e
  bash "$VALIDATE_BREAKDOWN_READY" "$tmpdir" >/dev/null 2>"$shape_err"
  shape_rc=$?
  set -e
  if [[ "$shape_rc" -eq 2 ]]; then
    echo "validate-refinement-lock-preflight.sh FAIL - $refinement_json" >&2
    grep -E 'POLARIS_(RESEARCH_UNIT_NO_IMPLEMENTATION|DISPATCH_THEME_UNIT_NO_IMPLEMENTATION)' "$shape_err" >&2 || cat "$shape_err" >&2
    echo "POLARIS_REFINEMENT_LOCK_PREFLIGHT_FAILED:$refinement_json" >&2
    return 2
  fi

  echo "validate-refinement-lock-preflight.sh PASS - $refinement_json"
  return 0
}

run_self_test() {
  local tmpdir
  tmpdir="$(mktemp -d -t validate-refinement-lock-preflight-smoke.XXXXXX)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  # DP-296 T3: canonical tasks[] fixtures (task_shape / tracked_deliverable_hint
  # are first-class tasks[] fields; the preflight reads them directly).
  # Legal: confirmation/audit specs-only + implementation tracked -> PASS.
  cat >"$tmpdir/ok.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-262" },
  "tasks": [
    { "id": "T1", "task_shape": "confirmation", "tracked_deliverable_hint": "specs_only" },
    { "id": "T2", "task_shape": "audit", "tracked_deliverable_hint": "specs_only" },
    { "id": "T3", "task_shape": "implementation", "tracked_deliverable_hint": "tracked" }
  ]
}
JSON
  if ! bash "${BASH_SOURCE[0]}" "$tmpdir/ok.json" >/dev/null 2>"$tmpdir/ok.err"; then
    echo "self-test failed: legal tasks[] did not pass" >&2
    cat "$tmpdir/ok.err" >&2
    return 1
  fi

  # Illegal: implementation task declares specs-only deliverable -> exit 2.
  cat >"$tmpdir/bad.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-262" },
  "tasks": [
    { "id": "T1", "task_shape": "implementation", "tracked_deliverable_hint": "specs_only" }
  ]
}
JSON
  set +e
  bash "${BASH_SOURCE[0]}" "$tmpdir/bad.json" >/dev/null 2>"$tmpdir/bad.err"
  local rc=$?
  set -e
  if [[ "$rc" -ne 2 ]]; then
    echo "self-test failed: implementation specs-only task expected exit 2, got $rc" >&2
    return 1
  fi

  # Missing tasks[] -> no-op PASS.
  cat >"$tmpdir/empty.json" <<'JSON'
{ "source": { "type": "dp", "id": "DP-262" } }
JSON
  if ! bash "${BASH_SOURCE[0]}" "$tmpdir/empty.json" >/dev/null 2>"$tmpdir/empty.err"; then
    echo "self-test failed: missing tasks[] did not pass" >&2
    cat "$tmpdir/empty.err" >&2
    return 1
  fi

  echo "validate-refinement-lock-preflight self-test PASS"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi
  if [[ "${1:-}" == "--self-test" ]]; then
    run_self_test
    exit $?
  fi
  if [[ $# -ne 1 ]]; then
    usage
    exit 1
  fi
  run_preflight "$1"
  exit $?
}

main "$@"
