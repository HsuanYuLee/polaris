#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER="$SCRIPT_DIR/scan-template-leaks.sh"

tmpdir="$(mktemp -d -t scan-template-leaks.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

workspace="$tmpdir/workspace"
template="$tmpdir/template"
mkdir -p "$workspace/acme" "$workspace/.claude/skills/references" "$workspace/.claude/skills/acme" "$workspace/scripts" "$template/.claude/skills/references"

cat > "$workspace/acme/workspace-config.yaml" <<'YAML'
jira:
  instance: acme.atlassian.net
  projects:
    - key: ACME
github:
  org: acme-inc
web_urls:
  production: https://www.acme.example
slack:
  channels:
    dev: C0123456789
YAML

cat > "$workspace/.claude/skills/references/example.md" <<'MD'
Use PROJ-123 for neutral examples.
Do not use ACME-123 in shared templates.
MD

cat > "$workspace/.claude/skills/acme/SKILL.md" <<'MD'
Company-specific ACME-999 is intentionally excluded.
MD

cat > "$workspace/scripts/example.sh" <<'SH'
# neutral script
SH

cat > "$template/.claude/skills/references/example.md" <<'MD'
Template still references acme-inc.
MD

set +e
"$SCANNER" --workspace "$workspace" --source workspace --blocking >/tmp/scan-template-leaks-selftest.out 2>/tmp/scan-template-leaks-selftest.err
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "selftest failed: blocking scan should fail on shared ACME-123" >&2
  exit 1
fi
if ! grep -q "ACME-123" /tmp/scan-template-leaks-selftest.out; then
  echo "selftest failed: expected shared hit in output" >&2
  exit 1
fi
if grep -q "ACME-999" /tmp/scan-template-leaks-selftest.out; then
  echo "selftest failed: company-specific skill should be excluded" >&2
  exit 1
fi

perl -0pi -e 's/ACME-123/PROJ-123/g' "$workspace/.claude/skills/references/example.md"
"$SCANNER" --workspace "$workspace" --source workspace --blocking >/tmp/scan-template-leaks-selftest-clean.out

set +e
"$SCANNER" --workspace "$workspace" --template "$template" --source template --blocking >/tmp/scan-template-leaks-selftest-template.out 2>/tmp/scan-template-leaks-selftest-template.err
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "selftest failed: template scan should fail on acme-inc" >&2
  exit 1
fi

echo "PASS: scan-template-leaks selftest"
