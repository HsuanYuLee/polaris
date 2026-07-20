#!/usr/bin/env bash
# Purpose: DP-307 T1 (AC1 / AC2 / AC-NEG3 / AC-NEG4) — assert the three branch-slug
#   producers (derive-task-md-from-refinement-json.sh python slugify,
#   engineering-branch-setup.sh bash slugify, resolve-task-branch.sh bash slugify)
#   emit byte-identical ASCII-only slugs for the same inputs, that the pure-ASCII
#   slug is unchanged vs. the pre-DP-307 output, and that an end-to-end derive with
#   a zh-TW title renders a `Task branch` field whose bytes are all < 0x80.
# Inputs:  none (hermetic fixtures constructed in a private mktemp dir)
# Outputs: stdout PASS line on success; FAIL details on stderr
# Exit code: 0 = pass, 1 = fail

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVE_SCRIPT="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"
BRANCH_SETUP_SCRIPT="$ROOT_DIR/scripts/engineering-branch-setup.sh"
RESOLVE_BRANCH_SCRIPT="$ROOT_DIR/scripts/resolve-task-branch.sh"

for required in "$DERIVE_SCRIPT" "$BRANCH_SETUP_SCRIPT" "$RESOLVE_BRANCH_SCRIPT"; do
  [[ -f "$required" ]] || { echo "FAIL: producer script not found: $required" >&2; exit 1; }
done

tmpdir="$(mktemp -d -t branch-slug-parity.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

FAIL=0

# ---------------------------------------------------------------------------
# Producer runners
# ---------------------------------------------------------------------------

# Description: run a bash producer's top-level `slugify()` on one input by
#              extracting the function source and evaluating it in a subshell.
# Args:        $1 = producer script path, $2 = input text
# Side effects: none (subshell-scoped eval)
bash_slug() {
  local script="$1"
  local input="$2"
  (
    eval "$(sed -n '/^slugify() {/,/^}/p' "$script")"
    slugify "$input"
  )
}

# Extract the embedded python `def slugify` from the derive script once, so the
# selftest exercises the real producer source (no second slugify copy).
PY_DRIVER="$tmpdir/python-slug-driver.py"
cat >"$PY_DRIVER" <<'PYEOF'
"""Extract and run the embedded slugify() from derive-task-md-from-refinement-json.sh.

Args (argv): derive script path, input text.
Prints the slug on stdout.
"""
import re
import sys

script_path, input_text = sys.argv[1], sys.argv[2]
lines = open(script_path, encoding="utf-8").read().splitlines()
start = next(
    (i for i, line in enumerate(lines) if line.startswith("def slugify(")), None
)
if start is None:
    sys.stderr.write("FAIL: def slugify not found in derive script\n")
    sys.exit(1)
end = next(
    (i for i, line in enumerate(lines[start:], start) if line.startswith("    return ")),
    None,
)
if end is None:
    sys.stderr.write("FAIL: slugify return statement not found in derive script\n")
    sys.exit(1)
namespace = {"re": re}
exec("\n".join(lines[start : end + 1]), namespace)
print(namespace["slugify"](input_text))
PYEOF

# Description: run the derive script's embedded python slugify on one input.
# Args:        $1 = input text
# Side effects: none
python_slug() {
  local input="$1"
  python3 "$PY_DRIVER" "$DERIVE_SCRIPT" "$input"
}

# ---------------------------------------------------------------------------
# Case 1 (AC1 / AC2): 3-producer byte-identical parity on four input classes,
# each pinned to the canonical engineering-branch-setup output (D2).
#   - CJK + English mix
#   - pure CJK (canonical output is empty; the "task" fallback is call-site
#     behavior, exercised end-to-end in case 3)
#   - mixed punctuation, > 40 chars (exercises `cut -c1-40` truncation parity)
#   - pure ASCII (AC-NEG3: pinned to the pre-DP-307 slug — unchanged)
# ---------------------------------------------------------------------------
inputs=(
  '範例 deterministic derivation'
  '純中文標題'
  'Fix: enforce ASCII_only branch names (canonical slug & hook gate) v2!'
  'derive slugify ascii parity'
)
expected_slugs=(
  'deterministic-derivation'
  ''
  'fix-enforce-ascii-only-branch-names-cano'
  'derive-slugify-ascii-parity'
)

for i in "${!inputs[@]}"; do
  input="${inputs[$i]}"
  expected="${expected_slugs[$i]}"
  setup_out="$(bash_slug "$BRANCH_SETUP_SCRIPT" "$input")"
  resolve_out="$(bash_slug "$RESOLVE_BRANCH_SCRIPT" "$input")"
  derive_out="$(python_slug "$input")"

  if [[ "$setup_out" != "$expected" ]]; then
    echo "FAIL [case 1 / AC1]: engineering-branch-setup slug drifted from pinned canonical" >&2
    echo "  input:    $input" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $setup_out" >&2
    FAIL=1
  fi
  if [[ "$resolve_out" != "$setup_out" ]]; then
    echo "FAIL [case 1 / AC1]: resolve-task-branch slug != engineering-branch-setup slug" >&2
    echo "  input:           $input" >&2
    echo "  branch-setup:    $setup_out" >&2
    echo "  resolve-branch:  $resolve_out" >&2
    FAIL=1
  fi
  if [[ "$derive_out" != "$setup_out" ]]; then
    echo "FAIL [case 1 / AC2]: derive python slug != engineering-branch-setup slug" >&2
    echo "  input:         $input" >&2
    echo "  branch-setup:  $setup_out" >&2
    echo "  derive python: $derive_out" >&2
    FAIL=1
  fi
done

# AC-NEG3 explicit pin: the pure-ASCII slug is byte-identical to the pre-DP-307
# derive output for the same title (no regression on ASCII-only titles).
ascii_regression="$(python_slug 'derive slugify ascii parity')"
if [[ "$ascii_regression" != 'derive-slugify-ascii-parity' ]]; then
  echo "FAIL [case 1 / AC-NEG3]: pure-ASCII slug changed vs pre-DP-307 output" >&2
  echo "  expected: derive-slugify-ascii-parity" >&2
  echo "  actual:   $ascii_regression" >&2
  FAIL=1
fi

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
echo "PASS [case 1]: 3-producer slug parity holds on all four input classes"

# ---------------------------------------------------------------------------
# Helper: write a minimal valid refinement.json fixture with the given title.
# Args: $1 = output path, $2 = source id, $3 = task title
# ---------------------------------------------------------------------------
write_refinement_fixture() {
  local out="$1"
  local source_id="$2"
  local title="$3"
  python3 - "$out" "$source_id" "$title" <<'PYEOF'
import json
import sys

out, source_id, title = sys.argv[1], sys.argv[2], sys.argv[3]
fixture = {
    "source": {
        "type": "dp",
        "id": source_id,
        "container": f"/tmp/{source_id.lower()}-fixture",
        "plan_path": f"/tmp/{source_id.lower()}-fixture/index.md",
        "jira_key": None,
    },
    "schema_version": 1,
    "tasks": [
        {
            "id": f"{source_id}-T1",
            "kind": "implementation",
            "title": title,
            "scope": "branch-slug parity selftest fixture",
            "allowed_files": ["scripts/sample.sh"],
            "modules": ["scripts/sample.sh"],
            "ac_ids": ["AC1"],
            "dependencies": [],
            "estimate_points": 1,
            "verification": {
                "method": "unit_test",
                "detail": "bash scripts/selftests/sample-selftest.sh",
                "verify_command": "bash scripts/selftests/sample-selftest.sh",
                "behavior_contract": {
                    "applies": False,
                    "reason": "selftest fixture; no runtime behavior",
                },
                "test_environment": {"level": "static"},
                "references": ["scripts/sample.sh"],
            },
        }
    ],
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(fixture, fh, ensure_ascii=False, indent=1)
PYEOF
}

# ---------------------------------------------------------------------------
# Helper: write a minimal valid JIRA-Epic-backed refinement.json fixture
# (source.type=jira) whose task carries a real per-task jira_key that DIFFERS
# from the composite work_item_id ({source_id}-Tn). This is the case the
# DP-backed helper above cannot exercise: there task_id == identity because
# jira_key is None. Generic placeholders only (EXCO / exampleco-web) — this
# selftest is a template-synced surface (framework-iteration § Template-Facing
# Examples Must Be Generic).
# Args: $1 = output path, $2 = epic id, $3 = task title, $4 = per-task jira_key
# ---------------------------------------------------------------------------
write_jira_refinement_fixture() {
  local out="$1"
  local epic_id="$2"
  local title="$3"
  local jira_key="$4"
  python3 - "$out" "$epic_id" "$title" "$jira_key" <<'PYEOF'
import json
import sys

out, epic_id, title, jira_key = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
fixture = {
    "source": {
        "type": "jira",
        "id": epic_id,
        "container": f"/tmp/{epic_id.lower()}-fixture",
        "plan_path": f"/tmp/{epic_id.lower()}-fixture/index.md",
        "repo": "exampleco-web",
        "base_branch": "develop",
    },
    "schema_version": 1,
    "tasks": [
        {
            "id": f"{epic_id}-T1",
            "kind": "implementation",
            "title": title,
            "scope": "jira-epic branch identity parity selftest fixture",
            "allowed_files": ["scripts/sample.sh"],
            "modules": ["scripts/sample.sh"],
            "ac_ids": ["AC1"],
            "dependencies": [],
            "estimate_points": 1,
            "jira_key": jira_key,
            "verification": {
                "method": "unit_test",
                "detail": "bash scripts/selftests/sample-selftest.sh",
                "verify_command": "bash scripts/selftests/sample-selftest.sh",
                "behavior_contract": {
                    "applies": False,
                    "reason": "selftest fixture; no runtime behavior",
                },
                "test_environment": {"level": "static"},
                "references": ["scripts/sample.sh"],
            },
        }
    ],
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(fixture, fh, ensure_ascii=False, indent=1)
PYEOF
}

# ---------------------------------------------------------------------------
# Case 2 (AC-NEG4): end-to-end derive with a zh-TW title — the rendered
# `Task branch` field must be pure ASCII (every byte < 0x80) and must keep the
# ASCII tokens from the title.
# ---------------------------------------------------------------------------
zhtw_json="$tmpdir/refinement-zhtw.json"
write_refinement_fixture "$zhtw_json" "DP-901" '驗證 ASCII slug 行為'
zhtw_out="$tmpdir/zhtw-task.md"
bash "$DERIVE_SCRIPT" --refinement-json "$zhtw_json" --task-id "DP-901-T1" >"$zhtw_out"

zhtw_row="$(grep -F '| Task branch |' "$zhtw_out")"
if LC_ALL=C grep -q '[^ -~]' <<< "$zhtw_row"; then
  echo "FAIL [case 2 / AC-NEG4]: Task branch row contains non-ASCII bytes" >&2
  printf '%s\n' "$zhtw_row" >&2
  exit 1
fi
if ! grep -qF 'task/DP-901-T1-ascii-slug' <<< "$zhtw_row"; then
  echo "FAIL [case 2 / AC-NEG4]: unexpected zh-TW title branch slug" >&2
  echo "  expected branch: task/DP-901-T1-ascii-slug" >&2
  printf '  actual row: %s\n' "$zhtw_row" >&2
  exit 1
fi
echo "PASS [case 2]: zh-TW title derives a pure-ASCII Task branch field"

# ---------------------------------------------------------------------------
# Case 3 (AC2 fallback): a pure-CJK title slugifies to empty at the producer
# level (canonical bash behavior) and the derive call site falls back to the
# literal "task" slug, keeping the branch non-empty and pure ASCII.
# ---------------------------------------------------------------------------
cjk_json="$tmpdir/refinement-cjk.json"
write_refinement_fixture "$cjk_json" "DP-902" '純中文標題'
cjk_out="$tmpdir/cjk-task.md"
bash "$DERIVE_SCRIPT" --refinement-json "$cjk_json" --task-id "DP-902-T1" >"$cjk_out"

cjk_row="$(grep -F '| Task branch |' "$cjk_out")"
if LC_ALL=C grep -q '[^ -~]' <<< "$cjk_row"; then
  echo "FAIL [case 3 / AC-NEG4]: pure-CJK title Task branch row contains non-ASCII bytes" >&2
  printf '%s\n' "$cjk_row" >&2
  exit 1
fi
if ! grep -qF 'task/DP-902-T1-task' <<< "$cjk_row"; then
  echo "FAIL [case 3 / AC2]: pure-CJK title did not fall back to the 'task' slug" >&2
  printf '  actual row: %s\n' "$cjk_row" >&2
  exit 1
fi
echo "PASS [case 3]: pure-CJK title falls back to the pure-ASCII 'task' slug"

# ---------------------------------------------------------------------------
# Case 4 (DP-328 AC1 / AC3): JIRA-Epic-backed parity. The derived branch must
# use the per-task delivery jira_key (EXCO-712), NOT the composite work_item_id
# (EXCO-700-T1). This is the dual-source half the DP-backed cases above cannot
# reach: there task_id == identity, so a producer that mistakenly emitted
# task/{task_id}-... still resolved. Here jira_key != work_item_id, so the
# composite leak is observable, and the derived branch is fed to the canonical
# resolve-task-branch.sh invariant (no second branch-identity rule).
# Regression guard: reverting the producer to f"task/{task_id}-{slug}" makes
# both the string assertion and the resolve-task-branch.sh check FAIL.
# ---------------------------------------------------------------------------
jira_json="$tmpdir/refinement-jira.json"
write_jira_refinement_fixture "$jira_json" "EXCO-700" 'jira epic branch identity parity' "EXCO-712"
jira_out="$tmpdir/jira-task.md"
bash "$DERIVE_SCRIPT" --refinement-json "$jira_json" --task-id "EXCO-700-T1" >"$jira_out"

jira_row="$(grep -F '| Task branch |' "$jira_out")"
expected_jira_branch='task/EXCO-712-jira-epic-branch-identity-parity'
if LC_ALL=C grep -q '[^ -~]' <<< "$jira_row"; then
  echo "FAIL [case 4 / AC1]: JIRA-Epic Task branch row contains non-ASCII bytes" >&2
  printf '%s\n' "$jira_row" >&2
  exit 1
fi
if ! grep -qF "$expected_jira_branch" <<< "$jira_row"; then
  echo "FAIL [case 4 / AC1]: derived branch did not use per-task jira_key identity" >&2
  echo "  expected branch: $expected_jira_branch" >&2
  printf '  actual row: %s\n' "$jira_row" >&2
  exit 1
fi
# Explicit composite-leak guard: the internal work_item_id must never appear as
# the branch prefix (this is exactly what the producer bug emitted).
if grep -qF 'task/EXCO-700-T1-' <<< "$jira_row"; then
  echo "FAIL [case 4 / AC1]: derived branch leaked the composite work_item_id (EXCO-700-T1)" >&2
  printf '  actual row: %s\n' "$jira_row" >&2
  exit 1
fi

# The derived task.md must satisfy the canonical resolve-task-branch.sh
# invariant (delivery_ticket_key prefix, AC-NEG5 no-leak) — reuse, no 2nd rule.
if ! bash "$RESOLVE_BRANCH_SCRIPT" "$jira_out" >/dev/null 2>&1; then
  echo "FAIL [case 4 / AC3]: derived JIRA-Epic task.md branch rejected by resolve-task-branch.sh" >&2
  printf '%s\n' "$jira_row" >&2
  bash "$RESOLVE_BRANCH_SCRIPT" "$jira_out" >/dev/null || true
  exit 1
fi
echo "PASS [case 4]: JIRA-Epic derive uses jira_key identity and passes resolve-task-branch.sh"

echo "PASS: branch-slug-producer-parity-selftest"
