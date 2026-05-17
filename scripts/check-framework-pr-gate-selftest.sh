#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
TMP="$(mktemp -d -t framework-pr-gate.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

make_stub() {
  local name="$1"
  local exit_code="$2"
  cat > "$TMP/$name" <<SH
#!/usr/bin/env bash
echo "$name"
exit $exit_code
SH
  chmod +x "$TMP/$name"
}

make_stub w1-pass 0
make_stub w2-pass 0
make_stub w4-pass 0
env \
  POLARIS_VALIDATE_RUNTIME_BIN="$TMP/w1-pass" \
  POLARIS_AUDIT_GRADUATION_BIN="$TMP/w2-pass" \
  POLARIS_CHECK_QUARANTINE_BIN="$TMP/w4-pass" \
  bash scripts/check-framework-pr-gate.sh >/dev/null

for fail in w1 w2 w4; do
  make_stub w1 0
  make_stub w2 0
  make_stub w4 0
  make_stub "$fail" 1
  if env \
    POLARIS_VALIDATE_RUNTIME_BIN="$TMP/w1" \
    POLARIS_AUDIT_GRADUATION_BIN="$TMP/w2" \
    POLARIS_CHECK_QUARANTINE_BIN="$TMP/w4" \
    bash scripts/check-framework-pr-gate.sh >"$TMP/out" 2>"$TMP/err"; then
    echo "self-test failed: $fail failure did not fail aggregator" >&2
    exit 1
  fi
  grep -q "framework-pr-gate failed" "$TMP/err"
done

env \
  POLARIS_VALIDATE_RUNTIME_BIN="$TMP/w1-pass" \
  POLARIS_AUDIT_GRADUATION_BIN="$TMP/w2-pass" \
  POLARIS_CHECK_QUARANTINE_BIN="$TMP/w4-pass" \
  POLARIS_SURFACE_CLASS="developer_pr" \
  bash scripts/check-framework-pr-gate.sh >/dev/null

workflow=".github/workflows/framework-pr.yml"
[[ -f "$workflow" ]] || { echo "missing $workflow" >&2; exit 1; }
for path in ".claude/**" ".agents/**" "scripts/**" "docs-manager/src/content/docs/specs/design-plans/**" "CLAUDE.md" "AGENTS.md"; do
  grep -Fq "$path" "$workflow" || { echo "workflow paths missing $path" >&2; exit 1; }
done
if grep -A80 "paths-ignore:" "$workflow" | rg -q '(\.claude/\*\*|\.agents/\*\*|scripts/\*\*|docs-manager/src/content/docs/specs/design-plans/\*\*|CLAUDE\.md|AGENTS\.md)'; then
  echo "workflow paths-ignore contains framework path" >&2
  exit 1
fi

echo "PASS: framework PR gate self-test"
