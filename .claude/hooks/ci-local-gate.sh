#!/usr/bin/env bash
# ci-local-gate.sh — PreToolUse hook (DP-032 D12-c + DP-043).
# Enforces repo CI mirror from workspace-owned polaris-config for git commit / gh pr create / git push.
#
# Behavior (per D12 Decision 4 — "skill main / hook fallback"):
#   1. Repo without workspace-owned generated ci-local.sh → allow (engineering
#      handles first-run gate at skill layer; hook stays defensive on cross-LLM
#      portability)
#   2. evidence /tmp/polaris-ci-local-{branch_slug}-{head_sha}-{context_hash}.json exists,
#      branch + head_sha + CI context match HEAD, status==PASS → allow (cache hit, zero cost)
#   3. cache miss / FAIL → run `scripts/ci-local-run.sh` synchronously
#      - exit 0 → allow (ci-local.sh wrote fresh evidence)
#      - exit ≠0 → block + tail of ci-local.sh log
#
# Branch filter:
#   - commit / pr-create: all branches (cache makes idempotent reruns free)
#   - push: only task/* and fix/* (skip wip/* / feat/* / main / develop / --delete / --tags)
#
# Env:
#   POLARIS_SKIP_CI_LOCAL=1 — emergency override only. Do NOT use in normal dev flow;
#                             plan D12 Decision 5 specifies "Bypass: NONE" for the
#                             three legacy bypasses (wip: prefix / POLARIS_SKIP_QUALITY /
#                             POLARIS_SKIP_CI_CONTRACT / main-develop skip).
#                             This var exists solely as a final escape hatch.
#
# Exit 0 = allow, Exit 2 = block

set -uo pipefail

# Resolve the framework workspace root from this hook's location so we can
# source the path constant. Hook lives in <workspace>/.claude/hooks/.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/lib/ci-local-path.sh
. "$HOOK_DIR/../../scripts/lib/ci-local-path.sh"

input=$(cat)
tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)
[[ "$tool_name" == "Bash" ]] || exit 0

command=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)

# Determine intercepted command mode
MODE=""
if printf '%s' "$command" | grep -qiE '^gh[[:space:]]+pr[[:space:]]+create\b'; then
  MODE="pr-create"
elif printf '%s' "$command" | grep -qiE '^git[[:space:]]+((-C[[:space:]]+[^[:space:]]+[[:space:]]+)?push|push)\b'; then
  MODE="push"
elif printf '%s' "$command" | grep -qiE '^git[[:space:]]+((-C[[:space:]]+[^[:space:]]+[[:space:]]+)?commit|commit)\b'; then
  MODE="commit"
fi
[[ -n "$MODE" ]] || exit 0

if [[ "${POLARIS_SKIP_CI_LOCAL:-}" == "1" ]]; then
  echo "[ci-local-gate] POLARIS_SKIP_CI_LOCAL=1 — bypassing (emergency only)" >&2
  exit 0
fi

# Resolve repo root (target — could be main checkout or worktree)
extracted=$(printf '%s' "$command" | grep -oE 'git -C [^ ]+' | head -1 | sed 's/git -C //' || true)
repo_root="${extracted:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"

[[ -n "$repo_root" ]] || exit 0

# Push mode: skip non-delivery branches and destructive pushes
if [[ "$MODE" == "push" ]]; then
  push_branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  case "$push_branch" in
    task/*|fix/*) ;;
    *) exit 0 ;;
  esac
  if printf '%s' "$command" | grep -qE '\-\-delete|\-\-tags'; then
    exit 0
  fi
fi

branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
head_sha=$(git -C "$repo_root" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)

# Run ci-local.sh synchronously. The generated script owns context-aware
# evidence caching because the cache key includes base/event/source/ref.
echo "[ci-local-gate] $MODE intercepted on ${branch} — running ci-local-run ..." >&2
ci_log=$(mktemp -t ci-local-gate.XXXXXX)

bash "$HOOK_DIR/../../scripts/ci-local-run.sh" --repo "$repo_root" >"$ci_log" 2>&1
rc=$?

if [[ $rc -eq 0 ]]; then
  rm -f "$ci_log"
  exit 0
fi

echo "" >&2
echo "BLOCKED: ci-local.sh FAILED for ${branch} @ ${head_sha} (exit ${rc})" >&2
echo "" >&2
tail -60 "$ci_log" >&2
echo "" >&2
echo "  Full log: ${ci_log}" >&2
echo "  Re-run:   bash ${HOOK_DIR}/../../scripts/ci-local-run.sh --repo ${repo_root}" >&2
exit 2
