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
---
name: acme
scope: company-only
company: acme
---
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

# --- the company carve-out is unconditional ----------------------------------
# It mirrors the sync copy set, which does not vary by delivery destination.
strict="$tmpdir/strict"
mkdir -p "$strict/acme" "$strict/.claude/skills/acme" "$strict/.claude/skills/references"
cp "$workspace/acme/workspace-config.yaml" "$strict/acme/workspace-config.yaml"
cat > "$strict/.claude/skills/acme/SKILL.md" <<'MD'
---
name: acme
scope: company-only
company: acme
---
Company-specific ACME-999 lives here.
MD
cat > "$strict/.claude/skills/references/neutral.md" <<'MD'
Neutral placeholder only.
MD

"$SCANNER" --workspace "$strict" --source workspace --blocking \
  >/tmp/scan-template-leaks-selftest-carveout.out \
  || { echo "selftest failed: a company skill directory should not be flagged" >&2; exit 1; }

# --only-path narrows a scan for triage without changing what counts as a leak.
"$SCANNER" --workspace "$strict" --source workspace --blocking \
  --only-path .claude/skills/references/neutral.md >/tmp/scan-template-leaks-selftest-scoped.out \
  || { echo "selftest failed: scan scoped to a clean path should pass" >&2; exit 1; }

# A company skill at the depth the runtime actually registers. The old carve-out
# keyed off the directory being named after a company, which forced company
# skills to sit one level too deep to ever be loaded. Here the exclusion has to
# come from the skill's own declaration.
declared="$tmpdir/declared"
mkdir -p "$declared/acme" "$declared/.claude/skills/acme-thing" "$declared/.claude/skills/plain-thing"
cp "$workspace/acme/workspace-config.yaml" "$declared/acme/workspace-config.yaml"
cat > "$declared/.claude/skills/acme-thing/SKILL.md" <<'MD'
---
name: acme-thing
scope: company-only
company: acme
---
Company-specific ACME-999 lives here, at a depth the runtime registers.
MD
cat > "$declared/.claude/skills/plain-thing/SKILL.md" <<'MD'
---
name: plain-thing
---
Shared skill that happens to mention ACME-999.
MD

set +e
"$SCANNER" --workspace "$declared" --source workspace --blocking \
  --only-path .claude/skills/acme-thing/SKILL.md \
  >/tmp/scan-template-leaks-selftest-declared.out 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] \
  || { echo "selftest failed: scope: company-only should carry the carve-out" >&2; exit 1; }

# The declaration is what buys the exemption, so a skill without it stays caught
# even though it sits at exactly the same depth.
set +e
"$SCANNER" --workspace "$declared" --source workspace --blocking \
  --only-path .claude/skills/plain-thing/SKILL.md \
  >/tmp/scan-template-leaks-selftest-undeclared.out 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] \
  || { echo "selftest failed: an undeclared skill at the same depth must still be flagged" >&2; exit 1; }

# The declaration is what buys the exemption, and it does so for every delivery:
# the exemption tracks what sync copies, not where a given delivery is headed.
set +e
"$SCANNER" --workspace "$declared" --source workspace --blocking \
  --only-path .claude/skills/acme-thing/SKILL.md \
  >/tmp/scan-template-leaks-selftest-declared-again.out 2>&1
rc=$?
set -e
[[ "$rc" -eq 0 ]] \
  || { echo "selftest failed: the company-only exemption must not depend on destination" >&2; exit 1; }

# Namespace mode: the repo's convention keeps company skills at
# .claude/skills/{ns}/{name}/ with a depth-one symlink for registration. The
# files beside SKILL.md — scripts, references, fixtures — declare nothing
# themselves, so the exemption has to resolve through the skill that owns them.
# The namespace here is deliberately NOT named after any configured company:
# if this case only passes when the directory name matches a company, the
# answer is back in the path.
nested="$tmpdir/nested"
mkdir -p "$nested/acme" "$nested/.claude/skills/teamx/log-search/references"
cp "$workspace/acme/workspace-config.yaml" "$nested/acme/workspace-config.yaml"
cat > "$nested/.claude/skills/teamx/log-search/SKILL.md" <<'MD'
---
name: log-search
scope: company-only
company: acme
---
Company-specific ACME-999 lives here.
MD
cat > "$nested/.claude/skills/teamx/log-search/references/schema.md" <<'MD'
ACME-999 appears in a file that declares nothing of its own.
MD

"$SCANNER" --workspace "$nested" --source workspace --blocking \
  >/tmp/scan-template-leaks-selftest-nested.out 2>&1 \
  || { echo "selftest failed: a namespace-mode company skill and its sibling files must be excluded" >&2; exit 1; }

echo "PASS: scan-template-leaks selftest"
