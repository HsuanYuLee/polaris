#!/usr/bin/env bash
set -euo pipefail

# scripts/gate-pr-body-template-selftest.sh — selftest for gate-pr-body-template.sh

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$SCRIPT_DIR/gates/gate-pr-body-template.sh"
TMPROOT="$(mktemp -d -t pr-body-template-selftest-XXXXXX)"
PASS=0
TOTAL=0

cleanup() {
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

assert_rc() {
  local label="$1"
  local got="$2"
  local want="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: got rc=%s want rc=%s\n' "$label" "$got" "$want" >&2
  fi
}

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: missing %q\n' "$label" "$needle" >&2
  fi
}

repo="$TMPROOT/repo"
mkdir -p "$repo/.github"
cat > "$repo/.github/pull_request_template.md" <<'EOF'
## Description

<!-- What changed -->

## Changed

<!-- Technical changes -->

## Screenshots (Test Plan)

<!-- Evidence -->

## Related documents

<!-- Links -->

## QA notes

<!-- QA -->
EOF

valid_body="$TMPROOT/valid.md"
cat > "$valid_body" <<'EOF'
## Description

Implement the scoped change.

## Changed

- Updated one file.

## Evidence Summary

| Layer | Status |
|-------|--------|
| A | PASS |

## Screenshots (Test Plan)

- Unit tests pass.

## Related documents

- JIRA: DEMO-1

## QA notes

- N/A
EOF

bad_body="$TMPROOT/bad.md"
cat > "$bad_body" <<'EOF'
## Summary

- Implemented the scoped change.

## Verification

- Tests pass.
EOF

escaped_body="$TMPROOT/escaped.md"
cat > "$escaped_body" <<'EOF'
## Description

\`apps/main/package.json\`

## Changed

- Updated one file.

## Screenshots (Test Plan)

- Unit tests pass.

## Related documents

- JIRA: DEMO-1

## QA notes

- N/A
EOF

mockbin="$TMPROOT/bin"
mkdir -p "$mockbin"
cat > "$mockbin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1 \$2" == "pr view" ]]; then
  cat "$valid_body"
  exit 0
fi
echo "unexpected gh call: \$*" >&2
exit 1
EOF
chmod +x "$mockbin/gh"

set +e
out="$("$GATE" --repo "$repo" --body-file "$valid_body" 2>&1)"
rc=$?
set -e
assert_rc "valid body passes" "$rc" "0"
assert_contains "valid message" "$out" "preserves repo template headings"

set +e
out="$("$GATE" --repo "$repo" --body-file "$bad_body" 2>&1)"
rc=$?
set -e
assert_rc "summary body blocks" "$rc" "2"
assert_contains "summary body missing template" "$out" "Description"

set +e
out="$("$GATE" --repo "$repo" --body-file "$escaped_body" 2>&1)"
rc=$?
set -e
assert_rc "escaped backtick blocks" "$rc" "2"
assert_contains "escaped backtick message" "$out" "escaped Markdown backticks"

set +e
out="$(PATH="$mockbin:$PATH" "$GATE" --repo "$repo" --pr "https://github.com/demo/example/pull/1" 2>&1)"
rc=$?
set -e
assert_rc "remote pr body source passes" "$rc" "0"
assert_contains "remote pr source message" "$out" "preserves repo template headings"

# DP-217 regression: body with zero h2 headings must BLOCK without emitting a
# bash "unbound variable" diagnostic under set -u. The empty body_headings
# array previously triggered a "${body_headings[@]}: unbound variable" error.
no_heading_body="$TMPROOT/no-headings.md"
cat > "$no_heading_body" <<'EOF'
This PR body forgot to include any level-2 headings at all.
It is just a paragraph of text describing what changed.
EOF

set +e
out="$("$GATE" --repo "$repo" --body-file "$no_heading_body" 2>&1)"
rc=$?
set -e
assert_rc "empty body_headings blocks" "$rc" "2"
TOTAL=$((TOTAL + 1))
if [[ "$out" == *"unbound variable"* ]]; then
  printf 'not ok DP-217: gate emitted unbound-variable diagnostic\n%s\n' "$out" >&2
else
  PASS=$((PASS + 1))
  printf 'ok DP-217: no unbound-variable diagnostic\n'
fi
assert_contains "no-heading body lists missing headings" "$out" "(none)"

# DP-240-T6 / AC9 — Script reuse justification fixtures.
#
# Body that satisfies template headings AND includes the reuse-justification
# section (used when --added-files lists a new root-level script).
reuse_ok_body="$TMPROOT/reuse-ok.md"
cat > "$reuse_ok_body" <<'EOF'
## Description

Add a new helper script.

## Changed

- Added scripts/new-helper.sh.

## Script reuse justification

Existing helpers were evaluated and do not cover the new contract; see DP-240 notes.

## Screenshots (Test Plan)

- Selftest passes.

## Related documents

- JIRA: DEMO-1

## QA notes

- N/A
EOF

# Same body without the reuse-justification section (still passes template
# heading check) — must BLOCK when added-files lists a new root script.
reuse_missing_body="$TMPROOT/reuse-missing.md"
cat > "$reuse_missing_body" <<'EOF'
## Description

Add a new helper script.

## Changed

- Added scripts/new-helper.sh.

## Screenshots (Test Plan)

- Selftest passes.

## Related documents

- JIRA: DEMO-1

## QA notes

- N/A
EOF

added_new_root_script="$TMPROOT/added-new-root-script.txt"
printf 'scripts/new-helper.sh\n' > "$added_new_root_script"

added_modified_only="$TMPROOT/added-modified-only.txt"
# Empty file (no newly-added paths) — modifying an existing script should not
# trigger the reuse-justification gate.
: > "$added_modified_only"

added_subdir_only="$TMPROOT/added-subdir-only.txt"
# New scripts under a subdirectory (gates/, selftests/, lib/) are not the
# "root-level helper" surface; they should NOT trigger the gate.
cat > "$added_subdir_only" <<'EOF'
scripts/gates/gate-new.sh
scripts/selftests/foo-selftest.sh
scripts/lib/helper.sh
EOF

added_python_root="$TMPROOT/added-python-root.txt"
printf 'scripts/new-helper.py\n' > "$added_python_root"

added_mjs_root="$TMPROOT/added-mjs-root.txt"
printf 'scripts/new-helper.mjs\n' > "$added_mjs_root"

# Case 1: new root .sh + body with reuse section → PASS
set +e
out="$("$GATE" --repo "$repo" --body-file "$reuse_ok_body" --added-files "$added_new_root_script" 2>&1)"
rc=$?
set -e
assert_rc "T6: new root .sh with reuse section passes" "$rc" "0"

# Case 2: new root .sh + body without reuse section → BLOCK
set +e
out="$("$GATE" --repo "$repo" --body-file "$reuse_missing_body" --added-files "$added_new_root_script" 2>&1)"
rc=$?
set -e
assert_rc "T6: new root .sh without reuse section blocks" "$rc" "2"
assert_contains "T6: reuse block mentions justification" "$out" "Script reuse justification"
assert_contains "T6: reuse block lists triggering file" "$out" "scripts/new-helper.sh"

# Case 3: modifying existing script (no added files) → PASS
set +e
out="$("$GATE" --repo "$repo" --body-file "$reuse_missing_body" --added-files "$added_modified_only" 2>&1)"
rc=$?
set -e
assert_rc "T6: modify-existing skips reuse gate" "$rc" "0"

# Case 4: new scripts in subdirs only (no root .sh) → PASS even without reuse section
set +e
out="$("$GATE" --repo "$repo" --body-file "$reuse_missing_body" --added-files "$added_subdir_only" 2>&1)"
rc=$?
set -e
assert_rc "T6: subdir-only adds skip reuse gate" "$rc" "0"

# Case 5: new root .py without reuse section → BLOCK
set +e
out="$("$GATE" --repo "$repo" --body-file "$reuse_missing_body" --added-files "$added_python_root" 2>&1)"
rc=$?
set -e
assert_rc "T6: new root .py without reuse section blocks" "$rc" "2"

# Case 6: new root .mjs without reuse section → BLOCK
set +e
out="$("$GATE" --repo "$repo" --body-file "$reuse_missing_body" --added-files "$added_mjs_root" 2>&1)"
rc=$?
set -e
assert_rc "T6: new root .mjs without reuse section blocks" "$rc" "2"

# Case 7: --added-files pointing to a missing file → BLOCK with clear error
set +e
out="$("$GATE" --repo "$repo" --body-file "$reuse_ok_body" --added-files "$TMPROOT/does-not-exist.txt" 2>&1)"
rc=$?
set -e
assert_rc "T6: missing --added-files blocks" "$rc" "2"
assert_contains "T6: missing --added-files error" "$out" "does not exist"

# Case 8: no --added-files supplied → legacy behavior (template heading only)
set +e
out="$("$GATE" --repo "$repo" --body-file "$valid_body" 2>&1)"
rc=$?
set -e
assert_rc "T6: omitting --added-files preserves legacy pass" "$rc" "0"

printf '\n=== pr-body-template selftest: %d/%d PASS ===\n' "$PASS" "$TOTAL"
[[ "$PASS" -eq "$TOTAL" ]]
