#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF_TEST=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/check-engineering-first-cut-worktree-contract.sh [--root <repo>] [--self-test]

Validates engineering first-cut worktree handoff and workspace overlay safety
contracts.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_DIR="$2"
      shift 2
      ;;
    --self-test)
      SELF_TEST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

failures=0
fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "missing required file: $path"
}

require_regex() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if ! grep -Eq -- "$pattern" "$path"; then
    fail "$label missing in ${path#$ROOT_DIR/}"
  fi
}

reject_regex() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if grep -Eq -- "$pattern" "$path"; then
    fail "$label found in ${path#$ROOT_DIR/}"
  fi
}

run_check() {
  local root="$1"
  local first_cut="$root/.claude/skills/references/engineering-first-cut-flow.md"
  local overlay="$root/.claude/skills/references/workspace-overlay.md"
  local dispatch="$root/.claude/skills/references/worktree-dispatch-paths.md"

  require_file "$first_cut"
  require_file "$overlay"
  require_file "$dispatch"
  [[ "$failures" -eq 0 ]] || return 1

  require_regex "$first_cut" 'WORKTREE_PATH=.*tail -n 1' "WORKTREE_PATH tail handoff"
  require_regex "$first_cut" 'git -C "\$WORKTREE_PATH" rev-parse --show-toplevel' "WORKTREE_PATH git root validation"
  require_regex "$first_cut" '--cwd "\$WORKTREE_PATH"' "dependency install worktree cwd"
  require_regex "$first_cut" 'ci-local-run\.sh" --repo "\$WORKTREE_PATH"' "ci-local worktree repo"
  require_regex "$first_cut" 'finalize-engineering-delivery\.sh"([[:space:]]|\\)*' "finalize helper call"
  require_regex "$first_cut" '--repo "\$WORKTREE_PATH"' "finalize worktree repo"
  require_regex "$first_cut" 'git stash' "main checkout stash prohibition"
  require_regex "$first_cut" 'git reset' "main checkout reset prohibition"
  require_regex "$first_cut" 'git restore' "main checkout restore prohibition"
  require_regex "$first_cut" 'git checkout' "main checkout checkout prohibition"
  require_regex "$first_cut" 'copy / rsync / mirror' "specs copy prohibition"

  require_regex "$overlay" 'Main checkout dirty state 是允許狀態' "main checkout dirty allowed statement"
  require_regex "$overlay" 'git stash' "overlay stash prohibition"
  require_regex "$overlay" 'copy / rsync / mirror' "overlay specs copy prohibition"
  require_regex "$overlay" '主 checkout absolute path|main checkout canonical overlay' "overlay absolute-path source"

  require_regex "$dispatch" 'tracked source file 的讀寫限定於此目錄' "dispatch tracked-source worktree boundary"
  require_regex "$dispatch" 'design-plans/DP-NNN-\*' "dispatch DP specs absolute path"
  require_regex "$dispatch" 'copy / rsync / mirror' "dispatch copy prohibition"

  reject_regex "$first_cut" '先用 `?git stash|git stash.*建立.*worktree|--auto-stash' "stash workaround suggestion"
  reject_regex "$overlay" '先用 `?git stash|git stash.*建立.*worktree|--auto-stash' "overlay stash workaround suggestion"
  reject_regex "$dispatch" 'rsync .*docs-manager/src/content/docs/specs.*worktree|cp -R .*docs-manager/src/content/docs/specs.*worktree' "specs-to-worktree copy command"
  [[ "$failures" -eq 0 ]]
}

write_fixture() {
  local root="$1"
  local first_cut_body="$2"
  local overlay_body="$3"
  local dispatch_body="$4"
  mkdir -p "$root/.claude/skills/references"
  printf '%s\n' "$first_cut_body" >"$root/.claude/skills/references/engineering-first-cut-flow.md"
  printf '%s\n' "$overlay_body" >"$root/.claude/skills/references/workspace-overlay.md"
  printf '%s\n' "$dispatch_body" >"$root/.claude/skills/references/worktree-dispatch-paths.md"
}

positive_first_cut() {
  cat <<'EOF'
WORKTREE_PATH="$(printf '%s\n' "$SETUP_OUTPUT" | tail -n 1)"
test "$(git -C "$WORKTREE_PATH" rev-parse --show-toplevel)" = "$WORKTREE_PATH"
bash scripts/env/install-project-deps.sh --cwd "$WORKTREE_PATH"
bash "${POLARIS_ROOT}/scripts/ci-local-run.sh" --repo "$WORKTREE_PATH"
不得為了建立 task worktree 對 main checkout 執行 `git stash`、`git reset`、`git restore`、`git checkout`。
不得把 `docs-manager/src/content/docs/specs/**`、`.claude/skills/**` 或 `polaris-config/**` copy / rsync / mirror 到 task worktree。
bash "${POLARIS_ROOT}/scripts/finalize-engineering-delivery.sh" \
  --repo "$WORKTREE_PATH"
EOF
}

positive_overlay() {
  cat <<'EOF'
Main checkout dirty state 是允許狀態；不得因 dirty user changes 對 main checkout 執行 `git stash`。
不得把 `docs-manager/src/content/docs/specs/**`、`.claude/skills/**` 或 `polaris-config/**` copy / rsync / mirror 到 task worktree。
需要這些 artifact 時使用主 checkout absolute path；verification source 仍是 main checkout canonical overlay。
EOF
}

positive_dispatch() {
  cat <<'EOF'
tracked source file 的讀寫限定於此目錄。
`design-plans/DP-NNN-*` artifacts 用主 checkout absolute path。
禁止把 `docs-manager/src/content/docs/specs/**`、`.claude/skills/**` 或 `polaris-config/**` copy / rsync / mirror 到 worktree。
EOF
}

expect_pass() {
  local name="$1"
  local root="$2"
  failures=0
  if ! run_check "$root"; then
    echo "SELFTEST FAIL: expected pass: $name" >&2
    exit 1
  fi
}

expect_fail() {
  local name="$1"
  local root="$2"
  local status=0
  failures=0
  set +e
  run_check "$root" >/dev/null 2>&1
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || {
    echo "SELFTEST FAIL: expected fail: $name" >&2
    exit 1
  }
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d -t dp192-first-cut-contract.XXXXXX)"
  trap "rm -rf '$tmp'" EXIT

  write_fixture "$tmp/positive" "$(positive_first_cut)" "$(positive_overlay)" "$(positive_dispatch)"
  expect_pass "positive contract" "$tmp/positive"

  write_fixture "$tmp/missing-worktree" \
    'bash scripts/engineering-branch-setup.sh task.md
bash scripts/env/install-project-deps.sh --cwd "$(git rev-parse --show-toplevel)"' \
    "$(positive_overlay)" \
    "$(positive_dispatch)"
  expect_fail "missing WORKTREE_PATH handoff" "$tmp/missing-worktree"

  write_fixture "$tmp/stash-workaround" \
    "$(positive_first_cut)
先用 git stash 暫存 main checkout dirty file，再建立 worktree。" \
    "$(positive_overlay)" \
    "$(positive_dispatch)"
  expect_fail "stash workaround" "$tmp/stash-workaround"

  write_fixture "$tmp/specs-copy" \
    "$(positive_first_cut)" \
    "$(positive_overlay)" \
    "$(positive_dispatch)
rsync docs-manager/src/content/docs/specs worktree/specs"
  expect_fail "specs copy workaround" "$tmp/specs-copy"

  echo "PASS: engineering first-cut worktree contract self-test"
}

if [[ "$SELF_TEST" -eq 1 ]]; then
  run_self_test
  exit 0
fi

run_check "$ROOT_DIR"
if [[ "$failures" -gt 0 ]]; then
  echo "check-engineering-first-cut-worktree-contract.sh FAIL ($failures issue(s))" >&2
  exit 1
fi

echo "PASS: engineering first-cut worktree contract"
