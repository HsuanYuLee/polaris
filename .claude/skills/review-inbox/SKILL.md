---
name: review-inbox
description: "Use when the user wants to discover and review PRs across the team awaiting their attention. NOT for a single specific PR (use review-pr). Supports three discovery modes: Label (GitHub label scan), Slack (channel-wide scan), Thread (specific Slack thread URL). Trigger: '掃 PR', 'review 大家的 PR', '批次 review', '有哪些 PR 要我看', Slack thread URL + review intent ('review <slack_url>', '幫我看這串'). Key: '我的 PR' → check-pr-approvals; '大家的 PR' / Slack URL → here; single PR URL → review-pr."
metadata:
  author: Polaris
  version: 2.1.0
---

# Review Inbox — 批次 Review 待審 PR

找出 workspace config `github.org` 所設定的 org 下需要自己 review / re-approve 的 PR，批次執行 review 後發 Slack 通知。支援兩種來源模式：

| 模式 | 觸發詞 | PR 來源 |
|------|--------|---------|
| **Label 模式** | 僅限明確提到 label：「掃 need review」「review inbox」「need review label」 | GitHub `need review` label |
| **Slack 模式**（預設） | 其他所有觸發詞：「review 大家的 PR」「review 所有 PR」「幫我看所有要 review 的」「批次 review」「掃大家的 PR」「掃 PR」「幫我掃」「scan PR」等 | Slack channel 貼文中的 PR URL |
| **Thread 模式** | 使用者提供 Slack thread URL + review 意圖：「review <slack_url>」「幫我看這串」「這串 PR review 一下」 | 指定 Slack 討論串中的 PR URL |

三種模式共用相同的 review 狀態判定和後續 review 流程，只是 PR 發現來源不同。

## Defaults

| 參數 | 預設值 | 適用模式 | 說明 |
|------|--------|----------|------|
| GitHub username | 動態取得 | 兩者 | `gh api user --jq '.login'`，排除自己的 PR |
| Need review label | 見 `references/shared-defaults.md` | Label | 搜尋含此關鍵字的 label |
| Slack channel | 見 `references/shared-defaults.md` | 兩者 | Slack 模式的掃描來源 + 兩者的結果通知頻道 |
| Approval threshold | 見 `references/shared-defaults.md` | 兩者 | approve 門檻 |
| 時間範圍 | 7 天 | Slack | 從使用者語意判斷（「三天」→ 3，「這週」→ 到週一天數，無指定 → 7） |
| Batch size | `skill_defaults.review-inbox.batch_size`（預設 5，0 = 不限） | 兩者 | 單次最多 review 幾個 PR，0 = 全部 review |
| Concurrency | `skill_defaults.review-inbox.concurrency`（預設 5） | 兩者 | 同時平行幾個 review sub-agent，避免機器過載 |
| 排序 | PR 建立時間升序 | 兩者 | 最早發出的 PR 優先被 review |
| Confirm | `skill_defaults.review-inbox.confirm`（預設 `false`） | 兩者 | `false` = 列完清單直接全跑，`true` = 等使用者選編號 |

## Scripts

本 skill 包含多個 script 處理確定性邏輯，避免 LLM 重複組裝 API 查詢：

| Script | 用途 | 適用模式 | Input | Output |
|--------|------|----------|-------|--------|
| `scripts/scan-need-review-prs.sh` | 全 org 掃描 need review PR | Label | `--exclude-author <username>` | JSON array of PR objects |
| `scripts/fetch-prs-by-url.sh` | 從 PR URL 清單取得 PR metadata | Slack | stdin (每行一個 PR URL) + `--exclude-author <username>` | JSON array of PR objects（格式同上） |
| `scripts/check-my-review-status.sh` | 批次判斷每個 PR 的 review 狀態 | 兩者 | stdin (PR JSON) + `<username>` arg | JSON array with `review_status` field |
| `scripts/extract-pr-urls.py` | 從 Slack MCP output 或 Slack Web API JSON 確定性提取 PR URL + thread mapping | Slack / Thread | stdin (Slack JSON) + `--org <org>` + 可選 `--thread-ts <ts>` | stdout: PR URLs (一行一個); side: `--mapping` JSON file |
| `scripts/slack-webapi.sh` | Slack MCP 失敗時的 CLI fallback（讀 channel/thread、發訊息） | Slack / Thread | `SLACK_BOT_TOKEN` + subcommand args | Slack Web API JSON |

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
| 含 Slack thread URL（`*.slack.com/archives/...`） | **Thread** | URL 中有 `thread_ts` 參數 |
| 「掃 need review」「review inbox」「need review label」 | **Label** | 明確提到 label 才走此模式 |
| 其他所有觸發詞（預設） | **Slack** | 「review 大家的 PR」「review 所有 PR」「幫我看所有要 review 的」「批次 review」「掃大家的 PR」「掃 PR」「幫我掃」「scan PR」等 |

**模式判斷規則**：

1. **Thread 模式**優先：使用者訊息中含 Slack URL（`https://*.slack.com/archives/<channel_id>/p<msg_ts>?thread_ts=<thread_ts>&cid=<channel_id>`）→ Thread 模式。從 URL 解析：
   - `channel_id`：路徑中 `/archives/` 後的 segment（或 `cid` query param）
   - `thread_ts`：`thread_ts` query param（即討論串 parent message 的 timestamp）
   - 若 URL 沒有 `thread_ts` 參數（不是討論串連結），取路徑中的 `p<msg_ts>`，將 `p` 去掉並在倒數第六位插入小數點（`p1776130982981829` → `1776130982.981829`），作為 `message_ts` 使用
2. **Label 模式**：使用者明確提到 `need review` label 相關詞彙
3. **Slack 模式**（預設）：其他所有觸發詞。團隊實務上 Slack channel 是 PR 的主要溝通管道，掃 channel 能涵蓋更完整的 PR 來源

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
> GitHub search index 不保證即時完整，實測會漏掉部分 repo（如 repo-a、repo-b）。
> `scan-need-review-prs.sh` 逐 repo 掃描確保不遺漏。

#### Slack 模式（sub-agent 委派）

Slack 模式的掃描（MCP 讀取 + URL 萃取 + PR 狀態查詢）**整包委派給 sub-agent**，主 session 只收到 filtered PR JSON。這樣 Slack 原始訊息不進入主 context，留給 review 階段使用。

若 Slack MCP tool 失敗（timeout / unavailable / auth error），改走 CLI fallback：
- 使用 `scripts/slack-webapi.sh read-channel ...` 讀取訊息
- 後續 pipeline 不變（`extract-pr-urls.py` 已支援 Web API JSON）
- 需要環境變數 `SLACK_BOT_TOKEN`（bot token）

**Strategist 計算好參數後，dispatch 一個 `standard_coding` sub-agent**，prompt 包含：

1. `oldest` timestamp（見 Step 0 的時間範圍對照）
2. Slack channel ID（`{config: slack.channels.pr_review}`）
3. GitHub org（`{config: github.org}`）
4. `$MY_USER`（GitHub username）
5. Script 絕對路徑（`$SKILL_DIR/scripts/`）

**Sub-agent 執行步驟**：

```
1. 嘗試呼叫 `slack_read_channel({ channel_id: "<CHANNEL_ID>", oldest: "<timestamp>", limit: 100 })`
2. 若 MCP 成功：將 MCP 回傳 JSON 寫入 `/tmp/slack-raw.json`
3. 若 MCP 失敗：改跑
   ```bash
   $SKILL_DIR/scripts/slack-webapi.sh read-channel \
     --channel-id "<CHANNEL_ID>" \
     --oldest "<timestamp>" \
     --limit 100 > /tmp/slack-raw.json
   ```
4. 執行 pipeline：
   ```bash
   cat /tmp/slack-raw.json | python3 $SKILL_DIR/scripts/extract-pr-urls.py --org <ORG> --mapping /tmp/pr-thread-mapping.json \
     | $SKILL_DIR/scripts/fetch-prs-by-url.sh --exclude-author $MY_USER \
     | $SKILL_DIR/scripts/check-my-review-status.sh $MY_USER > /tmp/review-candidates.json
   ```
5. 讀取 `/tmp/review-candidates.json` 和 `/tmp/pr-thread-mapping.json` 的內容
6. 回傳 Completion Envelope：
   - Status: DONE
   - Artifacts: { candidates: <JSON>, mapping: <JSON>, pr_count: N, raw_url_count: M }
   - Detail: `/tmp/polaris-agent-{timestamp}.md`（完整 PR URL 清單）
   - Summary: "掃描 {channel} {N} 天內訊息，提取 {M} 個 PR URL，過濾後 {N} 個需 review"
```

**Strategist 收到後**：
- 從 Artifacts 取得 `candidates`（review-candidates JSON）和 `mapping`（pr-thread-mapping JSON）
- 不需讀取 `/tmp/slack-raw.json` — 原始 Slack 訊息留在 sub-agent context 中，不進主 session
- 進入 Step 3 顯示清單

> **Why sub-agent?** 過去 Slack 模式在主 session 中跑，MCP 回傳的原始訊息（100+ 則）佔用大量 context，導致 review 階段 context 不足以讀 diff + rules + handbook。Sub-agent 吸收原始訊息，主 session 只收到 filtered JSON（通常 < 10 個 PR）。

#### Thread 模式

Thread 模式比 Channel 模式簡單 — 只讀一個討論串（通常 < 20 則訊息），不需 sub-agent 隔離。主 session 直接執行：

1. 嘗試呼叫 `slack_read_thread({ channel_id: "<CHANNEL_ID>", message_ts: "<THREAD_TS>" })`
2. 若 MCP 成功：將 MCP 回傳 JSON 寫入 `/tmp/slack-thread-raw.json`
3. 若 MCP 失敗：改跑
   ```bash
   $SKILL_DIR/scripts/slack-webapi.sh read-thread \
     --channel-id "<CHANNEL_ID>" \
     --thread-ts "<THREAD_TS>" > /tmp/slack-thread-raw.json
   ```
4. 執行 pipeline（`--thread-ts` 讓所有 URL 映射到同一個 thread）：
   ```bash
   cat /tmp/slack-thread-raw.json \
     | python3 $SKILL_DIR/scripts/extract-pr-urls.py --org <ORG> --thread-ts <THREAD_TS> --mapping /tmp/pr-thread-mapping.json \
     | $SKILL_DIR/scripts/fetch-prs-by-url.sh --exclude-author $MY_USER \
     | $SKILL_DIR/scripts/check-my-review-status.sh $MY_USER > /tmp/review-candidates.json
   ```
5. 讀取 `/tmp/review-candidates.json` 進入 Step 3

> **Why no sub-agent?** 一個 thread 的訊息量遠小於整個 channel（< 20 vs 100+），不會壓縮 context。直接在主 session 跑更快也更簡單。

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

> Stale approval 判定邏輯詳見 `references/stale-approval-detection.md`。

| review_status | 說明 | 動作 |
|---------------|------|------|
| `needs_first_review` | 從未 review 過 | 需要首次 review |
| `needs_re_approve` | approve 後作者有新 commit（stale） | 需要 re-approve |
| `needs_re_review` | REQUEST_CHANGES 後作者有回覆 review comments（不論有無新 push） | 需要 re-review |

> `valid_approve` 和 `waiting_for_author` 已被 script 自動過濾，不會出現在輸出中。
> `waiting_for_author` 包含：作者有新 push 但未回覆 review comments 的情況 — 視為還在改，不應再看。

若輸出為空 JSON array `[]`，告知使用者「目前沒有需要 review 的 PR」，流程結束。

### 3. 輸出待 review 清單

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

**Batch size 與 concurrency**：

- `batch_size`（config: `skill_defaults.review-inbox.batch_size`，預設 5，0 = 不限）控制本次總共 review 幾個 PR
- `concurrency`（config: `skill_defaults.review-inbox.concurrency`，預設 5）控制同時平行幾個 review sub-agent
- 當 PR 數超過 concurrency 時，分波執行：每波平行 concurrency 個，完成後啟動下一波，直到 batch_size 達標或全部完成

**確認模式**（由 `skill_defaults.review-inbox.confirm` 控制）：

- **`confirm: false`（預設）**：列完清單後直接進入 Step 4，自動選取全部（受 batch size 限制）。不等使用者輸入。
- **`confirm: true`**：詢問使用者要 review 哪些 PR，等待確認後才開始：
  > 請輸入要 review 的 PR 編號（例如 `1,3` 或 `all`，輸入 `none` 跳過）：

### 4. 批次執行 Review（平行 sub-agent）

對選中的 PR，**每個 PR 啟動一個獨立 `standard_coding` sub-agent 平行執行 review**。Sub-agent 不能呼叫 Skill tool，所以直接讀 `review-pr/SKILL.md` 的流程 inline 執行。

依 PR 狀態決定 review 模式：
- **首次 review** → 正常 review 流程
- **需 re-approve** → 檢查自上次 approve 後的新 diff，若無實質變更直接 re-approve，有變更則 review 新的部分
- **需 re-review** → re-review 流程（檢查上一輪 comments 的修正狀況）

**Strategist dispatch**：為每個 PR 建立一個 sub-agent，**所有 sub-agent 同時平行啟動**（單一訊息多個 Agent tool call）。每個 sub-agent prompt 包含：

1. PR URL + review_status（首次 / re-approve / re-review）
2. 指示讀取 `{SKILL_DIR}/../review-pr/SKILL.md`，按其流程執行：
   - Step 1: 辨識專案（從 URL 提取 repo，定位本地路徑）
   - Step 2: 用 `fetch-pr-info.sh` 取得 PR 資訊
   - Step 3: 讀 `.claude/rules/` + handbook
   - Step 3.5: 讀既有 review comments（去重）
   - Step 4: 審查每個變更檔案
   - Step 5: 提交 GitHub review
   - Step 6: 查詢 approve 狀態
   - Step 6.5: Handbook 校準（有 pattern 就寫入）
3. `$MY_USER`（GitHub username，用於 `fetch-pr-info.sh --my-user`）
4. workspace config 中的 `base_dir`（定位本地 repo）

**Sub-agent 回傳 Completion Envelope**：
```
Status: DONE
Artifacts: {
  pr_url, number, title, author, repo,
  result: "APPROVE" | "REQUEST_CHANGES" | "COMMENT",
  must_fix: N, should_fix: N, nit: N,
  approve_status: "M/2 approve(s), 已達標 / 還需 N 位",
  summary: "一句話描述"
}
Detail: /tmp/polaris-agent-{timestamp}.md（完整 review comments 清單）
```

**Strategist 收到所有結果後**，進入 Step 5 彙整。

> **Why per-PR sub-agent?** 每個 PR review 需讀 diff（可能 500+ 行）+ rules + handbook，5 個 PR 在主 session 跑會耗盡 context。各自隔離後主 session 只收 5 個摘要 JSON。

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

**Thread 模式**：走 Step 5b（回覆到使用者指定的討論串），`thread_ts` 直接從 Step 0 解析的值使用。

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

收集所有已 review PR 的作者 GitHub username（去重），依 `references/github-slack-user-mapping.md` 的完整 4-step lookup chain 查找 Slack user ID。

本 skill 可使用全部 4 步（含 Step 1 context match — Step 1a 讀取的 Slack 訊息可作為比對來源）。

**Step 5b-2：按 (thread_ts, author) 分組**

用 Step 1 sub-agent 回傳的 `mapping`（pr-thread-mapping JSON）中的 PR URL → thread_ts 對應，將 review 結果按 `(thread_ts, author)` 分組。同一個討論串中同一位作者的所有 PR 合成一則留言。

**Step 5b-3：發送 thread reply**

對每個 `(thread_ts, author)` 組合，優先用 `slack_send_message` MCP tool；若 MCP 失敗，改用 CLI fallback 回覆到該討論串：

**Workspace language policy gate（blocking）**：完整規則見 `references/workspace-language-policy.md`。每則 thread reply 送出前，先把最終 message 寫成 temp markdown，執行：

```bash
bash scripts/validate-language-policy.sh --blocking --mode artifact <review-inbox-thread-reply.md>
```

exit ≠ 0 → 修正 thread reply 語言後重跑；不可把未通過 gate 的 Slack 訊息送出。若同一輪會送多則 reply，每則都要 gate。

```
slack_send_message({
  channel_id: "<PR_CHANNEL_ID>",
  thread_ts: "<thread_ts>",
  message: "<留言內容>"
})
```

CLI fallback：
```bash
$SKILL_DIR/scripts/slack-webapi.sh send-message \
  --channel-id "<PR_CHANNEL_ID>" \
  --thread-ts "<thread_ts>" \
  --message "<留言內容>"
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

**Slack / Thread 模式**附加：
```
已回覆 N 則 Slack 討論串（共通知 M 位作者）
```

## Do

- 用 bundled scripts 做掃描和狀態判斷，不要手動組裝 API 查詢
  - Label 模式：`scan-need-review-prs.sh` + `check-my-review-status.sh`（主 session 直接執行）
  - Slack 模式：整包委派 sub-agent（先試 MCP；失敗改 `slack-webapi.sh` → `extract-pr-urls.py` → `fetch-prs-by-url.sh` → `check-my-review-status.sh`），主 session 只收 filtered JSON
- **Scan freshness（硬性規定）**：Scan 是 point-in-time snapshot。每次進入 Step 3（show list）或 Step 4（review）前，檢查 `/tmp/slack-raw.json` / scan 結果的 mtime；若距離現在超過 **60 秒**，必須重跑 Step 1（重 dispatch sub-agent 或重跑 script），不可沿用舊 candidates。適用情境：使用者在同一 session 中繼續詢問、確認 PR、或投入新的 review 意圖時，期間 channel 可能有新訊息
- Step 4 的 review 也由平行 sub-agent 執行，每個 PR 一個 sub-agent 讀 review-pr SKILL.md 跑完整流程
- 用 `gh api` 查 reviews（避免 `gh pr view` 的 encoding 問題）
- 列清單後等使用者確認才開始 review
- 每個 PR 的 review 結果都附上 approve 狀況
- re-approve 場景：若自上次 approve 後只有 CI/bot commit 無實質變更，直接 approve 不需重看整個 diff
- Slack 模式的時間範圍從使用者語意判斷，無指定時預設 7 天
- 走 CLI fallback 時，確認 `SLACK_BOT_TOKEN` 已設定，且 token 有 `channels:history`、`groups:history`、`chat:write`、`channels:read`（依私有頻道另加 `groups:read`）等 scopes

## Don't

- 不要 review 自己的 PR — 發現自己的 PR 在清單中要自動排除
- 不要未經確認就開始 review — 使用者可能只想看清單
- 不要在 Slack 模式發彙整訊息到 channel — 改為回覆各自討論串通知當事人
- 不要在 Slack 模式的 thread reply 設 `reply_broadcast: true` — 避免洗版
- Label 模式仍合成一則彙整訊息發到 channel
- 不要在 re-approve 時留冗餘 comments — 若無新問題，簡潔 approve 即可
- 不要對已 REQUEST_CHANGES 但作者尚未回覆 comments 的 PR 再次 review — 即使有新 push 也應跳過，等作者回覆後再看
- 不要在 scan snapshot 超過 60 秒後沿用舊 candidates JSON 回答 review 相關問題 — 期間 channel 可能有新訊息，必須重跑 Step 1


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
