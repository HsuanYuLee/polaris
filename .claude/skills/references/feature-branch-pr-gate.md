# Feature Branch PR Gate

當 Epic 使用 feature branch 開發模式（task branches → feature branch → develop）時，
本 reference 定義「何時自動建立 feature branch → develop 的 PR」的偵測邏輯與建立流程。

## 觸發時機

任何 workflow 在完成 task-level 工作後，若涉及 Epic 子單，都應執行此 gate check。
不限於特定 skill — **「發現可以開，就開」**。

### 觸發點

| Skill / 流程 | 觸發條件 | 說明 |
|--------------|---------|------|
| `epic-status` Phase 1 | 掃描完所有子單狀態 | 差距分析自然發現 |
| `git-pr-workflow` | task PR 建立完成 | 順便檢查同 repo 兄弟子單 |
| `check-pr-approvals` | 偵測到 task PR 被 merge | merge 是最關鍵的狀態變化 |
| `work-on` | 完成 task 的完整開發流程 | 委派給 git-pr-workflow 時帶入 |
| `fix-pr-review` | push 修正後 PR 被 merge | 同 check-pr-approvals |

## 偵測邏輯

### Step 1: 判斷是否為 feature branch 模式

```
task PR 的 baseRefName 不是 develop/main
  → 是 feature branch 模式
  → feature_branch = task PR 的 baseRefName
```

若 task PR 的 base 是 develop/main → 不是 feature branch 模式，跳過此 gate。

### Step 2–4: 查詢狀態（使用共用腳本）

```bash
references/scripts/check-feature-pr.sh {owner}/{repo} {feature_branch} --base develop
```

腳本一次完成三件事：
- **Step 2** — 列出所有以 feature branch 為 base 的 task PR，統計 merged/open/closed
- **Step 3** — 判斷是否全部 merged（`open == 0 && merged > 0`）
- **Step 4** — 檢查 feature PR 是否已存在（含 review、CI、conflict 狀態）

輸出 JSON，`action` 欄位決定下一步：

| action | 意義 | 處理 |
|--------|------|------|
| `CREATE_FEATURE_PR` | 全部 merged，尚無 feature PR | **Rebase feature branch → develop** → 建立 Feature PR |
| `FEATURE_PR_EXISTS` | 全部 merged，feature PR 已存在 | 跳過（冪等） |
| `TASKS_IN_PROGRESS` | 還有 open task PR | **Sibling Cascade Rebase**（若 merged > 0）→ rebase 所有 open sibling task PRs |
| `NO_TASK_PRS` | 找不到 task PR | 靜默跳過 |

## Sibling Cascade Rebase（任一 task merge 後）

當 check-feature-pr.sh 回傳 `TASKS_IN_PROGRESS`（還有 open task PR），代表有 task 剛 merge 進 feature branch，其他 sibling task PR 的 base 已過時。此時自動 rebase 所有 open sibling task PRs。

### 觸發條件

`action == "TASKS_IN_PROGRESS"` **且** `merged > 0`（至少有一個 task PR 已 merge）

### 流程

1. 從 check-feature-pr.sh 的輸出取得所有 open task PR 的 head branch
2. 對每個 open task PR 依序 rebase：
   ```bash
   git -C {repo_dir} fetch origin
   git -C {repo_dir} checkout {task_branch}
   git -C {repo_dir} rebase origin/{feature_branch}
   git -C {repo_dir} push --force-with-lease
   ```
3. Conflict 處理：同 check-pr-approvals Step 2 的自動解衝突流程（worktree sub-agent）
4. 結果靜默處理 — 成功不通知，conflict 才列入回報

### 為什麼

- 確保所有 open task PR 的 diff 只顯示自己的改動，不包含已 merge 的兄弟 PR 差異
- Reviewer 看到的是乾淨的 diff，不需要自行判斷哪些改動是本 PR 的
- 避免「PR 可以看但 diff 很亂」的狀態

## Feature Branch Rebase（建 Feature PR 前）

當所有 task PR 都 merge 完成（`action == "CREATE_FEATURE_PR"`），在建立 feature PR 之前先 rebase feature branch 到最新的 develop。

### 流程

```bash
git -C {repo_dir} fetch origin
git -C {repo_dir} checkout {feature_branch}
git -C {repo_dir} rebase origin/develop
git -C {repo_dir} push --force-with-lease
```

### Conflict 處理

- 嘗試自動解衝突
- 解不了 → 通知使用者，不建立 feature PR（dirty rebase 開出去的 PR 無意義）

### 為什麼

- Feature PR 的 diff 只包含本 Epic 的改動，不包含 develop 上已有的變更
- Reviewer 可以專注在 Epic 的整體改動，而非與 develop 的歷史差異

## 品質檢查（建 PR 前必跑）

Feature branch rebase 完成後、建 PR 前，執行品質檢查確保合併後的程式碼沒壞：

1. 讀取 `dev-quality-check` SKILL.md，執行完整品質檢查（lint + test + coverage）
2. 若品質檢查失敗 → **不建 PR**，回報失敗項目給使用者
3. 品質檢查通過 → 繼續建立 Feature PR

**為什麼**：個別 task PR 各自通過品質檢查，但合併到 feature branch 後可能產生衝突或整合問題。Feature PR 直接開出去 CI 才跑紅是浪費 reviewer 時間。

## 建立 Feature PR

### PR Title

```
[{EPIC_KEY}] {Epic Summary}
```

### PR Description 彙整邏輯

從所有 merged task PR 自動彙整：

```markdown
## Summary

Epic {EPIC_KEY} 的 feature branch，包含以下子單：

{for each merged task PR:}
- **{TICKET_KEY}** — {PR title}（#{PR number}）
{end for}

### 預期效果
{從 Epic description 的「預估改善」或 AC 區塊提取}

## Test plan
{從 Epic 的 AC 或 [驗證] 子單提取}
- [ ] {AC item 1}
- [ ] {AC item 2}
- [ ] ...

Generated with [Claude Code](https://claude.com/claude-code)
```

### 通知

建立後發 Slack 到 `{config: slack.channels.pr_review}`：

```
*[{EPIC_KEY}] Feature branch PR 已建立* 🚀

> <{pr_url}|#{number} — {title}>

所有 task PR 已 merge 回 feature branch，feature PR 準備進 develop。
請幫忙 review 🙏
```

## 行為規範

- **只建不 merge**：feature PR 建立後等人工 review + approve，不自動 merge
- **不問確認**：條件成熟就建，不打斷使用者問「要建 feature PR 嗎」
- **冪等**：已有 open feature PR → 跳過，不重複建
- **靜默成功**：建立後簡短回報（PR URL），不長篇大論
- **靜默跳過**：條件不成熟（還有 open task PR）→ 不說明為什麼沒建，除非使用者主動問
- **跨 repo 獨立**：Epic 跨多個 repo 時，每個 repo 獨立判斷。A repo 全 merged 就建 A 的 feature PR，不等 B repo
