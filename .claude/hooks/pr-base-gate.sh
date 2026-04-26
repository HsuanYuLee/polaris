#!/usr/bin/env bash
# pr-base-gate.sh — PreToolUse hook for `gh pr create` / `gh pr edit`
#
# DP-028 Gate 層: blocks PR `--base X` (both creation and post-hoc edit) when
# X does not match the expected base derived from the current branch's task.md
# (Base branch field, after resolve).
#
# Phase 1 covered `gh pr create --base`. Phase 2+ gap fill extended coverage
# to `gh pr edit --base` so revision-mode fixes to an existing PR's base are
# gated by the same rule (otherwise engineering could rebase the branch but
# leave the PR's base-ref stale).
#
# Design: specs/design-plans/DP-028-depends-on-branch-binding/plan.md § D2
# Blind spot #7: hook uses current branch name → resolve task.md → resolve
# expected base value, then compares against the actual `--base` argument.
#
# Hook type: PreToolUse
# Matcher:   Bash (settings.json uses `if: Bash(gh pr create*)` and
#                  `if: Bash(gh pr edit*)` pre-filters)
#
# Exit codes:
#   0 — allow (match, not applicable, fail-open, bypass, no --base)
#   2 — block (mismatch)
#
# Bypass (emergency only):
#   POLARIS_SKIP_PR_BASE_GATE=1 gh pr create --base foo ...
#   POLARIS_SKIP_PR_BASE_GATE=1 gh pr edit   --base foo ...

# Deliberately NOT using `set -e` — the hook must self-recover on its own
# errors and exit 0 (fail-open) rather than block every PR open.
set -u

# ---------------------------------------------------------------------------
# Emergency bypass — exit 0 immediately before any other work.
# ---------------------------------------------------------------------------
if [[ "${POLARIS_SKIP_PR_BASE_GATE:-}" == "1" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Read hook input (Claude Code PreToolUse: JSON on stdin).
# Aligns with version-docs-lint-gate.sh convention.
# ---------------------------------------------------------------------------
input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

# Double-check matcher (settings.json already filters Bash, but defend).
[[ "$tool_name" == "Bash" ]] || exit 0

command=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)

# Double-check the command is a gated subcommand — either `gh pr create` or
# `gh pr edit`. settings.json `if` already pre-filters, but defend here.
action=""
if printf '%s' "$command" | grep -qE '(^|[^[:alnum:]_-])gh[[:space:]]+pr[[:space:]]+create(\b|$)'; then
  action="create"
elif printf '%s' "$command" | grep -qE '(^|[^[:alnum:]_-])gh[[:space:]]+pr[[:space:]]+edit(\b|$)'; then
  action="edit"
else
  exit 0
fi

# ---------------------------------------------------------------------------
# Extract --base value. Support both forms:
#   --base X        (space-separated)
#   --base=X        (equals-separated)
# If no --base present → let gh use default, don't block.
# ---------------------------------------------------------------------------
actual_base=""
if printf '%s' "$command" | grep -qE -- '--base='; then
  actual_base=$(printf '%s' "$command" | sed -nE 's/.*--base=([^[:space:]]+).*/\1/p' | head -1)
elif printf '%s' "$command" | grep -qE -- '--base[[:space:]]'; then
  actual_base=$(printf '%s' "$command" | sed -nE 's/.*--base[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
fi

# No --base argument → allow (gh will use the remote default branch).
if [[ -z "$actual_base" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Resolve current branch's task.md via sibling helper script.
# The resolver returns the task.md absolute path on stdout and exits 0 when
# found. Any non-zero exit (framework repo, branch not managed by DP-028,
# no matching task.md) → fail-open (allow).
# ---------------------------------------------------------------------------
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
resolve_by_branch="${project_dir}/scripts/resolve-task-md-by-branch.sh"
resolve_base="${project_dir}/scripts/resolve-task-base.sh"

# If either sibling script is missing, fail-open with a stderr warn so the
# failure is visible but not blocking. (See F2: hooks should not block when
# their own machinery is incomplete.)
if [[ ! -x "$resolve_by_branch" && ! -f "$resolve_by_branch" ]]; then
  echo "[DP-028 pr-base-gate] WARN: resolver script missing at $resolve_by_branch — allowing PR creation (fail-open)" >&2
  exit 0
fi
if [[ ! -x "$resolve_base" && ! -f "$resolve_base" ]]; then
  echo "[DP-028 pr-base-gate] WARN: resolver script missing at $resolve_base — allowing PR creation (fail-open)" >&2
  exit 0
fi

task_md_path=$(bash "$resolve_by_branch" --current 2>/dev/null)
resolve_branch_rc=$?

# Non-zero exit or empty output → not managed by DP-028 → allow.
if [[ "$resolve_branch_rc" -ne 0 || -z "$task_md_path" ]]; then
  exit 0
fi

# Extra safety: resolver said OK but the file doesn't exist → fail-open.
if [[ ! -f "$task_md_path" ]]; then
  echo "[DP-028 pr-base-gate] WARN: resolver returned non-existent task.md: $task_md_path — allowing PR creation (fail-open)" >&2
  exit 0
fi

expected_base=$(bash "$resolve_base" "$task_md_path" 2>/dev/null)
resolve_base_rc=$?

# Resolver failure → fail-open.
if [[ "$resolve_base_rc" -ne 0 || -z "$expected_base" ]]; then
  echo "[DP-028 pr-base-gate] WARN: resolve-task-base.sh failed (rc=$resolve_base_rc) for $task_md_path — allowing PR creation (fail-open)" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# Compare actual vs expected.
# ---------------------------------------------------------------------------
if [[ "$actual_base" == "$expected_base" ]]; then
  exit 0
fi

# Resolve current branch for the error message (best-effort, never blocking).
current_branch=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<unknown>")

cat >&2 <<EOF

[DP-028 pr-base-gate] BLOCK: gh pr ${action} --base ${actual_base} does not match expected base from task.md.
  Current branch: ${current_branch}
  Task.md:        ${task_md_path}
  Expected --base: ${expected_base}
  Actual --base:   ${actual_base}

Why this gate exists: DP-028 enforces depends_on → PR base binding. Opening or
retargeting a PR against the wrong base (e.g., feat instead of the upstream
task branch) breaks the stacked PR chain and usually means the task.md
Base branch field was not consulted.

Fix options:
  1. Re-run engineer-delivery-flow so it reads task.md and uses the resolved base
  2. If task.md is wrong, fix task.md Base branch first, then retry
  3. Emergency bypass (NOT recommended): POLARIS_SKIP_PR_BASE_GATE=1 gh pr ${action} ...
EOF
exit 2
