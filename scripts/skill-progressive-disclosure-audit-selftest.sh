#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCANNER="$ROOT/scripts/skill-progressive-disclosure-audit.sh"

tmpdir="$(mktemp -d -t skill-progressive-disclosure.XXXXXX)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

workspace="$tmpdir/workspace"
mkdir -p "$workspace/.claude/skills"/{small,p2,p1,p0,multi,script}

write_skill() {
  local skill="$1"
  local words="$2"
  local extra="${3:-}"
  local file="$workspace/.claude/skills/$skill/SKILL.md"

  {
    cat <<EOF
---
name: $skill
description: Fixture skill for disclosure audit.
---

# Fixture

EOF
    for ((i = 1; i <= words; i += 1)); do
      printf 'word%s ' "$i"
    done
    printf '\n%s\n' "$extra"
  } > "$file"
}

write_skill small 80
write_skill p2 520
write_skill p1 780
write_skill p0 1040
write_skill multi 120 $'## Mode One\n\nDo one thing.\n\n## Mode Two\n\nDo another thing.\n\n## Mode Three\n\nDo a third thing.'
write_skill script 140 $'```bash\nfor file in "$ROOT"/.claude/skills/*/SKILL.md; do\n  echo "$file"\ndone\n```'

before_hash="$(find "$workspace/.claude/skills" -type f -name 'SKILL.md' -print0 | sort -z | xargs -0 shasum)"

"$SCANNER" --root "$workspace" >/tmp/skill-disclosure-summary.out
grep -q "Skill Progressive Disclosure Audit" /tmp/skill-disclosure-summary.out
grep -q "p0.*P0" /tmp/skill-disclosure-summary.out
grep -q "p1.*P1" /tmp/skill-disclosure-summary.out
grep -q "p2.*P2" /tmp/skill-disclosure-summary.out
grep -q "small.*INFO" /tmp/skill-disclosure-summary.out
grep -q "multi.*multi-mode" /tmp/skill-disclosure-summary.out
grep -q "script.*script-candidate" /tmp/skill-disclosure-summary.out

"$SCANNER" --root "$workspace" --markdown >/tmp/skill-disclosure-summary.md
grep -q "# Skill Progressive Disclosure Audit" /tmp/skill-disclosure-summary.md
grep -q "## Summary" /tmp/skill-disclosure-summary.md
grep -q "| p0 | P0 |" /tmp/skill-disclosure-summary.md

after_hash="$(find "$workspace/.claude/skills" -type f -name 'SKILL.md' -print0 | sort -z | xargs -0 shasum)"
if [[ "$before_hash" != "$after_hash" ]]; then
  echo "FAIL: scanner modified fixture SKILL.md files" >&2
  exit 1
fi

if find "$workspace" -path '*/docs-manager/src/content/docs/specs/*' -print -quit | grep -q .; then
  echo "FAIL: scanner wrote specs artifacts" >&2
  exit 1
fi

echo "PASS: skill progressive disclosure audit selftest"
