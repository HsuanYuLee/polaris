## Step 5 — Base Freshness Detection（D19）

> 純偵測，不做 side-effect。偵測與行動分離 — 本 step 只 detect，rebase action 集中在 Step 2 前置。

使用 `scripts/check-base-fresh.sh`：

```bash
bash "${POLARIS_ROOT}/scripts/check-base-fresh.sh" "<path/to/task.md>"
```

| 結果 | 動作 |
|------|------|
| exit 0 — fresh（base 自上次 rebase 後無新 commit） | ✅ 繼續 Step 6 |
| exit 1 — stale（base 有新 commit） | 🔄 **delivery flow loops back to Step 2 前置 Rebase** |

### Loop-back 行為

Step 2 前置 runs `engineering-rebase.sh` → rebase 改變 HEAD → 舊 evidence auto-invalidate → Steps 2→3→3.5 re-execute with new HEAD → Step 5 re-checks freshness。

### Local Extension

同行為；必須透過 task.md / local policy resolver 取得 upstream，不支援無 task.md rebase lane。

---

## Step 6 — Commit

### 6a. Commit

依 `references/commit-convention-default.md` 的 fallback chain 解析 commit message 規範：

1. **L1 — Repo tooling**：`{repo}/.commitlintrc.*` / `commitlint.config.*` / `package.json#commitlint` / husky `commit-msg` hook（最權威；機器規則 + commit-msg hook 同源 SoT）
2. **L2 — Repo handbook**：`{company}/polaris-config/{project}/handbook/**/*.md` 的 commit convention 段（補 L1 未宣告的敘述要求）
3. **L3 — Polaris default**：`references/commit-convention-default.md`（本 framework 兜底；headline 格式、type enum、subject 規則、squash 策略、revision 規格皆由此檔提供）

**規則衝突處理**：L1 命中即停（type enum / scope / subject limit 走 L1）；L2 / L3 只在 L1 未宣告的維度補充。

**做法**：手動寫 commit message + `git commit`（不假設 `git ai-commit` 等 user-level 工具可用，DP-032 D22 已從 framework 拔除）。commit-msg hook fail → 讀 stderr → 對照 L1 config 修 msg → 重試。

### Repo 自有的 commit-time 規則

Repo 可能有框架不知道、也不需要知道的 commit-time 產物要求（release note 檔、版本檔、
產生器等）。這些一律由上面 L1 / L2 的 repo tooling 與 repo handbook 揭露，實作時照 repo
自己的規則做即可；框架不代為定義、不代為檢查，也不把它們寫進 task schema 或 Allowed Files。

### JIRA Safety Net

Developer lane 以 task.md / JIRA ticket / DP pseudo-task ID 作為 ticket source。Local Extension lane 若沒有產品 JIRA ticket，使用 DP pseudo-task ID；不得為了 PR title 臨時創造無來源 ticket key。

---
