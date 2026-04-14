# PR Body Builder

PR template 偵測、body 組裝、AC Coverage 產生的共用流程。

**消費者**：`engineer-delivery-flow.md § Step 7`（Developer 與 Admin 兩角色共用）。

本 reference 從原 `pr-convention` skill（v1.3.0）抽出。原 skill 已刪除 — PR 生命週期統一由 `engineer-delivery-flow` 驅動。

---

## 1. Detect PR Template

依序檢查以下路徑（命中即停）：

1. `.github/pull_request_template.md`
2. `.github/PULL_REQUEST_TEMPLATE.md`
3. `.github/PULL_REQUEST_TEMPLATE/default.md`
4. `docs/pull_request_template.md`
5. `pull_request_template.md`（repo root）

**命中**：解析 `## ` headings 作為 section skeleton。HTML comments（`<!-- ... -->`）是 hints — 讀取理解但以實際內容取代。

**未命中**：使用 § 3 的預設 section list。

---

## 2. Build PR Title

### Developer（有 JIRA ticket）

格式：`[JIRA-KEY] <concise summary>`

| 範例 |
|------|
| `[TASK-123] 產品頁 BreadcrumbList 加首頁 entry` |
| `[PROJ-123] BreadcrumbList SEO 優化` |

### Admin（無 JIRA ticket）

格式：`<type>(<scope>): <summary>`（conventional commit）

| 範例 |
|------|
| `feat(pipeline): engineer delivery flow redesign` |
| `fix(skill): correct VR domain matching` |

---

## 3. Build PR Body

### 3a. 母單 PR 偵測

若 head branch 是 `feat/<EPIC_KEY>-*` 且 base 是 `develop` → 母單 PR。子單已各自 code review，不需逐行審查：

```md
## 母單 PR — 子單已各自 Code Review

此 PR 合併以下已審過的子單到 develop，**不需要逐行 review**。

| 子單 | PR | Approvals | 狀態 |
|------|-----|-----------|------|
| <SUB_KEY> | #<number> | N/N | merged |

所有子單均已通過 Code Review + CI，可直接 Approve。

## Description
<Epic 概述>

## Related documents
JIRA Epic: https://{jira_instance}/browse/<EPIC_KEY>
```

子單表格從 `gh pr list --base feat/<EPIC_KEY>-* --state merged` 取得。

### 3b. 一般 PR（非母單）

**有 template**：按 template section 順序填充。對每個 heading：

| Template heading（case-insensitive） | Fill logic |
|--------------------------------------|-----------|
| `Description` | diff + commit 摘要變更目的 |
| `Changed` | 條列技術改動與 side effect |
| `AC Coverage` | AC checklist（見 § 4） |
| `Screenshots` / `Test Plan` | 截圖、錄影或文字描述 |
| `Related documents` | JIRA / Confluence / 討論連結 |
| `QA notes` | QA 測試方法；N/A 則說明原因 |
| `Checklist` / `Pre-merge checklist` | 根據改動勾選項目 |
| `Breaking Changes` | 列出或標註 None |
| Other headings | 根據 heading + HTML comment hint 生成 |

**無 template**：使用預設 skeleton：

```md
## Description
<說明變更內容>

## Changed
<條列技術改動與 side effect>

## AC Coverage
<見 § 4>

## Screenshots (Test Plan)
<截圖或文字描述>

## Related documents
<JIRA / Confluence link>

## QA notes
<QA 測試方法 / N/A + 原因>
```

### 3c. AC Coverage injection

若 template 無 `AC Coverage` section 但 JIRA AC 可用 → 在 `Changed` 或 `Description` 之後插入。

---

## 4. AC Coverage 產生規則

1. 從 JIRA ticket description 讀取 AC 條目
2. 對照 PR diff + engineer-delivery-flow Step 3 驗證結果：
   - `[x]` → 此 PR 已實作並驗證
   - `[ ]` → 未涵蓋（附說明：out of scope / 另一張單 / 待後續）
3. 每條 AC 連結到對應的 [驗證] 子單：`→ [驗證報告](https://{jira_instance}/browse/<KEY>)`
4. **找不到 AC → 跳過此 section**（不留空佔位）

範例：

```md
## AC Coverage
- [x] AC1: 產品頁 breadcrumb 含首頁 entry → [驗證報告](https://example.atlassian.net/browse/TASK-123)
- [x] AC2: JSON-LD 移至 `<head>` → [驗證報告](https://example.atlassian.net/browse/TASK-123)
- [ ] AC3: GA 事件追蹤（out of scope, 見 PROJ-123）
```

---

## 5. Bug RCA 偵測（Developer only）

PR 建立後，若 JIRA ticket 是 Bug 類型且無 `[ROOT_CAUSE]` comment → 詢問開發者是否順便補寫 RCA。

### 跳過條件（符合任一即跳過）

- 無法解析 JIRA key（`[NO-JIRA]`）
- Admin 模式
- 母單 PR
- JIRA 查詢失敗（網路錯誤、權限問題）

### 流程

1. `getJiraIssue` 查 issue type
2. 非 Bug → 跳過
3. Bug → 搜尋 comments 中的 `[ROOT_CAUSE]`、`[SOLUTION]`、`根因`
4. 已有 RCA → 跳過
5. 尚無 RCA → 詢問：「Bug 單尚無 RCA 紀錄。要順便補寫嗎？」
   - 確認 → chain 到 `bug-rca` skill Step 4-5（若 skill 存在）
   - 拒絕 → 不阻擋

---

## 6. PR Create / Edit Command

### Create

```bash
POLARIS_PR_WORKFLOW=1 gh pr create \
  --base <detected-base> \
  --title "<title>" \
  --body "$(cat <<'EOB'
<body content>
EOB
)"
```

`POLARIS_PR_WORKFLOW=1` 讓 pre-PR hook 放行。

### Edit

```bash
gh pr edit <pr-number> \
  --title "<title>" \
  --body "$(cat <<'EOB'
<body content>
EOB
)"
```

---

## Do / Don't

- Do: 每個 template section 都填實際內容，不留 placeholder
- Do: PR description 自動嵌入 AC Coverage checklist
- Do: Bug 單詢問 RCA — 選擇性步驟，拒絕不阻擋
- Don't: 母單 PR 要求逐行 review
- Don't: AC 找不到時留空的 section
- Don't: vague title（"fix bug"、"update code"）
- Don't: JIRA 查詢失敗阻擋 PR 建立

---

## 來源

從原 `pr-convention` skill（v1.3.0）抽出。2026-04-14 work-on 重構 Phase 4 將 PR body 邏輯降級為 reference，消除獨立 skill 的路由歧義。
