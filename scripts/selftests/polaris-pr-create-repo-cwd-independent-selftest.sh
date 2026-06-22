#!/usr/bin/env bash
# Purpose: real-state selftest for DP-352-T2 Bug #2 — polaris-pr-create.sh's
#   gh pr create step must carry repo context (--repo <owner/repo>) so that when
#   invoked from a cwd that is NOT the target repo, gh resolves head/base refs
#   against the right repo instead of producing blank refs.
# Inputs:  none (self-contained fixtures via mktemp; stubs `gh` on PATH).
# Outputs: stdout `polaris-pr-create-repo-cwd-independent: PASS=N FAIL=M TOTAL=K`;
#   exit 0 only when FAIL=0.
#
# Bug reproduction fidelity: a fake `gh` records every arg of the `pr create`
# invocation. The fix is exercised through the real wrapper code path
# (create_pr_and_assign -> polaris_github_pr_create_cli) from a cwd that is the
# framework repo, NOT the product repo. Against the UNFIXED helper the recorded
# args carry NO repo context (no `--repo owner/repo`), so the head/base refs gh
# would resolve are blank — the assertion FAILS (RED). After the fix injects
# `--repo <owner/repo>` derived from REPO_PATH, the assertion passes (GREEN).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITHUB_REST_LIB="$SCRIPT_DIR/lib/github-rest.sh"

PASS=0
FAIL=0
TOTAL=0

WORK_DIR="$(mktemp -d -t polaris-pr-create-repo-cwd-selftest-XXXXXX)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

_assert() {
  local label="$1"
  local cond="$2" # "ok" or anything else = fail
  TOTAL=$((TOTAL + 1))
  if [[ "$cond" == "ok" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAIL] %s\n' "$label" >&2
  fi
}

# --- Fixture: a fake gh that records the args it received into a log file. ---
mkdir -p "$WORK_DIR/bin"
cat >"$WORK_DIR/bin/gh" <<'SH'
#!/usr/bin/env bash
# Fake gh: record the full invocation (all args) and emit a fake PR URL on
# `pr create`. Records to FAKE_GH_LOG. Resolves a fake login on `api user`.
log="${FAKE_GH_LOG:?}"
printf '%s\n' "$*" >>"$log"

if [[ "${1:-}" == "pr" && "${2:-}" == "create" ]]; then
  echo "https://github.com/acme/demo/pull/123"
  exit 0
fi
if [[ "${1:-}" == "api" && "${2:-}" == "user" ]]; then
  echo "selftest-bot"
  exit 0
fi
# Any other gh subcommand (e.g. pr edit / api assignees) just succeeds.
echo '{}'
exit 0
SH
chmod +x "$WORK_DIR/bin/gh"

# --- Fixture: a fake product git repo with an origin remote (acme/demo). ---
# This repo lives at $WORK_DIR/repo; the selftest itself runs from a DIFFERENT
# cwd (the framework SCRIPT_DIR), reproducing the "non-repo cwd" bug condition.
REPO="$WORK_DIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b feat/DP-352
git -C "$REPO" config user.email selftest@example.com
git -C "$REPO" config user.name selftest
git -C "$REPO" remote add origin git@github.com:acme/demo.git
touch "$REPO/file"
git -C "$REPO" add file
git -C "$REPO" commit -q -m init
git -C "$REPO" checkout -q -b task/DP-352-T2-demo

# shellcheck source=lib/github-rest.sh
. "$GITHUB_REST_LIB"

export PATH="$WORK_DIR/bin:$PATH"
export FAKE_GH_LOG="$WORK_DIR/gh.log"
: >"$FAKE_GH_LOG"

# REPO_PATH is the variable the wrapper threads into the helper. The helper must
# use it to derive repo context for the gh pr create invocation.
REPO_PATH="$REPO"

output_file="$WORK_DIR/pr-create.out"

# Invoke the real helper from a cwd that is NOT the product repo (we are running
# from the framework workspace). This is the exact bug condition.
rc=0
polaris_github_pr_create_cli "$output_file" \
  --base feat/DP-352 \
  --head task/DP-352-T2-demo \
  --title "[DP-352-T2] demo" \
  --body "demo body" >/dev/null 2>&1 || rc=$?

# --- Assertions ---

# A1: the helper succeeded (exit 0) — gh stub always succeeds, so this just
# guards against the helper crashing on the new repo-context plumbing.
if [[ "$rc" -eq 0 ]]; then
  _assert "A1: polaris_github_pr_create_cli exits 0" "ok"
else
  _assert "A1: polaris_github_pr_create_cli exits 0 (rc=$rc)" "fail"
fi

gh_invocation="$(cat "$FAKE_GH_LOG" 2>/dev/null || true)"

# A2 (RED on unfixed): the recorded `gh pr create` invocation MUST carry repo
# context. Without it gh resolves head/base against the wrong repo (cwd) and the
# refs come back blank. Accept either `--repo acme/demo` injected into the args
# (the canonical fix) OR `--repo=acme/demo`.
if grep -Eq -- '(^| )pr create( |$)' <<<"$gh_invocation" \
   && grep -Eq -- '--repo[ =]acme/demo' <<<"$gh_invocation"; then
  _assert "A2: gh pr create invocation carries --repo acme/demo (repo context, head/base non-blank)" "ok"
else
  _assert "A2: gh pr create invocation carries --repo acme/demo (repo context, head/base non-blank)" "fail"
  printf '       recorded gh invocation(s):\n%s\n' "$gh_invocation" >&2
fi

# A3: the user-provided pass-through args survive (the fix must not drop them).
if grep -Eq -- '--base feat/DP-352' <<<"$gh_invocation" \
   && grep -Eq -- '--head task/DP-352-T2-demo' <<<"$gh_invocation"; then
  _assert "A3: user-provided --base/--head pass-through preserved" "ok"
else
  _assert "A3: user-provided --base/--head pass-through preserved" "fail"
fi

# A4 (idempotency): if the caller ALREADY supplied --repo, the helper must not
# double-inject a conflicting repo (only one --repo flag in the invocation).
: >"$FAKE_GH_LOG"
rc2=0
polaris_github_pr_create_cli "$output_file" \
  --repo acme/demo \
  --base feat/DP-352 \
  --head task/DP-352-T2-demo \
  --title "[DP-352-T2] demo" >/dev/null 2>&1 || rc2=$?
gh_invocation2="$(cat "$FAKE_GH_LOG" 2>/dev/null || true)"
repo_flag_count="$(grep -Eo -- '--repo[ =]' <<<"$gh_invocation2" | wc -l | tr -d ' ')"
if [[ "$rc2" -eq 0 && "$repo_flag_count" == "1" ]]; then
  _assert "A4: caller-supplied --repo is not double-injected" "ok"
else
  _assert "A4: caller-supplied --repo is not double-injected (rc=$rc2 count=$repo_flag_count)" "fail"
fi

printf 'polaris-pr-create-repo-cwd-independent: PASS=%s FAIL=%s TOTAL=%s\n' "$PASS" "$FAIL" "$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
