---
name: check-pr-approvals
description: "Use when the user wants to check, manage, or act on their own open PRs — approval status, CI state, or unaddressed review comments. Trigger: '我的 PR', 'check PR approvals', 'PR 狀態', '催 review', 'PR 被 approve 了嗎', '幫我掃我的 PR'."
metadata:
  author: ""
  version: 1.7.0
---

# Check PR Approvals — PR Review 進度追蹤

掃描 `{config: github.org}` org（fallback: your-org）下指定使用者的所有 open PR，先確認 CI 全部通過（失敗的自動修正），再自動修正未回覆的 review comments，最後檢查 approve 數量（含 stale/dismissed 偵測）與 label 狀態，由使用者選擇哪些 PR 要請同仁幫忙 review，再發送到 Slack。核心原則：**CI 沒過的 PR 不請人 review，review comments 沒處理的 PR 先修再催，不浪費同仁時間**。

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

#### Rebase conflict 的自動解衝突流程

對 `rebase_status: "conflict"` 的 PR，開 worktree sub-agent 自動解衝突（與 Step 3 CI 失敗的自動修正機制對齊）：

1. **啟動 sub-agent**（`isolation: "worktree"`）：
   - checkout 該 PR 的 head branch
   - `git fetch origin <base>` 取得最新 base
   - `git rebase origin/<base>` 觸發 conflict
   - 對每個 conflict 檔案：讀取 conflict markers（`<<<<<<<` / `=======` / `>>>>>>>`），根據上下文判斷正確的解法：
     - 兩邊都新增不同內容 → 合併保留兩邊
     - 同一段落被兩邊修改 → 保留較新/較完整的版本（HEAD 通常是 base 上已合併的最終版）
     - 如果判斷不了 → 保留 HEAD（base branch）版本，較安全（⚠️ 注意：保留 HEAD 意味著捨棄 PR 作者的修改，僅在確實無法自動判斷正確版本時才採用此做法）
   - `git add <resolved-files>` + `git rebase --continue`，重複直到 rebase 完成
   - `git push --force-with-lease` 推送解衝突後的 branch
2. **解衝突失敗**（conflict 過於複雜或 rebase 多次失敗）：放棄自動解衝突，列入「conflict 待手動處理」區

⚠️ 同一個 repo 的多個 PR 不可平行解衝突（避免 git 互相干擾），依序處理。不同 repo 可平行。

解衝突完成後，顯示結果：

```
✅ 自動解衝突成功：
- repo-b #26 (chore/ai-enhancements) — rebase origin/master 完成，已 force push

⚠️ 以下 PR 自動解衝突失敗，需手動處理：
- repo-a #1786 (feat/xxx) — conflict 過於複雜
```

如果有任何 PR 自動解衝突失敗，**不阻擋後續流程**——已成功解衝突和原本就 rebase 成功的 PR 繼續進入 Step 3 CI 檢查。失敗的 PR 列入最終報告提醒使用者手動處理。

### 3. 檢查 CI 狀態（Gate：CI 沒過不催 review）

Rebase 後 CI 會重新觸發，等幾秒讓 GitHub 註冊 check runs，再查詢每個 PR 的 CI 狀態。
目的：**CI 沒過的 PR 不應該請人 review，浪費同仁時間**。

對每個 PR 執行：

```bash
gh pr checks <number> --repo {config: github.org}/<repo> 2>&1  # fallback: your-org
```

根據輸出判斷 CI 狀態：

| 狀態 | 判定條件 | 後續處理 |
|------|----------|----------|
| **pass** | 所有 checks 都是 `pass` | 進入 Step 4 approval 檢查 |
| **fail** | 任一 check 是 `fail`（包含 `codecov/patch`、`codecov/patch/*`） | 嘗試自動修正 |
| **pending** | 有 check 還在跑（`pending` / 無 check） | 等待後重試（最多重試 2 次，間隔 30 秒） |

> **codecov/patch 也是 CI 失敗**：`codecov/patch` 和 `codecov/patch/*`（如 `codecov/patch/main-core`）fail 代表新增或修改的程式碼覆蓋率不足，與 lint、build 失敗同等對待。不可將其視為「僅供參考」或「非 blocking」而跳過——覆蓋率不足的 PR 同樣不應請人 review。

#### CI 失敗的自動修正流程

對每個 CI 失敗的 PR，**委派 `fix-pr-review` skill 處理**。fix-pr-review 是修正自己 PR 的唯一入口，內建完整流程（CI 修正 → review comment 修正 → simplify → self-review → quality gate → reply → review lesson 萃取），且自帶 worktree 隔離（Step 2）。

**呼叫方式**：在主 agent 中直接 invoke fix-pr-review（不另開 worktree sub-agent，fix-pr-review 自己會開）：

```
讀取 fix-pr-review 的 SKILL.md 並依其流程修正此 PR。

PR: {pr_url}
模式：自動模式（跳過 Step 0.5 互動選擇）
範圍：僅修正 CI failures（Step 6），跳過 review comments（Step 7）
跳過：Step 13 Slack 通知（由 check-pr-approvals 統一發送）
```

- 修正失敗或超過 2 輪仍未通過：放棄自動修正，列入「CI 失敗待修」區
- 同一個 repo 的多個 PR 依序 invoke（避免 git 衝突）。不同 repo 可平行

#### 全部通過才繼續（Gate）

催 review 是一次性動作，分批催會打擾同仁。所有 PR 的 CI 必須全部通過後，才進入 Step 4 的 approval 檢查與後續催 review 流程：

- **全部 CI 通過**（含自動修正後通過的）→ 進入 Step 4 檢查 approval
- **任何一個 PR 仍失敗**（自動修正失敗）→ **暫停整個流程**，列出失敗的 PR 請使用者手動處理，不先催部分 CI 通過的 PR。使用者修好後可重新執行本 skill

### 3.5 自動修正未回覆的 Review Comments

> **⚠️ 此步驟為自動執行，不需使用者確認。發現 actionable comments 後直接 invoke fix-pr-review 修正，不要詢問使用者「要不要修」。** 與 Step 6（催哪些 PR 需要使用者選擇）不同——修正 review comments 是修自己的 PR，沒有理由不修。

CI 全部通過後，在催 review 之前先處理 reviewer 已經提出的 feedback——帶著未處理的 comment 催 review 不禮貌，等同要求 reviewer 再看一次同樣的問題。

用 bundled script 批次取得每個 PR 的未回覆 actionable comments：

```bash
echo "$ci_passed_prs" | "$SKILL_DIR/scripts/fetch-pr-review-comments.sh" --author $MY_USER
```

Script 自動過濾：
- **保留所有 code review bot 的建議**（Copilot、CodeRabbit、dependabot 等）——這些建議具參考價值，可能揭示安全風險或最佳實踐
- 只排除非 code review 的自動化訊息（changeset-bot、your-bot-account、codecov-commenter）
- 排除 PR author 自己的 comment
- 排除已有 author reply 的 comment（已處理過的）

#### 有 actionable comments 的 PR → 委派 fix-pr-review 修正

對每個 `has_actionable: true` 的 PR，**委派 `fix-pr-review` skill 處理**。統一入口確保修正流程完整（含 simplify、self-review、quality gate、reply、review lesson 萃取），且自帶 worktree 隔離（Step 2）。

**呼叫方式**：在主 agent 中直接 invoke fix-pr-review（不另開 worktree sub-agent，fix-pr-review 自己會開）：

```
讀取 fix-pr-review 的 SKILL.md 並依其流程修正此 PR。

PR: {pr_url}
模式：自動模式（跳過 Step 0.5 互動選擇）
範圍：完整流程（CI + review comments）
跳過：Step 3 Rebase（check-pr-approvals 已在 Step 2 完成 rebase）
跳過：Step 13 Slack 通知（由 check-pr-approvals 統一發送）
```

- 修正失敗或超過 2 輪仍未通過：放棄自動修正，列入「未修正 comments 待處理」區
- 同一個 repo 的多個 PR 依序 invoke（避免 git 衝突）。不同 repo 可平行

#### 結果呈現

修正完成後顯示摘要：

```
✅ 自動修正 review comments：
- repo-a #2010 — 3 則 comment 已修正並回覆
- repo-b #12165 — 2 則 comment 已修正並回覆

⚠️ 以下 comment 未能自動修正：
- repo-a #1954 — 1 則 comment 需手動處理（涉及架構決策）
```

#### 不阻擋後續流程

自動修正失敗**不阻擋** approval 檢查和催 review——未修正的 comments 列入最終報告，由使用者決定是否仍要催 review。這與 CI 失敗的 gate 不同：CI 失敗是客觀的「程式碼有問題」，而 review comment 可能只是建議或討論，不一定要修完才能催 review。

### 3.6 回溯萃取 Review Lessons

靜默掃描所有 PR 的**完整歷史 review comments**（包含已回覆的），萃取可通用化的 coding pattern 到各專案的 `.claude/rules/review-lessons/`。

**與 fix-pr-review Step 12.5 的差異：**
- fix-pr-review Step 12.5：只看本次修正的 comments（即時萃取）
- check-pr-approvals Step 3.6：看所有 PR 的所有歷史 comments（回溯萃取）
- 兩者寫入同一個 `.claude/rules/review-lessons/` 目錄，同主題會合併

#### 執行流程

對每個 PR 平行（不同 repo 可並行，同 repo 依序）執行：

1. 用 `gh api repos/{config: github.org}/<repo>/pulls/<number>/comments --paginate` 取得所有 review comments（fallback: your-org）
2. 用 `gh api repos/{config: github.org}/<repo>/issues/<number>/comments --paginate` 取得所有 issue comments
3. 過濾掉 bot 和 PR author 自己的 comment：
   - 排除：`changeset-bot`、`codecov-commenter`、`your-bot-account`、GitHub Actions bot
   - 排除：PR author（`$MY_USER`）自己的 comment
   - **保留**：真人 reviewer 的所有 comment（含已回覆的歷史）
4. 分析每個 comment 是否為可通用化 pattern（與 fix-pr-review 萃取條件相同）：
   - 涉及特定類型的程式碼問題（型別安全、邊界處理、命名規範、框架慣例等）
   - 具體到可以寫成規則、不只是此 PR 的一次性意見
   - 反映團隊或專案特定的 coding style 偏好
5. 檢查對應專案的 `.claude/rules/review-lessons/` 已有的 lesson 檔案，**用 Source PR URL 比對**是否已萃取過：
   - 若該 PR 的 URL 已出現在任一 lesson 檔案的 `Source:` 欄位 → 跳過，不重複萃取
6. 對新找到的可通用化 pattern，寫入 `.claude/rules/review-lessons/`：
   - 同主題已有 lesson 檔案 → 追加到既有檔案，附上 Source PR URL
   - 新主題 → 建立新 lesson 檔案，格式同 fix-pr-review Step 12.5 的產出
   - lesson 檔案不 commit（屬 AI 開發環境）

#### 重要注意

- **靜默執行**：不顯示進度，只在確實萃取到 lesson 時通知使用者（列出萃取到的主題）
- **已有 Source PR URL 的不重複萃取**：避免每次執行 check-pr-approvals 都重複寫入相同內容
- **不阻擋後續流程**：萃取失敗或無新 lesson 時，直接繼續到 Step 4，不中斷流程
- **不同 repo 的 PR 可平行掃描**：同 repo 多 PR 依序處理即可

#### Review Lessons 畢業檢查（靜默）

所有 repo 的 lesson 萃取完成後，對每個有 review-lessons 的 repo 計算總條目數（每個 `^- ` 開頭的行 = 1 條）。若任一 repo >= 15 → invoke `review-lessons-graduation`（帶入該 repo 路徑）。若全部 < 15 → 不輸出任何訊息。

### 4. 查詢每個 PR 的 Approve 數、Stale 狀態與 Label

Stale approval 判定邏輯依 `references/stale-approval-detection.md`。

**此步驟只有在 Step 3 確認所有 PR 的 CI 都通過後才會執行。**

用 bundled script 批次檢查 approval 狀態：

```bash
"$SKILL_DIR/scripts/fetch-user-open-prs.sh" --author $MY_USER \
  | "$SKILL_DIR/scripts/rebase-pr-branch.sh" --work-dir {base_dir} \
  | "$SKILL_DIR/scripts/check-pr-approval-status.sh" --threshold 2
```

或者如果不需要 rebase（已在前一步完成），直接 pipe rebase 結果：

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

### 5. 篩選與排序

- 篩選 **valid approve 數** < threshold（預設 2）的 PR（包含 stale 導致有效票數不足的）
- 依 valid approve 數升序排列（0 票排最前面，最需要關注）
- 同時記錄已達標的 PR 數量，供最終統計使用

### 6. 輸出帶編號的清單，等待使用者選擇

此步驟只有在所有 PR 的 CI 都通過後才會到達（Step 3 的 Gate 確保這一點）。

```
| # | Repo | PR | Title | Approvals | Reviewers | Label |
|---|------|----|-------|-----------|-----------|-------|
| 1 | repo-a | [#1786](https://github.com/org/repo-a/pull/1786) | feat: xxx | 0/2 | — | |
| 2 | repo-a | [#1920](https://github.com/org/repo-a/pull/1920) | [PROJ-460] xxx | 0/2 (stale) | reviewer-a ⚠️ re-approve | 👀 |
| 3 | repo-b | [#302](https://github.com/org/repo-b/pull/302) | fix: yyy | 1/2 | reviewer-b ✅ | |
```

- **Approvals 欄**：顯示 valid（非 stale）的 approve 數。若有 stale approve，標註 `(stale)`，例如 `0/2 (stale)` 表示有 approve 但全部因新 push 而失效
- **Reviewers 欄**：列出每位曾 review 的人及其狀態：
  - `username ✅` — valid approve（submitted_at > pushed_at）
  - `username ⚠️ re-approve` — stale approve，需要重新 approve
  - `username 🔄 changes` — 該 reviewer 最新狀態為 REQUEST_CHANGES
  - `—` — 尚無任何人 review
- **Label 欄**：若該 PR 已有 `👀 need review` label，顯示 `👀`；否則留空
- 表格下方附上統計摘要：共 N 個 open PR，M 個尚未取得 2 票 valid approve（含 stale 需 re-approve），K 個已達標

然後詢問使用者：

> 請輸入要催 review 的 PR 編號（例如 `1,3` 或 `all`，輸入 `none` 跳過）：

**等待使用者回覆後才繼續下一步。**

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

**僅發送使用者選中的 PR**（不是全部未達標的）。

使用 Slack MCP tool 發送訊息到指定 channel：

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

**`reviewer_details` 格式**：列出每位 reviewer 的狀態，讓同仁快速判斷自己該做什麼：
- 有 stale approve 的 reviewer：`⚠️ {username} 需 re-approve（有新 push）`
- 有 valid approve 的 reviewer：`✅ {username} 已 approve`（讓其他人知道不用重複看）
- 有 REQUEST_CHANGES 的 reviewer：`🔄 {username} requested changes`
- 尚無人 review：`還需 2 位同仁 review`
- 已有 1 票 valid：`還需 1 位同仁 review`

範例：
```
• <url|#1920> [PROJ-123] xxx — _0/2 approve(s)_
  ⚠️ teammate-name 需 re-approve（有新 push）| 還需 1 位同仁 review
```

按 repo 分組顯示，同一個 repo 的 PR 列在一起。

**如果使用者選擇 `none`：** 跳過 Slack 發送與 label 添加，直接告知使用者流程結束。

### 9. 回報完成

告知使用者：
- 已為哪些 PR 加上 `👀 need review` label（列出 PR 編號）
- 已發送 Slack 訊息到哪個 channel

### 10. Feature Branch PR Gate

掃描過程中若發現有 PR 已被 merge（`state: MERGED`），執行 `references/feature-branch-pr-gate.md` 的偵測邏輯。此步驟靜默執行，建立後在回報中一併告知使用者。

## Do

- **所有面向使用者的報告（CI 狀態、Approval 清單等）中，PR 編號必須用 markdown 超連結呈現**：`[#number](pr_url)`，讓使用者可以直接點擊前往。純文字 `#number` 不可接受
- 用 `gh api` 查 reviews（避免 `gh pr view` 的 encoding 問題）
- 批次在一個 bash command 中處理所有 PR，減少 tool call 次數
- Slack 訊息按 repo 分組，方便閱讀
- 支援使用者指定不同 author 或 channel
- 顯示清單後**必須等待使用者選擇**，不可自動決定
- 加 label 前先檢查是否已存在，避免重複
- Rebase conflict 的 PR 先嘗試自動解衝突（worktree sub-agent），解衝突失敗不阻擋其他 PR 繼續流程
- CI 失敗和 review comment 修正統一委派 `fix-pr-review` skill（worktree sub-agent），確保完整流程（simplify、self-review、quality gate、reply、review lesson 萃取）
- **所有 PR 的 CI 都通過後**才進入 review comments 檢查
- 所有 code review bot（Copilot、CodeRabbit、dependabot 等）的建議都視為 actionable — 可能揭示安全風險或最佳實踐
- Rebase 解衝突、CI 修正、review comment 修正都用 `isolation: "worktree"` 避免影響當前工作目錄
- CI 修正和 review comment 修正後信任本地 `quality-check-flow` 結果，不 poll GitHub CI
- **Review comment 修正自動執行，不需使用者確認** — 與 Step 6 催 review 的使用者選擇不同。發現 actionable comments 就直接 invoke fix-pr-review，修完再繼續

## Don't

- 不要用 `gh pr view --json reviews` — PR body 含特殊字元時 jq 會 parse 失敗
- 不要逐一發 Slack 訊息 — 所有結果合成一則發送
- 不要未經使用者選擇就發送 Slack 或加 label — 必須等使用者指定編號
- 不要對已達標（2+ valid approve）的 PR 加 label 或發送通知
- 不要在 Slack 訊息中使用「催促」、「催」、「趕快」等字眼 — 用「麻煩大家幫忙」、「有空幫忙看一下」等柔軟語氣
- 不要忽略 stale approve — approve 時間早於最後 push 時間的一律視為無效，必須計入需要 re-approve 的清單 — 詳見 references/stale-approval-detection.md
- **不要對 CI 沒過的 PR 催 review** — 浪費同仁時間，必須先修好 CI 再請人看
- **不要分批催 review** — 有任何 PR 的 CI 未通過時，不可先催已通過的那些。一次性催比分批打擾同仁好
- **不要 poll GitHub CI** — 本地 `quality-check-flow` 通過後 push 即可，不需要反覆 `gh pr checks` 等結果
- **不要修正非 code review 的自動化通知**（changeset-bot、codecov-commenter、your-bot-account）— 這些只是通知，不是 code review。但 Copilot、CodeRabbit、dependabot 等 code review bot 的建議要修
- **不要修正已有 author 回覆的 comment** — 已處理過的不重複修正
- **不要因 review comment 修正失敗而阻擋催 review** — 與 CI gate 不同，review comments 可能是建議而非 blocking issue
- **不要自己寫 CI/review comment 修正邏輯** — 統一委派 `fix-pr-review`，確保 simplify、self-review、quality gate、review lesson 萃取等步驟不被跳過
- **不要在修正 review comments 前詢問使用者是否要修正** — Step 3.5 是自動執行步驟，發現 actionable comments 就直接 invoke fix-pr-review。只有 Step 6 催 review 才需要使用者選擇


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
