---
name: sprint-planning
description: >
  Guides Sprint planning discussions by pulling JIRA tickets, calculating
  capacity, detecting carry-overs, suggesting priority order, and optionally
  generating a Confluence Release page draft. This skill automates the
  deterministic parts (data fetching, point tallying, dependency sorting) while
  leaving decisions to the user. Use this skill whenever the user mentions:
  "sprint planning", "planning", "下個 sprint", "排 sprint", "sprint 規劃",
  "plan sprint", "release page", "sprint backlog", "capacity planning",
  "carry over", "sprint candidate", "排單", or wants to prepare for or
  conduct a sprint planning session — even if they don't explicitly say
  "sprint planning".
metadata:
  author: ""
  version: 1.0.0
---

# Sprint Planning — Sprint 規劃討論引導

引導 Sprint Planning 討論：從 JIRA 拉取候選 tickets，計算 capacity，偵測 carry-over，建議優先排序，來回討論後產出最終 sprint backlog。可選推送 Confluence Release page。

**定位**：自動化確定性部分（拉 JIRA、算點數、排依賴），討論決策留給使用者。這不是一鍵產出工具，而是互動式的規劃助手。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`jira.projects`（取得 project keys 用於 JQL）、`confluence.space`、`scrum.sprint_capacity`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## Defaults

| 參數 | 預設值 | 說明 |
|------|--------|------|
| Sprint capacity | 20 pts （config: `scrum.sprint_capacity`） | 使用者的個人容量 |
| Sprint duration | 10 working days | 2 weeks |
| Projects | （config: `jira.projects[].key`） | 從 workspace-config.yaml 讀取 |
| Confluence space | （config: `confluence.space`） | Release page 所在空間 |

## Workflow

### 1. Collect inputs

兩種方式取得候選 tickets：

**方式 A — 使用者提供 ticket keys**：
使用者直接給一組 ticket keys（如 `PROJ-123 PROJ-123 TASK-123`），從 JIRA 拉取每張的資訊。

**方式 B — 從 JIRA board 自動拉取**：
搜尋使用者可能的候選：

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  jql: assignee = currentUser() AND status not in ("已釋出", "已關閉", "完成", "PENDING") AND project in ({config: jira.projects[].key}) ORDER BY priority DESC, updated DESC
  fields: ["summary", "status", "issuetype", "priority", "story_points", "sprint"]
  maxResults: 30
```

詢問使用者要用哪種方式，或者兩者結合（自動拉 + 使用者補充）。

### 2. Fetch ticket details

對每張候選 ticket 拉取完整資訊：

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <TICKET-KEY>
```

收集：
- **Key** + **標題**
- **Issue type**（Epic / Story / Task / Bug / Sub-task）
- **Status**（判斷 carry-over vs 新單）
- **Priority**
- **Story points**（如果已估點）
- **Sprint**（判斷是否已在某個 sprint 中）
- **Links**（判斷依賴關係：blocks / is blocked by）
- **Epic link**（歸屬哪個 Epic）

### 3. Detect carry-overs

Carry-over = 上個 sprint 未完成的單。判定條件：
- 在前一個 sprint 中（`sprint` 欄位）
- 狀態不是 `已釋出` / `完成` / `已關閉`

Carry-over 在排序時有更高優先權（已經開始的工作應該先完成）。

標記每張 carry-over ticket 的當前進度：
- `IN DEVELOPMENT` → 開發中，需繼續
- `CODE REVIEW` → PR 等待 review
- `WAITING FOR QA` → 等 QA
- 其他 → 標註狀態

### 4. Sort & suggest

用以下規則產出建議排序：

1. **Carry-over** 最優先（已投入成本，sunk cost 最小化）
2. **P0 / Highest priority** 次之
3. **有依賴關係的 tickets** 考慮順序：被 block 的排在 blocker 之後
4. **已估點的** 優先於未估點的（未估點的需要先估）
5. 同優先級按 Epic 分組（同 Epic 的單盡量排一起）

### 5. Present planning table

以表格呈現，讓使用者快速掌握全局：

```markdown
## Sprint Planning — Sprint YYYY.MM.DD

**Capacity**: 20 pts | **候選總點數**: XX pts | **差額**: ±Y pts

### Carry-over（上個 sprint 未完成）

| # | Ticket | Title | Type | Status | Points | Priority | Notes |
|---|--------|-------|------|--------|--------|----------|-------|
| 1 | PROJ-100 | feature title A | Story | CODE REVIEW | 3 | Medium | PR 等 review |
| 2 | PROJ-200 | bug title B | Bug | WAITING FOR QA | 2 | High | 等 QA |

小計：5 pts

### 新增候選

| # | Ticket | Title | Type | Points | Priority | Epic | Dependency | Notes |
|---|--------|-------|------|--------|----------|------|------------|-------|
| 3 | PROJ-123 | xxx | Story | 5 | High | PROJ-123 | — | |
| 4 | PROJ-123 | yyy | Task | 3 | Medium | PROJ-123 | blocked by PROJ-123 | |
| 5 | TASK-123 | zzz | Bug | ? | High | — | — | 未估點 |

小計：8+ pts

### 總計

| 項目 | 點數 |
|------|------|
| Carry-over | 5 |
| 新增候選 | 8+ |
| **合計** | **13+** |
| Capacity | 20 |
| **剩餘** | **7-** |
```

附加提示：
- 未估點的 tickets 用 `?` 標示，提醒需要先估點
- 超過 capacity 時標紅警告
- 依賴關係用箭頭標示（`blocked by PROJ-123`）

### 6. Interactive discussion

呈現表格後進入討論模式：

**使用者可能的操作**：
- 「移除 #5」→ 從候選中移除
- 「加入 PROJ-123」→ 新增到候選，拉 JIRA 資訊後更新表格
- 「PROJ-123 改 3 點」→ 調整估點
- 「PROJ-123 排到 PROJ-123 後面」→ 調整順序
- 「這個 sprint 我有 2 天請假」→ 調整 capacity（20 → 16 pts）
- 「OK」/ 「確定」→ 鎖定最終版本

每次調整後重新計算總點數和差額，更新表格呈現。

**Guardrails**：
- 總點數超過 capacity 10% 以上時主動提醒
- 有未估點的 tickets 時提醒需要先估點（可觸發 `jira-estimation`）
- 有依賴衝突時（如 A blocks B 但 B 排在 A 前面）主動提醒

### 7. Generate Release page draft (optional)

使用者確認最終 sprint backlog 後，詢問是否產出 Confluence Release page。

如果使用者同意：

**Step 7a — 計算 Release 日期**：
Sprint 結束日 = Sprint 開始日 + 10 working days。Release page 標題格式：`Release YYYYMMDD`。
詢問使用者確認日期（可能因假期調整）。

**Step 7b — 格式化 Release page**：

依照現有 Release page 格式（markdown bullet list，按團隊分組）：

```markdown
* Team A

    * [PROJ-100 ticket title](https://{config: jira.instance}/browse/PROJ-100) — Code Review
    * [PROJ-101 ticket title](https://{config: jira.instance}/browse/PROJ-101) — 開放

* Team B

    * [PROJ-200 ticket title](https://{config: jira.instance}/browse/PROJ-200) — Waiting for QA
```

每張 ticket 附上當前狀態。已關閉的用 `~~刪除線~~`。

**Step 7c — 推送 Confluence**：

搜尋是否已有該 Release page：

```
mcp__claude_ai_Atlassian__searchConfluenceUsingCql
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  cql: space = "{config: confluence.space}" AND title = "Release YYYYMMDD" AND type = page
```

- 已存在 → 更新（`updateConfluencePage`）
- 不存在 → 建立（`createConfluencePage`）

更新完成後附上 Confluence 頁面連結。

## Do

- 優先排 carry-over（已投入成本的工作）
- 即時重算點數和差額，每次調整後更新
- 依賴關係衝突時主動提醒
- 未估點 tickets 提醒需要先估
- Release page 格式嚴格遵循現有頁面風格
- 支持多輪來回討論，不急著鎖定

## Don't

- 不要自動決定 sprint 內容 — 排序是建議，決定權在使用者
- 不要未經確認就推 Confluence
- 不要把不屬於使用者的 tickets 加進來（除非使用者指定）
- 不要忽略 capacity 超標 — 必須明確提醒
- 不要在討論中途跳到其他 skill（如使用者說「PROJ-123 估幾點」可以建議觸發估點 skill，但不要自動觸發）

## Prerequisites

- Atlassian MCP 已連線（JIRA + Confluence）
- 使用者了解當前 sprint 狀態（或從 JIRA board 拉取）
