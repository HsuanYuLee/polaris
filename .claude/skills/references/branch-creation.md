# Branch Creation Reference

## Utility Script

**Path:** `scripts/create-branch.sh`

```bash
bash scripts/create-branch.sh <TICKET> <DESCRIPTION> [BASE_BRANCH]
```

| Argument | Required | Default | Example |
|----------|----------|---------|---------|
| `TICKET` | Yes | — | `PROJ-419` |
| `DESCRIPTION` | Yes | — | `remove-elapsed-time-log` |
| `BASE_BRANCH` | No | `develop` | `master`, `rc` |

The script validates ticket format, sanitises description to kebab-case, handles existing branches, and runs `git fetch` + `git checkout -b`.

## Branch Naming Convention

Format: `task/<TICKET>-<description>` (e.g. `task/TASK-123-remove-presale-ab-test-logic`)

### Deriving DESCRIPTION from JIRA Summary

1. Translate Chinese/Japanese to English if needed
2. Drop filler words (the, a, an, for, of, to, in, on, at, with, and, or)
3. Lowercase, hyphens instead of spaces, 3-6 words

| JIRA Summary | DESCRIPTION |
|-------------|-------------|
| 移除售前客服商品頁導流 AB test 相關邏輯 | remove-presale-ab-test-logic |
| Fix currency check on checkout page | fix-currency-check-checkout |
| [JP] DX メインページ改修 | jp-dx-main-page |

**CJK validation**: if translated DESCRIPTION is empty or only hyphens, use ticket key only (e.g. `task/PROJ-123`) and warn user.

## Dependency Branch Detection

Before determining base branch, check if the ticket depends on an unmerged branch:

### 1. Check JIRA comments for dependency markers

Scan comments for: `base on`, `depends on`, `依賴`, `需等`, `merge 後再`. Extract dependent ticket key.

### 2. Locate the dependency branch (multi-strategy)

In order until match found:
1. `gh pr list --search "<DEPENDENT_TICKET_KEY>" --state open` — search PR by JIRA key
2. Fetch dependent ticket summary → `gh pr list --search "<SUMMARY_KEYWORDS>"` — search by summary
3. `searchJiraIssuesUsingJql: parent = <DEPENDENT_TICKET_KEY>` → search PRs by sub-task keys
4. `git branch -a | grep -i "<DEPENDENT_TICKET_KEY>"` — direct git search

### 3. Confirm with user (always)

> PROJ-448 依賴 PROJ-450（找到 branch: `feat/PROJ-460-...`, PR #1920, Open）。要從該 branch 開出嗎？

### 4. Standard base branch rules (if no dependency)

- User says "hotfix" → `master`
- User says "rc fix" → `rc`
- User explicitly specifies → use that branch
- Otherwise → `develop`

## Post-Branch: Deploy AI Config

After branch creation, deploy Polaris AI config:

```bash
{base_dir}/polaris-sync.sh {project-name}
```

## Consumer Side Note — engineering reads Base branch via resolve-task-base.sh

本文件描述 breakdown-side 如何建立 task branch 並在 task.md 寫入 `Base branch` 欄位。**engineering 消費此欄位時，不可直接讀字面值** — 必須經過 resolve helper：

```bash
RESOLVED_BASE=$("${CLAUDE_PROJECT_DIR}/scripts/resolve-task-base.sh" "<path/to/task.md>")
```

Helper 會在「上游 task branch 已 merged 到 Epic feature branch」時自動回退到 feature branch 值，避免 rebase / PR 指向已刪除的 remote branch。

新 task.md 同時寫入 `Branch chain`，用來表達完整 cascade rebase 順序，例如：

```text
develop -> feat/PROJ-123-cwv-js-bundle -> task/TASK-123-dayjs-infra -> task/TASK-123-products
```

engineering first-cut / revision 會以 `scripts/cascade-rebase-chain.sh` 先自上而下 rebase 這條鏈；但 `gh pr create --base` / `gh pr edit --base` 仍只使用 `resolve-task-base.sh` 的輸出。

若本文件的 branch 建立指令有消費者場景（如使用者手動建新 branch 時指定 base），同樣建議走 resolve helper：

```bash
RESOLVED_BASE=$("${CLAUDE_PROJECT_DIR}/scripts/resolve-task-base.sh" "<path/to/task.md>")
bash scripts/create-branch.sh <TICKET> <DESCRIPTION> "${RESOLVED_BASE}"
```

應用細節（§ 4.5 / § R0 / Step 7 三處消費點）見 `references/engineer-delivery-flow.md § Base Branch Resolution`（DP-028 D2 / D4 / D6）。
