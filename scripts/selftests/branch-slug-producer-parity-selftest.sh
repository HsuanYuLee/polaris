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
# Case 2 (AC-NEG4): end-to-end derive with a zh-TW title — the rendered
# `Task branch` field must be pure ASCII (every byte < 0x80) and must keep the
# ASCII tokens from the title.
# ---------------------------------------------------------------------------
zhtw_json="$tmpdir/refinement-zhtw.json"
write_refinement_fixture "$zhtw_json" "DP-901" '驗證 ASCII slug 行為'
zhtw_out="$tmpdir/zhtw-task.md"
bash "$DERIVE_SCRIPT" --refinement-json "$zhtw_json" --task-id "DP-901-T1" >"$zhtw_out"

zhtw_row="$(grep -F '| Task branch |' "$zhtw_out")"
if printf '%s' "$zhtw_row" | LC_ALL=C grep -q '[^ -~]'; then
  echo "FAIL [case 2 / AC-NEG4]: Task branch row contains non-ASCII bytes" >&2
  printf '%s\n' "$zhtw_row" >&2
  exit 1
fi
if ! printf '%s' "$zhtw_row" | grep -qF 'task/DP-901-T1-ascii-slug'; then
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
if printf '%s' "$cjk_row" | LC_ALL=C grep -q '[^ -~]'; then
  echo "FAIL [case 3 / AC-NEG4]: pure-CJK title Task branch row contains non-ASCII bytes" >&2
  printf '%s\n' "$cjk_row" >&2
  exit 1
fi
if ! printf '%s' "$cjk_row" | grep -qF 'task/DP-902-T1-task'; then
  echo "FAIL [case 3 / AC2]: pure-CJK title did not fall back to the 'task' slug" >&2
  printf '  actual row: %s\n' "$cjk_row" >&2
  exit 1
fi
echo "PASS [case 3]: pure-CJK title falls back to the pure-ASCII 'task' slug"

echo "PASS: branch-slug-producer-parity-selftest"
