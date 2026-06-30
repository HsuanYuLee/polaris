#!/usr/bin/env bash
# Selftest for refinement-handoff-gate.sh
#
# Coverage:
#   1. Missing refinement.json blocks handoff
#   2. Valid refinement.json (schema_version, tasks[], adversarial_pass[])
#      passes for an Epic-backed spec, refinement.md/json path forms, and a
#      DP-backed source with `epic: null`
#   3. Invalid refinement.json blocks handoff
#   4. DP-230 D40: skill-workflow-boundary baseline + refinement-owned-only
#      mutation passes the inline boundary check
#   5. DP-230 D40 / AC-NEG16: refinement session that touches an out-of-scope
#      file fails the inline boundary check with
#      POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:refinement on stderr, even
#      when POLARIS_LANGUAGE_POLICY_BYPASS / POLARIS_SKILL_BOUNDARY_BYPASS
#      are set

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$script_dir/refinement-handoff-gate.sh"
boundary_gate="$script_dir/skill-workflow-boundary-gate.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

record_pass() {
  echo "PASS $1"
  pass=$((pass + 1))
}

record_fail() {
  echo "FAIL $1" >&2
  fail=$((fail + 1))
}

assert_ok() {
  local name="$1"
  shift
  if "$@" >/tmp/refinement-handoff-gate-test.out 2>/tmp/refinement-handoff-gate-test.err; then
    record_pass "$name"
  else
    cat /tmp/refinement-handoff-gate-test.err >&2 || true
    record_fail "$name"
  fi
}

assert_fail() {
  local name="$1"
  shift
  if "$@" >/tmp/refinement-handoff-gate-test.out 2>/tmp/refinement-handoff-gate-test.err; then
    cat /tmp/refinement-handoff-gate-test.out >&2 || true
    record_fail "$name"
  else
    record_pass "$name"
  fi
}

write_valid_epic_artifact() {
  local target="$1"
  cat > "$target" <<'JSON'
{
  "epic": "PR-999",
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-04-29T00:00:00+08:00",
  "modules": [
    {
      "path": "apps/main/pages/home/index.vue",
      "action": "modify"
    }
  ],
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "SSR JSON-LD is present.",
      "verification": {
        "method": "curl",
        "detail": "Fetch raw HTML and parse JSON-LD."
      }
    }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "PR-999-T1",
      "kind": "implementation",
      "title": "Add SSR JSON-LD",
      "scope": "Emit JSON-LD block on the home page.",
      "allowed_files": ["apps/main/pages/home/index.vue"],
      "modules": ["apps/main/pages/home/index.vue"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 2,
      "verification": {
        "method": "curl",
        "detail": "echo PASS",
        "verify_command": "echo PASS"
      }
    }
  ],
  "adversarial_pass": [
    {
      "ac_id": "AC1",
      "attack": "Empty body response from upstream",
      "enforce": "Fail-stop with diagnostic when JSON-LD parse fails."
    }
  ],
  "changed_files": [
    "apps/main/pages/home/index.vue"
  ]
}
JSON
}

write_valid_dp_artifact() {
  local target="$1"
  local container_abs="$2"
  python3 - "$target" "$container_abs" <<'PY'
import json, sys
target, container = sys.argv[1:]
payload = {
    "epic": None,
    "source": {
        "type": "dp",
        "id": "DP-999",
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
            "text": "DP-backed refinement artifacts can be validated.",
            "verification": {
                "method": "unit_test",
                "detail": "Run refinement handoff gate selftest."
            }
        }
    ],
    "dependencies": [],
    "edge_cases": [],
    "predecessor_audit": [],
    "tasks": [
        {
            "id": "DP-999-T1",
            "kind": "implementation",
            "title": "Add model-tier policy reference",
            "scope": "Create the model-tier policy reference.",
            "allowed_files": [".claude/skills/references/model-tier-policy.md"],
            "modules": [".claude/skills/references/model-tier-policy.md"],
            "ac_ids": ["AC1"],
            "dependencies": [],
            "estimate_points": 1,
            "verification": {
                "method": "unit_test",
                "detail": "echo PASS",
                "verify_command": "echo PASS",
            },
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
}

write_parity_md_and_index() {
  local container="$1"
  # Render canonical refinement.md from refinement.json via the official renderer
  # so the hand-edit detector accepts it.
  bash "$script_dir/render-refinement-md.sh" "$container/refinement.json" >/dev/null
  # Generate index.md whose AC ids match the JSON for parity.
  python3 - "$container" <<'PY'
import json
import sys
from pathlib import Path

container = Path(sys.argv[1])
data = json.loads((container / "refinement.json").read_text(encoding="utf-8"))
ac = data.get("acceptance_criteria", [])

index_lines = ["# Index", "", "## Acceptance Criteria", ""]
for a in ac:
    index_lines.append(f"- {a['id']}")
index_lines.append("")
(container / "index.md").write_text("\n".join(index_lines), encoding="utf-8")
PY
}

spec="$tmp/specs/PR-999"
mkdir -p "$spec"
printf '# Refinement\n' > "$spec/refinement.md"

assert_fail "missing refinement.json blocks handoff" "$gate" "$spec"

write_valid_epic_artifact "$spec/refinement.json"
write_parity_md_and_index "$spec"

assert_ok "spec directory with valid artifact passes" "$gate" "$spec"
assert_ok "refinement.md path resolves sibling artifact" "$gate" "$spec/refinement.md"
assert_ok "refinement.json path validates directly" "$gate" "$spec/refinement.json"

dp_spec="$tmp/specs/design-plans/DP-999-test"
mkdir -p "$dp_spec"
printf '# DP-999 Plan\n' > "$dp_spec/plan.md"
write_valid_dp_artifact "$dp_spec/refinement.json" "$dp_spec"
write_parity_md_and_index "$dp_spec"

assert_ok "DP-backed artifact with epic null passes" "$gate" "$dp_spec"

# Invalidate the EPIC artifact to trigger schema violation
python3 - "$spec/refinement.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data.pop("schema_version", None)
data.pop("tasks", None)
data["modules"] = []
data["acceptance_criteria"] = []
with open(path, "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PY
assert_fail "invalid refinement.json blocks handoff" "$gate" "$spec"

# ---- DP-230 D40 wiring ------------------------------------------------------
# Build a real git repo so the inline boundary gate can resolve repo + diff.
# When a refinement session baseline exists at runtime, the handoff gate must
# enforce that the session only touched refinement-owned scope.

if [[ -x "$boundary_gate" ]]; then
  bg_repo="$tmp/bgrepo"
  bg_container="$bg_repo/docs-manager/src/content/docs/specs/design-plans/DP-9001"
  mkdir -p "$bg_container/artifacts" "$bg_container/refinement-inbox" "$bg_repo/src"
  git -C "$bg_repo" init -q
  git -C "$bg_repo" config user.email selftest@local
  git -C "$bg_repo" config user.name selftest
  printf '# DP-9001 plan\n' > "$bg_container/plan.md"
  write_valid_dp_artifact "$bg_container/refinement.json" "$bg_container"
  write_parity_md_and_index "$bg_container"
  printf 'pre\n' > "$bg_repo/src/legacy.py"
  git -C "$bg_repo" add -A
  git -C "$bg_repo" -c commit.gpgsign=false commit -q -m init

  # Case A: refinement-owned only change after baseline -> handoff gate PASSES
  POLARIS_RUNTIME_DIR="$bg_repo/.polaris/runtime" \
    "$boundary_gate" --skill refinement --start \
      --source-container "$bg_container" --repo "$bg_repo" >/dev/null
  # In-scope edit that does NOT break refinement.json parity (artifacts/ only)
  mkdir -p "$bg_container/artifacts"
  printf '# session note\n' > "$bg_container/artifacts/note.md"
  if POLARIS_RUNTIME_DIR="$bg_repo/.polaris/runtime" \
       "$gate" "$bg_container" >/tmp/refinement-handoff-gate-test.out 2>/tmp/refinement-handoff-gate-test.err; then
    if grep -q 'PASS refinement handoff' /tmp/refinement-handoff-gate-test.out; then
      record_pass "DP-230 D40: refinement session in-scope edits pass handoff inline boundary check"
    else
      record_fail "DP-230 D40: gate returned 0 but did not emit PASS marker"
    fi
  else
    cat /tmp/refinement-handoff-gate-test.err >&2 || true
    record_fail "DP-230 D40: refinement session in-scope edits should pass"
  fi

  # Case B (AC-NEG16): out-of-scope file written -> gate must fail with
  # POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:refinement, even with bypass envs.
  printf 'forbidden\n' > "$bg_repo/src/new-forbidden.py"
  set +e
  err_out="$(POLARIS_RUNTIME_DIR="$bg_repo/.polaris/runtime" \
              "$gate" "$bg_container" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]] && printf '%s' "$err_out" | grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:refinement'; then
    record_pass "DP-230 D40: out-of-scope mutation blocks handoff"
  else
    record_fail "DP-230 D40: out-of-scope handoff should fail (rc=$rc, err=$err_out)"
  fi

  set +e
  err_out="$(POLARIS_LANGUAGE_POLICY_BYPASS=1 POLARIS_SKILL_BOUNDARY_BYPASS=1 \
              POLARIS_RUNTIME_DIR="$bg_repo/.polaris/runtime" \
              "$gate" "$bg_container" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]] && printf '%s' "$err_out" | grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:refinement'; then
    record_pass "DP-230 D40 / AC-NEG16: bypass envs cannot silence boundary gate"
  else
    record_fail "DP-230 D40 / AC-NEG16: bypass envs unexpectedly silenced gate (rc=$rc)"
  fi
else
  echo "skip: skill-workflow-boundary-gate.sh not executable (DP-230 D40 wiring uncovered)" >&2
fi

if [[ "$fail" -ne 0 ]]; then
  echo "refinement-handoff-gate selftest: $pass pass, $fail fail" >&2
  exit 1
fi

echo "refinement-handoff-gate selftest: $pass pass, $fail fail"
