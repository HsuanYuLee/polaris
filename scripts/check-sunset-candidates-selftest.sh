#!/usr/bin/env bash
# Selftest for check-sunset-candidates.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/check-sunset-candidates.sh"
TMP_DIR="$(mktemp -d -t sunset-candidates.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p \
  "$TMP_DIR/scripts" \
  "$TMP_DIR/.claude/skills/references" \
  "$TMP_DIR/.claude/skills/refinement" \
  "$TMP_DIR/.claude/skills/standup" \
  "$TMP_DIR/.claude/rules" \
  "$TMP_DIR/docs-manager/src/content/docs"

cat > "$TMP_DIR/scripts/migrate-old-thing.sh" <<'SH'
#!/usr/bin/env bash
echo old
SH

cat > "$TMP_DIR/scripts/check-active-thing.sh" <<'SH'
#!/usr/bin/env bash
echo active
SH

cat > "$TMP_DIR/.claude/skills/references/INDEX.md" <<'MD'
# Index

- [stale-reference.md](stale-reference.md)
- [active-reference.md](active-reference.md)
MD

cat > "$TMP_DIR/.claude/skills/references/stale-reference.md" <<'MD'
# Stale Reference
MD

cat > "$TMP_DIR/.claude/skills/references/active-reference.md" <<'MD'
# Active Reference
MD

cat > "$TMP_DIR/.claude/skills/refinement/SKILL.md" <<'MD'
---
name: refinement
---
# refinement
MD

cat > "$TMP_DIR/.claude/skills/standup/SKILL.md" <<'MD'
---
name: standup
---
# standup
MD

cat > "$TMP_DIR/.claude/rules/use-active.md" <<'MD'
Run check-active-thing.sh and read active-reference.md.
MD

json="$("$SCRIPT" --root "$TMP_DIR" --json)"

python3 - "$json" <<'PY'
import json
import sys

rows = json.loads(sys.argv[1])
by_target = {row["target"]: row for row in rows}

assert by_target["scripts/migrate-old-thing.sh"]["posture"] == "sunset_ready"
assert by_target["scripts/check-active-thing.sh"]["posture"] == "supporting_gate"
assert by_target[".claude/skills/references/stale-reference.md"]["posture"] == "sunset_candidate"
assert by_target[".claude/skills/references/active-reference.md"]["posture"] == "noncore_owned"
assert by_target[".claude/skills/refinement/SKILL.md"]["posture"] == "core_chain"
assert by_target[".claude/skills/standup/SKILL.md"]["posture"] == "sunset_candidate"

required = {
    "target",
    "type",
    "posture",
    "replacement_authority",
    "active_consumers",
    "action",
    "verification",
}
for row in rows:
    missing = required - row.keys()
    assert not missing, (row, missing)
PY

"$SCRIPT" --root "$TMP_DIR" --verify-ledger >/dev/null

echo "check-sunset-candidates self-test PASS"
