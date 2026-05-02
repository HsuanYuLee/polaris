---
name: check-pr-approvals
description: "掃描使用者的 open PR，偵測 CI 狀態、未回覆 review comments、approval 數量，分類為三種狀態（可催/需修/已達標）後由使用者選擇催 review 或手動修正。Trigger: '我的 PR', 'check PR approvals', 'PR 狀態', '催 review', 'PR 被 approve 了嗎', '幫我掃我的 PR'."
metadata:
  author: ""
  version: 2.1.0
---

# Check PR Approvals — PR Review 進度追蹤

掃描 `{config: github.org}` org（fallback: `your-org`）下指定使用者的 open PR，偵測 rebase、CI、review comments、approval / stale approval，分成三類後等待使用者選擇下一步。

核心邊界：本 skill 只偵測、分類、呈報與在使用者選擇後通知 reviewer；不自動修正 CI failure、review comments 或 rebase conflict。需修正的 PR 交給 `engineering`。

## 前置

讀取 workspace config（見 `references/workspace-config-reader.md`），需要：

- `github.org`
- `slack.channels.ai_notifications`
- shared defaults：approval threshold、review label、fallback org/channel

若使用者沒有指定 author，先執行：

```bash
MY_USER="$(gh api user --jq '.login')"
```

## Bundled Scripts

Script 路徑相對於本 skill 目錄。執行前確認有 `+x` 權限。

| Script | 用途 | Output contract |
|--------|------|-----------------|
| `scripts/fetch-user-open-prs.sh` | 搜尋 author open PR，含 base/head/labels | PR JSON array |
| `scripts/rebase-pr-branch.sh` | 批次 rebase PR branches | 加上 `rebase_status` |
| `scripts/fetch-pr-review-comments.sh` | 批次取得未回覆 actionable comments | 加上 `actionable_comments` |
| `scripts/check-pr-approval-status.sh` | 批次檢查 approvals / stale | 加上 approval fields |

Script 是 deterministic source；不要在入口重寫其內部 API / stale / bot filter 邏輯。

## Lazy-load Map

| 何時讀 | Reference | 用途 |
|--------|-----------|------|
| 產出分類報告、加 label、送 Slack、處理需修正 PR 時 | `references/check-pr-approvals-reporting.md` | report table、Slack wording、label fallback、JIRA remediation routing |
| 判讀 approval / stale semantics 前 | `../references/stale-approval-detection.md` | stale approval 權威定義 |
| 掃到 merged PR 時 | `../references/feature-branch-pr-gate.md` | Feature Branch PR Gate |
| Slack message 送出前 | `../references/workspace-language-policy.md` | language gate |
| 收尾前 | `../references/post-task-reflection-checkpoint.md` | post-task reflection |

## Workflow

### 1. Scan Open PRs

```bash
"$SKILL_DIR/scripts/fetch-user-open-prs.sh" --author "$MY_USER"
```

若結果為 `[]`，回報目前沒有 open PR，流程結束。

### 2. Rebase Branches

```bash
"$SKILL_DIR/scripts/fetch-user-open-prs.sh" --author "$MY_USER" \
  | "$SKILL_DIR/scripts/rebase-pr-branch.sh" --work-dir "{base_dir}"
```

`rebase_status=conflict` 的 PR 直接歸類為 🔧 需先修正，不嘗試自動解衝突。

### 3. Check CI

對 rebase 成功或 skipped 的 PR 查：

```bash
gh pr checks <number> --repo "{github_org}/<repo>"
```

Classification:

- all pass → 繼續 review comments / approvals 判定
- any fail → 🔧 需先修正
- pending / no checks → 最多重試 2 次，間隔 30 秒；仍 pending 則列為等待中並說明

`codecov/patch` 與 `codecov/patch/*` fail 一律等同 CI fail。

### 4. Check Review Comments

```bash
echo "$ci_passed_prs" \
  | "$SKILL_DIR/scripts/fetch-pr-review-comments.sh" --author "$MY_USER"
```

有未回覆 actionable comments 的 PR 歸類為 🔧 需先修正。Code review bots 的建議視為 actionable；非 code review bot 通知由 script 過濾。

### 5. Check Approvals

先讀 `../references/stale-approval-detection.md`，再跑：

```bash
echo "$review_comment_checked_prs" \
  | "$SKILL_DIR/scripts/check-pr-approval-status.sh" --threshold "$APPROVAL_THRESHOLD"
```

Valid approval = APPROVED 且非 stale。Stale approval 不算達標。

### 6. Classify

| 分類 | 條件 | 下一步 |
|------|------|--------|
| 🟢 可催 review | CI pass + 無 actionable comments + rebase 成功/可接受 + valid approvals 不足 | 可讓使用者選擇通知 |
| 🔧 需先修正 | CI fail / rebase conflict / actionable comments | 萃取 ticket key，提示走 `engineering` |
| ✅ 已達標 | valid approvals >= threshold | 不加 label、不通知 |

🔧 PR 必須從 branch name 或 title 萃取 ticket key（pattern: `[A-Z]+-\d+`）；萃取不到就標「無對應 ticket」。有 ticket key 且 JIRA 在 `CODE REVIEW` 時，依 reporting reference 回轉 `IN DEVELOPMENT` 並留言。

### 7. Report + User Selection Gate

讀 `references/check-pr-approvals-reporting.md` 產出使用者報告。報告後必須等待使用者輸入要通知的 🟢 PR 編號，例如 `1,2`、`all`、`none`。

不可讓使用者選 🔧 或 ✅ PR 送 review reminder。未得到選擇前，不加 label、不送 Slack。

### 8. Label + Slack

只處理使用者選中的 🟢 PR：

1. 依 reporting reference 加 review label，已存在則跳過。
2. 組 Slack message。
3. 送出前先把 message 寫成 temp markdown，跑：

   ```bash
   bash scripts/validate-language-policy.sh --blocking --mode artifact <check-pr-approvals-slack.md>
   ```

4. language gate 通過後才送 Slack。

### 9. Merged PR Side Effects

如果掃描過程發現 merged PR：

- 讀 `../references/feature-branch-pr-gate.md` 並執行 gate。
- 若 branch / title 可萃取非 Epic ticket key，且對應 spec container 存在，依 reporting reference 執行 Spec Done Marker。

## Hard Safety Rules

- 不自動修正 CI failure、review comments、rebase conflict。
- 不使用 `gh pr view --json reviews` 取代 bundled approval script。
- 不省略 🔧 PR ticket key；萃取不到要明寫。
- 不通知已達標或需修正的 PR。
- 不忽略 stale approval。
- 不把未通過 language gate 的 Slack message 送出。
- 不在 Slack wording 使用「催促」、「催」、「趕快」等字眼；用「麻煩大家幫忙」、「有空幫忙看一下」。

## Post-Task Reflection

收尾前執行 [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md)。
