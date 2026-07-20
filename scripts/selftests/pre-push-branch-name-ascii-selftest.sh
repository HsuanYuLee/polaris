#!/usr/bin/env bash
# Purpose: DP-307 D4/AC5/AC-NEG2 — verify the two pre-push enforcement layers
#   reuse validate-branch-name-ascii.sh and fail-closed on a content-bearing
#   push of a non-ASCII branch name, while preserving the DP-305-T3
#   delete-only / tags-only exit-0 carve-out.
# Inputs:  none (builds isolated temp git repos; feeds real git pre-push stdin
#          and Claude-Code-runtime command JSON payloads).
# Outputs: exit 0 + "PASS" on success; non-zero + diagnostic on failure.
# Side effects: creates and removes temp dirs under $TMPDIR.
#
# Layers under test:
#   L1 git-native hook  — scripts/install-git-hooks.sh $PRE_PUSH_HOOK heredoc;
#                         reads refs from STDIN ("<local_ref> <local_sha>
#                         <remote_ref> <remote_sha>").
#   L2 Claude Code hook — .claude/hooks/pre-push-quality-gate.sh; reads the
#                         `git push` command from JSON tool_input.command.
#
# Contract:
#   - content-bearing push of a non-ASCII branch -> fail-closed (non-zero exit,
#     POLARIS_BRANCH_NAME_NON_ASCII marker), gates do NOT mask it (AC5).
#   - content-bearing push of an ASCII branch     -> exit 0 (AC-NEG1 sanity).
#   - delete-only push (all-zero local SHA), even with a CJK branch name
#     -> exit 0, branch-name gate NOT executed (AC-NEG2 / DP-305-T3 carve-out).
#   - tags-only push                              -> exit 0, gate NOT executed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$SCRIPT_DIR/install-git-hooks.sh"
CC_HOOK="$SCRIPT_DIR/../.claude/hooks/pre-push-quality-gate.sh"
VALIDATOR="$SCRIPT_DIR/validate-branch-name-ascii.sh"

[[ -f "$INSTALLER" ]] || { echo "[selftest] missing installer: $INSTALLER" >&2; exit 1; }
[[ -f "$CC_HOOK" ]] || { echo "[selftest] missing claude-code hook: $CC_HOOK" >&2; exit 1; }
[[ -f "$VALIDATOR" ]] || { echo "[selftest] missing validator: $VALIDATOR" >&2; exit 1; }

tmp="$(mktemp -d -t pre-push-branch-name-ascii.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

zero_sha='0000000000000000000000000000000000000000'
cjk_branch='task/中文-branch'
ascii_branch='task/DP-307-T3-pre-push-branch-gate'

fail() { echo "[selftest][$1] $2" >&2; exit 1; }

# ===========================================================================
# Layer 1 — git-native generated pre-push hook (stdin ref protocol)
# ===========================================================================

repo="$tmp/repo"
mkdir -p "$repo/scripts/gates"
git init -b main "$repo" >/dev/null
git -C "$repo" config user.email selftest@example.test
git -C "$repo" config user.name "Self Test"
printf 'base\n' > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -m "base" >/dev/null

# Provide the real validator (single-source judgment) inside the temp repo so
# the generated hook resolves it via REPO_ROOT.
cp "$VALIDATOR" "$repo/scripts/validate-branch-name-ascii.sh"
chmod +x "$repo/scripts/validate-branch-name-ascii.sh"

cp "$INSTALLER" "$repo/scripts/install-git-hooks.sh"
chmod +x "$repo/scripts/install-git-hooks.sh"

# Sentinel gate: detects whether downstream gates were reached. The branch-name
# enforcement must run BEFORE this. If the branch-name gate fails the hook must
# exit non-zero regardless of (and ideally before) the sentinel.
sentinel="$repo/.gates-ran"
cat > "$repo/scripts/gates/gate-template-leaks.sh" <<'SENTINEL'
#!/usr/bin/env bash
set -euo pipefail
repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    *) shift ;;
  esac
done
touch "${repo:-.}/.gates-ran"
exit 0
SENTINEL
chmod +x "$repo/scripts/gates/gate-template-leaks.sh"

bash "$repo/scripts/install-git-hooks.sh" >/dev/null
pre_push="$repo/.git/hooks/pre-push"
[[ -x "$pre_push" ]] || fail L1 "pre-push hook was not installed"

base_sha="$(git -C "$repo" rev-parse HEAD)"

# run_native_hook <stdin-payload> -> prints exit code, leaves $sentinel iff
# downstream gates ran. Hook resolves REPO_ROOT from cwd, so anchor at $repo.
run_native_hook() {
  local payload="$1"
  rm -f "$sentinel"
  set +e
  ( cd "$repo" && printf '%s' "$payload" | "$pre_push" origin "https://example.test/repo.git" ) >/dev/null 2>&1
  local rc=$?
  set -e
  echo "$rc"
}

# --- AC5: content-bearing push of a non-ASCII branch -> fail-closed -----------
content_cjk="refs/heads/${cjk_branch} ${base_sha} refs/heads/${cjk_branch} ${zero_sha}
"
rc="$(run_native_hook "$content_cjk")"
[[ "$rc" != "0" ]] || fail AC5-L1 "content-bearing non-ASCII branch leaked through (exit 0)"

# Confirm the marker comes from the shared validator (single-source judgment).
marker="$( ( cd "$repo" && printf '%s' "$content_cjk" | "$pre_push" origin "https://example.test/repo.git" ) 2>&1 || true )"
grep -q 'POLARIS_BRANCH_NAME_NON_ASCII' <<< "$marker" \
  || fail AC5-L1 "non-ASCII fail did not emit POLARIS_BRANCH_NAME_NON_ASCII marker"

# --- AC-NEG1 sanity: content-bearing ASCII branch -> exit 0 -------------------
content_ascii="refs/heads/${ascii_branch} ${base_sha} refs/heads/${ascii_branch} ${zero_sha}
"
rc="$(run_native_hook "$content_ascii")"
[[ "$rc" == "0" ]] || fail AC-NEG1-L1 "content-bearing ASCII branch failed (exit $rc)"

# --- AC-NEG2: delete-only push with CJK branch -> exit 0, gate NOT run --------
# Orphan CJK branch cleanup must remain possible (DP-305-T3 carve-out intact).
delete_cjk="(delete) ${zero_sha} refs/heads/${cjk_branch} ${base_sha}
"
rc="$(run_native_hook "$delete_cjk")"
[[ "$rc" == "0" ]] || fail AC-NEG2-L1 "delete-only CJK push blocked (exit $rc)"
[[ ! -e "$sentinel" ]] || fail AC-NEG2-L1 "delete-only push reached gates (sentinel present)"

# --- AC5/carve-out: tags-only push -> exit 0, gate NOT run --------------------
tags_only="refs/tags/v1.2.3 ${base_sha} refs/tags/v1.2.3 ${zero_sha}
"
rc="$(run_native_hook "$tags_only")"
[[ "$rc" == "0" ]] || fail AC5-L1 "tags-only push blocked (exit $rc)"
[[ ! -e "$sentinel" ]] || fail AC5-L1 "tags-only push reached gates (sentinel present)"

# ===========================================================================
# Layer 2 — Claude Code runtime hook (.claude/hooks/pre-push-quality-gate.sh)
# ===========================================================================
# This hook reads the `git push` command from JSON tool_input.command and
# resolves the branch via `git -C <repo> rev-parse --abbrev-ref HEAD`. We drive
# it against dedicated temp repos checked out on the branch under test.

cc_repo_on_branch() {
  # $1 = branch name to check out HEAD onto. Echoes the repo path.
  local branch="$1" r="$tmp/ccrepo-$RANDOM"
  mkdir -p "$r/scripts/gates"
  git init -b main "$r" >/dev/null 2>&1
  git -C "$r" config user.email selftest@example.test
  git -C "$r" config user.name "Self Test"
  printf 'base\n' > "$r/README.md"
  git -C "$r" add README.md
  git -C "$r" commit -m base >/dev/null 2>&1
  cp "$VALIDATOR" "$r/scripts/validate-branch-name-ascii.sh"
  chmod +x "$r/scripts/validate-branch-name-ascii.sh"
  git -C "$r" checkout -q -b "$branch" 2>/dev/null
  printf '%s' "$r"
}

# run_cc_hook <repo> <push-command> -> prints exit code (stderr/stdout muted).
run_cc_hook() {
  local repo="$1" cmd="$2"
  local payload
  payload="$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))')"
  set +e
  CLAUDE_PROJECT_DIR="$repo" printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$repo" bash "$CC_HOOK" >/dev/null 2>&1
  local rc=$?
  set -e
  echo "$rc"
}

# --- AC5-L2: content-bearing push of CJK branch -> fail-closed ----------------
cc_cjk="$(cc_repo_on_branch "$cjk_branch")"
rc="$(run_cc_hook "$cc_cjk" "git -C $cc_cjk push origin HEAD")"
[[ "$rc" != "0" ]] || fail AC5-L2 "Claude Code hook let CJK branch push through (exit 0)"

# --- AC-NEG2-L2: delete push of CJK branch -> exit 0 (carve-out) --------------
rc="$(run_cc_hook "$cc_cjk" "git -C $cc_cjk push origin --delete $cjk_branch")"
[[ "$rc" == "0" ]] || fail AC-NEG2-L2 "Claude Code hook blocked --delete CJK push (exit $rc)"

# --- AC-NEG2-L2: tags-only push -> exit 0 (carve-out) -------------------------
rc="$(run_cc_hook "$cc_cjk" "git -C $cc_cjk push origin --tags")"
[[ "$rc" == "0" ]] || fail AC5-L2 "Claude Code hook blocked --tags push (exit $rc)"

echo "[pre-push-branch-name-ascii-selftest] PASS"
