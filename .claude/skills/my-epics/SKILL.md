---
name: my-epics
description: >
  Triage and prioritize assigned Epics. Queries JIRA for all assigned active Epics,
  verifies actual status (catches "looks active but already Done"), sorts by priority +
  created date, checks GitHub PR progress for In Development items, and outputs a
  prioritized dashboard. Writes triage state for /standup TDT integration.
  Use when: (1) user says "我的 epic", "my epics", "盤點", "triage", "手上有什麼",
  "排優先", "prioritize", (2) user was assigned new epics and wants to plan order,
  (3) sprint start to decide what to work on first.
metadata:
  author: Polaris
  version: 1.0.0
---

# My Epics — 盤點與排序

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`jira.projects`、`github.org`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## Step 1：撈取所有 assigned active Epics

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}
  jql: assignee = currentUser() AND issuetype = Epic AND status not in (Done, Closed, Launched, 完成) ORDER BY priority DESC, created DESC
  fields: ["summary", "status", "priority", "created", "duedate", "customfield_10016", "fixVersions"]
  maxResults: 50
```

## Step 2：狀態驗證

JIRA board 的 column mapping 和實際 status 可能不同步（例如 board 顯示「Waiting for Stage」但實際已是 Done）。

對每張 Epic 檢查：
- `status.statusCategory.key == "done"` → 標記為 **已完成（狀態不同步）**，從 active 清單移除
- `status.statusCategory.key == "indeterminate"` 且 status name 含 "stage"/"waiting" → 標記為 **等待部署**，檢查是否已 release

回報發現的不同步：
```
⚠️ 狀態不同步（JIRA board 顯示 active 但實際已完成）：
  - GT-450 [AEO] 方案資訊結構化資料 → 實際狀態：完成
  - GT-449 [AEO] 修正商品頁結構化資料 → 實際狀態：完成
```

## Step 3：GitHub 進度補充（僅 In Development）

對 status 為 In Development 的 Epics，並行查詢 GitHub：

```bash
# 查子單的 PR 狀態
gh pr list --search "<EPIC_KEY>" --state all \
  --json number,title,state,headRefName,baseRefName,mergeable,statusCheckRollup,reviews --limit 10
```

標註每張 In Dev Epic 的進度：
- 有 open PR 待 merge → `PR #N open`
- 有 merged PR → `PR #N merged`
- CI 紅 → `CI ❌`
- 有 review comments → `Review 待修`
- 無 PR → `開發中，尚無 PR`

## Step 4：排序與分群

按以下順序排列：

### Group 1：In Development（進行中）
按 PR 進度排序（快完成的排前面）：
1. PR merged / approved → 快完成 🟢
2. PR open, CI pass → 等 review
3. PR open, CI red / review comments → 有 blocker
4. 無 PR → 開發中

### Group 2：待辦 — Highest
按 created date ASC（先開的先做）

### Group 3：待辦 — High
按 created date ASC

### Group 4：待辦 — Medium / Low
按 created date ASC

## Step 5：產出 Dashboard

```
══════════════════════════════════════
📋 My Epics Dashboard — YYYY-MM-DD
══════════════════════════════════════

Active: N 張 | In Dev: X 張 | 待辦: Y 張 | 總估點: Z（未估: W 張）

🔧 In Development
  1. GT-483 [CWV] TTFB 優化 — 17 SP — PR #88 approved, 待 merge 🟢
  2. GT-478 [CWV] JS Bundle 瘦身 — PR #92 open, CI ✅
  3. GT-480 CWV 報表 mobile — 觀察中，明天收

📋 待辦 — Highest
  4. GT-495 [SEO] 首頁結構化資料 — 未估點
  5. GT-490 [SEO] FAQ H3 優化 — 未估點
  ...

📋 待辦 — High
  10. GT-509 AI 爬蟲調查 — 未估點
  ...

⚠️ 狀態不同步（已自動排除）
  - GT-450, GT-449 — 實際已完成

💡 建議下一步
  - GT-483 快完成了，merge 後可收
  - 待辦 Highest 有 6 張未估點，建議批次估點：做 GT-495 GT-490 GT-489
══════════════════════════════════════
```

## Step 6：寫入 Triage State

產出 dashboard 後，將精簡狀態寫入 `{company}/.epic-triage.json`（供 `/standup` TDT 讀取）：

```json
{
  "date": "2026-03-31",
  "epics": [
    {
      "key": "GT-483",
      "summary": "[CWV] TTFB 優化",
      "priority": "Highest",
      "status": "In Development",
      "sp": 17,
      "progress": "pr_approved",
      "rank": 1
    },
    {
      "key": "GT-495",
      "summary": "[SEO] 首頁結構化資料",
      "priority": "Highest",
      "status": "待辦",
      "sp": null,
      "progress": "not_started",
      "rank": 4
    }
  ]
}
```

`progress` 欄位值：
- `pr_merged` — PR 已 merge
- `pr_approved` — PR 已 approved，待 merge
- `pr_open` — PR open，review 中
- `pr_blocked` — PR 有 CI 紅或 review comments
- `in_dev` — 開發中，無 PR
- `not_started` — 待辦

State 檔路徑從 workspace config 的 company 目錄推算。檔案只保留最新一次的結果（覆寫）。

## Standup 連動

`/standup` 的 TDT（Today's To Do）區塊會讀取 `.epic-triage.json`：

1. **TDT 排序**：按 triage rank 排序今天要做的項目，而不是隨機列
2. **進度燈號**：比對 triage 時的 `progress` 和今天的實際狀態
   - 實際進度 > triage 時的預期 → 🟢 超前
   - 實際進度 = 預期 → ⚪ 正常
   - 實際進度 < 預期 → 🔴 落後
3. **無 triage state 時**：TDT 照原本邏輯（git branch + JIRA status），不影響現有行為

### 進度比較表

| triage progress | 今天實際 | 燈號 |
|----------------|---------|------|
| `not_started` | `in_dev` 或更高 | 🟢 超前 |
| `in_dev` | `pr_open` 或更高 | 🟢 超前 |
| `pr_open` | `pr_approved` 或 `pr_merged` | 🟢 超前 |
| `pr_blocked` | `pr_open`（blocker 已解除） | 🟢 超前 |
| 任何 | 同級 | ⚪ 正常 |
| `pr_open` | 仍 `pr_open` 超過 2 天 | 🔴 卡住 |
| `in_dev` | 仍 `in_dev` 超過 3 天 | 🔴 落後 |

## Do / Don't

- Do: 並行查詢 JIRA + GitHub，減少等待
- Do: 主動發現狀態不同步的 tickets 並回報
- Do: 對未估點的 Highest epic 建議批次估點
- Do: 子單 > 10 張時委派 sub-agent 查 GitHub
- Don't: 自動修改 JIRA 狀態 — 只讀只報
- Don't: 每次都重新掃全部 — 如果 triage state 存在且是今天的，提示「今天已盤點過，要重新掃嗎？」
- Don't: 和 `/sprint-planning` 混淆 — sprint-planning 是團隊級的 sprint 規劃（含 capacity、carry-over），my-epics 是個人級的工作盤點

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-03-31 | Initial release — JIRA triage + GitHub progress + standup state integration |
