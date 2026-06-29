#!/usr/bin/env bash
# Purpose: Assert .claude/skills/references/refinement-artifact.md documents the
#          behavior_contract applies=true schema in parity with the actual
#          derive enforcement in scripts/derive-task-md-from-refinement-json.sh.
#          Direction is doc->enforcement (DP-335 AC2 / AC-NEG3): the doc must
#          list every applies=true fail-loud sub-field the derive script
#          requires, plus the conditional requirements and the viewport: mobile
#          example. Missing any enforced sub-field => FAIL.
# Inputs:  none (reads repo files relative to git toplevel).
# Outputs: PASS line + exit 0 when the doc is in parity; exit 1 + a FAIL line
#          naming the missing sub-field otherwise. Side effects: none (read-only;
#          mktemp scratch only).
set -euo pipefail

ROOT_DIR="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
DOC="$ROOT_DIR/.claude/skills/references/refinement-artifact.md"
DERIVE="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$DOC" ]] || fail "doc not found: $DOC"
[[ -f "$DERIVE" ]] || fail "derive script not found: $DERIVE"

# --- Source of truth: the unconditional applies=true required sub-fields are
# the bc_require("<field>") calls in the derive script's bc_applies block. We
# extract them directly from the derive script so the parity set never drifts
# from enforcement (if derive adds/removes a bc_require, this selftest updates
# its expectation automatically). ---
# Portable array fill (host bash is 3.2; no mapfile/readarray).
required_fields=()
while IFS= read -r _field; do
  [[ -n "$_field" ]] && required_fields+=("$_field")
done < <(
  grep -oE 'bc_require\("[a-z_]+"\)' "$DERIVE" \
    | sed -E 's/bc_require\("([a-z_]+)"\)/\1/' \
    | sort -u
)

if [[ ${#required_fields[@]} -eq 0 ]]; then
  fail "no bc_require() fields found in derive script — enforcement extraction broke"
fi

# Sanity: the documented DP-335 contract expects these to be present. If derive
# ever drops one of the five canonical fields, this guards against a silently
# shrunk parity set passing vacuously.
for canonical in mode source_of_truth fixture_policy flow; do
  found=0
  for f in "${required_fields[@]}"; do
    [[ "$f" == "$canonical" ]] && found=1 && break
  done
  [[ "$found" -eq 1 ]] || fail "derive no longer requires '$canonical' via bc_require — extraction or enforcement changed; review DP-335 AC-NEG3"
done

# Read the doc once.
doc_text="$(cat "$DOC")"

assert_doc_contains() {
  local needle="$1"
  local label="$2"
  if ! printf '%s' "$doc_text" | grep -qF -- "$needle"; then
    fail "refinement-artifact.md does not document enforced $label ('$needle' missing) — doc is laxer than derive enforcement (DP-335 AC2)"
  fi
}

# 1. Every unconditional bc_require() sub-field must appear literally in the doc.
for f in "${required_fields[@]}"; do
  assert_doc_contains "$f" "applies=true sub-field"
done

# 2. The non-empty assertions[] requirement (enforced separately from bc_require,
# derive: "requires a non-empty 'assertions' list").
assert_doc_contains "assertions" "applies=true non-empty assertions[] requirement"

# 3. Conditional: fixture_policy=mockoon_required -> flow_script.
assert_doc_contains "mockoon_required" "conditional fixture_policy=mockoon_required"
assert_doc_contains "flow_script" "conditional flow_script requirement"

# 4. Conditional: mode=hybrid -> allowed_differences.
assert_doc_contains "hybrid" "conditional mode=hybrid"
assert_doc_contains "allowed_differences" "conditional allowed_differences requirement"

# 5. Mobile UI declaration example: viewport: mobile.
assert_doc_contains "viewport: mobile" "mobile UI viewport example"

echo "PASS: refinement-artifact.md behavior_contract applies=true schema is in parity with derive enforcement (${#required_fields[@]} required sub-fields + conditionals + viewport: mobile)"
