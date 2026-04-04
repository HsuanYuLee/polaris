---
name: intake-triage
description: >
  批次收單排工：分析 PM 開出的一批 ticket，評估優先序，告訴 PM 哪些先做、哪些後做、哪些規格不足需補。
  產出 JIRA label + comment + Slack 摘要。
  觸發：「收單」、「排工」、「intake」、「這批單幫我看」、「PM 開了一堆單」、「幫我排優先」、
  「intake-triage」、「triage these tickets」、「prioritize this batch」。
  當使用者提供一批 ticket key 並要求排優先序時使用此 skill，不要與 /my-triage（個人每日盤點）混淆。
metadata:
  author: Polaris
  version: 2.0.0
---

# Intake Triage — PM 收單排工

批次分析 PM 開出的 ticket，產出優先序建議。核心價值：讓 PM 拿到一張清楚的「先做 / 後做 / 補規格」清單，附帶非技術語言的理由。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`jira.projects`、`slack.channels.ai_notifications`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

---

## Step 0：解析輸入

使用者可能用三種方式提供 ticket：

### A. Ticket key 清單（最常用）
從使用者訊息中擷取所有 `[A-Z]+-\d+` 格式的 key。

### B. JQL
使用者提供 JQL 字串，直接用於 Step 1 查詢。

### C. Slack URL
使用者貼 Slack 訊息連結，先用 `slack_read_thread` 讀取內容，再從中擷取 ticket key。

### D. Epic key
使用者提供一個 Epic key，展開其子單：
```
jql: parent = {EPIC_KEY} AND status not in (Done, Closed, Launched, 完成)
```

如果無法判斷輸入類型，直接問使用者。

同時從使用者訊息中偵測 **theme**（`seo` / `cwv` / `a11y` / `generic`）。
若未明確指定，從 ticket summary 關鍵字推斷（如含 SEO / 結構化資料 / Schema → `seo`）。
無法推斷時預設 `generic`。

---

## Step 1：批次撈取 ticket

用 Step 0 解析出的 key 或 JQL 查詢 JIRA：

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}
  jql: key in ({keys}) AND status not in (Done, Closed, Launched, 完成)
  fields: ["summary", "description", "status", "priority", "issuetype", "created",
           "customfield_10016", "issuelinks", "labels", "parent", "comment"]
  maxResults: 50
```

如果結果過大（> 15 張），委派 sub-agent 讀取並擷取結構化資料。

對每張 ticket 建立標準化記錄：
```
{ key, summary, description, ac, status, priority, issuetype, storyPoints,
  labels, linkedIssues, hasParent, parentKey, created }
```

### Epic + 子單收斂

同批 ticket 中如果同時出現 Epic 和它的子單，自動收斂：

1. **偵測**：掃描所有 ticket 的 `parent` 欄位，建立 `parentKey → [childKeys]` 映射
2. **收斂規則**：

| 情境 | 處理 |
|------|------|
| Epic + 子單都在批次中 | Epic 不參與 5 維度 scoring，改為**摘要行**：顯示子單數量、已估點數、整體進度。排序和判決只看子單 |
| 只有 Epic（子單不在批次中） | 正常分析 Epic 本身 |
| 只有子單（Epic 不在批次中） | 正常分析，在輸出時標註 `(← {parentKey})` |

3. **摘要行格式**（Step 5 中使用）：
```
📦 {EPIC_KEY} {summary}（{N} 張子單，{M} 張在本批）
   子單判決分佈：Do First {a} | Do Soon {b} | Do Later {c} | Skip {d}
```

摘要行放在其子單群組的最前面，作為分組標題。

---

## Step 2：平行 per-ticket 分析

每張 ticket 評估 5 個維度。ticket 數量 ≤ 5 時主 agent 直接分析；> 5 時委派 sub-agent（model: haiku）平行處理。

### 維度 1：Readiness（規格完整度）— 0 到 3 分

對照 `references/epic-template.md` § Readiness Checklist 的 3 個必要項：

| 必要項 | 檢查方式 | 有 = +1 |
|--------|---------|---------|
| 背景與目標 | description 中有說明「為什麼做」 | ✅ |
| AC | 有可驗收條件，至少 1 條明確的 | ✅ |
| Scope | 有列出影響範圍（頁面、元件、API） | ✅ |

分數解讀：
- 3 = 規格完整，可直接開工
- 2 = 堪用，有一個小缺口
- 1 = 勉強，缺關鍵資訊
- 0 = 無法開工

### 維度 2：Effort（工作量信號）— S / M / L / XL

**不做 codebase probe**（留給 /work-on 開工時做）。僅從 ticket 內容推斷：

| 信號 | Effort |
|------|--------|
| 單一頁面、單一元件、明確改動點 | S |
| 2-3 個頁面或元件、有條件邏輯 | M |
| 跨頁面、跨模組、需要新 composable 或 API 串接 | L |
| 架構變更、跨專案、需要 infra 配合 | XL |

如果 ticket 資訊太少無法判斷 → 標 `?`（會影響判決，見 Step 4）。

### 維度 3：Impact（業務影響）— Low / Med / High

依 theme 套用不同的 domain lens：

Domain lens 定義可來自兩個來源（優先順序）：

1. **workspace-config.yaml** 的 `intake_triage.lenses` 區塊（若存在）
2. **內建預設**（下方表格）

若 config 中定義了 lens，使用 config 版本（可能包含公司特定的高流量頁面名稱等）。
若未定義，使用以下內建預設：

**SEO lens：**
| High | 影響結構化資料、meta tags、canonical、或高流量核心頁面 |
| Med | 影響次要頁面或改善現有但非關鍵的 SEO 元素 |
| Low | 影響低流量頁面，或改善幅度有限 |

**CWV lens：**
| High | 影響目前不及格的 LCP / CLS / INP 頁面 |
| Med | 改善已及格但仍有空間的指標 |
| Low | 對 CWV 分數影響有限 |

**a11y lens：**
| High | 影響 WCAG 2.1 AA 不合規的主要流程 |
| Med | 改善次要流程或增強型無障礙 |
| Low | 美觀或偏好層面的改善 |

**generic：** 不調整，從 ticket 描述直接判斷業務價值。

**Config 範例**（可選，放在 workspace-config.yaml）：
```yaml
intake_triage:
  lenses:
    seo:
      high: "影響結構化資料、meta tags、canonical、高流量頁面（商品頁、首頁、目的地頁）"
      med: "影響次要頁面（category list、搜尋結果頁）"
      low: "影響低流量頁面"
    cwv:
      high: "影響目前不及格的 LCP/CLS/INP 頁面"
```

**混合 theme 批次**：當同批 ticket 跨多個 theme 時，per-ticket 各自套用對應的 lens。在輸出的每張 ticket 旁標注所用 lens（如 `[CWV]`、`[SEO]`），讓 RD 和 PM 知道 impact 評估的依據。

### 維度 4：Dependencies（前後依賴）

1. 讀 JIRA `issuelinks`（blocks / is-blocked-by）
2. 在同批 ticket 中，比對 summary 和 description：
   - 兩張 ticket 提到相同的元件/頁面/composable → 可能有順序依賴或 merge 衝突
   - 一張的產出是另一張的前提 → 邏輯依賴
3. 標記：`independent` / `blocker`（別人需要你先完成）/ `blocked`（你需要等別人）/ `conflict-risk`（同時做會衝突）

### 維度 5：Duplicate Risk（重複風險）

比對同批 ticket 的 summary + description：
- 兩張 ticket 的改動對象幾乎相同 → `Likely`（建議合併）
- 有部分重疊但各有獨立價值 → `Possible`（標注提醒）
- 無重疊 → `None`

---

## Step 3：硬限制檢查

在 scoring 之外，額外檢查是否有**做了反而有害**的情況：

| 硬限制 | 判斷依據 | 處理 |
|--------|---------|------|
| 資料不相容 | API 回傳的資料結構不支援 ticket 要求的呈現方式 | 標 `blocked-hard`，不進判決 |
| 畫面高度特化 | 改動只適用特定情境但會影響通用流程 | 標 `blocked-hard`，說明風險 |
| 做了反而有問題 | 例如移除某 meta tag 會讓 Google 誤判 | 標 `blocked-hard`，說明原因 |

硬限制的判斷來自 ticket 描述的資訊。如果資訊不足以判斷 → 不標硬限制（寧可放行再由 /work-on 階段發現）。

被標 `blocked-hard` 的 ticket 不進入 Step 4 排序，直接歸入判決表的「硬限制」區塊。

---

## Step 4：計算判決

### 判決矩陣

| Readiness | Effort | Impact | → Verdict |
|-----------|--------|--------|-----------|
| 3 | S / M | High | **Do First** |
| 3 | S / M | Med | Do Soon |
| 3 | S / M | Low | Do Soon |
| 2–3 | L | High | Do Soon（需先估點） |
| 2–3 | L / XL | Med / Low | Do Later |
| 0–1 | any | any | **Skip**（規格不足） |
| any | any | duplicate Likely | **Skip**（建議合併） |
| any | ? | any | Do Later（資訊不足，無法判斷 effort） |

### 排序規則

1. **Do First 上限 3 張**。超過時，比較 Impact（High 優先）→ Effort（小的優先）→ created（早的優先），降最低的到 Do Soon
2. 同一 verdict 內，按 Impact DESC → Effort ASC → created ASC 排序
3. 依賴調整：如果 A 是 B 的 blocker 且 A 的 verdict 低於 B → 提升 A 到與 B 同級

### 產出判決清單

每張 ticket 的判決記錄：
```
{
  key, summary, verdict: "do-first" | "do-soon" | "do-later" | "skip" | "blocked-hard",
  readiness: 0-3, effort: "S"|"M"|"L"|"XL"|"?", impact: "Low"|"Med"|"High",
  dependencies: [...], duplicateRisk: "None"|"Possible"|"Likely",
  reason_rd: "...",      // RD 看的技術理由
  reason_pm: "...",      // PM 看的非技術理由
  questions: [...]       // Skip 時需要 PM 回答的問題
}
```

---

## Step 5：判決表（等使用者確認）

呈現判決表給 RD 確認：

```
══════════════════════════════════════════════════════
📋 Intake Triage — {theme} Batch — {date}
══════════════════════════════════════════════════════
Batch: {N} 張 | Do First: {n1} | Do Soon: {n2} | Do Later: {n3} | Skip: {n4} | 硬限制: {n5}

⚡ Do First（規格清楚、影響大、可立即開始）
 1. {KEY} {summary}    ✅✅✅  {effort}  ↑↑↑  [{lens}]
    「{reason_pm}」

📋 Do Soon（這個或下個 sprint）
  📦 {EPIC_KEY} {epic_summary}（{N} 張子單，{M} 張在本批）
     子單判決分佈：Do First 0 | Do Soon 3 | Do Later 2 | Skip 0
  2. {KEY} {summary}    ✅✅☐  {effort}  ↑↑  [{lens}]
     「{reason_pm}」
  3. {KEY} {summary}    ✅✅✅  {effort}  ↑↑  [{lens}]
     「{reason_pm}」
 ...

⏳ Do Later（不急）
 N. {KEY} {summary}    ✅☐☐  {effort}  ↑   [{lens}]
    「{reason_pm}」

❌ Skip（規格不足，需 PM 補）
 4. {KEY} {summary}    ☐☐☐  ?  ?
    「{reason_pm}」
    需要補：{questions}

🚫 硬限制（做了反而有問題）
 5. {KEY} {summary}
    「{reason_pm}」

依賴順序：{dependency chain}
重複風險：{duplicate pairs}
══════════════════════════════════════════════════════
```

**Readiness 視覺化**：`✅` = 有、`☐` = 缺（共 3 格，對應 3 個必要項）
**Impact 視覺化**：`↑↑↑` = High、`↑↑` = Med、`↑` = Low
**Lens 標記**：`[CWV]`、`[SEO]`、`[a11y]`、`[generic]` — 標注該 ticket 的 Impact 評估依據
**全域 rank**：所有 ticket 使用連續編號（1, 2, 3...），跨 verdict 類別不重新計數。這個數字就是建議的執行順序
**Epic 摘要行**：以 `📦` 開頭，不佔 rank 編號，作為子單群組的分組標題

RD 可以：
- 確認（`y`）→ 進入 Step 6
- 調整任何 ticket 的 verdict → 重新排序後再確認
- 跳過寫入（`skip writes`）→ 只看表，不寫 JIRA

---

## Step 6：JIRA 寫回

RD 確認後，對每張 ticket 寫入 JIRA。ticket 數量 > 5 時委派 sub-agent（model: haiku）平行處理。

### 6a. Label

移除該 ticket 上所有 `intake-` 開頭的舊 label，加上新 label：

| Verdict | Label |
|---------|-------|
| Do First | `intake-do-first` |
| Do Soon | `intake-do-soon` |
| Do Later | `intake-do-later` |
| Skip | `intake-skip` |
| 硬限制 | `intake-blocked` |

### 6b. 需求分析 Comment

每張 ticket 加一個 comment，格式：

```markdown
## 收單分析 — {date}

**判決：{verdict}**
**排序理由：** {reason_rd}

### 評估
- Readiness: {score}/3（{缺什麼}）
- Effort: {S/M/L/XL}（{依據}）
- Impact: {Low/Med/High}（{依據}）

### 依賴
{dependency list or "無"}

### 硬限制檢查
- [x] 資料來源可用
- [x] 不影響現有功能
- [ ] ⚠️ {如有疑慮}

{如果是 Skip，加上：}
### 需要 PM 補充
- [ ] {question 1}
- [ ] {question 2}
```

這個 comment 是**方向指引**，不是執行 spec。不寫檔案路徑或 code-level 細節（那是 /work-on 開工時才做的事）。目的是讓未來的 /work-on 省掉「理解需求」的時間，直接進入 codebase 分析。

### 6c. Skip ticket 額外處理

對 Skip 的 ticket，comment 中的「需要 PM 補充」區塊即為 PM 的 action item。不額外 tag PM（由 Step 7 的 Slack 摘要統一通知）。

---

## Step 7：PM 摘要 + 發送

自動產出非技術語言的 Slack 摘要。先呈現給 RD 審閱，RD 確認後發送。

### 摘要格式

```
📋 {theme} 收單分析 — {date}

這批 {N} 張單我看完了，優先序建議如下：

⚡ 馬上做（這個 sprint）
• {KEY} {summary}：{reason_pm}
• {KEY} {summary}：{reason_pm}

📋 之後做
• {KEY} {summary}：{reason_pm}

❌ 需要補規格
• {KEY} {summary}：{reason_pm}
  → 需要補：{questions 簡述}

🚫 建議不做
• {KEY} {summary}：{reason_pm}

📌 順序提醒
{dependency chain 的白話說明}

有問題再找我討論！
```

### 發送

問 RD：「要發到哪裡？」

選項：
- Slack channel（預設用 config 的 `slack.channels.ai_notifications`）
- Slack DM（問 RD 要 PM 的名字，用 `slack_search_users` 找到後 DM）
- 不發（RD 自己轉發）

---

## Do / Don't

- Do: Step 2 分析 > 5 張時委派 sub-agent 平行處理
- Do: 硬限制檢查要保守 — 只在 ticket 明確描述了不相容情況時才標
- Do: PM 理由用非技術語言，避免提及程式碼、元件名
- Do: 同批內偵測 duplicate risk，避免 PM 重複開單
- Do: comment 定位為「方向指引」，不寫檔案路徑
- Don't: 不做 codebase probe — 留給 /work-on
- Don't: 不自動修改 ticket status — 只加 label + comment
- Don't: 不替代 /refinement — refinement 是深入補完規格，intake-triage 是快速排序
- Don't: 不替代 /my-triage — my-triage 是個人每日盤點，intake-triage 是批次收單排工
- Don't: 不替代 /sprint-planning — sprint-planning 是團隊級 sprint 規劃，intake-triage 是需求排序

---

## 與既有工作流的銜接

```
PM 開單 → /intake-triage → 判決 + label + comment
                              ├─ Do First → /my-triage 讀取 label → /work-on 開工
                              ├─ Do Soon → 下個 sprint /sprint-planning 會撈到
                              ├─ Do Later → backlog
                              ├─ Skip → PM 補完後重新 /intake-triage 或 /refinement
                              └─ 硬限制 → 不做，已記錄原因
```

`intake-` label 與 `refinement-ready` / `needs-refinement` label 正交：
一張 ticket 可以同時是 `intake-do-first` + `needs-refinement`。

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0 | 2026-04-03 | 通用化：從 kkday 專屬搬到 shared skills，domain lens 改為 config-driven + 內建預設，author → Polaris |
| 1.1.0 | 2026-04-03 | Epic + 子單收斂邏輯、混合 theme lens 標注、全域 rank 編號 |
| 1.0.0 | 2026-04-03 | Initial release — Phase A（label + comment + Slack，不含 execution queue） |


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
