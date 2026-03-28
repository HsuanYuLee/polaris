---
name: auto-improve
description: >
  Autonomous code improvement agent: scans a repo for code quality issues (type safety, dead code,
  missing tests, code smells, deprecated usage) and creates JIRA tickets with detailed plans for
  humans to review and decide whether to implement.
  Supports dry-run mode (report only) and scheduled execution via /loop.
  Use when: (1) user says "auto improve", "自動改善", "掃 code", "code sweep", "autonomous improvement",
  (2) user wants AI to proactively find code issues, (3) user says "掃描品質",
  "find issues", "code health", "程式碼健檢", "improve code quality",
  (4) used with /loop for scheduled scans.
  This skill creates JIRA tickets for discovered issues — humans decide whether to implement.
metadata:
  author: ""
  version: 2.3.0
---

# Auto Improve — 自動程式碼品質改善

自動掃描指定 repo 的 codebase，找出品質問題，每個問題開一張 JIRA ticket（附 pseudocode + plan），供人類審核後決定是否實作。

## Defaults

| 參數 | 預設值 | 說明 |
|------|--------|------|
| Target repo | CWD 自動偵測 | 也可由使用者指定 repo 路徑 |
| Base branch | `develop` | 掃描基準 |
| Mode | `ticket` | `ticket`=開 JIRA ticket，`dry-run`=只報告不開 ticket |
| Max tickets | 5 | 單次最多開幾張 ticket |
| JIRA project | `TASK` | 可由使用者 override（如 `--project GT`） |
| Slack channel | 使用者指定 | 選填，完成後通知 |
| Scan dimensions | all | 可指定 `type-safety,dead-code,missing-tests,code-smells,deprecated-usage,review-lessons` |

## Scripts

| Script | 用途 | Input | Output |
|--------|------|-------|--------|
| `scripts/detect-repo-context.sh` | 偵測 repo 類型、框架、base branch | `[--repo-dir <path>]` | JSON object |

Script 路徑相對於本 SKILL.md 所在目錄。執行前確認有 `+x` 權限。

## Workflow

### 0. 解析參數

從使用者輸入解析：
- `--repo` 或 CWD → 目標 repo 路徑
- `--mode dry-run` → 只報告不建 ticket
- `--max N` → 最多開 N 張 ticket（預設 5）
- `--dimensions type-safety,dead-code` → 限定掃描維度
- `--project TASK` → JIRA project key（預設 `TASK`）
- `--slack <channel-id>` → 完成後發 Slack 通知

### 1. 偵測 Repo Context

```bash
SKILL_DIR="<path-to-this-skill>"
"$SKILL_DIR/scripts/detect-repo-context.sh" --repo-dir <target-repo>
```

輸出 JSON：
```json
{
  "project": "your-app",
  "framework": "nuxt3",
  "language": "typescript",
  "test_framework": "vitest",
  "base_branch": "develop",
  "src_dirs": ["src", "apps/main/src"],
  "has_eslint": true,
  "has_tsconfig": true
}
```

**掃描排除目錄**（不掃描以下路徑）：
`node_modules`, `dist`, `.nuxt`, `.output`, `vendor`, `coverage`, `.git`, `public/static`

### 2. 平行掃描

為每個掃描維度啟動獨立 sub-agent，平行執行。每個 sub-agent 負責：
1. 掃描該維度的問題（排除上述目錄）
2. 回傳結構化的 findings 清單

**掃描維度與策略：**

#### 2a. Type Safety（型別安全）

掃描目標：
- `any` type 使用（grep `as any`, `: any`, `<any>`）
- 缺少 return type 的 exported functions
- non-null assertion (`!`) 濫用
- 未型別化的 API response

判斷方式：讀取 tsconfig.json strict 設定，grep source files，分析上下文決定是否為真正問題。

#### 2b. Dead Code（死碼）

掃描目標：
- 未使用的 exports（grep import references across codebase）
- 未使用的 components（在 `components/` 但沒被任何 template/page import）
- 註解掉的程式碼區塊（連續 3+ 行 `//` 或 `/* */`）
- 空的函數或只有 console.log 的函數

判斷方式：交叉比對 export 與 import，確認移除不會造成 side effects。

#### 2c. Missing Tests（缺少測試）

掃描目標：
- 有 business logic 的 `.ts` 檔案沒有對應 `.test.ts` / `.spec.ts`
- Composables（`use*.ts`）沒有測試
- Store files 沒有測試
- Utils / helpers 沒有測試

排除：`types.ts`、`constants.ts`、`*.d.ts`、`index.ts`（barrel）、`*.config.*`、純 UI component。

判斷方式：用 dev-quality-check 的測試覆蓋偵測邏輯。此維度只補測試不改 source code。

#### 2d. Code Smells（程式碼異味）

掃描目標：
- 超長函數（>80 行）
- 深度巢狀（>4 層 indent）
- 重複程式碼（相似度高的區塊）
- Magic numbers / hardcoded strings
- 過大的 component（template >200 行）

判斷方式：結構分析，只回報高信心的 smells。

#### 2e. Deprecated Usage（過時用法）

掃描目標：
- 已棄用的 Vue 2 patterns（`this.$refs` in Options API, `@/` 不一致等）
- 已棄用的 library API（根據 package.json 版本比對）
- `require()` 可替換為 ESM import
- Legacy patterns 已有更好的替代方案

判斷方式：讀取專案的 .claude/rules/ 規範，比對現有 code。

#### 2f. Review Lessons 聚合

掃描目標：`.claude/rules/review-lessons/` 目錄下的所有 lesson 檔案。

**聚合邏輯：**

1. 列出 `.claude/rules/review-lessons/` 下所有 `.md` 檔案（若目錄不存在則跳過此維度）
2. 讀取每個 lesson 檔案，解析 `Source` 欄位（格式：`PR #NNN` 或 `PR #NNN, #MMM`）計算出現次數
3. 計算每個 lesson 的 PR 來源數量（= 同一主題檔案中不同 PR 的 Source 條目數）
4. 判斷「過時」：Source PR 最新合併日期超過 90 天（3 個月）且來源數量只有 1

**輸出分類：**

- **升級候選**（出現 ≥ 2 個不同 PR Source）：建議移到 `.claude/rules/` 主目錄成為正式規則
- **清理候選**（過時 + 低頻：最新 PR > 90 天 + Source 數量 = 1）：建議刪除
- **維持現狀**：其餘 lessons 保留在 review-lessons 目錄

**注意**：此維度不開 JIRA ticket，而是輸出一份獨立的 Review Lessons 報告，並在 Step 4 使用者確認後直接執行（搬移或刪除檔案），不走 Step 5 的建 ticket 流程。

### 3. 去重 + 彙整 Findings

#### 3a. 查詢已存在的 auto-improve tickets

用 JQL 查詢目前 JIRA project 中已存在的 `auto-improve` label tickets：

```
project = {JIRA_PROJECT} AND labels = "auto-improve" AND status not in (已關閉, 已釋出, 完成)
```

取得所有 open 的 auto-improve tickets 的 summary 和 description，用於比對。

#### 3b. 去重

對每個 finding，比對已存在的 tickets：
- **Summary 相似**（同維度 + 同檔案路徑）→ 視為重複，跳過
- **檔案路徑相同但問題不同** → 不算重複，保留

被過濾掉的 findings 在 dry-run 報告中標記 `⏭️ 已存在`。

#### 3c. 彙整

合併所有 sub-agent 的結果，去重後產出結構化清單：

```
| # | 維度 | 檔案 | 問題描述 | 信心度 | 修正複雜度 | 狀態 |
|---|------|------|----------|--------|-----------|------|
| 1 | type-safety | src/utils/api.ts:42 | `as any` 可替換為正確型別 | HIGH | LOW | 新發現 |
| 2 | dead-code | src/components/OldBanner.vue | 未被任何頁面 import | HIGH | LOW | ⏭️ 已存在 TASK-123 |
| 3 | missing-tests | src/composables/useCart.ts | 無對應測試檔 | HIGH | MEDIUM | 新發現 |
```

**過濾規則：**
- 只保留信心度 HIGH 的 findings
- 排除已存在的 tickets（去重）
- 優先排序：LOW 複雜度優先（容易處理）
- 相關聯的 findings 合併為一張 ticket（例如同一個 dead component + 其 import 移除）
- 套用 Max tickets 上限

### 4. 使用者確認

#### 4a. Review Lessons 報告（若有掃描 review-lessons 維度）

在其他 findings 之前，先輸出 Review Lessons 聚合報告：

```
Review Lessons 聚合報告
目錄：.claude/rules/review-lessons/

升級候選（出現 ≥ 2 個 PR Source）：
  • no-bare-v-if.md — Source: PR #123, PR #145, PR #167（3 次）
    建議升級到：.claude/rules/vue-template-patterns.md（或新建獨立規則檔）

清理候選（過時 + 低頻）：
  • old-axios-pattern.md — Source: PR #88（1 次，已超過 90 天）
    建議刪除

各主題出現頻率：
  no-bare-v-if.md ████████ 3 次
  prop-validation.md ████ 2 次
  old-axios-pattern.md ██ 1 次（過時）
```

詢問使用者：
> 輸入要執行的操作編號（例如 `upgrade:1` 升級、`clean:2` 清理，或 `all-upgrade`、`all-clean`、`none` 跳過）：

確認後，對升級候選：讀取 lesson 內容 → 寫入 `.claude/rules/` 對應檔案（新建或 append）→ 刪除 review-lessons 下原檔。對清理候選：直接刪除檔案。

**Dry-run 模式**在此步驟只輸出報告，不執行搬移或刪除。

#### 4b. 其他維度 Findings 確認

顯示 findings 清單（含去重結果），詢問使用者：

> 發現 N 個可改善項目（M 個新發現，K 個已存在 ticket 跳過），預計開 M 張 JIRA ticket。
> 輸入要建 ticket 的編號（例如 `1,3,5` 或 `all`），輸入 `none` 跳過：

**Dry-run 模式**在此步驟結束，只輸出報告不繼續。

### 5. 建立 JIRA Tickets

使用者確認後，對每個 finding 用 `createJiraIssue` 建立 JIRA ticket。

**Ticket 格式：**

- **Issue type**：Task
- **Summary**：`[Auto Improve] [{dimension}] {問題一句話描述}`
- **Labels**：`auto-improve`
- **Description**（Jira wiki markup）：

```
h2. 問題描述

*維度*：{dimension}
*信心度*：{HIGH}
*修正複雜度*：{LOW/MEDIUM/HIGH}
*影響檔案*：
- {file_path}:{line_number}
- {file_path}:{line_number}

{問題的詳細說明，包含現狀分析}

h2. 現有程式碼

{code:language=typescript|title=file_path}
// 標注問題的現有 code snippet（含行號）
{code}

h2. 修正計畫

*目標*：{一句話描述修正後的狀態}

*步驟*：
# {步驟 1 描述}
# {步驟 2 描述}
# {步驟 3 描述}

*Pseudocode*：
{code:language=typescript|title=修正藍圖}
// 修正後的 pseudocode，清楚標注：
// - 要改哪些檔案
// - 每個檔案的改動重點
// - 新增的型別/函數/測試的 signature
{code}

h2. 驗證方式

- {如何驗證修正正確：跑哪些測試、檢查哪些行為}
- {預期不會影響的範圍}

h2. 注意事項

- {潛在風險或需要額外確認的點}

----
_此 ticket 由 AI 自動掃描產生（auto-improve）。請人工審核後決定是否實作。_
```

**Pseudocode 撰寫原則：**
- 不是完整實作，是清楚的改動藍圖
- 標注每個檔案的改動意圖（新增 / 修改 / 刪除）
- 型別定義寫完整 signature，函數 body 用註解描述邏輯
- 測試案例列出 test case 名稱和 assertion 重點

**批次建立**：用 sub-agent 平行建立所有 ticket（`model: "haiku"` — 純 JIRA 模板填充），每張建完回報 JIRA URL。

### 6. 彙整結果 + Slack 通知

所有 ticket 建完後，輸出摘要：

```
Auto Improve 掃描完成：

1. [TASK-123](https://your-domain.atlassian.net/browse/TASK-123) — [type-safety] 移除 api.ts 的 `as any`
   信心度：HIGH | 複雜度：LOW

2. [TASK-123](https://your-domain.atlassian.net/browse/TASK-123) — [dead-code] 移除未使用的 OldBanner.vue
   信心度：HIGH | 複雜度：LOW

共建 2 張 ticket，待人工審核。
（另有 1 個 finding 因已存在 ticket 而跳過）
```

若有指定 Slack channel，發送 mrkdwn 訊息：

```
:mag: *Auto Improve 掃描完成*
Repo：{repo_name}
時間：{YYYY-MM-DD}

• <{jira_url}|{ticket_key}> {summary} — {dimension} | {complexity}
• <{jira_url}|{ticket_key}> {summary} — {dimension} | {complexity}

共 {count} 張新 ticket 待審核（{skipped} 個已存在跳過）
```

## Do

- 每張 ticket 只描述一個問題，保持小顆粒度
- Pseudocode 要清楚到 RD 看完就能直接實作
- 只回報高信心度的 findings，寧可漏報不可誤報
- 讀取專案的 `.claude/rules/` 確保修正方案符合專案規範
- Ticket 描述清楚標註「AI 自動發現」
- 確認後才建 ticket，不要自動建
- 建完 ticket 後附完整 JIRA URL
- 建 ticket 前先查重，避免對同一問題重複開單

## Don't

- 不要直接開 PR 或修改程式碼 — 只建 ticket 描述問題和計畫
- 不要回報 LOW 信心度的 findings — 會造成 review 負擔
- 不要在一張 ticket 裡混合多個維度的問題
- 不要寫完整實作程式碼 — pseudocode 足以表達意圖
- 不要在 missing-tests 維度的計畫中修改 source code — 只規劃補測試
- 不要假設 API 或元件存在 — pseudocode 中標注需確認的依賴
- 不要掃描 node_modules、dist、.nuxt 等建置產出目錄
- 不要對已存在 auto-improve ticket 的問題重複開單
- review-lessons 聚合結果不開 JIRA ticket — 直接搬移或刪除 rules 檔案
- 不要在使用者確認前自動執行 review-lessons 的升級或清理操作
