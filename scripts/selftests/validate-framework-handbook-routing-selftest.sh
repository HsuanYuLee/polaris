#!/usr/bin/env bash
set -euo pipefail

# Purpose: selftest for validate-framework-handbook-routing.sh (DP-240-T8 / AC10).
#
# Inputs: tmpdir-backed fixture lists per scenario.
# Outputs: TAP-like assertion log to stdout; non-zero exit if any case fails.
# Side effects: creates and tears down a single tmpdir under $TMPDIR.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-framework-handbook-routing.sh"
TMPROOT="$(mktemp -d -t framework-handbook-routing-selftest-XXXXXX)"
PASS=0
TOTAL=0

cleanup() {
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

[[ -x "$VALIDATOR" ]] || chmod +x "$VALIDATOR" 2>/dev/null || true

assert_rc() {
  local label="$1" got="$2" want="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: got rc=%s want rc=%s\n' "$label" "$got" "$want" >&2
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: missing %q in output\n%s\n' "$label" "$needle" "$haystack" >&2
  fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: unexpected %q in output\n%s\n' "$label" "$needle" "$haystack" >&2
  fi
}

# Fixture 1: framework-owned hit via .claude/**
fixture_claude="$TMPROOT/fixture-claude.txt"
cat > "$fixture_claude" <<'EOF'
.claude/rules/skill-routing.md
.claude/skills/engineering/SKILL.md
.claude/hooks/pre-memory-write.sh
EOF

# Fixture 2: framework-owned hit via scripts/**
fixture_scripts="$TMPROOT/fixture-scripts.txt"
cat > "$fixture_scripts" <<'EOF'
scripts/validate-mise-dependency-change.sh
scripts/gates/gate-pr-body-template.sh
scripts/selftests/foo-selftest.sh
EOF

# Fixture 3: framework-owned hit via docs-manager DP-* spec source
fixture_dp_source="$TMPROOT/fixture-dp-source.txt"
cat > "$fixture_dp_source" <<'EOF'
docs-manager/src/content/docs/specs/design-plans/DP-240-foo/index.md
docs-manager/src/content/docs/specs/design-plans/DP-240-foo/tasks/T1/index.md
EOF

# Fixture 4: product repo paths only (NOT framework-owned)
fixture_product="$TMPROOT/fixture-product.txt"
cat > "$fixture_product" <<'EOF'
exampleco/polaris-config/exampleco-web/handbook/index.md
exampleco/polaris-config/exampleco-web/generated-scripts/ci-local.sh
src/components/Foo.vue
src/pages/index.vue
EOF

# Fixture 5: mixed hit (both surfaces)
fixture_mixed="$TMPROOT/fixture-mixed.txt"
cat > "$fixture_mixed" <<'EOF'
.claude/rules/skill-routing.md
exampleco/polaris-config/exampleco-web/handbook/index.md
src/Foo.vue
EOF

# Fixture 6: framework configuration surface (mise.toml / workspace-config.yaml /
# .claude/instructions/manifest.yaml / root runtime targets)
fixture_config="$TMPROOT/fixture-config.txt"
cat > "$fixture_config" <<'EOF'
mise.toml
workspace-config.yaml
.claude/instructions/manifest.yaml
CLAUDE.md
AGENTS.md
.codex/AGENTS.md
.github/copilot-instructions.md
EOF

# Fixture 7: template scaffolding (treated as product/excluded surface)
fixture_template="$TMPROOT/fixture-template.txt"
cat > "$fixture_template" <<'EOF'
_template/rule-examples/foo.md
_template/skill-template/SKILL.md
EOF

# Fixture 8: empty file (no candidates → unclassified empty)
fixture_empty="$TMPROOT/fixture-empty.txt"
: > "$fixture_empty"

# Case 1: .claude/** files → framework_handbook_required=true
set +e
out="$("$VALIDATOR" --changed-files "$fixture_claude" 2>&1)"
rc=$?
set -e
assert_rc "T8: .claude/** changes exit 0" "$rc" "0"
assert_contains "T8: .claude/** triggers framework_handbook_required=true" "$out" '"framework_handbook_required":true'
assert_contains "T8: .claude/** lists skill-routing.md" "$out" "skill-routing.md"

# Case 2: scripts/** changes → framework_handbook_required=true
set +e
out="$("$VALIDATOR" --changed-files "$fixture_scripts" 2>&1)"
rc=$?
set -e
assert_rc "T8: scripts/** changes exit 0" "$rc" "0"
assert_contains "T8: scripts/** triggers handbook" "$out" '"framework_handbook_required":true'
assert_contains "T8: scripts/** lists validator" "$out" "validate-mise-dependency-change.sh"

# Case 3: docs-manager DP source path → framework_handbook_required=true
set +e
out="$("$VALIDATOR" --changed-files "$fixture_dp_source" 2>&1)"
rc=$?
set -e
assert_rc "T8: DP source changes exit 0" "$rc" "0"
assert_contains "T8: DP source triggers handbook" "$out" '"framework_handbook_required":true'
assert_contains "T8: DP source lists task path" "$out" "DP-240-foo"

# Case 4: product repo path only → framework_handbook_required=false
set +e
out="$("$VALIDATOR" --changed-files "$fixture_product" 2>&1)"
rc=$?
set -e
assert_rc "T8: product-only changes exit 0" "$rc" "0"
assert_contains "T8: product-only framework_handbook_required=false" "$out" '"framework_handbook_required":false'
assert_contains "T8: product-only paths captured" "$out" "polaris-config/exampleco-web/handbook"
assert_not_contains "T8: product-only does NOT mis-route framework_owned_hits" "$out" '"framework_owned_hits":[".claude'

# Case 5: mixed hit → framework_handbook_required=true AND product_repo_paths populated
set +e
out="$("$VALIDATOR" --changed-files "$fixture_mixed" 2>&1)"
rc=$?
set -e
assert_rc "T8: mixed changes exit 0" "$rc" "0"
assert_contains "T8: mixed framework_handbook_required=true" "$out" '"framework_handbook_required":true'
assert_contains "T8: mixed lists framework hit" "$out" '.claude/rules/skill-routing.md'
assert_contains "T8: mixed lists product path" "$out" "polaris-config/exampleco-web/handbook"

# Case 6: configuration surface files trigger handbook
set +e
out="$("$VALIDATOR" --changed-files "$fixture_config" 2>&1)"
rc=$?
set -e
assert_rc "T8: config-surface changes exit 0" "$rc" "0"
assert_contains "T8: config-surface triggers handbook" "$out" '"framework_handbook_required":true'
assert_contains "T8: config-surface lists mise.toml" "$out" '"mise.toml"'
assert_contains "T8: config-surface lists workspace-config" "$out" '"workspace-config.yaml"'
assert_contains "T8: config-surface lists CLAUDE.md" "$out" '"CLAUDE.md"'
assert_contains "T8: config-surface lists .codex" "$out" '.codex/AGENTS.md'
assert_contains "T8: config-surface lists copilot" "$out" 'copilot-instructions.md'

# Case 7: template scaffolding routed as product/excluded
set +e
out="$("$VALIDATOR" --changed-files "$fixture_template" 2>&1)"
rc=$?
set -e
assert_rc "T8: template changes exit 0" "$rc" "0"
assert_contains "T8: template does NOT require framework handbook" "$out" '"framework_handbook_required":false'
assert_contains "T8: template path classified as product" "$out" '"product_repo_paths":["_template/rule-examples/foo.md"'

# Case 8: empty file → no candidates, both arrays empty, required=false
set +e
out="$("$VALIDATOR" --changed-files "$fixture_empty" 2>&1)"
rc=$?
set -e
assert_rc "T8: empty changes exit 0" "$rc" "0"
assert_contains "T8: empty framework_handbook_required=false" "$out" '"framework_handbook_required":false'
assert_contains "T8: empty hits array" "$out" '"framework_owned_hits":[]'

# Case 9: --file repeatable, single explicit path
set +e
out="$("$VALIDATOR" --file ".claude/rules/foo.md" --file "src/components/Foo.vue" 2>&1)"
rc=$?
set -e
assert_rc "T8: --file repeatable exit 0" "$rc" "0"
assert_contains "T8: --file framework hit captured" "$out" '.claude/rules/foo.md'
assert_contains "T8: --file unclassified captured" "$out" '"unclassified":["src/components/Foo.vue"]'

# Case 10: deduplication (same path supplied twice)
dedup_file="$TMPROOT/dedup.txt"
cat > "$dedup_file" <<'EOF'
.claude/rules/skill-routing.md
.claude/rules/skill-routing.md
./.claude/rules/skill-routing.md
EOF
set +e
out="$("$VALIDATOR" --changed-files "$dedup_file" 2>&1)"
rc=$?
set -e
assert_rc "T8: dedup exit 0" "$rc" "0"
# Count occurrences of the path within "framework_owned_hits"
hits_count="$(printf '%s' "$out" | grep -o 'skill-routing\.md' | wc -l | tr -d ' ')"
TOTAL=$((TOTAL + 1))
if [[ "$hits_count" == "1" ]]; then
  PASS=$((PASS + 1))
  printf 'ok T8: dedup keeps single instance\n'
else
  printf 'not ok T8: dedup expected 1 hit, got %s\n%s\n' "$hits_count" "$out" >&2
fi

# Case 11: --mode diff emits stderr observability line
set +e
out_stderr="$("$VALIDATOR" --changed-files "$fixture_claude" --mode diff 2>&1 >/dev/null)"
rc=$?
set -e
assert_rc "T8: --mode diff exit 0" "$rc" "0"
assert_contains "T8: --mode diff stderr mentions handbook" "$out_stderr" "handbook/framework/index.md"

# Case 12: missing --changed-files path → BLOCK
set +e
out="$("$VALIDATOR" --changed-files "$TMPROOT/does-not-exist.txt" 2>&1)"
rc=$?
set -e
assert_rc "T8: missing --changed-files blocks" "$rc" "2"
assert_contains "T8: missing path error" "$out" "does not exist"

# Case 13: no --changed-files / --file supplied → BLOCK
set +e
out="$("$VALIDATOR" 2>&1)"
rc=$?
set -e
assert_rc "T8: no input blocks" "$rc" "2"
assert_contains "T8: no input error" "$out" "at least one"

# Case 14: invalid --mode value → BLOCK
set +e
out="$("$VALIDATOR" --changed-files "$fixture_claude" --mode bogus 2>&1)"
rc=$?
set -e
assert_rc "T8: invalid --mode blocks" "$rc" "2"
assert_contains "T8: invalid --mode error" "$out" "must be 'verdict' or 'diff'"

# Case 15: --help exits 0
set +e
out="$("$VALIDATOR" --help 2>&1)"
rc=$?
set -e
assert_rc "T8: --help exit 0" "$rc" "0"
assert_contains "T8: --help shows usage" "$out" "Usage:"

printf '\n=== validate-framework-handbook-routing selftest: %d/%d PASS ===\n' "$PASS" "$TOTAL"
[[ "$PASS" -eq "$TOTAL" ]]
