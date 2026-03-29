---
name: review-inbox
description: >
  Two modes for discovering PRs that need the user's review in the user's GitHub org (read from workspace config `github.org`), then batch-reviewing them.
  **Label mode**: scans GitHub "need review" label.
  **Slack mode**: scans Slack channel posts for PR URLs (default 7 days, supports natural language time range).
  Both modes exclude the user's own PRs and identify: never reviewed, stale approve needing re-approve,
  or author replied to REQUEST_CHANGES comments (ready for re-review). PRs where the author hasn't
  replied to review comments are skipped (still working on fixes).
  Use this skill whenever the user mentions:
  Label mode (ONLY when explicitly mentioning "need review" label) — "掃 need review",
  "scan need review", "review inbox", "need review label".
  Slack mode (DEFAULT for everything else) — "review 大家的 PR", "review everyone's PRs",
  "review 所有 PR", "review all PRs", "幫我看所有要 review 的", "show me PRs to review",
  "批次 review", "batch review", "review all", "有哪些 PR 要我看", "which PRs need my review",
  "我該 review 哪些", "what should I review", "幫我 review 全部", "review all for me",
  "掃大家的 PR", "scan team PRs", "掃 PR", "scan PR", "幫我掃大家七天內的 PR",
  "scan team PRs from last 7 days", "幫我掃", "scan for me", "掃大家三天的 PR",
  "幫我掃大家的 PR", "scan everyone's PRs", or any phrase about reviewing/scanning team PRs
  with an optional time range. When in doubt, default to Slack mode — do NOT ask the user.
  Do NOT confuse with review-pr which reviews specific PRs the user provides.
metadata:
  author: Polaris
  version: 2.0.0
---

# Review Inbox — 批次 Review 待審 PR

找出 workspace config `github.org` 所設定的 org 下需要自己 review / re-approve 的 PR，批次執行 review 後發 Slack 通知。支援兩種來源模式：

| 模式 | 觸發詞 | PR 來源 |
|------|--------|---------|
| **Label 模式** | 僅限明確提到 label：「掃 need review」「review inbox」「need review label」 | GitHub `need review` label |
| **Slack 模式**（預設） | 其他所有觸發詞：「review 大家的 PR」「review 所有 PR」「幫我看所有要 review 的」「批次 review」「掃大家的 PR」「掃 PR」「幫我掃」「scan PR」等 | Slack channel 貼文中的 PR URL |

兩種模式共用相同的 review 狀態判定和後續 review 流程，只是 PR 發現來源不同。

## Defaults

| 參數 | 預設值 | 適用模式 | 說明 |
|------|--------|----------|------|
| GitHub username | 動態取得 | 兩者 | `gh api user --jq '.login'`，排除自己的 PR |
| Need review label | 見 `references/shared-defaults.md` | Label | 搜尋含此關鍵字的 label |
| Slack channel | 見 `references/shared-defaults.md` | 兩者 | Slack 模式的掃描來源 + 兩者的結果通知頻道 |
| Approval threshold | 見 `references/shared-defaults.md` | 兩者 | approve 門檻 |
| 時間範圍 | 7 天 | Slack | 從使用者語意判斷（「三天」→ 3，「這週」→ 到週一天數，無指定 → 7） |
| Batch size | 5 | 兩者 | 單次最多 review 幾個 PR，使用者可 override |
| 排序 | PR 建立時間升序 | 兩者 | 最早發出的 PR 優先被 review |

## Scripts

本 skill 包含三個 shell script 處理確定性邏輯，避免 LLM 重複組裝 API 查詢：

| Script | 用途 | 適用模式 | Input | Output |
|--------|------|----------|-------|--------|
| `scripts/scan-need-review-prs.sh` | 全 org 掃描 need review PR | Label | `--exclude-author <username>` | JSON array of PR objects |
| `scripts/fetch-prs-by-url.sh` | 從 PR URL 清單取得 PR metadata | Slack | stdin (每行一個 PR URL) + `--exclude-author <username>` | JSON array of PR objects（格式同上） |
| `scripts/check-my-review-status.sh` | 批次判斷每個 PR 的 review 狀態 | 兩者 | stdin (PR JSON) + `<username>` arg | JSON array with `review_status` field |

Script 路徑相對於本 SKILL.md 所在目錄。執行前確認有 `+x` 權限。

## Workflow

**前置步驟**：取得當前使用者的 GitHub username，後續步驟用 `$MY_USER`：

```bash
MY_USER=$(gh api user --jq '.login')
```

共用常數（PR channel、approval threshold、label）見 `references/shared-defaults.md`。

### 0. 判斷模式

根據使用者的觸發詞決定模式：

| 觸發詞 | 模式 | 說明 |
|--------|------|------|
| 「掃 need review」「review inbox」「need review label」 | **Label** | 明確提到 label 才走此模式 |
| 其他所有觸發詞（預設） | **Slack** | 「review 大家的 PR」「review 所有 PR」「幫我看所有要 review 的」「批次 review」「掃大家的 PR」「掃 PR」「幫我掃」「scan PR」等 |

**模式判斷規則**：預設走 **Slack 模式**（7 天）。只有使用者明確提到 `need review` label 相關詞彙（「掃 need review」「review inbox」「need review label」）才走 Label 模式。其他所有觸發詞（包括「review 大家的 PR」「幫我 review 全部」「review 所有 PR」等模糊詞）一律走 Slack 模式，不需詢問使用者。原因：團隊實務上 Slack channel 是 PR 的主要溝通管道，掃 channel 能涵蓋更完整的 PR 來源。

**Slack 模式的時間範圍**從使用者語意判斷，轉為 `oldest` Unix timestamp 供 `slack_read_channel` 使用：
- 「今天」「today」→ 當天 00:00 起算（`date -v0H -v0M -v0S +%s`）
- 「三天」「3 天內」→ 3 天前（`date -v-3d +%s`）
- 「這週」→ 從今天算到最近週一的天數
- 「兩週」→ 14 天前（`date -v-14d +%s`）
- 無指定 → 預設 7 天前（`date -v-7d +%s`）

### 1. 掃描 + 狀態判斷

#### Label 模式

用 bundled scripts 一次完成掃描和狀態判斷：

```bash
SKILL_DIR="$(dirname "$(readlink -f "$0")")"  # 或直接用 skill 的絕對路徑
"$SKILL_DIR/scripts/scan-need-review-prs.sh" --exclude-author $MY_USER \
  | "$SKILL_DIR/scripts/check-my-review-status.sh" $MY_USER
```

> **為什麼不用 `gh search prs`？**
> GitHub search index 不保證即時完整，實測會漏掉部分 repo（如 backend-api、mobile-app）。
> `scan-need-review-prs.sh` 逐 repo 掃描確保不遺漏。

#### Slack 模式

判斷完模式和時間範圍後，**立即**計算 `oldest` timestamp 並呼叫 `slack_read_channel`，不要有多餘的中間步驟：

```
1. 計算 oldest timestamp（見 Step 0 的時間範圍對照）
2. 呼叫 slack_read_channel({ channel_id: "{config: slack.channels.pr_review}", oldest: "<timestamp>", limit: 100 })
3. 從結果萃取 PR URL + 訊息 ts → pipe 到 bundled scripts 取得 review 狀態
```

**萃取 PR URL + 訊息 ts**：從訊息文字中用 regex parse 出 PR URL（`github\.com/{config: github.org}/[^/]+/pull/\d+`），去重後得到 URL 清單。同時建立 **PR URL → message ts** 對應表（後續 Step 5 回覆討論串用）：
- 若訊息帶 `thread_ts` 且 `thread_ts ≠ ts` → 用 `thread_ts`
- 否則用訊息自身的 `ts`

**取得 PR metadata + 狀態判斷**：將 URL 清單（每行一個）pipe 到 bundled scripts：

```bash
echo "$PR_URLS" \
  | "$SKILL_DIR/scripts/fetch-prs-by-url.sh" --exclude-author $MY_USER \
  | "$SKILL_DIR/scripts/check-my-review-status.sh" $MY_USER
```

`fetch-prs-by-url.sh` 自動過濾已關閉的 PR 和自己的 PR，輸出格式與 `scan-need-review-prs.sh` 相同。

#### 共用輸出格式

兩種模式的輸出 JSON 格式相同（每個 PR 附帶 `review_status`）：

```json
[
  {
    "repo": "your-repo-name",
    "number": 1800,
    "title": "feat: xxx",
    "url": "https://github.com/{config: github.org}/your-repo-name/pull/1800",
    "author": "alice",
    "created_at": "2026-03-01T00:00:00Z",
    "review_status": "needs_first_review",
    "review_detail": "首次 review"
  }
]
```

**`review_status` 值對照表**：

| review_status | 說明 | 動作 |
|---------------|------|------|
| `needs_first_review` | 從未 review 過 | 需要首次 review |
| `needs_re_approve` | approve 後作者有新 commit（stale） | 需要 re-approve |
| `needs_re_review` | REQUEST_CHANGES 後作者有回覆 review comments（不論有無新 push） | 需要 re-review |

> `valid_approve` 和 `waiting_for_author` 已被 script 自動過濾，不會出現在輸出中。
> `waiting_for_author` 包含：作者有新 push 但未回覆 review comments 的情況 — 視為還在改，不應再看。

若輸出為空 JSON array `[]`，告知使用者「目前沒有需要 review 的 PR」，流程結束。

### 3. 輸出待 review 清單，等待確認

顯示帶編號的清單：

```
| # | Repo | PR | Title | 作者 | 狀態 |
|---|------|----|-------|------|------|
| 1 | your-repo-a | #1800 | feat: xxx | alice | 首次 review |
| 2 | your-repo-b | #302 | fix: yyy | bob | ⚠️ 需 re-approve |
| 3 | your-repo-a | #1850 | refactor: zzz | charlie | 🔄 作者已修正並回覆，需 re-review |
```

- **排序**：按 PR 建立時間升序（最早發出的排最前面，優先被 review）
- **狀態欄**說明自己與該 PR 的關係，讓使用者快速判斷
- 表格下方附統計：首次 review X 個、re-approve Y 個、re-review Z 個

**Batch size 限制**：若符合條件的 PR 超過預設上限（5 個），表格仍列出全部，但提醒使用者：

> 共 N 個 PR 需要 review，建議先處理前 5 個（最早發出的），剩餘的下一輪再跑。

詢問使用者：

> 請輸入要 review 的 PR 編號（例如 `1,3` 或 `all`，輸入 `none` 跳過）：
> 建議一次不超過 5 個，使用者可自行決定要處理幾個。

**等待使用者確認後才開始 review。**

### 4. 批次執行 Review

使用者確認後，對選中的 PR 啟動批次 review。

依 PR 狀態決定 review 模式：
- **首次 review** → 正常 review 流程
- **需 re-approve** → 檢查自上次 approve 後的新 diff，若無實質變更直接 re-approve，有變更則 review 新的部分
- **需 re-review** → re-review 流程（檢查上一輪 comments 的修正狀況）

**執行方式**：用 review-pr 的批次模式，將所有選中的 PR URL 傳入。具體做法是將 PR URL 清單組成 prompt，觸發 review-pr 的多 PR 批次模式（Step 0 的「多 PR 輸入」）。

每個 PR 的 review 由獨立 sub-agent 平行執行，遵循 review-pr 的完整流程（讀 rules、審查 diff、提交 review）。

### 5. 彙整結果並發 Slack

所有 review 完成後，依模式決定 Slack 通知方式。

Result emoji（兩種模式共用）：
- APPROVE → ✅
- REQUEST_CHANGES → ❌
- COMMENT → 💬

每個 PR 的結果行後面附上 approve 狀況（與 review-pr Step 6a 相同邏輯）：
```
  目前 M/2 approve(s){，已達標可 merge / ，還需 N 位}
```

#### 5a. Label 模式 — 彙整訊息發到 channel

發一則彙整訊息到 PR channel（與過去行為相同）：

```
:clipboard: *批次 PR Review 完成*
時間：{YYYY-MM-DD}
Reviewer：{my_username}

*{repo_name}*
• <{pr_url}|#{number}> {title} (@{author}) — {result_emoji} *{APPROVE/REQUEST_CHANGES/COMMENT}*
  {如有 must-fix，簡述最關鍵的 1 個問題}
  目前 M/2 approve(s){，已達標可 merge / ，還需 N 位}

共 review {count} 個 PR：✅ {approve_count} 個 APPROVE、❌ {rc_count} 個 REQUEST_CHANGES、💬 {comment_count} 個 COMMENT
```

按 repo 分組，同 repo 的 PR 列在一起。

#### 5b. Slack 模式 — 回覆各自討論串，按作者分別留言

**不發彙整訊息到 channel**，改為回到每個 PR 的原始 Slack 討論串通知當事人。

**Step 5b-1：查找 GitHub username → Slack user ID**

收集所有已 review PR 的作者 GitHub username（去重），依序嘗試以下方式查找 Slack user ID：

**優先順序：**

1. **從 Step 1 的 Slack 訊息中比對**：PR 通常由作者本人或同事貼到 channel。若 Step 1a 讀到的訊息中，發文者提到的 PR 作者 GitHub username 與該訊息的 Slack user ID 能對應上（例如發文者就是 PR 作者），直接使用該 Slack user ID。這是最可靠的來源，因為資料已在手上，不需額外 API call。

2. **`slack_search_users` 搜尋 GitHub username**：
   ```
   slack_search_users({ query: "<github_username>" })
   ```
   GitHub username 有時與 Slack display name 不同，實測常搜不到。

3. **取 GitHub 使用者真名後再搜 Slack**：
   ```bash
   gh api users/<github_username> --jq '.name'
   ```
   取得真名（如 `鄒適齊`）後用 `slack_search_users` 搜尋。

4. **Fallback**：以上都找不到 → 用 `@{github_username}` 純文字顯示（不含 `<@U...>` mention）。

> **效能提示**：方式 1 幾乎不花成本（資料已在 Step 1 讀取的訊息中），優先使用。方式 2-3 需要額外 API call，只在方式 1 無法確認時才執行。

**Step 5b-2：按 (thread_ts, author) 分組**

用 Step 1b 建立的 PR URL → message ts 對應表，將 review 結果按 `(thread_ts, author)` 分組。同一個討論串中同一位作者的所有 PR 合成一則留言。

**Step 5b-3：發送 thread reply**

對每個 `(thread_ts, author)` 組合，用 `slack_send_message` 回覆到該討論串：

```
slack_send_message({
  channel_id: "<PR_CHANNEL_ID>",
  thread_ts: "<thread_ts>",
  message: "<留言內容>"
})
```

**留言格式（mrkdwn）：**

單一 PR：
```
<@U_ALICE> PR review 結果：
• <{pr_url}|#{number}> {title} — {result_emoji} *{APPROVE/REQUEST_CHANGES/COMMENT}*
  {如有 must-fix，簡述最關鍵的 1 個問題}
  目前 M/2 approve(s){，已達標可 merge / ，還需 N 位}
```

同作者多個 PR：
```
<@U_BOB> PR review 結果：
• <{pr_url_1}|#{number_1}> {title_1} — {result_emoji} *{RESULT}*
  {如有 must-fix，簡述}
  目前 M/2 approve(s){，已達標 / ，還需 N 位}
• <{pr_url_2}|#{number_2}> {title_2} — {result_emoji} *{RESULT}*
  {如有 must-fix，簡述}
  目前 M/2 approve(s){，已達標 / ，還需 N 位}
```

同一個討論串有 3 位不同作者 → 發 3 則獨立 thread reply，各自 mention 對應的作者。

> **注意**：`reply_broadcast` 不要設為 true，避免每則回覆都出現在 channel 主頁面造成洗版。

### 6. 對話中輸出摘要

Slack 發送後，在對話中輸出完整摘要：

```
批次 Review 完成：

1. #1800 (feat: xxx) — ✅ APPROVE
   目前 2/2 approves，已達標可 merge

2. #302 (fix: yyy) — ✅ RE-APPROVE
   目前 1/2 approves，還需 1 位

3. #1850 (refactor: zzz) — ❌ REQUEST_CHANGES (must-fix: 2)
   目前 0/2 approves
```

**Label 模式**附加：
```
已發送 Slack 彙整訊息到 #channel
```

**Slack 模式**附加：
```
已回覆 N 則 Slack 討論串（共通知 M 位作者）
```

## Do

- 用 bundled scripts 做掃描和狀態判斷，不要手動組裝 API 查詢
  - Label 模式：`scan-need-review-prs.sh` + `check-my-review-status.sh`
  - Slack 模式：`fetch-prs-by-url.sh` + `check-my-review-status.sh`
- 用 `gh api` 查 reviews（避免 `gh pr view` 的 encoding 問題）
- 列清單後等使用者確認才開始 review
- 每個 PR 的 review 結果都附上 approve 狀況
- re-approve 場景：若自上次 approve 後只有 CI/bot commit 無實質變更，直接 approve 不需重看整個 diff
- Slack 模式的時間範圍從使用者語意判斷，無指定時預設 7 天

## Don't

- 不要 review 自己的 PR — 發現自己的 PR 在清單中要自動排除
- 不要未經確認就開始 review — 使用者可能只想看清單
- 不要在 Slack 模式發彙整訊息到 channel — 改為回覆各自討論串通知當事人
- 不要在 Slack 模式的 thread reply 設 `reply_broadcast: true` — 避免洗版
- Label 模式仍合成一則彙整訊息發到 channel
- 不要在 re-approve 時留冗餘 comments — 若無新問題，簡潔 approve 即可
- 不要對已 REQUEST_CHANGES 但作者尚未回覆 comments 的 PR 再次 review — 即使有新 push 也應跳過，等作者回覆後再看
