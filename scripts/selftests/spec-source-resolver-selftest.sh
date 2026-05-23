#!/usr/bin/env bash
# Selftest for scripts/spec-source-resolver.sh.
#
# 涵蓋 fixture：
#   1. DP-228 by source id（active DP）
#   2. EXAMPLE-556 by source id（active company spec）
#   3. EXB2C-3921 by source id（active company spec）
#   4. direct refinement.md path → 反推 container
#   5. duplicate DP match → exit 2 + POLARIS_SOURCE_DUPLICATE
#   6. missing source → exit 2 + POLARIS_SOURCE_MISSING
#   7. archive path → archived=true + readiness 含 archived-read-only
#
# 每個 case 都用一個獨立的 tmp specs-root fixture，避免污染 workspace 實際 specs。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RESOLVER="$ROOT_DIR/scripts/spec-source-resolver.sh"

[[ -x "$RESOLVER" ]] || { printf 'ERROR: resolver not executable: %s\n' "$RESOLVER" >&2; exit 1; }

tmpdir="$(mktemp -d -t spec-source-resolver.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

FAIL=0
note() { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; FAIL=1; }

# Helper: parse JSON field via python3
json_field() {
  local json="$1" field="$2"
  printf '%s' "$json" | python3 -c "import sys, json; d=json.loads(sys.stdin.read()); v=d.get('$field'); print(v if v is not None else '')"
}

# Helper: parse JSON readiness array (joined by ,)
json_readiness() {
  local json="$1"
  printf '%s' "$json" | python3 -c "import sys, json; d=json.loads(sys.stdin.read()); r=d.get('readiness') or []; print(','.join(r))"
}

#####################################
# Fixture setup
#####################################
specs="$tmpdir/specs"

# DP-228 active container with index.md + refinement.{md,json}
mkdir -p "$specs/design-plans/DP-228-foo"
cat >"$specs/design-plans/DP-228-foo/index.md" <<'EOF'
---
title: "DP-228"
status: LOCKED
---
EOF
echo "{}" >"$specs/design-plans/DP-228-foo/refinement.json"
echo "# refinement" >"$specs/design-plans/DP-228-foo/refinement.md"

# EXAMPLE-556 active company spec
mkdir -p "$specs/companies/exampleco/EXAMPLE-556"
cat >"$specs/companies/exampleco/EXAMPLE-556/index.md" <<'EOF'
---
title: "EXAMPLE-556"
status: LOCKED
---
EOF
echo "{}" >"$specs/companies/exampleco/EXAMPLE-556/refinement.json"
echo "# refinement" >"$specs/companies/exampleco/EXAMPLE-556/refinement.md"

# EXB2C-3921 active company spec
mkdir -p "$specs/companies/exampleco/EXB2C-3921"
cat >"$specs/companies/exampleco/EXB2C-3921/index.md" <<'EOF'
---
title: "EXB2C-3921"
status: DISCUSSION
---
EOF

# DP-700 duplicate (two folders)
mkdir -p "$specs/design-plans/DP-700-a" "$specs/design-plans/DP-700-b"
echo "---" >"$specs/design-plans/DP-700-a/index.md"
echo "---" >"$specs/design-plans/DP-700-b/index.md"

# DP-810 archive only
mkdir -p "$specs/design-plans/archive/DP-810-old"
cat >"$specs/design-plans/archive/DP-810-old/index.md" <<'EOF'
---
title: "DP-810"
status: IMPLEMENTED
---
EOF

#####################################
# Case 1: DP-228 by source id
#####################################
note "case 1: resolve --source-id DP-228"
if json="$("$RESOLVER" --specs-root "$specs" --source-id DP-228 2>/tmp/c1.err)"; then
  st="$(json_field "$json" source_type)"
  sid="$(json_field "$json" source_id)"
  container="$(json_field "$json" container)"
  primary="$(json_field "$json" primary_doc)"
  ref_md="$(json_field "$json" refinement_md)"
  ref_json="$(json_field "$json" refinement_json)"
  archived="$(json_field "$json" archived)"
  [[ "$st" == "dp" ]] || fail "case1 source_type expected dp, got $st"
  [[ "$sid" == "DP-228" ]] || fail "case1 source_id expected DP-228, got $sid"
  [[ "$container" == "$specs/design-plans/DP-228-foo" ]] || fail "case1 container mismatch: $container"
  [[ "$primary" == "$specs/design-plans/DP-228-foo/index.md" ]] || fail "case1 primary_doc mismatch: $primary"
  [[ "$ref_md" == "$specs/design-plans/DP-228-foo/refinement.md" ]] || fail "case1 refinement_md mismatch: $ref_md"
  [[ "$ref_json" == "$specs/design-plans/DP-228-foo/refinement.json" ]] || fail "case1 refinement_json mismatch: $ref_json"
  [[ "$archived" == "False" || "$archived" == "false" ]] || fail "case1 archived expected false, got $archived"
else
  fail "case1 resolver exited non-zero: $(cat /tmp/c1.err)"
fi

#####################################
# Case 2: EXAMPLE-556 by source id (JIRA / company)
#####################################
note "case 2: resolve --source-id EXAMPLE-556"
if json="$("$RESOLVER" --specs-root "$specs" --source-id EXAMPLE-556 2>/tmp/c2.err)"; then
  st="$(json_field "$json" source_type)"
  sid="$(json_field "$json" source_id)"
  container="$(json_field "$json" container)"
  primary="$(json_field "$json" primary_doc)"
  [[ "$st" == "jira" ]] || fail "case2 source_type expected jira, got $st"
  [[ "$sid" == "EXAMPLE-556" ]] || fail "case2 source_id expected EXAMPLE-556, got $sid"
  [[ "$container" == "$specs/companies/exampleco/EXAMPLE-556" ]] || fail "case2 container mismatch: $container"
  [[ "$primary" == "$specs/companies/exampleco/EXAMPLE-556/index.md" ]] || fail "case2 primary_doc mismatch: $primary"
else
  fail "case2 resolver exited non-zero: $(cat /tmp/c2.err)"
fi

#####################################
# Case 3: EXB2C-3921 by source id
#####################################
note "case 3: resolve --source-id EXB2C-3921"
if json="$("$RESOLVER" --specs-root "$specs" --source-id EXB2C-3921 2>/tmp/c3.err)"; then
  st="$(json_field "$json" source_type)"
  sid="$(json_field "$json" source_id)"
  container="$(json_field "$json" container)"
  status="$(json_field "$json" status)"
  [[ "$st" == "jira" ]] || fail "case3 source_type expected jira, got $st"
  [[ "$sid" == "EXB2C-3921" ]] || fail "case3 source_id expected EXB2C-3921, got $sid"
  [[ "$container" == "$specs/companies/exampleco/EXB2C-3921" ]] || fail "case3 container mismatch: $container"
  [[ "$status" == "DISCUSSION" ]] || fail "case3 status expected DISCUSSION, got $status"
else
  fail "case3 resolver exited non-zero: $(cat /tmp/c3.err)"
fi

#####################################
# Case 4: direct refinement.md path → 反推 container
#####################################
note "case 4: resolve --artifact-path refinement.md (DP)"
if json="$("$RESOLVER" --specs-root "$specs" --artifact-path "$specs/design-plans/DP-228-foo/refinement.md" 2>/tmp/c4.err)"; then
  st="$(json_field "$json" source_type)"
  container="$(json_field "$json" container)"
  [[ "$st" == "dp" ]] || fail "case4 source_type expected dp, got $st"
  [[ "$container" == "$specs/design-plans/DP-228-foo" ]] || fail "case4 container mismatch: $container"
else
  fail "case4 resolver exited non-zero: $(cat /tmp/c4.err)"
fi

# 4b: direct path against company spec
note "case 4b: resolve --artifact-path refinement.json (company)"
if json="$("$RESOLVER" --specs-root "$specs" --artifact-path "$specs/companies/exampleco/EXAMPLE-556/refinement.json" 2>/tmp/c4b.err)"; then
  st="$(json_field "$json" source_type)"
  sid="$(json_field "$json" source_id)"
  container="$(json_field "$json" container)"
  [[ "$st" == "jira" ]] || fail "case4b source_type expected jira, got $st"
  [[ "$sid" == "EXAMPLE-556" ]] || fail "case4b source_id expected EXAMPLE-556, got $sid"
  [[ "$container" == "$specs/companies/exampleco/EXAMPLE-556" ]] || fail "case4b container mismatch: $container"
else
  fail "case4b resolver exited non-zero: $(cat /tmp/c4b.err)"
fi

#####################################
# Case 5: duplicate DP-700 → exit 2 + POLARIS_SOURCE_DUPLICATE
#####################################
note "case 5: duplicate DP-700"
if "$RESOLVER" --specs-root "$specs" --source-id DP-700 >/tmp/c5.out 2>/tmp/c5.err; then
  fail "case5 expected non-zero exit"
else
  rc=$?
  [[ "$rc" == 2 ]] || fail "case5 expected exit 2, got $rc"
  grep -q 'POLARIS_SOURCE_DUPLICATE' /tmp/c5.err || fail "case5 missing POLARIS_SOURCE_DUPLICATE in stderr"
fi

#####################################
# Case 6: missing DP-999 → exit 2 + POLARIS_SOURCE_MISSING
#####################################
note "case 6: missing DP-999"
if "$RESOLVER" --specs-root "$specs" --source-id DP-999 >/tmp/c6.out 2>/tmp/c6.err; then
  fail "case6 expected non-zero exit"
else
  rc=$?
  [[ "$rc" == 2 ]] || fail "case6 expected exit 2, got $rc"
  grep -q 'POLARIS_SOURCE_MISSING' /tmp/c6.err || fail "case6 missing POLARIS_SOURCE_MISSING in stderr"
fi

# 6b: missing JIRA-style key
note "case 6b: missing EXAMPLE-9999"
if "$RESOLVER" --specs-root "$specs" --source-id EXAMPLE-9999 >/tmp/c6b.out 2>/tmp/c6b.err; then
  fail "case6b expected non-zero exit"
else
  rc=$?
  [[ "$rc" == 2 ]] || fail "case6b expected exit 2, got $rc"
  grep -q 'POLARIS_SOURCE_MISSING' /tmp/c6b.err || fail "case6b missing POLARIS_SOURCE_MISSING in stderr"
fi

#####################################
# Case 7: archive path → archived=true + readiness archived-read-only
#####################################
note "case 7: archive direct path → archived=true"
if json="$("$RESOLVER" --specs-root "$specs" --artifact-path "$specs/design-plans/archive/DP-810-old/index.md" 2>/tmp/c7.err)"; then
  st="$(json_field "$json" source_type)"
  archived="$(json_field "$json" archived)"
  readiness="$(json_readiness "$json")"
  [[ "$st" == "dp" ]] || fail "case7 source_type expected dp, got $st"
  [[ "$archived" == "True" || "$archived" == "true" ]] || fail "case7 archived expected true, got $archived"
  [[ "$readiness" == *"archived-read-only"* ]] || fail "case7 readiness missing archived-read-only: $readiness"
else
  fail "case7 resolver exited non-zero: $(cat /tmp/c7.err)"
fi

#####################################
# Summary
#####################################
if [[ "$FAIL" -ne 0 ]]; then
  printf 'FAIL: spec-source-resolver selftest\n' >&2
  exit 1
fi

echo "PASS: spec-source-resolver selftest"
