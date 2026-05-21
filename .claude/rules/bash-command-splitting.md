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

## Aggregate File Lists Need xargs

對多個 changed Markdown 跑 aggregate validator 時，不要把 newline-separated file list 塞進
shell 變數再當單一參數傳：

```bash
# ❌ Wrong — newline handling 在不同 shell/tool 之間不一致，validator 會把整串當一個路徑
changed=$(git diff --name-only ...)
bash scripts/validate-language-policy.sh ... $changed
```

```bash
# ✅ Correct — 透過 xargs 把每個路徑變成獨立 argument
git diff --name-only -- .claude/skills \
  | rg '\.md$' \
  | xargs bash scripts/validate-language-policy.sh --blocking --mode artifact
```

Starlight authoring check 額外要排除共用 index：

```bash
git diff --name-only -- .claude/skills/references \
  | rg '\.md$' \
  | rg -v '^\.claude/skills/references/INDEX\.md$' \
  | xargs bash scripts/validate-starlight-authoring.sh check
```

Why：`references/INDEX.md` 故意不寫 Starlight frontmatter，當 Starlight page 檢查會誤報；
path argument handling bug 也會讓 aggregate gate 看起來像 content failure，實際上是命令
構造錯誤。

## Helper Script Invocation — Workspace Root

Polaris helper scripts 不保證在 fresh shell 的 `PATH` 上。**禁止**直接呼叫 script 名稱、
依賴環境變數 PATH：

```bash
# ❌ Wrong
polaris-learnings.sh query --top 5 --min-confidence 3
```

```bash
# ✅ Correct — 用 workspace-relative path 並設定 POLARIS_WORKSPACE_ROOT
POLARIS_WORKSPACE_ROOT=/Users/hsuanyu.lee/work \
  bash scripts/polaris-learnings.sh query --top 5 --min-confidence 3
```

Why：`scripts/polaris-learnings.sh` 與多支 Polaris helper 在 `POLARIS_WORKSPACE_ROOT` 缺失時
fail-stop。By-path 呼叫讓 cwd 無關，避免假性 `command not found` 與「我以為這支 script 不
存在」的誤判。

## Gate Preflight Fail-Stop

任何「gate → external side effect」command sequence（PR/JIRA/Slack write）都要把 gate 與
writer 放在 fail-stop boundary：

```bash
set -euo pipefail
tmp="$(mktemp)"
printf '%s\n' "$body" > "$tmp"
bash scripts/validate-language-policy.sh --blocking --mode artifact "$tmp"
gh pr create --body-file "$tmp"
```

- 用 `set -euo pipefail`，或把 gate 與 writer 拆兩個 command，writer 只在 gate exit 0 後執行。
- Validator 需要 file path 時，materialize 一個真實的 `mktemp` 檔案，不要依賴 process
  substitution（不同 shell 行為不一致）。
- Why：PR/JIRA/Slack 寫入屬於 external side effect，gate 失敗後 writer 仍跑會造成 policy
  drift，事後需手動清理（撤 PR、刪 comment、發 retraction 訊息）。

## Why

`settings.json` `permissions.allow` uses glob patterns to match commands.
Using `cd` requires compound patterns like `cd * && *` — multi-segment patterns are hard to maintain and frequently miss edge cases.
Using tool path parameters keeps commands atomic, matching simple patterns (e.g., `git *`, `pnpm *`).
