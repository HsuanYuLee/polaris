---
name: refinement
description: >
  Iteratively enriches incomplete JIRA Epics into estimation-ready specs. Four modes:
  batch readiness scan, RD discovery (Phase 0), PM elaboration (Phase 1), approach
  discussion (Phase 2). Trigger: "refinement", "grooming", "討論需求", "需求釐清",
  "補完 Epic", "這張單缺什麼", "brainstorm", "方案討論", "想重構", "tech debt",
  "batch refinement", "sprint prep", or Epic with sparse content needing enrichment.
metadata:
  author: Polaris
  version: 3.1.0
---

# Backlog Refinement — 發現問題、充實需求、討論做法

四種模式，一個目標：產出可以估點拆單的完整需求。

## 模式總覽

| 模式 | 核心問題 | 入口 | 輸入 | 輸出 |
|------|---------|------|------|------|
| **Batch Scan** | 這些 Epic 準備好了嗎？ | 多張 Epic keys | Epic keys 清單 | 完整度總覽表 + JIRA label + comment |
| **Phase 0：發現 & 開單** | 為什麼要做？值不值得？ | RD 主動發起 | code smell / 效能問題 / tech debt | JIRA ticket + 問題分析 + 影響評估 |
| **Phase 1：需求充實** | 這張單到底要做什麼？ | PM 開的粗略 Epic | Epic 標題 + PM 的零散描述 | 完整的 Epic（AC、scope、edge cases） |
| **Phase 2：方案討論** | 怎麼做比較好？ | 需求已明確 | 完整的 Epic / ticket | Decision Record（選定方案 + trade-offs） |

**Batch Scan** 適合 sprint planning 前一次掃描多張 Epic，快速分流哪些可以排、哪些要先補充。
**Phase 0** 是 RD 主動發起的（重構、優化、tech debt），產出 JIRA ticket 後可以接 Phase 2。
**Phase 1** 是 PM 發起的，Epic 不完整需要充實。
**Phase 2** 是需求明確後的做法討論，任何來源都可以進入。

各模式可以獨立使用，也可以串接（Batch Scan → 挑出 needs-refinement 的 → Phase 1 深度補充）。

---

## Batch Scan：批次完整度掃描

適用於 sprint planning 前，一次掃描多張 Epic 的 readiness。

### 觸發場景

- 「幫我看這幾張 Epic 準備好了嗎：PROJ-481 PROJ-500 PROJ-510」
- 「sprint 準備，掃一下這些單」
- 「批次 refinement」
- 提供多個 Epic key + 任何與 refinement/readiness/完整度相關的意圖

### 1. 平行讀取所有 Epic

用 **sub-agent 平行**（`model: "haiku"` — 純 JIRA 讀取 + checklist 比對）對每張 Epic 執行：
1. `getJiraIssue` 讀取 Summary、Description、Comments、Labels
2. 根據 `references/project-mapping.md` 確認對應專案
3. 對照 Readiness Checklist（`references/epic-template.md`）逐項檢查

> 每個 sub-agent 獨立完成一張 Epic 的 readiness check，回傳結構化結果。

### 2. 彙整總覽表

所有 sub-agent 回報後，彙整為總覽表呈現給使用者：

```
## Refinement Readiness — Sprint 準備掃描

| # | Epic | Summary | 完整度 | 狀態 | 缺項 | 建議 |
|---|------|---------|--------|------|------|------|
| 1 | PROJ-481 | [feature] i18n key 減量... | 8/8 | ✅ Ready | — | → breakdown |
| 2 | PROJ-500 | [web] 商品頁重構... | 3/8 | ❌ Needs work | AC, Scope, Figma | → Phase 1 深度 refinement |
| 3 | PROJ-510 | [DS] Button 元件優化 | 6/8 | ⚠️ Almost | 依賴, Edge cases | → 快速補充後可排 |

✅ Ready: 2 張（可直接排入 sprint）
❌ Needs work: 1 張（需深度 refinement）
```

### 3. 更新 JIRA Label + Comment

使用者確認總覽表後，對每張 Epic 更新：

**Label**（用於 JQL 篩選，sprint-planning 可直接利用）：
- 完整度達標（必要項 1-3 全有）→ 加 `refinement-ready`，移除 `needs-refinement`（如有）
- 完整度不足 → 加 `needs-refinement`，移除 `refinement-ready`（如有）

**Comment**（詳細 checklist）：

```
mcp__claude_ai_Atlassian__addCommentToJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: <EPIC_KEY>
  body: |
    ## Refinement Readiness Check — [日期]

    | # | 項目 | 狀態 | 備註 |
    |---|------|------|------|
    | 1 | 背景與目標 | ✅ | — |
    | 2 | AC | ❌ | 缺 Acceptance Criteria |
    | 3 | Scope | ⚠️ | 有但缺 out of scope |
    | 4 | Figma | ✅ | 有連結 |
    | 5 | API 文件 | N/A | 無 API 串接 |
    | 6 | Edge cases | ❌ | 未提及 |
    | 7 | 依賴 | ✅ | 已列出 |
    | 8 | Baseline | N/A | 非效能類 |

    **完整度：5/8**
    **建議：** 補充 AC（至少 3 條可驗收條件）和 Scope（列出 out of scope）後可進拆單。
  contentFormat: markdown
```

### 4. 引導下一步

總覽表呈現後，詢問使用者：

- 「哪幾張要深入 refine？」→ 逐張進入 Phase 1
- 「Ready 的要直接拆單嗎？」→ 觸發 `epic-breakdown`
- 「全部看完了，準備 planning」→ 觸發 `sprint-planning`

> Batch Scan 只做完整度檢查 + 標記，不做深度 refinement。需要深度補充的 Epic 逐張進 Phase 1。

---

## Phase 0：發現 & 開單（RD 主動發起）

RD 在開發過程中發現問題（code smell、效能瓶頸、tech debt、架構不合理），想研究是否值得投入時間改善。

### 觸發場景

- 「這段 code 寫得很亂，想研究一下怎麼重構」
- 「這個頁面載入很慢，想查一下原因」
- 「這個 composable 被 5 個頁面用到但沒有測試」
- 「想重構」、「tech debt」、「效能不好」

### 1. 問題分析（自適應 Explore）

使用 `references/explore-pattern.md` 的自適應探索模式掃描 codebase。

**探索目標**：分析指定模組的引用關係、測試覆蓋、程式碼品質。

啟動 1 個 Explore subagent，帶入使用者指定的程式碼/模組路徑和問題描述。Subagent 會自行判斷範圍大小 — 單一模組直接探索，跨多模組自動分裂。

**收到探索摘要後**，主 agent 彙整產出結構化的問題分析：

```
── 問題分析 ─────────────────────────────
📍 位置：src/composables/useFeature.ts
📊 被引用：12 個檔案（5 頁面 + 7 元件）

問題：
1. 沒有 error handling — API 失敗時整個頁面 crash
2. 沒有 cache — 每次切換 tab 都重新 fetch
3. 沒有測試 — 0% coverage，改了怕壞
4. 混合了 fetching + formatting + caching 邏輯（SRP 違反）

影響：
- 使用者體驗：切 tab 閃一下（重新 fetch）
- 穩定性：API 不穩時商品頁白屏
- 維護性：任何改動都可能影響 12 個使用者
```

### 2. 影響評估（說服 PM / QA 用）

產出一份讓非技術人員能理解的影響評估：

```
── 影響評估 ─────────────────────────────
問題嚴重度：🟡 Medium（目前沒壞，但風險高）

不修的風險：
- API 不穩時商品頁會白屏（影響營收）
- 每次改 price 相關邏輯都要祈禱不壞其他頁面
- 新人接手這段 code 會非常痛苦

修了的好處：
- 商品頁 API 錯誤有 graceful fallback（不再白屏）
- 頁面切換更快（cache 減少重複 fetch）
- 有測試保護，未來改動更安全

建議投入：3-5 pts（≈ 1-2 天）
ROI 評估：高 — 影響範圍大（12 個檔案）、投入小
```

### 3. 產出 JIRA ticket 草稿

```
── JIRA Ticket 草稿 ────────────────────
Type:     Story（或 Task / Tech Debt — 依團隊慣例）
Summary:  [proj] 重構 useFeature composable — 加入 error handling、cache、測試
Priority: Medium

Description:
## 背景
useFeature composable 被 12 個檔案引用，但缺乏 error handling、cache 和測試。
API 不穩時會導致商品頁白屏。

## 目標
- 加入 error handling（API 錯誤 → graceful fallback）
- 加入 cache（避免重複 fetch）
- 補測試（目標 coverage ≥ 80%）
- 拆分 SRP（fetching / formatting / caching 分離）

## AC
1. API 回應 error → 頁面顯示上次快取的價格 + 錯誤提示
2. 60 秒內的重複請求走 cache
3. useFeature 測試覆蓋率 ≥ 80%
4. 拆為 useFeatureFetch + useFeatureFormat

## Scope
- 修改：composables/useFeature.ts
- 新增：composables/useFeature.test.ts
- 影響：需確認 12 個使用者不受影響

## QA 影響範圍
- 商品頁價格顯示（正常 + API error）
- 所有使用 useFeature 的頁面
```

### 4. 確認 & 開單

RD 確認草稿後：
1. 用 `createJiraIssue` 建立 JIRA ticket
2. 設定 `需求來源` = `Tech - maintain`（重構）或 `Tech - bug`（效能問題）
3. 建議下一步：
   - 簡單的 → 直接 Phase 2 討論做法 → 估點 → 開工
   - 複雜的 → Phase 2 討論做法 → SA/SD → 拆子單

---

## Phase 1：需求充實（做什麼）

### 1. 讀取 Epic 現況 + Codebase 探索（自適應 Explore）

從 JIRA 讀取 Epic 的所有資訊：Summary、Description、AC、Comments、Linked Issues、Figma link。

同時根據 `references/project-mapping.md` 確認對應的專案。確認專案路徑後，使用 `references/explore-pattern.md` 的自適應探索模式掃描 codebase 建立技術 context。

**探索目標**：找出與 Epic 需求相關的現有實作，產出 scope 和 edge cases 建議。

啟動 1 個 Explore subagent，帶入 Epic 需求摘要和專案路徑。Subagent 會自行判斷範圍大小 — 小需求直接探索，大需求自動分裂成多個 sub-Explore 平行處理。

**收到探索摘要後**，主 agent 彙整進入 Step 2。不要再額外讀取原始碼。若某個面向資訊不足，針對性地追加單一 Explore subagent 補充，不要回到全面掃描。

### 2. 完整性檢查

對照以下 checklist 逐項檢查，標出有/缺/模糊：

```
── Epic 完整性檢查 ──────────────────────
✅ 標題      明確描述功能目標
⚠️ 背景      有提到原因，但缺使用者痛點或商業目標
❌ AC        沒有 Acceptance Criteria
⚠️ Scope     提到了「商品頁」但沒列出具體哪些頁面/元件
❌ Edge cases 沒有提到錯誤處理、空狀態、多語系
✅ Figma     有連結
❌ API       沒有 API 文件或端點資訊
⚠️ 依賴      提到「需要後端配合」但沒有具體 ticket
── 完整度：3/8（不足以估點）────────────
```

**完整的 Epic 應包含：**

| 項目 | 說明 | 範例 |
|------|------|------|
| **背景 & 目標** | 為什麼做這個？解決什麼問題？ | 「旅客在商品頁找不到出發日的價格，導致跳出率高」 |
| **AC（Acceptance Criteria）** | 可驗收的條件，一條一條列 | 「使用者選擇日期後，價格區塊即時更新顯示該日價格」 |
| **Scope（影響範圍）** | 涉及哪些頁面、元件、API | 「某頁面 FeatureSection 元件 + /api/feature endpoint」 |
| **Edge cases** | 異常情境怎麼處理 | 「無價格 → 顯示『價格洽詢』；API timeout → skeleton + retry」 |
| **Figma / 設計稿** | 視覺目標 | Figma link |
| **API 文件** | 資料來源與格式 | Swagger link 或 endpoint + response shape |
| **依賴** | 需要其他團隊或其他單先完成的 | 「依賴 BE-1234 API 上線」 |
| **不做什麼（Out of scope）** | 明確排除的項目 | 「本次不處理多幣別切換」 |

### 3. 產出補充建議

針對每個缺失項，AI 基於 codebase 研究產出**建議草稿**，不是空白問題：

```
── 建議補充內容 ─────────────────────────

📝 AC（建議草稿，請 RD 確認後跟 PM 對齊）：
1. 使用者進入商品頁 → 價格區塊顯示預設日期（最近可出發日）的價格
2. 使用者切換日期 → 價格即時更新，不需重新載入頁面
3. 該日無價格 → 顯示「價格洽詢」+ 聯繫客服按鈕
4. API 回應 > 3 秒 → 顯示 skeleton loading
5. 多幣別 → 依使用者設定的幣別顯示（沿用現有 useCurrency composable）  ← 替換為專案實際的 composable

📝 Scope（根據 codebase 分析）：
- 修改：src/pages/feature/[id]/_components/FeatureSection.vue
- 修改：src/composables/useFeature.ts
- 新增：server/api/product/price.get.ts（如果 BFF 需要）
- 影響：Design System 的 FeatureComp 元件可能需要支援 loading state

📝 Edge cases（根據現有程式碼推測）：
- 目前 FeatureSection 沒有 error handling，需要加
- useFeature 目前只拉一次資料，切換日期需要改成 reactive

📝 依賴：
- 需確認 /api/product/price 是否已上線（目前 codebase 中沒有這個 endpoint）
- FeatureComp 元件是否需要改？如果需要，要先開 DS 的單

── 需要 PM 回答的問題 ──────────────────
❓ 多幣別切換是否在本次 scope 內？
❓ 「價格洽詢」的 CTA 導向哪裡？（客服表單 / LINE / 電話）
❓ 是否有 A/B test 計畫？需要 feature flag 嗎？
```

### 4. 寫回 JIRA

RD 確認建議內容後（可以調整），以 **JIRA comment** 寫回 Epic：

```
## Refinement 建議 — [日期]

### AC（草稿，待 PM 確認）
1. ...
2. ...

### Scope
- ...

### Edge Cases
- ...

### 待 PM 回答
- [ ] 多幣別切換是否在 scope 內？
- [ ] ...
```

**用 comment 而不是直接改 description**，原因：
- 保留 PM 原始描述，不覆蓋
- PM 可以在 comment 下回覆，形成討論串
- 多輪 refinement 有完整歷史

### 5. 多輪迭代

PM 回覆後，下一次對話再跑 refinement：
1. 讀取 JIRA Epic + 所有 comments（包含上一輪的建議和 PM 回覆）
2. 重新跑完整性檢查 — 這次應該更多 ✅
3. 針對仍然不足的部分產出新建議
4. 重複直到完整度足夠

**判斷「夠了」的標準：**
- AC ≥ 3 條且可驗收
- Scope 明確到可以列出受影響的檔案/元件
- Edge cases 至少覆蓋：空狀態、錯誤狀態、loading 狀態
- 依賴已釐清（有對應 ticket 或確認不需要）

完整度達標後：

### 6. 整合母單描述

多輪 refinement 結束後，散落在 comments 中的資訊應整合為結構化 Epic description。用 `editJiraIssue` 更新母單 description：

> 結構化格式參考：`references/epic-template.md`

**注意**：整合時保留 PM 的原始意圖，加入 refinement 過程中補充的 AC、Scope、Edge Cases 等。Comments 歷史仍保留做討論紀錄，但 description 是「最終版需求文件」。

整合完成後，**更新 JIRA Label**：
- 加 `refinement-ready`，移除 `needs-refinement`（如有）
- 這讓 Batch Scan 和 sprint-planning 能用 JQL 篩選已就緒的 Epic

建議下一步：

```
── Epic 完整度：7/8（可以進估點）────────
✅ Description 已整合為結構化格式
✅ Label: refinement-ready
建議下一步：
  → epic-breakdown（拆子單 + 估點）
  → jira-estimation（單張估點）
```

---

## Phase 2：方案討論（怎麼做）

Epic 內容完整後，如果做法不明確（多種實作路徑、架構選擇），進入方案討論。

### 適用場景

- 預估 > 8 點的 Epic
- 涉及跨專案改動（design-system + main-repo）
- 技術選型有多個選項（用現有元件 vs 新建）
- RD 主動問「這張怎麼做比較好」

### 流程

1. **產出 2-3 種方案**，每個附：

```
── Option A: 擴展現有元件 ──────────────
Approach:  修改 FeatureComp 元件，加入 loading/error state
Pros:      複用現有元件，改動範圍小
Cons:      FeatureComp 已經很複雜，再加 state 可能過載
Effort:    M（3-5 pts）
Affects:   <design-system> + <your-repo>
Risk:      DS 改動需要先 merge 才能在 main-repo 用
```

2. **比較矩陣** + 推薦，但由 RD 決定

3. **產出 Decision Record** → 寫回 JIRA comment：

```
## Decision Record — [日期]

**Decision**: Option A — 擴展 FeatureComp 元件
**Reason**: 複用性高，長期維護成本低
**Key decisions**:
- 用 Intl.NumberFormat（不自己寫 formatting）
- SSR render 價格（SEO）
**Open questions**:
- [ ] DS 的 PR 能否在本 sprint 內 merge？
```

---

## Skill Chain

```
refinement
  ├─ Batch Scan 完成
  │   ├─ refinement-ready → epic-breakdown / sprint-planning
  │   └─ needs-refinement → Phase 1 逐張深度補充
  │
  ├─ Phase 0 完成（開單）
  │   → Phase 2（討論做法）→ jira-estimation → work-on
  │
  ├─ Phase 1 完成（Epic 充實 + label: refinement-ready）
  │   → epic-breakdown（拆子單）
  │   → jira-estimation（估點）
  │
  └─ Phase 2 完成（方案確定）
      → sasd-review（複雜需求產出 SA/SD）
      → work-on（直接開工）
```

## Do / Don't

- Do: 用 codebase 分析產出具體建議，不要列空白問題讓 RD 自己填
- Do: 討論過程中寫回 JIRA comment（保留討論歷史），完整度達標後整合到 description
- Do: 每次 refinement 開始時先讀 JIRA comments，接續上一輪進度
- Do: 標出「需要 PM 回答」和「RD 可以自己決定」的問題
- Do: 完整度達標時主動建議進入估點/拆單
- Do: Phase 0 的影響評估用非技術語言寫，讓 PM/QA 能理解
- Do: Phase 0 開單時設定正確的 `需求來源`（Tech - maintain / Tech - bug）
- Don't: 替 PM 決定需求 — 建議草稿可以，但最終由 PM 確認
- Don't: 一次要求 PM 回答太多問題 — 分優先級，最多 3-5 個關鍵問題
- Don't: 完整度不足就直接進估點 — 先把需求釐清
- Don't: 跳過 codebase 分析 — 不讀 code 就無法產出有意義的 scope 和 edge cases
- Don't: Phase 0 誇大問題嚴重度 — 如實評估，讓數據說話（引用次數、影響頁面數）

## Prerequisites

- **Phase 0**：RD 指定的程式碼或模組路徑 + 對應專案已 clone
- **Phase 1**：JIRA ticket 存在（至少有標題）
- **Phase 2**：需求已明確（Phase 0 或 Phase 1 完成）
- Atlassian MCP 已連線
- 對應專案已 clone 到 `{base_dir}/`（用於 codebase 分析）
