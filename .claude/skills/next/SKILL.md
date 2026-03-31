---
name: next
description: >
  Zero-input context router — reads todo list, git branch, git status, and JIRA ticket
  state to auto-determine and invoke the correct next action. Reduces user memory burden
  after context compression or session breaks. Use when: (1) user says "下一步", "next",
  "繼續", "continue", "然後呢", "what's next", "接下來", (2) user returns to a session
  and wants to resume, (3) after completing a task and wondering what to do next.
  Key distinction: "做 PROJ-123" → work-on (explicit ticket); "下一步" with no ticket → here.
metadata:
  author: Polaris
  version: 1.0.0
---

# Next — 自動判斷下一步

使用者只需要說「下一步」或「繼續」，skill 自動讀取當前狀態並路由到正確的動作。

## 狀態來源

按優先級依序檢查：

1. **Todo list** — 是否有未完成的任務？
2. **Git branch** — 當前 branch 是否包含 JIRA ticket key？
3. **Git status** — 是否有未 commit 的變更？
4. **JIRA ticket** — ticket 的狀態是什麼？
5. **GitHub PR** — 是否已有 PR？PR 狀態如何？

## Step 1：收集狀態（並行）

同時執行以下查詢：

```bash
# Git branch name
git -C {project_path} branch --show-current

# Git status
git -C {project_path} status --porcelain

# Git diff stats (if any changes)
git -C {project_path} diff --stat
```

從 branch name 提取 JIRA ticket key（格式：`task/PROJ-123-*` 或 `feat/PROJ-123-*`）。

若 branch 是 `main`/`develop`/`master` → 沒有 ticket context，跳至 Step 3。

## Step 2：查詢 JIRA + GitHub（並行）

有 ticket key 時，並行查詢：

```
# JIRA
mcp__claude_ai_Atlassian__getJiraIssue
  issueIdOrKey: <TICKET_KEY>
  fields: status,summary,issuetype,parent

# GitHub PR
gh pr list --search "<TICKET_KEY>" --state all \
  --json number,title,state,headRefName,reviews,statusCheckRollup,isDraft --limit 5
```

## Step 3：決策樹

```
Level 0: Todo list
├─ 有 in_progress 任務 → 回報任務內容，繼續執行
├─ 有 pending 任務（無 in_progress）→ 回報下一個 pending，開始執行
└─ 無任務 → 繼續 Level 1

Level 1: Git branch context
├─ 在 main/develop → 無 ticket context → 跳至 Level 4
└─ 在 ticket branch → 繼續 Level 2

Level 2: JIRA ticket 狀態
├─ Open / To Do → 「ticket 還沒開始」→ invoke start-dev
├─ In Development → 繼續 Level 3
├─ Code Review → 繼續 Level 3
├─ Done / Closed → 「ticket 已完成」→ 跳至 Level 4
└─ 其他狀態 → 回報狀態，建議下一步

Level 3: GitHub PR + Git 狀態
├─ 無 PR + 有 uncommitted changes → 「有改動但還沒 PR」→ invoke git-pr-workflow
├─ 無 PR + 無 changes → 「branch 是空的」→ 「開始開發？」→ invoke work-on <TICKET>
├─ PR open + CI 紅 → 「CI 失敗」→ invoke fix-pr-review
├─ PR open + CHANGES_REQUESTED → 「有 review 要修」→ invoke fix-pr-review
├─ PR open + 0 approved → 「等 review」→ invoke check-pr-approvals
├─ PR open + approved ≥ threshold → 「已 approved，可以 merge」→ 回報
├─ PR merged → 「PR 已 merge」→ 跳至 Level 4
└─ PR draft → 「PR 是 draft」→ 建議 ready for review 或繼續開發

Level 4: 無 ticket context 或 ticket 已完成
├─ 有 parent Epic → 「看 Epic 進度？」→ 建議 epic-status <EPIC_KEY>
└─ 無 context → 「沒有進行中的工作，要做什麼？」
    → 建議最近的 JIRA ticket 或 sprint backlog
```

## Step 4：執行

決策樹找到目標後：

1. **簡短回報**目前狀態和判斷理由（一句話）
2. **直接 invoke** 對應 skill（用 Skill tool）
3. 不問「要繼續嗎？」— 使用者說「下一步」就是要動作

### 範例輸出

```
📍 Branch: task/PROJ-448-product-listing
📋 JIRA: In Development | PR: #1920 open, CI ✅, Review: CHANGES_REQUESTED

→ 有 review 要修，啟動 fix-pr-review...
```

```
📍 Branch: main（無 ticket context）
📋 Todo: [in_progress] 修正 GT-480 的 CWV 報表

→ 繼續之前的任務...
```

```
📍 Branch: task/PROJ-450-checkout-flow
📋 JIRA: In Development | 無 PR | Git: 3 files changed

→ 有改動但還沒 PR，啟動 git-pr-workflow...
```

## Do / Don't

- Do: 一句話回報 + 直接動作，不冗長解釋
- Do: 並行查詢所有狀態來源，減少等待
- Do: 尊重 todo list 最高優先 — 如果有未完成任務，先完成它
- Do: 從 branch name 提取 ticket key 時支援 `task/`、`feat/`、`fix/`、`chore/` 等前綴
- Don't: 問「要做什麼？」— 使用者說「下一步」就是要你判斷
- Don't: 列出所有可能選項讓使用者選 — 直接路由到最合理的一個
- Don't: 在沒有任何 context 時 silently fail — 至少建議查 sprint backlog

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-03-31 | Initial release — todo + git + JIRA + PR context routing |
