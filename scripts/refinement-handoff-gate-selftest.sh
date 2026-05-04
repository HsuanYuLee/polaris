#!/usr/bin/env bash
# Selftest for refinement-handoff-gate.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gate="$script_dir/refinement-handoff-gate.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

record_pass() {
  echo "PASS $1"
  pass=$((pass + 1))
}

record_fail() {
  echo "FAIL $1" >&2
  fail=$((fail + 1))
}

assert_ok() {
  local name="$1"
  shift
  if "$@" >/tmp/refinement-handoff-gate-test.out 2>/tmp/refinement-handoff-gate-test.err; then
    record_pass "$name"
  else
    cat /tmp/refinement-handoff-gate-test.err >&2 || true
    record_fail "$name"
  fi
}

assert_fail() {
  local name="$1"
  shift
  if "$@" >/tmp/refinement-handoff-gate-test.out 2>/tmp/refinement-handoff-gate-test.err; then
    cat /tmp/refinement-handoff-gate-test.out >&2 || true
    record_fail "$name"
  else
    record_pass "$name"
  fi
}

spec="$tmp/specs/EPIC-999"
mkdir -p "$spec"
printf '# Refinement\n' > "$spec/refinement.md"

assert_fail "missing refinement.json blocks handoff" "$gate" "$spec"

cat > "$spec/refinement.json" <<'JSON'
{
  "epic": "EPIC-999",
  "version": "1.0",
  "created_at": "2026-04-29T00:00:00+08:00",
  "modules": [
    {
      "path": "apps/main/pages/home/index.vue",
      "action": "modify"
    }
  ],
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "SSR JSON-LD is present.",
      "verification": {
        "method": "curl",
        "detail": "Fetch raw HTML and parse JSON-LD."
      }
    }
  ],
  "dependencies": [],
  "edge_cases": []
}
JSON

assert_ok "spec directory with valid artifact passes" "$gate" "$spec"
assert_ok "refinement.md path resolves sibling artifact" "$gate" "$spec/refinement.md"
assert_ok "refinement.json path validates directly" "$gate" "$spec/refinement.json"

dp_spec="$tmp/specs/design-plans/DP-999-test"
mkdir -p "$dp_spec"
printf '# DP-999\n' > "$dp_spec/refinement.md"
printf '# DP-999 Plan\n' > "$dp_spec/plan.md"
cat > "$dp_spec/refinement.json" <<JSON
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "$dp_spec",
    "plan_path": "$dp_spec/plan.md",
    "jira_key": null
  },
  "version": "1.0",
  "created_at": "2026-04-30T00:00:00+08:00",
  "modules": [
    {
      "path": ".claude/skills/references/model-tier-policy.md",
      "action": "create"
    }
  ],
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "DP-backed refinement artifacts can be validated.",
      "verification": {
        "method": "unit_test",
        "detail": "Run refinement handoff gate selftest."
      }
    }
  ],
  "dependencies": [],
  "edge_cases": []
}
JSON

assert_ok "DP-backed artifact with epic null passes" "$gate" "$dp_spec"

cat > "$spec/refinement.json" <<'JSON'
{
  "epic": "EPIC-999",
  "version": "1.0",
  "created_at": "2026-04-29T00:00:00+08:00",
  "modules": [],
  "acceptance_criteria": [],
  "dependencies": [],
  "edge_cases": []
}
JSON

assert_fail "invalid refinement.json blocks handoff" "$gate" "$spec"

if [[ "$fail" -ne 0 ]]; then
  echo "refinement-handoff-gate selftest: $pass pass, $fail fail" >&2
  exit 1
fi

echo "refinement-handoff-gate selftest: $pass pass, $fail fail"
