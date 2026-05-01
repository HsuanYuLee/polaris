#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$SCRIPT_DIR/install-copilot-hooks.sh"

tmp="$(mktemp -d -t install-copilot-hooks-selftest.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo/scripts/gates"
git init -b main "$repo" >/dev/null
git -C "$repo" config user.email selftest@example.test
git -C "$repo" config user.name "Self Test"
printf 'base\n' > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -m "base" >/dev/null

cp "$INSTALLER" "$repo/scripts/install-copilot-hooks.sh"
chmod +x "$repo/scripts/install-copilot-hooks.sh"

bash "$repo/scripts/install-copilot-hooks.sh" >/dev/null

pre_push="$repo/.git/hooks/pre-push"
pre_commit="$repo/.git/hooks/pre-commit"

[[ -x "$pre_push" ]] || { echo "[selftest] pre-push hook was not installed" >&2; exit 1; }
[[ -x "$pre_commit" ]] || { echo "[selftest] pre-commit hook was not installed" >&2; exit 1; }

grep -q 'gate-ci-local.sh' "$pre_push" || { echo "[selftest] pre-push does not delegate ci-local gate" >&2; exit 1; }
grep -q 'gate-evidence.sh' "$pre_push" || { echo "[selftest] pre-push does not delegate evidence gate" >&2; exit 1; }
grep -q 'gate-changeset.sh' "$pre_push" || { echo "[selftest] pre-push does not delegate changeset gate" >&2; exit 1; }

if grep -qE '/tmp/\\.quality-gate-passed|No quality gate marker|quality gate marker' "$pre_push"; then
  echo "[selftest] pre-push still contains retired quality marker logic" >&2
  exit 1
fi

if grep -qE '/tmp/\\.quality-gate-passed|No quality gate marker|quality gate marker' "$SCRIPT_DIR/../.claude/hooks/pre-push-quality-gate.sh"; then
  echo "[selftest] Claude pre-push gate still contains retired quality marker logic" >&2
  exit 1
fi

GATE_PROJECT_DIR="$repo" bash "$SCRIPT_DIR/codex-guarded-git-push.sh" --dry-run >/tmp/install-copilot-hooks-selftest-push.out
if grep -qE 'First push detected|No quality gate marker|quality gate marker' /tmp/install-copilot-hooks-selftest-push.out; then
  echo "[selftest] codex guarded push emitted retired quality marker advisory" >&2
  cat /tmp/install-copilot-hooks-selftest-push.out >&2
  exit 1
fi
rm -f /tmp/install-copilot-hooks-selftest-push.out

echo "[install-copilot-hooks-selftest] PASS"
