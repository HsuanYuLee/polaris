# PR Body Builder

PR template 偵測、body 組裝、AC Coverage 產生的共用流程。

**消費者**：`engineer-delivery-flow.md § Step 7`（Developer 與 Admin 兩角色共用）。

本 reference 從原 `pr-convention` skill（v1.3.0）抽出。原 skill 已刪除 — PR 生命週期統一由 `engineer-delivery-flow` 驅動。

---

## 1. Detect PR Template（L1→L2→L3 fallback chain，D23）

**L1 — Repo template**（最權威）：依序檢查以下路徑（命中即停）：

1. `.github/pull_request_template.md`
2. `.github/PULL_REQUEST_TEMPLATE.md`
3. `.github/PULL_REQUEST_TEMPLATE/default.md`
4. `docs/pull_request_template.md`
5. `pull_request_template.md`（repo root）

**命中**：解析 `## ` headings 作為 section skeleton。HTML comments（`<!-- ... -->`）是 hints — 讀取理解但以實際內容取代。

**L2 — Company config**：L1 未命中時，檢查 workspace-config `pr_template` 路徑（若有設定）。

**L3 — Polaris default**：L1 + L2 均未命中 → 使用 § 3b 的預設 skeleton。

**規則衝突**：L1 命中即停 — L2/L3 不補充 L1 已覆蓋的 section。

---

## 1.5. Section Classification（D23）

每個 PR body section 分為三類：

| 分類 | 定義 | 範例 |
|------|------|------|
| **must-inject** | engineering **一定**填入，無論 template 有無該 heading | `AC Coverage`（Developer）、`Evidence Summary`（evidence AND gate 摘要） |
| **conditional** | 有相關資料才填 | `Screenshots`、`Bug RCA`、`Breaking Changes`、`VR Diff` |
| **follow-template** | 依 L1 template heading 填充，template 無此 heading 就不加 | `QA notes`、`Checklist`、`Pre-merge checklist`、其他自定義 heading |

**Injection 規則**：
- must-inject section 若 template 已有對應 heading → 就地填充
- must-inject section 若 template 無對應 heading → 在 `Changed` 或 `Description` 之後插入
- conditional section 條件未觸發 → 整段不出現（不留空佔位）

---

## 2. Build PR Title

### Developer（有 JIRA ticket）

格式：`[JIRA-KEY] <concise summary>`

| 範例 |
|------|
| `[KB2CW-3788] 產品頁 BreadcrumbList 加首頁 entry` |
| `[GT-521] BreadcrumbList SEO 優化` |

### Admin（無 JIRA ticket）

格式：`<type>(<scope>): <summary>`（conventional commit）

| 範例 |
|------|
| `feat(pipeline): engineer delivery flow redesign` |
| `fix(skill): correct VR domain matching` |

---

## 3. Build PR Body

### 3.0. Body language

PR body 的說明性文字必須使用 root `workspace-config.yaml` 的 `language` 值。

讀取順序：

1. root `workspace-config.yaml` 的 `language`（例如 `zh-TW`）
2. 若未設定，使用使用者本輪主要語言
3. 若仍無法判斷，使用 repo PR template HTML comments / headings 的主要語言

規則：

- `language: zh-TW` → PR body prose 用台灣繁體中文。
- `language: en` → PR body prose 用英文。
- code identifiers、commands、file paths、package names、JIRA keys、API names、official product names 保留原文。
- Template headings 保留 repo template 原文，不翻譯 heading。
- 不要混用「Summary / Verification」等非 template section 來避開 template；仍按 § 1 / § 1.5 / § 3b 填入既有 headings。

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

### 3c. Evidence Summary injection（must-inject，D23+D15）

PR body 必須包含 evidence AND gate 摘要（must-inject section）。若 template 無 `Evidence` heading，在 `AC Coverage` 或 `Changed` 之後插入。

**Developer 格式**：

```md
## Evidence Summary

| Layer | Status | Evidence |
|-------|--------|----------|
| A — CI (`ci-local.sh`) | ✅ PASS | `head_sha` matches |
| B — Verify (`run-verify-command.sh`) | ✅ PASS | `head_sha` matches |
| C — VR (`run-visual-snapshot.sh`) | ⏭️ N/A | VR not triggered |
```

**Admin 格式**：only Layer A（CI）row。

---

## 3d. Revision Fragment Overlay（D23）

Revision mode 更新 PR body 時，**overlay 變更 section，不重寫整份**。

| Section | Revision 行為 |
|---------|--------------|
| `Description` | 在末尾追加 `### Revision R{n}` 段落（修正摘要、signal 來源） |
| `AC Coverage` | 保持原始 checklist；新修正若影響 AC → 補充 note |
| `Evidence Summary` | 重寫（evidence AND gate 重新評估） |
| `Changed` | 在末尾追加修正項目（不刪原始 diff 摘要） |
| 其他 section | 不動 |

更新用 `gh pr edit --body`。

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
- [x] AC1: 產品頁 breadcrumb 含首頁 entry → [驗證報告](https://example.atlassian.net/browse/KB2CW-3791)
- [x] AC2: JSON-LD 移至 `<head>` → [驗證報告](https://example.atlassian.net/browse/KB2CW-3792)
- [ ] AC3: GA 事件追蹤（out of scope, 見 GT-522）
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
PR_BODY_FILE="$(mktemp -t polaris-pr-body.XXXXXX.md)"
cat > "$PR_BODY_FILE" <<'EOB'
<body content>
EOB

bash "${CLAUDE_PROJECT_DIR}/scripts/polaris-pr-create.sh" \
  --base <detected-base> \
  --title "<title>" \
  --body-file "$PR_BODY_FILE"
```

`polaris-pr-create.sh` 會執行 `gate-pr-body-template.sh` 與 PR language gate，確認 body 保留 repo PR template 的 `##` section headings 且符合 workspace 語言政策；請使用 `--body-file`，不要用 shell inline `--body` 手拼 Markdown，避免 backtick / code block 被 shell escape 弄壞。裸 `gh pr create` 與 `gh pr create --draft` 不可作為 Developer delivery endpoint；completion gate 會再讀 remote PR metadata/body，阻擋 draft、非 open、或 invalid remote PR body。

### Edit

```bash
set -euo pipefail
PR_BODY_FILE="$(mktemp -t polaris-pr-body.XXXXXX.md)"
cat > "$PR_BODY_FILE" <<'EOB'
<body content>
EOB

bash "${CLAUDE_PROJECT_DIR}/scripts/gates/gate-pr-body-template.sh" \
  --repo "$(git rev-parse --show-toplevel)" \
  --body-file "$PR_BODY_FILE"
bash "${CLAUDE_PROJECT_DIR}/scripts/validate-language-policy.sh" \
  --blocking \
  --mode artifact \
  "$PR_BODY_FILE"
gh pr edit <pr-number> \
  --title "<title>" \
  --body-file "$PR_BODY_FILE"
```

Edit path 必須 fail-stop：template gate 或 language gate 任一失敗，就不得執行 `gh pr edit`。Completion gate 只是最後兜底，不能取代 edit 前的 preflight。

---

## Do / Don't

- Do: 每個 template section 都填實際內容，不留 placeholder
- Do: 使用 `--body-file` 送出 PR body，避免 shell quoting 破壞 Markdown
- Do: create 走 `polaris-pr-create.sh`，edit 先跑 template gate + language gate
- Don't: 裸用 `gh pr create`、`gh pr create --draft`、或 `gh pr edit --body`
- Do: PR description 自動嵌入 AC Coverage checklist
- Do: Bug 單詢問 RCA — 選擇性步驟，拒絕不阻擋
- Don't: 母單 PR 要求逐行 review
- Don't: AC 找不到時留空的 section
- Don't: vague title（"fix bug"、"update code"）
- Don't: JIRA 查詢失敗阻擋 PR 建立

---

## 來源

從原 `pr-convention` skill（v1.3.0）抽出。2026-04-14 engineering 重構 Phase 4 將 PR body 邏輯降級為 reference，消除獨立 skill 的路由歧義。DP-032 D23 增加 L1→L2→L3 fallback chain、section classification、Evidence Summary must-inject、Revision fragment overlay。
