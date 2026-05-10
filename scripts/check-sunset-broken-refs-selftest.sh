#!/usr/bin/env bash
# Selftest for check-sunset-broken-refs.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/check-sunset-broken-refs.sh"
TMP_DIR="$(mktemp -d -t sunset-broken-refs.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

git init "$TMP_DIR" >/dev/null
git -C "$TMP_DIR" config user.email test@example.com
git -C "$TMP_DIR" config user.name Test
mkdir -p "$TMP_DIR/scripts" "$TMP_DIR/.claude/skills/references" "$TMP_DIR/.claude/rules"

cat > "$TMP_DIR/scripts/remove-me.sh" <<'SH'
#!/usr/bin/env bash
echo old
SH
cat > "$TMP_DIR/.claude/rules/active.md" <<'MD'
Run remove-me.sh here.
MD
cat > "$TMP_DIR/.claude/skills/references/INDEX.md" <<'MD'
# Index

- [existing.md](existing.md)
MD
cat > "$TMP_DIR/.claude/skills/references/existing.md" <<'MD'
# Existing
MD

git -C "$TMP_DIR" add .
git -C "$TMP_DIR" commit -m init >/dev/null
git -C "$TMP_DIR" branch base
rm "$TMP_DIR/scripts/remove-me.sh"
git -C "$TMP_DIR" add -u
git -C "$TMP_DIR" commit -m remove >/dev/null

if "$SCRIPT" --root "$TMP_DIR" --base-ref base --skip-runtime-compile >/dev/null 2>&1; then
  echo "self-test failed: deleted active callsite passed" >&2
  exit 1
fi

perl -0pi -e 's/Run remove-me\.sh here\.\n//' "$TMP_DIR/.claude/rules/active.md"
git -C "$TMP_DIR" add .claude/rules/active.md
git -C "$TMP_DIR" commit -m reconnect >/dev/null
"$SCRIPT" --root "$TMP_DIR" --base-ref base --skip-runtime-compile >/dev/null

perl -0pi -e 's/existing\.md/missing.md/g' "$TMP_DIR/.claude/skills/references/INDEX.md"
git -C "$TMP_DIR" add .claude/skills/references/INDEX.md
git -C "$TMP_DIR" commit -m dead-index >/dev/null
if "$SCRIPT" --root "$TMP_DIR" --base-ref base --skip-runtime-compile >/dev/null 2>&1; then
  echo "self-test failed: dead reference index link passed" >&2
  exit 1
fi

echo "check-sunset-broken-refs self-test PASS"
