---
name: bug-triage
description: >
  Bug diagnostic skill: root cause analysis and RD confirmation for Bug tickets.
  Use when the user wants to triage, analyze, or diagnose a Bug ticket — before planning starts.
  Trigger: '修 bug', 'fix bug', '分析 bug', 'triage bug', 'bug 分析', '修這張 bug',
  'help me fix', '幫我修正', '開始修正', '修正這張', 'fix this ticket' (when issue type is Bug),
  'debug', '找 bug', '為什麼壞了', 'why is this failing', 'investigate', '查問題',
  '這個怎麼回事', 'root cause', '根因', '排查'.
  NOT for: PR review fixes (use engineering revision mode), already-diagnosed bugs with root cause confirmed (use breakdown → engineering).
  This skill handles DIAGNOSIS only — estimation, test plan, QA challenge, and design doc are delegated to breakdown.
metadata:
  author: Polaris
  version: 2.2.0
---

# Bug Triage — 診斷層

Bug 票的診斷技能。定位根因、確認方向，為 `breakdown` 提供已確認的技術分析。

**職責邊界**：bug-triage 只做診斷（探索 → 根因 → RD 確認 → enriched ticket）。不做估點、不做測試計畫、不寫 Design Doc — 那是 `breakdown` 的工作。不建 branch、不寫 code、不開 PR — 那是 `engineering` 的工作。

**三層架構定位**：
```
Layer 1 理解: bug-triage (Bug) / refinement (Epic/Story)
Layer 2 派工: breakdown (通用：估點 + 測試 + QA Challenge + Design Doc)
Layer 3 施工: engineering (branch + TDD + 品質 + PR)
```

## Step 1 — Read Ticket & Identify Project

1. Parse ticket key from user input (or current branch if not provided)
2. Parallel:
   - `getJiraIssue` — read full ticket (summary, description, AC, labels, status, assignee)
   - Check `fields.issuetype.name` — if not Bug, tell user and suggest the correct skill:
     - Story/Task → `breakdown` or `engineering`
     - Epic → `refinement` → `breakdown`
3. Identify project per `references/project-mapping.md` (Summary `[tag]` → workspace config `projects` block)
4. Check if root cause is already confirmed (JIRA comments contain `[ROOT_CAUSE]` section):
   - If confirmed → "已有根因分析，要重新分析還是直接進派工？（breakdown {TICKET}）"
5. **Check for AC-FAIL origin**: if ticket description starts with `## [VERIFICATION_FAIL]` (created by verify-AC skill on implementation-drift disposition) → route to **AC-FAIL Path** (Step 2-AF), skipping Step 2-3 full exploration. verify-AC has already presented observed vs expected as facts; bug-triage's job is narrower — locate the code defect on the feature branch.

## Step 2-AF — AC-FAIL Path (for [VERIFICATION_FAIL] Bugs)

When Step 1.5 detects `[VERIFICATION_FAIL]` prefix, skip the generic Step 2-3 exploration and use the structured追溯 info that verify-AC already wrote.

### 2-AF.1 — Parse [VERIFICATION_FAIL] block

Extract from ticket description:

| Field | Example | Usage |
|-------|---------|-------|
| 來源 AC 驗收單 | `TASK-123` | Link context, not re-verification |
| Epic | `PROJ-123` | Root for related work orders |
| **分析對象 branch** | `feat/PROJ-123-breadcrumblist-seo` | **Primary investigation surface — NOT develop/main** |
| Repos 涉入 | `your-app, your-backend` | Scope of analysis |
| 相關 Task keys | `TASK-123, TASK-123` | Link to task.md work orders |
| 相關 PR numbers | `#2100, #2101` | PR diffs = exact change set |
| Feature branch commit range | `{base_sha}..{head_sha}` | Bounded git log scope |
| **失敗項目** | `AC#2: Observed X, Expected Y` | What to reproduce + fix |
| 復現條件 | URL, locale, viewport, fixtures | How to reproduce |
| 驗證 metadata | curl / Playwright / timestamp | Reference only |

### 2-AF.2 — Scoped investigation (Explorer sub-agent, feature-branch-only)

Dispatch Explorer (`standard_coding`) with a **narrower** prompt than the generic Step 3:

```
Prompt: AC 驗證失敗，定位 feature branch 上的 code 缺陷。

來自 verify-AC 的事實（不需重驗證）：
- Observed: {actual behavior}
- Expected: {AC spec}
- 復現條件: {URL, locale, viewport, fixtures}

**分析範圍（硬邊界）**：
- Branch: {feat/...-branch-name}（不是 develop/main）
- Repos: {repo_a}, {repo_b}
- Commit range: {base_sha}..{head_sha}
- PRs: {#N1}, {#N2}（diff 是確切改動範圍）

任務：
1. 讀 {company}/polaris-config/{project}/handbook/ 了解架構
2. 從 PR diff + feature branch code 找出 observed behavior 的產生點
3. 對比 expected — 判斷是「缺實作」「實作錯了」「邊界條件漏了」還是「依賴整合出錯」
4. 評估最小修正範圍（必須在 feature branch 上修，不可回 develop/main）

**禁止**：
- 跑 `git log --author`、`git blame`（assignee 層的資訊 bug-triage 不應知道）
- 重跑 verify-AC 已執行的驗證步驟
- 擴大到 feature branch 以外的 code

回傳格式：同 Step 3 Full Path 的 Root Cause / Impact / Proposed Fix。
Proposed Fix 的「預估改動」必須限定在 {repos} 的 feature branch 上。
```

Sub-agent dispatch 必須注入 Completion Envelope spec（見 `skills/references/sub-agent-roles.md`）。Detail 同時是下一 skill（engineering）的 handoff artifact（見 `skills/references/handoff-artifact.md`）：

- **路徑**：`{company_specs_dir}/{EPIC}/artifacts/bug-triage-ac-fail-{BUG_KEY}-{timestamp}.md`（timestamp 格式 `YYYY-MM-DDTHHMMSSZ` UTC）。主 checkout 絕對路徑（gitignored，worktree 以此讀寫）。詳見 `skills/references/worktree-dispatch-paths.md`。
- **格式**：frontmatter（`skill: bug-triage`、`ticket: {BUG_KEY}`、`scope: ac-fail`、`timestamp`、`truncated: false`、`scrubbed: false`）+ `## Summary`（≤ 500 字，Root Cause / Impact / Proposed Fix 壓縮版）+ `## Raw Evidence`（grep 結果、PR diff 片段、[VERIFICATION_FAIL] block、suspect code 行號）
- **寫入後必跑 scrub + cap**：`python3 scripts/snapshot-scrub.py --file {artifact_path}`（scrub secrets、20KB 截斷、更新 frontmatter flag）。Sub-agent 完成寫入後執行一次，然後才把 Detail 路徑回傳給 Strategist

### 2-AF.3 — Fall through to Step 4

AC-FAIL path 產出同樣的 Root Cause / Impact / Proposed Fix 結構 → 直接進 **Step 4 RD Confirmation**（hard stop 不變）→ Step 5 寫回 JIRA。

### 2-AF.4 — Handoff override

Step 5c 的 handoff 訊息改為：

```markdown
## ✅ AC-FAIL Bug 診斷完成 — {BUG_KEY}

對應 AC 驗收單：{AC_TICKET_KEY}
分析對象：{feature_branch_name}

| Item | Status |
|------|--------|
| Root Cause（feature branch 上的） | ✅ 已確認 |
| JIRA Comment | ✅ 已更新 |
| Proposed Fix | ✅ {scope summary} |
| Evidence artifact | {artifact_path} |

---
說「做 {BUG_KEY}」進入施工。engineering 會 checkout **{feature_branch_name}**（不是 develop），在上面開 fix branch。
修完 PR merge 回 feature branch 後，說「驗 {EPIC_KEY}」跑 verify-AC full re-run。
```

## Step 2 — Fast-Path Detection

Evaluate whether this bug qualifies for the simplified fast path:

| Criteria | Fast Path | Full Path |
|----------|-----------|-----------|
| Root cause clarity | Obvious from ticket description (typo, wrong value, missing condition) | Requires codebase investigation |
| Scope | Single file, ≤ 20 lines changed | Multi-file or cross-module |

**Both criteria must be met for fast path.** When in doubt, use full path.

Fast path simplification: Step 3 analyzes inline (no Explorer sub-agent).

## Step 3 — Root Cause Analysis

### Full Path

Dispatch an **Explorer sub-agent** (`standard_coding`) to investigate the codebase:

```
Prompt: 分析 Bug {TICKET} 的根因。

Ticket 資訊：
- Summary: {summary}
- Description: {description}
- AC/重現步驟: {acceptance criteria or repro steps}

專案目錄: {project_dir}

任務：
1. 先讀 {company}/polaris-config/{project}/handbook/ 了解專案架構
2. 找到相關程式碼（根據 ticket 描述的功能/頁面/元件）
3. 判斷根因：哪個檔案、哪段邏輯、為什麼壞了
4. 評估影響範圍：還有哪些地方用到同一段邏輯？修改會不會連動？
5. 提出修正方向（不需要寫 code，只要方向）

回傳格式：
### Root Cause
- 檔案: {path}
- 問題: {一句話描述}
- 原因: {為什麼會發生}

### Impact
- 影響範圍: {哪些功能/頁面受影響}
- 連動風險: {修改可能影響的其他地方}

### Proposed Fix
- 方向: {修正策略}
- 預估改動: {檔案數, 行數}

### Handbook Observations
- Gaps: {handbook 缺少的相關資訊}
- Stale: {handbook 中過時的資訊}
```

回傳使用 Completion Envelope 格式（見 `skills/references/sub-agent-roles.md`）。Detail 同時是下一 skill（engineering）的 handoff artifact（見 `skills/references/handoff-artifact.md`）：

- Summary ≤ 3 句（根因、影響範圍、修正方向）回傳給 Strategist
- **Detail 寫入**：`specs/{EPIC}/artifacts/bug-triage-root-cause-{TICKET}-{timestamp}.md`（timestamp 格式 `YYYY-MM-DDTHHMMSSZ` UTC）
- **格式**：frontmatter（`skill: bug-triage`、`ticket: {TICKET}`、`scope: root-cause`、`timestamp`、`truncated: false`、`scrubbed: false`）+ `## Summary`（≤ 500 字，Root Cause / Impact / Proposed Fix 壓縮版）+ `## Raw Evidence`（grep 結果、suspect code 行號、commit hash、error trace、handbook relevant excerpt）
- **寫入後必跑 scrub + cap**：`python3 scripts/snapshot-scrub.py --file {artifact_path}`（scrub secrets、20KB 截斷、更新 frontmatter flag）。Sub-agent 完成寫入後執行一次，然後才把 Detail 路徑回傳給 Strategist

### Fast Path

Analyze inline based on ticket description. Still produce the same Root Cause / Impact / Proposed Fix structure, but from ticket info + quick file read (≤ 3 files).

## Step 4 — RD Confirmation (Hard Stop)

Present root cause analysis to user in structured format:

```markdown
## 🔍 Bug 根因分析 — {TICKET}

### Root Cause
{from Explorer}

### Impact
{from Explorer}

### Proposed Fix
{from Explorer}

---
⏸ **請確認根因分析是否正確，再繼續。**
如果根因不對，請指正，我會重新分析。
```

**This is a hard stop.** Do not proceed until user explicitly confirms. If user corrects the analysis, re-run Step 3 with the new information (max 2 re-analyses; if still wrong after 2 rounds, escalate: "建議直接看 code 確認，要開 branch 先探索嗎？").

## Step 5 — Enrich JIRA & Handoff

After RD confirmation:

### 5a — Write Root Cause to JIRA

Add a JIRA comment with confirmed root cause (REST API v2 wiki markup):

**Workspace language policy gate（blocking）**：完整規則見 `references/workspace-language-policy.md`。送出 JIRA diagnostic comment 前，先把最終 comment body 寫成 temp markdown，執行：

```bash
bash scripts/validate-language-policy.sh --blocking --mode artifact <bug-triage-root-cause-comment.md>
```

exit ≠ 0 → 修正 comment 主敘述語言後重跑；不可把未通過 gate 的 `[ROOT_CAUSE]` / `[IMPACT]` / `[PROPOSED_FIX]` 寫入 JIRA。

```
h3. [ROOT_CAUSE]
{confirmed root cause description}
檔案: {file path(s)}
原因: {why it happens}

h3. [IMPACT]
影響範圍: {affected features/pages}
連動風險: {related areas}

h3. [PROPOSED_FIX]
方向: {fix direction}
預估改動: {file count, scope}
```

This comment becomes the input for `breakdown` — it reads `[ROOT_CAUSE]` to skip re-analysis.

### 5b — Process Handbook Observations

If the Explorer sub-agent returned Handbook Observations (gaps or stale info), process them per `references/explore-pattern.md`:
- Gaps → write to `{company}/polaris-config/{project}/handbook/` appropriate sub-file
- Stale → mark or fix in handbook

### 5c — Handoff

Fast Path 沒有 Explorer 產 artifact；Full Path 的 artifact 路徑會在 handoff 訊息標出來讓 engineering on-demand 讀：

```markdown
## ✅ Bug 診斷完成 — {TICKET}

| Item | Status |
|------|--------|
| Root Cause | ✅ 已確認 |
| JIRA Comment | ✅ 已更新 |
| Proposed Fix | ✅ {scope summary} |
| Evidence artifact | {artifact_path or "— (Fast Path)"} |

---
說「breakdown {TICKET}」進入派工（估點 + 測試計畫 + Design Doc）。
或說「做 {TICKET}」直接施工（engineering 會檢查 plan 是否存在）。
```

## Error Handling

- **JIRA API failure**: report which operation failed, suggest manual fallback
- **Explorer sub-agent returns inconclusive**: present what was found, ask user for hints (specific file, module, or feature area)
- **Root cause changes mid-triage**: if user provides new info after Step 4 confirmation, re-run from Step 3 with new context

## Post-Task Reflection

Per `references/post-task-reflection-checkpoint.md`:
- Check for user corrections → feedback memory or handbook update
- Check for framework gaps → backlog entry
- Version bump reminder if rules/skills were modified
