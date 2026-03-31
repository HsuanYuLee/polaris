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
| `CREATE_FEATURE_PR` | 全部 merged，尚無 feature PR | 進入「建立 Feature PR」 |
| `FEATURE_PR_EXISTS` | 全部 merged，feature PR 已存在 | 跳過（冪等） |
| `TASKS_IN_PROGRESS` | 還有 open task PR | 靜默跳過 |
| `NO_TASK_PRS` | 找不到 task PR | 靜默跳過 |

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
