# Bash Command Rules

## Core Principle: Avoid cd

Do not use `cd` in Bash commands. Use each tool's built-in path parameter or absolute paths instead.

`cd <path> && <cmd>` is a compound command — permission patterns are hard to maintain (`cd * && *`, `cd * && * | *`...) and frequently trigger permission confirmation prompts. A single command matches a simple pattern (e.g., `Bash(git *)`), no confirmation needed.

### Alternatives

| Tool | ❌ Avoid | ✅ Use instead |
|------|---------|---------------|
| git | `cd /repo && git status` | `git -C /repo status` |
| pnpm | `cd /repo && pnpm test` | `pnpm -C /repo test` |
| gh | `cd /repo && gh pr list` | `gh pr list --repo owner/repo` |
| node | `cd /repo && node script.js` | `node /repo/script.js` |
| bash | `cd /repo && bash script.sh` | `bash /repo/script.sh` |
| skill scripts | `cd /skill && ./run.sh` | `/full/path/to/skill/run.sh` |

Only exception: when a tool has absolutely no path parameter and must run in a specific directory (very rare).

## Do Not Chain Independent Commands with &&

```
# ✅ Good: issue multiple parallel Bash tool calls
Bash: git -C /repo log --oneline -5
Bash: git -C /repo status
Bash: git -C /repo diff --name-only
```

```
# ❌ Bad: chain everything together
Bash: git -C /repo log --oneline -5 && git -C /repo status && git -C /repo diff --name-only
```

## Pipes Are Fine

Pipes count as a single command and work normally:

```
# ✅ Good
Bash: git -C /repo branch -a | grep -i claude
Bash: gh api repos/org/repo/pulls/123/comments --paginate | python3 -c "..."
Bash: /path/to/fetch.sh --author user | /path/to/check.sh --threshold 2
```

## Decision Guide

| Scenario | Approach |
|----------|----------|
| Need to run in a specific directory | Use tool's path parameter (`git -C`, `pnpm -C`, `gh --repo`) |
| Single command + pipe | Execute directly ✅ |
| Multiple independent commands | Split into parallel Bash tool calls ✅ |
| Sequential dependent operations | Split into sequential Bash tool calls ✅ |

## Why

`settings.json` `permissions.allow` uses glob patterns to match commands.
Using `cd` requires compound patterns like `cd * && *` — multi-segment patterns are hard to maintain and frequently miss edge cases.
Using tool path parameters keeps commands atomic, matching simple patterns (e.g., `git *`, `pnpm *`).
