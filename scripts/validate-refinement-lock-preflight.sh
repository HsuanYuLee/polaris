#!/usr/bin/env bash
# Purpose: Refinement LOCK-time breakdown-ready preflight (DP-262 T4, DP-296 T3,
#          DP-316 T2, DP-274 D4, DP-369 T2).
#          Reads refinement.json canonical tasks[], FULL-DERIVES the REAL task.md
#          per task via derive-task-md-from-refinement-json.sh, and runs the real
#          validate-breakdown-ready.sh against each derived task.md. A task whose
#          declared deliverable shape would fail breakdown readiness (e.g. an
#          implementation task that plans a specs-only deliverable, or a runtime
#          task whose env_bootstrap is prose) makes the preflight fail-stop
#          (exit 2), naming the offending task. A refinement.json that is missing
#          required per-task body fields makes the derive bridge fail-loud, which
#          the preflight surfaces as a fail-stop (an incomplete spec must not pass
#          LOCK).
# Inputs:  <refinement.json path | source-container dir> (positional)
#          --self-test : run the embedded smoke test
# Outputs: stdout PASS line; exit 0 PASS, exit 1 usage/IO error,
#          exit 2 contract violation (one or more tasks not ready)
# Side effects: writes/removes a tmpdir of derived task.md files
#
# Design (DP-262 AC5 / AC-NEG3 / AC7; DP-296 AC2 / AC-NEG1; DP-369 AC-NF1):
# - The preflight does NOT reimplement task.md synthesis, the specs-only /
#   task_shape carve-out classification, the Level projection, or the
#   env_bootstrap executability judgment. It DERIVES the real task.md per task
#   via the single canonical writer (derive-task-md-from-refinement-json.sh) and
#   delegates the verdict to validate-breakdown-ready.sh — the single source of
#   truth shared with breakdown / engineering (AC7 / AC-NF1). There is no second
#   synthesis path and no hardcoded-clean placeholder body.
# - DP-369 T2: replacing the previous hardcoded-clean placeholder (which shadowed
#   the real env_bootstrap / verify_command / allowed_files with synthetic values)
#   means real illegitimate per-task content is now validated AT LOCK time. The
#   derive bridge owns the Level projection (DP-316 single source), the per-task
#   body field requirement (fail-loud on incomplete specs), and task_shape
#   passthrough (DP-296); the preflight only orchestrates derive -> validate.
# - DP-274 D4: the source-level delivery-unit shape gate is delegated to the same
#   validate-breakdown-ready.sh in directory mode (no second classifier).
# - Missing tasks[] (or non-array) is a no-op PASS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_BREAKDOWN_READY="$SCRIPT_DIR/validate-breakdown-ready.sh"
# DP-369 T2: derive the REAL task.md per planned task through the single canonical
# writer. The derive bridge owns the Level projection (DP-316 T1 single source),
# the env_bootstrap executability gate (via validate-task-md.sh, DP-369 T1), the
# per-task body field requirement (fail-loud on incomplete specs), and task_shape
# passthrough (DP-296) — the preflight never copies any of those judgments.
DERIVE_TASK_MD="$SCRIPT_DIR/derive-task-md-from-refinement-json.sh"

usage() {
  cat >&2 <<'EOF'
usage: validate-refinement-lock-preflight.sh <refinement.json|source-container>
       validate-refinement-lock-preflight.sh --self-test

Reads refinement.json canonical tasks[], FULL-DERIVES one real task.md per task
via derive-task-md-from-refinement-json.sh, and runs validate-breakdown-ready.sh
against each. Fails (exit 2) when any task's declared content would not pass
breakdown readiness (deliverable shape, env_bootstrap executability, Level
projection), or when the refinement.json is missing required per-task body
fields (derive fail-loud), naming the offending task.
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
  if [[ ! -f "$DERIVE_TASK_MD" ]]; then
    echo "validate-refinement-lock-preflight: missing derive bridge at $DERIVE_TASK_MD" >&2
    return 1
  fi

  # Extract the canonical source id once; the derive bridge's id contract requires
  # the full-form task id (DP-NNN-Tn / EPIC-NNN-Tn), composed below as
  # ${source_id}-${task_id}. Default keeps the embedded smoke / legacy fixtures
  # working when source.id is absent.
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
  # set to a writable directory, keep the derived task.md files there (and do not
  # auto-remove) so the selftest can inspect the derived bodies. Unset (the
  # production path) uses an auto-removed mktemp dir.
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
  # summary-language guard activates against the derived task.md files. The guard
  # walks up from each task.md for a workspace-config.yaml `language:`; without it
  # the guard would silently skip and English-only planned titles would slip
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

  # DP-296 T3: extract the canonical tasks[] short work-item ids (T1/V1), one per
  # line. task_shape / tracked_deliverable_hint / Level / env_bootstrap are NOT
  # parsed here anymore — the derive bridge reads them straight from the canonical
  # tasks[] entry (DP-369 T2, no second parse). Missing tasks[] (or non-array)
  # yields no rows -> no-op PASS.
  local task_ids
  task_ids="$(python3 - "$refinement_json" <<'PY'
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
    if "\n" in task_id:
        print(f"BADFIELD\t{idx}", file=sys.stderr)
        raise SystemExit(3)
    print(task_id)
PY
)" || {
    echo "validate-refinement-lock-preflight: failed to parse tasks[] in $refinement_json" >&2
    return 1
  }

  if [[ -z "$task_ids" ]]; then
    echo "validate-refinement-lock-preflight.sh PASS - no tasks[] to preflight ($refinement_json)"
    return 0
  fi

  local failures=()
  local task_id derived_dir derive_err err
  while IFS= read -r task_id; do
    [[ -z "$task_id" ]] && continue

    # DP-369 T2: derive the REAL task.md from the canonical tasks[] entry. The
    # derive bridge fail-louds (non-zero) when the refinement.json is missing
    # required per-task body fields, declares an unknown Level, or otherwise
    # produces a non-constructible task.md — all of which mean the spec must not
    # pass LOCK. Folder-native ${task_id}/index.md so the directory-mode
    # delivery-unit shape gate below can scan ${tmpdir}.
    derived_dir="$tmpdir/$task_id"
    mkdir -p "$derived_dir"
    derive_err="$tmpdir/$task_id.derive.err"
    if ! bash "$DERIVE_TASK_MD" --refinement-json "$refinement_json" \
        --task-id "${source_id}-${task_id}" >"$derived_dir/index.md" 2>"$derive_err"; then
      local derive_detail
      derive_detail="$(head -n 3 "$derive_err" | tr '\n' ' ')"
      failures+=("task '$task_id' could not be derived (refinement.json incomplete or invalid for full-derive): $derive_detail")
      continue
    fi

    err="$tmpdir/$task_id.err"
    if ! bash "$VALIDATE_BREAKDOWN_READY" "$derived_dir/index.md" >/dev/null 2>"$err"; then
      local detail
      detail="$(head -n 3 "$err" | tr '\n' ' ')"
      failures+=("task '$task_id' not breakdown-ready: $detail")
    fi
  done <<<"$task_ids"

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
  # validate-breakdown-ready.sh. The derived task.md files live as folder-native
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

  # DP-369 T2: the embedded smoke uses FULL canonical tasks[] (id + title + scope +
  # allowed_files + verification with behavior_contract + test_environment +
  # estimate_points) so the derive bridge can produce a real task.md. The legacy
  # minimal-field fixtures (only task_shape / hint) are no longer derivable and
  # would fail-loud — that is the intended target state, asserted in the wrapper
  # selftest's incomplete-task case.
  # Legal: confirmation/audit specs-only + implementation tracked -> PASS.
  cat >"$tmpdir/ok.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-262", "base_branch": "feat/DP-262" },
  "acceptance_criteria": [ { "id": "AC1", "text": "lock preflight smoke ok" } ],
  "modules": [],
  "tasks": [
    {
      "id": "T1",
      "kind": "confirmation",
      "title": "lock preflight smoke confirmation specs-only",
      "scope": "lock preflight smoke confirmation specs-only carve-out",
      "task_shape": "confirmation",
      "tracked_deliverable_hint": "specs_only",
      "allowed_files": ["docs-manager/src/content/docs/specs/design-plans/DP-262-example/index.md"],
      "modules": [],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "echo PASS",
        "behavior_contract": { "applies": false, "reason": "framework smoke fixture；無 runtime / UI 行為變更" },
        "test_environment": { "level": "static" },
        "verify_command": "echo PASS",
        "references": []
      }
    },
    {
      "id": "T2",
      "kind": "implementation",
      "title": "lock preflight smoke implementation tracked",
      "scope": "lock preflight smoke implementation tracked deliverable",
      "task_shape": "implementation",
      "tracked_deliverable_hint": "tracked",
      "allowed_files": ["scripts/lock-preflight-smoke-T2.sh"],
      "modules": ["scripts/lock-preflight-smoke-T2.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "echo PASS",
        "behavior_contract": { "applies": false, "reason": "framework smoke fixture；無 runtime / UI 行為變更" },
        "test_environment": { "level": "static" },
        "verify_command": "echo PASS",
        "references": []
      }
    }
  ]
}
JSON
  if ! bash "${BASH_SOURCE[0]}" "$tmpdir/ok.json" >/dev/null 2>"$tmpdir/ok.err"; then
    echo "self-test failed: legal tasks[] did not pass" >&2
    cat "$tmpdir/ok.err" >&2
    return 1
  fi

  # Illegal: a runtime implementation task whose Env bootstrap command is PROSE
  # (no parseable command) -> exit 2. Under full-derive the REAL env_bootstrap
  # value lands in the task.md and validate-task-md.sh's executability gate
  # (DP-369 T1) rejects it. This replaces the old "implementation specs-only"
  # fixture: full-derive injects a .changeset for every implementation T-task, so
  # an implementation task is never purely specs-only in a changeset repo — that
  # old synthetic scenario was an artifact of the removed placeholder, not a
  # shape full-derive produces (DP-369 finding).
  cat >"$tmpdir/bad.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-369", "base_branch": "feat/DP-369" },
  "acceptance_criteria": [ { "id": "AC1", "text": "lock preflight smoke bad" } ],
  "modules": [],
  "tasks": [
    {
      "id": "T1",
      "kind": "implementation",
      "title": "lock preflight smoke runtime task prose env bootstrap",
      "scope": "runtime task whose env_bootstrap is prose, not a command",
      "task_shape": "implementation",
      "tracked_deliverable_hint": "tracked",
      "allowed_files": ["scripts/lock-preflight-smoke-bad.sh"],
      "modules": ["scripts/lock-preflight-smoke-bad.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "curl -fsS http://127.0.0.1:9999/lock-preflight-smoke-probe",
        "behavior_contract": { "applies": false, "reason": "framework smoke fixture；無 runtime / UI 行為變更" },
        "test_environment": { "level": "runtime", "runtime_verify_target": "http://127.0.0.1:9999/lock-preflight-smoke-probe", "env_bootstrap_command": "啟動 dev.kkday.com 三層 stack 並把 dev server 釘在 3001" },
        "verify_command": "curl -fsS http://127.0.0.1:9999/lock-preflight-smoke-probe",
        "references": []
      }
    }
  ]
}
JSON
  set +e
  bash "${BASH_SOURCE[0]}" "$tmpdir/bad.json" >/dev/null 2>"$tmpdir/bad.err"
  local rc=$?
  set -e
  if [[ "$rc" -ne 2 ]]; then
    echo "self-test failed: runtime task with prose env_bootstrap expected exit 2, got $rc" >&2
    cat "$tmpdir/bad.err" >&2
    return 1
  fi

  # Missing tasks[] -> no-op PASS.
  cat >"$tmpdir/empty.json" <<'JSON'
{ "source": { "type": "dp", "id": "DP-262", "base_branch": "feat/DP-262" } }
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
