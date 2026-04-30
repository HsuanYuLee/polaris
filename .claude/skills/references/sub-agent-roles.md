# Sub-agent Dispatch Patterns

How to dispatch sub-agents effectively. Three mandatory standards, three specialized protocols, and common prompt patterns for reference.

## 1. Mandatory Standards

### Completion Envelope

All sub-agents must return results with this header so the orchestrator can determine success without parsing prose:

```markdown
## Status: {DONE | BLOCKED | PARTIAL}
**Artifacts**: {files, URLs, ticket keys — or "none"}
**Detail**: {/path/to/detail-file.md | "inline" if short enough}
**Summary**: {≤ 3 sentences — decision-relevant conclusions only}
```

- `DONE` — task completed. Orchestrator proceeds.
- `BLOCKED` — cannot proceed. Must include `**Blocker**:` line.
- `PARTIAL` — some done, some not. Must include `**Remaining**:` line.

#### Summary vs Detail Separation

The **Summary** goes into the main session's context window. The **Detail** stays on disk. This is the primary mechanism for controlling context consumption.

| Content type | Where it goes | Example |
|-------------|---------------|---------|
| Conclusions, decisions, blockers | Summary (≤ 3 sentences) | "3 files need changes; composable X is the right extension point; no breaking changes" |
| Full analysis, file-by-file breakdown, diffs, evidence | Detail file on disk | Exploration report, review findings, test output |
| File paths, URLs, ticket keys | Artifacts line | PR #123, branch name, JIRA key |

**Detail file write rules:**
- Epic-scoped work → `specs/{EPIC}/artifacts/{agent-type}-{timestamp}.md`
- Design Plan-scoped work → `specs/design-plans/DP-NNN/artifacts/{agent-type}-{timestamp}.md`
- No scope → `/tmp/polaris-agent-{timestamp}.md`
- After writing, verify file exists: `test -f {path}` before reporting `Detail: {path}`
- If Detail is `"inline"` — the full content fits in ≤ 5 lines and is included in the Summary section itself

**Why:** sub-agent returns without length constraints can dump thousands of tokens into the main context. The Strategist reads the Summary for routing decisions; if deeper analysis is needed, it reads the Detail file on demand.

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

Choose a provider-neutral model class based on task type. The authoritative class definitions, Codex / Claude runtime mappings, approved small-model candidates, and risk gates live in [model-tier-policy.md](model-tier-policy.md).

| Task Type | Model Class | Examples |
|-----------|-------------|---------|
| **Read-only extraction / batch templates** | `small_fast` | Batch JIRA sub-task creation, ticket field updates, checklist comparison |
| **Low-latency interactive iteration** | `realtime_fast` | Explicit Codex Spark-style interactive coding loop when access and risk gates pass |
| **Explore / Analyze with decisions** | `standard_coding` | Codebase scan, PR review, ticket analysis, CI/debug analysis |
| **Execute / Fix** | `standard_coding` | Implementation, fix review comments, CI fixes |
| **Architecture / final arbitration** | `frontier_reasoning` | High-risk review, cross-system tradeoff, irreversible planning decision |
| **No override needed** | `inherit` | Parent session already selected the appropriate model |

Do not encode raw provider model names here. If a runtime needs a concrete value, resolve it through `model-tier-policy.md`.

### Context Isolation

- Each sub-agent receives a **complete, self-contained prompt** — it has no access to the parent conversation
- Include all necessary context: ticket key, repo path, analysis results, file paths
- Specify what tools the sub-agent should/shouldn't use
- For implementation tasks, specify `isolation: "worktree"` when parallel execution is needed

### Handbook Knowledge Injection

Sub-agents don't auto-load `.claude/rules/` from sub-repos or the workspace root. Two handbook layers need explicit injection, using **different strategies**:

| Layer | Strategy | Why |
|-------|----------|-----|
| **Company handbook** | Strategist 選擇性摘錄 | 跨 repo 知識，只有部分段落跟當前任務相關 |
| **Repo handbook** | Sub-agent 自己全讀 | 在該 repo 工作，整份 handbook 都適用 |

**Dispatch prompt pattern**:

```
你要在 kkday-b2c-web 修改 breadcrumb schema。

[Company Context]
- b2c-web 商品頁資料（breadcrumb, product detail, pricing）來自 member-ci internal API
- b2c-web SSR 透過 Nuxt server middleware 呼叫 member-ci
- 改動 member-ci API response 會影響 b2c-web 顯示

[Repo Handbook — 先讀再開始]
讀以下檔案，作為你對這個 repo 的基礎理解：
1. /absolute/path/to/kkday-b2c-web/.claude/rules/handbook/index.md
2. 讀完 index 後，讀 index 引用的所有子文件（handbook/*.md）
讀完後再開始任務。

你的任務是...
```

**Company context — when to inject**: cross-repo data flow, API integration, team conventions.
**Company context — when to skip**: purely isolated tasks (CSS fix, lint error).
**Repo handbook — when to inject**: always, if the repo has a handbook. Cost is a few Read calls; benefit is complete repo context equivalent to auto-loaded rules.

---

## 2. Specialized Protocols

These roles have **multi-step interaction patterns** that warrant a canonical definition. Skills should cite these by name when dispatching.

### QA Challenger + Resolver

A multi-round challenge loop for test plan quality assurance.

**When to use**: `engineering` Step 5f (AC Gate), before implementation begins.

**Protocol**:
1. **QA Challenger** (`standard_coding`) reviews the test plan and flags gaps:
   - Negative cases, boundary conditions, regression risks, environment differences, concurrency
   - Returns `⚠️ 需回應` or `✅ 涵蓋完整` per item
2. **QA Resolver** (`standard_coding`) addresses each ⚠️ with concrete solutions
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

**When to use**: `breakdown` estimation step, after estimation is complete but before writing to JIRA.

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

**When to use**: `engineering` first-cut **Phase 3 exit gate**（取代原 pre-PR Step 4，DP-032 D21）；發生在 `/simplify` 之後、Step 1.5 Scope Gate 之前。**Revision mode R5 不呼叫此 agent** — R5 只跑 Layer A+B+C 機械 evidence，Phase 3（含 Self-Review）不重跑。

**Review scope (handbook-first hard spec)**：

| 來源 | 用途 |
|------|------|
| `{repo}/.claude/rules/handbook/**/*.md` + `{repo}/CLAUDE.md` + `{repo}/.claude/rules/**/*.md` | **Primary compliance baseline**（judge against；repo long-term convention 是 SoT） |
| task.md `## 改動範圍` / `## 估點理由` | **Context only**（理解 PR 意圖，**不**作 compliance spec — 避免 task.md rubber stamp workaround） |
| task.md `Allowed Files` / `verification.*` / `depends_on` | **不讀**（D20 Scope Gate / D15 verify evidence / D14 artifact gate 已處理） |

Reviewer 以「這 PR 對 repo 是不是好的」為基準，不是「這 PR 是否符合 task.md 文字」。

**Iteration rules**:

- `passed: true` → Phase 3 exit，dispatcher 進 Step 1.5 Scope Gate
- `passed: false` → dispatcher 回 **Phase 3**（LLM 可自由改 test / 改實作 / 重跑 /simplify 任一）
- 回到 Phase 3 後**必然重走** TDD → /simplify → Self-Review（Phase 3 exit condition 強制）
- **Hard cap 3 輪**，超過 → halt → 使用者手動介入
- **NO bypass**（無「強制繼續」flag）

**Return format** (JSON):
```json
{
  "passed": true,
  "blocking": [
    {
      "file": "path/to/file.ts",
      "line": 42,
      "rule": "{repo}/.claude/rules/handbook/code-conventions.md § Composables",
      "message": "..."
    }
  ],
  "non_blocking": [
    {
      "file": "path/to/file.ts",
      "line": 80,
      "severity": "suggestion",
      "message": "..."
    }
  ],
  "summary": "..."
}
```

- `blocking[]` items prevent Phase 3 exit — must be fixed first；每項**必須**含 `rule` 欄位指向具體 handbook path / 具體 rule 段落（dispatcher 才能把 fix target 還給 Phase 3 的 LLM）
- `non_blocking[]` items are reported but don't block

**Evidence**: Critic does **not** write evidence file，**not** part of Layer A+B+C AND gate. Self-Review 是 LLM 語意 checkpoint，不是 CI-class gate.

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
使用 Completion Envelope 格式：
- Summary ≤ 3 句（結論 + 決策相關重點）
- Detail 寫入檔案：{detail_path}（完整分析、檔案清單、影響範圍）
- 寫完後 `test -f {detail_path}` 確認檔案存在

## 限制
- 只做讀取，不編輯
- 用本地 repo，不用 gh api repos/.../contents/
```

**Model class**: `standard_coding`

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
1. 建 branch（依 `references/branch-creation.md` 流程，或使用 `scripts/create-branch.sh`）
2. TDD 開發（讀取 `unit-test` SKILL.md + 專案 CLAUDE.md）
3. Local CI Mirror（engineer-delivery-flow § Step 2 — `ci-local.sh`）→ 行為驗證（engineer-delivery-flow Step 3）→ PR（git-pr-workflow）

## 限制
- 你無法使用 Skill tool，讀取 SKILL.md 並直接執行步驟
- 品質檢查未通過 → 先修正再發 PR
- 估點變動 > 30% → 停止，回傳問題描述
```

**Model class**: `standard_coding` | **Isolation**: `"worktree"` when parallel

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

**Model class**: `small_fast`

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

**Model class**: `standard_coding`

---

## Migration Notes

This file was rewritten in v1.40.0 from a role registry to a dispatch patterns reference. Changes:
- **Removed**: Named roles for generic patterns (Explorer, Implementer, Analyst, Validator, Scribe, Commander, Researcher)
- **Retained**: Three specialized protocols (QA Challenger/Resolver, Architect Challenger, Critic) that have multi-step interaction patterns worth standardizing
- **Added**: Common dispatch prompt patterns as copy-paste references
- **Rationale**: Audit found only 4/11 roles were correctly cited. Generic roles added a layer of indirection that skill authors naturally bypassed by writing inline prompts. Specialized protocols with multi-step interactions (challenge loops, structured JSON returns) remain valuable as canonical definitions
