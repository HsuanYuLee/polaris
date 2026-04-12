---
name: bug-triage
description: >
  Bug diagnostic skill: root cause analysis and RD confirmation for Bug tickets.
  Use when the user wants to triage, analyze, or diagnose a Bug ticket — before planning starts.
  Trigger: '修 bug', 'fix bug', '分析 bug', 'triage bug', 'bug 分析', '修這張 bug',
  'help me fix', '幫我修正', '開始修正', '修正這張', 'fix this ticket' (when issue type is Bug).
  NOT for: PR review fixes (use fix-pr-review), already-diagnosed bugs with root cause confirmed (use breakdown → work-on).
  This skill handles DIAGNOSIS only — estimation, test plan, QA challenge, and design doc are delegated to breakdown.
metadata:
  author: Polaris
  version: 2.0.0
---

# Bug Triage — 診斷層

Bug 票的診斷技能。定位根因、確認方向，為 `breakdown` 提供已確認的技術分析。

**職責邊界**：bug-triage 只做診斷（探索 → 根因 → RD 確認 → enriched ticket）。不做估點、不做測試計畫、不寫 Design Doc — 那是 `breakdown` 的工作。不建 branch、不寫 code、不開 PR — 那是 `work-on` 的工作。

**三層架構定位**：
```
Layer 1 理解: bug-triage (Bug) / refinement (Epic/Story)
Layer 2 派工: breakdown (通用：估點 + 測試 + QA Challenge + Design Doc)
Layer 3 施工: work-on (branch + TDD + 品質 + PR)
```

## Step 1 — Read Ticket & Identify Project

1. Parse ticket key from user input (or current branch if not provided)
2. Parallel:
   - `getJiraIssue` — read full ticket (summary, description, AC, labels, status, assignee)
   - Check `fields.issuetype.name` — if not Bug, tell user and suggest the correct skill:
     - Story/Task → `breakdown` or `work-on`
     - Epic → `refinement` → `breakdown`
3. Identify project per `references/project-mapping.md` (Summary `[tag]` → workspace config `projects` block)
4. Check if root cause is already confirmed (JIRA comments contain `[ROOT_CAUSE]` section):
   - If confirmed → "已有根因分析，要重新分析還是直接進派工？（breakdown {TICKET}）"

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

Dispatch an **Explorer sub-agent** (sonnet) to investigate the codebase:

```
Prompt: 分析 Bug {TICKET} 的根因。

Ticket 資訊：
- Summary: {summary}
- Description: {description}
- AC/重現步驟: {acceptance criteria or repro steps}

專案目錄: {project_dir}

任務：
1. 先讀 {repo}/.claude/rules/handbook/ 了解專案架構
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
- Gaps → write to `{repo}/.claude/rules/handbook/` appropriate sub-file
- Stale → mark or fix in handbook

### 5c — Handoff

```markdown
## ✅ Bug 診斷完成 — {TICKET}

| Item | Status |
|------|--------|
| Root Cause | ✅ 已確認 |
| JIRA Comment | ✅ 已更新 |
| Proposed Fix | ✅ {scope summary} |

---
說「breakdown {TICKET}」進入派工（估點 + 測試計畫 + Design Doc）。
或說「做 {TICKET}」直接施工（work-on 會檢查 plan 是否存在）。
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
