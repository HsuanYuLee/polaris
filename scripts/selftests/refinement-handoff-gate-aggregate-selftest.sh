#!/usr/bin/env bash
# Purpose: DP-417 T10 — fail-aggregate contract reporting + up-front enumerate for
#          the refinement producer-write / handoff-gate chain.
# Inputs:  none (self-contained fixtures under a tmpdir).
# Outputs: stdout PASS/FAIL lines; exit 0 all pass, exit 1 any fail.
# Side effects: writes/removes a tmpdir of fixture refinement artifacts.
#
# Coverage (part 1 CORE — AC12 / AC13 / AC-NEG7 / AC-N1):
#   AC12  fail-aggregate: a single refinement artifact with violations spanning
#         MULTIPLE gate layers, run through refinement-handoff-gate.sh --aggregate,
#         reports ALL unmet contract requirements in ONE execution (not fail-first).
#   AC-NEG7 no fail-first regression: an artifact with 3 violations in 3 different
#         gate layers surfaces all 3 markers in one run (aborting after the first is
#         a regression).
#   AC13  up-front enumerate: refinement-handoff-gate.sh --enumerate AND
#         write-producer-owned-artifact.sh --enumerate-contract <token> list the
#         complete required-field/gate set for the chain WITHOUT writing/mutating.
#   AC-N1 a clean valid artifact still passes --aggregate (exit 0).
#
# NOTE (part 2 / AC21): this file is structured so the framework-release-tail case
#   can append below the "PART-2 APPEND POINT" marker without touching part-1
#   helpers or cases. Reuse build_valid_dp_artifact / assert_* helpers.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$script_dir/refinement-handoff-gate.sh"
producer_writer="$script_dir/write-producer-owned-artifact.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

record_pass() { echo "PASS $1"; pass=$((pass + 1)); }
record_fail() { echo "FAIL $1" >&2; fail=$((fail + 1)); }

# dir_fingerprint <dir> -> stable checksum of every file's content, for a
# no-mutation assertion (enumerate/dry-run must not write).
dir_fingerprint() {
  local dir="$1"
  (cd "$dir" && find . -type f -exec shasum {} \; 2>/dev/null | sort)
}

# --- shared fixture builders (reused by part-2) -----------------------------

# build_valid_dp_artifact <container_dir> : writes a refinement.json + rendered
# refinement.md + parity index.md that PASS the whole handoff chain, including
# lock-preflight -> derive -> validate-breakdown-ready.
build_valid_dp_artifact() {
  local container="$1"
  mkdir -p "$container"
  printf '# DP-910 Plan\n' > "$container/plan.md"
  python3 - "$container/refinement.json" "$container" <<'PY'
import json, sys
target, container = sys.argv[1:]
payload = {
    "epic": None,
    "source": {
        "type": "dp",
        "id": "DP-910",
        "container": container,
        "plan_path": container + "/plan.md",
        "jira_key": None,
    },
    "version": "1.0",
    "schema_version": "1.0",
    "created_at": "2026-04-30T00:00:00+08:00",
    "modules": [
        {"path": ".claude/skills/references/model-tier-policy.md", "action": "create"}
    ],
    "acceptance_criteria": [
        {
            "id": "AC1",
            "text": "DP-backed refinement artifacts can be validated by the handoff aggregate gate.",
            "verification": {
                "method": "unit_test",
                "detail": "Run refinement handoff gate aggregate selftest.",
            },
        }
    ],
    "dependencies": [],
    "edge_cases": [],
    "predecessor_audit": [],
    "tasks": [
        {
            "id": "DP-910-T1",
            "kind": "implementation",
            "title": "Add model-tier policy reference",
            "scope": "Create the model-tier policy reference file.",
            "modules": [".claude/skills/references/model-tier-policy.md"],
            "ac_ids": ["AC1"],
            "dependencies": [],
            "verification": {
                "method": "unit_test",
                "detail": "echo PASS",
                "verify_command": "echo PASS",
            },
        }
    ],
    "handoff_advisories": [
        {
            "id": "framework-release-surface-missing",
            "producer": "refinement-release-surface-advisory",
            "severity": "actionable",
            "recommended_action": "Absorb release surface advisory into this fixture task.",
            "disposition": "absorbed_by_task",
            "task_ids": ["DP-910-T1"],
        }
    ],
    "adversarial_pass": [
        {
            "ac_id": "AC1",
            "attack": "Reference body missing required headings",
            "enforce": "Validator fails with explicit missing-section diagnostic.",
        }
    ],
    "changed_files": [".claude/skills/references/model-tier-policy.md"],
}
with open(target, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)
PY
  bash "$script_dir/render-refinement-md.sh" "$container/refinement.json" >/dev/null
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

# inject_multi_layer_violations <container_dir> : mutates the VALID refinement.json
# in place to break THREE distinct gate layers (schema / module-AC coverage /
# AC-id-shape), WITHOUT re-rendering md, so a fail-first chain aborts at the schema
# layer while an aggregate run surfaces all three.
inject_multi_layer_violations() {
  local container="$1"
  python3 - "$container/refinement.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
# Layer 1 (schema): drop the required top-level 'dependencies' field.
data.pop("dependencies", None)
# Layer 2 (module-AC coverage): un-cover the module by removing it from the task's
# modules[] so its filename token is not in the AC blob nor any task module blob.
for t in data.get("tasks", []):
    t["modules"] = []
# Layer 3 (AC-id shape): add an AC with an id that violates ^AC[0-9]+$ / ^AC-[A-Z0-9]+$.
data.setdefault("acceptance_criteria", []).append({
    "id": "ACfoo",
    "text": "Extra AC with an invalid id shape.",
    "verification": {"method": "unit_test", "detail": "echo PASS"},
})
json.dump(data, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
}

# --- AC-N1: clean valid artifact still passes --aggregate -------------------
valid="$tmp/DP-910-valid"
build_valid_dp_artifact "$valid"
if "$gate" --aggregate "$valid" >"$tmp/valid.out" 2>"$tmp/valid.err"; then
  record_pass "AC-N1: valid artifact passes --aggregate (exit 0)"
else
  cat "$tmp/valid.err" >&2 || true
  record_fail "AC-N1: valid artifact should pass --aggregate"
fi

# --- AC12 / AC-NEG7: multi-layer fail is aggregated in ONE run --------------
badc="$tmp/DP-910-multifail"
build_valid_dp_artifact "$badc"
inject_multi_layer_violations "$badc"

set +e
"$gate" --aggregate "$badc" >"$tmp/agg.out" 2>"$tmp/agg.err"
agg_rc=$?
set -e
agg_all="$(cat "$tmp/agg.out" "$tmp/agg.err")"

if [[ "$agg_rc" -ne 0 ]]; then
  record_pass "AC12: multi-layer fail exits non-zero under --aggregate"
else
  record_fail "AC12: multi-layer fail should exit non-zero (rc=$agg_rc)"
fi

# All three distinct-layer markers must appear in the SINGLE aggregate run.
layer_hits=0
declare -a missing_layers=()
check_layer() {
  local label="$1" pattern="$2"
  if printf '%s' "$agg_all" | grep -qE "$pattern"; then
    layer_hits=$((layer_hits + 1))
  else
    missing_layers+=("$label ($pattern)")
  fi
}
check_layer "schema:dependencies" "dependencies"
check_layer "module-AC-coverage" "POLARIS_MODULE_AC_MISSING"
check_layer "AC-id-shape" "POLARIS_AC_ID_SHAPE_INVALID"

if [[ "$layer_hits" -eq 3 ]]; then
  record_pass "AC12: all three layer markers reported in ONE aggregate run"
else
  record_fail "AC12: only $layer_hits/3 layer markers reported; missing: ${missing_layers[*]:-none}"
fi

# AC-NEG7: not fail-first — more than one distinct gate layer surfaced.
if [[ "$layer_hits" -ge 2 ]]; then
  record_pass "AC-NEG7: aggregate did not fail-first (>=2 distinct layers surfaced)"
else
  record_fail "AC-NEG7: aggregate appears fail-first (only $layer_hits distinct layer)"
fi

# Sanity: default (fail-first) mode on the SAME artifact surfaces the schema layer
# but NOT the later layers (proves the two modes differ / aggregate is meaningful).
set +e
"$gate" "$badc" >"$tmp/ff.out" 2>"$tmp/ff.err"
ff_rc=$?
set -e
ff_all="$(cat "$tmp/ff.out" "$tmp/ff.err")"
if [[ "$ff_rc" -ne 0 ]] \
   && ! printf '%s' "$ff_all" | grep -qE 'POLARIS_AC_ID_SHAPE_INVALID'; then
  record_pass "AC-NEG7: default fail-first mode stops before the later AC-id-shape layer"
else
  record_fail "AC-NEG7: default mode unexpectedly reached the AC-id-shape layer (fail-first not observable)"
fi

# --- AC13: up-front enumerate lists the whole chain WITHOUT writing ----------
enum_dir="$tmp/DP-910-enum"
build_valid_dp_artifact "$enum_dir"
before_fp="$(dir_fingerprint "$enum_dir")"

set +e
"$gate" --enumerate "$enum_dir" >"$tmp/enum.out" 2>"$tmp/enum.err"
enum_rc=$?
set -e
after_fp="$(dir_fingerprint "$enum_dir")"

if [[ "$enum_rc" -eq 0 ]]; then
  record_pass "AC13: --enumerate exits 0"
else
  cat "$tmp/enum.err" >&2 || true
  record_fail "AC13: --enumerate should exit 0 (rc=$enum_rc)"
fi

if [[ "$before_fp" == "$after_fp" ]]; then
  record_pass "AC13: --enumerate mutates nothing (no write)"
else
  record_fail "AC13: --enumerate mutated the container"
fi

# The enumeration must span the whole chain: handoff sub-gates + lock-preflight +
# derive + validate-breakdown-ready.
enum_out="$(cat "$tmp/enum.out")"
enum_ok=1
for needle in schema module-ac-coverage ac-id-shape lock-preflight derive validate-breakdown-ready; do
  if ! printf '%s' "$enum_out" | grep -qiF "$needle"; then
    enum_ok=0
    echo "  enumerate missing chain stage: $needle" >&2
  fi
done
if [[ "$enum_ok" -eq 1 ]]; then
  record_pass "AC13: --enumerate lists the complete chain (handoff + lock-preflight + derive + breakdown-ready)"
else
  record_fail "AC13: --enumerate did not list every chain stage"
fi

# AC13: producer-token enumerate via the writer entrypoint (no write).
producer_before="$(dir_fingerprint "$enum_dir")"
set +e
"$producer_writer" --enumerate-contract refinement:design-doc >"$tmp/penum.out" 2>"$tmp/penum.err"
penum_rc=$?
set -e
producer_after="$(dir_fingerprint "$enum_dir")"
if [[ "$penum_rc" -eq 0 ]] \
   && grep -qiF "refinement:design-doc" "$tmp/penum.out" \
   && grep -qiF "validate-refinement-json" "$tmp/penum.out" \
   && [[ "$producer_before" == "$producer_after" ]]; then
  record_pass "AC13: producer --enumerate-contract lists the token contract without writing"
else
  cat "$tmp/penum.err" >&2 || true
  record_fail "AC13: producer --enumerate-contract failed (rc=$penum_rc)"
fi

# =========================== PART-2 APPEND POINT ============================
# DP-417 T10 part 2 (AC21, framework-release tail) appends its cases below,
# reusing build_valid_dp_artifact / dir_fingerprint / record_pass|fail.
#
# Coverage (part 2 — AC21):
#   AC21a release-tail fail-aggregate: framework-release-closeout.sh --aggregate
#         surfaces ALL argument-shape precondition violations in ONE run (not
#         fail-first), while default mode stops at the first (proves the modes
#         differ / aggregate is meaningful).
#   AC21b release-tail enumerate/dry-run: --enumerate on BOTH release scripts
#         lists the complete release precondition set WITHOUT executing (exit 0).
#   AC21c deterministic handoff producer: framework-release-closeout.sh
#         --emit-handoff emits the COMPLETE framework-release arg set
#         deterministically (byte-identical across runs) with no writes.
#   AC21d drift-parity: SKILL.md and the closeout script agree on the
#         canonical delivery-head authority (deliverable.head_sha, DP-360) and
#         the task_kind=V exclusion.
# ===========================================================================

closeout="$script_dir/framework-release-closeout.sh"
execute="$script_dir/framework-release-execute.sh"
skill_md="$script_dir/../.claude/skills/framework-release/SKILL.md"

# --- AC21a: closeout --aggregate surfaces all precondition violations at once -
vtask="$tmp/AC21-Vtask.md"
printf -- '---\ntask_kind: V\n---\n# V task\n' > "$vtask"

set +e
"$closeout" --aggregate --task-md "$vtask" >"$tmp/co_agg.out" 2>"$tmp/co_agg.err"
co_agg_rc=$?
set -e
co_agg_all="$(cat "$tmp/co_agg.out" "$tmp/co_agg.err")"

if [[ "$co_agg_rc" -eq 2 ]]; then
  record_pass "AC21a: closeout --aggregate exits 2 on precondition violations"
else
  cat "$tmp/co_agg.err" >&2 || true
  record_fail "AC21a: closeout --aggregate should exit 2 (rc=$co_agg_rc)"
fi

co_precond_hits=0
declare -a co_precond_missing=()
check_precond() {
  local label="$1" pattern="$2"
  if printf '%s' "$co_agg_all" | grep -qF "$pattern"; then
    co_precond_hits=$((co_precond_hits + 1))
  else
    co_precond_missing+=("$label ($pattern)")
  fi
}
check_precond "aggregate-marker" "POLARIS_FRAMEWORK_RELEASE_CLOSEOUT_PRECONDITION_AGGREGATE"
check_precond "verify-evidence"  "verify-evidence"
check_precond "version-tag"      "version-tag"
check_precond "release-url"      "release-url"
check_precond "task_kind=V"      "task_kind=V"

if [[ "$co_precond_hits" -eq 5 ]]; then
  record_pass "AC21a: closeout --aggregate lists all 5 distinct precondition markers in ONE run"
else
  record_fail "AC21a: only $co_precond_hits/5 precondition markers reported; missing: ${co_precond_missing[*]:-none}"
fi

# Control: default (fail-first) mode stops at the FIRST precondition and never
# reaches the later version-tag / task_kind=V checks.
set +e
"$closeout" --task-md "$vtask" >"$tmp/co_ff.out" 2>"$tmp/co_ff.err"
co_ff_rc=$?
set -e
co_ff_all="$(cat "$tmp/co_ff.out" "$tmp/co_ff.err")"
if [[ "$co_ff_rc" -ne 0 ]] \
   && ! printf '%s' "$co_ff_all" | grep -qF 'task_kind=V' \
   && ! printf '%s' "$co_ff_all" | grep -qF 'version-tag'; then
  record_pass "AC21a: default closeout mode is fail-first (stops before later preconditions)"
else
  record_fail "AC21a: default closeout mode unexpectedly reached later preconditions (fail-first not observable)"
fi

# --- AC21b: --enumerate lists the full release precondition set, no execution --
set +e
"$closeout" --enumerate >"$tmp/co_enum.out" 2>"$tmp/co_enum.err"
co_enum_rc=$?
"$execute" --enumerate >"$tmp/ex_enum.out" 2>"$tmp/ex_enum.err"
ex_enum_rc=$?
set -e

if [[ "$co_enum_rc" -eq 0 && "$ex_enum_rc" -eq 0 ]]; then
  record_pass "AC21b: --enumerate exits 0 on both release scripts"
else
  cat "$tmp/co_enum.err" "$tmp/ex_enum.err" >&2 || true
  record_fail "AC21b: --enumerate should exit 0 (closeout=$co_enum_rc execute=$ex_enum_rc)"
fi

co_enum_out="$(cat "$tmp/co_enum.out")"
enum_ok=1
for needle in --workspace-commit --template-commit --version-tag --release-url \
              --verify-evidence --task-head-sha --preflight-evidence \
              task_kind=V deliverable.head_sha; do
  if ! printf '%s' "$co_enum_out" | grep -qF -- "$needle"; then
    enum_ok=0
    echo "  closeout --enumerate missing: $needle" >&2
  fi
done
ex_enum_out="$(cat "$tmp/ex_enum.out")"
for needle in feat/DP-NNN --full-tail --source-id; do
  if ! printf '%s' "$ex_enum_out" | grep -qF -- "$needle"; then
    enum_ok=0
    echo "  execute --enumerate missing: $needle" >&2
  fi
done
if [[ "$enum_ok" -eq 1 ]]; then
  record_pass "AC21b: --enumerate lists the complete release precondition set (both scripts)"
else
  record_fail "AC21b: --enumerate did not list every release precondition"
fi

# --- AC21c: deterministic handoff producer emits the full arg set, no writes --
etask_dir="$tmp/DP-910-emit"
etask="$etask_dir/task.md"
mkdir -p "$etask_dir"
printf -- '---\ntask_kind: implementation\n---\n# T1\n' > "$etask"
: > "$tmp/verify1.json"
emit_args=(--emit-handoff --repo "$tmp" --task-md "$etask" --verify-evidence "$tmp/verify1.json" \
  --workspace-commit a1b2c3d4 --template-commit b2c3d4e5 \
  --version-tag v9.9.9 --release-url https://example.com/r/v9.9.9)
emit_before_fp="$(dir_fingerprint "$etask_dir")"
set +e
"$closeout" "${emit_args[@]}" >"$tmp/emit1.out" 2>"$tmp/emit1.err"
emit_rc1=$?
"$closeout" "${emit_args[@]}" >"$tmp/emit2.out" 2>"$tmp/emit2.err"
emit_rc2=$?
set -e
emit_after_fp="$(dir_fingerprint "$etask_dir")"

if [[ "$emit_rc1" -eq 0 && "$emit_rc2" -eq 0 ]]; then
  record_pass "AC21c: --emit-handoff exits 0 for a valid arg set"
else
  cat "$tmp/emit1.err" >&2 || true
  record_fail "AC21c: --emit-handoff should exit 0 (rc1=$emit_rc1 rc2=$emit_rc2)"
fi

emit_out="$(cat "$tmp/emit1.out")"
emit_ok=1
for needle in framework-release-closeout.sh framework-release-execute.sh --full-tail \
              --task-md --verify-evidence --workspace-commit --version-tag --release-url; do
  if ! printf '%s' "$emit_out" | grep -qF -- "$needle"; then
    emit_ok=0
    echo "  --emit-handoff missing arg-set token: $needle" >&2
  fi
done
if [[ "$emit_ok" -eq 1 ]]; then
  record_pass "AC21c: --emit-handoff emits the complete framework-release arg set"
else
  record_fail "AC21c: --emit-handoff did not emit the complete arg set"
fi

if diff -q "$tmp/emit1.out" "$tmp/emit2.out" >/dev/null 2>&1; then
  record_pass "AC21c: --emit-handoff output is deterministic (byte-identical across runs)"
else
  record_fail "AC21c: --emit-handoff output is non-deterministic"
fi

if [[ "$emit_before_fp" == "$emit_after_fp" ]]; then
  record_pass "AC21c: --emit-handoff mutates nothing (no write)"
else
  record_fail "AC21c: --emit-handoff mutated the fixture"
fi

# --- AC21d: SKILL <-> script drift parity (head_sha authority + V exclusion) --
drift_ok=1
for f in "$skill_md" "$closeout"; do
  if ! grep -qF 'deliverable.head_sha' "$f"; then
    drift_ok=0
    echo "  drift: 'deliverable.head_sha' missing from $f" >&2
  fi
done
if ! grep -qF 'task_kind=V' "$closeout"; then
  drift_ok=0
  echo "  drift: 'task_kind=V' exclusion missing from closeout script" >&2
fi
if ! grep -qF 'task_kind' "$skill_md"; then
  drift_ok=0
  echo "  drift: task_kind V-exclusion not documented in SKILL.md" >&2
fi
if [[ "$drift_ok" -eq 1 ]]; then
  record_pass "AC21d: SKILL.md and closeout script agree on head_sha authority + V exclusion"
else
  record_fail "AC21d: SKILL <-> script drift on head_sha authority / V exclusion"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "refinement-handoff-gate-aggregate selftest: $pass pass, $fail fail" >&2
  exit 1
fi
echo "refinement-handoff-gate-aggregate selftest: $pass pass, $fail fail"
