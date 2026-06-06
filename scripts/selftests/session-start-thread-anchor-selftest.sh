#!/usr/bin/env bash
# Purpose: Hermetic selftest for .claude/hooks/session-start-thread-anchor.sh (DP-290 T2).
#          Covers AC1 (anchor + 「下一步」injected on startup), AC4 (missing anchor =>
#          exit 0 + fail-open notice), AC5 (settings.json hooks.SessionStart matcher
#          startup points at an existing executable hook), AC6 (hook body uses only
#          cat + git, no curl/wget/build), AC-NEG1 (no PATH=/env dumps in stdout),
#          AC-NEG2 (each error branch — non-git dir, failing git status, missing anchor —
#          exits 0).
# Inputs:  None (builds its own tmp git repos as CLAUDE_PROJECT_DIR).
# Outputs: Prints PASS on success; exits non-zero with FAIL on any assertion failure.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/.claude/hooks/session-start-thread-anchor.sh"
SETTINGS="$ROOT/.claude/settings.json"
WRITER="$ROOT/scripts/update-active-thread.sh"
TMP="$(mktemp -d -t dp290-session-start.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -f "$HOOK" ] || fail "hook script not found: $HOOK"

# ---- AC1: fresh-session injection contains anchor + 「下一步」 ----
PROJECT="$TMP/p1"
mkdir -p "$PROJECT"
git -C "$PROJECT" init -q
git -C "$PROJECT" config user.email test@example.com
git -C "$PROJECT" config user.name "SessionStart Test"
git -C "$PROJECT" commit -q --allow-empty -m base
git -C "$PROJECT" checkout -q -b feat/dp290-handoff

POLARIS_ACTIVE_THREAD_STAMP="2026-06-06T00:00:00Z" CLAUDE_PROJECT_DIR="$PROJECT" \
  bash "$WRITER" --content $'# 下一步\n\nResume DP-290 V1 verification next.' >/dev/null

OUT1="$TMP/out1.txt"
printf '{"hook_event_name":"SessionStart","matcher":"startup"}' \
  | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOK" >"$OUT1" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "AC1: hook did not exit 0 on startup (rc=$rc)"
grep -q 'active-thread anchor' "$OUT1" || fail "AC1: anchor marker missing from stdout"
grep -q '下一步' "$OUT1" || fail "AC1: 「下一步」section missing from stdout"
grep -q 'branch: feat/dp290-handoff' "$OUT1" || fail "AC1: branch name missing from stdout"

# ---- AC-NEG1: no env dump / secrets in output ----
if grep -Eq '(^|[^A-Za-z_])PATH=' "$OUT1"; then
  fail "AC-NEG1: PATH= env dump detected in hook output"
fi
if grep -Eq '^[A-Z_]{3,}=' "$OUT1"; then
  fail "AC-NEG1: env-var-style dump (VAR=...) detected in hook output"
fi

# ---- AC4 / AC-NEG2(missing anchor): delete anchor => exit 0 + fail-open notice ----
rm -f "$PROJECT/.claude/active-thread.md"
OUT_MISSING="$TMP/out_missing.txt"
printf '{}' | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOK" >"$OUT_MISSING" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "AC4: missing anchor did not exit 0 (rc=$rc)"
grep -q 'fail-open' "$OUT_MISSING" || fail "AC4: missing-anchor fail-open notice absent"

# ---- AC-NEG2: non-git directory => exit 0 ----
NONGIT="$TMP/nongit"
mkdir -p "$NONGIT"
OUT_NONGIT="$TMP/out_nongit.txt"
# Unset CLAUDE_PROJECT_DIR and run from a non-git dir so git rev-parse fails.
printf '{}' | env -u CLAUDE_PROJECT_DIR bash -c 'cd "$1" && bash "$2"' _ "$NONGIT" "$HOOK" >"$OUT_NONGIT" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "AC-NEG2: non-git directory did not exit 0 (rc=$rc)"
grep -q 'fail-open' "$OUT_NONGIT" || fail "AC-NEG2: non-git fail-open notice absent"

# ---- AC-NEG2: failing git status => exit 0 ----
# Point CLAUDE_PROJECT_DIR at a dir that has a .claude anchor but is NOT a git repo,
# so `git -C ... status` fails while the project dir still resolves.
BROKEN="$TMP/broken"
mkdir -p "$BROKEN/.claude"
printf 'anchor body\n' >"$BROKEN/.claude/active-thread.md"
OUT_BROKEN="$TMP/out_broken.txt"
printf '{}' | CLAUDE_PROJECT_DIR="$BROKEN" bash "$HOOK" >"$OUT_BROKEN" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "AC-NEG2: failing git status did not exit 0 (rc=$rc)"

# ---- AC6: hook body uses only cat + git; no network/build commands ----
for forbidden in 'curl' 'wget' 'npm ' 'pnpm ' 'yarn ' 'make ' 'go build' 'docker '; do
  if grep -Eq "(^|[^[:alnum:]_-])${forbidden}" "$HOOK"; then
    fail "AC6: hook references forbidden network/build command: '${forbidden}'"
  fi
done
grep -q 'git ' "$HOOK" || fail "AC6: hook does not use git (expected git branch/status)"
grep -q 'cat ' "$HOOK" || fail "AC6: hook does not use cat (expected to cat the anchor)"

# ---- AC5: settings.json hooks.SessionStart matcher startup -> existing executable hook ----
[ -f "$SETTINGS" ] || fail "AC5: settings.json not found: $SETTINGS"
if ! command -v jq >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:jq" >&2
  fail "AC5: jq required to assert settings.json hooks.SessionStart (run 'mise install')"
fi

CMD="$(jq -r '
  .hooks.SessionStart[]?
  | select(.matcher == "startup")
  | .hooks[]?
  | .command
' "$SETTINGS" | grep 'session-start-thread-anchor.sh' | head -n1)"
[ -n "$CMD" ] || fail "AC5: no SessionStart matcher=startup entry pointing at session-start-thread-anchor.sh"

# Resolve the command's hook path (strip the bash wrapper + $CLAUDE_PROJECT_DIR prefix).
HOOK_REL="$(printf '%s' "$CMD" | sed -E 's#.*\$CLAUDE_PROJECT_DIR/##; s#".*##')"
[ -n "$HOOK_REL" ] || fail "AC5: could not parse hook path from command: $CMD"
RESOLVED="$ROOT/$HOOK_REL"
[ -f "$RESOLVED" ] || fail "AC5: registered hook path does not exist: $RESOLVED"
[ -x "$RESOLVED" ] || fail "AC5: registered hook is not executable: $RESOLVED"

echo "PASS: session-start-thread-anchor selftest (AC1/AC4/AC5/AC6/AC-NEG1/AC-NEG2)"
