#!/usr/bin/env bash
# validate-specs-bound-write-contract-selftest.sh
#
# DP-207: covers scripts/validate-specs-bound-write-contract.sh (frontmatter +
# registry path validation for specs-bound markdown).
#
# DP-228 T2: additionally covers .claude/hooks/no-direct-evidence-write.sh
# POLARIS_SKILL_WRITER producer-env consent semantics:
#   AC1     POLARIS_SKILL_WRITER={skill} + file_path matches that skill's
#           owning specs-bound markdown glob → exit 0 + stderr attribution
#           `polaris_skill_writer={skill}`.
#   AC-NEG2 POLARIS_SKILL_WRITER set, but file_path is .polaris/evidence/*.json
#           (evidence JSON, not specs-bound markdown) → exit 2 (env must not
#           bypass evidence JSON writers).
#   AC-NEG4 POLARIS_SKILL_WRITER=refinement, but file_path is in bug-triage's
#           path_globs (cross-skill) → exit 2 (strict owning_skill binding).
#   Extra   POLARIS_SKILL_WRITER unset + specs-bound markdown → exit 2.
#   Extra   POLARIS_SKILL_WRITER=unknown-skill + specs-bound markdown → exit 2.
#   Extra   POLARIS_SKILL_WRITER set + path not in any glob for that skill
#           (e.g. refinement + verification/V*/) → exit 2.

set -euo pipefail

# Resolve repo root: prefer git-toplevel so worktree invocation finds the
# correct hook/script copies. Fall back to BASH_SOURCE-derived path.
if ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$ROOT" ]]; then
  :
else
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

VALIDATOR="$ROOT/scripts/validate-specs-bound-write-contract.sh"
HOOK="$ROOT/.claude/hooks/no-direct-evidence-write.sh"
PRODUCERS_JSON="$ROOT/scripts/lib/evidence-producers.json"

TMP="$(mktemp -d -t dp207-specs-bound.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Part 1 — DP-207 validator coverage (unchanged from baseline).
# ---------------------------------------------------------------------------

repo="$TMP/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name "Specs Bound Test"
mkdir -p "$repo/scripts/lib"
cp "$PRODUCERS_JSON" "$repo/scripts/lib/evidence-producers.json"

valid="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-topic/dogfood-evidence/DP-999/valid.md"
mkdir -p "$(dirname "$valid")"
cat >"$valid" <<'MD'
---
title: "Valid evidence"
description: "Valid fixture."
draft: true
sidebar:
  hidden: true
---

## Observed

valid
MD
bash "$VALIDATOR" --repo "$repo" --files "$valid" >"$TMP/dp207-valid.out"

invalid="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-topic/dogfood-evidence/DP-999/invalid.md"
cat >"$invalid" <<'MD'
## Observed

missing frontmatter
MD
if bash "$VALIDATOR" --repo "$repo" --files "$invalid" >"$TMP/dp207-invalid.out" 2>&1; then
  echo "FAIL: invalid frontmatter should fail" >&2
  exit 1
fi
grep -q 'missing required frontmatter' "$TMP/dp207-invalid.out"

unregistered="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-topic/random.md"
cat >"$unregistered" <<'MD'
---
title: "Random"
description: "Random."
draft: true
sidebar:
  hidden: true
---
MD
if bash "$VALIDATOR" --repo "$repo" --files "$unregistered" >"$TMP/dp207-unregistered.out" 2>&1; then
  echo "FAIL: unregistered path should fail" >&2
  exit 1
fi
grep -q 'no specs-bound producer registration' "$TMP/dp207-unregistered.out"

# ---------------------------------------------------------------------------
# Part 2 — DP-228 T2: hook POLARIS_SKILL_WRITER producer-env consent.
# ---------------------------------------------------------------------------

if [[ ! -x "$HOOK" ]]; then
  echo "FAIL: hook is not executable: $HOOK" >&2
  exit 1
fi
if [[ ! -f "$PRODUCERS_JSON" ]]; then
  echo "FAIL: producers table missing: $PRODUCERS_JSON" >&2
  exit 1
fi

# Sanity-check the registry has the owning_skill entries the cases depend on.
python3 - <<PY
import json, sys
data = json.load(open("$PRODUCERS_JSON"))
skills_seen = {p.get("owning_skill") for p in data.get("producers", [])}
required = {"refinement", "bug-triage", "verify-AC", "learning"}
missing = required - skills_seen
if missing:
    print(f"FAIL: registry missing owning_skill entries: {sorted(missing)}", file=sys.stderr)
    sys.exit(2)
PY

WORKDIR="$TMP/hook"
mkdir -p "$WORKDIR"

run_hook() {
  local payload="$1"
  local expected_exit="$2"
  local label="$3"
  local env_var="${4:-}"
  local out_file="$WORKDIR/${label}.out"
  set +e
  if [[ -n "$env_var" ]]; then
    env $env_var bash -c 'printf "%s" "$1" | "$2" >"$3" 2>&1' _ "$payload" "$HOOK" "$out_file"
  else
    printf '%s' "$payload" | "$HOOK" >"$out_file" 2>&1
  fi
  local rc=$?
  set -e
  if [[ "$rc" -ne "$expected_exit" ]]; then
    echo "FAIL ($label): expected exit $expected_exit, got $rc" >&2
    cat "$out_file" >&2
    exit 1
  fi
}

make_payload() {
  local file_path="$1"
  python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$file_path',
    'content': '---\ntitle: fixture\n---\n'
  }
}))
"
}

# AC1: POLARIS_SKILL_WRITER=refinement + dogfood-evidence specs markdown
# matches refinement entry's path_globs → bypass.
refinement_path="$ROOT/docs-manager/src/content/docs/specs/design-plans/__dp228_fixture__/dogfood-evidence/DP-228/sample.md"
payload_ac1=$(make_payload "$refinement_path")
run_hook "$payload_ac1" 0 ac1-skill-writer-refinement \
  "POLARIS_SKILL_WRITER=refinement"
grep -q 'polaris_skill_writer=refinement' "$WORKDIR/ac1-skill-writer-refinement.out"

# AC1b: POLARIS_SKILL_WRITER=bug-triage + jira-comments root-cause path
# matches bug-triage entry's path_globs → bypass.
bug_triage_path="$ROOT/docs-manager/src/content/docs/specs/design-plans/__dp228_fixture__/jira-comments/2026-05-22-root-cause.md"
payload_ac1b=$(make_payload "$bug_triage_path")
run_hook "$payload_ac1b" 0 ac1b-skill-writer-bug-triage \
  "POLARIS_SKILL_WRITER=bug-triage"
grep -q 'polaris_skill_writer=bug-triage' "$WORKDIR/ac1b-skill-writer-bug-triage.out"

# AC1c: POLARIS_SKILL_WRITER=learning + research artifact path → bypass.
learning_path="$ROOT/docs-manager/src/content/docs/specs/design-plans/__dp228_fixture__/artifacts/research/2026-05-22-notes.md"
payload_ac1c=$(make_payload "$learning_path")
run_hook "$payload_ac1c" 0 ac1c-skill-writer-learning \
  "POLARIS_SKILL_WRITER=learning"
grep -q 'polaris_skill_writer=learning' "$WORKDIR/ac1c-skill-writer-learning.out"

# AC-NEG2: POLARIS_SKILL_WRITER=verify-AC + evidence JSON path
# (.polaris/evidence/verify/*.json) → STILL BLOCKED.
# verify-AC owns ac-verification/*.json but POLARIS_SKILL_WRITER consent
# applies only to specs-bound markdown; evidence JSON writes must continue
# to require deterministic writer scripts.
evidence_json_path="$ROOT/.polaris/evidence/verify/__dp228_fixture__.json"
payload_neg2=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$evidence_json_path',
    'content': '{}'
  }
}))
")
run_hook "$payload_neg2" 2 neg2-evidence-json-not-bypassed \
  "POLARIS_SKILL_WRITER=verify-AC"
grep -q 'BLOCKED' "$WORKDIR/neg2-evidence-json-not-bypassed.out"

# AC-NEG4: POLARIS_SKILL_WRITER=refinement + bug-triage's jira-comments path
# → DENIED (cross-skill isolation, strict owning_skill binding).
payload_neg4=$(make_payload "$bug_triage_path")
run_hook "$payload_neg4" 2 neg4-cross-skill-denied \
  "POLARIS_SKILL_WRITER=refinement"
grep -q 'DENIED skill_writer path mismatch' "$WORKDIR/neg4-cross-skill-denied.out"
grep -q 'BLOCKED' "$WORKDIR/neg4-cross-skill-denied.out"

# Extra: POLARIS_SKILL_WRITER unset + specs-bound markdown → BLOCKED
# (existing behaviour preserved).
payload_no_env=$(make_payload "$refinement_path")
run_hook "$payload_no_env" 2 extra-no-env-blocked
grep -q 'BLOCKED' "$WORKDIR/extra-no-env-blocked.out"

# Extra: POLARIS_SKILL_WRITER set to a skill not in the registry → DENIED.
payload_unknown=$(make_payload "$refinement_path")
run_hook "$payload_unknown" 2 extra-skill-unknown \
  "POLARIS_SKILL_WRITER=not-a-real-skill"
grep -q 'DENIED skill_writer not in registry' "$WORKDIR/extra-skill-unknown.out"

# Extra: POLARIS_SKILL_WRITER=refinement + path not in any refinement glob
# (e.g. verification/V*/ which is verify-AC's territory) → DENIED.
verify_path="$ROOT/docs-manager/src/content/docs/specs/design-plans/__dp228_fixture__/verification/V1/index.md"
payload_path_oob=$(make_payload "$verify_path")
run_hook "$payload_path_oob" 2 extra-path-out-of-skill-globs \
  "POLARIS_SKILL_WRITER=refinement"
grep -q 'DENIED skill_writer path mismatch' "$WORKDIR/extra-path-out-of-skill-globs.out"

# Extra: out-of-scope path (non-specs, non-evidence) → hook no-op exit 0,
# regardless of POLARIS_SKILL_WRITER presence.
oos_payload=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '/tmp/some-random-file.txt',
    'content': 'irrelevant'
  }
}))
")
run_hook "$oos_payload" 0 oos-noop "POLARIS_SKILL_WRITER=refinement"

echo "PASS: validate specs-bound write contract selftest"
