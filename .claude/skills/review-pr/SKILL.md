---
name: review-pr
description: >
  Review someone else's PR as a code reviewer: read the PR diff, check against
  .claude/rules, leave inline comments on issues found, and submit a review with
  APPROVE or REQUEST_CHANGES. Use when: (1) user says "review PR", "review 這個 PR",
  "幫我 review", "review for me", "code review", (2) user shares a PR URL and asks
  to review it, (3) user says "看一下這個 PR", "take a look at this PR", "檢查 PR",
  "check this PR", "review pull request". This skill is
  for REVIEWING someone else's code — not for fixing review comments on your own PR
  (use engineering revision mode for that).
metadata:
  author: Polaris
  version: 2.0.0
---

# review-pr

以 reviewer 角色審查 PR，依據專案 `.claude/rules/` 規範檢查程式碼，留下 inline comments 並提交 review。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`github.org`、`slack.channels.ai_notifications`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## 0. 偵測輸入來源

### 從 Slack 訊息擷取 PR 連結

依 `references/slack-pr-input.md` 的流程從 Slack 訊息中擷取 PR URL。

保留的 Slack context（`slack_channel_id` 從 config `slack.channels.ai_notifications` 讀取、`slack_thread_ts`、`slack_source`）供 Step 7 使用。

> **批次 review 由 review-inbox 負責**：若使用者提供多個 PR，引導至 `review-inbox`（「掃 PR」）。本 skill 專注於單一 PR 的完整 review 流程。

## Scripts

本 skill 包含 shell script 處理確定性邏輯，避免 LLM 重複組裝 API 查詢：

| Script | 用途 | Input | Output |
|--------|------|-------|--------|
| `scripts/fetch-pr-info.sh` | 取得 PR 完整資訊（metadata + files + re-review 偵測 + approval 狀態） | `<owner/repo> <pr_number> [--my-user <username>]` | JSON object |

Script 路徑相對於本 SKILL.md 所在目錄。執行前確認有 `+x` 權限。

## 1. Parse PR Number & 辨識對應專案

依 `references/pr-input-resolver.md` 的流程解析 PR 資訊並定位本地專案路徑。

本 skill 為唯讀 review，若本地找不到 repo 目錄，啟用 `remote_mode: true` 改用 GitHub API 遠端讀取（詳見 reference doc）。

後續讀取程式碼時，以解析出的專案路徑為根目錄。

## 2. Fetch PR Information

用 bundled script 一次取得 PR 完整資訊（metadata + files + re-review 偵測 + approval 狀態）：

```bash
SKILL_DIR="$(dirname "$(readlink -f "$0")")"  # 或直接用 skill 的絕對路徑
"$SKILL_DIR/scripts/fetch-pr-info.sh" {owner}/{repo} {pr_number} --my-user {my_username}
```

**輸出 JSON 格式**：

```json
{
  "repo": "{org}/{repo}",
  "number": 1882,
  "title": "feat: xxx",
  "author": "alice",
  "base": "develop",
  "head": "feat/xxx",
  "file_count": 5,
  "total_additions": 120,
  "total_deletions": 30,
  "total_changes": 150,
  "review_strategy": "single",
  "is_re_review": false,
  "my_review_count": 0,
  "my_last_review_state": "",
  "files": [...],
  "all_reviews": [...],
  "pushed_at": "2026-03-15T00:00:00Z"
}
```

### 根據 script 輸出決定流程

- `is_re_review: true` → 自動切換到 **Re-review 模式**（跳至「Re-review 模式」章節）
- `is_re_review: false` → 繼續正常 review 流程
- `review_strategy: "batch"` → 進入分批 review 模式（見下方）
- `review_strategy: "single"` → 直接取得完整 diff

#### 單一 review 模式

直接取得完整 diff，進入 Step 3：

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number} -H "Accept: application/vnd.github.v3.diff"
```

#### 分批 review 模式（Sub-Agent）

當 PR 太大時，依照以下流程分批 review：

**Step A — 過濾與分組檔案**

先排除不需 review 的檔案：
- lock files（`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`）
- generated code（`*.generated.ts`, `*.gen.ts`）
- 純刪除檔案（`status: removed` 且無新增行）

將剩餘檔案依 **目錄相關性** 分組，每組總變更行數控制在 600 行以內。分組原則：
1. 同目錄的檔案優先放同一組
2. 相關聯的檔案放同一組（例如 component + 對應的 test, hook + 使用該 hook 的元件）
3. 若單一檔案超過 600 行，該檔案獨立一組

**Step B — 平行啟動 sub-agent**

為每一組檔案啟動一個 sub-agent（使用 Agent tool），**所有 sub-agent 同時平行啟動**：

每個 sub-agent 的 prompt 需包含：
1. PR 基本資訊（標題、描述、作者、base branch）
2. 該組檔案的 diff（用 `gh api` 取得完整 diff 後擷取該組檔案的部分，或用 `gh pr diff <number> -- <file1> <file2> ...` 取得特定檔案的 diff）
3. 專案規範（`.claude/rules/` 內容）— 將規範內容直接嵌入 prompt 中
4. **已指出問題清單**（Step 3.5 產出）— 嵌入 prompt 中，指示 sub-agent 跳過語意相同的問題
5. 專案根目錄路徑
6. review 維度與嚴重程度定義（見下方 Step 4b、4c）
7. 明確指示：只做 research（讀檔案、分析程式碼），不要編輯任何檔案、不要提交 review

每個 sub-agent 的 prompt 範本：

```
你是 PR code reviewer。請 review 以下檔案的變更。

## PR 資訊
- PR: #{number} {title}
- 作者: {author}
- 描述: {body}
- Base branch: {baseRefName}

## 專案規範
{rules_content}

## Repo Handbook（coding 準則，全文遵守）
{handbook_content}
（若 handbook 不存在則省略此區塊）

## 你負責的檔案
{該組檔案清單}

## Diff
{該組檔案的 diff 內容}

## 已指出的問題（其他 reviewer 已留言，不要重複）
{existing_comments_summary}

## Review 指示
1. 讀取每個變更檔案的完整原始碼（路徑: {project_root}/{filename}）以理解上下文
2. 依據以下維度審查：正確性、型別安全、規範遵循、安全性、效能、可維護性
3. 將問題分類為 must-fix / should-fix / nit
4. 不要讀取或 review 不在你負責清單中的檔案
5. 跳過「已指出的問題」清單中語意相同的問題，只留全新發現

## 輸出格式
請以 JSON 格式回傳結果（純文字，不要用 code block）：
{
  "comments": [
    {
      "path": "檔案路徑",
      "line": 行號（diff 中新檔案的行號）,
      "severity": "must-fix|should-fix|nit",
      "body": "comment 內容（含嚴重程度標籤、問題描述、規範引用、建議修改）"
    }
  ],
  "summary": "這組檔案的整體評價（1-2 句）
}

使用 Completion Envelope 格式（見 `skills/references/sub-agent-roles.md`）：
- Summary ≤ 3 句（findings 總結）
- Detail 寫入 `/tmp/polaris-agent-{timestamp}.md`（完整 JSON comments 陣列）
```

**Step C — 彙整結果**

收集所有 sub-agent 回傳的結果後：
1. 合併所有 comments 到一個陣列
2. 合併所有 summary 作為整體 review summary 的素材
3. 進入 Step 5 提交統一的 review

## 3. Read Project Rules

讀取對應專案的 `.claude/rules/` 目錄下的規範檔案：

**本地模式**（預設）：
```bash
ls {base_dir}/{repo}/.claude/rules/
```

**遠端模式**（`remote_mode: true`）：
```bash
# 列出規範檔案
gh api repos/{owner}/{repo}/contents/.claude/rules?ref={headRefName} --jq '.[].name'
# 讀取各規範檔案
gh api repos/{owner}/{repo}/contents/.claude/rules/{filename}?ref={headRefName} --jq '.content' | base64 -d
```

讀取所有規範檔案，作為 review 依據。常見規範類型包含：型別安全、專案架構、狀態管理、API 開發、格式化、命名、元件開發等。若 `.claude/rules/` 不存在（本地或遠端皆無），則僅依通用審查維度進行 review。

**Repo Handbook 是 review 的 primary standard**：若 `{base_dir}/{repo}/.claude/rules/handbook/` 存在，讀取 `index.md` + 所有子檔案。Handbook 記錄了 repo 的架構、慣例、coding 準則 — review 時全文遵守。符合 handbook 的 pattern 不應被 flag，違反 handbook 的 pattern 應指出。若 handbook 不存在，跳過此步驟。

**重要**：如果是分批 review 模式，規範內容需要在 Step 2 的 Step B 中嵌入各 sub-agent 的 prompt，因此在此步驟就要完成讀取。

## 3.5 讀取既有 Review Comments（去重用）

在開始審查之前，先讀取 PR 上已有的 review comments，避免重複指出其他 reviewer（人類或 AI）已經提過的問題。

### 取得既有 comments

```bash
# 取得所有 review comments（inline comments）
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments --paginate \
  --jq '.[] | {path: .path, line: .original_line, body: .body, user: .user.login}'

# 取得所有 review body（頂層 review 意見）
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews --paginate \
  --jq '.[] | select(.body != "" and .body != null) | {body: .body, user: .user.login, state: .state}'
```

### 建立「已指出問題清單」

從 comments 中提取每個問題的核心語意（哪個檔案、哪段程式碼、什麼問題），建立一份去重參考清單。

### 審查時的去重規則

在 Step 4 審查時，對每個發現的問題，比對「已指出問題清單」：

| 情境 | 動作 |
|------|------|
| 同一檔案、同一位置、語意相同的問題已被指出 | **跳過**，不留 comment |
| 同一檔案、不同位置但相同 pattern 的問題（如「多處缺少 error handling」），已有人在其中一處指出 | **跳過**，除非其他位置有更嚴重的影響（如安全漏洞） |
| 問題被提出但 reviewer 的分析有誤或遺漏關鍵面向 | **留 comment**，補充遺漏的面向（不重複已說的部分） |
| 全新的問題，無人提過 | **正常留 comment** |

**核心原則**：已經有人說過的事不需要再說一遍。AI review 的價值在於發現別人沒看到的問題，不是附和已有的意見。

**分批 review 模式**：在 Step 2 的 Step B sub-agent prompt 中，將「已指出問題清單」一併嵌入，讓各 sub-agent 都能去重。

## 4. Review Each Changed File

> **注意**：如果已採用分批 review 模式（Step 2 的 sub-agent 流程），此步驟由各 sub-agent 分別執行，主 agent 跳至 Step 5 彙整結果。

對每個變更檔案進行審查：

### 4a. 讀取完整檔案與 diff

**本地模式**（預設）：
```bash
# 讀取檔案完整內容（理解上下文）
Read tool: {base_dir}/{repo}/<filename>
```

**遠端模式**（`remote_mode: true`）：
```bash
# 從 GitHub 讀取 PR branch 上的檔案內容
gh api repos/{owner}/{repo}/contents/{filename}?ref={headRefName} --jq '.content' | base64 -d
```

對照 diff 中的變更進行審查。

### 4b. 審查維度

依據 `.claude/rules/` 規範，檢查以下面向：

| 維度 | 檢查內容 |
|------|---------|
| **正確性** | 邏輯是否正確、邊界條件、null/undefined 處理 |
| **型別安全** | TypeScript 型別是否正確、有無 any、型別斷言是否合理 |
| **規範遵循** | 是否符合 `.claude/rules/` 中定義的專案規範 |
| **安全性** | XSS、injection、敏感資料暴露 |
| **效能** | 不必要的 re-render、大量迴圈、記憶體洩漏風險 |
| **可維護性** | 命名清晰度、函式大小、重複程式碼 |
| **無障礙性** | ARIA 屬性、語意化 HTML、鍵盤操作 |
| **跨檔案一致性** | 元件 props 是否在 stories/docs/tests 中都有對應覆蓋 |
| **PR 描述一致性** | 描述的行為、命名、API 是否與實際程式碼一致 |

### 4b-1. 檢查既有 codebase 慣例

新增元件或模組時，先查看 1-2 個同類型既有實作：
- 新增 Vue 元件 → 看類似元件（Options API vs `<script setup>`、props 風格）
- 新增 API endpoint → 看同 router 下的錯誤處理、驗證方式
- 新增 test → 看同目錄下的測試風格與覆蓋深度

若偏離既有慣例，在 comment 標註（尊重團隊可能正在遷移，標為 nit 而非 must-fix）。

### 4c. 分類問題嚴重程度

| 等級 | 定義 | 範例 |
|------|------|------|
| **must-fix** | 會造成 bug、安全漏洞、或違反關鍵規範 | 型別錯誤、XSS、race condition |
| **should-fix** | 不影響功能但違反規範或最佳實踐 | 命名不一致、缺少錯誤處理 |
| **nit** | 風格建議，不影響功能和規範 | 更好的寫法建議、排版 |

### 4d. Severity Calibration 注意事項

| 情境 | 最高嚴重程度 | 說明 |
|------|-------------|------|
| API payload key 命名與相鄰方法不一致 | **should-fix** | 不同 API endpoint 可能有不同 contract，不可在未驗證 API spec 的情況下標為 must-fix。應建議作者確認 API 文件，若有 `@see` 連結則引用 |
| 僅基於「其他地方都這樣寫」的推論 | **should-fix** | 一致性問題不等於正確性問題，除非有明確規範要求 |
| 無法從 diff 或原始碼直接驗證的外部行為假設 | **should-fix** | 例如「後端 API 會拒絕」「第三方服務不支援」——無法驗證的推測不應標為 must-fix，改為 should-fix 並請作者確認 |
| 語言 / 函式庫行為推論（regex、array 方法、framework 預設值等） | **未驗證前 should-fix；驗證後才可升 must-fix** | 須用 Node REPL / MDN / 官方文件當場實測再下判斷。無法驗證 → should-fix 並請作者確認。誤判範例：JS regex `[^}]+` 在無 `s` flag 下仍可跨行匹配（character class 不受 dotAll 影響），反向宣稱「缺 `s` flag」為 bug 是錯誤 — 這類錯誤若已送出 REQUEST_CHANGES 會卡住作者 merge |

**核心原則**：must-fix 必須是「從程式碼可直接證明會出錯」的問題（型別錯誤、null dereference、XSS）。基於推測或慣例推論的問題，最多 should-fix。語言/函式庫特性（regex、array 方法、framework 預設等）若未當場驗證，同樣最多 should-fix。

## 5. Compose & Submit Review

### 5.0 Workspace language policy gate

完整規則見 `references/workspace-language-policy.md`；本段只定義 review-pr 的接入點。

Review 產物的語言以 PR description / thread 的主要語言為準；若無法判斷，fallback 到
root `workspace-config.yaml language`。送出 review body 與 inline comments 前，先把最終文字
寫成暫存 markdown，執行同一支 gate：

```bash
bash scripts/validate-language-policy.sh \
  --advisory \
  --mode artifact \
  --language "<pr_primary_language_or_workspace_language>" \
  <review-output.md>
```

第一版先 advisory，避免誤擋必要引用：原 PR 英文描述、程式碼符號、error message、
GitHub suggestion block、以及作者原文。升級成 blocking 的條件：PR-language 偵測穩定、
suggestion block / code quote stripping 穩定，且連續 release 無 false positive。即使 advisory，
reviewer 自己撰寫的問題描述與 summary 仍必須跟隨上述語言決策。

### 5a. 組裝 review comments

將所有問題整理為 inline review comments：

```bash
# 使用 GitHub API 提交 review（含 inline comments）
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews \
  --method POST \
  --input - <<'EOF'
{
  "event": "<APPROVE|REQUEST_CHANGES|COMMENT>",
  "body": "<review_summary>",
  "comments": [
    {
      "path": "<file_path>",
      "line": <line_number>,
      "body": "<comment_body>"
    },
    {
      "path": "<file_path>",
      "start_line": <start_line>,
      "line": <end_line>,
      "body": "<multi_line_comment>"
    }
  ]
}
EOF
```

- **單行 comment**：只需 `line`
- **多行 comment**：`start_line` + `line`（適用建議重構一個 function 等跨多行情況）

### 5b. 判斷 Review Action

| 條件 | Review Action |
|------|--------------|
| 無任何問題 | **APPROVE** |
| 只有 nit 等級的建議 | **APPROVE**（附帶建議 comments） |
| 有 should-fix 但無 must-fix | **COMMENT**（不擋 merge，但建議修正） |
| 有任何 must-fix | **REQUEST_CHANGES**（擋 merge，必須修正） |

### 5c. Review Summary 格式

#### APPROVE

```markdown
LGTM! 程式碼品質良好，符合專案規範。

<如有 nit 建議，在此簡述>
```

#### COMMENT

```markdown
整體方向正確，有幾個建議可以改善：

- should-fix: N 個（建議修正但不擋 merge）
- nit: M 個

詳見各 inline comment。
```

#### REQUEST_CHANGES

```markdown
有 N 個問題需要修正：

**Must-fix:**
- <簡述各 must-fix 問題>

**Should-fix:**
- <簡述各 should-fix 問題>

詳見各 inline comment。
```

### 5d. Inline Comment 格式

自然描述問題，根據情境選擇格式：

**帶 Suggested Change（優先使用）** — 讓作者一鍵 apply：

````markdown
<問題描述>

```suggestion
<替換後的程式碼，取代 comment 所在行範圍>
```
````

注意：suggestion 內容取代 `line`（或 `start_line`~`line`）指定的行範圍；確保縮排完全一致；一個 comment 只能有一個 suggestion block。

**純 Comment** — 無法用 suggestion 表達時：

```markdown
**[must-fix]** / **[should-fix]** / **[nit]**

<問題描述>

<如果有，引用 `.claude/rules/` 中的具體規範>

建議修改：
<具體建議或程式碼片段>
```

### 5d-1. 何時用 Suggested Change vs 純 Comment

| 情境 | 格式 |
|------|------|
| 修改既有程式碼（加 prop、改寫法、修 bug） | **Suggested Change** |
| 缺少某些東西（缺測試、缺文件） | **純 Comment** |
| 架構性建議（如 component 拆分方向） | **純 Comment** |
| 多處需要同樣修改 | 第一處用 **Suggested Change**，其餘引用「同上」 |

## 6. Output Summary

完成後，先查詢該 PR 目前的 approve 狀況，再輸出摘要報告。

### 6a. 查詢 PR Approve 狀態

```bash
# 取得所有 reviews
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews \
  --jq '.[] | {user: .user.login, state: .state, submitted_at: .submitted_at}'

# 取得最後 push 時間（判斷 stale）
gh api repos/{owner}/{repo}/pulls/{pr_number} --jq '.head.repo.pushed_at'
```

計算每位 reviewer 的狀態：
- **valid approve**：APPROVED 且 submitted_at > pushed_at
- **stale approve**：APPROVED 但 submitted_at < pushed_at（需 re-approve）
- **request changes**：最新 review 為 REQUEST_CHANGES

### 6b. 輸出摘要

```
PR Review 報告：
- PR: #<number> (<title>)
- 作者: <author>
- Review 結果: APPROVE / COMMENT / REQUEST_CHANGES
- must-fix: X 個
- should-fix: Y 個
- nit: Z 個

PR Approve 狀況：目前 M/2 valid approve(s)
- username1 ✅ 已 approve
- username2 ⚠️ 需 re-approve（approve 後有新 push）
- 還需 N 位同仁 review
```

這讓 PR 作者和 reviewer 都能快速判斷下一步：誰需要重按 approve、還差幾票、不用多看。

若輸入來源為 Slack（`slack_source: true`），接續執行 Step 7。

## 6.5 Review 發現 → Handbook 校準（Standard-First）

在輸出摘要後，分析本次 review 中**自己留下的 review comments**，判斷是否有值得寫入 repo handbook 的 coding pattern。

### 核心原則：Standard First

Review 中發現的 repo-specific pattern 應**直接寫入 handbook**。Handbook 是 repo 的 coding 準則 — 發現新 pattern 就更新標準，下次 review 或開發直接按新標準走。

### 萃取判斷

**值得寫入 handbook** 的 comment：
- 框架慣用法（Vue / Nuxt / TypeScript 的正確用法）
- Error handling 慣例
- 型別安全 pattern
- 效能決策（避免不必要的 re-render、記憶體洩漏等）
- 測試撰寫慣例
- 元件設計原則

**排除**（不寫入）：
- typo、漏 import、copy-paste 錯誤
- 純格式問題（縮排、換行）
- 只適用特定業務邏輯的單次性問題
- nit 等級的風格建議（非規範要求）

若本次 review **沒有任何**符合條件的 comment，跳過此步驟，不輸出任何訊息。

### 分類與寫入

依 `repo-handbook.md` § Step 3b 的三層分類：

| 分類 | 目標 | 範例 |
|------|------|------|
| Repo-specific | `{repo}/.claude/rules/handbook/` 子文件 | Vue SFC 命名慣例、API error format |
| Company-level | `rules/{company}/handbook/` 子文件 | 跨 repo 的 changeset 規則 |
| Framework | feedback memory（確認後直接寫入 rule） | Polaris skill routing 行為 |

**寫入前去重**：比對 handbook 既有內容 + `rules/` 檔案，語意相同則跳過。

### 衝突處理（Standard-First Calibration）

如果 review 中留的 comment 被 PR author 推回（不同意、不改），**不要自行判斷誰對誰錯**。暫停並回報 Strategist：

```
Review 衝突：
- 我的 comment：「{comment 摘要}」
- Author 回覆：「{回覆摘要}」
- Handbook 現狀：{有涵蓋/沒涵蓋}

請確認：(a) 更新 handbook 配合 author → 我撤回 comment
        (b) 堅持 → 我回覆請 author 修改
```

User 確認後：
- **(a)** → 更新 handbook → 下次 review 按新標準
- **(b)** → 回覆 author，不更新 handbook

### 完成後輸出（僅有寫入 handbook 時）

```
Handbook 更新：
- 寫入 {base_dir}/{repo}/.claude/rules/handbook/{file}.md：{pattern 摘要}
```

### Reverse Sync（靜默）

寫入 handbook 後，執行 reverse-sync：

```bash
{base_dir}/polaris-sync.sh --reverse {project-name}
```

## 7. Slack 通知（僅當輸入來源為 Slack 時）

若 Step 0 標記了 `slack_source: true`，在 GitHub review 提交完成後，回覆原始 Slack thread 通知 PR 作者。

### 7a. 查找 PR 作者的 Slack 帳號

依 `references/github-slack-user-mapping.md` 的 lookup chain 查找 PR 作者的 Slack user ID（跳過 Step 1 context match，從 Step 2 開始）。

### 7b. 組裝 Slack 訊息

訊息格式（使用 Slack mrkdwn）：

```
📋 *PR Review 完成*

<{pr_url}|#{number} {title}>
✅ 結果: *APPROVE* / ❌ *REQUEST_CHANGES* / 💬 *COMMENT*

• must-fix: X 個
• should-fix: Y 個
• nit: Z 個

{如有 must-fix，簡述最重要的 1-2 個問題}

<@{author_slack_user_id}> 請查看 review comments 🙏
```

### 7c. 發送 Slack 訊息

使用 `slack_send_message` MCP tool，回覆到原始 thread：

```
slack_send_message({
  channel_id: "<slack_channel_id>",
  thread_ts: "<slack_thread_ts>",
  text: "<組裝好的訊息>"
})
```

**重要**：必須帶 `thread_ts` 回覆在原始訊息的 thread 中，不要發成獨立訊息。

## Re-review 模式

當使用者提到 re-review、已修正、請重新 review 時，切換到 re-review 模式：

1. **重新取得最新 diff**（`gh api repos/{owner}/{repo}/pulls/{number}/files`）— 作者可能已 push 修正，必須用最新 diff 判斷問題是否已修正，不可沿用首次 review 時的快取 diff
2. 用 GitHub API 讀取上一輪的 review comments
3. 讀取作者對每個 comment 的回覆
4. 逐一確認每個 comment 的處理狀況（**對照最新 diff 判斷**）：
   - 已修正 → 回覆確認 ✅
   - 作者回覆不調整並附理由 → **評估理由是否合理**，合理則接受並回覆認同，不合理則在該 comment thread 留言說明
   - 未修正也未回覆 → 標記未修正 ❌
   - ⚠️ **回覆前先檢查該 comment thread 是否已有自己（reviewer）的確認回覆**，若已回覆過且狀況未變則跳過，避免重複留言
5. 只有真正新發現的問題才留新的 inline comment
6. **判斷是否 re-approve**：
   - 上一輪所有 must-fix 皆已修正（或理由合理已接受）**且** 本輪無新的 must-fix → 提交 **APPROVE** review
   - 仍有未解決的 must-fix 或本輪發現新的 must-fix → 提交 **REQUEST_CHANGES**
   - 上一輪僅有 should-fix / nit 且皆已處理 → 提交 **APPROVE**
   - ⚠️ 提交 review 前告知使用者判斷結果與理由，確認後再送出
   - **Review body 簡潔即可**，不要重複總結各 thread 已回覆的內容。範例：
     - APPROVE: `"LGTM, 上一輪的問題都已修正 👍"`
     - REQUEST_CHANGES: `"還有 N 個 must-fix 未解決，詳見各 thread"`

**重要**：re-review 不是重新審一遍留一堆新 comment，而是確認上一輪修正狀況。作者有權對建議提出不同意見，reviewer 應判斷其理由是否成立。

### Re-review 後自動學習

Re-review 流程的 Step 3 完成後（所有 comment 處理狀況已確認），自動執行以下學習流程：

**Step A — 提取學習點**

從 re-review 過程中，找出以下類型的回饋：

| 情境 | 學習類型 | 記錄動作 |
|------|---------|---------|
| 作者回覆「不調整」且理由合理，reviewer 接受 | **False Positive** | 記錄該 pattern 為不應報的情況 |
| 作者修正了，但修正方式與建議不同且更好 | **Better Pattern** | 記錄為 accepted pattern |
| reviewer 自己發現上一輪 comment 確實過度嚴格（severity 太高） | **Severity Calibration** | 記錄嚴重程度校準 |

若本輪 re-review **沒有任何**上述情況（例如作者全部照建議修正），則跳過學習步驟。

**Step B — 寫入 review-learnings.md**

學習點寫入對應專案的 `{base_dir}/{repo}/.claude/rules/review-learnings.md`。

若檔案不存在，建立新檔案：

```markdown
# Review Learnings

從歷次 PR review 回饋中累積的經驗，避免重複誤報。
Review 時請參考此檔案，對列出的 pattern 不要重複報告。

## False Positives（不應報的情況）

## Accepted Patterns（專案允許的寫法）

## Severity Calibration（嚴重程度校準）
```

若檔案已存在，在對應分類下追加新條目。每個條目格式：

```markdown
- [YYYY-MM-DD] PR #<number>: <簡述情境>（原因：<作者理由或 reviewer 反思>）
```

**Step C — 去重與清理**

寫入前檢查是否已有**語意相同**的條目（同一種 pattern 不需重複記錄）。若已存在，跳過不寫入。

若同一分類下條目超過 20 條，將相似的條目合併為一條通用規則。例如：
- 多條「XXX 副檔名是刻意的」→ 合併為「副檔名選擇是刻意的技術決策，不需建議更改」

**Step D — 輸出學習摘要**

在 re-review 報告最後附上學習摘要（僅有新學習點時才顯示）：

```
📝 Review 學習更新：
- 新增 N 條 false positive 記錄
- 新增 M 條 accepted pattern
- 新增 K 條 severity calibration
- 已寫入 {base_dir}/{repo}/.claude/rules/review-learnings.md
```

## Do / Don't

- Do: 仔細閱讀 PR description 理解改動意圖，再開始 review
- Do: 核對 PR description 與實際程式碼是否一致（命名、API、行為描述）
- Do: 依據 `.claude/rules/` 規範給出具體、可行的建議
- Do: 區分問題嚴重程度（must-fix / should-fix / nit），讓作者知道優先順序
- Do: 盡量使用 GitHub suggested change，讓作者一鍵 apply
- Do: 給出具體修改建議或程式碼片段，而非只說「這裡有問題」
- Do: 肯定好的設計決策，review 不是只挑毛病
- Do: 檢查跨檔案一致性（元件 props 是否在 stories、docs、tests 中都有覆蓋）
- Do: 查看同類型既有元件/模組了解專案慣例，標註偏離之處
- Don't: 對風格偏好（非規範要求）使用 must-fix 或 should-fix
- Don't: 建議大規模重構，review 範圍限於 PR 變更內容
- Don't: review 自動產生的檔案（如 lock files、generated code）
- Don't: 對 PR description 中已說明的已知限制重複提出
- Don't: 重複指出其他 reviewer（人類或 AI）已經留言過的問題——AI review 的價值在於發現別人沒看到的
- Don't: 所有 comment 都用嚴格模板——自然描述問題，重點是有幫助

## Prerequisites

- `gh` CLI installed and authenticated
- 本地 clone 搜尋順序：`./` → `{base_dir}/{repo}`（從 workspace config 取得）。找不到時告知使用者，不 silently fallback 到 hardcoded 路徑。


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
