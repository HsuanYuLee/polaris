---
name: scope-challenge
description: >
  Lightweight planning gate that challenges the scope and assumptions of a JIRA ticket before
  estimation begins. Reads ticket content, checks completeness, proposes 2-3 alternative approaches
  with tradeoffs, and recommends whether to proceed as-is, simplify, split, or request more info.
  Advisory only — does not block.
  Use when: (1) user says "scope challenge", "挑戰需求", "challenge requirements",
  "challenge scope", "需求質疑", "question requirements", "scope review", "review scope",
  "需求合理性", "requirement reasonableness",
  (2) invoked by work-on or epic-breakdown before estimation,
  (3) user wants to validate whether a ticket's scope is reasonable before committing effort.
metadata:
  author: Polaris
  version: 1.1.0
---

# Scope Challenge — 需求質疑

在估點前快速檢視 JIRA ticket，挑戰 scope 合理性，提出替代方案。

## 1. 讀取 Ticket

用 `getJiraIssue` 取得 ticket 內容，擷取：
- Summary、Description、AC（Acceptance Criteria）
- Issue type（Epic / Story / Task / Bug）
- 已有的子單（若為 Epic）
- Linked issues、attachments、comments

## 2. 完整性檢查

逐項檢查，缺少的標記 ❌：

| 項目 | 檢查方式 |
|------|----------|
| Acceptance Criteria | description 中有明確的 AC 或驗收條件 |
| 開發路徑（path） | description 中指明哪個專案 / 目錄 |
| Figma 連結 | description 或 attachment 中有 figma.com URL |
| API 文件 | description 中有 API endpoint 說明或 Swagger/Postman 連結 |
| 影響範圍 | 明確說明改動涉及哪些頁面 / 流程 |

缺少 ≥2 項 → 建議補齊後再估點。

## 3. Scope 挑戰

對 ticket 提出以下質疑（只列出適用的）：

**過大？**
- 單張 Story/Task 涵蓋 >3 個獨立功能 → 建議拆分
- Epic 的子任務彼此無明確邊界 → 建議重新定義 scope

**過度設計？**
- 能用既有元件解決但描述中要求從零建造
- 要求通用化但目前只有一個使用場景

**隱藏假設？**（用自適應 Explore 驗證）
- 假設 API 已存在但未驗證
- 假設 Design System 有對應元件但未確認
- 假設不需要 migration 但實際可能需要

> 當 ticket 有明確的專案路徑且列出了具體假設時，啟動 1 個 Explore subagent（參考 `references/explore-pattern.md`）快速驗證：grep API endpoint 是否存在、元件是否支援所需 props、是否有 migration 相關程式碼。探索目標：驗證 ticket 中的隱藏假設是否成立。若專案路徑不明或無具體假設可驗證，跳過此步驟。

**80/20 簡化？**
- 是否有更小的改動能達成 80% 的效果
- 是否能先 hardcode 再逐步抽象

## 4. 替代方案

提出 2-3 個做法，格式：

```
### 方案 A：照原 spec 做（原始 scope）
- 預估複雜度：HIGH
- 優點：完整滿足需求
- 風險：開發時間長、可能延期

### 方案 B：簡化版（80/20）
- 預估複雜度：MEDIUM
- 優點：快速交付核心價值
- 取捨：省略 XX 功能，後續再補

### 方案 C：拆分（分階段）
- 預估複雜度：每階段 LOW-MEDIUM
- 優點：可漸進交付、降低風險
- 取捨：需要多張 ticket 管理
```

只列有意義的替代方案。如果原 scope 已經合理簡潔，說明原因並建議直接進入估點。

## 5. 輸出建議

```
📋 Scope Challenge Report — {TICKET-KEY}

完整性：✅ AC ✅ Path ❌ Figma ✅ API
建議：{proceed / simplify / split / needs-more-info}

{替代方案表格}

→ 建議採用方案 {X}，原因：{一句話}
```

詢問使用者選擇後，繼續後續流程（估點 / 拆單）。使用者也可以選擇跳過，直接進入估點。

## 6. 拆單審查模式（由 epic-breakdown invoke）

當由 `epic-breakdown` Step 7.5 自動 invoke 時，輸入是**拆單結果表格**而非 JIRA ticket。此模式跳過 Step 1-2，直接進行拆單品質審查。

### 審查項目

對每張子單逐一檢查，標記 PASS / FAIL：

| 項目 | PASS 條件 | FAIL 時的建議 |
|------|----------|-------------|
| 點數合理 | <= 5 點 | 拆成更小的子單 |
| AC 明確 | 有具體的驗收條件 | 補上 AC |
| Happy Flow | 有使用者視角的操作步驟 | 補上 Happy Flow |
| 獨立可測 | 可獨立開發、獨立驗收 | 合併到相關子單或重新劃分邊界 |
| 無循環依賴 | 子單之間無環形相依 | 調整依賴方向或合併 |
| 無隱藏假設 | 不依賴未驗證的 API / 元件 | 標明假設或加 Spike 子單 |

### 輸出格式

```
🔍 Scope Challenge — 拆單審查

| # | 子單 | Points | AC | Happy Flow | 獨立可測 | 結果 |
|---|------|--------|----|------------|---------|------|
| 1 | ... | ✅ 3pt | ✅ | ✅ | ✅ | PASS |
| 2 | ... | ❌ 8pt | ✅ | ❌ | ✅ | FAIL |

FAIL 項目：
- #2：8 點過大，建議拆為「API handler」(3pt) + 「前端串接」(5pt)
- #2：缺少 Happy Flow

結論：FAIL（2 項需調整）
```

回傳結構化結果讓 `epic-breakdown` 可自動處理。

## Do / Don't

- Do: 質疑時附上具體理由，不要泛泛而談
- Do: 方案要可執行，不是空泛建議
- Do: PM 描述不清時主動列出缺少項目
- Do: 拆單審查模式下，FAIL 必須附帶可執行的修正建議（怎麼拆 / 怎麼補）
- Don't: 阻擋流程 — 使用者說「跳過」就跳過
- Don't: 質疑所有 ticket — 小改動（≤2 files, 明確 AC）直接說「scope 合理，建議直接估點」
- Don't: 替代方案超過 3 個 — 選擇太多反而拖慢決策
- Don't: 拆單審查模式下提出替代方案（Step 4）— 此時只審查拆單品質，不質疑整體 scope
