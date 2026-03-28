---
name: wt-parallel
description: >
  Orchestrate parallel AI agent work using git worktrees.
  Supports two modes: `wt` CLI (if installed) or Claude Code built-in `isolation: "worktree"` (fallback).
  Use when: (1) working on multiple JIRA tickets simultaneously,
  (2) splitting a large task into parallel sub-tasks,
  (3) user mentions "parallel", "worktree", "wt", "平行", "多個 ticket", "拆分".
  Not for single-branch development — use fix-bug or start-dev instead.
---

# Parallel Work with Worktrees

Manage git worktrees for parallel AI agent work. Two modes available:

| Mode | When | How |
|------|------|-----|
| **wt CLI** | `wt` is installed | User runs commands in separate terminals via `wt switch` |
| **Built-in** (fallback) | `wt` not installed | Agent spawns sub-agents with `isolation: "worktree"` |

---

## 1. Mode Detection

**Run every time the skill is triggered.**

```bash
which wt && echo "MODE=wt" || echo "MODE=builtin"
```

### If `wt` is found → **wt mode**

Verify full setup:

```bash
test -f ~/.config/worktrunk/config.toml && echo OK          # user config exists?
test -f .config/wt.toml && echo OK                          # project config exists?
type wt                                                     # should say "shell function"
```

If anything is missing, follow `references/setup.md` or run:

```bash
bash <skill-dir>/scripts/setup-wt.sh --yes
```

### If `wt` is NOT found → **builtin mode**

No extra setup needed. Claude Code's `Agent` tool with `isolation: "worktree"` handles worktree creation and cleanup automatically. Inform the user:

> `wt` CLI 未安裝，將使用 Claude Code 內建的 worktree 隔離模式。如需 `wt` 的進階功能（squash merge、pre-merge hooks），請參考 `references/setup.md` 安裝。

**Proceed to the appropriate use case below.**

---

## 2. Use Case 1 — Multiple Tickets in Parallel

When the user wants to work on multiple JIRA tickets simultaneously.

### Common Steps (both modes)

1. **Collect ticket list** — from user input or JIRA MCP query.
2. **Fetch ticket info** — get summary/description for each ticket via JIRA MCP.

### wt mode

3. **Generate terminal commands** — output one block per ticket:

```
# Terminal 1: <TICKET> - <summary>
wt switch -c task/<TICKET>-<short-desc> -y && claude '<prompt for this ticket>'

# Terminal 2: <TICKET> - <summary>
wt switch -c task/<TICKET>-<short-desc> -y && claude '<prompt for this ticket>'
```

4. **User copies each block into a separate terminal** and runs them.

### Builtin mode

3. **Launch parallel sub-agents** — one Agent call per ticket, all in a single message:

```
Agent({
  prompt: "<prompt for this ticket>",
  isolation: "worktree",
  model: "sonnet",
  description: "<TICKET> implementation"
})
```

4. Each sub-agent automatically gets an isolated worktree. Changes are returned with worktree path and branch name.

### After completion (both modes)

5. **Create a PR** using `git-pr-workflow` skill (preferred, includes quality check + JIRA status transition + `need review` label), or `pr-convention` for a simpler flow. Do **not** use bare `gh pr create --fill` as it bypasses YourOrg PR conventions.

### Prompt Template for Each Agent

The `claude '<prompt>'` should include:

- JIRA ticket number and summary
- Key acceptance criteria
- Instruction to only modify files relevant to the ticket
- Instruction to commit frequently
- Instruction to run `/dev-quality-check` before finishing

---

## 3. Use Case 2 — Split a Single Task into Sub-branches

When the user wants to break one large task into parallel sub-tasks.

### Common Steps (both modes)

1. **Analyze the task** — read the JIRA ticket, understand scope.
2. **Split into sub-tasks** — divide by file boundaries to avoid conflicts.

### wt mode

3. **Create parent branch:**

```bash
wt switch -c task/<TICKET>-<feature-name> -y
```

4. **Create sub-branches from parent** (without switching):

```bash
wt switch -c task/<TICKET>-<sub-task-1> --no-cd -y
wt switch -c task/<TICKET>-<sub-task-2> --no-cd -y
```

5. **Get worktree paths** then output terminal commands for the user to paste:

```bash
wt list   # shows each worktree path
```

```
# Terminal 1: <sub-task-1 description>
cd <worktree-path-1> && claude '<sub-task prompt>'

# Terminal 2: <sub-task-2 description>
cd <worktree-path-2> && claude '<sub-task prompt>'
```

6. **After all sub-tasks complete**, merge sub-branches back to parent:

```bash
wt merge task/<TICKET>-<feature-name>
```

7. **Create PR from parent branch** using `git-pr-workflow` skill (preferred) or `pr-convention`. Do **not** use bare `gh pr create --fill`.

### Builtin mode

3. **Create parent branch** using git directly:

```bash
git checkout -b task/<TICKET>-<feature-name>
git push -u origin task/<TICKET>-<feature-name>
```

4. **Launch parallel sub-agents** — one per sub-task, all in a single message:

```
Agent({
  prompt: "On branch task/<TICKET>-<feature-name>, implement <sub-task>. Only modify: <file list>. Run /dev-quality-check before finishing.",
  isolation: "worktree",
  model: "sonnet",
  description: "<TICKET> sub-task N"
})
```

5. Each sub-agent works in an isolated worktree and returns changes on its own branch. Review the returned branches and merge them into the parent branch.

6. **Create PR from parent branch** using `git-pr-workflow` skill (preferred) or `pr-convention`. Do **not** use bare `gh pr create --fill`.

### Splitting Guidelines

- **By layer**: API logic vs. UI components vs. tests
- **By feature area**: different pages, different components
- **Always avoid**: two sub-tasks editing the same file

---

## 4. Worktree Agent Behavior Guidelines

Every agent working in a worktree MUST (applies to both modes):

1. **Scope discipline** — only modify files within the assigned scope.
2. **Commit frequently** — small, focused commits for cleaner squash merges.
3. **Run checks before finishing** — invoke `dev-quality-check` skill (the single entry point for lint + test + coverage). Do **not** run raw `pnpm run lint` / `pnpm run test:unit` directly.
4. **Never push directly to develop** — use `wt merge` (wt mode) or create a PR.
5. **Never force-push** — if push fails, investigate and resolve.
6. **Report completion** — output a summary of changes and confirm lint/tests pass.

---

## 5. Useful wt Commands (wt mode only)

| Command | Description |
|---------|-------------|
| `wt switch -c <branch> -y` | Create new worktree + branch and switch to it |
| `wt switch -c <branch> --no-cd -y` | Create worktree + branch without switching |
| `wt switch <branch>` | Switch to existing worktree |
| `wt list` | List all worktrees |
| `wt merge <target-branch>` | Squash merge current branch into target |
| `wt remove` | Remove current worktree |
| `wt commit` | Commit with AI-generated message |
| `wt status` | Show status across all worktrees |

---

## Do / Don't

- **Do** run mode detection (Section 1) before spawning worktree agents
- **Do** ensure each worktree agent works on its own branch with non-overlapping files
- **Do** commit frequently in each worktree for cleaner squash merges
- **Do** run `/dev-quality-check` before merging
- **Do** use `wt merge` (wt mode) or create a PR — never push directly to develop
- **Don't** run multiple agents in the same worktree
- **Don't** create worktrees for trivially small tasks that don't benefit from parallelism
- **Don't** let two sub-tasks edit the same file — split by file boundaries
- **Don't** force-push — if push fails, investigate and resolve
- **Don't** skip pre-merge hooks (`--no-verify`) unless absolutely necessary

## Prerequisites

**Minimum (builtin mode):**
- `git` installed
- `gh` CLI authenticated (for PR creation)

**Full (wt mode, optional):**
- `wt` (worktrunk) CLI installed (`brew install worktrunk`)
- Shell integration active (`wt` is a shell function, not a binary path)
- User config at `~/.config/worktrunk/config.toml`
- Project config at `<project-root>/.config/wt.toml`
- Claude Code permission `Bash(wt:*)` in `.claude/settings.local.json`

> Full wt setup instructions: `references/setup.md`
