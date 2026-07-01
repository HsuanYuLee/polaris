#!/usr/bin/env bash
# Purpose: Assert the framework-release SKILL.md contract markers required by
#          DP-334 / DP-388 are present: single feat/DP-NNN -> main PR gate,
#          PR-gated fast-forward main promotion, version compression on the
#          feat/DP-NNN HEAD (one DP one version, AC-NEG2), sync AFTER main
#          promotion (AC6), bootstrap fallback / rollback steps (AC7), the
#          engineering=individual-DP-task-PR boundary, and that retained bundle
#          wording is annotated as a guarded bootstrap fallback rather than the
#          default release lane. Keeps the framework-release contract deterministic.
# Inputs:  none (reads workspace .claude/skills/framework-release/SKILL.md).
# Outputs: stdout PASS lines per assertion; stderr POLARIS_* token on failure.
# Exit:    0 PASS, 1 FAIL (one or more contract markers missing / drift detected).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="$ROOT/.claude/skills/framework-release/SKILL.md"

TOKEN="POLARIS_FRAMEWORK_RELEASE_CONTRACT_MARKER_MISSING"
FAILURES=()

is_template_checkout() {
  local origin_url=""
  origin_url="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
  case "$origin_url" in
    git@github.com:*/polaris|git@github.com:*/polaris.git|https://github.com/*/polaris|https://github.com/*/polaris.git)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if [[ ! -f "$SKILL" ]]; then
  if is_template_checkout; then
    echo "PASS [TEMPLATE] framework-release skill is maintainer-only and absent from this template checkout; contract marker assertions skipped"
    exit 0
  fi
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

# --- AC4: single feat/DP-NNN -> main PR gate + fast-forward promotion ---
assert_grep "AC4" "release orchestration: single feat/DP-NNN -> main PR gate" \
  'feat/DP-NNN -> main'
assert_grep "AC4" "release orchestration: version compression at feat HEAD" \
  'mise run release-version'
assert_grep "AC4" "release orchestration: open the PR via canonical producer" \
  'polaris-pr-create.sh'
assert_grep "AC4" "release orchestration: PR-gated fast-forward helper" \
  'framework-release-main-promotion.sh'
assert_grep_regex "AC4" "main promotion is fast-forward / linear" \
  'fast-forward|快轉|linear|線性'
assert_grep_regex "AC4" "final merge bubble is forbidden" \
  'final merge bubble|不新增 final `Merge pull request'
assert_grep "AC4" "engineering=individual-DP-task-PR boundary declared" \
  '個別 DP task PR'

# --- AC3 / AC-NEG2: version compression at feat/DP-NNN HEAD, one DP one version ---
assert_grep "AC3" "version compression located on feat/DP-NNN HEAD" \
  'feat/DP-NNN HEAD'
assert_grep "AC-NEG2" "one DP one version / forbid multi-DP stacking" \
  'POLARIS_RELEASE_VERSION_MULTI_DP_STACKING'
assert_grep_regex "AC-NEG2" "explicit one-DP-one-version concept" \
  '一 DP 一版本|禁止多 DP 壓版|一張 DP.*版本'
# AC-NEG5 retained: no post-promotion raw version commit.
assert_grep "AC-NEG5" "AC-NEG5 no post-promotion raw version commit" \
  'AC-NEG5'
assert_grep_regex "AC-NEG5" "post-promotion version commit prohibition concept" \
  'post-promotion.*版本.*commit|版本.*commit.*post-promotion|事後 release commit|promotion 後.*壓版本'

# --- AC6: sync runs AFTER PR-gated main promotion (version lands on main first) ---
assert_grep_regex "AC6" "sync after main promotion" \
  'AFTER PR-Gated main Promotion|promotion.*之後才.*sync|sync.*promotion.*之後'
assert_grep "AC6" "sync producer invoked" \
  'sync-to-polaris.sh'

# --- AC7: bootstrap fallback / rollback steps present ---
assert_grep_regex "AC7" "bootstrap fallback / rollback section present" \
  'Bootstrap Fallback|rollback|Rollback'
assert_grep_regex "AC7" "rollback recovers half-finished feat / tag / sync state" \
  '半完成的 feat|半完成.*tag|不留下半完成'

# --- AC1 gate lane: feat/DP-NNN aggregation lane is the canonical/target lane ---
assert_grep "AC1" "gate lane: feat/DP-NNN aggregation lane" \
  'feat/DP-NNN aggregation lane'
assert_grep "AC1" "gate lane: chore/DP-NNN-* chore-followup retained" \
  'chore/DP-NNN-'

# --- AC5 Migration Boundaries: bundle wording retained ONLY as bootstrap fallback ---
# The bundle_branch_alias lane may remain, but it must be annotated as a guarded
# bootstrap fallback with removal criteria (not the default release lane).
assert_grep "AC5" "bundle lane annotated as bootstrap fallback only" \
  'BOOTSTRAP FALLBACK ONLY'
assert_grep "AC5" "Migration Boundaries removal criteria referenced" \
  'Migration Boundaries'
assert_grep_regex "AC5" "removal criteria for bundle path declared" \
  'removal criteria|AC7 PASS'

# --- AC-NF1: maintainer-only frontmatter retained ---
assert_grep "AC-NF1" "scope: maintainer-only frontmatter retained" \
  'scope: maintainer-only'

# --- AC-NEG1: individual DP task PR carries only changeset, no version compression ---
assert_grep "AC-NEG1" "individual DP task PR boundary: changeset only, no version bump" \
  '只含 changeset'
assert_grep_regex "AC-NEG1" "individual DP task PR boundary: explicit no-version-compression" \
  '個別 DP task PR[^。]*不壓版本|不壓版本[^。]*個別 DP task PR'
# AC-NEG1: DP task PR must target feat/DP-NNN, never main directly (no PR-less /
# main-targeting raw commit escape into the aggregation branch).
assert_grep_regex "AC-NEG1" "DP task PR targets feat, never main directly" \
  'target `feat/DP-NNN`|拒絕 DP task PR 直接 target `main`|絕不直 target `main`|絕不直 merge `main`'

# --- AC-NEG3: no steady-state GitHub merge mode / old single-merge contract ---
assert_absent "AC-NEG3" "no GitHub merge commit command in steady contract" \
  'gh pr merge'
assert_absent "AC-NEG3" "no old single merge commit steady contract" \
  'main` 每版只留一個 merge commit'

# --- AC-NEG: no new env bypass / generic carve-out introduced in SKILL.md ---
assert_absent "AC-NEG" "no POLARIS_SKIP bypass encouraged in skill prose" \
  'POLARIS_SKIP_DOCS_LINT=1 to bypass'
assert_absent "AC-NEG" "no generic gate carve-out env var introduced" \
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
