# Sub-agent Dispatch Patterns

How to dispatch sub-agents effectively. Three mandatory standards, three specialized protocols, and common prompt patterns for reference.

## 1. Mandatory Standards

### Completion Envelope

All sub-agents must return results with this 3-line header so the orchestrator can determine success without parsing prose:

```markdown
## Status: {DONE | BLOCKED | PARTIAL}
**Artifacts**: {files, URLs, ticket keys — or "none"}
**Summary**: {one-sentence result}
```

- `DONE` — task completed. Orchestrator proceeds.
- `BLOCKED` — cannot proceed. Must include `**Blocker**:` line.
- `PARTIAL` — some done, some not. Must include `**Remaining**:` line.

#### Return vs Save Separation

Sub-agents should structure their return with two distinct sections when the task involves cross-session context (e.g., implementation, analysis that may be resumed later):

```markdown
## Status: DONE
**Artifacts**: PR #123, branch task/TEAM-3500
**Summary**: Implemented i18n fallback for product page

### User Summary
（給使用者看的簡潔結果）
- PR 已開：#123
- 修改了 3 個檔案，測試全過

### Checkpoint State
（給 cross-session resume 用的完整脈絡，存入 memory 或 checkpoint）
- Branch: task/TEAM-3500 based on feat/PROJ-483
- Decisions: 選擇 extend existing composable 而非建新的（T2 taste call）
- Remaining risk: SSR hydration 未在 Docker 環境驗證
- Dependencies: 需等 feat/PROJ-483 merge 後 rebase
```

**When to include**: implementation tasks, multi-step analysis, anything the user might say "繼續" for in a future session.
**When to skip**: one-shot reads (exploration, PR status check, JIRA batch ops) — plain envelope is sufficient.

The Strategist uses `User Summary` for the response and `Checkpoint State` for memory/checkpoint writes. This prevents the common failure mode where cross-session memory is either too terse (lost context) or too verbose (clutters the user's view).

### Model Tier Selection

Choose model based on task type to balance cost and quality:

| Task Type | Model | Examples |
|-----------|-------|---------|
| **Explore / Analyze** | `"sonnet"` | Codebase scan, PR review, ticket analysis |
| **Execute / Fix** | `"sonnet"` | Implementation, fix review comments, CI fixes |
| **Template operations** | `"haiku"` | Batch JIRA sub-task creation, ticket field updates |

### Context Isolation

- Each sub-agent receives a **complete, self-contained prompt** — it has no access to the parent conversation
- Include all necessary context: ticket key, repo path, analysis results, file paths
- Specify what tools the sub-agent should/shouldn't use
- For implementation tasks, specify `isolation: "worktree"` when parallel execution is needed

---

## 2. Specialized Protocols

These roles have **multi-step interaction patterns** that warrant a canonical definition. Skills should cite these by name when dispatching.

### QA Challenger + Resolver

A multi-round challenge loop for test plan quality assurance.

**When to use**: `work-on` Step 5f (AC Gate), before implementation begins.

**Protocol**:
1. **QA Challenger** (sonnet) reviews the test plan and flags gaps:
   - Negative cases, boundary conditions, regression risks, environment differences, concurrency
   - Returns `⚠️ 需回應` or `✅ 涵蓋完整` per item
2. **QA Resolver** (sonnet) addresses each ⚠️ with concrete solutions
3. **QA Challenger** re-evaluates the solutions
4. Repeat until all ✅, or max 3 rounds → remaining ⚠️ escalated to user

**Return format** (Challenger):
```markdown
### 🔍 QA Challenge

| # | 類型 | 挑戰內容 | 建議補充的測試項目 |
|---|------|---------|------------------|
| 1 | ⚠️ 缺 negative case | {具體缺什麼} | {建議} |
| 2 | ✅ 涵蓋完整 | {哪些面向沒問題} | — |

### 結論
- ⚠️ 需回應：N 條
- ✅ 涵蓋完整：M 條
```

**Return format** (Resolver):
```markdown
## Round N — Resolver
(每個 ⚠️ 的解決方案)

## Round N — Challenger
(每個方案的 ✅/⚠️ 判定)

## Final Stable Test Plan
(穩定後的完整測試計畫)
```

---

### Architect Challenger

A one-shot estimation review that challenges story points and technical approach.

**When to use**: `jira-estimation` Step 8.4a, after estimation is complete but before writing to JIRA.

**Persona**: Staff Engineer with 10 years of experience. Not friendly — only finds problems.

**Review dimensions**:
1. **複雜度低估** — cross-service dependencies, migration, data backfill
2. **技術方案盲點** — simpler alternatives, edge cases
3. **影響範圍遺漏** — shared component blast radius
4. **拆單粒度** — sub-tasks > 5 points or < 1 point, dependency order

**Return format**:
```markdown
### 🏛️ Architect Challenge

| # | 類型 | 挑戰內容 | 建議 |
|---|------|---------|------|
| 1 | ⚠️ 複雜度低估 | {which sub-task, why} | {adjustment} |
| 2 | ✅ 合理 | {what's fine} | — |

### 結論
- ⚠️ 需回應：N 條
- ✅ 合理：M 條
```

---

### Critic (Pre-PR Review)

A structured code review that returns findings in a parseable format.

**When to use**: `git-pr-workflow` Step 4 (pre-PR review loop), `fix-pr-review` Step 9 (post-fix self review).

**Review scope**: `.claude/rules/` project rules, coding conventions, test coverage, type safety, security.

**Return format** (JSON):
```json
{
  "passed": true,
  "blocking": [],
  "non_blocking": [
    {
      "file": "path/to/file.ts",
      "line": 42,
      "severity": "suggestion",
      "message": "..."
    }
  ]
}
```

- `blocking` items prevent PR creation — must be fixed first
- `non_blocking` items are reported but don't block

---

## 3. Common Dispatch Patterns (Reference)

These are **not canonical roles** — they're common prompt patterns that skills use. Copy and adapt the pattern that fits your use case. No need to cite this file.

### Exploration Pattern

For codebase scanning. Always reference `explore-pattern.md` for adaptive exploration rules.

```markdown
你是 codebase 探索 agent。

## 目標
{what to find — files, patterns, dependencies, impact scope}

## 方法
先讀取 `skills/references/explore-pattern.md`，使用自適應探索模式。
用 Glob、Grep、Read 探索。不編輯任何檔案。

## 回傳
- 檔案清單 + 實作模式摘要
- 影響範圍評估

## 限制
- 只做讀取，不編輯
- 用本地 repo，不用 gh api repos/.../contents/
```

**Model**: sonnet

### Implementation Pattern

For coding tasks with a pre-approved plan.

```markdown
你是開發 agent。完成以下實作。

## Ticket
{ticket_key}: {summary}
Project: {repo_path}

## 已確認的計畫
{plan or analysis results}

## 流程
1. 建 branch（讀取 jira-branch-checkout SKILL.md）
2. TDD 開發（讀取 tdd SKILL.md + 專案 CLAUDE.md）
3. 品質檢查（dev-quality-check）→ 行為驗證（verify-completion）→ PR（git-pr-workflow）

## 限制
- 你無法使用 Skill tool，讀取 SKILL.md 並直接執行步驟
- 品質檢查未通過 → 先修正再發 PR
- 估點變動 > 30% → 停止，回傳問題描述
```

**Model**: sonnet | **Isolation**: `"worktree"` when parallel

### JIRA Batch Operations Pattern

For template-based JIRA writes (sub-task creation, field updates).

```markdown
你是 JIRA 操作 agent。依下方表格批次建立子單。

## 操作
{table of sub-tasks to create, with summary, description, SP, assignee}

## 限制
- 照表操課，不改變內容
- 不讀 codebase
- 回傳每筆操作的結果 + 連結
```

**Model**: haiku

### GitHub Status Scan Pattern

For batch PR status checking.

```markdown
你是 GitHub 狀態掃描 agent。

## 輸入
{ticket list}

## 查詢
對每張 ticket：gh pr list --search "{KEY}" --state all --json ...

## 回傳
| Ticket | PR # | State | CI | Approved | Mergeable |
|--------|------|-------|----|----------|-----------|

## 限制
- 只查詢，不修改
```

**Model**: sonnet

---

## Migration Notes

This file was rewritten in v1.40.0 from a role registry to a dispatch patterns reference. Changes:
- **Removed**: Named roles for generic patterns (Explorer, Implementer, Analyst, Validator, Scribe, Commander, Researcher)
- **Retained**: Three specialized protocols (QA Challenger/Resolver, Architect Challenger, Critic) that have multi-step interaction patterns worth standardizing
- **Added**: Common dispatch prompt patterns as copy-paste references
- **Rationale**: Audit found only 4/11 roles were correctly cited. Generic roles added a layer of indirection that skill authors naturally bypassed by writing inline prompts. Specialized protocols with multi-step interactions (challenge loops, structured JSON returns) remain valuable as canonical definitions
