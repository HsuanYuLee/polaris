#!/usr/bin/env bash
# Purpose: Hermetic selftest for keeping company skills out of the Polaris
#          template. The exclusion must key off the skill's own `scope:
#          company-only` declaration, not off the directory being named after a
#          company: company skills now sit at .claude/skills/{company}-{name}/,
#          the only depth the runtime registers, so their location no longer
#          distinguishes them from shared skills.
# Inputs: none (builds a self-contained instance + template under a tmpdir)
# Outputs: stdout PASS lines; exit 0 on success, non-zero on first failed assertion
# Side effects: creates and removes a tmpdir; never touches the live ~/polaris template

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$SCRIPT_DIR/sync-to-polaris.sh"

fail() {
  echo "[selftest] FAIL: $*" >&2
  exit 1
}

[[ -f "$SYNC" ]] || fail "sync-to-polaris.sh not found at $SYNC"

tmpdir="$(mktemp -d -t sync-skill-scope.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

INSTANCE="$tmpdir/instance"
TEMPLATE="$tmpdir/template"

mkdir -p "$INSTANCE/.claude/skills" "$INSTANCE/.claude/rules" \
         "$INSTANCE/.claude/hooks" "$INSTANCE/scripts"
printf '3.99.999\n' >"$INSTANCE/VERSION"

INSTANCE_SYNC="$INSTANCE/scripts/sync-to-polaris.sh"
cp "$SYNC" "$INSTANCE_SYNC"
chmod +x "$INSTANCE_SYNC"

# A company skill, at the registered depth, declaring what it is.
mkdir -p "$INSTANCE/.claude/skills/acme-deploy"
cat >"$INSTANCE/.claude/skills/acme-deploy/SKILL.md" <<'MD'
---
name: acme-deploy
description: Company-specific deploy flow.
scope: company-only
company: acme
---
Internal hostnames and channel ids live here.
MD

# A shared skill sitting beside it, distinguishable only by the declaration.
mkdir -p "$INSTANCE/.claude/skills/shared-thing"
cat >"$INSTANCE/.claude/skills/shared-thing/SKILL.md" <<'MD'
---
name: shared-thing
description: Generic skill that belongs in the template.
---
Generic content.
MD

# A maintainer-only skill: a separate exemption that must keep working.
mkdir -p "$INSTANCE/.claude/skills/maintainer-thing"
cat >"$INSTANCE/.claude/skills/maintainer-thing/SKILL.md" <<'MD'
---
name: maintainer-thing
description: Maintainer-only skill.
scope: maintainer-only
---
Maintainer content.
MD

mkdir -p "$TEMPLATE/.claude/skills" "$TEMPLATE/.claude/rules"
git -C "$TEMPLATE" init -q
git -C "$TEMPLATE" config user.email selftest@example.com
git -C "$TEMPLATE" config user.name selftest
git -C "$TEMPLATE" commit -q --allow-empty -m "fixture template"

output="$("$INSTANCE_SYNC" --polaris "$TEMPLATE" 2>&1)" \
  || { printf '%s\n' "$output" >&2; fail "sync-to-polaris exited non-zero"; }

[[ ! -e "$TEMPLATE/.claude/skills/acme-deploy" ]] \
  || fail "a skill declaring scope: company-only reached the template"
grep -q "acme-deploy/ (company-only, skipped)" <<<"$output" \
  || fail "sync output did not report the company skill as skipped"

[[ -f "$TEMPLATE/.claude/skills/shared-thing/SKILL.md" ]] \
  || fail "a shared skill at the same depth was not synced"

[[ ! -e "$TEMPLATE/.claude/skills/maintainer-thing" ]] \
  || fail "maintainer-only exemption stopped working"

echo "[selftest] PASS: scope: company-only keeps a skill out of the template"
echo "[selftest] PASS: a shared skill at the same depth still syncs"
echo "[selftest] PASS: the maintainer-only exemption is unaffected"
