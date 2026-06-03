#!/usr/bin/env bash
# memory-hygiene-validator-nested-frontmatter-selftest.sh — DP-213 validator + chain contract.
#
# Verifies:
#   - validator does NOT fail-stop on nested_frontmatter flag (AC3).
#   - validator surfaces nested_frontmatter in warnings section (AC-NEG3).
#   - canonical chain `dry-run --json | validate | apply` walks through
#     without POLARIS_MEMORY_HYGIENE_APPLY bypass (AC4).

set -euo pipefail

REPO="${REPO:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
TIERING="$REPO/scripts/memory-hygiene-tiering.py"
VALIDATOR="$REPO/scripts/validate-memory-hygiene-plan.sh"

WORK="$(mktemp -d -t mh-validator-XXXX)"
trap 'rm -rf "$WORK"' EXIT

MEMORY_DIR="$WORK/memory"
mkdir -p "$MEMORY_DIR"

# Two entries: one normal, one with nested metadata: block (flagged)
cat >"$MEMORY_DIR/normal_01.md" <<'EOF'
---
name: normal-01
description: normal entry
type: feedback
last_triggered: 2026-05-20
trigger_count: 3
created: 2026-05-01
---
body
EOF

cat >"$MEMORY_DIR/nested_01.md" <<'EOF'
---
name: nested-01
description: entry with nested metadata block
type: feedback
last_triggered: 2026-05-20
trigger_count: 2
created: 2026-05-01
metadata:
  type: feedback
  topic: validator-test
---
body
EOF

printf '# Memory Index\n\n' >"$MEMORY_DIR/MEMORY.md"

# AC3: validator exit code MUST be 0 even when nested_frontmatter true
plan_json="$WORK/plan.json"
python3 "$TIERING" dry-run --json --memory-dir "$MEMORY_DIR" >"$plan_json"

# Sanity: plan should have nested_frontmatter flag set on nested_01.md
nested_flag="$(python3 -c "import json; d=json.load(open('$plan_json')); print([c['flags'].get('nested_frontmatter') for c in d['classifications'] if c['file']=='nested_01.md'][0])")"
if [[ "$nested_flag" != "True" ]]; then
  echo "FAIL: plan did not flag nested_frontmatter on nested_01.md (got $nested_flag)" >&2
  exit 1
fi

# AC3: validator exits 0
# DP-277 T2: verdict (--format json) now goes to STDERR; stdout is the plan
# pass-through. Read the JSON verdict from stderr.
validator_exit=0
"$VALIDATOR" --input "$plan_json" --format json >"$WORK/validator.out" 2>"$WORK/validator.err" || validator_exit=$?
if [[ "$validator_exit" -ne 0 ]]; then
  echo "FAIL: validator exited $validator_exit (expected 0; AC3)" >&2
  cat "$WORK/validator.err" >&2
  exit 1
fi

# AC-NEG3: warnings array (verdict on stderr) must contain nested_frontmatter for nested_01.md
nested_in_warnings="$(python3 -c "import json; d=json.load(open('$WORK/validator.err')); print(any(w['code']=='nested_frontmatter' and w['detail']=='nested_01.md' for w in d.get('warnings', [])))")"
if [[ "$nested_in_warnings" != "True" ]]; then
  echo "FAIL: validator warnings missing nested_frontmatter entry for nested_01.md (AC-NEG3)" >&2
  cat "$WORK/validator.err" >&2
  exit 1
fi

# AC-NEG3: validator must NOT silently strip the signal — issues array should not contain nested_frontmatter
issues_has_nested="$(python3 -c "import json; d=json.load(open('$WORK/validator.err')); print(any(i['code']=='nested_frontmatter' for i in d.get('issues', [])))")"
if [[ "$issues_has_nested" == "True" ]]; then
  echo "FAIL: validator issues should not contain nested_frontmatter (now warnings-only; AC-NEG3)" >&2
  exit 1
fi

# AC4: full chain dry-run | validate | apply with no env bypass
# Confirm POLARIS_MEMORY_HYGIENE_APPLY is not set in this env
if [[ -n "${POLARIS_MEMORY_HYGIENE_APPLY:-}" ]]; then
  echo "FAIL: POLARIS_MEMORY_HYGIENE_APPLY is set in current env — chain must run without bypass" >&2
  exit 1
fi

# Run apply (consumes plan_json from disk via stdin)
python3 "$TIERING" apply --memory-dir "$MEMORY_DIR" <"$plan_json" >"$WORK/apply.out" 2>&1 || {
  echo "FAIL: apply chain failed without env bypass (AC4)" >&2
  cat "$WORK/apply.out" >&2
  exit 1
}

# Verify apply normalized nested metadata (the nested file should no longer have `metadata:` line)
if grep -q "^metadata:$" "$MEMORY_DIR/nested_01.md"; then
  echo "FAIL: apply did not normalize nested metadata block" >&2
  exit 1
fi

echo "PASS: DP-213 validator nested_frontmatter chain selftest"
