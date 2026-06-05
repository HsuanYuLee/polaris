#!/usr/bin/env bash
# Purpose: DP-273 T2 (Wall B) hermetic selftest — closeout / release-tail context
#          must NOT re-run the refinement-session boundary check, while a live
#          refinement->breakdown handoff still fires it. Also asserts the
#          defense-in-depth baseline cleanup after a refinement handoff PASS.
# Inputs:  none (builds synthetic overlay repos + DP containers under mktemp).
# Outputs: stdout PASS/FAIL lines; exit 0 all-pass, exit 1 any failure.
# Side effects: tmpdir only (removed on EXIT). No live workspace mutation.
#
# Coverage:
#   - AC2 / AC6 (positive): closeout-context with a stale refinement baseline +
#     a release diff containing a code deliverable -> check-main-chain-compliance
#     does NOT emit POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:refinement.
#   - AC-NEG2 (negative): a LIVE refinement->breakdown handoff context -> the
#     boundary STILL fires (must not be weakened).
#   - baseline cleanup: after refinement handoff gate PASS, the stale boundary
#     baseline for that source is removed.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
main_chain_gate="$script_dir/check-main-chain-compliance.sh"
handoff_gate="$script_dir/refinement-handoff-gate.sh"
boundary_gate="$script_dir/skill-workflow-boundary-gate.sh"
render_md="$script_dir/render-refinement-md.sh"

for g in "$main_chain_gate" "$handoff_gate" "$boundary_gate"; do
  if [[ ! -x "$g" ]]; then
    echo "FAIL: gate not executable: $g" >&2
    exit 1
  fi
done

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

pass=0
fail=0
record_pass() { echo "PASS $1"; pass=$((pass + 1)); }
record_fail() { echo "FAIL $1" >&2; fail=$((fail + 1)); }

# Emit a schema-valid DP-backed refinement.json (mirrors the canonical fixture
# used by refinement-handoff-gate-selftest.sh) so the handoff gate reaches its
# inline boundary check instead of failing earlier on schema validation.
write_valid_dp_artifact() {
  local target="$1" container_abs="$2"
  python3 - "$target" "$container_abs" <<'PY'
import json, sys
target, container = sys.argv[1:]
payload = {
    "epic": None,
    "source": {
        "type": "dp",
        "id": "DP-998",
        "container": container,
        "plan_path": container + "/plan.md",
        "jira_key": None,
    },
    "version": "1.0",
    "schema_version": "1.0",
    "created_at": "2026-06-05T00:00:00+08:00",
    "modules": [
        {"path": "src/foo.py", "action": "modify"}
    ],
    "acceptance_criteria": [
        {
            "id": "AC1",
            "text": "Wall B fixture AC.",
            "verification": {"method": "unit_test", "detail": "Run selftest."},
        }
    ],
    "dependencies": [],
    "edge_cases": [],
    "predecessor_audit": [],
    "tasks": [
        {
            "id": "DP-998-T1",
            "kind": "implementation",
            "title": "Wall B fixture task",
            "scope": "Deliver src/foo.py.",
            "allowed_files": ["src/foo.py"],
            "modules": ["src/foo.py"],
            "ac_ids": ["AC1"],
            "dependencies": [],
            "estimate_points": 1,
            "verification": {"method": "unit_test", "detail": "Run selftest."},
        }
    ],
    "adversarial_pass": [
        {
            "ac_id": "AC1",
            "attack": "Boundary skip leaks an out-of-scope mutation.",
            "enforce": "Live handoff boundary still fires (AC-NEG2).",
        }
    ],
    "changed_files": ["src/foo.py"],
}
with open(target, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)
PY
}

# Render canonical refinement.md + a parity index.md from refinement.json.
write_parity_md_and_index() {
  local container="$1"
  bash "$render_md" "$container/refinement.json" >/dev/null
  python3 - "$container" <<'PY'
import json, sys
from pathlib import Path
container = Path(sys.argv[1])
data = json.loads((container / "refinement.json").read_text(encoding="utf-8"))
lines = ["# Index", "", "## Acceptance Criteria", ""]
for a in data.get("acceptance_criteria", []):
    lines.append(f"- {a['id']}")
lines.append("")
(container / "index.md").write_text("\n".join(lines), encoding="utf-8")
PY
}

# Build an isolated repo + DP-backed source container that satisfies the
# check-main-chain-compliance source-container contract (parent markdown,
# valid refinement.json, >=1 T*.md, >=1 V*.md).
make_repo() {
  local label="$1"
  local repo="$tmp_root/repo-$label"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@local
  git -C "$repo" config user.name selftest
  git -C "$repo" config commit.gpgsign false

  local container="$repo/docs-manager/src/content/docs/specs/design-plans/DP-998-wall-b-fixture"
  mkdir -p "$container/tasks/T1" "$container/tasks/V1" "$container/artifacts"
  printf '# DP-998 Plan\n' > "$container/plan.md"
  write_valid_dp_artifact "$container/refinement.json" "$container"
  write_parity_md_and_index "$container"
  printf '# T1\n## Allowed Files\n- `src/foo.py`\n' > "$container/tasks/T1/index.md"
  printf '# V1\n' > "$container/tasks/V1/index.md"
  mkdir -p "$repo/src"
  printf '# repo\n' > "$repo/README.md"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "init"

  printf '%s\n%s\n' "$repo" "$container"
}

# refn_baseline_path: compute where refinement-handoff-gate / boundary-gate
# stores the refinement session baseline for this container (must mirror the
# id derivation in those scripts).
refn_baseline_path() {
  local repo="$1" container="$2"
  local real_container baseline_id
  real_container="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$container")"
  baseline_id="$(printf '%s|%s' refinement "$real_container" \
    | python3 -c "import hashlib,sys; print(hashlib.sha1(sys.stdin.read().encode()).hexdigest()[:16])")"
  printf '%s\n' "$repo/.polaris/runtime/skill-workflow-boundary/refinement-${baseline_id}.json"
}

# ---- 1. AC2/AC6 positive: closeout context skips refinement boundary --------
# Simulate: a refinement session captured a baseline; then breakdown +
# engineering landed downstream code commits (the delivery). At release-tail
# closeout, check-main-chain-compliance must NOT emit the refinement boundary
# block even though a code deliverable sits in the release diff and the stale
# refinement baseline still exists on disk.
{
  out="$(make_repo "closeout-pos")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"

  # Refinement session baseline at the refinement HEAD.
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$boundary_gate" --skill refinement --start --source-container "$container" --repo "$repo" >/dev/null

  # Downstream delivery lands AFTER the refinement session: a code deliverable
  # (out of refinement-owned scope) gets committed -> stale refinement baseline.
  printf 'def foo():\n    return 1\n' > "$repo/src/foo.py"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "engineering: deliver src/foo.py (DP-998 T1)"

  set +e
  err_out="$(POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$main_chain_gate" --repo "$repo" --source-container "$container" \
              --allow-active-verification --closeout 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if printf '%s' "$err_out" | grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:refinement'; then
    record_fail "AC2/AC6 closeout context emitted refinement boundary block (rc=$rc, err=$err_out)"
  else
    record_pass "AC2/AC6 closeout context skips refinement boundary (no BLOCKED marker)"
  fi
}

# ---- 2. AC2/AC6 positive (auto-detect, no flag): stale baseline -> skip ------
# Same as #1 but WITHOUT --closeout, relying on liveness auto-detection: the
# committed diff between the refinement baseline head and HEAD already contains
# out-of-refinement-scope code, so the session is not live -> boundary skipped.
{
  out="$(make_repo "closeout-autodetect")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"

  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$boundary_gate" --skill refinement --start --source-container "$container" --repo "$repo" >/dev/null

  printf 'def foo():\n    return 2\n' > "$repo/src/foo.py"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "engineering: deliver src/foo.py (DP-998 T1)"

  set +e
  err_out="$(POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$handoff_gate" "$container/refinement.json" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if printf '%s' "$err_out" | grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:refinement'; then
    record_fail "AC2/AC6 stale-baseline auto-detect emitted refinement boundary block (rc=$rc, err=$err_out)"
  else
    record_pass "AC2/AC6 stale-baseline auto-detect skips refinement boundary"
  fi
}

# ---- 3. AC-NEG2 negative: LIVE refinement->breakdown handoff still fires -----
# A live refinement session writes an out-of-scope file in the working tree
# (not committed downstream). The boundary MUST still fire when the handoff
# gate runs — Wall B must not weaken the live handoff boundary.
{
  out="$(make_repo "live-handoff")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"

  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$boundary_gate" --skill refinement --start --source-container "$container" --repo "$repo" >/dev/null

  # Live refinement session illegally mutates a code file (working tree dirty,
  # no downstream commits) -> baseline head == HEAD, session is live.
  printf 'x = 1\n' > "$repo/src/forbidden.py"

  set +e
  err_out="$(POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$handoff_gate" "$container/refinement.json" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if printf '%s' "$err_out" | grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:refinement'; then
    record_pass "AC-NEG2 live refinement handoff still fires boundary (not weakened)"
  else
    record_fail "AC-NEG2 live refinement handoff failed to fire boundary (rc=$rc, err=$err_out)"
  fi
}

# ---- 4. baseline cleanup (boundary gate): --cleanup-stale-on-pass -----------
# skill-workflow-boundary-gate.sh must, on a refinement --check PASS with
# --cleanup-stale-on-pass, remove that source's baseline (EC4 defense-in-depth)
# so a later release-tail closeout cannot re-trip on a left-over baseline.
# Without the flag, an ordinary in-session re-check keeps its baseline.
{
  out="$(make_repo "cleanup-flag")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"

  baseline_path="$(refn_baseline_path "$repo" "$container")"

  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$boundary_gate" --skill refinement --start --source-container "$container" --repo "$repo" >/dev/null

  if [[ ! -f "$baseline_path" ]]; then
    record_fail "baseline cleanup: --start did not write baseline at $baseline_path"
  else
    # Scope-only refinement change (artifacts/ keeps refinement.md/json parity).
    printf '# session note\n' > "$container/artifacts/note.md"
    # Without the flag the in-session re-check must keep the baseline.
    if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
         "$boundary_gate" --skill refinement --check --source-container "$container" --repo "$repo" >/dev/null 2>&1 \
       && [[ -f "$baseline_path" ]]; then
      record_pass "baseline cleanup: in-session re-check keeps baseline (no flag)"
    else
      record_fail "baseline cleanup: in-session re-check unexpectedly removed baseline / failed"
    fi
    # With the flag, a PASS retires the stale baseline.
    if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
         "$boundary_gate" --skill refinement --check --cleanup-stale-on-pass \
           --source-container "$container" --repo "$repo" >/dev/null 2>&1; then
      if [[ -f "$baseline_path" ]]; then
        record_fail "baseline cleanup: baseline still present after PASS + --cleanup-stale-on-pass"
      else
        record_pass "baseline cleanup: --cleanup-stale-on-pass removes baseline on PASS"
      fi
    else
      record_fail "baseline cleanup: refinement scope-only check unexpectedly failed (cleanup flag)"
    fi
  fi
}

# ---- 5. baseline cleanup (handoff gate stale path) --------------------------
# When the handoff gate detects a stale/closeout session (downstream code
# already committed), it skips the boundary check AND retires the stale
# refinement baseline so a later run cannot re-trip on it (EC4).
{
  out="$(make_repo "cleanup-handoff")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"

  baseline_path="$(refn_baseline_path "$repo" "$container")"

  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$boundary_gate" --skill refinement --start --source-container "$container" --repo "$repo" >/dev/null

  # Downstream code commit -> stale baseline -> closeout context.
  printf 'def foo():\n    return 3\n' > "$repo/src/foo.py"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "engineering: deliver src/foo.py (DP-998 T1)"

  if [[ ! -f "$baseline_path" ]]; then
    record_fail "handoff cleanup: --start did not write baseline at $baseline_path"
  elif POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
         "$handoff_gate" "$container/refinement.json" >/dev/null 2>&1; then
    if [[ -f "$baseline_path" ]]; then
      record_fail "handoff cleanup: stale baseline still present after closeout-detected handoff"
    else
      record_pass "handoff cleanup: stale baseline retired on closeout-detected handoff"
    fi
  else
    record_fail "handoff cleanup: handoff gate unexpectedly failed in closeout context"
  fi
}

if [[ "$fail" -ne 0 ]]; then
  echo "closeout-no-refinement-session-boundary selftest: $pass pass, $fail fail" >&2
  exit 1
fi
echo "closeout-no-refinement-session-boundary selftest: $pass pass, $fail fail"
