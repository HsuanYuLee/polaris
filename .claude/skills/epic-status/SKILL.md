---
name: epic-status
description: "Use when the user wants to see an Epic's progress against merge — what's blocked, missing, or closeable. Trigger: 'epic 進度', 'epic 狀態', '離 merge 還多遠', '還差什麼', '補全 epic'. Key: '拆單' → breakdown; 'epic 進度' → here."
metadata:
  author: Polaris
  version: 1.4.0
---

# Epic Status — 進度追蹤與差距補全

使用者貼一個 Epic key，skill 自動掃描所有子單的 JIRA 狀態 + GitHub branch/PR/CI/review 狀態，
產出一張「離 feature merge 還多遠」的差距報告，並可選擇性地路由到現有 skill 補全缺口。

## 前置：讀取 workspace config

讀取 workspace config（參考 `references/workspace-config-reader.md`）。
本步驟需要的值：`jira.instance`、`github.org`、`projects`（用於 ticket → repo mapping）、`slack.channels`。
若 config 不存在，使用 `references/shared-defaults.md` 的 fallback 值。

---

## Phase 1：掃描與彙整

Phase 1 是 read-only 的狀態收集，不修改任何 JIRA 或 GitHub 資料。

### 1. 讀取 Epic

```
mcp__claude_ai_Atlassian__getJiraIssue
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  issueIdOrKey: <EPIC_KEY>
  fields: ["summary", "status", "issuetype", "description", "labels"]
```

確認 issue type 是 Epic。若不是 Epic → 提示使用者「這張不是 Epic，要看單張 ticket 的狀態嗎？」並結束。

### 2. 查詢所有子單

```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  cloudId: {config: jira.instance}  # fallback: your-domain.atlassian.net
  jql: parent = <EPIC_KEY> ORDER BY status ASC
  # storyPointsFieldId：依 references/jira-story-points.md Step 0 探測
  fields: ["summary", "status", "issuetype", "assignee", "story_points", "<storyPointsFieldId>"]
  maxResults: 50
```

若子單數量為 0 → 提示「這張 Epic 還沒有子單，要先拆單嗎？」並建議使用 `/breakdown`。

### 3. 偵測 Feature Branch

Epic 通常有一個 feature branch（如 `feat/PROJ-460-xxx`），子單的 task branch 會 merge 回這個 feature branch，最後 feature branch 再 merge 進 develop/main。

**3a. 查詢 Epic 對應的 feature branch**：

```bash
# 方法 1：用 Epic key 搜尋 PR（feature branch → develop 的 PR）
gh pr list --search "<EPIC_KEY>" --state all --json number,title,headRefName,baseRefName,state --limit 5

# 方法 2：搜尋 branch 名稱
gh pr list --search "head:feat/<EPIC_KEY>" --state all --json number,title,headRefName,baseRefName,state --limit 5
```

從結果中辨識 feature branch（通常是 `feat/<EPIC_KEY>-*` 或包含 Epic key 的 branch）。
若找不到 feature branch → 記為「Feature branch 尚未建立」，子單 PR 的 base 判斷跳過。

**3b. 掃描 Feature PR 狀態**：

找到 feature branch 後，使用共用腳本查詢 feature PR 完整狀態（task PR merge 進度 + feature PR review/CI/conflict）：

```bash
references/scripts/check-feature-pr.sh {owner}/{repo} {feature_branch} --base develop
```

從腳本輸出的 JSON 解析：
- `task_prs.all_merged` → 是否所有 task PR 已 merge
- `feature_pr.exists` → feature PR 是否存在
- `feature_pr.review.changes_requested > 0` → gap：**修 feature PR review**
- `feature_pr.review.approved` vs `feature_pr.review.requested` → approved 比例
- `feature_pr.ci` → CI 狀態（success/failure/pending）
- `feature_pr.mergeable` → conflict 狀態
- `feature_pr.inline_comments > 0` 且無 CHANGES_REQUESTED → gap：**有未處理 comments**
- `action == "CREATE_FEATURE_PR"` → gap：**需建立 feature PR**（Phase 2 路由到 `feature-branch-pr-gate.md`）

Feature PR 的狀態會顯示在狀態矩陣的 **Feature Branch 區塊**，並納入差距分析。

### 4. 交叉比對 GitHub 狀態

對每張子單，**並行**查詢 GitHub：

**4a. 查詢 branch 和 PR**（每張子單一個 Bash call，並行執行）：

```bash
gh pr list --search "<TICKET_KEY>" --state all --json number,title,headRefName,baseRefName,state,isDraft --limit 5
```

`--state all` 同時抓 open 和 merged 的 PR。注意 `baseRefName` 欄位——用來判斷 PR 的 merge 目標。

**4a-2. 對每個 open PR，使用共用腳本取得完整狀態**：

```bash
references/scripts/get-pr-status.sh {owner}/{repo} {pr_number}
```

從腳本輸出的 JSON 解析：
- `ci.status` → CI 狀態（success/failure/pending）
- `reviews.approved` / `reviews.changes_requested` → review 計數
- `comments.unresolved` → 未回覆的 inline comments 數量（thread-based 偵測）
- `mergeable` → conflict 狀態

即使 review state 不是 `CHANGES_REQUESTED`，只要 `comments.unresolved > 0` 就標記為 gap：**有未處理 comments**。
這能抓到 Copilot review、COMMENTED state 的人工 review 等「沒有正式 request changes 但有待處理 comments」的情況。

**4b. 判斷 PR merge 目標**：

每張子單的 PR，檢查 `baseRefName`：

| baseRefName | 意義 | 狀態標記 |
|-------------|------|---------|
| = feature branch | ✅ 正確目標 | 正常追蹤 |
| = develop/main | ⚠️ 直接進 develop | 標記為「跳過 feature branch」 |
| 其他 | 可能是依賴 branch | 標記 base branch 名稱 |

**4c. 若子單數量 > 10**，改用 sub-agent 處理（避免主 session 大量 tool call）：

Dispatch Explorer sub-agent（`model: "sonnet"`）：

```
你是 GitHub 狀態掃描 agent。對以下 JIRA 子單查詢 GitHub 狀態並回傳結果表格。

## 子單清單
{ticket_keys_and_summaries}

## Feature Branch
{feature_branch_name}（若為空表示尚未建立）

## GitHub org
{config: github.org}

## 查詢方式
對每張子單並行執行：
1. gh pr list --search "<TICKET_KEY>" --state all --json number,title,headRefName,baseRefName,state,isDraft --limit 5
2. 對每個 open PR：references/scripts/get-pr-status.sh {owner}/{repo} {pr_number}

## 回傳格式
| Ticket | PR # | PR State | Base | CI | Reviews | Branch |
每張子單一行。無 PR 的標記「—」。Base 欄位標記 PR 的 merge 目標（feature branch / develop / 其他）。

## 限制
- 只做查詢，不修改任何東西
- 用 gh CLI，不用 gh api
```

### 5. 產出狀態矩陣

將 JIRA 狀態 + GitHub 狀態彙整成一張表：

```
## Epic: <EPIC_KEY> — <Summary>
狀態：<Epic Status> | 子單：N 張 | 總估點：X 點
Feature branch：feat/PROJ-460-product-listing → develop（PR #88, open, CI ✅, Review: ❌ CHANGES_REQUESTED by @reviewer）

| # | Ticket | Summary | Type | JIRA 狀態 | Points | PR | Base | Merged | CI | Review | Gap |
|---|--------|---------|------|----------|--------|----|----|--------|----|----|-----|
| 1 | PROJ-101 | Add login page | Story | ✅ Done | 3 | #42 | feat branch | ✅ | ✅ | ✅ | — |
| 2 | PROJ-102 | API validation | Task | 🔄 In Dev | 2 | #45 | feat branch | — | ❌ | 0/2 | CI 紅 |
| 3 | PROJ-103 | Error handling | Task | 📋 Open | 2 | — | — | — | — | — | 未開工 |
| 4 | PROJ-104 | [驗證] Login flow | Sub-task | ✅ Done | — | — | — | — | — | — | — |
| 5 | PROJ-105 | [驗證] Error state | Sub-task | 📋 Open | — | — | — | — | — | — | 驗證未執行 |
```

**Merged 欄位**：PR 是否已 merge 回 feature branch（或 develop，若無 feature branch）。
這是「離 feature merge 還多遠」的核心指標——只有 merged ✅ 的子單才算完成。

**狀態 icon 對照**：

| JIRA 狀態 | Icon |
|----------|------|
| 開放 / Open / To Do | 📋 |
| SA/SD | 📝 |
| In Development | 🔄 |
| Code Review | 👀 |
| QA Testing / Waiting for Stage | 🧪 |
| Regression / Waiting for Release | 📦 |
| Done / Closed / Launched | ✅ |

**CI 狀態**：從 `get-pr-status.sh` 的 `ci.status` 欄位，success = ✅，failure = ❌，pending = ⏳，無 PR = —

**Review 狀態**：從 `get-pr-status.sh` 的 `reviews.approved` / `reviews.changes_requested` 計算，如 `2/2 ✅` 或 `0/2 ⚠️`

**Inline comments**：由 `get-pr-status.sh` 的 `comments.unresolved` 欄位提供（thread-based 偵測，非單純計數）。即使沒有 `CHANGES_REQUESTED`，有未回覆 comments 也是 gap（常見於 Copilot review 或 COMMENTED state 的人工 review）。

### 5. 差距分析摘要

在狀態矩陣下方附上差距分析：

```
## 差距分析

### Feature Branch 完成度
- Feature branch：`feat/PROJ-460-product-listing` → develop（PR #88, open, CI ✅, Review: ❌ CHANGES_REQUESTED）
- Task merged → feature branch：1/3 張（33%）| 3/7 點（43%）
- Task PR open（待 merge）：1/3 張
- 未開工：1/3 張
- **Feature PR review 狀態**：若有 CHANGES_REQUESTED → 列為 blocker

### 開發進度（含未 merge）
- 完成（Done + PR merged/open）：2/3 張（66%）| 5/7 點（71%）
- 開發中（In Dev + Code Review）：1/3 張
- 未開工：1/3 張

### 驗證進度
- 驗證子單：2/5 完成（40%）
- 未執行：PROJ-105（[驗證] Error state）— 對應的開發子單尚未完成

### Blockers（需立即處理）
- ❌ PROJ-102：CI 紅（PR #45），2 個 check 失敗
- ⚠️ PROJ-105：Code Review 卡 3 天，0/2 approved

### 待處理（Next Actions）
- 📋 PROJ-103：未開工（2 點）— 可用 `/work-on PROJ-103` 開始
- 📋 PROJ-106：未估點 — 可用 `/work-on PROJ-106` 估點 + 開發
- 👀 PROJ-105：需催 review — 可用 `/check-pr-approvals` 通知 reviewer
- 🧪 PROJ-105：驗證未執行 — 開發完成後用 `verify-completion` 驗證

### 離 Feature Merge 的距離

完成定義：所有 task PR merged 回 feature branch + CI 綠 + 驗證通過 → feature branch 可 merge 進 develop。

```
Feature branch merge 進度：
  ████░░░░░░ 33%（1/3 task merged 回 feature branch）

完整 pipeline：
  [開發] ████████░░ 66%  →  [驗證] ████░░░░░░ 40%  →  [Merged] ███░░░░░░░ 33%

需要的動作：{N} 個
  - {未開工}張開工
  - {CI紅}張修 CI
  - {缺review}張催 review
  - {PR open 未 merge}張 merge PR
  - {驗證未過}張驗證
```
```

**Blocker 判斷邏輯**：
- CI 紅（task PR 或 feature PR） → Blocker（阻擋 merge）
- Code Review 超過 2 天且 0 approved → Blocker
> Review 卡住的判定（含 stale approval）詳見 `references/stale-approval-detection.md`。
- PR 有 merge conflict → Blocker
- **Feature PR 有 CHANGES_REQUESTED** → Blocker（即使所有 task PR 已 merge，feature PR 被 request changes 也無法上線）
- 開發子單 Done 但對應 `[驗證]` 子單未完成 → Blocker（驗證是 merge 的前置條件）
- 其餘為「待處理」

---

## Phase 2：自動補全

Phase 1 報告產出後，**不詢問使用者**，直接根據 gap 類型自動路由到對應 skill 執行。
使用者觸發「補全」就是要動作，不需要再確認一次。

### Gap → Skill 路由表

| Gap 類型 | 路由 Skill | 說明 |
|---------|-----------|------|
| CHANGES_REQUESTED（task PR） | `fix-pr-review` | 修 review comments，push 修正 |
| CHANGES_REQUESTED（feature PR） | `fix-pr-review` | 同上，但對象是 feature PR |
| 有未處理 inline comments（無 CHANGES_REQUESTED） | `fix-pr-review` | Copilot review、COMMENTED state 的 comments 也要修 |
| CI 紅（task PR 或 feature PR） | `fix-pr-review` | 修 CI failures |
| Review 卡住（0 approved 超過 2 天） | `check-pr-approvals` | 催 review + Slack 通知 |
| 未估點 | `work-on` | 包含估點 + 拆子單 |
| 未開工（有估點） | `work-on` | 建 branch + 開發 + PR |
| 有 code 沒 PR | `git-pr-workflow` | 品質檢查 + 發 PR |
| 驗證未執行（開發已完成） | `verify-completion` | 對應開發子單已 Done/PR merged |
| 驗證未執行（開發未完成） | — | 隨開發流程自動處理，不單獨路由 |
| PR 有 conflict | 提示使用者 | rebase 需人工判斷，不自動執行 |
| 所有 task PR 已 merge，無 feature PR | 自動建 feature PR | 見 `references/feature-branch-pr-gate.md` |

### 自動路由判斷邏輯

Phase 1 產出報告後，掃描所有 gap，按以下決策樹自動分類並執行：

```
for each gap in gaps:
  if gap.type == "CHANGES_REQUESTED":
    → fix-pr-review（帶 PR URL）
  elif gap.type == "HAS_UNRESOLVED_COMMENTS":
    → fix-pr-review（帶 PR URL，即使沒有 CHANGES_REQUESTED）
  elif gap.type == "CI_RED":
    → fix-pr-review（帶 PR URL）
  elif gap.type == "REVIEW_STUCK":
    → check-pr-approvals
  elif gap.type == "NO_ESTIMATE":
    → work-on（帶 ticket key）
  elif gap.type == "NOT_STARTED":
    → work-on（帶 ticket key）
  elif gap.type == "CODE_NO_PR":
    → git-pr-workflow
  elif gap.type == "VERIFICATION_PENDING" and dev_done:
    → verify-completion
  elif gap.type == "NO_FEATURE_PR" and all_tasks_merged:
    → 自動建 feature PR（feature-branch-pr-gate.md）
  elif gap.type == "CONFLICT":
    → 不自動執行，報告中標記提醒使用者
```

### 執行順序

**核心原則：自力可完成的優先，需他人協助的最後。**
把所有「我們能獨立處理」的 gap 全部做完，收斂到只剩「等同仁 review / approve」才停下來通知。
這樣使用者每次觸發補全，結束時得到的是一個乾淨的狀態：「你的部分都做完了，只差 review」。

按此原則排序：

**Phase A — 自力可完成（不需他人介入）：**
1. **修 PR review**（CHANGES_REQUESTED / unresolved comments — 修正 code 是自己的事）
2. **修 CI**（CI 紅 — 修正 code 是自己的事）
3. **開發**（未開工的 ticket）
4. **建 PR**（有 code 沒 PR）
5. **驗證**（開發完成但驗證未執行）
6. **建 feature PR**（所有 task merged）

**Phase B — 需他人協助（Phase A 全部完成後才執行）：**
7. **催 review**（review 卡住 — 發 Slack 通知後只能等）

### 執行模式

- 獨立的 gap 可平行處理（不同 repo 的 ticket、催 review 等 read-only 動作）
- 同 repo 的開發類 gap 走 `work-on` 批次模式（自帶 worktree 隔離）
- 每個 gap 透過 Skill tool 觸發對應 skill，不手動執行 skill 步驟

### 重掃

補全完成後，**重新跑一次 Phase 1**（快速重掃），產出更新後的狀態矩陣，讓使用者看到即時進度。

### Slack 通知（補全過程中）

補全過程中需要發 Slack 訊息時（催 review、通知進度），根據訊息目的選擇頻道：

| 目的 | Config Key | 說明 |
|------|-----------|------|
| 催 review / 請團隊幫忙 | `slack.channels.pr_review` | 發給團隊的公開訊息 |
| AI 執行進度通知 | `slack.channels.ai_notifications` | 發給使用者自己的私人通知 |

**規則**：凡是需要其他人看到並採取行動的訊息（催 review、PR 狀態更新、請求 approve），一律用 `pr_review` 頻道。只有給使用者自己看的狀態報告才用 `ai_notifications`。

---

## Do / Don't

- Do: Phase 1 完全 read-only，不修改任何 JIRA 或 GitHub 資料
- Do: 使用 `--state all` 查 PR，同時看 open 和 merged 的狀態
- Do: 子單 > 10 張時委派 sub-agent 查 GitHub，避免主 session tool call 爆量
- Do: Blocker 優先排序 — 修 review > CI 紅 > 催 review > 未開工
- Do: Phase 2 自動路由，不問確認（使用者說「補全」就是要動作）
- Do: 補全後重掃一次產出更新報告
- Do: 將 `[驗證]` 子單納入追蹤 — 驗證是開發流程的一環，未驗證的子單算 gap
- Do: 在差距分析中分開統計「開發進度」和「驗證進度」，兩者都達 100% 才算 feature 完成
- Don't: Phase 1 就開始修東西 — 先看全貌再動手
- Don't: 手動執行 skill 步驟 — Phase 2 必須用 Skill tool 觸發
- Don't: 把 Done/Closed 的子單列為 gap — 已完成就跳過
- Don't: 自動 rebase conflicting PR — merge conflict 需要人工判斷

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-03-31 | Initial release — Phase 1 scan + Phase 2 gap closing |
| 1.0.1 | 2026-03-31 | Add Slack channel routing guidance — pr_review for team, ai_notifications for self |
| 1.1.0 | 2026-03-31 | Phase 1: scan feature PR (feat→develop) review status + CI; Phase 2: auto-route gaps without confirmation |
| 1.1.1 | 2026-03-31 | Phase 1: detect unresolved inline comments (not just CHANGES_REQUESTED) — catches Copilot review and COMMENTED-state reviews |
| 1.2.0 | 2026-03-31 | Phase 2: self-first execution principle — do all self-actionable gaps first, leave review-dependent items last |
| 1.3.0 | 2026-03-31 | Step 3b: use shared `check-feature-pr.sh` script for feature PR status (task PR merge count + review/CI/conflict) |
| 1.4.0 | 2026-03-31 | Step 4: use shared `get-pr-status.sh` for per-child-ticket PR status (CI, review, unresolved comments, mergeable). Replaces inline gh api calls with thread-based unresolved detection |


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
