---
name: check-pr-approvals
description: "掃描使用者的 open PR，偵測 CI 狀態、未回覆 review comments、approval 數量，分類為三種狀態（可催/需修/已達標）後由使用者選擇催 review 或手動修正。Trigger: '我的 PR', 'check PR approvals', 'PR 狀態', '催 review', 'PR 被 approve 了嗎', '幫我掃我的 PR'."
metadata:
  author: ""
  version: 2.0.0
---

# Check PR Approvals — PR Review 進度追蹤

掃描 `{config: github.org}` org（fallback: your-org）下指定使用者的所有 open PR，偵測 rebase 狀態、CI 結果、未回覆 review comments、approval 數量（含 stale/dismissed 偵測），分類後由使用者決定下一步。核心原則：**偵測問題、分類呈報、由使用者決定修正或催 review**。

本 skill 不做任何自動修正。問題 PR 附上 ticket key，使用者可用「做 KB2CW-XXXX」觸發 engineering 完整流程修正。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`github.org`、`slack.channels.ai_notifications`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

## Defaults

| 參數 | 預設值 | 說明 |
|------|--------|------|
| GitHub author | 動態取得 | `gh api user --jq '.login'`，可由使用者在 prompt 指定其他人 |
| Approval threshold | 見 `references/shared-defaults.md` | 低於此數視為「需要 review」 |
| Slack channel | 見 `references/shared-defaults.md` | 可由使用者指定其他 channel |
| Review label | 見 `references/shared-defaults.md` | 加在需要 review 的 PR 上 |

如果使用者沒有特別指定，直接用預設值執行，不需要額外確認。

**取得當前使用者**：workflow 開頭執行 `MY_USER=$(gh api user --jq '.login')`，後續步驟用 `$MY_USER`。

## Scripts

本 skill 包含四個 shell script 處理確定性邏輯，避免 LLM 重複組裝 API 查詢：

| Script | 用途 | Input | Output |
|--------|------|-------|--------|
| `scripts/fetch-user-open-prs.sh` | 搜尋使用者所有 open PR（含 branch 資訊） | `--author <username>` | JSON array of PR objects |
| `scripts/rebase-pr-branch.sh` | 批次 rebase PR branches 到最新 base | stdin (PR JSON) + `--work-dir <path>` | JSON array with `rebase_status` field |
| `scripts/fetch-pr-review-comments.sh` | 批次取得未回覆的 actionable review comments | stdin (PR JSON) + `--author <username>` | JSON array with `actionable_comments` field |
| `scripts/check-pr-approval-status.sh` | 批次檢查 approval 數量（含 stale 偵測） | stdin (PR JSON) + `--threshold <N>` | JSON array with approval info |

Script 路徑相對於本 SKILL.md 所在目錄。執行前確認有 `+x` 權限。

## Workflow

### 1. 搜尋 Open PR + 取得 Branch 資訊

用 bundled script 一次完成搜尋和取得 branch 資訊：

```bash
SKILL_DIR="$(dirname "$(readlink -f "$0")")"  # 或直接用 skill 的絕對路徑
"$SKILL_DIR/scripts/fetch-user-open-prs.sh" --author $MY_USER
```

如果結果為空（`[]`），直接告知使用者「目前沒有 open PR」，流程結束。

**輸出 JSON 格式**（每個 PR 含 base/head branch）：

```json
[
  {
    "repo": "repo-a",
    "number": 1786,
    "title": "feat: xxx",
    "url": "https://github.com/your-org/repo-a/pull/1786",
    "updated_at": "2026-03-15T00:00:00Z",
    "labels": "👀 need review",
    "base": "develop",
    "head": "feat/xxx"
  }
]
```

### 2. Rebase 每個 PR 到最新 base branch

用 bundled script 批次 rebase，確保 reviewer 看到的是最新 code：

```bash
"$SKILL_DIR/scripts/fetch-user-open-prs.sh" --author $MY_USER \
  | "$SKILL_DIR/scripts/rebase-pr-branch.sh" --work-dir {base_dir}
```

Script 內建處理：
- **Cascade rebase**：若 task PR 的 base 是 feature branch（非 develop/main/master），自動先 rebase feature branch 到其 upstream（從 open PR 查 baseRefName），再 rebase task branch。需設定 `ORG` 環境變數。避免 diff 膨脹
- 每個 repo 依序處理（同 repo 多 PR 共用本地目錄，不可平行）
- Rebase 前自動 `git stash`，完成後 `git stash pop`
- Conflict 時自動 `git rebase --abort`，記錄到結果
- 處理完切回原本的 branch

**`rebase_status` 值**：`success` / `conflict` / `skipped`

Conflict 的 PR 直接歸類為 🔧 需先修正，不嘗試自動解衝突。

### 3. 偵測 CI 狀態

Rebase 後 CI 會重新觸發，等幾秒讓 GitHub 註冊 check runs，再查詢每個 PR 的 CI 狀態。

對每個 PR 執行：

```bash
gh pr checks <number> --repo {config: github.org}/<repo> 2>&1  # fallback: your-org
```

根據輸出判斷 CI 狀態：

| 狀態 | 判定條件 | 分類 |
|------|----------|------|
| **pass** | 所有 checks 都是 `pass` | 繼續下一步判定 |
| **fail** | 任一 check 是 `fail`（包含 `codecov/patch`、`codecov/patch/*`） | 🔧 需先修正 |
| **pending** | 有 check 還在跑（`pending` / 無 check） | 等待後重試（最多重試 2 次，間隔 30 秒） |

> **codecov/patch 也是 CI 失敗**：`codecov/patch` 和 `codecov/patch/*`（如 `codecov/patch/main-core`）fail 代表新增或修改的程式碼覆蓋率不足，與 lint、build 失敗同等對待。

### 3.5 偵測未回覆的 Review Comments

用 bundled script 批次取得每個 CI pass PR 的未回覆 actionable comments：

```bash
echo "$ci_passed_prs" | "$SKILL_DIR/scripts/fetch-pr-review-comments.sh" --author $MY_USER
```

Script 自動過濾：
- **保留所有 code review bot 的建議**（Copilot、CodeRabbit、dependabot 等）——這些建議具參考價值，可能揭示安全風險或最佳實踐
- 只排除非 code review 的自動化訊息（changeset-bot、your-bot-account、codecov-commenter）
- 排除 PR author 自己的 comment
- 排除已有 author reply 的 comment（已處理過的）

有 actionable comments 的 PR 歸類為 🔧 需先修正。

### 4. 查詢每個 PR 的 Approve 數、Stale 狀態與 Label

Stale approval 判定邏輯依 `references/stale-approval-detection.md`。

用 bundled script 批次檢查 approval 狀態：

```bash
echo "$rebase_result" | "$SKILL_DIR/scripts/check-pr-approval-status.sh" --threshold 2
```

Script 自動處理：
- 用 `gh api` 取得 reviews（避免 `gh pr view --json reviews` 的 encoding 問題）
- Stale 判定：APPROVED review 的 `submitted_at` 早於 PR 的 `pushed_at` → stale
- 計算 valid approvals = APPROVED 且非 stale 的數量

**輸出附加欄位**：

| 欄位 | 說明 |
|------|------|
| `valid_approvals` | 有效 approve 數 |
| `total_approvals` | 所有 APPROVED review 數（含 stale） |
| `has_stale` | 是否有 stale approve |
| `reviewers` | `[{user, state, is_stale}]` |
| `needs_review` | valid < threshold |

同時從 Step 1 的 labels 欄位判斷是否已有 `👀 need review` label。

### 5. 分類與排序

每個 PR 依據前面步驟的偵測結果，歸入三個分類：

| 分類 | 條件 | 意義 |
|------|------|------|
| 🟢 可催 review | CI pass + 無 actionable comments + rebase 成功 + approval 不足 | 準備好被 review |
| 🔧 需先修正 | CI fail / 有 actionable comments / rebase conflict | 有問題，需走 engineering 修正 |
| ✅ 已達標 | valid approvals >= threshold | 不需要動作 |

**Ticket key 萃取**：對 🔧 分類的 PR，從 branch name 或 PR title 萃取 ticket key（pattern: `[A-Z]+-\d+`）。萃取不到的標記「無對應 ticket」。

**JIRA 狀態回轉**：對有 ticket key 的 🔧 PR，查詢當前 JIRA 狀態。若為 `CODE REVIEW`（PR 已開的常見狀態），轉回 `IN DEVELOPMENT`，並留 JIRA comment 記錄原因（例：「PR #1920 CI failing — reverted to IN DEVELOPMENT for fix」）。理由：讓使用者說「做 KB2CW-XXXX」時，engineering 直接命中「IN DEV + 有 branch」路由，不會被 CODE REVIEW 分支擋下。已在 IN DEVELOPMENT 或其他狀態的不動。

排序：🟢 PR 依 valid_approvals 升序（0 票最前面），🔧 PR 依問題嚴重度排列（conflict > CI fail > comments）。

### 6. 輸出分類報告，等待使用者選擇

```
🟢 可催 review（N 個）：
| # | Repo | PR | Title | Approvals | Reviewers | Label |
|---|------|----|-------|-----------|-----------|-------|
| 1 | repo-a | [#1786](url) | feat: xxx | 0/2 | — | |
| 2 | repo-b | [#302](url) | fix: yyy | 1/2 | reviewer-b ✅ | |

🔧 需先修正（N 個）：
| Repo | PR | Ticket | 問題 |
|------|----|--------|------|
| repo-a | [#1920](url) | KB2CW-3788 | CI fail (codecov/patch) |
| repo-c | [#45](url) | KB2CW-3801 | rebase conflict (3 files) |
| repo-d | [#67](url) | （無對應 ticket） | 2 unresolved review comments |

→ 要修嗎？輸入「做 KB2CW-3788」走 engineering

✅ 已達標（N 個）：repo-a [#100](url), repo-b [#200](url)
```

**🟢 Reviewers 欄**：
- `username ✅` — valid approve
- `username ⚠️ re-approve` — stale approve
- `username 🔄 changes` — REQUEST_CHANGES
- `—` — 尚無人 review

**🟢 Label 欄**：已有 `👀 need review` 顯示 `👀`，否則留空。

**🔧 問題欄**：可複合（例如「CI fail + 2 unresolved comments」）。

統計摘要：共 X 個 open PR，N 個可催 review，M 個需先修正，K 個已達標。

然後詢問使用者：

> 請輸入要催 review 的 🟢 PR 編號（例如 `1,2` 或 `all`，輸入 `none` 跳過）：

**等待使用者回覆後才繼續下一步。** 🔧 PR 不可選擇催 review。

### 7. 為選中的 PR 加上 Label

對使用者選中的 PR，如果尚未有 need review label，使用 `gh` 加上。

**注意：** 不同 repo 的 label 名稱格式可能不同（`👀 need review` 或 `:eyes: need review`）。先嘗試 Unicode emoji 格式，若失敗則改用 shortcode 格式：

```bash
# 先嘗試 Unicode emoji 格式（config: github.org，fallback: your-org）
gh pr edit <number> --repo {config: github.org}/<repo> --add-label "👀 need review" 2>&1
# 若失敗（label not found），改用 shortcode 格式
gh pr edit <number> --repo {config: github.org}/<repo> --add-label ":eyes: need review" 2>&1
```

如果該 PR 已有此 label 則跳過，避免重複操作。

### 8. 發送 Slack 訊息

**僅發送使用者選中的 🟢 PR**。

使用 Slack MCP tool 發送訊息到指定 channel：

**Workspace language policy gate（blocking）**：完整規則見 `references/workspace-language-policy.md`。Slack reminder 送出前，先把最終 message 寫成 temp markdown，執行：

```bash
bash scripts/validate-language-policy.sh --blocking --mode artifact <check-pr-approvals-slack.md>
```

exit ≠ 0 → 修正 reminder 語言後重跑；不可把未通過 gate 的 Slack 訊息送出。

```
mcp__claude_ai_Slack__slack_send_message
  channel_id: <channel>
```

訊息格式（Slack mrkdwn）：

```
:mag: *PR Review 進度*
時間：{YYYY-MM-DD}
作者：{author}

以下 PR 麻煩大家有空幫忙 review / re-approve，感謝 :pray:

*{repo_name}*
• <{pr_url}|#{number}> {title} — _{valid_approvals}/2 approve(s)_
  {reviewer_details}

共 {selected_count} 個 PR 需要 review / re-approve
```

**`reviewer_details` 格式**：
- 有 stale approve 的 reviewer：`⚠️ {username} 需 re-approve（有新 push）`
- 有 valid approve 的 reviewer：`✅ {username} 已 approve`
- 有 REQUEST_CHANGES 的 reviewer：`🔄 {username} requested changes`
- 尚無人 review：`還需 2 位同仁 review`
- 已有 1 票 valid：`還需 1 位同仁 review`

按 repo 分組顯示，同一個 repo 的 PR 列在一起。

**如果使用者選擇 `none`：** 跳過 Slack 發送與 label 添加，直接告知使用者流程結束。

### 9. 回報完成

告知使用者：
- 已為哪些 PR 加上 `👀 need review` label（列出 PR 編號）
- 已發送 Slack 訊息到哪個 channel
- 哪些 🔧 PR 的 JIRA ticket 已從 CODE REVIEW 轉回 IN DEVELOPMENT（列出 ticket keys）

若有 🔧 PR，附上提醒：

```
🔧 以下 PR 仍需修正（JIRA 已轉回 IN DEVELOPMENT）：
- repo-a #1920 (KB2CW-3788) — CI fail
- repo-c #45 (KB2CW-3801) — rebase conflict
→ 輸入「做 KB2CW-3788」走 engineering 修正
```

### 10. Feature Branch PR Gate

掃描過程中若發現有 PR 已被 merge（`state: MERGED`），執行 `references/feature-branch-pr-gate.md` 的偵測邏輯。此步驟靜默執行，建立後在回報中一併告知使用者。

### 10.1 Spec Done Marker

Step 10 掃出 MERGED PR 時，從 PR branch / title 萃取 ticket key，若 `specs/companies/{company}/{TICKET}/` 存在，執行：

```bash
scripts/mark-spec-implemented.sh {TICKET}
```

將 `refinement.md` / `plan.md` 的 frontmatter `status` 標為 `IMPLEMENTED`；docs-manager 會直接讀取 canonical specs status。idempotent（已標過就 no-op）。Epic（`GT-*`）的 IMPLEMENTED 由 verify-AC 寫，這裡不動；只處理 Bug 和 ad-hoc task（非 Epic 類型）。

## Do

- **所有面向使用者的報告中，PR 編號必須用 markdown 超連結呈現**：`[#number](pr_url)`，讓使用者可以直接點擊前往
- 用 `gh api` 查 reviews（避免 `gh pr view` 的 encoding 問題）
- 批次在一個 bash command 中處理所有 PR，減少 tool call 次數
- Slack 訊息按 repo 分組，方便閱讀
- 支援使用者指定不同 author 或 channel
- 顯示清單後**必須等待使用者選擇**，不可自動決定
- 加 label 前先檢查是否已存在，避免重複
- 🔧 PR 報告中必須包含 ticket key（從 branch name 或 PR title 萃取），方便使用者觸發 engineering 修正
- 🔧 PR 若 JIRA 狀態為 CODE REVIEW，必須轉回 IN DEVELOPMENT 並留 comment 記錄原因，確保 engineering 路由正確命中「IN DEV + 有 branch」路徑
- 三分類邏輯嚴格執行：🟢（ready）/ 🔧（needs fix）/ ✅（approved）
- 每次執行都是冪等的 — 掃描當前狀態，不依賴前次結果
- 所有 code review bot（Copilot、CodeRabbit、dependabot 等）的建議都視為 actionable comment

## Don't

- 不要嘗試自動修正任何問題（CI failure、review comments、rebase conflict）— 只偵測和報告
- 不要用 `gh pr view --json reviews` — PR body 含特殊字元時 jq 會 parse 失敗
- 不要逐一發 Slack 訊息 — 所有結果合成一則發送
- 不要未經使用者選擇就發送 Slack 或加 label — 必須等使用者指定編號
- 不要對已達標（2+ valid approve）的 PR 加 label 或發送通知
- 不要讓使用者選擇 🔧 分類的 PR 來催 review — 這些需要先修正
- 不要省略 ticket key — 🔧 PR 必須附上 ticket key，使用者需要它來觸發修正
- 不要在 Slack 訊息中使用「催促」、「催」、「趕快」等字眼 — 用「麻煩大家幫忙」、「有空幫忙看一下」等柔軟語氣
- 不要忽略 stale approve — approve 時間早於最後 push 時間的一律視為無效 — 詳見 references/stale-approval-detection.md
- 不要將非 code review 的自動化通知列為 actionable comment（changeset-bot、codecov-commenter、your-bot-account）
- 不要將已有 author 回覆的 comment 列為 actionable
- 不要處理無 ticket key 的 PR 的修正路由 — 列出但標記「無對應 ticket」

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
