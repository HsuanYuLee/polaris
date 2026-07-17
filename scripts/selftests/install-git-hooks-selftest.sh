#!/usr/bin/env bash
# Purpose: selftest for scripts/install-git-hooks.sh — verify the installer
#   writes the pre-push / pre-commit hooks, the installed pre-push hook delegates
#   to the canonical portable gate scripts, and NO retired quality-gate-marker
#   logic remains in either the installed hook, the Claude pre-push hook, or the
#   codex guarded-push wrapper output.
#
#   DP-360 T3: the Claude pre-push gate no longer unconditionally early-exits on
#   main / master / develop — every named branch now runs the delivery gates plus
#   the affected-scoped selftest closure. The guarded-push dry-run check below is
#   therefore made HERMETIC: it copies the real wrapper + adapter + Claude hook
#   into a self-contained temp repo with STUB gates (green no-ops) + a STUB
#   affected-runner, so the dry-run runs the full (no-early-exit) gate path against
#   the temp repo and still completes, while the retired-marker assertion stays
#   exact. This mirrors pre-push-affected-gate-selftest.sh's hermetic-fixture
#   pattern; it does NOT weaken the assertion — a retired-marker advisory anywhere
#   in the output still fails the test.
# Inputs:  none (builds isolated temp git repos).
# Outputs: exit 0 + PASS line on success; non-zero + diagnostic on failure.
# Side effects: creates and removes temp dirs under $TMPDIR.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$SCRIPT_DIR/install-git-hooks.sh"

tmp="$(mktemp -d -t install-git-hooks-selftest.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo/scripts/gates"
git init -b main "$repo" >/dev/null
git -C "$repo" config user.email selftest@example.test
git -C "$repo" config user.name "Self Test"
printf 'base\n' > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -m "base" >/dev/null

cp "$INSTALLER" "$repo/scripts/install-git-hooks.sh"
chmod +x "$repo/scripts/install-git-hooks.sh"

bash "$repo/scripts/install-git-hooks.sh" >/dev/null

pre_push="$repo/.git/hooks/pre-push"
pre_commit="$repo/.git/hooks/pre-commit"

[[ -x "$pre_push" ]] || { echo "[selftest] pre-push hook was not installed" >&2; exit 1; }
[[ -x "$pre_commit" ]] || { echo "[selftest] pre-commit hook was not installed" >&2; exit 1; }

grep -q 'gate-ci-local.sh' "$pre_push" || { echo "[selftest] pre-push does not delegate ci-local gate" >&2; exit 1; }
grep -q 'gate-revision-rebase.sh' "$pre_push" || { echo "[selftest] pre-push does not delegate revision-rebase gate" >&2; exit 1; }
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

# ---------------------------------------------------------------------------
# Guarded-push dry-run check (hermetic).
#
# The codex guarded-push wrapper drives the Claude pre-push gate. Under DP-360 T3
# the gate no longer early-exits on main, so a bare repo would now (correctly) fail
# the live delivery gates. To keep this check asserting the wrapper's contract —
# the dry-run completes AND emits no retired quality-gate-marker advisory — we run
# it against a SELF-CONTAINED guard repo: the real wrapper + adapter + Claude hook
# are copied in, downstream gates are green STUBS, and the affected-runner is a
# green STUB. The gate path therefore runs end-to-end (proving no early-exit
# dependency) and the retired-marker grep below stays exact and fail-closed.
# ---------------------------------------------------------------------------
WRAPPER="$SCRIPT_DIR/codex-guarded-git-push.sh"
ADAPTER="$SCRIPT_DIR/gate-hook-adapter.sh"
CC_HOOK="$SCRIPT_DIR/../.claude/hooks/pre-push-quality-gate.sh"

[[ -f "$WRAPPER" ]] || { echo "[selftest] guarded-push wrapper missing: $WRAPPER" >&2; exit 1; }
[[ -f "$ADAPTER" ]] || { echo "[selftest] gate-hook-adapter missing: $ADAPTER" >&2; exit 1; }
[[ -f "$CC_HOOK" ]] || { echo "[selftest] Claude pre-push hook missing: $CC_HOOK" >&2; exit 1; }

guard="$tmp/guard"
mkdir -p "$guard/.claude/hooks" "$guard/scripts/gates"

# Real wrapper + adapter + Claude hook (each resolves ROOT_DIR/GATES_DIR from its
# own location, so the copies stay anchored to the guard repo, not the worktree).
cp "$WRAPPER" "$guard/scripts/codex-guarded-git-push.sh"
cp "$ADAPTER" "$guard/scripts/gate-hook-adapter.sh"
cp "$CC_HOOK" "$guard/.claude/hooks/pre-push-quality-gate.sh"
chmod +x "$guard/scripts/codex-guarded-git-push.sh" "$guard/scripts/gate-hook-adapter.sh" "$guard/.claude/hooks/pre-push-quality-gate.sh"

# Branch-name ASCII validator (the standalone gate near the top of the hook references it).
cat >"$guard/scripts/validate-branch-name-ascii.sh" <<'V'
#!/usr/bin/env bash
exit 0
V
chmod +x "$guard/scripts/validate-branch-name-ascii.sh"

# Downstream delivery gates: green no-op stubs. (gate-runtime-instruction-manifest
# is intentionally absent so its `-x` guard is simply skipped.)
for g in gate-ci-local gate-evidence-producer-whitelist gate-revision-rebase gate-evidence gate-changeset gate-no-tracked-specs gate-template-leaks; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$guard/scripts/gates/$g.sh"
  chmod +x "$guard/scripts/gates/$g.sh"
done

# Affected-scoped selftest closure runner: green stub (the hook invokes it on a
# content-bearing push under DP-360 T3).
printf '#!/usr/bin/env bash\nexit 0\n' >"$guard/scripts/selftest-affected-runner.sh"
chmod +x "$guard/scripts/selftest-affected-runner.sh"

git init -b main "$guard" >/dev/null
git -C "$guard" config user.email selftest@example.test
git -C "$guard" config user.name "Self Test"
printf 'base\n' > "$guard/README.md"
git -C "$guard" add -A
git -C "$guard" commit -q -m base

guard_out="$tmp/guard-push.out"
set +e
GATE_PROJECT_DIR="$guard" bash "$guard/scripts/codex-guarded-git-push.sh" --dry-run >"$guard_out" 2>&1
guard_rc=$?
set -e

if [[ "$guard_rc" -ne 0 ]]; then
  echo "[selftest] codex guarded push dry-run did not pass against hermetic stub repo (exit $guard_rc)" >&2
  cat "$guard_out" >&2
  exit 1
fi

if grep -qE 'First push detected|No quality gate marker|quality gate marker' "$guard_out"; then
  echo "[selftest] codex guarded push emitted retired quality marker advisory" >&2
  cat "$guard_out" >&2
  exit 1
fi

echo "[install-git-hooks-selftest] PASS"
