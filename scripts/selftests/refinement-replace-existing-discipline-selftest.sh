#!/usr/bin/env bash
# Purpose: Selftest for the DP-417 T9 replace-existing source discipline gate.
#          Exercises (a) the LOCK preflight enumeration gate (AC9/AC-NEG4) — a
#          refinement source marked replaces_existing must enumerate ALL existing
#          sources of the replaced thing with runtime/build-output evidence
#          (source-grep alone is insufficient because build-time / CDN / inline
#          injection paths are invisible to source grep); (b) the LOCK preflight
#          anti-dead-code-port gate (AC11/AC-NEG6) — ported symbols carry
#          usage-check evidence and site-wide-dead symbols (usage_count==0) must be
#          flagged removable, never silently ported (new legacy); (c) a fully-valid
#          replaces_existing source PASSes; (d) AC-N1 a non-replacing source (no
#          field) PASSes unaffected. Also asserts the additive replaces_existing
#          schema shape in validate-refinement-json.sh (well-formed passes,
#          malformed fails) and that both enforcement checks live in the single
#          canonical preflight (no second preflight path).
# Inputs:  none (builds hermetic tmpdir fixtures)
# Outputs: stdout PASS line; exit 0 PASS, exit 1 FAIL
# Side effects: writes/removes a tmpdir

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREFLIGHT="$ROOT_DIR/scripts/validate-refinement-lock-preflight.sh"
JSON_VALIDATOR="$ROOT_DIR/scripts/validate-refinement-json.sh"

tmpdir="$(mktemp -d -t refinement-replace-existing-discipline-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

fail() {
  echo "FAIL: $*"
  exit 1
}

# --- Preflight harness -----------------------------------------------------
LAST_RC=0
run_preflight() {
  local label="$1" fixture="$2"
  set +e
  bash "$PREFLIGHT" "$fixture" >/dev/null 2>"$tmpdir/$label.err"
  LAST_RC=$?
  set -e
}

expect_preflight_pass() {
  local label="$1" fixture="$2"
  run_preflight "$label" "$fixture"
  [[ "$LAST_RC" -eq 0 ]] || { cat "$tmpdir/$label.err"; fail "expected preflight PASS (exit 0) for $label, got $LAST_RC"; }
}

expect_preflight_exit2_contains() {
  local label="$1" fixture="$2" pattern="$3"
  run_preflight "$label" "$fixture"
  [[ "$LAST_RC" -eq 2 ]] || { cat "$tmpdir/$label.err"; fail "expected preflight exit 2 for $label, got $LAST_RC"; }
  grep -q "$pattern" "$tmpdir/$label.err" || { cat "$tmpdir/$label.err"; fail "expected '$pattern' in preflight stderr for $label"; }
}

# ---------------------------------------------------------------------------
# Preflight fixtures. These read the authoritative refinement.json directly and
# fire the source-level replace-existing gate before the task-derive loop, so a
# no-tasks fixture is enough to exercise the gate in isolation.
# ---------------------------------------------------------------------------

# (a) AC9 / AC-NEG4 — replaces_existing marked but existing_sources carry only
# source-grep discovery (no runtime/build-output enumeration) -> fail-closed.
cat >"$tmpdir/enum-grep-only.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-417", "base_branch": "feat/DP-417" },
  "replaces_existing": {
    "replaced": "Bootstrap grid utility classes",
    "existing_sources": [
      { "path_or_channel": "src/styles/grid.scss", "evidence": "source-grep", "evidence_ref": "rg col-md-push src/ -> 0 hits" }
    ]
  }
}
JSON
expect_preflight_exit2_contains "enum-grep-only" "$tmpdir/enum-grep-only.json" \
  "POLARIS_REFINEMENT_REPLACE_EXISTING_ENUMERATION"

# (a2) AC9 — replaces_existing marked but existing_sources empty -> fail-closed.
cat >"$tmpdir/enum-empty.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-417", "base_branch": "feat/DP-417" },
  "replaces_existing": {
    "replaced": "Bootstrap grid utility classes",
    "existing_sources": []
  }
}
JSON
expect_preflight_exit2_contains "enum-empty" "$tmpdir/enum-empty.json" \
  "POLARIS_REFINEMENT_REPLACE_EXISTING_ENUMERATION"

# (b) AC11 / AC-NEG6 — a site-wide dead symbol (usage_count 0) ported with
# disposition=kept (not flagged removable) -> fail-closed (new legacy).
cat >"$tmpdir/dead-port-kept.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-417", "base_branch": "feat/DP-417" },
  "replaces_existing": {
    "replaced": "Bootstrap grid utility classes",
    "existing_sources": [
      { "path_or_channel": "https://cdn.example.com/bootstrap.min.css", "evidence": "cdn", "evidence_ref": "prepareCdnAssets injects bootstrap.min.css at build" },
      { "path_or_channel": "src/styles/grid.scss", "evidence": "build-output", "evidence_ref": "dist/main.css contains .col-md-push after build" }
    ],
    "ported_symbols": [
      { "symbol": "col-md-push", "usage_evidence": "rg '\\.col-md-push' src/ -> 0 hits", "usage_count": 0, "disposition": "kept" }
    ]
  }
}
JSON
expect_preflight_exit2_contains "dead-port-kept" "$tmpdir/dead-port-kept.json" \
  "POLARIS_REFINEMENT_REPLACE_EXISTING_DEAD_PORT"

# (b2) AC11 — a ported symbol with no usage_evidence at all -> fail-closed.
cat >"$tmpdir/port-no-usage-evidence.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-417", "base_branch": "feat/DP-417" },
  "replaces_existing": {
    "replaced": "Bootstrap grid utility classes",
    "existing_sources": [
      { "path_or_channel": "dist/main.css", "evidence": "build-output", "evidence_ref": "build output enumerated" }
    ],
    "ported_symbols": [
      { "symbol": "col-md-6", "usage_count": 42, "disposition": "kept" }
    ]
  }
}
JSON
expect_preflight_exit2_contains "port-no-usage-evidence" "$tmpdir/port-no-usage-evidence.json" \
  "POLARIS_REFINEMENT_REPLACE_EXISTING_DEAD_PORT"

# (c) VALID — replaces_existing with full runtime/build-output enumeration and all
# ported symbols usage-checked (dead one flagged removable, live one kept) -> PASS.
cat >"$tmpdir/valid-replaces.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-417", "base_branch": "feat/DP-417" },
  "replaces_existing": {
    "replaced": "Bootstrap grid utility classes",
    "existing_sources": [
      { "path_or_channel": "https://cdn.example.com/bootstrap.min.css", "evidence": "cdn", "evidence_ref": "prepareCdnAssets injects bootstrap.min.css at build" },
      { "path_or_channel": "dist/main.css", "evidence": "build-output", "evidence_ref": "grep .col-md-6 dist/main.css -> present" },
      { "path_or_channel": "layout.html inline <style>", "evidence": "inline", "evidence_ref": "curl rendered page -> inline col-* block" }
    ],
    "ported_symbols": [
      { "symbol": "col-md-6", "usage_evidence": "rg '\\.col-md-6' src/ -> 42 hits", "usage_count": 42, "disposition": "kept" },
      { "symbol": "col-md-push", "usage_evidence": "rg '\\.col-md-push' src/ -> 0 hits", "usage_count": 0, "disposition": "removable" }
    ]
  }
}
JSON
expect_preflight_pass "valid-replaces" "$tmpdir/valid-replaces.json"

# (d) AC-N1 — a non-replacing source (no replaces_existing field) PASSes
# unaffected: the gate is a strict no-op when the field is absent.
cat >"$tmpdir/non-replacing.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-417", "base_branch": "feat/DP-417" }
}
JSON
expect_preflight_pass "non-replacing" "$tmpdir/non-replacing.json"

# ---------------------------------------------------------------------------
# JSON validator schema shape (additive, validated-when-present). Build a
# hermetic valid dp refinement.json under an /archive/ path (which makes the
# validator skip container/plan_path filesystem-currentness checks), then inject
# a well-formed / malformed replaces_existing and assert the shape verdict.
# ---------------------------------------------------------------------------
jv_dir="$tmpdir/jv"
python3 - "$jv_dir" <<'PY'
import copy
import json
import sys
from pathlib import Path

jv_dir = Path(sys.argv[1])

base = {
    "source": {"type": "dp", "id": "DP-999", "container": "c", "plan_path": "c/plan.md"},
    "version": "1.0",
    "created_at": "2026-07-13T00:00:00Z",
    "schema_version": "1.0",
    "modules": [{"path": "scripts/x.sh", "action": "create"}],
    "acceptance_criteria": [
        {"id": "AC1", "text": "t", "verification": {"method": "unit_test", "detail": "echo"}}
    ],
    "dependencies": [],
    "edge_cases": [],
    "predecessor_audit": [],
    "verification_strategy": {"mode": "per_task_self_verify", "reason": "r", "authority": "a"},
    "tasks": [
        {
            "id": "T1", "kind": "implementation", "title": "t", "scope": "s",
            "modules": ["scripts/x.sh"], "ac_ids": ["AC1"], "dependencies": [],
            "verification": {"method": "unit_test", "detail": "echo"},
        }
    ],
    "adversarial_pass": [{"ac_id": "AC1", "attack": "a", "enforce": "e"}],
}

valid_rx = {
    "replaced": "Bootstrap grid utility classes",
    "existing_sources": [
        {"path_or_channel": "dist/main.css", "evidence": "build-output", "evidence_ref": "grep .col-md-6 dist/main.css"}
    ],
    "ported_symbols": [
        {"symbol": "col-md-6", "usage_evidence": "rg .col-md-6 -> 42", "usage_count": 42, "disposition": "kept"}
    ],
}


def write_case(name, mutate):
    doc = copy.deepcopy(base)
    mutate(doc)
    d = jv_dir / "archive" / name
    d.mkdir(parents=True, exist_ok=True)
    (d / "refinement.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")


# valid: additive field present, well-formed -> exit 0
write_case("valid", lambda d: d.__setitem__("replaces_existing", copy.deepcopy(valid_rx)))

# malformed: evidence outside the enum
def bad_evidence(d):
    rx = copy.deepcopy(valid_rx)
    rx["existing_sources"][0]["evidence"] = "hunch"
    d["replaces_existing"] = rx
write_case("bad-evidence", bad_evidence)

# malformed: usage_count negative
def bad_usage_count(d):
    rx = copy.deepcopy(valid_rx)
    rx["ported_symbols"][0]["usage_count"] = -1
    d["replaces_existing"] = rx
write_case("bad-usage-count", bad_usage_count)

# malformed: existing_sources empty
def empty_sources(d):
    rx = copy.deepcopy(valid_rx)
    rx["existing_sources"] = []
    d["replaces_existing"] = rx
write_case("empty-sources", empty_sources)

# malformed: disposition outside the enum
def bad_disposition(d):
    rx = copy.deepcopy(valid_rx)
    rx["ported_symbols"][0]["disposition"] = "maybe"
    d["replaces_existing"] = rx
write_case("bad-disposition", bad_disposition)

# non-replacing base (no field) -> exit 0 (AC-N1 at the schema layer)
write_case("no-field", lambda d: None)
PY

run_jv() {
  local name="$1"
  set +e
  bash "$JSON_VALIDATOR" "$jv_dir/archive/$name/refinement.json" >/dev/null 2>"$tmpdir/jv.$name.err"
  LAST_RC=$?
  set -e
}

run_jv "valid"
[[ "$LAST_RC" -eq 0 ]] || { cat "$tmpdir/jv.valid.err"; fail "valid replaces_existing must pass json validator (exit 0), got $LAST_RC"; }

run_jv "no-field"
[[ "$LAST_RC" -eq 0 ]] || { cat "$tmpdir/jv.no-field.err"; fail "non-replacing base must pass json validator (exit 0), got $LAST_RC"; }

for bad in bad-evidence bad-usage-count empty-sources bad-disposition; do
  run_jv "$bad"
  [[ "$LAST_RC" -ne 0 ]] || fail "malformed replaces_existing '$bad' must fail json validator"
  grep -q 'replaces_existing' "$tmpdir/jv.$bad.err" || { cat "$tmpdir/jv.$bad.err"; fail "expected a replaces_existing shape error for '$bad'"; }
done

# ---------------------------------------------------------------------------
# AC-NF1 / single-path — both enforcement checks live in the one canonical
# preflight; there is no second preflight and both marker families are owned by
# validate-refinement-lock-preflight.sh.
# ---------------------------------------------------------------------------
grep -q 'POLARIS_REFINEMENT_REPLACE_EXISTING_ENUMERATION' "$PREFLIGHT" \
  || fail "[single-path] enumeration gate marker not owned by the canonical preflight"
grep -q 'POLARIS_REFINEMENT_REPLACE_EXISTING_DEAD_PORT' "$PREFLIGHT" \
  || fail "[single-path] anti-dead-code-port gate marker not owned by the canonical preflight"

# The schema field shape lives in the json validator (additive), not a fork.
grep -q 'replaces_existing' "$JSON_VALIDATOR" \
  || fail "[single-path] replaces_existing schema shape not declared in validate-refinement-json.sh"

echo "PASS: refinement-replace-existing-discipline selftest"
