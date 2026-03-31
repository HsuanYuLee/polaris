# PR Input Resolver

從使用者輸入解析 PR 資訊並定位本地專案路徑的共用流程。

## 輸入格式

| 輸入類型 | 範例 |
|---------|------|
| PR URL | `https://github.com/{owner}/{repo}/pull/{number}` |
| PR 編號 | `#1920` 或 `1920` |
| 無輸入 | 從當前 branch 自動偵測 |

## 解析流程

### 1. 取得 PR 資訊

- **URL 格式** → 直接從 URL 提取 `owner`、`repo`、`number`
- **只有編號** → 用 `gh pr view` 取得完整資訊：
  ```bash
  gh pr view <number> --json number,url -q '.number,.url'
  ```
- **無輸入** → 從當前 branch 偵測：
  ```bash
  gh pr view --json number,url -q '.number,.url'
  ```

### 2. 定位本地路徑

依序搜尋：
1. 當前工作目錄（`./`）— 若 repo 名稱符合
2. `{base_dir}/{repo名稱}`（`base_dir` 從 workspace config 的 `projects` block 取得）

例如：
- `github.com/acme-org/my-app/pull/1882` → `{base_dir}/my-app`
- `github.com/acme-org/another-repo/pull/300` → `{base_dir}/another-repo`

### 3. Fallback 策略

本地找不到時，依 skill 特性選擇 fallback：

| Skill 類型 | Fallback |
|-----------|----------|
| 需要修改程式碼的（fix-pr-review） | 詢問使用者本地路徑 |
| 唯讀（review-pr） | 設定 `remote_mode: true`，改用 GitHub API 遠端讀取 |

#### Remote Mode 讀取方式

```bash
# 列出檔案
gh api repos/{owner}/{repo}/contents/{path} --jq '.[].name'

# 讀取檔案內容
gh api repos/{owner}/{repo}/contents/{path}?ref={headRefName} --jq '.content' | base64 -d

# 專案規範
gh api repos/{owner}/{repo}/contents/.claude/rules --jq '.[].name'
```

## 輸出

解析完成後提供以下變數供後續步驟使用：
- `owner`：GitHub org/user
- `repo`：repo 名稱
- `pr_number`：PR 編號
- `local_path`：本地專案根目錄（或 `null`）
- `remote_mode`：是否使用遠端讀取（`true`/`false`）
