#!/usr/bin/env bash
# refinement-research-producer-selftest.sh — DP-293 T4 / AC6 contract.
#
# Purpose: verify the refinement-owned research-snapshot producer entry added to
#   scripts/lib/evidence-producers.json (glob
#   docs-manager/src/content/docs/specs/**/artifacts/research/*.md, token
#   refinement:research-snapshot) works end-to-end without breaking the
#   pre-existing learning co-owner of the same glob.
# Inputs:  none (hermetic; resolves repo root via git toplevel / BASH_SOURCE,
#          uses a tmp WORKDIR for the live writer case).
# Outputs: prints PASS on success; diagnostic + non-zero exit on any failure.
# Exit code: 0 PASS, 1 contract failure.
#
# Cases (AC6 + adversarial):
#   A  write-producer-owned-artifact.sh --producer-token refinement:research-snapshot
#      to a research/*.md path → exit 0, file materialised (live writer path).
#   B  no-direct-evidence-write hook + POLARIS_SKILL_WRITER=refinement on the same
#      research glob → exit 0 BYPASS_SKILL (refinement co-ownership).
#   C  no-direct-evidence-write hook + POLARIS_SKILL_WRITER=learning on the same
#      research glob → exit 0 BYPASS_SKILL (pre-existing learning authority preserved).
#   D  no-direct-evidence-write hook + POLARIS_PRODUCER=refinement:research-snapshot
#      on the same research glob → exit 0 BYPASS_TOKEN.
#   E  token uniqueness: refinement:research-snapshot appears in exactly one
#      producer entry; the research glob is co-owned by exactly {learning, refinement}.
#   NEG  POLARIS_PRODUCER=refinement:research-snapshot on a NON-research protected
#        path (refinement.json) → exit 2 DENIED token+path mismatch (no bypass).

set -euo pipefail

if ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$ROOT_DIR" ]]; then
  :
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
HOOK="$ROOT_DIR/.claude/hooks/no-direct-evidence-write.sh"
WRITER="$ROOT_DIR/scripts/write-producer-owned-artifact.sh"
PRODUCERS_JSON="$ROOT_DIR/scripts/lib/evidence-producers.json"
WORKDIR="$(mktemp -d -t dp293-research.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

for f in "$HOOK" "$WRITER"; do
  if [[ ! -x "$f" ]]; then
    echo "FAIL: not executable: $f" >&2
    exit 1
  fi
done
if [[ ! -f "$PRODUCERS_JSON" ]]; then
  echo "FAIL: producers table missing: $PRODUCERS_JSON" >&2
  exit 1
fi

# Case E: token uniqueness + research glob co-ownership invariant.
PRODUCERS_JSON="$PRODUCERS_JSON" python3 - <<'PY'
import json
import os
import sys

data = json.load(open(os.environ["PRODUCERS_JSON"]))
producers = data.get("producers", []) or []

# Global token uniqueness (writer + hook both fail-closed on duplicates).
seen = {}
for p in producers:
    for t in (p.get("producer_tokens") or []):
        seen[t] = seen.get(t, 0) + 1
dups = sorted(t for t, c in seen.items() if c > 1)
if dups:
    print(f"FAIL: duplicate producer_tokens: {dups}", file=sys.stderr)
    sys.exit(1)
if seen.get("refinement:research-snapshot", 0) != 1:
    print("FAIL: refinement:research-snapshot must appear in exactly one entry "
          f"(found {seen.get('refinement:research-snapshot', 0)})", file=sys.stderr)
    sys.exit(1)

# Research glob must be co-owned by exactly {learning, refinement}.
research_glob = "docs-manager/src/content/docs/specs/**/artifacts/research/*.md"
owners = sorted(
    p.get("owning_skill", "")
    for p in producers
    if research_glob in (p.get("path_globs") or [])
)
if owners != ["learning", "refinement"]:
    print(f"FAIL: research glob owners expected [learning, refinement], got {owners}",
          file=sys.stderr)
    sys.exit(1)

# The refinement research entry must carry the same metadata contract as learning.
ref = next(p for p in producers
           if "refinement:research-snapshot" in (p.get("producer_tokens") or []))
if sorted(ref.get("required_frontmatter") or []) != ["artifact_type", "created", "source"]:
    print(f"FAIL: refinement research required_frontmatter mismatch: "
          f"{ref.get('required_frontmatter')}", file=sys.stderr)
    sys.exit(1)
print("case-E ok")
PY

# Case A: live writer path materialises a research snapshot via the token.
research_target="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-293-fixture/artifacts/research/2026-06-07-fixture.md"
body_file="$WORKDIR/body.md"
cat >"$body_file" <<'BODY'
---
artifact_type: research-snapshot
source: DP-293
created: 2026-06-07
---

# Fixture research snapshot
BODY
set +e
"$WRITER" --producer-token refinement:research-snapshot \
  --path "$research_target" --body-file "$body_file" >"$WORKDIR/caseA.out" 2>&1
rc_a=$?
set -e
if [[ "$rc_a" -ne 0 ]]; then
  echo "FAIL (case A): writer expected exit 0, got $rc_a" >&2
  cat "$WORKDIR/caseA.out" >&2
  exit 1
fi
if [[ ! -f "$research_target" ]]; then
  echo "FAIL (case A): research snapshot not materialised at $research_target" >&2
  exit 1
fi
grep -q 'owning_skill=refinement' "$WORKDIR/caseA.out" || {
  echo "FAIL (case A): writer attribution missing owning_skill=refinement" >&2
  cat "$WORKDIR/caseA.out" >&2
  exit 1
}

# Hook fixture path (string only — the hook is a PreToolUse gate, no disk write).
hook_research_path="$ROOT_DIR/docs-manager/src/content/docs/specs/design-plans/__dp293_fixture__/artifacts/research/2026-06-07-fixture.md"
# A protected specs *.md that is NOT under artifacts/research/ — refinement.md is
# hook-protected (docs-manager/.../specs/**/*.md) yet outside the research glob,
# so the research token must NOT bypass it. (refinement.json is intentionally not
# used here: it is not in the hook's protected scope, so the hook would no-op.)
non_research_md_path="$ROOT_DIR/docs-manager/src/content/docs/specs/design-plans/__dp293_fixture__/refinement.md"

run_hook() {
  local payload="$1" expected_exit="$2" label="$3" env_var="${4:-}"
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

mk_payload() {
  python3 -c "import json,sys; print(json.dumps({'tool_name':'Write','tool_input':{'file_path':sys.argv[1],'content':'---\nartifact_type: research-snapshot\nsource: DP-293\ncreated: 2026-06-07\n---\n'}}))" "$1"
}

# Case B: POLARIS_SKILL_WRITER=refinement on research glob → BYPASS_SKILL.
payload_research=$(mk_payload "$hook_research_path")
run_hook "$payload_research" 0 caseB-refinement-skill "POLARIS_SKILL_WRITER=refinement"
grep -q 'skill-writer bypass' "$WORKDIR/caseB-refinement-skill.out"
grep -q 'polaris_skill_writer=refinement' "$WORKDIR/caseB-refinement-skill.out"

# Case C: POLARIS_SKILL_WRITER=learning on the SAME research glob → still BYPASS_SKILL.
run_hook "$payload_research" 0 caseC-learning-skill "POLARIS_SKILL_WRITER=learning"
grep -q 'skill-writer bypass' "$WORKDIR/caseC-learning-skill.out"
grep -q 'polaris_skill_writer=learning' "$WORKDIR/caseC-learning-skill.out"

# Case D: POLARIS_PRODUCER=refinement:research-snapshot on research glob → BYPASS_TOKEN.
run_hook "$payload_research" 0 caseD-refinement-token "POLARIS_PRODUCER=refinement:research-snapshot"
grep -q 'token+glob bypass' "$WORKDIR/caseD-refinement-token.out"
grep -q 'producer=refinement:research-snapshot' "$WORKDIR/caseD-refinement-token.out"

# Case NEG: refinement:research-snapshot token on a protected specs *.md OUTSIDE
# the research glob (refinement.md) → exit 2 DENIED token+path mismatch (no bypass).
payload_neg=$(mk_payload "$non_research_md_path")
run_hook "$payload_neg" 2 caseNEG-token-path-mismatch "POLARIS_PRODUCER=refinement:research-snapshot"
grep -q 'DENIED token+path mismatch' "$WORKDIR/caseNEG-token-path-mismatch.out"
grep -q 'BLOCKED' "$WORKDIR/caseNEG-token-path-mismatch.out"

echo "PASS"
