#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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

cat > "$workspace/scripts/leaky-dp-path.sh" <<'SH'
bash scripts/check-main-chain-compliance.sh --source-container docs-manager/src/content/docs/specs/design-plans/DP-201-real-work-item
SH

cat > "$workspace/scripts/fixture-dp-path.sh" <<'SH'
fixture="$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-201-fixture"
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
if ! grep -q "framework-dp-active-path:DP-201-real-work-item" /tmp/scan-template-leaks-selftest.out; then
  echo "selftest failed: expected framework DP active path leak in output" >&2
  exit 1
fi
if grep -q "ACME-999" /tmp/scan-template-leaks-selftest.out; then
  echo "selftest failed: company-specific skill should be excluded" >&2
  exit 1
fi
if grep -q "DP-201-fixture" /tmp/scan-template-leaks-selftest.out; then
  echo "selftest failed: temp fixture DP path should be excluded" >&2
  exit 1
fi

perl -0pi -e 's/ACME-123/PROJ-123/g' "$workspace/.claude/skills/references/example.md"
rm -f "$workspace/scripts/leaky-dp-path.sh"
"$SCANNER" --workspace "$workspace" --source workspace --blocking >/tmp/scan-template-leaks-selftest-clean.out

set +e
"$SCANNER" --workspace "$workspace" --template "$template" --source template --blocking >/tmp/scan-template-leaks-selftest-template.out 2>/tmp/scan-template-leaks-selftest-template.err
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "selftest failed: template scan should fail on acme-inc" >&2
  exit 1
fi

repo="$tmpdir/repo"
config_absent_worktree="$tmpdir/repo-linked"
mkdir -p "$repo/.claude/skills/references" "$repo/acme"
cat > "$repo/.gitignore" <<'TXT'
acme/
TXT
cat > "$repo/acme/workspace-config.yaml" <<'YAML'
jira:
  projects:
    - key: ACME
github:
  org: acme-inc
YAML
cat > "$repo/.claude/skills/references/example.md" <<'MD'
Neutral placeholder only.
MD
git -C "$repo" init -q
git -C "$repo" add .gitignore .claude/skills/references/example.md
git -C "$repo" -c user.email=polaris@example.invalid -c user.name=Polaris commit -qm init
git -C "$repo" worktree add -q "$config_absent_worktree"
cat > "$config_absent_worktree/.claude/skills/references/leak.md" <<'MD'
Do not ship ACME-123 in template-facing references.
MD

set +e
"$SCANNER" --workspace "$config_absent_worktree" --source workspace --blocking >/tmp/scan-template-leaks-selftest-absent.out 2>/tmp/scan-template-leaks-selftest-absent.err
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "selftest failed: config-absent linked worktree should still block ACME-123" >&2
  exit 1
fi
if ! grep -q "ACME-123" /tmp/scan-template-leaks-selftest-absent.out; then
  echo "selftest failed: config-absent linked worktree output should include ACME-123" >&2
  exit 1
fi

set +e
POLARIS_TEMPLATE_LEAK_BYPASS=1 "$SCANNER" --workspace "$config_absent_worktree" --source workspace --blocking >/tmp/scan-template-leaks-selftest-bypass.out 2>/tmp/scan-template-leaks-selftest-bypass.err
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "selftest failed: bypass env must not silence config-absent linked worktree leak" >&2
  exit 1
fi

no_company="$tmpdir/no-company"
mkdir -p "$no_company/.claude/skills/references"
cat > "$no_company/.claude/skills/references/example.md" <<'MD'
Neutral placeholder only.
MD
"$SCANNER" --workspace "$no_company" --source workspace --blocking >/tmp/scan-template-leaks-selftest-no-company.out

echo "PASS: scan-template-leaks selftest"
