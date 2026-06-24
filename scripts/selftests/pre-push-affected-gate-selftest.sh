#!/usr/bin/env bash
# Purpose: selftest for the DP-360 T3 pre-push wiring (AC2 / AC-NEG4 / AC-NEG5):
#   .claude/hooks/pre-push-quality-gate.sh must (a) NO LONGER unconditionally
#   early-exit on main / master / develop at the legacy :76 case; (b) run the
#   delivery gates on feat/* / chore/* / main as well as task/* / fix/*; (c) invoke
#   the affected-scoped selftest closure runner on a content-bearing push; (d)
#   propagate the runner's fail-closed exit (injected affected red -> hook exit≠0),
#   with no env bypass and no NO_CI_LOCAL_CONFIGURED fail-open.
#   The hook is driven against HERMETIC temp git repos with STUB gates + a STUB
#   affected-runner, so the live full corpus (~319 selftests, ~160min) and the live
#   .git/hooks are never touched.
# Inputs:  none (builds isolated temp git repos; feeds Claude-Code-runtime push JSON).
# Outputs: exit 0 + PASS line on success; non-zero + diagnostic on failure.
# Side effects: creates and removes temp dirs under $TMPDIR.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"      # .../scripts
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"             # workspace root
CC_HOOK="$ROOT_DIR/.claude/hooks/pre-push-quality-gate.sh"

[[ -f "$CC_HOOK" ]] || { echo "FAIL: pre-push hook missing: $CC_HOOK" >&2; exit 1; }

tmp="$(mktemp -d -t pre-push-affected.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "[selftest][$1] $2" >&2; exit 1; }

# build_repo — materialize a hermetic git repo on branch $2 with:
#   - the REAL pre-push-quality-gate.sh under .claude/hooks/ (resolves ROOT_DIR/GATES_DIR
#     from its own location, so a self-contained copy keeps it anchored to the temp repo)
#   - STUB downstream gates under scripts/gates/ (all green; gate-ci-local emits a marker)
#   - a STUB scripts/selftest-affected-runner.sh that records invocation + obeys an
#     injected exit code via the AFFECTED_STUB_RC file (so we assert wiring, not corpus)
#   - one extra committed file on the branch so the push diff is non-empty
# Args: $1 = repo path, $2 = branch name. Echoes nothing.
build_repo() {
  local repo="$1" branch="$2"
  mkdir -p "$repo/.claude/hooks" "$repo/scripts/gates" "$repo/scripts"

  cp "$CC_HOOK" "$repo/.claude/hooks/pre-push-quality-gate.sh"
  chmod +x "$repo/.claude/hooks/pre-push-quality-gate.sh"

  # Branch-name ASCII validator (the standalone gate near the top references it).
  cat >"$repo/scripts/validate-branch-name-ascii.sh" <<'V'
#!/usr/bin/env bash
exit 0
V
  chmod +x "$repo/scripts/validate-branch-name-ascii.sh"

  # gate-ci-local stub: records that it ran (proves branch coverage reached it) and
  # passes. This stands in for the real ci-local gate.
  cat >"$repo/scripts/gates/gate-ci-local.sh" <<STUB
#!/usr/bin/env bash
set -euo pipefail
touch "$repo/.ci-local-ran"
exit 0
STUB
  chmod +x "$repo/scripts/gates/gate-ci-local.sh"

  # Other downstream gates: green no-ops so this selftest isolates branch coverage +
  # the affected gate. (gate-runtime-instruction-manifest is intentionally absent so
  # its `-x` guard is skipped without affecting the assertions.)
  for g in gate-evidence-producer-whitelist gate-revision-rebase gate-evidence gate-changeset gate-template-leaks; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"$repo/scripts/gates/$g.sh"
    chmod +x "$repo/scripts/gates/$g.sh"
  done

  # STUB affected-runner: records invocation, echoes the changed set it received, and
  # exits with the code in $repo/.affected-stub-rc (default 0). This lets us assert the
  # hook INVOKES the runner and PROPAGATES its verdict without running the real corpus.
  cat >"$repo/scripts/selftest-affected-runner.sh" <<STUB
#!/usr/bin/env bash
set -euo pipefail
touch "$repo/.affected-ran"
cat >"$repo/.affected-stdin"
rc=0
[[ -f "$repo/.affected-stub-rc" ]] && rc="\$(cat "$repo/.affected-stub-rc")"
exit "\$rc"
STUB
  chmod +x "$repo/scripts/selftest-affected-runner.sh"

  git init -b main "$repo" >/dev/null 2>&1
  git -C "$repo" config user.email selftest@example.test
  git -C "$repo" config user.name "Self Test"
  printf 'base\n' >"$repo/README.md"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  if [[ "$branch" != "main" ]]; then
    git -C "$repo" checkout -q -b "$branch"
  fi
  # A change on the branch so the push diff (HEAD~1..HEAD) is non-empty.
  printf 'changed\n' >>"$repo/scripts/foo.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "change on $branch"
}

# run_hook <repo> -> prints exit code. Drives the Claude Code hook with a push command
# JSON payload. CLAUDE_PROJECT_DIR anchors repo resolution at the temp repo.
run_hook() {
  local repo="$1"
  local cmd="git -C $repo push origin HEAD"
  local payload
  payload="$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))')"
  set +e
  CLAUDE_PROJECT_DIR="$repo" printf '%s' "$payload" \
    | CLAUDE_PROJECT_DIR="$repo" bash "$repo/.claude/hooks/pre-push-quality-gate.sh" >/dev/null 2>&1
  local rc=$?
  set -e
  echo "$rc"
}

# ---------------------------------------------------------------------------
# Case 1 (AC2): main push no longer early-exits at :76 — downstream gates AND the
# affected runner are reached (proven by their marker files), and the hook passes
# when everything is green.
# ---------------------------------------------------------------------------
main_repo="$tmp/main"
build_repo "$main_repo" "main"
rc="$(run_hook "$main_repo")"
[[ "$rc" == "0" ]] || fail AC2-main "main push must pass when gates green (got rc=$rc)"
[[ -f "$main_repo/.ci-local-ran" ]] || fail AC2-main "main push did NOT reach gate-ci-local (still early-exiting at :76)"
[[ -f "$main_repo/.affected-ran" ]] || fail AC2-main "main push did NOT invoke the affected runner"

# ---------------------------------------------------------------------------
# Case 2 (AC2): develop + master are likewise covered (no :76 early-exit).
# ---------------------------------------------------------------------------
for b in develop master; do
  r="$tmp/$b"
  build_repo "$r" "$b"
  rc="$(run_hook "$r")"
  [[ "$rc" == "0" ]] || fail AC2-$b "$b push must pass when gates green (got rc=$rc)"
  [[ -f "$r/.ci-local-ran" ]] || fail AC2-$b "$b push did NOT reach gate-ci-local"
  [[ -f "$r/.affected-ran" ]] || fail AC2-$b "$b push did NOT invoke the affected runner"
done

# ---------------------------------------------------------------------------
# Case 3 (AC2): feat/* and chore/* branches are covered.
# ---------------------------------------------------------------------------
for b in feat/some-feature chore/some-chore task/DP-999-T1-demo fix/some-fix; do
  r="$tmp/branch-$(echo "$b" | tr '/' '-')"
  build_repo "$r" "$b"
  rc="$(run_hook "$r")"
  [[ "$rc" == "0" ]] || fail AC2-branch "$b push must pass when gates green (got rc=$rc)"
  [[ -f "$r/.ci-local-ran" ]] || fail AC2-branch "$b push did NOT reach gate-ci-local"
  [[ -f "$r/.affected-ran" ]] || fail AC2-branch "$b push did NOT invoke the affected runner"
done

# ---------------------------------------------------------------------------
# Case 4 (AC2 / AC-NEG5): injected affected RED -> hook fails closed (exit≠0). The
# affected runner exit propagates through the hook on a feat/* push.
# ---------------------------------------------------------------------------
red_repo="$tmp/red"
build_repo "$red_repo" "feat/red-affected"
printf '2\n' >"$red_repo/.affected-stub-rc"
rc="$(run_hook "$red_repo")"
[[ "$rc" != "0" ]] || fail AC-NEG5-red "injected affected red must make hook fail closed (got exit 0)"
[[ -f "$red_repo/.affected-ran" ]] || fail AC-NEG5-red "affected runner not invoked on red case"

# ---------------------------------------------------------------------------
# Case 5 (AC2 / AC-NEG5): main push with injected affected RED also fails closed —
# main must not slip past the affected gate.
# ---------------------------------------------------------------------------
main_red="$tmp/main-red"
build_repo "$main_red" "main"
printf '1\n' >"$main_red/.affected-stub-rc"
rc="$(run_hook "$main_red")"
[[ "$rc" != "0" ]] || fail AC-NEG5-main-red "main push with affected red must fail closed (got exit 0)"

# ---------------------------------------------------------------------------
# Case 6 (AC-NEG4 no env bypass): POLARIS_SKIP_CI_LOCAL / arbitrary POLARIS_*_BYPASS
# must NOT silence the affected gate. With an injected affected red, the hook still
# fails closed even with these env vars set.
# ---------------------------------------------------------------------------
bypass_repo="$tmp/bypass"
build_repo "$bypass_repo" "feat/bypass-attempt"
printf '2\n' >"$bypass_repo/.affected-stub-rc"
set +e
POLARIS_SKIP_CI_LOCAL=1 POLARIS_AFFECTED_BYPASS=1 POLARIS_SKIP_AFFECTED=1 \
  CLAUDE_PROJECT_DIR="$bypass_repo" \
  printf '%s' "$(printf '%s' "git -C $bypass_repo push origin HEAD" | python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))')" \
  | POLARIS_SKIP_CI_LOCAL=1 POLARIS_AFFECTED_BYPASS=1 POLARIS_SKIP_AFFECTED=1 \
    CLAUDE_PROJECT_DIR="$bypass_repo" bash "$bypass_repo/.claude/hooks/pre-push-quality-gate.sh" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" != "0" ]] || fail AC-NEG4-bypass "env bypass vars must NOT silence the affected gate (got exit 0)"

# ---------------------------------------------------------------------------
# Case 7 (carve-out preserved): delete-only push still exits 0 (DP-305-T3 carve-out
# at line 61) and must NOT invoke the affected runner.
# ---------------------------------------------------------------------------
del_repo="$tmp/del"
build_repo "$del_repo" "feat/delete-carve"
rm -f "$del_repo/.affected-ran"
del_cmd="git -C $del_repo push origin --delete feat/delete-carve"
del_payload="$(printf '%s' "$del_cmd" | python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))')"
set +e
CLAUDE_PROJECT_DIR="$del_repo" printf '%s' "$del_payload" \
  | CLAUDE_PROJECT_DIR="$del_repo" bash "$del_repo/.claude/hooks/pre-push-quality-gate.sh" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" == "0" ]] || fail carve-out "delete-only push must exit 0 (got rc=$rc)"
[[ ! -f "$del_repo/.affected-ran" ]] || fail carve-out "delete-only push must NOT invoke the affected runner"

# ---------------------------------------------------------------------------
# Case 8 (source-level AC2 proof): the legacy `main|master|develop) exit 0` early-exit
# is removed from the real hook source (defends against a future re-introduction).
# ---------------------------------------------------------------------------
if grep -Eq 'HEAD\|main\|master\|develop\) exit 0' "$CC_HOOK"; then
  fail AC2-source "real hook still contains the legacy main/master/develop unconditional early-exit"
fi

echo "PASS: pre-push-affected-gate selftest"
