---
name: standup
description: >
  Generates daily standup reports (YDY/TDT/BOS/口頭同步) by collecting git activity,
  JIRA status changes, and Google Calendar meetings. Merges all sources,
  deduplicates, groups by configured teams, and formats all four sections for Confluence. Use
  this skill whenever the user mentions: "standup", "站立會議",
  "standup meeting", "YDY", "今天做了什麼", "what did I do today", "daily standup",
  "產出 standup", "generate standup", "standup report", "寫 standup",
  "write standup", "daily report", or wants to prepare their daily standup
  content — even if they don't explicitly say "standup".
metadata:
  author: Polaris
  version: 1.5.1
---

# Standup — 每日站立會議報告產生器

自動從 git commits、JIRA 狀態變更、Google Calendar 會議收集昨日工作，合併去重後產出 YDY/TDT/BOS 格式的 standup 報告。使用者確認後推送至 Confluence 當月 Standup Meeting 頁面。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`confluence.space`、`github.org`、`jira.projects`（取得 project keys 用於 JQL）。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## Defaults

| 參數 | 預設值 | 說明 |
|------|--------|------|
| GitHub author | 動態取得 | `gh api user --jq '.login'` |
| GitHub org | `{config: github.org}` | 見 `references/shared-defaults.md` |
| Confluence space | `{config: confluence.space}` | 見 `references/shared-defaults.md` |
| Standup page | 當月頁面 | 動態搜尋 `YYYYMM Standup Meeting` |
| Timezone | Asia/Taipei (UTC+8) | |
| Known repos | 見 Step 2 | `{base_dir}/` 下的 git repos |

如果使用者沒有特別指定，直接用預設值執行，不需要額外確認。

## Workflow

### 1. Determine dates

根據 standup 呈現日（PRESENT_DATE）計算三個日期。注意三個概念的區別：

| 概念 | 說明 | 用途 |
|------|------|------|
| **PRESENT_DATE**（呈現日） | Standup 報告的日期，也是日期標題 `## YYYYMMDD` | 標題、TDT 會議來源 |
| **YDY_DATE**（YDY 活動日） | 收集 git/JIRA/Calendar 活動的日期 | YDY 工作項目 + 會議 |
| **TDT_PLAN_DATE**（TDT 規劃目標日） | TDT 工作項目規劃的目標日（下個工作日） | TDT 工作項目語境 |

> **標題永遠是 PRESENT_DATE**，不是 TDT_PLAN_DATE。週五 standup 標題是週五，不是下週一。

| 呈現日 | YDY_DATE | PRESENT_DATE（標題） | TDT_PLAN_DATE |
|--------|----------|---------------------|---------------|
| 週一 | 上週五 | 週一（今天） | 週一（今天） |
| 週二~四 | 昨天 | 今天 | 今天 |
| 週五 | 昨天（週四） | 週五（今天） | 下週一 |

週五特殊之處：標題和會議用 PRESENT_DATE（週五），但 TDT 工作項目是規劃下週一要做的事。

用 `date` 指令計算：

```bash
# 取得今天星期幾 (1=Mon, 5=Fri, 7=Sun)
DOW=$(date +%u)

# 計算三個日期
case $DOW in
  1) YDY_DATE=$(date -v-3d +%Y-%m-%d); PRESENT_DATE=$(date +%Y-%m-%d); TDT_PLAN_DATE=$(date +%Y-%m-%d) ;;
  5) YDY_DATE=$(date -v-1d +%Y-%m-%d); PRESENT_DATE=$(date +%Y-%m-%d); TDT_PLAN_DATE=$(date -v+3d +%Y-%m-%d) ;;
  *) YDY_DATE=$(date -v-1d +%Y-%m-%d); PRESENT_DATE=$(date +%Y-%m-%d); TDT_PLAN_DATE=$(date +%Y-%m-%d) ;;
esac
```

**使用者可以覆蓋日期**：如果使用者說「幫我寫昨天的 standup」或指定特定日期，以使用者指定為準。

### 2. Collect git activity (YDY source)

掃描 `{base_dir}/` 下所有 git repos，搜尋使用者在 YDY 日期的 commits：

```bash
MY_USER=$(gh api user --jq '.login')
```

對每個 repo 執行（平行多個 Bash tool call）：

```bash
git -C {base_dir}/<repo> log --author="$MY_USER" --since="$YDY_DATE 00:00 +0800" --until="$YDY_DATE 23:59 +0800" --oneline --no-merges 2>/dev/null
```

掃描的 repos：從 `{config: projects[].path}` 讀取清單（只掃 `{base_dir}/` 下有 `.git` 的目錄）。若 config 未設定，fallback 到 `ls {base_dir}/` 列出所有目錄後逐一檢查。

從 commit messages 中提取 ticket 號（對應 `{config: jira.projects[].key}` 的 pattern，如 `PROJ-\d+`）。記錄每個 ticket 對應的 repo 和 commit 摘要。

### 3. Collect JIRA activity (YDY source)

用 Atlassian MCP 搜尋使用者在 YDY 日期有更新的 tickets：

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  jql: assignee = currentUser() AND updated >= "YYYY-MM-DD" AND updated < "YYYY-MM-DD+1" AND project in ({config: jira.projects[].key}) ORDER BY updated DESC
  fields: ["summary", "status", "issuetype", "priority", "parent"]
  maxResults: 20
```

**回應過大處理**：JIRA 回傳可能超過 token 限制被存成檔案。此時用 Bash + python/jq 從檔案提取所需欄位（key、summary、status），不要嘗試 Read 整個檔案。

提取：ticket key、標題、當前狀態。這些資訊用於：
- 補充 git 沒抓到的 tickets（如只改了 JIRA 狀態沒 commit 的）
- 取得 ticket 標題（git commit message 不一定有）
- 作為 TDT 的 fallback 來源（見 Step 7）

### 4. Collect Google Calendar meetings (YDY + TDT source)

用 Google Calendar MCP 分別取得 **YDY_DATE** 和 **PRESENT_DATE** 的會議（平行兩個 tool call）：

> 注意：TDT 會議取的是 **PRESENT_DATE**（呈現日），不是 TDT_PLAN_DATE。週五 standup 的 TDT 會議是週五當天的會議，不是下週一的。

```
mcp__claude_ai_Google_Calendar__gcal_list_events
  timeMin: YYYY-MM-DDT00:00:00
  timeMax: YYYY-MM-DDT23:59:59
  timeZone: Asia/Taipei
  condenseEventDetails: false    ← 需要完整資訊（地點等）
```

- 過濾掉全天事件（`allDay: true`）
- YDY_DATE 的會議 → 放入 YDY 的「meeting」區塊
- PRESENT_DATE 的會議 → 放入 TDT 的「meeting」區塊
- 常見會議關鍵字對應：`standup`、`refinement`、`planning`、`retro`、`sprint review`、`1on1`

**會議資訊格式**（列完整資訊，每項用換行 + 縮排排列）：

```markdown
* 會議名稱
  M月 D日 (星期X) · 上午/下午H:MM - H:MM
  時區：Asia/Taipei
  地點：XXX（如果有 location 欄位）
```

**已知限制**：Google Calendar MCP 不回傳 `conferenceData`（Google Meet 連結、撥入電話號碼等），因此無法自動取得 Meet 連結。只列 MCP 回傳的欄位，不要猜測或捏造 Meet URL。

### 5. Merge & deduplicate YDY

合併三個來源，去重規則：
- 同一個 ticket 從 git + JIRA 都找到 → 合併為一行，以 JIRA 狀態為主、git commit 摘要為輔
- 按團隊分組（從 `{config: teams}` 讀取，每個 team 對應一組 `{config: jira.projects[].key}`）：
  - **{config: teams[0].name}**（Team A）：`{config: jira.projects[0].key}-*` tickets + 不帶 ticket 號的相關活動
  - **{config: teams[1].name}**（Team B）：`{config: jira.projects[1].key}-*` tickets
  - 若 config 有更多 teams，依序對應各自的 JIRA project key
- 每個 ticket 格式：`[TICKET-KEY ticket title](https://{config: jira.instance}/browse/TICKET-KEY) — 動作摘要`
- 「meeting」區塊：會議、非 ticket 工作（calendar events + 使用者口述的補充）

### 6. Plan vs Actual comparison

Compare today's YDY items against the previous day's TDT (planned tasks) to track planning accuracy. This gives the user visibility into what went as planned, what was unplanned work, and what planned work didn't happen.

**Prerequisite**: Fetch the current month's Confluence standup page content before this step (use the same search + get flow described in Step 10a/10b). If the page content was not yet fetched, fetch it now and cache the result for reuse in Step 10.

**Extract previous day's TDT**:
1. In the Confluence page content, find the most recent standup entry before today (look for the `## YYYYMMDD` heading closest to but before today's date)
2. Parse the `TDT – Today's Tasks` section from that entry
3. Extract each planned item: JIRA ticket key (e.g., `PROJ-123`, `TEAM-45`) and description

**Skip conditions** — skip this step entirely and proceed to Step 7 if:
- No previous standup entry exists on the page (first day of the month, after vacation, new page)
- The previous entry has no TDT section

**Comparison logic**:

For each YDY item that has a JIRA ticket key:
- If the ticket key matches a previous TDT item → append `` `✅ planned` `` to the YDY line
- If the ticket key is NOT in previous TDT → append `` `🟢 additional` `` to the YDY line

For each previous TDT item NOT found in today's YDY:
- Add it to the YDY list as: `🔴 loss: [reason]` — ask the user for the reason if it's not obvious (e.g., ticket was deprioritized, blocked, context-switched). If the user already mentioned it in conversation, use that context

For non-ticket items (meetings, generic descriptions like "refinement"):
- Match by keyword similarity (e.g., "refinement" in TDT matches "Refinement 會議" in YDY)
- **Calendar/meeting items are excluded from comparison** — they don't get plan vs actual annotations because meetings are externally scheduled and not "planned work" in the sprint sense

Present the annotated YDY to the user as part of the confirmation step (Step 9). The annotations help the user see their planning accuracy at a glance.

### 7. Collect TDT candidates

用 JIRA 搜尋使用者當前 sprint 的進行中 / 待處理工作：

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  jql: assignee = currentUser() AND status in ("IN DEVELOPMENT", "CODE REVIEW", "開放", "SA/SD", "待辦事項") AND project in ({config: jira.projects[].key}) AND sprint in openSprints() ORDER BY priority DESC
  fields: ["summary", "status", "issuetype", "priority"]
```

> **注意**：status 清單必須包含「待辦事項」，這是新 sprint 剛排入的 tickets 常見狀態。遺漏會導致 TDT 為空。

**Fallback（query 回傳 0 筆時）**：
1. 先從 Step 3 的 YDY JIRA 結果中，篩出 status 仍為進行中的 tickets（非「已釋出」「完成」「已關閉」）作為 TDT 候選
2. 如果仍然為空，主動詢問使用者「明天預計做什麼？」，不要靜默跳過 TDT 區塊

TDT 的排序邏輯：
1. **若 `{company}/.daily-triage.json` 存在且為今天或昨天的**：按 triage `rank` 排序 TDT，並附上進度燈號
2. 無 triage state 時 fallback：P0 / Highest priority 最前
3. 進行中（IN DEVELOPMENT）優先於待開始（開放 / 待辦事項）
4. 有依賴關係的標註 `↳ unblocks TICKET-KEY`

**Triage 連動**（有 `.daily-triage.json` 時）：

讀取 triage state，對每個 TDT 項目比對 triage 時的 `progress` 和今天的實際狀態：
- 實際進度超過 triage 預期 → 🟢 超前（例：triage 時 `in_dev`，今天已 `pr_open`）
- 實際進度 = 預期 → ⚪ 正常
- 實際進度落後（同狀態超過 2-3 天）→ 🔴 卡住

進度比較順序：`not_started` < `in_dev` < `pr_open` < `pr_blocked` < `pr_approved` < `pr_merged`

TDT 輸出範例（有 triage state 時）：
```
* **TDT – Today's Tasks**
  * 🟢 GT-483 [CWV] TTFB 優化 — PR approved, 待 merge（超前）
  * ⚪ GT-478 [CWV] JS Bundle 瘦身 — 開發中
  * ⚪ GT-495 [SEO] 首頁結構化資料 — 待估點
```

**Sprint context**：在 TDT 標題後附上 sprint 剩餘天數和剩餘點數（從 JIRA board 或使用者口述取得）。這是 nice-to-have，如果無法自動取得就跳過或問使用者。

### 8. Collect BOS (Blockers/Obstacles)

兩個來源：

**自動偵測**：
- JIRA 上 status = `DISCUSS` 的 tickets（使用者的）
- 從前幾天 standup 的 BOS 段落判斷是否有持續中的 blocker（讀 Confluence 現有內容）

**使用者輸入**：
- 詢問使用者是否有其他 blockers
- 使用者可能在對話開頭就口述了 blockers，記得納入

### 9. Format & present for confirmation

組合所有資料，依 `references/standup-template.md` 的模板格式呈現給使用者確認。產出前先 Read 模板確認格式規則。

**必須產出的四個區塊**（缺一不可）：
1. `* **YDY – Yesterday I Did**`
2. `* **TDT – Today's Tasks**`
3. `* **BOS – Blockers or Struggles**`
4. `* **口頭同步**` — 用 `_斜體_` 一段話總結 YDY 重點 + TDT 計畫 + BOS 摘要，放在 BOS 之後、`---` 分隔線之前

**口頭同步撰寫規則**：以第一人稱、口語化的方式寫一段 2-4 句話，涵蓋：昨天主要完成什麼（YDY 精華）、今天預計做什麼（TDT 重點）、有無 blocker。不是逐條複述，而是站會上會怎麼講就怎麼寫。

**格式規則**（詳見模板）：
- YDY 中有 parent Epic 的 ticket → 以 Epic 為最上層巢狀在團隊分組內
- `{config: jira.projects[0].key}-*` Epic → {config: teams[0].name}（Team A）；`{config: jira.projects[1].key}-*` Epic → {config: teams[1].name}（Team B）；無 JIRA → 自定義標題；會議 → meeting
- Sub-task 全部通過時折成一行 `（N/N 驗證子單通過）`，有失敗才展開
- TDT 也用 Epic 巢狀（與 YDY 一致）
- NO-JIRA 項目用一行摘要帶過

**資料來源**：Step 3 JIRA 查詢已包含 `parent` 欄位。對 YDY 中出現的每個 ticket：
1. 取得其 parent（Epic）key
2. 用 `getJiraIssue` 或 `searchJiraIssuesUsingJql`（`parent = EPIC-KEY`）取得同一 Epic 下所有 task 和 sub-task
3. 標註每個 task/sub-task 的狀態

**呈現後等待使用者確認或修改**。使用者可能會：
- 補充遺漏的工作項目
- 修改動作摘要的措辭
- 新增/移除某些項目
- 說「OK」或「推上去」表示確認

### 10. Push to Confluence

使用者確認後，將 standup 附加到當月 Confluence 頁面。

依 `references/confluence-page-update.md` 的完整流程（含版本衝突偵測）：

1. **搜尋當月頁面**：CQL `space = "{config: confluence.space}" AND title = "YYYYMM Standup Meeting" AND type = page`。找不到則告知使用者需先建立
2. **取得現有內容**：記錄 `version.number`
3. **版本衝突偵測**：更新前比對版本號，若已變動則重新取得最新內容
4. **附加新 standup**：在現有內容末尾附加（保持 `---` 分隔），`versionMessage: "Add standup YYYYMMDD"`

更新完成後告知使用者並附上 Confluence 頁面連結。

## Do

- 去重：同一 ticket 從多個來源找到時合併為一行
- 按團隊分組（依 `{config: teams}` 設定，預設 Team A / Team B）
- Ticket 用完整 Confluence link 格式：`[KEY title](URL)`
- TDT 優先排 P0 和進行中的 tickets
- 呈現後等使用者確認才推 Confluence
- 接受使用者口述補充到任何區塊
- 正確處理 Friday → Monday 日期邏輯
- 格式嚴格遵循現有 Confluence 頁面的 markdown 結構
- 產出前先 Read `references/standup-template.md` 確認格式規則
- Epic 巢狀收在團隊分組內（不另開 section），TDT 也用 Epic 巢狀
- Sub-task 全通過時折成一行，NO-JIRA 用一行摘要
- 口頭同步用 `_斜體_` 一併推上 Confluence

## Don't

- 不要未經使用者確認就推 Confluence
- 不要包含 merge commits（git log 用 `--no-merges`）
- 不要列其他團隊/專案的 tickets（除非使用者主動提到）
- 不要捏造活動 — 只報告資料來源找到的 + 使用者口述的
- 不要改變 Confluence 現有頁面的格式風格（新 entry 必須和舊 entry 風格一致）
- 不要在 BOS 區塊加「無」— 如果沒有 blockers 就只留標題
- 不要使用 `<custom data-type="smartlink">` tag — 用 markdown contentFormat 更新 Confluence 時，既有的 smart link（內嵌卡片）會被轉為普通連結，這是 Confluence API 的已知行為。統一用 `[TICKET-KEY title](URL)` markdown link 格式
- 不要猜測或捏造 Google Meet 連結 — Calendar MCP 不回傳 conferenceData，沒有就不列

## Prerequisites

- `gh` CLI 已認證
- Atlassian MCP 已連線（JIRA + Confluence）
- Google Calendar MCP 已連線
- 使用者的 repos 已 clone 到 `{base_dir}/` 下（base_dir 從 workspace-config.yaml 取得）
