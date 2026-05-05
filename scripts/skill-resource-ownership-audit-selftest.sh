#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT="$ROOT/scripts/skill-resource-ownership-audit.sh"
TMPDIR="$(mktemp -d -t skill-resource-ownership-audit.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.claude/skills"/{alpha,beta,gamma,references}
mkdir -p "$TMPDIR/.claude/skills/alpha/references"
mkdir -p "$TMPDIR/scripts"

cat > "$TMPDIR/.claude/skills/alpha/SKILL.md" <<'MD'
---
name: alpha
description: Alpha skill.
---

# Alpha

Read `single-flow.md` and `private-note.md`.
MD

cat > "$TMPDIR/.claude/skills/beta/SKILL.md" <<'MD'
---
name: beta
description: Beta skill.
---

# Beta

Read `shared-flow.md`.
MD

cat > "$TMPDIR/.claude/skills/gamma/SKILL.md" <<'MD'
---
name: gamma
description: Gamma skill.
---

# Gamma

Read `shared-flow.md`.
MD

cat > "$TMPDIR/.claude/skills/references/INDEX.md" <<'MD'
# References Index

| File | Description | Triggers |
|------|-------------|----------|
| [single-flow.md](single-flow.md) | Alpha-only flow | alpha |
| [shared-flow.md](shared-flow.md) | Shared flow | beta, gamma |
| [index-only.md](index-only.md) | Ambiguous index-only flow | alpha |
MD

cat > "$TMPDIR/.claude/skills/references/single-flow.md" <<'MD'
# Single Flow

Alpha-only operational steps.
MD

cat > "$TMPDIR/.claude/skills/references/shared-flow.md" <<'MD'
# Shared Flow

Shared operational steps.
MD

cat > "$TMPDIR/.claude/skills/references/index-only.md" <<'MD'
# Index Only

No direct consumer mentions this file.
MD

cat > "$TMPDIR/.claude/skills/alpha/references/private-note.md" <<'MD'
# Private Note

Alpha private note.
MD

cat > "$TMPDIR/scripts/one-off.sh" <<'SH'
#!/usr/bin/env bash
echo one-off
SH
chmod +x "$TMPDIR/scripts/one-off.sh"

before="$(find "$TMPDIR" -type f | sort)"
output="$(bash "$AUDIT" --root "$TMPDIR" --markdown)"
after="$(find "$TMPDIR" -type f | sort)"

if [[ "$before" != "$after" ]]; then
  echo "selftest failed: audit modified fixture files" >&2
  exit 1
fi

printf '%s\n' "$output" | rg -n 'single-flow\.md.*candidate_rehome' >/dev/null
printf '%s\n' "$output" | rg -n 'shared-flow\.md.*keep_shared' >/dev/null
printf '%s\n' "$output" | rg -n 'index-only\.md.*needs_manual_review' >/dev/null
printf '%s\n' "$output" | rg -n 'private-note\.md.*keep_private' >/dev/null
printf '%s\n' "$output" | rg -n 'resource_path.*kind.*consumers.*suggested_owner.*action' >/dev/null

echo "skill-resource-ownership-audit selftest PASS"
