---
name: jira-branch-checkout
description: >
  Create git branches from JIRA ticket numbers following the naming convention
  task/[JIRA_TICKET_NUMBER]-[DESCRIPTION]. Use this skill when: (1) The user explicitly
  asks to create or checkout a branch for a JIRA ticket (e.g. "開 branch PROJ-419",
  "create branch for PROJ-500"), (2) Another skill (like work-on or fix-bug)
  delegates branch creation to this skill. Trigger keywords: "開 branch", "create branch",
  "checkout branch", "建 branch", "切 branch", "hotfix branch".
  Do NOT trigger this skill when the user says "work on", "做", "implement", or "fix" a
  ticket — those should go to work-on or fix-bug, which will delegate to this
  skill for branch creation when needed.
metadata:
  author: Polaris
  version: 1.1.0
---

# JIRA Branch Checkout

All git operations are handled by `scripts/create-branch.sh`. The agent prepares
three arguments and invokes it.

## Utility scripts

**scripts/create-branch.sh**: Create a `task/<TICKET>-<DESC>` branch from a remote base.

```bash
bash scripts/create-branch.sh <TICKET> <DESCRIPTION> [BASE_BRANCH]
```

| Argument      | Required | Default   | Example                    |
|---------------|----------|-----------|----------------------------|
| `TICKET`      | Yes      | —         | `PROJ-419`                |
| `DESCRIPTION` | Yes      | —         | `remove-elapsed-time-log`  |
| `BASE_BRANCH` | No       | `develop` | `master`, `rc`             |

The script validates the ticket format, sanitises the description to kebab-case,
handles existing branches, and runs `git fetch` + `git checkout -b`.

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`github.org`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## Workflow

### 1. Extract TICKET from user message

e.g. `PROJ-419`, `VM-1186`, `BIDL-200`.

### 2. Fetch ticket title

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <TICKET>
```

### 3. Derive DESCRIPTION

Convert the JIRA summary to a **3–6 word** kebab-case English phrase:

1. Translate Chinese/Japanese to English if needed.
2. Drop filler words (the, a, an, for, of, to, in, on, at, with, and, or).
3. Lowercase, hyphens instead of spaces.

| JIRA Summary                           | DESCRIPTION                  |
|----------------------------------------|------------------------------|
| 移除售前客服商品頁導流 AB test 相關邏輯 | remove-presale-ab-test-logic |
| Fix currency check on checkout page    | fix-currency-check-checkout  |
| [JP] DX メインページ改修               | jp-dx-main-page              |
| Session config 調整                     | session-config               |

**CJK 翻譯結果驗證**：翻譯完成後，檢查清理後的 DESCRIPTION 是否有效：
- 若 DESCRIPTION 為空、僅包含連字號（`-`）、或僅包含空白字元 → 使用 JIRA ticket key 作為唯一標識（例如 `task/PROJ-123`），並警告使用者：「Could not generate a meaningful branch suffix from the CJK title. Using ticket key only.」
- Never produce a branch name with a trailing hyphen or empty suffix after the ticket number.

### 4. Check for dependency branch

Before determining the base branch, check if this ticket depends on an unmerged branch:

**4a. Check JIRA comments for dependency markers:**

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <TICKET>
  fields: ["comment"]
```

Scan comments for keywords: `base on`, `depends on`, `依賴`, `需等`, `merge 後再`.
Extract the dependent ticket key (e.g. `PROJ-450`).

**4b. If dependency found, locate the branch (multi-strategy):**

In the feature-branch → sub-branch model, the JIRA key in the comment may not match
the branch name (e.g. comment says `PROJ-450` but branch is `feat/PROJ-460-...`).
Use these strategies in order until a match is found:

1. **Search PR by JIRA key:**
   ```bash
   gh pr list --search "<DEPENDENT_TICKET_KEY>" --state open --json headRefName,number,title --limit 5
   ```

2. **If no exact match in PR title, search by JIRA summary:**
   Fetch the dependent ticket's summary from JIRA, then:
   ```bash
   gh pr list --search "<JIRA_SUMMARY_KEYWORDS>" --state open --json headRefName,number,title --limit 5
   ```

3. **Check JIRA sub-tasks for branch clues:**
   ```
   searchJiraIssuesUsingJql: parent = <DEPENDENT_TICKET_KEY>
   ```
   Then search PRs by sub-task keys.

4. **Search git branches directly:**
   ```bash
   git branch -a | grep -i "<DEPENDENT_TICKET_KEY>"
   ```

If multiple candidates are found, list them all for user to choose.
If no match found, ask the user to provide the branch name directly.

**4c. Confirm with user (always):**

> PROJ-448 依賴 PROJ-450（找到 branch: `feat/PROJ-460-aggregate-offer-structured-data`，PR #1920，Open）。
> 要從該 branch 開出嗎？

- User confirms → use that branch as BASE_BRANCH
- User declines or no dependency found → proceed to 4d

**4d. Standard base branch rules:**

- User says "hotfix" → `master`
- User says "rc fix" → `rc`
- User explicitly specifies a branch → use that branch
- Otherwise → `develop` (do not ask)

### 5. Run the script

```bash
bash "<SKILL_DIR>/scripts/create-branch.sh" "<TICKET>" "<DESCRIPTION>" "<BASE_BRANCH>"
```

Relay the output to the user and proceed with the requested task.
