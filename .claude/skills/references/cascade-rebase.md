# Cascade Rebase（Feature Branch 場景）

Shared reference for cascade rebase logic. Used by:
- `git-pr-workflow` Step 6.5
- `fix-pr-review` Step 3
- `check-pr-approvals` Step 2 (via `scripts/rebase-pr-branch.sh`)

## 何時觸發

當 PR 的 base branch 是 feature branch（非 develop/main/master）時，必須先 cascade rebase。

## 邏輯

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

若 feature branch 落後 develop，task PR 的 diff 會包含所有 develop 新 commits 的檔案變更，reviewer 無法分辨哪些是本 PR 的修改。Cascade rebase 確保 diff 只包含本 PR 的改動。

## Conflict 處理

- **無 conflict** → 繼續後續步驟
- **有 conflict，範圍在 PR 變動檔案內** → 嘗試自動解決
- **有 conflict，範圍超過 PR 變動檔案** → 回報使用者手動處理，不繼續

## Edge Cases

| 場景 | 處理 |
|------|------|
| Feature branch 無 open PR | upstream fallback 到 develop |
| Feature branch PR 已 merge | upstream fallback 到 develop |
| Feature branch 本身也基於另一個 feature branch | 只做一層 cascade（feature → develop），不遞迴 |
| `scripts/rebase-pr-branch.sh` 批次模式 | 腳本內建 cascade 邏輯，會自動偵測並處理 |
