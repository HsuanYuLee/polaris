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
