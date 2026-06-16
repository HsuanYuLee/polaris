#!/usr/bin/env bash
# Purpose: selftest for DP-325 T4 — assert the three "read the authoritative FIELD,
#   not a path/filename heuristic" consumer fixes classify by the recorded field:
#     A1 (AC5) : derive-task-md-from-refinement-json.sh derives the task.md change
#                table Action from refinement.json modules[].action — the SAME path
#                yields create vs modify purely from the field, never from path shape.
#     A2/A3 (AC6): skill-resource-ownership-audit.sh / script-ownership-audit.py read
#                the manifest kind / owner_surface field; with a filename prefix that
#                conflicts with the field, classification follows the field.
#     AC-NF1   : missing / invalid authoritative input fails-closed with a structured
#                marker (derive) or degrades safely without crashing (audits).
# Inputs:  none (constructs refinement.json + manifest fixtures in a tmpdir)
# Outputs: stdout PASS line on success; non-zero exit + stderr on failure
# Exit code: 0 = pass, non-zero = fail

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVE="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"
SKILL_AUDIT="$ROOT_DIR/scripts/skill-resource-ownership-audit.sh"
SCRIPT_AUDIT="$ROOT_DIR/scripts/script-ownership-audit.py"

[[ -x "$DERIVE" ]] || { echo "FAIL: derive script not executable: $DERIVE" >&2; exit 1; }
[[ -x "$SKILL_AUDIT" ]] || { echo "FAIL: skill-resource audit not executable: $SKILL_AUDIT" >&2; exit 1; }
[[ -f "$SCRIPT_AUDIT" ]] || { echo "FAIL: script-ownership audit not found: $SCRIPT_AUDIT" >&2; exit 1; }

tmpdir="$(mktemp -d -t derive-action-field.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

fail() {
  echo "FAIL [$1]: $2" >&2
  exit 1
}

# A refinement.json whose top-level modules[] records ${action} for the SAME
# allowed path on every run. The path itself never changes between the two cases —
# only the recorded action field — proving the change-table Action follows the field.
write_refinement() {
  local out="$1" action="$2"
  cat >"$out" <<JSON
{
  "source": {
    "type": "dp",
    "id": "DP-901",
    "container": "/Users/x/work/docs-manager/src/content/docs/specs/design-plans/DP-901-sample",
    "plan_path": "/tmp/dp-901/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "modules": [
    { "path": "scripts/selftests/shape-conflict-selftest.sh", "action": "${action}", "complexity": "low", "risk": "low", "reason": "fixture", "references": 0 }
  ],
  "tasks": [
    {
      "id": "DP-901-T1",
      "kind": "implementation",
      "title": "範例 field-driven action",
      "scope": "驗證 task.md 改動範圍 Action 跟 modules[].action 欄位、不跟 path。",
      "allowed_files": ["scripts/selftests/shape-conflict-selftest.sh"],
      "modules": ["scripts/selftests/shape-conflict-selftest.sh"],
      "ac_ids": ["AC5"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/shape-conflict-selftest.sh",
        "verify_command": "bash scripts/selftests/shape-conflict-selftest.sh",
        "behavior_contract": { "applies": false, "reason": "framework infra" },
        "test_environment": { "level": "static" },
        "references": ["scripts/selftests/shape-conflict-selftest.sh"]
      }
    }
  ]
}
JSON
}

action_cell_for() {
  # Extract the ## 改動範圍 change-table action column for the single allowed path.
  # The change table row is `| \`path\` | <action> | <summary> |` where <action>
  # is a single lowercase word; the Scope Trace Matrix row for the same path has a
  # different 2nd column, so anchor on the lowercase-word-then-pipe shape.
  local task_md="$1"
  grep -F '| `scripts/selftests/shape-conflict-selftest.sh` |' "$task_md" \
    | grep -E '\| `[^`]*` \| (create|modify|delete|investigate) \|' \
    | sed -E 's/^\| `[^`]*` \| (create|modify|delete|investigate) \|.*/\1/'
}

# ---------------------------------------------------------------------------
# Case 1 (AC5): the SAME path is a `scripts/selftests/*-selftest.sh` — a shape the
# deleted path heuristic always tagged "create". With modules[].action=modify the
# derived Action must be "modify" (follows the FIELD, contradicting the old path
# heuristic).
# ---------------------------------------------------------------------------
write_refinement "$tmpdir/modify.json" "modify"
out_modify="$tmpdir/task-modify.md"
bash "$DERIVE" --refinement-json "$tmpdir/modify.json" --task-id "DP-901-T1" >"$out_modify" 2>"$tmpdir/modify.err" \
  || fail "case 1 / AC5" "derive failed for modify fixture: $(cat "$tmpdir/modify.err")"
got_modify="$(action_cell_for "$out_modify")"
[[ "$got_modify" == "modify" ]] \
  || fail "case 1 / AC5" "selftest path with modules[].action=modify rendered Action='$got_modify' (expected modify; path heuristic would say create)"

# ---------------------------------------------------------------------------
# Case 2 (AC5): same path, modules[].action=create -> Action="create". The ONLY
# thing changed between case 1 and 2 is the recorded field; the path is byte-equal.
# ---------------------------------------------------------------------------
write_refinement "$tmpdir/create.json" "create"
out_create="$tmpdir/task-create.md"
bash "$DERIVE" --refinement-json "$tmpdir/create.json" --task-id "DP-901-T1" >"$out_create" 2>"$tmpdir/create.err" \
  || fail "case 2 / AC5" "derive failed for create fixture: $(cat "$tmpdir/create.err")"
got_create="$(action_cell_for "$out_create")"
[[ "$got_create" == "create" ]] \
  || fail "case 2 / AC5" "same path with modules[].action=create rendered Action='$got_create' (expected create)"

# Cross-check: the two outputs differ ONLY in the action column for the same path,
# confirming the Action tracks the field, not the path.
[[ "$got_modify" != "$got_create" ]] \
  || fail "case 2 / AC5" "Action did not change between modules[].action=modify and =create (field is not driving it)"

# ---------------------------------------------------------------------------
# Case 3 (AC6): manifest kind drives classification. A root script whose FILENAME
# prefix ('demo-') gives no infra signal but whose manifest kind='gate' must be
# classified as framework infrastructure by BOTH audits — following the field.
# A second script whose name LOOKS like a gate ('gate-looking-...') but whose
# manifest kind='support' must NOT be force-classified as a gate by filename.
# ---------------------------------------------------------------------------
ws="$tmpdir/ws"
mkdir -p "$ws/scripts" "$ws/.claude/skills/demo" "$ws/.claude/hooks"
cat >"$ws/scripts/manifest.json" <<'JSON'
{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/demo-named-but-is-a-gate.sh",
      "kind": "gate",
      "runner": "bash",
      "owner_surface": "skill_or_reference",
      "selftest": "N/A",
      "selftest_reason": "fixture",
      "lifecycle": "hot_path",
      "relocation": "stay"
    },
    {
      "path": "scripts/gate-looking-but-is-support.sh",
      "kind": "support",
      "runner": "bash",
      "owner_surface": "skill_or_reference",
      "selftest": "N/A",
      "selftest_reason": "fixture",
      "lifecycle": "support_path",
      "relocation": "stay"
    }
  ]
}
JSON
for s in demo-named-but-is-a-gate gate-looking-but-is-support; do
  printf '#!/usr/bin/env bash\nset -euo pipefail\n' >"$ws/scripts/${s}.sh"
  chmod +x "$ws/scripts/${s}.sh"
done
# A minimal skill so the audits run their skill/private logic without error.
printf '# Demo Skill\n' >"$ws/.claude/skills/demo/SKILL.md"

# A3: script-ownership-audit.py — kind=gate -> root_contract regardless of name;
# kind=support with a gate-looking name -> NOT root_contract.
audit_json="$tmpdir/script-audit.json"
python3 "$SCRIPT_AUDIT" --root "$ws" --format json >"$audit_json" 2>"$tmpdir/script-audit.err" \
  || fail "case 3 / AC6" "script-ownership-audit.py crashed: $(cat "$tmpdir/script-audit.err")"
gate_class="$(python3 -c "
import json
d=json.load(open('$audit_json'))
by={r['path']:r for r in d['scripts']}
print(by['scripts/demo-named-but-is-a-gate.sh']['classification'])
")"
support_class="$(python3 -c "
import json
d=json.load(open('$audit_json'))
by={r['path']:r for r in d['scripts']}
print(by['scripts/gate-looking-but-is-support.sh']['classification'])
")"
[[ "$gate_class" == "root_contract" ]] \
  || fail "case 3 / AC6" "kind=gate script (demo-named) classified '$gate_class' (expected root_contract — must follow manifest kind, not filename)"
[[ "$support_class" != "root_contract" ]] \
  || fail "case 3 / AC6" "kind=support script with gate-looking name classified root_contract (filename leaked into classification)"

# A2: skill-resource-ownership-audit.sh — kind=gate -> keep_shared root infra with a
# manifest-kind reason; kind=support with gate-looking name does NOT get the
# 'manifest kind=gate' infra reason.
skill_audit_out="$tmpdir/skill-audit.txt"
bash "$SKILL_AUDIT" --root "$ws" >"$skill_audit_out" 2>"$tmpdir/skill-audit.err" \
  || fail "case 3 / AC6" "skill-resource-ownership-audit.sh crashed: $(cat "$tmpdir/skill-audit.err")"
grep -qE 'scripts/demo-named-but-is-a-gate\.sh.*manifest kind=gate' "$skill_audit_out" \
  || fail "case 3 / AC6" "kind=gate script not marked as manifest-kind infra by skill-resource audit"
if grep -E 'scripts/gate-looking-but-is-support\.sh' "$skill_audit_out" | grep -q 'manifest kind=gate'; then
  fail "case 3 / AC6" "kind=support script with gate-looking name wrongly tagged as manifest kind=gate infra"
fi

# ---------------------------------------------------------------------------
# Case 4 (AC-NF1): missing authoritative input is handled deterministically.
#  - derive fail-loud: a refinement missing a required field exits non-zero with a
#    structured 'ERROR:' marker (no silent framework default).
#  - audits degrade safely: a workspace whose manifest.json is absent must not
#    crash either audit (graceful no-kind handling, not a stack trace).
# ---------------------------------------------------------------------------
bad_json="$tmpdir/bad.json"
cat >"$bad_json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-901", "container": "/x", "plan_path": "/x", "jira_key": null },
  "schema_version": 1,
  "modules": [],
  "tasks": [ { "id": "DP-901-T1", "kind": "implementation", "title": "x" } ]
}
JSON
if bash "$DERIVE" --refinement-json "$bad_json" --task-id "DP-901-T1" >/dev/null 2>"$tmpdir/bad.err"; then
  fail "case 4 / AC-NF1" "derive did not fail-loud on a task missing required fields"
fi
grep -qE 'ERROR:' "$tmpdir/bad.err" \
  || fail "case 4 / AC-NF1" "derive fail-loud lacked a structured ERROR marker: $(cat "$tmpdir/bad.err")"

ws_nomani="$tmpdir/ws-nomani"
mkdir -p "$ws_nomani/scripts" "$ws_nomani/.claude/skills/demo"
printf '#!/usr/bin/env bash\nset -euo pipefail\n' >"$ws_nomani/scripts/lonely.sh"
chmod +x "$ws_nomani/scripts/lonely.sh"
printf '# Demo Skill\n' >"$ws_nomani/.claude/skills/demo/SKILL.md"
python3 "$SCRIPT_AUDIT" --root "$ws_nomani" --format json >/dev/null 2>"$tmpdir/nomani-py.err" \
  || fail "case 4 / AC-NF1" "script-ownership-audit.py crashed without manifest.json: $(cat "$tmpdir/nomani-py.err")"
bash "$SKILL_AUDIT" --root "$ws_nomani" >/dev/null 2>"$tmpdir/nomani-sh.err" \
  || fail "case 4 / AC-NF1" "skill-resource-ownership-audit.sh crashed without manifest.json: $(cat "$tmpdir/nomani-sh.err")"

echo "PASS: derive-task-md-action-from-field selftest"
