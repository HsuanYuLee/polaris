# Epic Verification Workflow

Reference doc for the three-layer verification structure. Not yet integrated into skills — validate with 2 Epic cycles before graduating to skill changes.

## Status: Draft (pre-graduation)

**Graduation criteria:**
- [x] Epic #1 試跑完成，記錄調整項（GT-483, 2026-04-05）
- [x] Reference doc 根據 Epic #1 修正（加入 Playwright browser-first、URL 規範、測資來源）
- [ ] Epic #2 驗證完成，無結構性修改
- [ ] 畢業 → 改進 epic-breakdown, epic-status, work-on, jira-estimation

**Graduation signal:** 連續 2 個 Epic 走完流程且 doc 核心流程不需修改。

---

## Three-Layer Verification

| Layer | Purpose | Timing | Form |
|-------|---------|--------|------|
| **Task test plan** | PR 品質紀錄，留存讓人 review | task branch → feature PR | Sub-task（紀錄用，在 PR gate 內，非獨立驗收） |
| **Epic per-AC verification** | 業務目標達標證明 | 所有 task merge 回 feature 後 | KB2CW Task × N，Playwright E2E 逐條跑 |
| **Feature integration test** | task 之間互動沒問題 | 同上 | 驗收單之一或獨立一張 |

## Layer 1: Task Test Plan (sub-task)

**What:** 每張實作 task 開一張 sub-task 記錄測試計劃。

**Purpose:** 不是驗收 gate，而是品質紀錄。讓其他人 review 這個 Epic 時，能確認每張 task 是如何通過框架定下的測試計劃的。未來可以與時俱進增強或調整。

**Content:**
```
測試計劃 — {TICKET_KEY}

1. 品質檢查：lint ✓ / test ✓ / coverage ✓
2. VR：{triggered / not applicable}（理由）
3. 驗證：{verify-completion 結果 or 手動驗證步驟}
4. PR review：{approved by X}
```

**Trigger:** `work-on` 或 `jira-estimation` 建立 task 時自動建 sub-task。dev-quality-check 和 verify-completion 跑完後更新內容。

**Not a blocker:** task 的 PR merge 不依賴 sub-task 狀態。sub-task 是事後記錄。

## Layer 2: Epic per-AC Verification (KB2CW Task)

**What:** Epic 的每個 AC 開一張驗收 ticket。

**Source of AC items:**
- QA/PM 提供的 happy flow 和驗收標準
- RD 補充 Polaris 推斷的重要檢查（VR、效能指標、邊界條件）

**Size threshold:**
- Epic > 8 pts 或 > 2 tasks → per-AC 拆驗收單
- Epic ≤ 8 pts 或 ≤ 2 tasks → 合併成一張「Epic 驗收」

**When to create:**
- `epic-breakdown` 拆單時自動在最後產生
- Status 設為 Open / Waiting for Development
- 標記依賴：depends on 所有實作單

**When to run:**
- `epic-status` 偵測所有實作單 PR merged 回 feature branch 後提醒
- 驗收前先 rebase develop（確保 feature branch 是最新的）

**Environment tagging:**
每張驗收單標記可在哪個環境驗：

| Tag | Meaning | Example |
|-----|---------|---------|
| `env:feature` | 可在 feature branch 驗 | VR zero-diff, code structure check |
| `env:stage` | 需要 stage 環境 | 真實 TTFB 數字, 真實 API response |
| `env:both` | feature 初步驗 + stage 最終驗 | 效能指標（local 初步, stage 最終） |

同一張驗收單可跑兩次：feature branch 初步通過 → stage 最終通過。更新結果在 ticket comment。

**Execution:**
- Playwright E2E 逐條跑，結果更新在各驗收 task 上
- 結果作為 evidence 給 QA/PM 確認標準達到

## Layer 3: Feature Integration Test

**What:** feature branch 每次整合新的 sub-task code 後，重跑**所有已整合子單**的驗證。不是只在「全部 merge 完」才跑一次。

**Why:** GT-483 試跑實證 — KB2CW-3461 和 KB2CW-3556 各自驗過，但 rebase 整合時 conflict resolution 把正確的 i18n endpoint 蓋掉，個別驗證都沒重跑，直到上線前才發現翻譯全壞。

**Core rule: 有整合就要驗，不管整合兩個或三個 task。**

### Trigger Points

整合驗證不是單一觸發點，而是多層觸發同一個動作：

| 觸發場景 | 時機 | 信心度 |
|----------|------|--------|
| Polaris 幫 merge task → feat | 整合完立刻跑 | 最高（確定性） |
| 手動 merge 後使用者說「繼續」/「next」 | /next 偵測 feat branch 有新 commit | 高 |
| 跑 epic-status / converge | 推進前兜底 | 中（可能距離整合已有時間差） |
| 開 feature PR 到 develop | git-pr-workflow quality gate | 兜底（最後防線） |

四層觸發同一個動作：收集 feat branch 上所有已整合子單的驗證項，全部跑一輪。

### Executable Verification Format

每張子單的驗證項必須是**可執行的**，不能只是 JIRA 文字描述。建立子單時，驗證項需包含至少一個 executable check：

```yaml
# 驗證項格式（寫在 JIRA sub-task description 或 comment）
verification:
  # 首選：Playwright 瀏覽器驗證（有 session、有渲染、有 JS 執行）
  # {BASE_URL} 由公司層 playwright-testing reference 定義（如 dev.kkday.com）
  - name: "商品頁 SSR 渲染正常"
    type: browser
    command: |
      npx playwright test --grep "product-page-render"
      # 或 inline script:
      # page.goto('{BASE_URL}/zh-tw/product/12345')
      # expect(page.locator('[data-testid="product-title"]')).toBeVisible()
    assert: "page renders without error, key elements visible"

  - name: "i18n 翻譯正常（瀏覽器）"
    type: browser
    command: |
      # page.goto('{BASE_URL}/zh-tw/product/12345')
      # expect(page.locator('text=加入購物車')).toBeVisible()
    assert: "translated text renders correctly in browser context"

  # API-only 驗證（無渲染需求時才用 curl）
  - name: "footer cache header"
    type: endpoint_check
    command: "curl -sI {BASE_URL}/api/_nuxt/footer"
    assert: "headers contains 'x-nitro-cache'"

  - name: "TTFB < 1000ms"
    type: performance
    command: "curl -o /dev/null -s -w '%{time_starttransfer}' {BASE_URL}/zh-tw/"
    assert: "time_starttransfer < 1.0"

  - name: "SSR 無 waterfall"
    type: log_check
    description: "dev server log 不應出現 sequential fetch warning"
```

| Type | 自動化程度 | 說明 |
|------|-----------|------|
| `browser` | 全自動 | **首選** — Playwright 瀏覽器驗證（有 session、有渲染） |
| `endpoint_check` | 全自動 | curl + response assertion（僅限無渲染需求的 API） |
| `performance` | 全自動 | timing assertion |
| `log_check` | 半自動 | 需人工判讀 log |
| `visual` | 半自動 | VR 截圖比對 |
| `manual` | 手動 | 標記步驟，人工執行 |

### Execution Flow

```
feat branch 整合了新的 sub-task code
  ↓
1. 列出所有已整合的 sub-task（git log 比對）
2. 從 JIRA 收集每張的 verification items
3. 起 dev server on feat branch
4. 逐項執行驗證
5. 輸出報告：
   KB2CW-3461 i18n 翻譯    ✅ PASS (data keys: 1847)
   KB2CW-3461 SSR parallel  ✅ PASS (no waterfall)
   KB2CW-3462 footer cache  ✅ PASS (x-nitro-cache: HIT)
   KB2CW-3556 prefetch      ✅ PASS (prefetch triggered)
   ─────────────────────────
   Integration: 4/4 PASS
6. 任一 FAIL → 標記「整合回歸」，阻擋推進
```

### Content (unchanged)
- VR 截圖比對（feature branch vs main/develop baseline）
- E2E smoke test（key user flows）
- 如果 Epic 涉及效能 → 效能基準對比

**Form:** 可以是驗收單之一（如「Feature 整合 VR」），或獨立一張。

## GT-483 Lessons Learned (Epic #1 Trial)

GT-483 整合測試試跑產出的具體教訓，已驗證並固化在本文件中。

### 1. 瀏覽器優先，curl 退居 API-only

**問題：** curl 打 endpoint 沒有 session、沒有 cookie、沒有 JS 執行。頁面是否真的渲染正常、翻譯是否正確顯示、CSR hydration 是否成功 — curl 一概看不到。

**規則：** 整合測試的 `type` 首選 `browser`（Playwright）。只有純 API header 檢查（如 cache header）或 timing 測試才用 `endpoint_check`。

### 2. URL 格式規範

b2c-web 的 URL 有嚴格的格式要求，寫錯會 404：

| 欄位 | ✅ 正確 | ❌ 錯誤 |
|------|--------|--------|
| locale | `zh-tw`（小寫） | `zh-TW` |
| location | `tw-taiwan`（urlName） | `A01-001`（area code） |
| 完整範例 | `/zh-tw/product/12345` | `/zh-TW/product/12345` |

**來源：** SIT 站的實際 URL 是 source of truth，直接從 SIT 複製再換 host。

### 3. 測資來源：SIT → localhost

**SIT DB 和 dev DB 是同一個。** SIT 有的商品、locale、location，dev 環境就有。

**正確做法：**
1. 到 SIT 站 (`https://sit-www.kkday.com`) 取目標頁面 URL
2. 記下 URL pattern（locale、location、商品 ID 等）
3. 替換 host 為 `localhost:3001`
4. 在 Playwright 裡直接 `page.goto(localUrl)`

**不要：** 自己猜商品 ID、猜 URL path、或從 DB 撈 ID。SIT 站上看得到的就是可用的測資。

### 4. 驗證項選擇

| 好的驗證項 | 不好的驗證項 |
|-----------|------------|
| 頁面是否渲染（Playwright 截圖 + 元素斷言） | curl 打 API 看 JSON |
| 翻譯文字是否出現在畫面上 | i18n API response 有幾個 key |
| 關鍵互動是否可用（按鈕、連結） | HTTP status code 200 |
| SSR hydration 完成（無 console error） | 無渲染的 API timing |

---

## Feature Branch Flow

```
feature/{EPIC_KEY}-{description}
  │
  │  ── 實作階段 ──
  ├── task/{TICKET_KEY}-{desc} → PR to feature branch
  │     └── sub-task: 測試計劃（Layer 1, 品質紀錄）
  ├── task/{TICKET_KEY}-{desc} → PR to feature branch
  │     └── sub-task: 測試計劃
  ├── ...
  │
  │  ── 驗收階段（所有 task merge 回 feature 後）──
  │  ── Step 0: rebase develop ──
  ├── {TICKET_KEY} — 驗收 AC1 (Layer 2)
  ├── {TICKET_KEY} — 驗收 AC2 (Layer 2)
  ├── {TICKET_KEY} — Feature 整合測試 (Layer 3)
  │
  └── feature → develop PR（全部驗收通過 = 功能完整驗收的 PR）
```

## Skill Integration Map (post-graduation)

| Skill | Change needed |
|-------|--------------|
| `epic-breakdown` | 拆單最後自動產生 per-AC 驗收單 + 整合測試單 |
| `epic-status` | Phase 1 偵測「所有 task merged → 提醒開始驗收」。Phase 2 路由驗收 gap |
| `work-on` | 建 task 時自動建測試計劃 sub-task |
| `jira-estimation` | 估點時產生測試計劃 template |
| `dev-quality-check` | Step 8b VR 條件觸發（已完成 v1.52.0） |
| `git-pr-workflow` | 驗收前 auto-rebase develop（待做） |

## Edge Cases

| Situation | Handling |
|-----------|---------|
| Epic 只有 1 張 task | 合併所有驗證為一張，不拆 per-AC |
| AC 只能在 stage 驗 | 標記 `env:stage`，feature branch 階段跳過，stage deploy 後跑 |
| 驗收跑出非預期差異 | 評估是否開 fix ticket 或接受差異，記錄在驗收 ticket comment |
| Feature branch 跟 develop 衝突 | rebase + 解衝突後重跑整合測試 |
| 某張 task PR 一直沒 merge | `epic-status` Phase 2 路由 → fix-pr-review 或催 review |
| QA/PM 沒提供 happy flow | RD 根據 Epic AC 自擬，標記「RD 推斷，待 PM 確認」 |
