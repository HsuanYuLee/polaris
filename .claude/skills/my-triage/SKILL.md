---
name: my-triage
description: >
  Triage and prioritize all assigned work: Epics, Bugs, and orphan Tasks/Stories.
  Queries JIRA for active items, verifies actual status (catches "looks active but
  already Done"), sorts by priority + type, checks GitHub PR progress for In Development
  items, and outputs a prioritized dashboard. Writes triage state for /standup TDT integration.
  Use when: (1) user says "我的 epic", "my epics", "盤點", "triage", "手上有什麼",
  "排優先", "prioritize", "my work", "我的工作", (2) user was assigned new work and wants
  to plan order, (3) sprint start to decide what to work on first.
metadata:
  author: Polaris
  version: 1.1.0
---

# My Triage — 每日工作盤點與排序

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`jira.projects`、`github.org`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## Step 1：撈取所有 assigned active 工作項目

掃描三類工作：Epic、Bug、無 parent 的獨立 Task/Story。

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}
  jql: assignee = currentUser() AND status not in (Done, Closed, Launched, 完成) AND (issuetype = Epic OR issuetype = Bug OR (issuetype in (Story, Task, 任務, 大型工作) AND "Epic Link" is EMPTY)) AND project in ({config: jira.projects[].key}) ORDER BY priority DESC, created DESC
  fields: ["summary", "status", "priority", "created", "duedate", "customfield_10016", "fixVersions", "issuetype", "parent"]
  maxResults: 50
```

撈回後，過濾掉有 `parent` 欄位的 Task/Story（這些已歸屬 Epic，由 Epic 涵蓋）。保留：
- 所有 Epic（不論有無 parent）
- 所有 Bug（不論有無 parent — Bug 即使掛在 Epic 底下也獨立追蹤，因為通常需要緊急處理）
- 無 parent 的 Task/Story（孤兒票）

## Step 2：狀態驗證

JIRA board 的 column mapping 和實際 status 可能不同步（例如 board 顯示「Waiting for Stage」但實際已是 Done）。

對每張 ticket 檢查：
- `status.statusCategory.key == "done"` → 標記為 **已完成（狀態不同步）**，從 active 清單移除
- `status.statusCategory.key == "indeterminate"` 且 status name 含 "stage"/"waiting" → 標記為 **等待部署**，檢查是否已 release

回報發現的不同步：
```
⚠️ 狀態不同步（JIRA board 顯示 active 但實際已完成）：
  - GT-450 [AEO] 方案資訊結構化資料 → 實際狀態：完成
  - GT-449 [AEO] 修正商品頁結構化資料 → 實際狀態：完成
```

## Step 3：GitHub 進度補充（僅 In Development）

對 status 為 In Development 的項目，並行查詢 GitHub：

```bash
# 查 PR 狀態（Epic 用 key 搜子單 PR，Bug/Task 直接搜 key）
gh pr list --search "<TICKET_KEY>" --state all \
  --json number,title,state,headRefName,baseRefName,mergeable,statusCheckRollup,reviews --limit 10
```

標註每張 In Dev 項目的進度：
- 有 open PR 待 merge → `PR #N open`
- 有 merged PR → `PR #N merged`
- CI 紅 → `CI ❌`
- 有 review comments → `Review 待修`
- 無 PR → `開發中，尚無 PR`

## Step 4：排序與分群

按以下順序排列：

### Group 1：🐛 Bug（最優先）
Bug 按 priority 排序（P0 > P1 > ...），同 priority 按 created ASC。
Bug 不論狀態都排在最前面（即使是待辦也比 Epic 優先顯示）。

### Group 2：🔧 In Development（進行中的 Epic / Task）
按 PR 進度排序（快完成的排前面）：
1. PR merged / approved → 快完成 🟢
2. PR open, CI pass → 等 review
3. PR open, CI red / review comments → 有 blocker
4. 無 PR → 開發中

### Group 3：📋 待辦 — Highest
按 created date ASC（先開的先做）

### Group 4：📋 待辦 — High
按 created date ASC

### Group 5：📋 待辦 — Medium / Low
按 created date ASC

## Step 5：產出 Dashboard 並寫入 Triage State

```
══════════════════════════════════════
📋 My Triage Dashboard — YYYY-MM-DD
══════════════════════════════════════

Active: N 張（Epic: A | Bug: B | Task: C）| In Dev: X 張 | 待辦: Y 張 | 總估點: Z（未估: W 張）

🐛 Bug
  1. KB2CW-3599 商品頁 XXX 問題 — P0, In Development, PR #99 open

🔧 In Development
  2. GT-483 [CWV] TTFB 優化 (Epic) — 17 SP — PR #88 approved, 待 merge 🟢
  3. GT-478 [CWV] JS Bundle 瘦身 (Epic) — PR #92 open, CI ✅
  4. GT-480 CWV 報表 mobile (Epic) — 觀察中，明天收

📋 待辦 — Highest
  5. GT-495 [SEO] 首頁結構化資料 (Epic) — 未估點
  6. GT-510 商品頁 OG image 修正 (Task) — 3 SP
  ...

📋 待辦 — High
  10. GT-509 AI 爬蟲調查 (Epic) — 未估點
  ...

⚠️ 狀態不同步（已自動排除）
  - GT-450, GT-449 — 實際已完成

💡 建議下一步
  - Bug KB2CW-3599 是 P0，優先處理
  - GT-483 快完成了，merge 後可收
  - 待辦 Highest 有 6 張未估點，建議批次估點
══════════════════════════════════════
```

**同時寫入 Triage State**：產出 dashboard 的同一步驟內，立即將精簡狀態寫入 `{company}/.daily-triage.json`（供 `/standup` TDT 讀取）。這兩個動作必須在同一輪完成，不可拆成獨立步驟，避免對話中斷導致寫檔被跳過。

```json
{
  "date": "2026-03-31",
  "items": [
    {
      "key": "KB2CW-3599",
      "summary": "商品頁 XXX 問題",
      "type": "Bug",
      "priority": "Highest",
      "status": "In Development",
      "sp": null,
      "progress": "pr_open",
      "rank": 1
    },
    {
      "key": "GT-483",
      "summary": "[CWV] TTFB 優化",
      "type": "Epic",
      "priority": "Highest",
      "status": "In Development",
      "sp": 17,
      "progress": "pr_approved",
      "rank": 2
    }
  ]
}
```

JSON 欄位說明：
- `type`：`Epic` / `Bug` / `Task` / `Story`
- `progress` 欄位值：
  - `pr_merged` — PR 已 merge
  - `pr_approved` — PR 已 approved，待 merge
  - `pr_open` — PR open，review 中
  - `pr_blocked` — PR 有 CI 紅或 review comments
  - `in_dev` — 開發中，無 PR
  - `not_started` — 待辦

State 檔路徑從 workspace config 的 company 目錄推算。檔案只保留最新一次的結果（覆寫）。

## Standup 連動

`/standup` 的 TDT（Today's To Do）區塊會讀取 `.daily-triage.json`：

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
- Do: Bug 永遠排在 Dashboard 最上方，不論 priority
- Do: 子單 > 10 張時委派 sub-agent 查 GitHub
- Don't: 自動修改 JIRA 狀態 — 只讀只報
- Don't: 每次都重新掃全部 — 如果 triage state 存在且是今天的，提示「今天已盤點過，要重新掃嗎？」
- Don't: 和 `/sprint-planning` 混淆 — sprint-planning 是團隊級的 sprint 規劃（含 capacity、carry-over），my-triage 是個人級的工作盤點
- Don't: 掃有 parent 的 Task/Story — 這些已在 Epic 底下追蹤

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.1.0 | 2026-03-31 | Rename my-epics → my-triage; expand scope to Bug + orphan Task/Story; `.epic-triage.json` → `.daily-triage.json`; Step 5+6 merged |
| 1.0.0 | 2026-03-31 | Initial release — JIRA triage + GitHub progress + standup state integration |
