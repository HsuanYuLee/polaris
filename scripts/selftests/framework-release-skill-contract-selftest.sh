#!/usr/bin/env bash
# Purpose: Assert the framework-release SKILL.md contract markers required by
#          DP-308 are present (bundle-release orchestration, version boundary on
#          the verified bundle PR HEAD, existing gate-lane guidance, and the
#          engineering=individual-DP-PR boundary). Keeps the framework-release
#          contract deterministic instead of prose-only.
# Inputs:  none (reads workspace .claude/skills/framework-release/SKILL.md).
# Outputs: stdout PASS lines per assertion; stderr POLARIS_* token on failure.
# Exit:    0 PASS, 1 FAIL (one or more contract markers missing / drift detected).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="$ROOT/.claude/skills/framework-release/SKILL.md"

TOKEN="POLARIS_FRAMEWORK_RELEASE_CONTRACT_MARKER_MISSING"
FAILURES=()

if [[ ! -f "$SKILL" ]]; then
  echo "$TOKEN: framework-release SKILL.md not found at $SKILL" >&2
  exit 1
fi

# assert_grep <ac_id> <description> <pattern> ...
# All patterns (single-quoted fixed strings via grep -F) must be present.
assert_grep() {
  local ac_id="$1" desc="$2"
  shift 2
  local pat missing=0
  for pat in "$@"; do
    if ! grep -qF -- "$pat" "$SKILL"; then
      missing=1
      FAILURES+=("$ac_id ($desc): missing marker -> $pat")
    fi
  done
  if [[ "$missing" -eq 0 ]]; then
    echo "PASS [$ac_id] $desc"
  else
    echo "FAIL [$ac_id] $desc" >&2
  fi
}

# assert_grep_regex <ac_id> <description> <ERE pattern>
assert_grep_regex() {
  local ac_id="$1" desc="$2" pat="$3"
  if grep -qE -- "$pat" "$SKILL"; then
    echo "PASS [$ac_id] $desc"
  else
    FAILURES+=("$ac_id ($desc): missing regex marker -> $pat")
    echo "FAIL [$ac_id] $desc" >&2
  fi
}

# assert_absent <ac_id> <description> <pattern>
# Pattern must NOT appear (drift / legacy / bypass guard).
assert_absent() {
  local ac_id="$1" desc="$2" pat="$3"
  if grep -qF -- "$pat" "$SKILL"; then
    FAILURES+=("$ac_id ($desc): forbidden marker present -> $pat")
    echo "FAIL [$ac_id] $desc" >&2
  else
    echo "PASS [$ac_id] $desc"
  fi
}

# --- AC1: bundle-release orchestration step + engineering-PR-only boundary ---
assert_grep "AC1" "bundle-release orchestration: aggregate-release branch step" \
  'engineering-branch-setup.sh --aggregate-release'
assert_grep "AC1" "bundle-release orchestration: release:version on bundle branch" \
  'mise run release:version'
assert_grep "AC1" "bundle-release orchestration: open+merge bundle PR" \
  'polaris-pr-create.sh'
assert_grep "AC1" "engineering=individual-DP-PR boundary declared" \
  '個別 DP PR'

# --- AC2: version compression only on verified bundle PR HEAD + AC-NEG5 ---
assert_grep "AC2" "version compression located on bundle PR HEAD" \
  'bundle PR HEAD'
assert_grep "AC2" "AC-NEG5 no post-merge raw version commit" \
  'AC-NEG5'
# Ensure the forbidden post-merge-version-commit concept is present somewhere
# (phrasing-tolerant via ERE alternation).
assert_grep_regex "AC2" "post-merge version commit prohibition concept" \
  'post-merge.*版本.*commit|版本.*commit.*post-merge|事後 release commit|merge 後.*壓版本'

# --- AC3: existing gate lanes (chore-followup + bundle_branch_alias) ---
assert_grep "AC3" "gate lane: chore/DP-NNN-* chore-followup" \
  'chore/DP-NNN-'
assert_grep "AC3" "gate lane: chore-followup named lane" \
  'chore-followup'
assert_grep "AC3" "gate lane: bundle_branch_alias aggregate-release" \
  'bundle_branch_alias'

# --- AC-NF1: maintainer-only frontmatter retained ---
assert_grep "AC-NF1" "scope: maintainer-only frontmatter retained" \
  'scope: maintainer-only'

# --- AC-NEG1: individual DP PR carries only changeset, no version compression ---
assert_grep "AC-NEG1" "individual DP PR boundary: changeset only, no version bump" \
  '只含 changeset'
assert_grep_regex "AC-NEG1" "individual DP PR boundary: explicit no-version-compression" \
  '個別 DP PR[^。]*不壓版本|不壓版本[^。]*個別 DP PR'
# AC-NEG1 adversarial: no residual per-PR "author runs release:version in the PR"
# legacy wording that would make individual DP PRs carry version changes again.
assert_absent "AC-NEG1" "no legacy per-PR release:version author wording" \
  '作者在 PR 內以 `mise run release:version`'

# --- AC-NEG2: no new env bypass / generic carve-out introduced in SKILL.md ---
assert_absent "AC-NEG2" "no POLARIS_SKIP bypass encouraged in skill prose" \
  'POLARIS_SKIP_DOCS_LINT=1 to bypass'
assert_absent "AC-NEG2" "no generic gate carve-out env var introduced" \
  'POLARIS_BUNDLE_GATE_BYPASS'

# --- Report ---
if [[ "${#FAILURES[@]}" -gt 0 ]]; then
  {
    echo ""
    echo "$TOKEN"
    printf '  - %s\n' "${FAILURES[@]}"
  } >&2
  exit 1
fi

echo ""
echo "framework-release SKILL.md contract: ALL MARKERS PRESENT"
exit 0
