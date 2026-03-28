# Sub-agent 委派規則

## 委派模式

- 多個獨立改善點時，優先用 sub-agent 平行處理以節省時間
- 需要深入調查（如找出所有不符規範的檔案）時，用 sub-agent 避免塞爆主對話 context
- **批次實作用 Worktree 隔離**：`work-on` 批次模式 Phase 2 的每個 sub-agent 必須用 `isolation: "worktree"`，確保平行開發時不會互相覆蓋檔案或產生 git conflict。單張 ticket 的 sub-agent 不強制，但涉及多檔案改動時建議使用
- **Plan-first（先想再寫）**：Sub-agent 開始寫 code 前，若預估影響超過 3 個檔案或需要架構決策（新建 vs 擴充元件、跨模組改動），先進 Plan 模式產出實作方案再執行
- **Explore-then-Implement（探索與實作分離）**：需要掃描 codebase 時，使用 `skills/references/explore-pattern.md` 的自適應探索模式。目的：保持實作 phase 的 context window 乾淨
- **Sub-agent Talent Pool（角色分工）**：所有 sub-agent 調度統一引用 `skills/references/sub-agent-roles.md` 的角色定義

## Model 分級

啟動 sub-agent 時依任務類型指定 model，節省成本同時確保品質。規劃類決策（SA/SD 設計、Epic 拆單策略、scope challenge）留給主 agent（Opus）處理，不委派給 sub-agent：

| 任務類型 | model 參數 | 範例 |
|---------|-----------|------|
| **探索 / 分析** | `"sonnet"` | Explore subagent、PR review、code analysis、Phase 1 ticket 分析 |
| **執行 / 修正** | `"sonnet"` | 實作 sub-agent、fix-pr-review worktree、CI 修正、rebase conflict |
| **JIRA 模板操作** | `"haiku"` | 批次建子單、批次建 ticket、readiness checklist 比對 |

> 各角色的完整定義見 `skills/references/sub-agent-roles.md`。

## 操作規則

- **優先用本地 repo 讀取檔案**：當 `{base_dir}/<repo>` 存在時，sub-agent 必須用 Read tool 或本地 git 指令讀取檔案，不可用 `gh api repos/.../contents/` 遠端讀取。遠端模式僅限本地無 clone 時的 fallback
- **批次操作前先驗證權限**：啟動多個平行 sub-agent 前（如批次 PR review、跨 repo 建 PR），先用單一 sub-agent 跑完一輪完整流程確認 bash 權限無誤，再啟動其餘
- **Worktree 適用於需要隔離的操作**：fix-pr-review 等需要避免影響當前開發的操作應使用 `isolation: "worktree"`。注意：project-level `settings.local.json` 的 project-specific patterns 在 worktree 中不可用
- **通用 permissions 放 user-level `~/.claude/settings.json`**：Sub-agent 在子專案或 worktree 執行時 fallback 到 user-level settings
