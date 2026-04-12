---
name: pr-convention
description: >
  Creates or edits GitHub pull requests following team conventions via gh CLI.
  Use when the user asks to create a PR, open a PR, edit a PR description, or
  prepare a pull request in any repository. Trigger keywords: "PR",
  "pull request", "gh pr create", "gh pr edit", "open PR", "發 PR".
metadata:
  author: Polaris
  version: 1.3.0
---

# PR Convention

## Workflow

### 1. Detect and parse repo PR template

Check for a PR template file in this priority order (stop at the first match):

1. `.github/pull_request_template.md`
2. `.github/PULL_REQUEST_TEMPLATE.md`
3. `.github/PULL_REQUEST_TEMPLATE/default.md`
4. `docs/pull_request_template.md`
5. `pull_request_template.md` (repo root)

```bash
# Try each path in order; use the first that exists
for f in .github/pull_request_template.md \
         .github/PULL_REQUEST_TEMPLATE.md \
         .github/PULL_REQUEST_TEMPLATE/default.md \
         docs/pull_request_template.md \
         pull_request_template.md; do
  [ -f "$f" ] && cat "$f" && break
done
```

**If a template is found**, parse its `## ` headings as the section skeleton. Each
heading becomes a section in the PR body, in the same order as the template.
HTML comments (`<!-- ... -->`) under each heading are hints for what content goes
there — read them to understand intent, but replace them with actual content.

Store the parsed section list for use in Step 4. Example parse result:

```
Sections: [Description, Changed, Screenshots (Test Plan), Related documents, QA notes]
```

**If no template is found**, fall back to the default section list in Step 4b.

### 2. Determine base branch

**2a. Check for dependency branch (priority):**

If the current branch was created from a non-standard base (not develop/master), detect it:

```bash
CURRENT_BRANCH=$(git branch --show-current)
# Extract JIRA key from branch name (e.g. task/PROJ-123-xxx → PROJ-123)
JIRA_KEY=$(echo "$CURRENT_BRANCH" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+')
```

Then check JIRA comments for dependency markers (`base on`, `depends on`, `依賴`, `需等`).
If a dependency ticket is found, locate its branch using multi-strategy search
(same as references/branch-creation.md § dependency branch): PR by JIRA key → PR by summary → sub-task keys → git branch.

If found and the dependency PR is still open → set base to that branch.
If the dependency PR is already merged → use `develop` (the dependency code is already in develop).

Always confirm with user:

> 偵測到此單依賴 PROJ-124（branch: `feat/PROJ-125-...`，PR 尚未 merge）。PR base 設為該 branch？

**2b. Standard auto-detect (fallback):**

```bash
gh repo view --json defaultBranchRef -q .defaultBranchRef.name
```

Only ask if auto-detection fails. Do not list options unprompted.

### 3. Build PR title

Format: `[JIRA-KEY] <concise summary>`

| Example |
|---------|
| `[PROJ-456] 移除售前客服商品頁導流 AB test 相關邏輯` |
| `[VM-1186] JP DX メインページ改修` |
| `[NO-JIRA] Fix typo in checkout footer` |

If no JIRA key is available, ask for one. Use `[NO-JIRA]` only as a last resort.

### 4. Build PR body

Fill every section — never leave a section as `...` or empty.

**4a. 偵測是否為母單 PR（feature branch → develop）**

如果 head branch 是 `feat/<EPIC_KEY>-*` 且 base 是 `develop`，這是母單 PR — 子單已各自 code review 過，不需要再逐行審查。使用母單專用模板：

```md
## ⚡ 母單 PR — 子單已各自 Code Review

此 PR 合併以下已審過的子單到 develop，**不需要逐行 review**。

| 子單 | PR | Approvals | 狀態 |
|------|-----|-----------|------|
| <SUB_KEY> | #<number> | ✅ N/N | merged |

所有子單均已通過 Code Review + CI，可直接 Approve。

## Description
<Epic 概述 — 從 JIRA Epic description 的背景與目標段落提取>

## Related documents
JIRA Epic: https://{config: jira.instance}/browse/<EPIC_KEY>
```

子單表格從 `gh pr list --base feat/<EPIC_KEY>-* --state merged` 自動取得。

**4b. 一般 PR 模板（非母單）**

**If a template was found in Step 1**, use the template's section order as the
skeleton. For each section heading from the template:

1. **Known section** — match by heading name (case-insensitive) and fill with
   skill-generated content per the mapping table below
2. **Unknown section** — keep the heading as-is; use the template's HTML comment
   as a hint to generate appropriate content from the diff and commit history
3. **AC Coverage injection** — if the template does not include an `AC Coverage`
   section but JIRA AC data is available, insert it after the section closest to
   "Changed" or "Description" (wherever change details end and evidence begins)

| Template heading (case-insensitive match) | Fill logic |
|-------------------------------------------|-----------|
| `Description` | 從 diff + commit 摘要變更目的 |
| `Changed` | 條列技術改動與 side effect |
| `AC Coverage` | AC checklist（見下方產生規則） |
| `Screenshots` / `Test Plan` / `Screenshots (Test Plan)` | 截圖、錄影或文字描述 |
| `Related documents` | JIRA / Confluence / 討論連結 |
| `QA notes` | QA 測試方法；N/A 則說明原因 |
| `Checklist` / `Pre-merge checklist` | 根據 PR 改動勾選對應項目 |
| `Breaking Changes` / `Breaking changes` | 列出 breaking changes 或標註 None |
| Other headings | 根據 heading 名稱 + HTML comment hint 生成內容 |

**If no template was found**, use the default section list:

```md
## Description
<說明變更內容>

## Changed
<條列技術改動與 side effect>

## AC Coverage
- [x] AC1: <AC 描述> → [驗證報告](https://{config: jira.instance}/browse/<驗證子單 KEY>)
- [x] AC2: <AC 描述> → [驗證報告](https://{config: jira.instance}/browse/<驗證子單 KEY>)
- [ ] AC3: <AC 描述>（out of scope, 見 <JIRA-KEY>）

## Screenshots (Test Plan)
<截圖、錄影或文字描述測試結果；若無則寫明原因>

## Related documents
<列出 JIRA / Confluence / 討論連結>

## QA notes
<QA 測試方法；若不適用則寫 N/A 並說明原因>
```

**AC Coverage 產生規則：**
1. 從 JIRA ticket description 的 AC 欄位（Acceptance Criteria）讀取所有 AC 條目
2. 對照本次 PR 的改動範圍，逐一判斷每條 AC 是否已涵蓋：
   - `[x]` → 此 PR 已實作並驗證
   - `[ ]` → 未涵蓋（需附說明：out of scope、另一張單處理、待後續）
3. 若 verify-completion 結果可用，以其驗證結果作為 `[x]`/`[ ]` 依據
4. **每條 AC 連結到對應的 [驗證] 子單**（JIRA URL），讓 reviewer 點進去看驗證報告 comment。格式：`→ [驗證報告](https://{config: jira.instance}/browse/<KEY>)`。注意：GitHub 會 sanitize 掉 `target="_blank"`，所以用標準 Markdown link 即可（外部連結在 GitHub 上預設就會另開分頁）。若該 AC 沒有對應驗證子單則不加連結
5. **找不到 AC → 跳過此 section**（不阻擋 PR 流程，不留空的 AC Coverage）

### 5. Create or edit the PR

**Create:**

```bash
gh pr create \
  --title "[JIRA-KEY] <summary>" \
  --body "$(cat <<'EOB'
## Description
移除售前客服商品頁導流 AB test 相關邏輯，包含 feature flag 與相關元件。

## Changed
- 移除 `PreSaleABTest` 元件及相關 hooks
- 清除 feature flag `presale_ab_test` 判斷邏輯
- Side effect: 售前客服入口將固定顯示，不再走 AB 分流

## AC Coverage
- [x] AC1: 移除 AB test feature flag 後，售前客服入口固定顯示
- [x] AC2: 移除後無 console error，hydration 正常

## Screenshots (Test Plan)
已於 dev 環境驗證商品頁客服入口正常顯示。

## Related documents
JIRA: https://{config: jira.instance}/browse/PROJ-456

## QA notes
確認商品頁客服入口正常顯示即可，無需測試 AB 分流。
EOB
)" \
  --base develop
```

**Edit:**

```bash
gh pr edit <pr-number> \
  --title "[JIRA-KEY] <summary>" \
  --body "$(cat <<'EOB'
...
EOB
)"
```

**View:**

```bash
gh pr view <pr-number> --json title,body
```

## Pre-merge checklist

Before creating or finalising a PR, verify the following items and fix any violations proactively:

### Type safety
- Run the relevant type-check command (e.g. `tsc --noEmit`, or IDE diagnostics) on changed files.
- Fix **all** type errors (including implicit `any`) introduced by the PR before requesting review.
- For `.js` files, add JSDoc type annotations where the linter or IDE reports implicit-any warnings.

### Test coverage (codecov/patch)
- Every new or changed **logic** (functions, validators, helpers) must have corresponding unit tests.
- Test files must live alongside the source file and use the **`.test.ts` / `.test.js`** (or `.spec.ts` / `.spec.js`) suffix.
- Verify codecov/patch passes by checking the CI status after push; if it fails, add the missing tests before requesting review.

### Code duplication
- If the same logic is copy-pasted across two or more files, extract it into a shared module before merging.

## Do / Don't

- Do: include a concrete Test Plan (steps + expected result), even if it's "N/A — config-only change".
- Do: list side effects / risks in Changed.
- Do: confirm type-check and codecov/patch CI pass before marking PR as ready.
- Do: PR description 自動嵌入 AC Coverage checklist，讓 reviewer 一眼看出覆蓋狀況。
- Don't: leave any template section blank or with placeholder text.
- Don't: use vague titles like "fix bug" or "update code".
- Don't: paste long chat logs or internal secrets into the description.
- Don't: use non-standard test file suffixes — use `.test.ts` / `.test.js` or `.spec.ts` / `.spec.js`.
- Don't: 對母單 PR 要求逐行 code review — 子單已各自審過，母單只是合併到 develop。
- Don't: 找不到 AC 時硬塞空的 AC Coverage section — 直接跳過不留空佔位。


## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
