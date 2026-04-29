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

spec="$tmp/specs/GT-999"
mkdir -p "$spec"
printf '# Refinement\n' > "$spec/refinement.md"

assert_fail "missing refinement.json blocks handoff" "$gate" "$spec"

cat > "$spec/refinement.json" <<'JSON'
{
  "epic": "GT-999",
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

cat > "$spec/refinement.json" <<'JSON'
{
  "epic": "GT-999",
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

