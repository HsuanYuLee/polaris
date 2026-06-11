#!/usr/bin/env bash
# Purpose: Verify scan-template-leaks.sh is gitignore-aware (DP-305 D5 / AC5 / AC-NEG3).
# Inputs:  none (builds a self-contained temp git workspace fixture)
# Outputs: stdout PASS line on success; exit 1 on any assertion failure.
# Side effects: creates/removes a temp git repo under $TMPDIR.
#
# Contract under test:
#   AC5     — scanner skips git-ignored files via `git check-ignore`; a
#             gitignored file whose content looks like a leak produces NO hit;
#             tracked-file leak detection stays unchanged.
#   AC-NEG3 — gitignore-aware skip must NOT skip tracked files; a tracked file
#             whose content looks like a leak still fails closed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCANNER="$SCRIPT_DIR/scan-template-leaks.sh"

tmpdir="$(mktemp -d -t scan-template-leaks-gitignore.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

workspace="$tmpdir/workspace"
mkdir -p "$workspace/acme" "$workspace/.claude/skills/references"

# Workspace must be a real git repo so `git check-ignore` resolves.
git -C "$workspace" init -q
git -C "$workspace" config user.email selftest@example.com
git -C "$workspace" config user.name selftest

cat > "$workspace/acme/workspace-config.yaml" <<'YAML'
jira:
  instance: acme.atlassian.net
  projects:
    - key: ACME
github:
  org: acme-inc
YAML

# .gitignore exempts a local session-state file (mirrors .claude/active-thread.md).
cat > "$workspace/.gitignore" <<'GI'
.claude/active-thread.md
GI

# (1) Gitignored file with leak-looking content — must be SKIPPED (AC5).
cat > "$workspace/.claude/active-thread.md" <<'MD'
Working on ACME-123 in the acme repo right now.
MD

# Track the config + gitignore so patterns load and ignore rules apply.
git -C "$workspace" add acme/workspace-config.yaml .gitignore
git -C "$workspace" commit -q -m "fixture base"

# ---- AC5: gitignored leak file produces NO hit; scan is clean (exit 0) ----
set +e
"$SCANNER" --workspace "$workspace" --source workspace --blocking \
  >"$tmpdir/ac5.out" 2>"$tmpdir/ac5.err"
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "AC5 failed: gitignored leak file should be skipped, scan must pass clean (rc=$rc)" >&2
  cat "$tmpdir/ac5.out" >&2
  exit 1
fi
if grep -q "active-thread.md" "$tmpdir/ac5.out"; then
  echo "AC5 failed: gitignored .claude/active-thread.md must not appear as a hit" >&2
  cat "$tmpdir/ac5.out" >&2
  exit 1
fi
if grep -q "ACME-123" "$tmpdir/ac5.out"; then
  echo "AC5 failed: leak content inside a gitignored file must not be flagged" >&2
  exit 1
fi

# ---- AC-NEG3: tracked file with the same leak content STILL fails closed ----
cat > "$workspace/.claude/skills/references/example.md" <<'MD'
Do not use ACME-123 in shared templates.
MD
git -C "$workspace" add .claude/skills/references/example.md
git -C "$workspace" commit -q -m "tracked leak"

set +e
"$SCANNER" --workspace "$workspace" --source workspace --blocking \
  >"$tmpdir/neg3.out" 2>"$tmpdir/neg3.err"
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "AC-NEG3 failed: tracked file with leak content must fail closed (rc=0)" >&2
  cat "$tmpdir/neg3.out" >&2
  exit 1
fi
if ! grep -q "ACME-123" "$tmpdir/neg3.out"; then
  echo "AC-NEG3 failed: expected tracked ACME-123 leak in output" >&2
  cat "$tmpdir/neg3.out" >&2
  exit 1
fi
if ! grep -q "example.md" "$tmpdir/neg3.out"; then
  echo "AC-NEG3 failed: expected tracked example.md as the leaking file" >&2
  exit 1
fi

echo "PASS: scan-template-leaks gitignore-aware selftest"
