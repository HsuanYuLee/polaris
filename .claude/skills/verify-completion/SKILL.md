---
name: verify-completion
description: >
  Verifies that a code change actually works as intended before declaring a task done.
  Goes beyond lint/test pass — checks real behavior (dev server, curl, browser, UI render).
  Use this skill whenever: (1) another skill (fix-bug, work-on, tdd) finishes
  implementation and needs to confirm the fix works end-to-end, (2) user says "驗證", "verify",
  "確認改好了", "真的修好了嗎", "check it works", "驗收", (3) after quality check passes but
  before declaring a task complete. This skill is the last gate before PR — it catches issues
  that pass tests but fail in practice (wrong env var, missing import in SSR, layout shift).
metadata:
  author: Polaris
  version: 1.3.0
---

# Verification Before Completion

Tests passing ≠ feature working. This skill adds a behavioral verification step after code changes
pass quality checks (lint + test + coverage). The goal is to catch the class of bugs that only
appear when the code actually runs — SSR hydration mismatches, missing runtime dependencies,
environment-specific behavior, visual regressions.

## When to Run

This skill should be invoked **after** `dev-quality-check` passes and **before** declaring
the task complete (committing / opening PR). It's the final gate.

Typical invocation chain:
```
implementation → dev-quality-check → verify-completion → commit/PR
```

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## 1. Extract Test Plan from JIRA

Before any verification, read the JIRA ticket description to find the test plan. Tickets created through
the estimation/breakdown flow include a 「測試計畫」or 「測試計劃」section with specific verification items.

**1a. Read the ticket:**

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}（config: `jira.instance`，fallback: your-domain.atlassian.net）
  issueIdOrKey: <TICKET>
  fields: ["description"]
  responseContentFormat: markdown
```

**1b. Extract test plan items:**

Look for sections matching these patterns in the description:
- `## 測試計畫` / `## 測試計劃` / `## Test Plan`
- Checklist items: `- [ ] ...` or `* [ ] ...`

If found, these items become the **primary verification checklist**.
If no test plan is found in the description, fall back to the generic verification checklist in Step 3.

**1c. Check for existing verification sub-tasks:**

Before creating anything, query JIRA to see if verification sub-tasks already exist for this ticket.
This handles the common case where a previous run already created them, or another skill (like
`epic-breakdown`) included verification items during task breakdown.

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}
  jql: parent = <TICKET> AND summary ~ "驗證"
  fields: ["summary", "status", "assignee"]
  maxResults: 20
```

**If existing sub-tasks are found → enter Status Check Mode (skip to 1c-ii).**
**If no sub-tasks found → enter Create Mode (continue to 1c-i).**

---

**1c-i. Create Mode — create sub-tasks for each test plan item:**

（當沒有既有驗證子單時才走這條路。）

為每個測試項目建立 JIRA sub-task，掛在當前 ticket 下。每張子單必須包含：
- **測試方法**：如何驗證（curl、dev server、unit test）
- **測試資料**：具體的測試 URL、locale、input data
- **預期結果**：什麼算 PASS

```
mcp__claude_ai_Atlassian__createJiraIssue
  cloudId: {config: jira.instance}
  projectKey: <PROJECT>
  issueTypeName: Sub-task
  parent: <TICKET>
  summary: "[驗證] <test plan item>"
  assignee_account_id: <當前使用者 accountId>
  description: |
    ## 測試方法
    curl localhost:3000/zh-tw/category/... 檢查 HTTP 200 + title 正確

    ## 測試資料
    - URL: https://{config: infra.dev_host}/your/test/path
    - Locale: zh-tw, en, ja（切語系驗證）

    ## 預期結果
    - HTTP 200
    - `<title>` 包含正確語系文字
    - Server log 無 error
```

**測試資料來源**：從 JIRA ticket description 的測試計畫、AC、或 Figma 連結中提取。
若 description 未提供具體測試 URL，使用 dev 環境的已知可用頁面（如首頁、熱門商品頁）。

Sub-task 建立後 assign 給當前使用者（從 getJiraIssue 的 assignee.accountId 取得）。

Then continue to **1d** below.

---

**1c-ii. Status Check Mode — use existing sub-tasks:**

（當已有驗證子單時走這條路。不重複建單，直接檢查狀態。）

將查到的子單依狀態分類：

| 子單狀態 | 分類 | 處理方式 |
|---------|------|---------|
| **完成** | ✅ already_done | 不需再驗，直接納入報告 |
| **開放 / In Development** | ⬜ pending | 需要驗證或確認 — 進入 1d 分類 + 1e 啟動 sub-agent |
| 其他（如 BLOCKED） | 🔧 needs_attention | 讀 sub-task comments 了解原因，回報使用者 |

比對既有子單和 JIRA description 中的測試計畫項目。若測試計畫有項目但找不到對應子單
（例如新增了測試項目），為缺少的項目建立新子單（走 1c-i 的建立邏輯，只建缺少的）。

**只對 pending 的子單執行後續驗證流程。** already_done 的子單直接帶入 Step 4 的報告。

Then continue to **1d** below (only for pending items).

---

**1d. Classify each item as automatable or manual:**

| 類型 | 判斷標準 | 處理方式 |
|------|---------|---------|
| **可自動驗證** | curl 打 API、SSR 檢查、console error 檢查 | Sub-agent 平行執行 |
| **可自動修復** | 補寫測試、修 lint、加 error handling | **先修再驗** — 不等人，直接修完驗 |
| **需人工介入** | 測資有問題、需 staging 環境、需視覺比對 | 標記為「需人工」，回報使用者 |

核心原則：**能自動做的都自動做完**，只有真正需要人工判斷的才回報。
例如「SSR init route 單元測試」→ 這是可自動修復的，直接補寫測試、跑測試、通過後標完成。

**1e. Start verification environment + health check + launch ALL sub-agents in parallel:**

啟動 dev server，**確認 server 健康啟動**後，為每一個 sub-task 啟動獨立的平行 sub-agent。

唯一例外：sub-task 之間有明確依賴時（如 B 的驗證需要 A 的修復先完成），才 sequential 處理。

**1e-i. Install + 啟動 dev server：**

模擬真實開發者流程：先裝依賴，再啟動 dev server。這確保連 `pnpm i` 產生的 postinstall（`nuxi prepare`、type generation）都能正常通過。

```bash
# 1. Install dependencies（確保 lock file 一致、postinstall hooks 正常）
pnpm -C <project> install

# 2. 啟動 dev server（背景執行）
# 注意：有些專案用 turbo-run 需要選 app，直接用 nuxi dev 避免互動式選單
<project>/node_modules/.bin/nuxi dev <project> --dotenv .env.local &
```

> 如果專案沒有 `.env.local`，去掉 `--dotenv` 參數，讓 Nuxt 讀預設的 `.env`。

**1e-ii. Dev Server Health Check Gate（non-skippable）：**

啟動後必須等頁面真正可訪問才能繼續。**必須透過 `<dev-docker>` 的 nginx proxy 層打**，這才是標準開發流程。

**標準 dev 環境架構：**
```
curl → {config: infra.dev_host}:80 → nginx (Docker) → host.docker.internal:3001 → Nuxt dev server
```

- Nuxt dev server 跑在 **port 3001**（不是 3000）
- nginx 從 Docker container proxy 到 `host.docker.internal:3001`
- `/etc/hosts` 將 `{config: infra.dev_host}` 指向 `127.0.0.1`
- 503 = nginx 連不到 upstream（Nuxt 未啟動或 crash），不是 Nuxt 自己回的

Health check 抓的是「server 根本起不來」的情況（如 vitest import 被 Nitro runtime 載入導致 worker init crash、module 解析失敗、env var 缺少），避免 sub-agents 全部拿到 503 卻看不出根因。

```bash
# 透過 nginx proxy 打真實頁面，每 5 秒一次，最多等 90 秒
for i in $(seq 1 18); do
  http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://{config: infra.dev_host}/<default-locale>" --max-time 10 2>/dev/null)
  if [ "$http_code" = "200" ]; then
    echo "✅ Dev server ready via nginx proxy (HTTP 200)"
    break
  fi
  echo "⏳ Waiting for dev server... ($i/18, HTTP $http_code)"
  sleep 5
done
```

其中 `<default-locale>` 用專案的預設語系路徑。**必須打一個真實頁面路徑**（如 `http://{config: infra.dev_host}/your/test/path`），不能只打 `/`（框架可能 redirect 或回 404）。

**Health check 判定（兩階段）：**

**階段 1：Server 可達性**

| 結果 | 動作 |
|------|------|
| HTTP 200 | ✅ 進入階段 2 content sanity check |
| 90 秒後仍 503 | ❌ **FAIL**。503 = nginx 連不到 dev server upstream。回報：「Dev server 啟動失敗（nginx 回 503），請檢查：(1) dev server 是否在正確 port 上，(2) `<dev-docker>` 是否在跑，(3) terminal 的 server log」 |
| 90 秒後 connection refused (000) | ❌ **FAIL**，回報：「nginx proxy 未啟動（connection refused），請確認 `<dev-docker>` 容器是否在執行」 |

**階段 2：Content Sanity Check**

HTTP 200 不代表頁面正常。頁面可以載入但翻譯全壞（顯示 i18n key 而非翻譯文字）、API 資料缺失（空白區塊）、或 SSR 失敗（只有 client shell）。用 curl 取得 HTML 後做基本 sanity check：

```bash
# 取得頁面 HTML
html=$(curl -s "http://{config: infra.dev_host}/<default-locale>" --max-time 10)

# Check 1：i18n key 洩漏 — 頁面不應出現大量未翻譯的 key
# 常見 pattern：連續底線分隔的英文詞（如 common_type_to_search、home_index2_learn_more）
i18n_leak_count=$(echo "$html" | grep -oE '[a-z]+(_[a-z0-9]+){2,}' | wc -l)
if [ "$i18n_leak_count" -gt 10 ]; then
  echo "⚠️ i18n key leak detected ($i18n_leak_count raw keys in HTML)"
fi

# Check 2：SSR 內容存在 — 頁面應有實際的 HTML 內容，不是空的 app shell
if echo "$html" | grep -q "__NUXT__"; then
  echo "✅ SSR payload present"
else
  echo "⚠️ No SSR payload — possible client-only render"
fi

# Check 3：<title> 應包含有意義的文字，不是 i18n key
title=$(echo "$html" | grep -oP '<title>\K[^<]+')
echo "Page title: $title"
```

**Content check 判定：**

| 問題 | 嚴重度 | 動作 |
|------|--------|------|
| i18n key leak > 10 個 | ⚠️ WARNING | 回報：「頁面顯示 i18n key 而非翻譯文字，可能原因：(1) .env.local 的 API_LANG_BASE_URL 指向不可達的 endpoint，(2) api-lang 服務不可用。檢查 /api/_nuxt/local/i18n?locale=zh-tw 的回應」。**不 block sub-agents**（翻譯問題可能是環境限制），但在驗證報告中標註 |
| No SSR payload | 🔴 FAIL | SSR 完全失敗，回報並 FAIL |
| title 是 i18n key | ⚠️ WARNING | 同 i18n leak，標註在報告中 |

**只有 Server 不可達（階段 1 失敗）才 block 所有 sub-agents。** Content 問題（階段 2）標註 warning 但繼續執行——翻譯缺失可能是 dev 環境限制（如 Mockoon 未啟動），不應阻擋其他驗證項目。

**1e-iii. Launch sub-agents：**

每個 sub-agent 從頭到尾獨立完成：執行驗證 → 留 JIRA comment → 轉狀態，不需等待其他 agent，也不回到主 agent 統一處理。

每個 sub-agent 的 prompt：

```
你是驗證 agent。驗證以下測試計畫項目，完成後獨立更新 JIRA sub-task 狀態。

## 項目
{test_plan_item}

## Sub-task
{sub_task_key}（JIRA sub-task，驗完由你轉狀態）

## Ticket
{ticket_key} in {base_dir}/{repo}

## 測試資料
{test_urls, locales, input data}

## 指示

{根據項目類型：}

### 可自動驗證（curl/SSR/API 檢查）
1. 依測試資料中的 URL + 所有指定 locale 逐一驗證
2. 執行驗證（curl、grep HTML、檢查 server log）
3. 在 sub-task 留 comment 記錄測試結果（含指令、輸出、截圖描述）
4. 轉 sub-task 狀態：PASS → 開始開發(11) → 子任務開發完畢(13)

### 可自動修復（補測試、修 code）
1. 讀取相關 skill（unit-test）+ 專案 CLAUDE.md
2. 實作修復（補寫測試、修正 code）
3. 跑測試確認通過
4. 在 sub-task 留 comment 記錄修了什麼 + 測試結果
5. 轉 sub-task 狀態：同上

### 無法執行（環境不具備、外部依賴缺失等）
**不可直接跳過。** 必須**盡最大努力讓驗證可執行**，而不是標 BLOCKED 回報。

**解決環境問題的優先順序**（逐步嘗試，不是跳過）：
1. **自行啟動缺少的服務** — Mockoon 未啟動 → 啟動 Mockoon；dev server 未跑 → 啟動 dev server
2. **尋找有效的測試資料** — product 404 → 找一個真正存在的 product ID；API 回空 → 換一組參數
3. **使用替代驗證方式** — Mockoon 無法啟動 → 用 dev server 直連 + timing 測量作替代
4. **以上都失敗** → 才標 BLOCKED，但 comment 必須詳述嘗試過什麼、為什麼每步都失敗

**HTTP 狀態碼規則**：預期頁面要正常顯示時，**HTTP 200 是唯一可接受的狀態碼**。
404/500 不可當作「預期行為」——如果商品不存在導致 404，應該換一個存在的商品 ID 重測，
而不是接受 404 然後說「SSR 沒 crash 所以算通過」。
唯一例外：驗證項目明確是在測試錯誤頁面（如「404 頁面正確顯示」）。

真的無法解決時：
1. 在 sub-task 留 comment 說明：
   - 嘗試了什麼（具體步驟和指令）、每步失敗的原因
   - 建議的替代驗證方式
2. sub-task 保持「開放」不轉狀態
3. 回傳：BLOCKED（附失敗原因 + 建議方案）

### 需人工介入（視覺比對、staging 環境等真正只有人能做的事）
1. 在 sub-task 留 comment 說明原因 + 建議的人工驗證步驟
2. sub-task 保持「開放」不轉狀態
3. 回傳：MANUAL_REQUIRED

## JIRA 操作
- 留 comment：addCommentToJiraIssue（cloudId: {config: jira.instance}，fallback: your-domain.atlassian.net）
- 轉狀態：transitionJiraIssue（transition id: 11 開始開發, 13 子任務開發完畢）
- comment 格式：
  ### 測試結果
  **方法**: curl localhost:3000/zh-tw/category/...
  **Locale**: zh-tw, en, ja
  **結果**:
  - zh-tw: HTTP 200, title 正確 ✅
  - en: HTTP 200, title 正確 ✅
  - ja: HTTP 200, title 正確 ✅

## 限制
- 用 Read tool 讀本地檔案
- 修復後跑 lint + test 確認不破壞既有程式碼
- 每個 sub-agent 獨立轉自己負責的 sub-task 狀態，不等其他 agent
```

同 repo 的修復類 sub-agent 使用 `isolation: "worktree"` 避免衝突。
驗證類 sub-agent 不改檔案，不需 worktree。

## 1.5. 逐條 AC 驗證

在執行一般驗證流程之前，先對照 JIRA 的 Acceptance Criteria 逐條確認。

**1.5a. 取得 AC：**

- 從 Step 1 已讀取的 ticket description 中尋找 AC（關鍵字：`Acceptance Criteria`、`驗收標準`、`AC`、`- [ ]` checklist）
- 若當前 ticket 是 sub-task，且 description 無 AC，則讀取 parent ticket 的 description 取得 Epic/Story 層級的 AC：

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: <PARENT_TICKET>
  fields: ["description", "summary"]
  responseContentFormat: markdown
```

**1.5b. 判斷相關性：**

並非所有 AC 都與當前 ticket 的改動直接相關。逐條判斷：
- ✅ 相關：AC 的驗收範圍包含本次改動的功能
- ⏭️ 跳過：AC 屬於其他 sub-task 或尚未實作的部分（標記「超出本次範圍」）

**1.5c. 對每條相關 AC 進行具體驗證：**

用實際執行的方式驗證，不可只靠「看 code」斷定通過：

| AC | 驗證方式 | 結果 |
|----|---------|------|
| AC1: 價格 300ms 更新 | dev server 實測，devtools 計時 | ✅ ~180ms |
| AC2: timeout → skeleton | mock API delay 5s（Mockoon route） | ✅ 正確顯示 skeleton |
| AC3: 多幣別支援 | 切換幣別後驗 API response | ❌ 未實作 |
| AC4: 後端異常 → fallback | 關掉 mock server 觸發 500 | ✅ fallback UI 正確 |

常用驗證方式：
- curl + grep HTML（SSR 輸出）
- devtools Network tab 計時
- Mockoon route 模擬延遲/錯誤
- 切換 locale / 幣別 / 登入狀態
- dev server console 有無 error

**1.5d. AC 驗證結果處理：**

| 結果 | 動作 |
|------|------|
| 全部 ✅ | 繼續 Step 1e / Step 2 正常流程 |
| 有 ❌（未實作）| **阻擋 PR**：列出未通過的 AC，詢問使用者確認：(1) 補實作，(2) 確認該 AC 超出本張 ticket 範圍 |
| 有 ❌（實作有誤）| **阻擋 PR**：必須修正後重新驗證 |
| AC 超出本次範圍（⏭️）| 在驗證報告中標明，不阻擋 |

**1.5e. 將 AC 驗證結果寫入 JIRA comment：**

無論通過或失敗，都要在 ticket 留下驗證記錄：

```
mcp__claude_ai_Atlassian__addCommentToJiraIssue
  cloudId: {config: jira.instance}
  issueIdOrKey: <TICKET>
  body: |
    ## AC 驗證結果

    | AC | 驗證方式 | 結果 |
    |----|---------|------|
    | AC1: 價格 300ms 更新 | dev server 實測 | ✅ ~180ms |
    | AC2: timeout → skeleton | mock API delay 5s | ✅ 正確顯示 |
    | AC3: 多幣別 | 切換幣別 | ❌ 未實作 |

    **整體結果**：X/Y 通過
    **未通過項目**：（列出 ❌ 的 AC 及原因）
    **超出本次範圍**：（列出 ⏭️ 的 AC）
```

---

## 2. Determine Verification Strategy

Based on the type of change, pick the appropriate verification method:

| Change Type | Verification Method | How |
|-------------|-------------------|-----|
| API util / composable / store | Unit test output review | Tests already ran — review the actual assertions match the JIRA AC |
| Vue component (visual) | Dev server + manual check | `pnpm -C <project> dev`, check the page in browser |
| SSR / SEO change | SSR render check | `curl localhost:3000/<page>` and inspect HTML output |
| Bug fix | Reproduce → verify gone | Re-run the exact reproduction steps from the JIRA ticket |
| API integration | Request/response check | `curl` the endpoint or check network tab |
| Build/config change | Build verification | `pnpm -C <project> build` and check output |

## 3. Generic Verification Checklist

Run through these checks based on what applies (supplements the JIRA test plan from Step 1):

### Functional Verification
- [ ] **AC match** — re-read the JIRA ticket's Acceptance Criteria. Does the implementation satisfy each point?
- [ ] **Reproduction test** (bug fix only) — follow the original bug reproduction steps. Is the bug gone?
- [ ] **Happy flow** — walk through the primary user scenario described in the ticket

### Technical Verification
- [ ] **No console errors** — check browser console or server logs for unexpected errors
- [ ] **SSR works** (if Nuxt) — `curl` the page and verify the critical content is in the HTML (not just client-rendered)
- [ ] **Build succeeds** — `pnpm -C <project> build` completes without errors
- [ ] **No TypeScript errors** — `pnpm -C <project> type-check` or equivalent

### Edge Cases (if applicable)
- [ ] **Empty state** — what happens with no data?
- [ ] **Error state** — what happens when the API fails?
- [ ] **Mobile viewport** — does the layout work on small screens?

## 4. Collect Results and Update Sub-tasks

收集所有 sub-agent 結果後：

**4a. 更新 JIRA sub-task 狀態（由各 sub-agent 獨立完成，不回主 agent 統一處理）：**

| Sub-agent 結果 | Sub-task 動作 |
|---------------|-------------|
| PASS | 轉「完成」 |
| FIXED | commit 修復 → 轉「完成」 |
| FAIL（既有環境問題） | 留 comment 說明 → 轉「完成」（標註非本次改動） |
| BLOCKED（嘗試執行失敗） | 留 comment 說明失敗原因 + 建議替代方案 → 保持「開放」 |
| MANUAL_REQUIRED | 留 comment 說明 → 保持「開放」 |

**4b. 呈現驗證報告：**

```
── Verification Result（JIRA Test Plan）──
✅ Category page SSR 正常載入 → PROJ-1001 完成
✅ Product page SSR 正常載入 → PROJ-1002 完成
✅ i18n 翻譯正確顯示（直連 api-lang）→ PROJ-1003 完成
🔧 ab_test 直連 — 嘗試驗證失敗（原因：...）→ PROJ-1004 開放
✅ error isolation → PROJ-1005 完成
✅ mock server timing parallel 改善 → PROJ-1006 完成
✅ 無 hydration mismatch → PROJ-1007 完成
✅ SSR init route 單元測試 → PROJ-1008 完成（自動補寫）
── JIRA Test Plan: 7/8 passed, 1 blocked
── 需人工介入: 0 項
── Conclusion: BLOCKED — 1 項需解決後重跑 ─────
```

**判定標準：**

| 狀態 | 能否進 PR |
|------|----------|
| 全部 ✅ | ✅ PASS — 可進 PR |
| 有 FIXED 項目 | ✅ PASS — 修復已 commit，可進 PR |
| 有 BLOCKED 項目 | ❌ BLOCKED — 回報使用者，說明失敗原因和建議替代方案 |
| 有 MANUAL_REQUIRED | ❌ BLOCKED — 回報使用者，等人工確認後再繼續 |
| 有 FAIL（非環境問題） | ❌ FAIL — 需修正後重跑 |

## 5. Commit Gate — 驗證子單全通過才放行

這是 commit/push 前的最終 gate。根據 Step 4 的驗證報告做出放行決定：

```
驗證子單: X/Y 通過

X == Y → ✅ COMMIT ALLOWED — 所有驗證項目通過，可以 commit/push
X <  Y → ❌ COMMIT BLOCKED — 列出未通過項目和原因，等使用者決定
```

**BLOCKED 時的回應格式：**

```
❌ 驗證未全數通過（X/Y），不可 commit。

未通過項目：
- PROJ-3505 [驗證] ab_test cache TTL — BLOCKED（Mockoon 未啟動）
- PROJ-3506 [驗證] cache hit 確認 — BLOCKED（依賴 3505）

建議：
1. 啟動 Mockoon proxy 後重跑 verify-completion
2. 或使用者確認可跳過（將記錄在 PR description）
```

使用者明確說「跳過」某項驗證時，在該 sub-task 留 comment 記錄跳過原因，
但 **sub-task 保持「開放」不轉完成** — 讓 QA 知道這項未驗。

## 6. When Verification Is Not Feasible

Some changes can't be easily verified locally:

| Situation | What to Do |
|-----------|-----------|
| Requires auth/session from staging | Note it as "verified via tests only, needs QA on staging" |
| Third-party API not available locally | Verify mock behavior matches expected contract |
| Database-dependent | Verify query logic via unit test, flag for QA integration test |
| Feature flag gated | Verify with flag on, note flag name for QA |

In these cases, explicitly state what was verified and what needs QA attention.

## Do / Don't

- Do: **逐條 AC 驗證並留 JIRA comment**（Step 1.5）— AC 是驗收標準，有未通過則阻擋 PR，等使用者確認是否超出範圍
- Do: 先查既有驗證子單（1c），有就複用，沒有才建新的 — 避免重複建單
- Do: 為每個測試項目建 JIRA sub-task，驗完轉「完成」— 讓進度可追蹤
- Do: 可自動修復的項目（補測試、修 code）直接修完再驗，不要回報「待補」
- Do: **每個 sub-task 用獨立 sub-agent 平行處理**（執行→留 comment→轉狀態），不要回主 agent 統一處理
- Do: Re-read the JIRA AC before verifying — don't rely on memory
- Do: Flag SSR issues early — they're invisible in dev mode but break production
- Do: **每個驗證項目都必須嘗試執行**，失敗後在 JIRA 留 comment 說明原因和建議替代方案
- Don't: **只做功能驗證不對照 AC** — AC 是驗收標準，必須逐條確認；跳過 AC 驗證等於跳過驗收
- Don't: 把可自動完成的項目標為「需人工介入」— 只有真正需要人類判斷的才標
- Don't: **不可跳過任何驗證項目** — 「跳過」不是合法狀態，必須嘗試後才能標 BLOCKED
- Don't: Skip verification because tests pass — tests cover code paths, not user experience
- Don't: Verify in production — always use local dev or staging
- Don't: 在主 agent 逐一留 JIRA comment — 這是 sub-agent 的工作

## Prerequisites

- Code changes completed and saved
- `dev-quality-check` passed (lint + test + coverage + build smoke test)
- Dev server must start successfully — Step 1e health check will verify this automatically. If the server can't start (503 / connection refused), the entire verification fails immediately with a clear error message pointing to the server log
