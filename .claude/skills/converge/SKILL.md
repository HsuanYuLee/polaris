---
name: converge
description: "Use when the user wants to push all in-flight work forward toward review in one pass — closing gaps across Epics, Bugs, and orphan Tasks. NOT for single-ticket work (use work-on) or read-only triage (use my-triage). Trigger: '收斂', 'converge', '推進', '全部推到 review', '把我的單收一收', 'epic 進度', '離 merge 還多遠', '補全'."
metadata:
  author: Polaris
  version: 1.0.0
---

# Converge — Batch Convergence Orchestrator

Scans all assigned work, detects gaps between current state and "ready for review / merge",
proposes a prioritized execution plan, then auto-executes after user confirmation.

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`jira.projects`、`github.org`、`teams`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## Phase 1 — 掃描 + Gap 分析（自動，不問使用者）

### Step 1: 撈取所有 assigned active 工作

複用 my-triage Step 1 JQL：

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}
  jql: assignee = currentUser() AND status not in (Done, Closed, Launched, 完成) AND (issuetype = Epic OR issuetype = Bug OR (issuetype in (Story, Task, 任務, 大型工作) AND "Epic Link" is EMPTY)) AND project in ({config: jira.projects[].key}) ORDER BY priority DESC, created DESC
  fields: ["summary", "status", "priority", "created", "duedate", "customfield_10016", "fixVersions", "issuetype", "parent"]
  maxResults: 50
```

過濾規則同 my-triage：保留 Epic + Bug + 無 parent 的 Task/Story。

### Step 2: 展開 Epic 子單

對每個 Epic，查詢其子單：

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}
  jql: "Epic Link" = {EPIC_KEY} AND assignee = currentUser() ORDER BY created ASC
  fields: ["summary", "status", "issuetype", "priority", "customfield_10016"]
  maxResults: 30
```

> 子單 > 10 張時，委派 sub-agent 並行查詢 JIRA + GitHub（見 § Sub-agent 批次掃描）。

### Step 3: GitHub PR 狀態掃描

對每張 status 為 In Development / Code Review 的 ticket，以及每個 Epic 的 feature branch：

**單一 PR 狀態**（使用共用 script）：
```bash
/path/to/references/scripts/get-pr-status.sh {owner}/{repo} {pr_number}
```

回傳 JSON keys：`ci.status`、`reviews.approved`、`reviews.changes_requested`、`comments.unresolved`、`mergeable`

**Feature PR 檢查**（使用共用 script）：
```bash
/path/to/references/scripts/check-feature-pr.sh {owner}/{repo} {feature_branch} --base develop
```

回傳 JSON keys：`task_prs.all_merged`、`feature_pr.exists`、`feature_pr.number`、`feature_pr.state`

找不到 PR 的 ticket → `gh pr list --search "{TICKET_KEY}" --state all`

### Step 4: Gap 分類

對每張 ticket（含 Epic 子單），判定 gap type：

| Gap Type | 條件 | 自動路由 |
|----------|------|----------|
| `NO_ESTIMATE` | `customfield_10016` (SP) 為 null 且不是 Bug | `jira-estimation` |
| `NO_BREAKDOWN` | Epic 無子單 | `epic-breakdown` |
| `NOT_STARTED` | status = 待辦事項/開放，有估點 | `work-on` |
| `CODE_NO_PR` | status = In Development，無 open PR | `git-pr-workflow` |
| `CI_RED` | PR 存在，CI 失敗 | `fix-pr-review` |
| `CHANGES_REQUESTED` | PR 有 CHANGES_REQUESTED review | `fix-pr-review` |
| `HAS_UNRESOLVED_COMMENTS` | PR 有未解決的 review comments（含 COMMENTED 狀態） | `fix-pr-review` |
| `REVIEW_STUCK` | PR open > 2 天，0 approved | `check-pr-approvals` |
| `STALE_APPROVAL` | PR approved 但 approval 已過期（新 commit 後未 re-approve） | `check-pr-approvals` |
| `VERIFICATION_PENDING` | 開發完成但 [驗證] 子單未完成 | `verify-completion` |
| `NO_FEATURE_PR` | 所有 task PR 已 merge，但無 feature → develop PR | feature-branch-pr-gate 自動建立 |
| `MERGE_CONFLICT` | PR 有衝突 | 報告，不自動執行 |
| `WAITING_QA` | status = Waiting for QA | ⏸ 跳過 |
| `WAITING_RELEASE` | status = Waiting for Release / Ready for Stage | ⏸ 跳過 |
| `READY` | 無 gap，等待 merge 或已完成 | ✅ 不需動作 |

一張 ticket 可能有多個 gap（例如 CI_RED + HAS_UNRESOLVED_COMMENTS），全部列出。

### Step 5: 排序

四層排序：

1. **Quick wins**（1 步到 review）— `CI_RED`、`CHANGES_REQUESTED`、`HAS_UNRESOLVED_COMMENTS`、`CODE_NO_PR`、`NO_FEATURE_PR`
2. **需要實作**（2-3 步）— `NOT_STARTED`（已估點）、`VERIFICATION_PENDING`
3. **需要規劃**（4+ 步）— `NO_ESTIMATE`、`NO_BREAKDOWN`
4. **等別人**（跳過）— `REVIEW_STUCK`、`STALE_APPROVAL`、`WAITING_QA`、`WAITING_RELEASE`、`MERGE_CONFLICT`

同層內：離 review 步數少 → 多，self-actionable first。

## Phase 2 — 提案（等使用者確認）

呈現執行計畫：

```
══════════════════════════════════════
🔄 Converge Plan — YYYY-MM-DD
══════════════════════════════════════

Scanned: N tickets（Epic: A | Bug: B | Task: C）
Gaps found: X | Ready: Y | Skipped: Z

⚡ Quick Wins（1 步）
  1. PROJ-101 [CWV] JS Bundle 瘦身 — CI_RED on PR #92 → fix-pr-review
  2. TEAM-201 SKU 價格 Bug — CODE_NO_PR → git-pr-workflow

🔨 需要實作（2-3 步）
  3. PROJ-106 AI 爬蟲調查 — NOT_STARTED (5 SP) → work-on
  4. PROJ-105 首頁結構化資料 — NOT_STARTED → work-on

📋 需要規劃
  5. PROJ-104 HTML + CSS 優化 — NO_ESTIMATE → jira-estimation
  6. PROJ-102 Category LCP+CLS — NO_ESTIMATE → jira-estimation

⏸ 等別人（不執行）
  - PROJ-100 TTFB 優化 — REVIEW_STUCK (PR #2066, 0 approved, 3 days)
  - TEAM-203 — WAITING_QA

✅ Ready（無 gap）
  - PROJ-103 CWV 報表 — Ready for Stage
══════════════════════════════════════

執行？(y/n/調整順序/移除項目)
```

使用者可以：
- `y` / `全部跑` — 依序執行全部
- 指定只跑某些項目（`跑 1, 2, 5`）
- 移除項目（`不要 3`）
- 調整順序

## Phase 3 — 執行（確認後自動推進）

### 執行策略

**Sequential by default**：依排序逐張執行，每完成一張報告狀態。

**Parallel when safe**：兩張 ticket 滿足以下全部條件時可 parallel（各自開 worktree）：
- 不在同一個 Epic 下
- 不修改同一個 repo 的同一組檔案
- 都是 Quick Win 層級

**每張 ticket 的執行流程**：

1. 根據 gap type 路由到對應 skill（見 Phase 1 Step 4 表格）
2. Sub-agent 讀取目標 skill 的 SKILL.md 並 inline 執行
3. 執行完成後回報結果（使用 Completion Envelope）
4. 主 agent 記錄結果，繼續下一張

### Gap → Skill 路由

| Gap Type | Skill | Dispatch Pattern | Model |
|----------|-------|-----------------|-------|
| `NO_BREAKDOWN` | `epic-breakdown` | Exploration → Analysis | sonnet |
| `NO_ESTIMATE` | `jira-estimation` | Exploration → Analysis (batch: haiku for JIRA writes) | sonnet/haiku |
| `NOT_STARTED` | `work-on` | Implementation | sonnet |
| `CODE_NO_PR` | `git-pr-workflow` | Implementation | sonnet |
| `CI_RED` | `fix-pr-review` | Implementation | sonnet |
| `CHANGES_REQUESTED` | `fix-pr-review` | Implementation | sonnet |
| `HAS_UNRESOLVED_COMMENTS` | `fix-pr-review` | Implementation | sonnet |
| `REVIEW_STUCK` | `check-pr-approvals` | JIRA + Slack notification | sonnet |
| `STALE_APPROVAL` | `check-pr-approvals` | JIRA + Slack notification | sonnet |
| `VERIFICATION_PENDING` | `verify-completion` | Verification (E2E + test plan) | sonnet |
| `NO_FEATURE_PR` | `feature-branch-pr-gate.md` reference | Implementation | sonnet |

### 安全機制

- **Restore point**：Phase 3 開始前，若 working tree 有 uncommitted changes → `git stash push -m "polaris-restore-converge-{timestamp}"`
- **Self-regulation scoring**：每個 sub-agent 獨立累計風險分數（見 `rules/sub-agent-delegation.md`），> 35% 停止並回報
- **Worktree isolation**：parallel 執行的 sub-agent 使用 `isolation: "worktree"` 避免衝突
- **Abort**：任一 sub-agent 回報 BLOCKED 且影響後續 ticket → 暫停，回報使用者

### NOT_STARTED 的特殊處理

`NOT_STARTED` gap 的 ticket 需要完整的 `work-on` 流程（分析 → plan → implement → quality → PR）。這是最重資源的操作：

- 單張 NOT_STARTED ticket → 直接路由 `work-on`
- 多張 NOT_STARTED tickets → 逐張執行（不 parallel），因為每張都可能修改大量檔案
- 使用者可以選擇只跑 Quick Wins，跳過 NOT_STARTED（`只跑 quick wins`）

### 批次估點的特殊處理

多張 `NO_ESTIMATE` tickets → 可以用 haiku model batch 建子單 + 估點，效率更高：

1. 一次讀取所有待估 Epic 的 description
2. 批次產出子單 + 估點建議
3. 呈現給使用者確認
4. 確認後 batch 建立 JIRA sub-tasks

## Phase 4 — 收斂報告

執行完畢後，重新跑 Phase 1 掃描（rescan），產出 before vs after 矩陣：

```
══════════════════════════════════════
📊 Converge Report — YYYY-MM-DD
══════════════════════════════════════

| Ticket | Before | After | Action Taken |
|--------|--------|-------|-------------|
| PROJ-101 | CI_RED | READY | fix-pr-review → CI pass |
| PROJ-106 | NOT_STARTED | CODE_REVIEW | work-on → PR #105 |
| PROJ-104 | NO_ESTIMATE | NOT_STARTED | jira-estimation → 8 SP |
| PROJ-100 | REVIEW_STUCK | REVIEW_STUCK | ⏸ skipped (等 review) |

Summary:
  ✅ Resolved: 3 gaps
  ⏸ Skipped: 2 (等別人)
  ❌ Failed: 0

Next actions:
  - PROJ-100: 催 review（要我發 Slack 嗎？）
  - TEAM-203: 追 QA 進度
══════════════════════════════════════
```

**Slack 催 review**：對 `REVIEW_STUCK` 的 ticket，問使用者是否要透過 `check-pr-approvals` 發 Slack 催 review。

## Sub-agent 批次掃描

當 Phase 1 的 ticket 總數 > 10，委派 sub-agent 並行掃描 GitHub 狀態：

```markdown
你是 GitHub 狀態掃描 agent。

## 輸入
以下 tickets 需要查詢 GitHub PR 狀態：
{ticket_list}

## 查詢方式
對每張 ticket：
1. `gh pr list --repo {owner}/{repo} --search "{TICKET_KEY}" --state all --json number,title,state,headRefName,statusCheckRollup,reviews,mergeable --limit 5`
2. 解析 CI 狀態、review 狀態、mergeable

## 回傳格式
| Ticket | PR # | State | CI | Approved | Changes Req | Unresolved | Mergeable |
|--------|------|-------|----|----------|-------------|------------|-----------|

## 限制
- 只做查詢，不修改任何東西
- 找不到 PR 就標 "no PR"
```

## Epic 模式 vs 全域模式

如果使用者指定了特定 Epic key（例：`converge PROJ-100`），只掃描該 Epic 及其子單，不掃全部。
這等同於原本 `epic-status` 的行為。

如果沒指定 ticket → 全域模式，掃描所有 assigned work。

## Do

- 並行查詢 JIRA + GitHub，減少等待
- Phase 2 必須等使用者確認才執行 Phase 3
- 用共用 scripts（`get-pr-status.sh`、`check-feature-pr.sh`）而不是 inline gh api
- Quick wins 優先，self-actionable first
- 每完成一張 ticket 立即報告，不要等全部做完
- Rescan after execution，讓使用者看到 before/after
- 記錄 gap routing 和結果到 session timeline

## Don't

- 不自動修改 JIRA 狀態 — 讓下游 skill 處理
- 不跳過 Phase 2 確認 — 這是批次操作，使用者需要審查計畫
- 不 parallel 執行 NOT_STARTED tickets — 太重，逐張跑
- 不處理其他人的 tickets — 只掃 assignee = currentUser()
- 不把 `WAITING_QA` / `WAITING_RELEASE` 當成 gap — 這些是正常流程
- 不跟 `/my-triage` 混淆 — triage 只看不動，converge 看了就動

## 跟現有 skill 的關係

| Skill | 變化 |
|-------|------|
| `my-triage` | 不變，純儀表板 |
| `epic-status` | 保留為 converge 的 Epic-only alias |
| `work-on` | 不變，converge 的下游執行器 |
| `fix-pr-review` | 不變，converge 的下游執行器 |
| `check-pr-approvals` | 不變，converge 的下游執行器 |
| `git-pr-workflow` | 不變，converge 的下游執行器 |
| `jira-estimation` | 不變，converge 的下游執行器 |
| `epic-breakdown` | 不變，converge 的下游執行器 |
| `verify-completion` | 不變，converge 的下游執行器 |

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-04-03 | Initial release — absorbs epic-status gap analysis, adds batch orchestration |


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
