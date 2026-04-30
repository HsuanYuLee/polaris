# JIRA Ticket → 專案路徑對應表

透過 JIRA ticket 的 **Summary 中的 tag**（不分大小寫）判斷對應的本地專案路徑。

> **Config 優先**：優先從 workspace config 的 `projects` 區塊讀取對應表（參考 `references/workspace-config-reader.md`）。
> 以下為 **fallback** — 當 workspace config 不存在時使用。

## 對應規則（Fallback 值）

| Summary Tag | 專案目錄 | 說明 |
|---|---|---|
| `[app-a]` | `your-org-app-a` | Main frontend app |
| `[app-b]` | `your-org-app-b` | Secondary app |
| `[mobile]` | `your-org-mobile` | Mobile app |
| `[email]` | `your-org-email` | Email templates |
| `[ds]` | `your-design-system` | Design System |

## 使用方式

1. 讀取 workspace config 的 `projects` 區塊（若存在）
2. 從 JIRA ticket 的 Summary 欄位中擷取 `[...]` tag
3. 比對 config 的 `projects[].tags`（不分大小寫），取得 `name` 作為專案目錄
4. 若 config 不存在，使用上方 fallback 表
5. 專案完整路徑為 `{workspace.base_dir}/<專案目錄>`（base_dir 從 config 讀取，如 `~/work/your-company`）
6. 如果 Summary 中沒有 tag 或無法匹配，嘗試用 `projects[].keywords` 模糊匹配
7. 仍無法匹配，**詢問使用者**指定專案

## 適用 Skill

需要分析 codebase 的 skill 都應參考此對應表：
- `breakdown`（Bug 根因分析、Story/Task/Epic 拆子單與估點）
- `sasd-review`（SA/SD 需分析異動範圍）
