# Pre-Work Rebase（含 Cascade）

Shared reference for rebase logic. **所有 branch 在開始開發/修正前必須 rebase 到最新 base**。

Used by:
- `engineering` § 4.5 Pre-Development Rebase（first-cut）
- `engineering` § R0 Pre-Revision Rebase（revision mode）
- `engineer-delivery-flow` Step 5 Final Re-Sync
- `engineering` delivery flow
- `check-pr-approvals` Step 2 (via `scripts/rebase-pr-branch.sh`)
- `feature-branch-pr-gate` § Feature Branch Rebase

## 核心原則

**在開發/修正前 rebase，不是之後。** 先發現 conflict 再動手，避免做完才 rebase 發現衝突又修一次。

## 何時觸發

| 場景 | 觸發時機 |
|------|---------|
| **First-cut**（engineering § 4.5） | Branch checkout 後、開發前 |
| **Revision mode**（engineering § R0） | PR branch checkout 後、讀施工圖前 |
| **Delivery flow**（Step 5） | 開發完成後、開 PR 前（final re-sync，通常 skip） |
| **Feature PR merge 前** | feature-branch-pr-gate 建 PR 前 |

## 邏輯

### 判斷 branch 類型

```
current branch 的 base 是什麼？
├─ base 是 feature branch（feat/{EPIC}-*）→ Cascade Rebase
└─ base 是 develop/main/master → Simple Rebase
```

### Simple Rebase（base 是 develop/main）

```bash
git fetch origin
git rebase origin/{base}
# 若有修改：
git push --force-with-lease
```

適用：
- Task branch → develop（無 feature branch 場景）
- Feature branch → develop（feature PR 開 PR 前或 revision mode）

### Cascade Rebase（base 是 feature branch）

Task branch 的 base 是 feature branch 時，**必須先確保 feature branch 也是最新的**。否則 task PR diff 會混入 develop 的新 commit。

```
1. 查詢 feature branch 的 upstream：
   gh pr list --repo {org}/{repo} --head {feature_branch} --state open --json baseRefName --jq '.[0].baseRefName'

2. Fallback：若無 open PR（已 merge 或未建 PR）→ 預設 upstream = develop

3. Rebase feature branch 到 upstream：
   git fetch origin
   git checkout {feature_branch}
   git rebase origin/{upstream}
   git push --force-with-lease

4. Rebase task branch 到更新後的 feature branch：
   git checkout {task_branch}
   git rebase origin/{feature_branch}
```

## 為什麼

若 base branch 落後 upstream，PR diff 會包含所有 upstream 新 commits 的檔案變更，reviewer 無法分辨哪些是本 PR 的修改。Rebase 確保 diff 只包含本 PR 的改動。

**在開發前做的額外好處**：conflict 在寫 code 之前就浮出來。若開發後才 rebase 遇到 conflict，已經寫好的 code 可能需要重新調整（特別是如果 conflict 涉及同一區域的邏輯修改）。

## Conflict 處理

- **無 conflict** → 繼續後續步驟
- **有 conflict，範圍在 PR 變動檔案內** → 嘗試自動解決
- **有 conflict，範圍超過 PR 變動檔案** → 回報使用者手動處理，**不開始開發/修正**

## Edge Cases

| 場景 | 處理 |
|------|------|
| Feature branch 無 open PR | upstream fallback 到 develop |
| Feature branch PR 已 merge | upstream fallback 到 develop |
| Feature branch 本身也基於另一個 feature branch | 只做一層 cascade（feature → develop），不遞迴 |
| `scripts/rebase-pr-branch.sh` 批次模式 | 腳本內建 cascade 邏輯，會自動偵測並處理 |
| Base branch 無新 commit（已是最新） | 跳過 rebase（`git log HEAD..origin/{base}` 為空） |
| Feature PR（feat → develop）revision mode | Simple Rebase：`git rebase origin/develop`（feature branch 自己就是 PR branch）|
