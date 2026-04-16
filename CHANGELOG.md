# Changelog

All notable changes to Polaris are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/).

> Versions before 1.4.0 were retroactively tagged during the initial development sprint.

## [3.10.0] - 2026-04-16

### DP-005: Engineering Test Command + Handbook Injection

Closes two quality gaps discovered in GT-521/KB2CW-3788: (1) engineering sub-agents used generic `npx vitest run` instead of project-specific test commands, (2) sub-agent dispatch prompts omitted handbook injection, causing coding conventions to be ignored.

**Test Command pipeline (new)**
- `pipeline-handoff.md` — task.md schema gains `## Test Command` section (between 測試計畫 and Verify Command)
- `breakdown/SKILL.md` — Step 14.5 fills Test Command from `workspace-config.yaml` → `projects[].dev_environment.test_command`
- `workspace-config-reader.md` — documents new `test_command` config field
- `validate-task-md.sh` — enforces `## Test Command` as required section
- `engineering/SKILL.md` — sub-agent must use task.md's Test Command; environment failure = hard stop

**Handbook injection (fix)**
- `engineering/SKILL.md` — removed "handbook 自動載入" lie; added explicit handbook injection block for batch + first-cut modes
- `breakdown/SKILL.md` — corrected "handbook 自動載入" to accurate wording
- `design-plan/SKILL.md` — Phase 4b sub-agent prompt adds handbook reading instruction; Phase 5 adds sidebar regeneration step
- `converge/SKILL.md` — Phase 3 execution sub-agents gain handbook pre-read for code-modifying skills

**Mechanism canaries (new)**
- `mechanism-registry.md` — `handbook-injection-in-subagent` (High), `test-command-in-task-md` (High), `test-env-hard-gate` (Critical)

## [3.9.1] - 2026-04-16

### Specs Viewer: Home link

- `generate-specs-sidebar.sh` — add Home link at top of sidebar for navigation back to landing page

## [3.9.0] - 2026-04-16

### Polaris Specs Viewer

Docsify-based browser for design plans, Epic refinements, and task work orders. One command (`scripts/polaris-viewer.sh`) generates a navigation sidebar and opens a local web viewer.

- `scripts/generate-specs-sidebar.sh` — scans `specs/design-plans/` and `{company}/specs/` to build sidebar with status badges (💬/🔒/✅/❌), deduplicates title prefixes, skips empty epics
- `scripts/polaris-viewer.sh` — launcher: generate sidebar → start HTTP server → open browser
- `docs-viewer/` — docsify SPA with home page; `_sidebar.md` is generated (gitignored)
- `.gitignore` — whitelist `docs-viewer/`, exclude generated sidebar

## [3.8.1] - 2026-04-16

### Design plan checklist completeness gate

design-plan Phase 5 now runs `grep -c '- [ ]'` before allowing status → IMPLEMENTED. If any unchecked items remain, the transition is blocked until each is confirmed done or dropped. Fixes the "last item forgot to tick" pattern discovered in DP-003 (commit/sync completed but checklist not updated because attention had moved to session memory).

- `skills/design-plan/SKILL.md` — Phase 5 gains a deterministic grep gate as Step 1, before status change

## [3.8.0] - 2026-04-16

### Epic-centric specs folder (unified artifact structure)

All Epic artifacts now live under `specs/{EPIC}/` — mockoon fixtures, VR baselines, verification evidence, lighthouse reports, refinement artifacts, and task work orders. Previously, mockoon fixtures lived in `ai-config/{company}/mockoon-environments/{epic}/` separate from refinement data. This migration unifies everything so an Epic folder is self-contained: one folder to share, archive, or delete at Epic completion.

**Design decisions (DP-003):**
- D1: proxy-config.yaml stays at company level (`{company_base_dir}/mockoon-config/`) — cross-epic shared config
- D2: VR baselines become permanent per-epic (`specs/{EPIC}/tests/vr/baseline/`) — specs folder is gitignored, no size concern
- D3: verify-AC evidence gets local copy (`specs/{EPIC}/verification/{TICKET}/{timestamp}/`) before JIRA upload

**Changes:**
- `skills/references/epic-folder-structure.md` — **new** reference defining the complete folder schema, path resolution, artifact lifecycle, and bootstrap rules
- `skills/references/INDEX.md` — new § Epic Folder Structure section
- `skills/references/visual-regression-config.md` — directory structure split into tooling (domain-level) and data (per-epic); fixtures schema updated (`runner` + `shared_config_dir` replace `environments_dir` + `active_epic` + hardcoded `start_command`)
- `skills/references/api-contract-guard.md` — contract-check invocation updated to new path
- `skills/references/epic-verification-workflow.md` — fixture folder paths + cleanup flow updated
- `skills/visual-regression/SKILL.md` — fixture lifecycle section rewritten for `specs/{EPIC}/tests/mockoon/`; bootstrap, runner integration, and Phase 3 commit flow updated
- `skills/verify-AC/SKILL.md` — Step 5 split into 5a (local evidence copy) + 5b (JIRA upload)
- `skills/engineering/SKILL.md` — Phase 1.5 contract-check path updated
- `skills/breakdown/SKILL.md` — references-to-load table gains `epic-folder-structure.md`
- `kkday/workspace-config.yaml` — fixtures block: removed `environments_dir`, `active_epic`, hardcoded `start_command`; added `runner`, `shared_config_dir`
- `_template/workspace-config.yaml` — new `visual_regression` section with updated schema example
- `kkday/ai-config/kkday/visual-regression/record-fixtures.sh` — MOCKOON_DIR parameterized (env var or argument), no longer hardcoded
- `rules/mechanism-registry.md` — new canary `epic-folder-structure-compliance` (Medium)
- `polaris-backlog.md` — closed "Epic-centric specs folder" item

**Data migration (kkday):**
- `kkday/ai-config/kkday/mockoon-environments/GT-478/` → `kkday/specs/GT-478/tests/mockoon/`
- `kkday/ai-config/kkday/mockoon-environments/GT-483/` → `kkday/specs/GT-483/tests/mockoon/`
- `kkday/ai-config/kkday/mockoon-environments/proxy-config.yaml` → `kkday/mockoon-config/proxy-config.yaml`
- `kkday/ai-config/kkday/mockoon-environments/demo.json` → `kkday/mockoon-config/demo.json`

## [3.7.0] - 2026-04-16

### Infra-first decision framework (AC-verification-driven)

When breakdown decomposes an Epic, deciding whether to insert 1–2 "infra prerequisite" subtasks (Mockoon fixtures, VR baseline, stable data seed) before feature subtasks was previously done by Strategist improvisation — with two failure modes. (1) Over-engineering: simple Epics got infra prereq inserted because `visual_regression` config existed, even when AC were all `unit_test`. (2) Under-engineering: complex Epics shipped without fixtures and verify-AC hit backend API drift. Pattern had been applied intuitively across GT-483 / GT-478 / GT-521; this version lifts it into an explicit, shared reference.

The decision tree is fully AC-driven. Q1: does any AC use `lighthouse` / `playwright` / `curl`? Q2: any `modules[].api_change`? + exception list (i18n / docs / static-config / research / Epic-is-infra / existing-infra-covers). Output is a structured `decision_trace[]` auditable by the new mechanism-registry canary.

- `skills/references/infra-first-decision.md` — **new** shared reference (Why / Inputs / Classification / Decision tree / Exceptions / Output / Graceful degrade / Tier Guidance / Canary / Edge cases). Mirrors `planning-worktree-isolation.md` structure.
- `skills/references/refinement-artifact.md` (schema `version: 1.0 → 1.1`):
  - `modules[]` gains optional `api_change: "none" | "additive" | "breaking"` (defaults to `"none"` when absent; backward-compat safe)
  - New downstream rows: breakdown Step 5.5 + refinement Step 5 preview consumers
  - New § `modules[].api_change` documenting the signal
- `skills/references/INDEX.md` — new row for `infra-first-decision.md` under § Estimation & Planning
- `skills/references/pipeline-handoff.md` — breakdown → engineering Pre-conditions now reference infra-first-decision.md with graceful-degrade note
- `skills/breakdown/SKILL.md` (v2.5.0 → v2.6.0):
  - **New Step 5.5 Infra-first 決策** (Planning Path only) — reads refinement.json, outputs infra_subtasks + ordering_rule + decision_trace
  - Step 6 old "API-first 排序規則 + 穩定測資單 (Fixture Recording Task)" (bound to `visual_regression` config) replaced with "消費 Step 5.5 輸出" section; old logic becomes documented fallback path
- `skills/refinement/SKILL.md` (v4.1.1 → v4.2.0):
  - Step 5 § 子單結構 template now includes an infra-first summary line generated from the same decision tree (identical source, rendered during refinement preview)
  - Step 5b prose updated to explain preview/breakdown consistency contract
- `rules/mechanism-registry.md`:
  - New canary **`breakdown-infra-first-applied`** (Medium drift) — detects Planning Path breakdown missing infra-first decision trace, or ordering violating decision tree, or refinement preview missing the summary line
- `polaris-backlog.md`:
  - Closed: **breakdown：infra-first 決策框架（AC-verification-driven）**

## [3.6.0] - 2026-04-16

### Breakdown Step 14 — no main-checkout mutation during branch creation

Step 14 previously ran `git checkout develop` + `git pull` + `git checkout -b feat/...` directly on the user's main checkout. If the user had WIP, checkout would fail or corrupt staging. Discovered as a scoped-out note during v3.4.0 worktree isolation work.

The solution turned out to be simpler than the worktree approach proposed in the backlog: **don't switch checkout at all.** `git branch <name> <start>` (without `-b`) creates the ref without touching the working tree. Then `git push -u origin <name>` uploads it. Main checkout's HEAD / branch / working tree never change.

- `skills/breakdown/SKILL.md` (v2.4.0 → v2.5.0):
  - Step 14 absolute rule: forbid `git checkout` / `git pull` / `git stash` on main checkout
  - 14b: replaced `checkout develop + pull + checkout -b + push` with `fetch origin develop + git branch feat/... origin/develop + push`
  - 14c: same pattern for task branches (`git branch task/X feat/Y`)
  - Added "為什麼不用 `checkout -b`？" + canary signal (git status on main checkout must not change during Step 14)
  - Updated the Worktree Isolation section's footnote (previously said branch creation would touch main checkout)
- `rules/mechanism-registry.md`:
  - New canary **`breakdown-step14-no-checkout`** (High drift) — detects `git checkout` / `git pull` on main checkout path during breakdown Step 14, or changes to main checkout HEAD/branch/working tree after Step 14
- `polaris-backlog.md`:
  - Closed: **breakdown Step 14 main-checkout mutation**

## [3.5.0] - 2026-04-16

### Breakdown Step 3a — AC drift detection vs refinement artifact

When refinement v2+ reshapes AC structure (e.g., `AC#1/2/3-5` → `AC1-14`), any existing subtasks still referencing the old AC numbers silently go stale. Downstream consumers (engineering, verify-AC) then read the wrong AC IDs. GT-478 breakdown caught this only because the Strategist manually cross-referenced `refinement.json` with each subtask description. Automating this in Step 3 closes the gap.

- `skills/breakdown/SKILL.md` (v2.3.0 → v2.4.0):
  - Step 3: added detection item 4 — AC 引用對齊（當 `refinement.json` 存在且有既有子單時）
  - New § **3a AC 引用漂移偵測與調和** — trigger conditions, detection flow (regex extract + normalize + compare), 4-option reconcile decision (SUPERSEDE / UPDATE / RECREATE / KEEP), user-facing presentation format, sub-agent dispatch boundary (static comparison stays in main session, batch editJiraIssue uses haiku sub-agent)
  - `jira-subtask-creation.md § Retiring Obsolete Subtasks` (already exists) is the SUPERSEDE implementation reference
- `skills/references/refinement-artifact.md`:
  - New row in downstream table: `breakdown (Step 3a — AC drift)` consumes `acceptance_criteria[].id`
  - New § **AC ID 格式約定** documenting the stable anchor contract: `AC1/AC2/...`, `AC-NEG1/...`, `AC2.1/...`; subtask descriptions must use `ACn` or `AC#n` (normalized for drift comparison); warning that refinement v2+ AC restructuring must co-process existing subtasks
- `polaris-backlog.md`:
  - Closed: **breakdown Step 3 偵測既有子單 AC 編號漂移**

### Backlog hygiene — split conjoined items, add Step 14 mutation guard

- `polaris-backlog.md`:
  - Split one malformed `- [ ]` entry that had two `**Why:**` blocks into separate items: **infra-first decision framework** and **Epic-centric specs folder structure**
  - Added **Breakdown Step 14 main-checkout mutation** entry (scoped-out note from v3.4.0 worktree isolation session): Step 14 feature/task branch creation directly mutates main checkout (`git checkout develop` + `git pull`), which conflicts with user WIP. Three solution options documented (pre-check clean state / worktree-add-B pattern / move branch creation to engineering)

## [3.4.0] - 2026-04-16

### Planning skill worktree isolation — generalized to all four planning skills

Refinement v4.1.0 introduced Worktree Isolation for Tier 2+ runtime verification (avoiding main-checkout mutation during `pnpm install` / build / dev server operations). The same drift risk applies to `breakdown` (runtime sanity-check during estimation), `bug-triage` (AC-FAIL Path investigates a feature branch; bug reproduction requires a running env), and `sasd-review` (technical feasibility probes). Generalizing this prevents planning skills from silently corrupting user WIP.

- `skills/references/planning-worktree-isolation.md` (**new**):
  - Shared reference consolidating the worktree isolation protocol — why, absolute rules, execution flow, canary signal, sub-agent dispatch, exceptions
  - Tier Guidance table per skill: when the worktree requirement activates
- `skills/refinement/SKILL.md` (v4.1.0 → v4.1.1):
  - Replaced ~70 lines of inline Worktree Isolation content with a 10-line skill-specific header + link to the shared reference
- `skills/breakdown/SKILL.md` (v2.2.0 → v2.3.0):
  - New § **Worktree Isolation (條件性)** — triggers for estimation sanity-check, infra-first decision verification, Scope Challenge runtime checks
  - Note clarifying Step 14 feature-branch creation is a separate concern (skill's intended output, not runtime verification)
- `skills/bug-triage/SKILL.md` (v2.1.0 → v2.2.0):
  - New § **Worktree Isolation (條件性)** — mandatory for AC-FAIL Path (feature-branch investigation), manual bug reproduction, cross-branch behavior comparison
  - AC-FAIL Path sub-agents must use `isolation: "worktree"` to prevent feature-branch state from leaking into main checkout
- `skills/sasd-review/SKILL.md` (v1.0.0 → v1.1.0):
  - New § **Pre-step (conditional): Worktree Isolation** — triggers for feasibility verification (runtime API/module behavior), dev scope quantification via build, A/B alternative comparison
- `skills/references/INDEX.md`:
  - New entry under **Estimation & Planning** pointing to `planning-worktree-isolation.md`
- `rules/mechanism-registry.md`:
  - New canary **`planning-skill-worktree-isolation`** (High drift) under § Delegation — detects `pnpm install` / build / dev server in main checkout path before any `worktree add`
- `polaris-backlog.md`:
  - Closed: **Generalize worktree isolation to breakdown / sasd-review / bug-triage**

## [3.3.0] - 2026-04-16

### Breakdown pipeline — split subtasks + SUPERSEDED pattern

Addresses two gaps surfaced by GT-478 breakdown (11 implementation subtasks, 1 of which was split; 3 obsolete verification subtasks needing retirement).

- `scripts/validate-task-md.sh`:
  - Header regex relaxed `^# T[0-9]+:` → `^# T[0-9]+[a-z]*:` to allow split subtask headers (T8a, T8b)
  - Rationale: preserving parent T-number + alpha suffix avoids renumbering siblings and breaking downstream task.md references
- `skills/references/pipeline-handoff.md`:
  - § task.md Schema: added **Header numbering** note documenting sequential + suffix convention and validator regex
- `skills/references/jira-subtask-creation.md`:
  - New § **Retiring Obsolete Subtasks** — `[SUPERSEDED]` summary prefix + SP=0 + comment pattern for workflows without direct Open → Cancel transition
  - Applies to any company workflow lacking Cancelled/Rejected transition from initial state
- `polaris-backlog.md`:
  - Added **Breakdown: AC drift detection vs refinement artifact** (High) — Step 3 should flag mismatched AC numbering between existing subtasks and refinement.json

## [3.2.0] - 2026-04-16

### Library change protocol — reviewer-suggested upgrade pause

Addresses drift in `engineering` revision mode where sub-agents default to closing PRs by silently deferring reviewer-suggested library upgrades ("defer to next sprint", "current version doesn't support this"). Reviewer upgrade suggestions are often load-bearing signals — silently dismissing them loses legitimate improvement paths and burns reviewer trust.

- `rules/library-change-protocol.md`:
  - New § **Reviewer-Suggested Upgrades in Revision Mode** — pause and escalate to user before deciding
  - Forbidden defaults: unilateral deferral, "T3 so deferred" auto-response, "reply-only no code change"
  - Correct flow: sub-agent stops → main agent asks user → user decides Y (upgrade protocol) or N (reply with reason)
  - Scope: any library/framework/module upgrade suggestion in PR review, not just Nuxt modules
  - New Common Rationalization row added
- `rules/mechanism-registry.md`:
  - New canary **`lib-reviewer-upgrade-pause`** (High drift) — detects "deferred to next sprint" replies without user consultation

## [3.1.0] - 2026-04-16

### Refinement skill — Worktree Isolation

- `refinement` skill bumped `4.0.0 → 4.1.0`:
  - Added **§ Worktree Isolation** section with absolute-rule framing and canary signal
  - Tier 2+ refinement must create `refinement/{EPIC_KEY}` worktree from `origin/{base_branch}` before any codebase/runtime work
  - **No mutation of user's main checkout**: forbids `git checkout`, `git stash`, `git pull` in main workspace
  - Canary signal: before any git command, self-check "will this change the main checkout's HEAD/branch/working tree?"
  - Prerequisites section updated to call out worktree requirement

### Backlog — Planning pipeline evolution

Three High-priority framework items added to `polaris-backlog.md`:

- **Generalize worktree isolation** to `breakdown` / `sasd-review` / `bug-triage` (same pattern, Tier 2+ runtime work)
- **`specs/{EPIC}/` as Epic single source of truth** — consolidate refinement artifacts, task.md, Lighthouse reports, Mockoon fixtures, verification evidence into one folder. Affects mockoon workspace-config path, breakdown task.md location, verify-AC evidence placement
- **`breakdown` infra-first decision framework** — AC-verification-driven decision tree: if hardest AC requires runtime state (Mockoon fixtures / VR baseline / specific data) → infra subtask first; else feature-first. API changes: breaking → API-first-then-fixtures; additive → parallel

### Framework experience

- Real-session drift discovered and corrected: first draft of Worktree Isolation only said "build worktree" without forbidding main-checkout mutation — Strategist still executed stash→checkout→pull sequence before running build. v4.1.0 second pass adds absolute rules + canary signal to prevent misinterpretation

## [3.0.4] - 2026-04-15

### Docs alignment after Codex parity rollout

- Updated skill count references from **25 → 26** in:
  - `README.md`
  - `README.zh-TW.md`
  - `docs/quick-start-zh.md`
- Added `codex-mcp-setup` to `docs/chinese-triggers.md` so trigger catalog matches the actual skill inventory.
- Re-ran docs lint and confirmed no drift:
  - `Docs lint: OK (26 skills, all documented)`

## [3.0.3] - 2026-04-15

### Codex bootstrap + cross-LLM parity hardening

- Added `scripts/sync-codex-mcp.sh`:
  - Syncs baseline Codex MCP servers (`claude_ai_Atlassian`, `claude_ai_Slack`)
  - Supports `--dry-run` / `--apply` and optional `--login`
  - Skips OAuth login automatically for `stdio` transport servers
- Added `codex-mcp-setup` skill (Claude + Codex mirrored layouts):
  - Standardized Codex setup flow (MCP sync + skills link + parity + doctor)
- Added `scripts/transpile-rules-to-codex.sh`:
  - Source of truth: `.claude/rules/**/*.md`
  - Generates `.codex/AGENTS.md` + `.codex/.generated/rules-manifest.txt`
  - Supports `--check` drift validation for CI
- Added `scripts/verify-cross-llm-parity.sh`:
  - Runs `mechanism-parity.sh --strict` + `transpile-rules-to-codex.sh --check`
  - Provides a single CI-friendly cross-LLM parity gate

### Init / upgrade workflow integration

- `init` skill now includes **Step 13.6 Codex Bootstrap** (skippable):
  - Runs skills sync, Codex MCP sync, rules transpile, cross-LLM parity verification, and Codex doctor
  - Keeps init non-blocking on Codex bootstrap failures (warn + continue)
- `init` Step 14 "Done" summary now reports Codex bootstrap status:
  - `✓ enabled` / `— skipped` / `⚠ partial`
- `scripts/sync-from-polaris.sh` upgrade flow now runs post-upgrade:
  - `scripts/transpile-rules-to-codex.sh`
  - `scripts/verify-cross-llm-parity.sh`

### Docs

- Updated Codex quick-start (EN + zh-TW):
  - Documented MCP baseline sync, rules transpile, and cross-LLM parity check
  - Declared `.claude/**` as SSOT and `.agents/**`, `.codex/**` as generated outputs
- Updated README upgrade section (EN + zh-TW) to reflect post-upgrade Codex parity checks

## [3.0.2] - 2026-04-15

### Codex compatibility — skills path sync bridge

- Added `scripts/sync-skills-cross-runtime.sh` to sync skills between:
  - `.claude/skills` (Claude layout)
  - `.agents/skills` (Codex layout)
- Supports:
  - `--to-agents` / `--to-claude` / `--both`
  - `--link` mode (`.agents/skills -> .claude/skills` symlink)
- Added `.agents/skills` whitelist in `.gitignore` so repo-scoped Codex skills can be version-controlled.
- Updated Codex quick-start docs with explicit skill sync step:
  - `docs/codex-quick-start.md`
  - `docs/codex-quick-start.zh-TW.md`

### Maintainer-only skill boundary hardening

- `scripts/sync-to-skills.sh` now skips skills marked with `scope: maintainer-only` in SKILL frontmatter.
- This aligns vendoring behavior with `sync-to-polaris.sh` and prevents framework-internal maintenance skills from being exported to external/team skills repos.

## [3.0.1] - 2026-04-15

### `design-plan` skill — 新增 Sub-agent Handoff 模式（v1.1.0）

Phase 4 實作階段新增雙模式選擇：

- **4a. Main-agent 模式**：小 scope（Checklist ≤ 3 項、單檔案）走 Strategist 直接執行
- **4b. Sub-agent Handoff 模式**：大 scope 走「dispatch sub-agents 消費 plan.md 作為 work order」的 pattern，類比 `breakdown → task.md → engineering`

**Sub-agent Handoff 要點**：
- Dispatch prompt 只傳 plan file **路徑**（sub-agent 自己讀），不 copy plan 內容
- Phases 依賴關係決定平行 vs 順序；多 sub-agent 寫同檔時用 worktree isolation
- Main agent 只做 orchestration + fan-in validate + 統一 tick off Checklist
- Sub-agent 偏離 plan 必須 STOP + 回報，不擅自決策

**Dogfood 驗證**：DP-002 重構（engineering revision mode + pr-pickup + fix-pr-review 移除）透過此模式執行——5 個 phases 全部 DONE、零 user 修正。

## [3.0.0] - 2026-04-15

### ⚠ Breaking — `fix-pr-review` skill 移除

`fix-pr-review` 整個 skill 已刪除。「修 PR」這件事回歸施工標準：**回讀施工圖（task.md / plan.md）→ 比對 review signals → 重跑完整驗收**，不再是 symptom-driven 的逐 comment patch。

### engineering 擴充為 first-cut + revision 雙模式（v4.0.0 → v5.0.0）

`engineering` 新增 **revision mode**（D1 六步流程），成為所有 PR code 修正的唯一入口：

1. 讀施工圖
2. 比對 review signals vs 原計劃
3. Classify：`code drift` / `plan gap` / `spec issue`
4. 執行修正（依 classification）
5. 重跑 engineer-delivery-flow（quality + behavioral verify + AC check）
6. 回覆 reviewer + lesson 萃取

**嚴格性規則**：
- **Plan gap / spec issue → 硬擋退回上游**（breakdown / refinement），不就地補 plan（避免便宜行事繞過品質關卡）
- **Legacy PR 無施工圖 → 硬擋**（要求先跑 `/breakdown {TICKET}` 補 plan，或用 `--bypass` 旗標並警告）
- **Review comments 不分級**：所有 comment（typo 或邏輯漏洞）一律走完整 revision flow，不做 triage

Mode detection 發生在 engineering Step 0：PR 已開 → revision；否則 → first-cut（原有流程保留不變）。

### 新 skill：`pr-pickup` — Slack 協作層

填補 fix-pr-review 原本的 Slack 協作價值，但**只做溝通傳遞，不做 code 修正**：

- **Intake**：從 Slack 訊息擷取 PR URL + thread context
- **Dispatch**：同步 Skill tool 呼叫 engineering revision mode
- **Broadcast**：完工後回 Slack thread（✅ 完成 / ⛔ 退回 / ⚠️ 失敗）

觸發：`pr-pickup`、`pickup`、Slack URL + PR intent。

### Learning Pipeline — `plan-gap` + `review-lesson` 標籤

新增兩類 lesson 標籤，對應不同 handbook 目標：

- `plan-gap`（engineering R3a plan gap 退回時寫入）→ 畢業成 refinement / breakdown 的 checklist 條目
- `review-lesson`（engineering R6 code drift 修完時寫入）→ 畢業成 repo handbook

**閾值**：N=3（同 feedback memory graduation）。自動掃描整合進 standup（post-step）和 sprint-planning（pre-step）。

**CLI 擴充**：`polaris-learnings.sh` 新增 `--tag` / `--metadata` 旗標 + `graduate <tag>` subcommand。

### Design Plan Skill 檔案位置遷移（DP-001 superseded）

原本 `.claude/design-plans/{topic}.md`（committed）改為 `specs/design-plans/DP-NNN-{slug}/plan.md`（gitignored）：

- Plan 檔是個人工作空間的思考紀錄，畢業成 rule/reference 才進 framework git
- 比照 `{company}/specs/{TICKET}/` 架構，framework 層有對應的 spec folder
- 非 ticket 用 `DP-NNN` 三位數流水號 + kebab-case slug
- 每個 plan 是 folder（容納 draft / diagram 子檔）

### 規則 + 文件更新

- `rules/skill-routing.md`：移除 fix-pr-review，新增 engineering revision mode 路由 + pr-pickup 路由
- `rules/mechanism-registry.md`：Common Rationalizations 更新指向 engineering revision mode
- `rules/*/mechanism-registry.md` canaries：保留 deterministic 機制規則，移除 skill-specific 殘跡
- `references/engineer-delivery-flow.md` Step 7：加 revision mode 行為（push to existing PR）
- `references/cross-session-learnings.md`：新增 Pipeline Learning Tags + Graduation Pipeline section
- `references/shared-defaults.md`：pr-pickup 列入 config consumers
- `standup` / `sprint-planning` SKILL：加 learning queue 掃描步驟
- 25+ 其他 references / skills 的 fix-pr-review 引用清除（bug-triage / review-pr / converge / next / learning / INDEX 等）
- 雙語 docs 同步：README / workflow-guide / chinese-triggers（EN + zh-TW），mermaid diagram 更新
- `.claude/settings.local.json` 移除 fix-pr-review 相關 permission

### Dogfood

DP-002 全程走 design-plan 流程產出（LOCKED → 5 個 phase 平行 / 順序 dispatch sub-agents 消費 plan.md 作為 work order）。

## [2.17.0] - 2026-04-15

### Design Plan skill — non-ticket architecture discussions

新增 `design-plan` skill，填補 breakdown/refinement/sasd-review 之間的 gap：**非 ticket 設計討論的持久化落地機制**。

- **新 skill**：`.claude/skills/design-plan/SKILL.md`
- **檔案位置**：`.claude/design-plans/{topic}.md`（committed to git，類似 ADR）
- **Status 流轉**：DISCUSSION → LOCKED → IMPLEMENTED / ABANDONED
- **觸發**：使用者說「想討論」「怎麼設計」「重構」「重新設計」「要怎麼改」等，或多輪架構討論自動回溯建檔
- **決策即寫檔**：每個確認的決策，下一個 tool call 必須更新 plan file
- **實作時讀 plan**：implementation 階段必須讀 plan file，不依賴對話記憶
- **Checklist-based done**：Implementation Checklist 全打勾才能宣告完成

**Dogfood**：本 skill 的實作本身經過 design-plan 流程產出，plan file 一起 commit 作為決策紀錄（`.claude/design-plans/design-plan-skill.md`）。

### 規則更新

- `rules/skill-routing.md`：新增 design-plan routing 條目
- `rules/context-monitoring.md § 5b Defer = Immediate Capture`：加「design decision → plan file」case + check-pr-approvals v2.10→v2.16 掉棒事件說明
- `rules/feedback-and-memory.md § Memory Hygiene Checks`：新增第 9 項 stale design-plan 掃描（DISCUSSION > 30 天 / LOCKED > 14 天未實作）
- `rules/mechanism-registry.md § Strategist Behavior`：新增 4 個 canaries（`design-plan-creation` / `design-plan-decision-capture` / `design-plan-reference-at-impl` Critical；`design-plan-checklist-done` High）+ Common Rationalizations + Priority Audit Order 1a

### 為什麼這個 skill 存在

check-pr-approvals v2.10.0 重設計時，早期決策「check-pr-approvals 發現問題 PR 轉 JIRA 狀態」在後續討論中被「engineering 零改動」覆蓋，實作時掉棒，v2.16.0 才補回。這次事件暴露了「非 ticket 設計討論」缺乏 landing point，設計決策只存在對話記憶中，容易被後續 phrasing 覆蓋。design-plan 把決策從記憶轉成檔案，讓實作有確定性的 spec 可讀。

## [2.16.0] - 2026-04-15

### check-pr-approvals: JIRA status revert for 🔧 PRs

補上 v2.10.0 遺漏的 JIRA 狀態回轉邏輯。

- **Step 5 新增**：對 🔧 分類 PR，若 JIRA 狀態為 `CODE REVIEW`，轉回 `IN DEVELOPMENT` 並留 comment 記錄原因
- **理由**：engineering 的路由表中 `CODE REVIEW` 狀態會導向「修 review comments 嗎？」引導至 fix-pr-review。為了讓「做 KB2CW-XXXX」直接命中 engineering 的「IN DEV + 有 branch」路徑，check-pr-approvals 必須主動回轉狀態
- **Step 9 回報**：列出哪些 ticket 已回轉狀態
- **Do**：新增規則「🔧 PR 若 JIRA 狀態為 CODE REVIEW，必須轉回 IN DEVELOPMENT」

## [2.15.0] - 2026-04-15

### 清除 v2.12.0 文件殘留 + maintainer-only 感知 lint

v2.13 的 docs-sync 只修了 phantom 引用和 skill count，但遺漏了其他殘留：

- **Skill Orchestration 圖修復**：移除 `DS` (docs-sync) 節點、移除 self-loop edges（`RP/FPR/CPA → self`）、移除 `DS` class 分類。連通性說明改為「lesson extraction 直接寫 handbook，不需中繼節點」
- **chinese-triggers.md**：移除 docs-sync 行；`learning` 描述的 review-lessons 改為 handbook
- **workflow-guide Learning Modes 表**：「write to review-lessons」改為「write to repo handbook」
- **readme-lint.py**：動態讀取 SKILL.md 的 `scope: maintainer-only`，自動從 doc-mention 檢查排除。與 sync-to-polaris.sh 同一機制
- **Skill count**：25 → 24（扣除 maintainer-only 的 docs-sync）

## [2.14.0] - 2026-04-15

### sync-to-polaris: maintainer-only skill exclusion

- **`scope: maintainer-only`**：SKILL.md frontmatter 新增此欄位的 skill 不會 sync 到 template repo
- **`docs-sync` 從 template 移除**：framework 文件維護是個人行為，不應暴露給所有使用者
- **通用機制**：任何 skill 加 `scope: maintainer-only` 即自動排除，不需改 sync 腳本

## [2.13.0] - 2026-04-15

### docs-sync fix + version-docs-lint-gate hook

v2.12.0 刪除 `review-lessons-graduation` 後漏跑 post-version-bump chain，導致 14 處文件殘留引用。

- **文件修復**：skill count 26→25（9 處）、phantom skill 引用（6 處）、mermaid 圖節點+邊
- **確定性拘束**：新增 `version-docs-lint-gate.sh` — VERSION staged 時自動跑 `readme-lint.py`，lint fail 則 block commit
- **Local-only 設計**：hook 註冊在 `settings.local.json`（gitignored），腳本在 repo 但不自動生效，避免暴露個人行為到 template
- **Handbook 條目**：`working-habits.md` § 框架維護，記錄 bump 後必跑 docs-sync 的個人習慣
- **Mechanism registry**：新增 `version-docs-lint-gate` + 更新 `docs-sync-on-version-bump` 加註確定性備援

## [2.11.0] - 2026-04-15

### standup local markdown backup

Standup 確認後自動存本地 markdown 檔案，作為 Confluence 推送前的備份。

- **路徑結構**：`{base_dir}/standups/{YYYY}/{MM}/{YYYYMMDD}.md`（年/月兩層，檔名帶完整日期）
- **執行順序**：Step 10a 存本地 → Step 10b 推 Confluence（local first, 離線也有紀錄）
- **自動建目錄**：`mkdir -p` 建立不存在的年/月目錄
- **覆寫設計**：同日重跑直接覆寫

## [2.10.0] - 2026-04-15

### check-pr-approvals v2.0.0 — detect + report only

check-pr-approvals 從「偵測 + 自動修正 + 催 review」瘦身為「偵測 + 報告 + 催 review」。

- **移除所有自動修正邏輯**：CI 修正、rebase conflict 解衝突、review comment 修正（原委派 fix-pr-review）全部移除
- **三分類報告**：🟢 可催 review / 🔧 需先修正（附 ticket key）/ ✅ 已達標
- **修正走 engineering**：問題 PR 由使用者主動「做 KB2CW-XXXX」觸發 engineering 完整流程（TDD + behavioral verify），確保功能不被改壞
- **冪等設計**：每次執行重新掃描當前狀態，不等修正完成、不輪詢遠端 CI
- **移除 review lessons 萃取**：lesson 萃取應在 engineering 修正時自然產生，不在掃描時回溯
- **Backlog**：review-lessons buffer 廢除排入 Medium backlog

淨減 124 行（78 insertions, 202 deletions）。四個 bundled scripts 不動，engineering 不動。

## [2.9.0] - 2026-04-14

### docs-sync restructure — deterministic lint + git-diff scoping

文件同步從「全量掃描 + 手動修」重構為「確定性偵測 + 差異驅動修復」。

- **`readme-lint.py` 擴充為 docs-lint** — 新增 5 項確定性檢查：
  - Phantom skill 偵測（doc 引用不存在的 SKILL.md）
  - chinese-triggers 表格 ↔ catalog 比對
  - Mermaid diagram node ↔ catalog 比對
  - `KNOWN_NON_SKILLS` 白名單降低 false positive
  - 原有 skill count + undocumented skill 檢查保留
- **`docs-sync` SKILL.md v3.0.0** — 新增 Step 0（git diff + completeness scoring）：
  - Step 0a: 跑 `readme-lint.py` 確定性檢查
  - Step 0b: `git diff` 找出上次同步後變更的 SKILL.md
  - Step 0c: 借 `/learning` baseline→classify 模式分類變更深度
  - Step 0d: 借 `/refinement` N/M 維度對每個 skill 打 4 維覆蓋分數
  - 無變更 + lint 通過 → 直接跳到驗證，不跑全量掃描
- **Post-version-bump chain 調整** — docs-lint 先跑（確定性），有問題才觸發 docs-sync（AI）
- **文件全面更新** — 修正 7 個 doc 檔案：
  - `work-on` → `engineering`（全部文件）
  - 移除 phantom skills（`jira-worklog` 公司層、`skill-creator` Claude 官方）
  - 新增 `check-pr-approvals`、`my-triage`、`next`、`sasd-review` 到各 doc

## [2.8.0] - 2026-04-14

### Pipeline Persona — Architect / Packer / Engineer

三層 pipeline 的角色收斂，每個 skill 有明確的身份宣言和「不做」邊界。

- **refinement** — Architect persona：把模糊需求變成可執行藍圖，不拆單、不估點
- **breakdown** — Packer persona：接過藍圖拆工單、估價、排班，不做技術探索
  - Step 4 新增 `refinement.json` early-exit：有 artifact 時跳過 Explore sub-agent，直接消費
- **engineering** — Engineer persona（v2.6.0 已有）
- `pipeline-handoff.md` Role Boundaries 表加 persona 標籤

## [2.7.0] - 2026-04-14

### Context Pressure Monitor — deterministic session degradation prevention

長 session 中 Strategist 靠自律計算 tool calls 不可靠（v1.71.0 事件），改用 PostToolUse hook 確定性注入警告。

- **`scripts/context-pressure-monitor.sh`** — 計數 Bash/Edit/Write/Read/Grep/Glob/Agent calls，三級警告：
  - 20 calls → advisory（wrap up current phase）
  - 25 calls → urgent（save state, delegate）
  - 35 calls → critical（checkpoint mode NOW）
- 註冊進 `~/.claude/settings.json` PostToolUse hooks
- `mechanism-registry.md` 新增 `context-pressure-monitor` entry
- `context-monitoring.md` §5 從 "Future enhancement" 升級為 "Deterministic mechanism"

**設計原則**：與 `test-sequence-tracker.sh` 同模式 — stdout injection（advisory），不 block。

## [2.6.0] - 2026-04-14

### Engineering Mindset — Deterministic Quality Gates & Skill Rename

`work-on` 更名為 `engineering`，搭配三層確定性強化，確保 AI 工程師不再跳過品質檢查。

#### 確定性品質 Gate（P0）
- **`scripts/pre-commit-quality.sh`** — 自動偵測 lint/typecheck/test 並執行，全過寫 quality evidence
- **`scripts/quality-gate.sh`** — PreToolUse hook，`git commit` 前檢查 evidence，沒有就 exit 2 擋下
- Coverage advisory — 列出缺少 test 的 source files（non-blocking）
- 整合進 `quality-check-flow.md` Step 4b + `mechanism-registry.md`

#### Scope Lock（P1）
- `pipeline-handoff.md` task.md schema 新增 `## Allowed Files` section
- `engineer-delivery-flow.md` 新增 Step 5.5 Scope Check（advisory + risk signal）
- `sub-agent-delegation.md` self-regulation scoring：計畫外檔案 +10% → +15%

#### Skill Rename: work-on → engineering
- 目錄 `skills/work-on/` → `skills/engineering/`
- SKILL.md 開頭加工程師 persona 宣言
- 全框架 ~30 個檔案 cross-reference 更新
- Routing table 保留 `做`/`work on` trigger，skill name 改為 `engineering`

**設計原則**：能用確定性驗證的，不靠 AI 自律。Hook exit code > 行為規則。

## [2.5.0] - 2026-04-14

### Library Change Protocol — Investigation & Workaround Standards

從 GT-521 KB2CW-3789（nuxt-schema-org tagPosition）的 debug session 萃取兩條準則，加入 `library-change-protocol.md`：

- **Config Not Working — Systematic Elimination**：config 不生效時，先列出所有注入點再依序排除；驗證結果矛盾以失敗為準
- **Workaround Documentation Standard**：繞過官方 API 時，code comment 必須包含完整決策鏈（目標 → 試了什麼 → 為什麼選此方案 → 移除條件）

**觸發背景**：T2 修復過程在 5 個注入點之間來回測試，浪費 4 次 dev server 重啟。

## [2.4.0] - 2026-04-14

### review-inbox Thread Mode

review-inbox 新增第三種 PR 發現模式：給一個 Slack 討論串 URL，從該 thread 提取 PR URL 並走標準 review pipeline。填補 channel 全掃（太廣）和單一 PR review（太窄）之間的缺口。

- **extract-pr-urls.py** — 新增 `--thread-ts` flag，Thread 模式跳過 per-message 解析，直接撈全文 PR URL
- **SKILL.md** — Step 0 Thread 偵測、Step 1 Thread pipeline（主 session 直接跑，不需 sub-agent）、Step 5 Thread reply
- **skill-routing.md** — routing table 新增 Slack thread URL + review intent 觸發

**使用方式**：`review <slack_thread_url>`

## [2.3.0] - 2026-04-14

### Verify Command — Developer Self-Test Gate

breakdown（Tech Lead）為每張 task.md 寫一個可執行的 smoke test 指令，work-on（Engineer）實作完後必須原封不動執行。FAIL 直接擋 PR，消除「sub-agent 聲稱 pass 但沒真跑」的結構性弱點。

- **pipeline-handoff.md** — task.md schema 新增 `## Verify Command` section
- **breakdown SKILL.md** — Step 14.5 新增 Verify Command 撰寫指南（範例、原則、N/A 情境）
- **engineer-delivery-flow.md** — Step 3d 改為 Verify Command hard gate；舊 `## 行為驗證` 降級為 legacy fallback
- **mechanism-registry.md** — 新增 `verify-command-immutable-execute` (Critical)

**角色分工**：
| 角色 | Skill | 驗證職責 |
|------|-------|---------|
| Tech Lead | breakdown | 寫 verify command（what to check） |
| Engineer | work-on | 執行 verify command（self-test） |
| QA | verify-AC | 跑完整 AC 驗收（business-level） |

**觸發背景**：GT-521 PR #2126 JSON-LD head position 實作未生效，sub-agent 未跑 runtime 驗證即開 PR。

## [2.2.0] - 2026-04-14

### Review Skill Architecture — Discovery / Engine Split

review-inbox 升級為三層 sub-agent 架構（Slack scan → per-PR review → 彙整），review-pr 砍掉批次模式純化為 single-PR review engine。

- **review-inbox v2.1.0** — Slack 模式 Step 1 委派 sub-agent（MCP + extract-pr-urls.py pipeline），原始訊息不進主 session context；Step 4 每個 PR 由獨立平行 sub-agent 執行 review-pr 流程
- **review-pr v2.0.0** — 移除 Step 0 批次模式（multi-PR dispatch、batch Slack notification），批次調度由 review-inbox 負責
- **extract-pr-urls.py** — 支援新 MCP 輸出格式（`=== Message from ...` headers + `Message TS`），保留 legacy fallback；thread_ts 從秒級近似提升為微秒精度

**職責分工**：
| 職責 | 負責者 |
|------|--------|
| PR 發現（Slack / Label 掃描） | review-inbox |
| 批次調度（平行 sub-agent） | review-inbox Step 4 |
| 單 PR review（diff → 審查 → 提交） | review-pr |
| 批次 Slack 通知 | review-inbox Step 5 |
| 單 PR Slack 通知 | review-pr Step 7 |

## [2.1.0] - 2026-04-14

### Phase 4 — Delivery Flow Polish

v2.0.0 follow-up：補齊 contract、VR 整合、pr-convention 降級、delivery canaries。

- **Delivery Contract** — `engineer-delivery-flow.md` 頂部加 Preconditions / Postconditions / 不做的事
- **VR Step 3.5** — Behavioral Verify 後、Pre-PR Review 前條件觸發 `visual-regression`（Local mode），結果寫入 evidence file
- **Deleted skill: `pr-convention`** — PR template 偵測、body 組裝、AC Coverage、母單 PR、Bug RCA 偵測邏輯移到新 reference `pr-body-builder.md`，消除獨立 skill 的路由歧義
- **New reference: `pr-body-builder.md`** — engineer-delivery-flow Step 7 消費
- **Delivery Contract canaries** — mechanism-registry 新增 5 條 delivery-flow 專屬 canary（step-order、single-backbone、vr-trigger、pr-body、evidence-completeness）
- **Sweep** — 更新 INDEX.md、git-pr-workflow、bug-rca、mechanism-registry 中所有 pr-convention 引用

## [2.0.0] - 2026-04-14

### BREAKING — Engineer Delivery Flow Redesign

execution backbone 從分散的 skill 統一到共用 reference，work-on 和 git-pr-workflow 共用同一份交付流程。

- **New references**
  - `engineer-delivery-flow.md` — 共用交付 backbone：Simplify → Quality Check → Behavioral Verify (Layer A+B) → Pre-PR Review → Rebase → Commit → PR → JIRA transition
  - `quality-check-flow.md` — lint / test / coverage / risk scoring 自檢流程（原 dev-quality-check 內容）
- **Restructured skills**
  - `work-on` v4.0.0 — Developer 主入口，TDD 開發後委託 engineer-delivery-flow (Role: Developer)。刪除 Phase 2.5 Sanity Gate（吸收進 delivery-flow Step 3）
  - `git-pr-workflow` v4.0.0 — 瘦身為 Admin 入口（~440→~90 行），加 `tier: meta` + `admin_only: true`，委託 engineer-delivery-flow (Role: Admin)
- **Deleted skills**
  - `verify-completion/` — 行為驗證段 → engineer-delivery-flow Step 3；AC 驗證段 → verify-AC（已獨立）
  - `dev-quality-check/` — 內容 → quality-check-flow.md；`detect-project-and-changes.sh` → 搬到 `scripts/`
- **Skill routing**
  - 新增 § Admin-Only Skill Guard：git-pr-workflow 在產品 repo 引導走 work-on
- **Reference sweep** — 16 files 更新 verify-completion / dev-quality-check 引用
- **Evidence gate 合併** — 刪除 `/tmp/.quality-gate-passed-{BRANCH}` + pre-push hook marker，保留 `/tmp/polaris-verified-{TICKET}.json` + pre-PR hook 為唯一 gate

## [1.110.0] - 2026-04-14

- **Handbook as Coding Standard — review skills now read and enforce repo handbook**
  - `review-pr` Step 3: reads `handbook/index.md` + sub-files as primary review standard (full compliance, not checklist)
  - `review-pr` Step 6.5: review findings write directly to handbook (Standard-First), replacing review-lessons buffer
  - `fix-pr-review` Step 5: upfront handbook read for global context before per-comment fixes
  - `fix-pr-review` Step 7b: upgraded to Standard-First Calibration (conflict → pause → ask user → update handbook or reply reviewer)
  - `repo-handbook.md` § 3c: reframed from "review context" to "coding standard" — three roles (work-on, review-pr, fix-pr-review) all comply holistically
  - `INDEX.md`: added `review-pr` to repo-handbook triggers
- **review-lessons buffer deprecated** for repos with handbook — new patterns go directly to handbook via Standard-First flow
  - `review-lessons-graduation` skill retained only for legacy repos without handbook

## [1.109.0] - 2026-04-13

- **jira-worklog moved to company layer** (`skills/kkday/jira-worklog/`)
  - Decision: worklog compliance is company-driven behavior, not universal developer need
  - Removed from framework `skill-routing.md` — no company-specific info in framework files
- **jira-worklog-batch.py — deterministic script replaces AI orchestration**
  - JIRA fetch, changelog parsing, allocation, delete/write all handled by Python script
  - AI only handles Google Calendar MCP (OAuth) → passes meeting hours JSON to script
  - Token consumption: ~100k → ~3k per monthly run
  - Fixed JIRA API migration: `/rest/api/3/search` → `/rest/api/3/search/jql` (cursor-based pagination)
- **Standup decoupled from worklog** — removed Post-Standup: Daily Worklog section
  - Monthly reminder stays in personal handbook (`working-habits.md`)

## [1.108.0] - 2026-04-13

- **jira-worklog v3.0 — monthly compliance model**
  - Redesign: `8h = meetings + 1h lunch + ticket work`, meeting hours from Google Calendar are core
  - Primary trigger changed from daily standup post-step to monthly batch
  - Phase 2 monthly reconciliation fills gap days, ensures monthly total ≈ expected
  - Monthly reminder added to personal handbook (last 5 workdays of month)
- **Skill catalog consolidation: 44 → 32 (-27%)**
  - Deleted: `end-of-day`, `example`, `start-dev`, `wt-parallel`
  - Merged: `which-company` → `use-company`, `validate-isolation` + `validate-mechanisms` → `validate`, `worklog-report` → `jira-worklog`, `epic-status` → `converge`, `unit-test-review` → `unit-test`, `systematic-debugging` → `bug-triage`
  - Downgraded: `kkday/docs-sync`, `kkday/sasd-review` (removed as skills)
  - `docs-sync` marked `scope: maintainer-only`
- **New mechanism: `defer-immediate-capture`**
  - When deferring work ("等 X 再處理 Y"), capture in todo/memory immediately
  - Added to `context-monitoring.md` §5b and `mechanism-registry.md`

## [1.107.0] - 2026-04-13

- **Skill catalog consolidation: 33 → 30 skills (cumulative 44 → 30, -32%)**
  - `scope-challenge` → `breakdown`: Quality Challenge inlined as Step 7.5; standalone Scope Challenge Mode added (SC1-SC5)
  - `tdd` → `unit-test`: TDD Mode §1.5 with Red-Green-Refactor cycle, cycle log, and anti-patterns
  - `jira-branch-checkout` → `references/branch-creation.md` + `scripts/create-branch.sh`: skill wrapper removed, script promoted to shared location
  - Updated 11 referencing files (INDEX, sub-agent-roles, work-on, git-pr-workflow, pr-convention, fix-pr-review, verify-completion, decision-audit-trail, refinement-artifact, confidence-labeling, tdd-smart-judgment)
  - Net -272 lines (19 files changed)

## [1.106.0] - 2026-04-13

- **Breakdown v2.0.0 — Universal Planning Skill (Phase 2 of 3-Layer Redesign)**
  - Rename `epic-breakdown` → `breakdown`: now handles Bug / Story / Task / Epic uniformly
  - New Bug Path (B1-B4): reads `[ROOT_CAUSE]` from bug-triage → estimates → simple (1-2pt) direct handoff or complex (3+pt) subtask split
  - Story/Task absorbed from `jira-estimation` Step 8: codebase exploration → subtask split → estimation → Quality Challenge
  - Epic path preserved within unified Planning Path (Steps 4-16)
  - Delete `jira-estimation` — estimation logic fully internalized into breakdown
  - Updated 22 reference files: routing, registry, skills, references
  - Net -402 lines across 24 files (consolidation)
  - Three-layer architecture now fully implemented: bug-triage/refinement → breakdown → work-on

## [1.105.0] - 2026-04-13

- **docs-sync: fix-bug → bug-triage rename across all documentation**
  - Reflects v1.104.0 3-layer architecture redesign in 12 bilingual doc files
  - Skill count corrected 43→42 in README.md, README.zh-TW.md, quick-start-zh.md
  - Mermaid diagrams updated: Bug path now shows `bug-triage` → `epic-breakdown` → `work-on` (3-layer)
  - Bug Fix prose sections rewritten for diagnosis-only model (workflow-guide EN/zh-TW, rd-workflow)
  - Template rule-examples updated (skill-routing, scenario-playbooks, pr-and-review)
  - chinese-triggers.md version bumped to v1.104.0, trigger keywords updated

## [1.104.0] - 2026-04-13

- **Skill Architecture Redesign — 3-Layer Separation (Phase 1)**
  - Three-layer model: Understanding (bug-triage / refinement) → Planning (breakdown) → Execution (work-on)
  - New: `bug-triage` v2.0.0 — pure diagnostic skill (root cause analysis → RD confirmation → enriched JIRA ticket)
  - Rewrite: `work-on` v3.0.0 — execution-only orchestrator, slimmed 56% (657→290 lines), Plan Existence Gate replaces Readiness Gate + AC Gate
  - Delete: `fix-bug` — replaced by bug-triage (Layer 1) + work-on (Layer 3)
  - Downgrade: `jira-estimation` v2.0.0 — library skill, callers updated to bug-triage + breakdown
  - Updated: `skill-routing.md`, `mechanism-registry.md`, and 12+ reference files cleaned of fix-bug references
  - Phase 2 planned: breakdown expansion as universal planner (Bug + Story/Task + Epic branches)

## [1.103.0] - 2026-04-12

- **Framework Handbook — User-Facing Working Preferences**
  - `.claude/handbook/` — new layer for user working habits and quality standards (not AI behavioral rules)
  - `working-habits.md` — session management, Strategist interaction style, decision patterns
  - `quality-standards.md` — output format (JIRA links, Slack URL formatting), verification standards
  - Migrated 6 feedback memories into handbook (session-split-direct, session-split-proactive, strategist-pushback, slack-url-linebreak, jira-ticket-clickable-link, session-split-include-trigger)
  - `CLAUDE.md` § Framework Handbook — periodic review flow (stay / upgrade to rules / downgrade to company handbook)
- **Refinement SKILL.md — Two Post-Validation Improvements**
  - Step 2b: Production Runtime Verification — curl/dev-server verification required when codebase analysis involves runtime behavior (source code ≠ runtime)
  - Step 5b: Output format constraint — refinement.md only contains implementation-ready information, no historical context or derivation process
  - Design path changed from `.claude/designs/` to `{company_base_dir}/designs/{EPIC_KEY}/` (ticket workspace model)
  - Modules table includes `Repo` column for cross-repo traceability

## [1.102.0] - 2026-04-12

- **Refinement v2 — Codebase-Backed Technical Validation**
  - `refinement/SKILL.md` v3.1.0 → v4.0.0: Phase 1 redesigned from checklist filling to 7-step technical verification
  - Complexity Tier (1/2/3): Tier 2 as floor — codebase exploration + AC hardening by default
  - AC Hardening: functional + non-functional + negative AC with verification method per criterion
  - Local-First Workflow: multi-round refinement via local markdown + browser preview, JIRA write-back only on finalization
  - `scripts/refinement-preview.py` — zero-dependency local preview server (Python stdlib + marked.js CDN, 3s auto-refresh)
  - `references/refinement-artifact.md` — structured JSON artifact schema for downstream skill consumption (breakdown, estimation, work-on)
  - `references/confidence-labeling.md` — shared confidence labeling reference (HIGH/MEDIUM/LOW/NOT_RESEARCHED)
  - Phase 2 enhanced with optional multi-role analysis (RD/QA/Arch lenses) for Tier 3
  - `references/INDEX.md` updated with new references + refinement added to explore-pattern triggers

## [1.101.0] - 2026-04-12

- **Dedup Scan + README Lint + Editorial Guideline**
  - `scripts/dedup-scan.py` — file-level bigram Jaccard overlap scanner for rules/ and references/
  - `scripts/dedup-scan-sections.py` — section-level containment scanner (finds embedded duplicates)
  - Resolved 3 true duplications: mechanism-registry § Library Rationalizations → ref to library-change-protocol.md; epic-verification-structure § Assignee → ref to jira-subtask-creation.md; epic-verification-structure § 三層驗證 → ref to epic-verification-workflow.md
  - `library-change-protocol.md` — enriched Common Rationalizations with `(docs, issues, config)` detail
  - `scripts/readme-lint.py` — skill count check + undocumented-skill cross-reference + `--fix` auto-correct + `--verbose` mode
  - `docs/quick-start-zh.md` — auto-fixed 3 stale skill counts (33/41 → 43)
  - `skills/references/docs-editorial-guideline.md` — new reference: writing style for public docs (conclusion-first, show don't tell, structured vs editorial split)
  - `rules/framework-iteration.md` — added readme-lint as Step 2 in post-version-bump chain
  - `polaris-backlog.md` — closed: "Rules/skills dedup scan", "README.md lint-on-bump"

## [1.100.0] - 2026-04-12

- **Backlog Clearance + Learning Refactor + Dedup**
  - `skills/references/review-lesson-extraction.md` — new shared reference: sub-agent prompt, dedup logic, write format, graduation check (extracted from learning SKILL.md PR/Batch modes, 1060→947 lines)
  - `skills/references/INDEX.md` — added review-lesson-extraction.md entry
  - `skills/learning/SKILL.md` — PR mode Steps P2-P4 and Batch mode Steps B5-B7 now reference the shared file instead of duplicating
  - `CLAUDE.md` — removed Context Recovery section (deduped into context-monitoring.md §4), 195→182 lines
  - `rules/context-monitoring.md` — enriched §4 Compression Awareness with artifact/timeline checks from CLAUDE.md
  - `polaris-backlog.md` — closed: skill-script-extraction (already done), learning refactor, CLAUDE.md refactor; merged: PostToolUse hooks ×2→1, isolation ×2→1; added: rules/skills dedup scan, README.md lint-on-bump

## [1.99.0] - 2026-04-12

- **Library Change Protocol + Blind Spot Scan + Key Libraries**
  - `rules/library-change-protocol.md` — universal protocol for replacing, upgrading, or removing dependencies: three-layer exhaustion check (docs → issues → config), four-question impact assessment, upgrade-specific checks (changelog, migration guide, peer deps, lock file diff), runtime vs build-time distinction, decision tier matrix
  - `CLAUDE.md` — added Blind Spot Scan as Strategist Responsibility #6: pre-execution self-check (invert, edge cases, silent failure) before presenting plans or decisions
  - `mechanism-registry.md` — registered 6 new mechanisms: `lib-exhaust-before-replace` (Critical), `lib-replace-is-t3`, `lib-config-registration-check`, `lib-lock-file-diff`, `lib-key-libraries-binding`, `blind-spot-scan`
  - b2c-web handbook — added Key Libraries section (Nuxt 3, Vue 3, Pinia, @nuxtjs/i18n, nuxt-schema-org, @nuxtjs/device, nuxt-vitalizer, Turborepo, Vitest)
  - member-ci handbook — added Key Libraries section (CodeIgniter 2, GuzzleHttp, Vue 2, Vuex 3, Vue Router 3, Webpack 5, Optimizely, Adyen)
  - `polaris-backlog.md` — added CLAUDE.md length refactor as Low priority item

## [1.98.0] - 2026-04-12

- **member-ci Handbook v0 + Company Handbook Enrichment**
  - Generated `kkday-member-ci/.claude/rules/handbook/` — index.md (architecture overview) + 6 sub-files (api-design, php-conventions, security, vue-conventions, logging, testing)
  - Graduated 4 existing rules files + 11 review-lessons files into handbook sub-files, deleted originals
  - Key corrections from user Q&A: CodeIgniter 2.1.4 (not 3), pure PHP → Vue 2 history, device routing via CloudFront + UA, internal API design principle (不對外揭露 service)
  - `rules/kkday/handbook/cross-repo-dependencies.md` — enriched with web-api ↔ member-ci, member-ci ↔ mobile-member-ci (legacy), member-ci ↔ docker dependencies, internal API design principle

## [1.97.0] - 2026-04-12

- **Review-Lessons Buffer Deprecation + Handbook Direct Write**
  - `repo-handbook.md` — 有 handbook 的 repo，PR review findings 直接寫入 handbook 子文件，不經 review-lessons/ buffer
  - `repo-handbook.md` — Ingest channel table 更新：PR review lesson → PR review finding (direct write)
  - `repo-handbook.md` — Review Lessons → Handbook 流程圖更新為 Direct Write 三層分類
  - First real-world validation: b2c-web 14 review-lessons files graduated (70+ patterns), review-lessons/ directory deleted

## [1.96.0] - 2026-04-12

- **Handbook Lifecycle — Full Implementation (Generate→Ingest→Query→Lint)**
  - `explore-pattern.md` — Handbook-First 探索協議：Explorer subagent 先讀 handbook 再做 codebase scan，只探索 gap，減少冗餘 Read
  - `explore-pattern.md` — Handbook Observations 回傳欄位（Used / Gaps / Stale），Strategist 收到後自動回寫 handbook
  - `explore-pattern.md` — Handbook 回寫規則：Gap → 寫入 repo/company handbook（`confidence: generated`）、Stale → 直接修正或加 stale-hint
  - `explore-pattern.md` — Conflict resolution 優先級：user correction > PR lesson > Explorer 回寫
  - `repo-handbook.md` — Step 4 重組為三管道 ingest channel（user correction / PR lesson / Explorer 回寫），lifecycle diagram 更新
  - `repo-handbook.md` — Step 5 Handbook Lint 三粒度保鮮機制：Lazy lint（讀到時驗）、Event-driven lint（git diff → stale-hint）、Batch lint（sprint planning / monthly standup）
  - `mechanism-registry.md` — 新增 Handbook Lifecycle section（5 個 canary signal）
  - `INDEX.md` — explore-pattern 描述更新

## [1.95.0] - 2026-04-11

- **AI Files Local-Mode Automation**
  - `workspace-config.yaml` — 新增 `ai_files_mode` 欄位（`local` / `committed`），公司層級控制 AI 檔案可見性
  - `polaris-sync.sh` — deploy 後自動設定 `.git/info/exclude` + `skip-worktree`（檢查 .gitignore 避免重複、只對 tracked files 設 skip-worktree、冪等）
  - `polaris-sync.sh --scan` — 新 mode，一次掃描所有 workspace repos 並修復缺漏的 git-hide 設定
  - 修正 `get_projects()` parser：只取 `projects:` block，不會誤撈 `visual_regression` 等 nested names
  - 首次 scan 修復 web-design-system（3 tracked files 缺 skip-worktree）和 kkday-web-docker（缺 exclude entry）

## [1.94.0] - 2026-04-11

- **Handbook Knowledge Injection — Two-Layer Strategy**
  - `sub-agent-roles.md` — Company handbook = Strategist 選擇性摘錄；Repo handbook = sub-agent 自己全讀（效果等同 auto-loaded rules）
  - `repo-handbook.md` — 修正「auto-loaded by Claude Code」的錯誤描述。在 workspace setup 下 repo handbook 不會自動載入，需透過 dispatch prompt 指示 sub-agent 自己讀
  - 設計原則：company-level 放 workspace（永遠相關，自動載入）；repo-level 留在 repo（按需注入，避免 context 膨脹）

## [1.93.0] - 2026-04-11

- **Company Handbook — Three-Layer Knowledge Architecture**
  - **New concept**: Handbook 分三層 — Framework（個人工作風格）→ Company（跨 repo 知識）→ Repo（單一 repo 架構）。受 Karpathy 知識庫系統啟發：探索效率來自「起點更高」（compiled knowledge），不是「步驟更聰明」
  - **KKday company handbook** (`rules/kkday/handbook/`): index.md + 4 子文件（cross-repo-dependencies, development-workflow, tools-and-channels, testing-and-verification）
  - **Three-layer classification** (`repo-handbook.md` Step 3b): Q1「換 workspace 還適用？」→ Q2「換 repo 還適用？」— 三個問題，每個 3 秒可分類
  - **Company context injection** (`sub-agent-roles.md`): dispatch sub-agent 到子 repo 時，Strategist 注入 company handbook 的 Cross-Repo Dependencies 段落
  - **feedback-and-memory.md** item 1 改為三層分類邏輯
  - **12 筆 memory 遷移至 company handbook** 後刪除，MEMORY.md 瘦身

## [1.92.0] - 2026-04-11

- **Backlog Context Format — 每個項目附帶 Why / Without it / Source**
  - `polaris-backlog.md` — 新增 § Item Format 格式規範，所有現有項目補上 context block（動機、後果、來源）
  - `feedback-and-memory.md` — backlog entry format 從一行模板升級為帶 context block 的多行格式
  - AI Files Management 3 個子項合併為一個群組項目
  - 目標：「繼續 Polaris」時讀 backlog 即可判斷優先序，不需翻 memory 重建前因後果

## [1.91.0] - 2026-04-11

- **Handbook as Review Standard — Review Comment ↔ Handbook Cross-Reference**
  - `fix-pr-review` Step 7b 新增：修正前比對 review comment 與 handbook，衝突 → 暫停 → escalate（修 code + 更新 handbook，或回覆 reviewer 說明慣例）
  - `review-lessons-graduation` 畢業路由三分流：repo-specific → `handbook/*.md` 子文件（優先）、跨 repo 通用 → `rules/*.md`、framework → workspace `rules/*.md`
  - `repo-handbook.md` Step 3c 新增：Handbook as Review Standard — review-pr / fix-pr-review / graduation 三者統一以 handbook 為 primary context
  - Reviewer 的意見反過來驗證 handbook：衝突是 handbook 品質的校正信號，每次解決後知識庫更準確

## [1.90.0] - 2026-04-11

- **Handbook v1 — Correction-Driven Update + Nested Structure**
  - **Correction-Driven Update** (`repo-handbook.md` Step 3b) — user 糾正 repo-specific 知識時，暫停工作 → 更新 handbook（不建 feedback memory）→ 基於新理解繼續。判斷捷徑：「換一個 workspace 還適用嗎？」No → handbook，Yes → feedback
  - **Nested handbook structure** (Step 3a) — 主文件 100-300 行（架構全景），子文件 `handbook/*.md` ≤50 行（code style、testing、API conventions），全部在 `.claude/rules/` 自動載入
  - **Step 1 補強** — handbook 生成第一步改為「先讀 README.md」，README 是 Overview 和 Cross-Repo 段落的 primary source
  - **feedback-and-memory.md** — item 1 加入 handbook vs feedback 分類邏輯：repo-specific → handbook，framework → feedback
  - **mechanism-registry.md** — 新增 `correction-driven-handbook-update` (Critical) + `repo-knowledge-to-handbook-not-feedback` (High) canary
  - **首批 handbook 產出**：kkday-b2c-web（主文件 + 3 子文件：local-dev, testing, cwv-benchmark）、kkday-web-docker（主文件）
  - **Feedback → Handbook 遷移**：7 筆 kkday repo-specific feedback memory 遷移至 handbook 子文件並刪除

## [1.89.0] - 2026-04-11

- **Repo Handbook — AI 的新人 onboarding 文件**
  - `skills/references/repo-handbook.md` — 完整設計：repo 類型辨識（10 種 primary type + 6 種 secondary trait）、按類型生成 handbook 結構、user Q&A 校正流程、stale detection 維護機制
  - `/init` — 最後新增 optional step：老手可在初始化時直接為已設定的 repo 建立 handbook
  - `work-on` — Phase 0.5 Handbook Check：首次 work-on 自動觸發 handbook 生成；sub-agent prompt 加入「先讀 handbook 再探索」指示
  - `git-pr-workflow` + `fix-pr-review` — post-step：PR 建好/修完後自動 diff 改動 vs handbook，更新 stale 段落
  - Handbook 存在 `{repo}/.claude/handbook.md`（gitignored），類比人類的架構文件：README 是給外部人看的，CLAUDE.md 是員工守則，handbook 是系統架構文件

## [1.88.0] - 2026-04-11

- **Learning Compile & Lint — 知識複利機制** (inspired by Karpathy's LLM Knowledge Base)
  - **Step 1.5 增強**: Baseline scan 新增查詢 `polaris-learnings.sh` 既有知識，讓每次學習從已知出發而非從零開始
  - **Step 4b Compile (新增)**: 新學到的知識與既有 learnings 碰撞 — 明確標注 confirm（增強信心）/ contradict（發現矛盾）/ extend（擴展深度）/ new（全新知識）。自動 confirm/boost 已驗證的 learnings
  - **Step 6 Lint (新增)**: 學習完成後分析知識盲點 — adjacent unknowns、stale knowledge、unresolved contradictions、depth gaps。產出 1-3 個建議下一步學什麼，並自動回寫 learnings 到 cross-session knowledge base
  - External flow 從 `Ingest → Extract → Save` 進化為 `Ingest → Extract → Compile → Save → Lint`，知識從此能滾雪球

## [1.87.0] - 2026-04-10

- **GT-521 拘束機制 — 行為規則推到確定性層**
  - `scripts/verification-evidence-gate.sh` (PreToolUse) — ticket branch 上 `gh pr create` 必須有 `/tmp/polaris-verified-{TICKET}.json` evidence file（valid JSON、< 4h、ticket match、non-empty results）。無 evidence = exit 2 物理攔截。Bypass: `POLARIS_SKIP_EVIDENCE=1`（非 ticket PR）
  - `scripts/test-sequence-tracker.sh` (PostToolUse on Bash|Edit|Write) — 追蹤 test-fail → production-file-edit → test-pass 序列，偵測到時注入警告：「你改了 production code 讓測試過，確認這是正確修法？」
  - `scripts/polaris-write-evidence.sh` — evidence file writer，供 verify-completion / fix-bug 呼叫
  - `api-docs-before-replace` mechanism (Critical) — 模組行為不符預期時，必須查官方 API 文件再行動。Compiled source ≠ API truth。替換是 T3 決策需使用者確認
  - mechanism-registry: 新增 Deterministic Quality Hooks section + Priority Audit Order #12
  - settings.json: 註冊兩支新 hooks

## [1.86.0] - 2026-04-10

- **`runtime-claims-need-runtime-evidence` mechanism (High)** — Sub-agent source code analysis about runtime behavior must be verified with actual execution (curl, test, dev server) before adoption. Source: nuxt-schema-org JSON-LD position was incorrectly concluded as `<head>` from code reading; actual production output is in `<body>`
- **Backlog cleanup addendum** — closed Session-split checkpoint gate (covered by `checkpoint-mode-at-25`)

## [1.85.0] - 2026-04-10

- **API Contract Guard** — Detects schema drift between Mockoon fixtures and live API responses. Prevents stale fixtures from masking real API contract changes (false negatives). Three drift categories: breaking (type change, field removal → blocks task), additive (new field → auto-update), value-only (same schema → no action)
  - `scripts/contract-check.sh` — schema diff engine (Python, zero deps). Parses Mockoon environment files, hits live API via proxyHost, recursive JSON schema comparison. Exit codes: 0=clean, 1=breaking, 2=unreachable
  - `skills/references/api-contract-guard.md` — design doc with drift classification, skill integration pattern, fixture update flow
  - Pre-steps added to 4 skills: `visual-regression` (Step 2.5), `fix-bug` (Step 4.4), `work-on` (Phase 1.5), `verify-completion` (Pre-flight)
- **Backlog cleanup** — closed 36 items (23 Medium no-pain/premature + 13 Low brainstorm-era). 11 items remain

## [1.84.0] - 2026-04-10

- **fix-pr-review configurable mode** — Step 0.5 now reads `skill_defaults.fix-pr-review.mode` from `workspace-config.yaml` (default: `auto`). Users set their preferred mode in config; per-invocation keywords (`互動`/`auto`) still override

## [1.83.0] - 2026-04-10

- **Backlog Hygiene mechanism** — Post-version-bump chain 新增 Step 2：掃描 `polaris-backlog.md` 的 stale items。每個 `[ ]` item 帶 `(YYYY-MM-DD)` 日期 tag，可選 `[platform]`/`[next-epic]` 豁免 tag。無 tag > 60 天 → 建議關閉，有 tag > 90 天 → 確認是否仍有效。Fallback：每月首次 `/standup` 觸發
- **Backlog 大掃除** — 移除 ~75 個完成項，34 個 open items 按主題重新分組，全部標記日期 + 豁免 tag。檔案從 362 行縮到 137 行
- **`backlog-staleness-scan` mechanism (Medium)** — 新增 mechanism-registry canary，追蹤版本升級和月度 standup 是否觸發 backlog 掃描

## [1.82.0] - 2026-04-10

- **fix-bug Step 4.5 Hard Gate** — AC Local Verification 升級為 Hard Gate：每個 Local 驗證項必須有 PASS/SKIP/FAIL disposition + 證據（test output、curl response、截圖），不允許「unit test 過了就跳過行為驗證」。來源：KB2CW-3783 hotfix 中跳過了起 dev server 的語系切換驗證，只靠 unit test 就發 PR
- **`local-verification-hard-gate` mechanism (Critical)** — 新增 mechanism-registry canary：fix-bug Step 4.5 的 Local 驗證項如果包含行為驗證（需起 server），不可只用 unit test 替代

## [1.81.1] - 2026-04-10

- **Reference Discovery INDEX.md tracked** — `skills/references/INDEX.md` now committed to the repo (was untracked). Reference Discovery section added to CLAUDE.md as a supplement to v1.80.0

## [1.81.0] - 2026-04-10

- **sync-to-polaris auto-genericize** — Before committing to the template repo, automatically applies each company's `genericize-map.sed` + `genericize-jira.sed` to all `.md` files. Company-specific references (JIRA keys, domains, Slack IDs, org names) are replaced with generic placeholders before the template is committed. The post-commit leak check now serves as verification — surviving patterns indicate missing sed rules, not a manual cleanup task. Converts the 18-hit leak warning (v1.79.0) from "remind to fix" to "auto-fixed"

## [1.80.0] - 2026-04-09

- **Version bump reminder PostToolUse hook** — Deterministic enforcement for the Critical `version-bump-reminder` mechanism. `hooks/version-bump-reminder.sh` fires after every `git commit`, checks committed files for `skills/` or `rules/` paths, injects a reminder if found. Skips VERSION bump commits to avoid loops. Wired into `settings.json` PostToolUse
- **Reference Discovery mechanism (Critical)** — New `reference-index-scan` canary in mechanism-registry: before any skill execution, read `skills/references/INDEX.md` and pull trigger-matched references. Added to CLAUDE.md § Reference Discovery as a skill execution prerequisite. Common Rationalizations table included
- **Write Isolation Model documentation** — `sub-agent-delegation.md` gains § Write Isolation Model: three tiers (Shared / Worktree / Cross-repo) with selection guide, inspired by LangGraph's per-task write buffer pattern
- **Backlog hygiene** — closed "Standup 口頭同步條列化" (already implemented), closed "Version bump hook" (done this version), closed "Write isolation model 文件化" (done this version)

## [1.79.0] - 2026-04-09

- **jira-worklog v2.0 — Daily quota allocation** — 8h per workday split among In Development tickets by story point weight. Smart filtering excludes non-logged ticket types. Batch curl for multi-day backfill. Standup auto-log integration
- **Story Points dynamic discovery (cross-cutting)** — `jira-story-points.md` rewritten as authoritative reference with mandatory Step 0 field ID discovery. All 7 skills using Story Points (converge, epic-status, intake-triage, jira-worklog, my-triage, jira-subtask-creation, work-on) updated to use `<storyPointsFieldId>` placeholder — hardcoded `customfield_10016` strictly forbidden
- **epic-verification-structure.md rewrite** — Verification tickets default 0pt (not 1pt), lifecycle flow with PASS/FAIL comment templates, Epic close criteria, implementation task description split into code-level test plan vs business-level AC sections, test sub-tasks as JIRA 子任務 issueType (not Task)
- **PR review conventions (L1 rule)** — New universal `pr-and-review.md`: inline comments mandatory (no findings in review body), review language follows PR description language. kkday-scoped placeholder added
- **check-pr-approvals** — PR links must be clickable markdown format
- **jira-subtask-creation** — Step 0 query existing sub-tasks before creating, assignee param fix
- **version-bump-reminder canary (Critical)** — Added to mechanism-registry after discovering 6 consecutive sessions modified `skills/` without triggering version bump reminder. Common Rationalizations table added. Backlog item for deterministic PostToolUse hook

## [1.78.0] - 2026-04-08

- **sasd-review v1.0.0 — Design-First Gate** — 從 kkday 專屬提升為框架級 skill。在寫任何程式碼前產出 SA/SD 設計文件：需求分析 → 歧義收集 → 2-3 方案比較 → 確認後產出（含 Dev Scope、System Flow、Task List with Estimates）。移除 kkday 專有術語（BFF、PC/M），保留通用工程紀律
- **jira-quality.md — L1 通用 JIRA 規則** — 從 kkday jira-conventions 提升 7 條通用規則：缺資訊主動問不猜、PM 範例 ≠ 實作規格、外部連結需取回內容、建完 issue 附連結、拆單含驗證場景、批次建子單、attachment 先刪再傳。kkday jira-conventions 瘦身為僅保留專案 key 結構和 VR template 格式
- **清理 kkday 重複 skills** — 刪除 ai-config 中 6 個重複的 skill 副本（kkday-dev-quality-check、kkday-git-pr-workflow、kkday-unit-test、kkday-dev-guide 及對應的 non-prefix stale copies），Polaris 已有更新版本
- **skill-routing.md** — 新增 sasd-review 路由條目

## [1.77.0] - 2026-04-08

- **pr-convention v1.3.0 — Template-aware PR body** — Step 1 偵測專案 PR template 檔案（5 路徑優先順序），Step 4b 以 template section 結構為骨架填入內容。Mapping table 涵蓋常見 section（Description, Changed, Screenshots, Checklist, Breaking Changes 等），不認識的 section 保留 heading 並用 HTML comment hint 生成內容。無 template 則 fallback 到預設格式。AC Coverage 在 template 未定義時自動注入
- **git-pr-workflow Step 7** — 改為引用 pr-convention 的 template 偵測與 mapping 邏輯，避免重複定義

## [1.76.0] - 2026-04-07

- **fix-bug Step 4.5 AC Local Verification** — 開發完成後、發 PR 前，根據 ticket 的 [VERIFICATION] Local 項目逐一驗證（unit test / Playwright 截圖 / 手動確認），結果更新回 JIRA。Post-deploy 項目標記「待 SIT 驗證」不阻擋 PR
- **fix-bug VR Gate（條件觸發）** — 改動涉及前端可見代碼（pages/components/layouts/*.vue/*.scss）且有 VR 設定時，自動觸發 visual regression 檢查
- **jira-estimation VERIFICATION 兩層模板** — Bug 的預計驗證方式分 Local（PR 前，RD 負責）和 Post-deploy（SIT/Prod，驗證子任務追蹤）兩層，JIRA comment 模板同步更新

## [1.75.0] - 2026-04-07

- **jira-estimation Bug VERIFICATION section** — Bug ticket 的 [ROOT_CAUSE] + [SOLUTION] 模板新增 `[VERIFICATION]` 段，列出預計驗證方式（重現步驟、邊界場景、數據確認），比照 Task 的 AC 概念
- **pr-create-guard.sh env bypass** — 新增 `POLARIS_PR_WORKFLOW=1` 環境變數讓 git-pr-workflow skill 合法放行 `gh pr create`。修正 hook 無法區分「隨手開 PR」與「skill 品質檢查後開 PR」的設計缺口
- **git-pr-workflow v3.4.0 Step 7** — 加上 `POLARIS_PR_WORKFLOW=1` 環境變數說明

## [1.74.0] - 2026-04-07

- **VR Principles P1-P7** — 將 6 個 session 累積的 hard-won rules 集中寫入 SKILL.md（走 nginx proxy、CSR waitForSelector、mobile UA、proxy/replay mode 差異、首次截圖 quality gate、workers:1、JIRA wiki markup）。P1/P3 泛化為框架層原則，kkday 細節以 blockquote 附註
- **VR Phase 2 mandatory checkpoint** — replay mode 切換後強制跑 VR pass + 人工截圖確認，才能進 Phase 3 commit fixtures。防止 proxy fallback 隱藏缺失 fixture
- **VR JIRA report template** — 新增 `references/vr-jira-report-template.md`，定義 wiki markup 表格穿插截圖格式、all-pass / mixed results 模板、attachment 命名慣例。Step 5c 引用此 template
- **checklist-before-done 機制** — 宣告任務完成前必須回查 session 起始清單，逐項確認 done/carry-forward/dropped。加入 context-monitoring §5b + mechanism-registry（High drift）
- **JIRA 附件先刪再傳規則** — 加入 `rules/kkday/jira-conventions.md`，適用所有 JIRA attachment 操作
- **ai-config version control** — `.gitignore` whitelist VR test files（pages.spec.ts, playwright.config.ts）+ proxy-config.yaml。Fixture JSON 維持 local only。新公司只需加 `!{company}/`
- **visual-regression-config.md** — 新增 Playwright config 必設項目（workers:1, mobile UA）

## [1.73.0] - 2026-04-06

- **Per-Epic Fixture Isolation** — fixture 管理從 root-level 遷移到 per-epic 子目錄（`mockoon-environments/GT-483/`）。每個 Epic 獨立一套完整 fixture，新 Epic 從上一個 copy + 重錄有變動的 route。刪除 root-level 12 個 legacy JSON 檔案
- **mockoon-runner.sh `--epic` 參數** — `mockoon-runner.sh start <dir> --epic GT-483` 從子目錄載入 fixture。Root-level loading 標記 deprecated
- **VR SKILL.md 三個 feedback 寫入** — (1) Mockoon CLI proxy 不自動錄 fixture，需手動 curl (2) 首次截圖品質閘門：zero-diff ≠ 正確，需人工確認 (3) JIRA attachment 同名覆蓋陷阱：wiki markup 綁 attachment ID 不是檔名
- **VR SKILL.md Fixture Lifecycle section** — 文件化 per-epic 目錄結構、bootstrap 流程、runner 整合、設計決策（為何不做 base + overlay）
- **GT-483 fixture 合併** — 從 root 補齊 11 條 route（mkt 1、svcb2c 2、hotel_product 4、product 4），GT-483 現為完整獨立集合（12 檔、47 routes）
- **Gzip header 全清** — 最後一個殘留（GT-483/recommend `content-encoding: gzip`）已移除。來源：Mockoon proxy 錄製時抓了真實 server 的壓縮 header 但存了已解壓的 body

## [1.72.0] - 2026-04-06

- **Cross-Session Carry-Forward Check** — 寫 next-session memory 前必須 diff 前一份 checkpoint 的 pending items。每個 item 必須標記為 (a) done / (b) carry-forward / (c) dropped，不允許靜默丟棄。根因：v1.71 session 掉了 JIRA VR 報告，因為 4/6 session 寫新 memory 時沒回頭檢查 4/5 checkpoint 的未完成項
- **Checkpoint Mode at 25 Tool Calls** — tool call > 25 且有 pending work 時，主動進入存檔模式：寫 checkpoint memory + diff 前一份 checkpoint + 建議開新 session。防止 context 耗盡導致跨 session 狀態遺失
- **mechanism-registry 新增** — `cross-session-carry-forward` (Critical) + `checkpoint-mode-at-25` (High)，加入 Priority Audit Order #5 和 #6a

## [1.71.0] - 2026-04-06

- **VR 確定性修復：fixture gzip header 根因** — Mockoon fixture 的 `Content-Encoding: gzip` header 搭配 plain JSON body 導致 Mockoon crash（嘗試解壓非壓縮資料）。這同時是 proxy mode 崩潰和 Product page SSR hang 的根因。移除 14 個 response 的 gzip header 後，8/8 zero-diff、Product page 首次正常渲染
- **polaris-env.sh env override 恢復** — `--vr`/`--e2e` 自動從 `proxy-config.yaml` 讀 `env_override` 注入 dev server 啟動指令。v1.70.0 移除後發現仍需要（Mockoon fixture 需要 env override 才能攔截 API calls）
- **VR SKILL.md：Record → Compare 兩階段流程** — 新增 Fixture Recording Workflow section，文件化 fixture 錄製（proxy mode）→ 驗證（replay mode）→ commit 的完整生命週期
- **JIRA VR 報告補發** — GT-483 VR 通過 comment（8/8 zero-diff + 確定性措施 + 修復紀錄），修正上次 session 遺漏
- **proxy-config.yaml 公司層** — 從 GT-483/ Epic 目錄 copy 到 `mockoon-environments/`，成為公司共用 config

## [1.70.0] - 2026-04-05

- **VR 架構修正：走 Docker nginx，不走 localhost** — VR base_url 從 `localhost:3001` 改回 `dev.kkday.com`（Docker nginx）。之前因 Docker compose v2 壞掉繞過 nginx，導致整個架構歪掉（Product page "SSR hang"、Search page "不在 b2c-web" 都是偽問題）。現在回到正確路徑：Playwright → Docker nginx → b2c-web / member-ci / mobile-member-ci
- **移除 Search page** — `kkday.com/zh-tw/search/?keyword=tokyo` production 回 404，頁面不存在。從 spec 和 workspace-config 移除
- **Product page 解除 skip** — 走 Docker nginx 後 SSR 應能正常 render，之前的 "hang" 可能是 localhost 直打造成的
- **移除 polaris-env.sh env override 自動注入** — 不再需要 Mockoon 取代 nginx，b2c-web 通過 Docker 網路呼叫 member-ci
- **feedback memory** — 記錄 workaround 累積導致架構歪掉的完整路徑，`no-workaround-accumulation` 教科書案例

## [1.69.0] - 2026-04-05

- **VR JIRA 圖文報告** — Step 5b 擴充為三步（收集 artifacts → `jira-upload-attachment.sh` 批次上傳 → 解析 URL）。Step 5c 改為 wiki markup 圖文穿插報告（每頁一 section，PASS 附截圖，FAIL 附 diff 圖，SKIP 附原因）。MCP markdown mode 不支援 attachment 引用，改用 REST API v2 + wiki markup
- **jira-upload-attachment.sh** — 共用腳本，curl + JIRA REST API 批次上傳 attachment，自動從 `.env.secrets` 讀取 credentials。所有需要 JIRA 附件的 skill 可共用
- **Fixture 一致性驗證** — `proxy-config.yaml` 新增 `migration_pairs` schema，`record-fixtures.sh` Step 6 自動比對新舊 endpoint 的 JSON key structure。支援 `key_structure` 和 `exact` 兩種比對模式，endpoint 遷移場景（如 i18n member-ci → api-lang）自動抓不一致
- **polaris-env.sh env override 自動注入** — `--vr`/`--e2e` profile 下自動掃描 `environments_dir/*/proxy-config.yaml`，讀取所有 `env_override` 值 prepend 到 dev server 啟動指令。不再需要手動設定 `.env.local`
- **Product page SSR hang 重分類** — 確認 fixture 已齊（`fetch_product/10000` + `fetch_packages_data`），hang 是 SSR code 層級 bug（API 全回但 render 不完成）。Backlog 從 "fixture 補全" 更新為 "SSR debug runbook"
- **Search page 不在 b2c-web** — 確認 `/search/` 由外部服務處理，local dev 無法載入。SIT mode 可覆蓋

## [1.68.0] - 2026-04-05

- **VR domain-level testing principle** — VR tests domains, not repos. Skip reasons changed from "not in this repo" to actionable TODOs (missing fixtures, SSR investigation needed). Feedback memory recorded for cross-session enforcement
- **VR SKILL.md Step 5c: JIRA update required** — VR results (pass/fail/skip with reasons) must be written to JIRA verification ticket after every run. Structured comment template added
- **VR backlog: 5 coverage completeness items** — Product page fixture gap, Search Results fixture, dual-endpoint consistency validation, JIRA auto-update AC, polaris-env.sh env override automation

## [1.67.0] - 2026-04-05

- **Design doc persistence in work-on** — `work-on` now writes a per-ticket design doc to `.claude/designs/{TICKET-KEY}.md` at two points: batch Phase 1 Step 1e (after user confirms analysis) and single-ticket Step 5g (after AC Gate). Design docs capture technical approach, test plan, sub-tasks, and decisions. Phase 2 sub-agents now read the design doc file instead of receiving inline analysis text, reducing prompt size and enabling cross-session resume via file read. `.claude/designs/` added to `.gitignore`
- **CLAUDE.md updated** — `.claude/designs/` listed in Framework Files section and product repo `.gitignore` recommendation

## [1.66.0] - 2026-04-05

- **CSO audit: 17 skill descriptions rewritten to trigger-only** — Discovered via Superpowers learning that SKILL.md descriptions containing workflow summaries cause the agent to shortcut (follow description instead of reading full body). Audited all 42 skills: 9 HIGH, 8 MEDIUM flagged. All 17 descriptions rewritten to contain ONLY trigger conditions, never workflow steps. Average reduction from 6-14 lines to 1 line per description
- **Rationalization tables for top 3 high-drift mechanisms** — Added "Common Rationalizations" sections to mechanism-registry.md for `skill-first-invoke` (7 entries), `delegate-exploration` (4 entries), and `fix-through-not-revert` + debugging/verification (7 entries). All entries sourced from real observed violations (GT-483 sessions, VR env failures), not hypothetical. Pattern inspired by Superpowers' prompt engineering approach
- **Superpowers learning → 2 backlog items** — Critic two-stage review split (spec-compliance + code-quality), skill-creator baseline failure recording (RED-GREEN-REFACTOR for skills)

## [1.65.0] - 2026-04-05

- **Fan-in validation for parallel sub-agents** — new "Fan-In Validation" section in `sub-agent-delegation.md`. When dispatching multiple parallel sub-agents, the Strategist now validates all completion envelopes before synthesis: Status must be present, Artifacts must be non-empty for DONE status, and missing/BLOCKED/PARTIAL agents are handled explicitly. Prevents silent partial failures from corrupting synthesis results
- **Return vs Save separation in completion envelope** — `sub-agent-roles.md` Completion Envelope gains a new convention: `User Summary` (concise result for display) vs `Checkpoint State` (full context for cross-session resume). Solves the common failure mode where memory files are either too terse or too verbose for session continuation
- **LangGraph learning → 4 backlog items** — Deep exploration of langchain-ai/langgraph produced actionable insights: per-skill retry policy (`polaris-retry.sh`), session-level cache (`polaris-cache.sh`), write isolation model documentation, and structured memory namespace. All tracked in backlog Medium with source attribution

## [1.64.0] - 2026-04-05

- **Chinese developer guide sections** — quick-start-zh.md expanded from quick-start-only to complete developer guide: architecture (three-layer rules, directory structure, workflow orchestration, scheduled agents), multi-company setup (isolation mechanism, diagnostics), customization (safe-to-edit vs framework internals), and upgrading (sync-from-polaris.sh). Chinese-speaking colleagues no longer need to reference the English README

## [1.63.0] - 2026-04-05

- **sync-to-polaris post-sync leak check** — new `leak_check()` function in `sync-to-polaris.sh` that runs between commit and push. Extracts company-specific patterns from all `workspace-config.yaml` files (JIRA ticket keys as `KEY-\d+`, domain names, Slack channel IDs, GitHub orgs) and greps the polaris template. Warns on matches but does not block push. First scan found 71 hits to genericize over time
- **VR strict judgment backlog cleanup** — merged two duplicate entries, confirmed VR SKILL.md already has "Strict mode (fixtures active)" section with zero-diff-only pass criteria

## [1.62.0] - 2026-04-05

- **Mockoon fixture per-Epic lifecycle** — epic-verification-workflow.md gains Fixture Lifecycle section: record at Epic start, re-record after cross-repo API task, develop on stable fixtures, delete on release. kkday playwright-testing.md gains full Mockoon integration doc (architecture, recording workflow, parallel Epic isolation design). Backlog item updated from "pending" to "design complete"
- **epic-breakdown API-first ordering + fixture recording task** — when Epic involves cross-repo API changes, API task must be ordered first. Additionally, epic-breakdown now auto-generates a "穩定測資" (fixture recording) task (1pt) for Epics with `visual_regression` config. Ordering: API task → fixture recording → frontend tasks. This makes fixture recording a visible, trackable JIRA ticket instead of hidden skill logic

## [1.61.0] - 2026-04-05

- **fix-pr-review Step 3b rebase hygiene expansion** — Step 3b renamed to "Post-Rebase 衛生檢查" and split into 3b-1 (full scan of inherited non-PR files: changesets, pre.json, CHANGELOG, package.json version bumps) + 3b-2 (changeset self-check). Previously only cleaned `.changeset/` files, now uses `git checkout origin/{baseRefName}` to restore all inherited files to base state before push. Source: PR #2088 lesson where rebase brought in unrelated CHANGELOG and version bumps

## [1.60.0] - 2026-04-05

- **Epic verification Playwright-first update** — epic-verification-workflow.md updated with `browser` (Playwright) as the preferred verification type over curl. Verification examples use `{BASE_URL}` variable (company-layer defines the actual URL). Added GT-483 Lessons Learned section: browser-first rationale, URL format conventions (locale lowercase, urlName not area code), SIT→localhost test data sourcing. Graduation checklist: Epic #1 complete, awaiting Epic #2 to graduate into skill integration
- **kkday playwright-testing reference** (company-layer, gitignored) — defines dev.kkday.com as BASE_URL, Docker routing map (b2c-web / member-ci / mobile-member-ci), auth via test account + storageState, A/B mock via route intercept, URL conventions

## [1.59.0] - 2026-04-04

- **Deterministic post-task reflection checkpoint** — 33 write skills now have a mandatory `## Post-Task Reflection (required)` final step in their SKILL.md, pointing to shared reference `skills/references/post-task-reflection-checkpoint.md`. Covers behavioral feedback scan, technical learning check, mechanism audit (top 5 canaries), and graduation check. 12 read-only skills excluded. Root cause: two GT-483 sessions produced 12+ violations with zero feedback because the Strategist was always "still fixing" and the task-completion trigger never fired. This is 方案 C from the backlog — the lowest-cost deterministic enforcement that makes reflection impossible to skip

## [1.57.0] - 2026-04-04

- **polaris-env.sh Docker health check fix** — Docker services (Layer 1) now use port-listening check instead of HTTP 200 (nginx returns 404 on `/` but services are up). Requires check for Docker dependencies also uses port-based verification. Fixed `docker compose` → `docker-compose` for Colima compatibility. Added stabilization wait before Layer 4 verification
- **JIRA attachment upload via REST API** — validated curl-based upload to JIRA tickets using API token stored in `{company}/.env.secrets`. Enables VR screenshots to be attached to verification tickets. Token setup uses IDE file editing (not terminal `read -s` which fails in Claude Code's non-interactive shell)

## [1.56.0] - 2026-04-04

- **Deterministic Enforcement Principle** — new framework-level design philosophy in CLAUDE.md: "能用確定性驗證的，不要靠 AI 自律". When behavioral drift is discovered, the fix must push checks into deterministic layers (scripts, hooks, exit codes), not add another behavioral rule. Includes workaround accumulation signal: ≥2 workarounds for the same feature → STOP and check design
- **polaris-env.sh design fix** — `--vr` profile now starts Layer 1 (Docker) like all other profiles. Previous design incorrectly assumed Mockoon replaces Docker; Docker is infrastructure, Mockoon supplements it. Removed `ensure_redis()` (Redis lives in Docker compose). Restored `requires` check for all profiles
- **polaris-env.sh hard gate** — Layer 4 verification is now profile-aware and exits non-zero when required services fail health check. Prevents downstream tools from running in a broken environment
- **VR strict mode** — SKILL.md Step 5: when Mockoon fixtures are active, zero-diff is the only PASS. No "known variance" or "data variation" classification allowed
- **Decision drift mechanisms** — 4 new canaries in mechanism-registry: `no-workaround-accumulation` (Critical), `design-implementation-reconciliation` (High), `env-hard-gate` (High), `no-bandaid-as-feature` (High). Workaround accumulation is now #1 in Priority Audit Order
- **Backlog: skill checkpoint gate + clean-room test** — medium-term items for extending deterministic enforcement to skill execution and new script validation

## [1.55.0] - 2026-04-04

- **Project→Backlog pipeline fix** — `type: project` memories with action items (待實施/下一步/需要解決) now trigger FRAMEWORK_GAP classification and flow into `polaris-backlog.md` at write time. Previously only `type: feedback` memories were classified, causing project-level improvements to become dead letters. Batch scan during memory hygiene also extended to cover project memories
- **`project-backlog-classification` mechanism** — new High-drift canary in mechanism-registry: project memory containing action items without corresponding backlog entry. Catches the gap that let VR improvements sit unactioned for a full day
- **VR reliability trio in backlog** — three items added: Mockoon fixture determinism (fix false positives), polaris-env.sh hardening (Redis/port/pnpm auto), VR strict judgment (zero-diff only when fixtures active)

## [1.54.0] - 2026-04-04

- **/next v1.1.0 — cross-session recovery** — Level -1 added before todo/git/JIRA checks: scans MEMORY.md for in-progress project memories, `.claude/checkpoints/` for recent checkpoints, and `wip/*` branches. Enables "推進手上的事情" to resume both ticket-based work and memory-based work (e.g., framework improvements, design discussions). Universal improvement — all users benefit, not just framework maintainers

## [1.53.0] - 2026-04-04

- **Epic three-layer verification reference doc** — `references/epic-verification-workflow.md`: Task test plans (PR gate records), per-AC verification tickets (Playwright E2E), Feature integration tests. Includes graduation criteria (2 Epic cycles), size threshold (>8pt → per-AC split), environment tagging (feature/stage/both), and skill integration map. Draft status — validate before graduating to skill changes
- **KKday JIRA conventions rule** — `.claude/rules/kkday/jira-conventions.md`: sub-tasks in KB2CW project (Task + parent link), ticket creation guidelines, happy flow verification requirement. First L2 company rule for kkday

## [1.52.0] - 2026-04-04

- **VR conditional trigger in quality gate** — `dev-quality-check` Step 8b: auto-detect frontend-visible changes (pages/, components/, layouts/, *.vue, *.css) and recommend VR when `visual_regression` is configured. Also triggers for member-ci and design-system changes that affect b2c rendering. Informational, not blocking
- **Epic verification backlog** — three-layer verification structure designed: Task test plans (PR gate records), per-AC verification tickets (Playwright E2E), Feature branch integration tests. Auto-rebase pre-step, auto-generated verification tickets, and feature integration testing planned for upcoming versions

## [1.51.0] - 2026-04-04

- **One-click environment — polaris-env.sh** — new `scripts/polaris-env.sh` with start/stop/status commands and three profiles: `--full` (Docker + dev servers), `--vr` (Mockoon + standalone dev server, skips Docker requires), `--e2e` (all layers). 4-layer architecture: infra → fixtures → dev servers → health verification. Idempotent (skips already-running services), PID tracking in `/tmp/polaris-env/`. VR SKILL.md Step 2 refactored from ~120 lines inline management to a single `polaris-env.sh --vr` call
- **Polaris naming update** — "About the name" section updated to reflect the original North Star concept (guiding users further than they imagined) rather than the interim Zhang Liang reference

## [1.50.0] - 2026-04-04

- **Session Start — Fast Check protocol** — every conversation begins with a lightweight WIP detection (`git status` + `stash list` + branch check). If uncommitted changes exist, reports to user and offers: continue WIP or branch-switch. Topic switches use `wip/{topic}` branches instead of stash (explicit, trackable, survives across sessions). Two new mechanism-registry canaries: `session-start-fast-check` and `wip-branch-before-topic-switch` — source: commit 混到 prevention

## [1.49.0] - 2026-04-04

- **Security hardening — skill-sanitizer + safety-gate expansion** — New `scripts/skill-sanitizer.py`: 5-layer pre-LLM security scanner (credentials, prompt injection/exfil/tamper, suspicious bash, context pollution, trust abuse) with code block context awareness and Unicode normalization. 15 built-in test vectors, `scan-memory` mode for memory file integrity checks. `safety-gate.sh` expanded from 5 to 11 patterns (added reverse shell ×3, pipe-to-shell ×2, crontab). Learning skill Step 1.1 pre-scans external repo SKILL.md files before exploration. Memory integrity guard in `feedback-and-memory.md`. Security section in mechanism-registry (3 canaries). README Security section with zero-telemetry policy. Inspired by [skill-sanitizer](https://github.com/cyberxuan-XBX/skill-sanitizer) — source: gstack telemetry incident response

## [1.48.0] - 2026-04-03

- **/init re-init mode** — existing users can run `/init` → "Re-init" to add only new sections (Step 9a Dev Environment, Step 9b Visual Regression) without re-running the full wizard. Scans existing config for missing fields and only runs the gaps. Recommended upgrade path from pre-v1.46.0
- **/init Step 9b-4 server config resolution** — critical fix from second simulation: when a project depends on an infrastructure repo (Docker stack), VR config now correctly inherits the infra repo's `start_command` and `base_url` instead of the app's standalone dev server. Presents A/B choice to user. Accuracy improved from ~30% to ~80% in simulation
- **/init Phase 3.5 locale expansion** — after confirming pages, asks whether to test additional locales beyond the primary

## [1.47.0] - 2026-04-03

- **/init Step 9a+9b friction fixes** — validated via worktree simulation against real kkday repos. Seven fixes: (1) cross-repo dependency detection scans Docker volume mounts and .env cross-references to surface prerequisites (2) SIT URL always asks user — `.env` contains dev URLs not SIT, auto-detection was wrong (3) production domain requires explicit user input — code only has dev/template URLs (4) dynamic routes prompt user for example IDs/slugs (5) missing `.env.example` warning when start script references `.env.local` (6) monorepo multi-app selection instead of assuming which app is primary (7) locale codes read from i18n config for correct case

## [1.46.0] - 2026-04-03

- **visual-regression before/after rewrite** — SKILL.md completely rewritten from baseline model to before/after comparison. Two modes: SIT (staging vs local dev) and Local (git stash before/after). Leverages Playwright's built-in `--update-snapshots` for temporary baselines — no files committed. Server startup uses health-check-first strategy (reuse running server, only start if needed)
- **Lib layering** — Playwright dependency moved from per-domain `package.json` to company VR level (`ai-config/{company}/visual-regression/package.json`), all domains share one installation. Domain directories contain only test files
- **Config cleanup** — removed obsolete `baseline_env` and `snapshot_dir` defaults from root workspace-config.yaml. VR config reference updated with before/after mode description, fixture server value proposition, and new directory structure
- **/init Step 9a + 9b** — new sections: Dev Environment (AI-detects start commands from docker-compose/package.json/Makefile/README, smartSelect presentation) and Visual Regression (domain mapping, key page discovery, SIT URL, test file generation). Populates `projects[].dev_environment` and `visual_regression.domains[]` in company config
- **workspace-config-reader** — added `dev_environment.*` and domain-level VR field index, removed stale project-level VR fields
- **skill-routing** — visual-regression triggers added to routing table
- **Mockoon fixture value** — feedback memory recording why fixture server matters (backend API changes during development cause false positives in screenshot comparison)

## [1.45.0] - 2026-04-03

- **intake-triage generalized** — promoted from kkday-specific (`skills/kkday/`) to shared skill (`skills/intake-triage/`). Domain lens now config-driven: reads `intake_triage.lenses` from workspace-config.yaml with built-in defaults as fallback. Author changed to Polaris. Skill count 39→40
- **docs-sync** — READMEs (EN+zh-TW) skill count updated, chinese-triggers.md entry added, workflow-guide mermaid diagrams updated with intake-triage node

## [1.44.0] - 2026-04-03

- **intake-triage skill** — new kkday-specific skill for batch ticket prioritization from PM. Analyzes tickets across 5 dimensions (Readiness, Effort, Impact, Dependencies, Duplicate Risk) with theme-aware domain lenses (SEO/CWV/a11y/generic). Produces a prioritized verdict table (Do First/Do Soon/Do Later/Skip/Hard Block) with Do First capped at 3, writes JIRA labels + analysis comments, and sends PM-facing Slack summary in non-technical language. Epic + subtask auto-convergence: when both appear in a batch, Epic becomes a summary header while subtasks are individually scored. Tested on 44 real tickets. Execution Queue deferred to Phase B (backlog) with 4 explicit trigger conditions
- **skill-routing update** — intake-triage added to routing table, "排優先" trigger disambiguated from my-triage (requires multiple ticket keys)

## [1.43.0] - 2026-04-03

- **Hotfix auto-ticket creation** — two-layer mechanism for hotfix scenarios where no JIRA ticket exists: (1) Strategist pre-processing route: fix intent + Slack URL + no JIRA key → read Slack thread → auto-create Bug ticket → route to `fix-bug` with new ticket key (2) git-pr-workflow Step 6.0 safety net: if changeset step detects no JIRA key in branch/commits → auto-create ticket, update PR title and changeset. Prevents CI failures from missing JIRA key in changeset/PR title. Mechanism registry entry `hotfix-auto-ticket` added for post-task audit

## [1.42.0] - 2026-04-03

- **Language preference** — `/init` Step 0a now asks the user's preferred language (zh-TW, en, ja, etc.) and writes it to root `workspace-config.yaml`. The Strategist reads this field at conversation start and responds in that language. Template config updated with a NOTE clarifying that `language` belongs in root config, not company config

## [1.41.0] - 2026-04-03

- **Learning from tvytlx/ai-agent-deep-dive** — deep-dive into reverse-engineered Claude Code architecture specs (16 docs). Three actionable items applied: (1) `verify-completion` verification sub-agents now default to read-only — cannot modify project files to make verification pass (verifier ≠ fixer), with explicit exception for auto-fix items (2) `sub-agent-delegation.md` adds worktree path translation rule — dispatch prompts must declare the worktree working directory to prevent sub-agents from reading/writing the wrong workspace (3) `e2e-verify.spec.ts` adds adversarial probe mode (`E2E_ADVERSARIAL=1`) with 4 boundary tests: nonexistent product, invalid locale, missing ID, nonexistent category — checks no 5xx, no uncaught JS, non-blank page. Three items deferred to backlog: compact auto-checkpoint, per-agent isolation config, read-only isolation mode

## [1.40.0] - 2026-04-03

- **Sub-agent role system rewrite** — `sub-agent-roles.md` restructured from 11-role registry to dispatch patterns reference. Audit found only 4/11 roles were correctly cited by skills — generic roles (Explorer, Implementer, Analyst, Validator, Scribe) removed as named roles, replaced with copy-paste prompt patterns. Three specialized protocols retained with canonical definitions: QA Challenger/Resolver (multi-round challenge loop), Architect Challenger (estimation review), Critic (pre-PR review with JSON return). Mandatory standards (Completion Envelope, Model Tier Selection, Context Isolation) elevated to top of file. Converge routing table fixed: removed role name labels, replaced with dispatch pattern descriptions, corrected VERIFICATION_PENDING (was mislabeled QA Challenger → now Verification) and REVIEW_STUCK (was mislabeled Scribe/haiku → now sonnet). Based on cross-framework research (OpenAI Swarm, CrewAI, LangGraph, Claude Agent SDK, AutoGen, gstack, GSD) — no production framework uses a dynamic role registry; all define roles inline per-dispatch

## [1.39.0] - 2026-04-03

- **Mockoon CLI runner** — new `scripts/mockoon/` module with `mockoon-runner.sh` supporting start/stop/status, proxy mode (passthrough to SIT) and mock mode (canned responses for E2E). Reads environment JSON files from any directory (framework-agnostic, company provides the data)
- **Unified dependency installer** — `scripts/install-deps.sh` installs all framework tools (Playwright, Mockoon CLI, Chromium browser) with `--check` mode for status reporting. Called by `/init` Step 13.5 and usable after `sync-from-polaris.sh` upgrades
- **E2E Mockoon pre-flight** — `e2e-verify.sh` now detects Mockoon proxy status before running tests, warns when using live backend (results may vary vs stable fixtures)
- **`/init` Step 13.5** — auto-installs framework dependencies during workspace setup

## [1.38.0] - 2026-04-03

- **E2E browser verification via Playwright** — new `scripts/e2e/` module (framework-level, not installed in product repos) with Playwright config, generic page health check spec, and wrapper shell script. Checks 6 dimensions: HTTP status, blank page, hydration errors, uncaught JS errors, critical elements, error page indicators. Supports page type inference from git diff (product/category/destination/home). `verify-completion` v1.6.0 adds Step 1.7 "E2E Browser Verification" — runs through `https://dev.kkday.com` (Docker nginx proxy), gracefully skips if dev server is not running, blocks on hydration/JS/render failures. Screenshots saved for reports

## [1.37.0] - 2026-04-03

- **`converge` skill v1.0.0** — batch convergence orchestrator that scans all assigned work, classifies 14 gap types (NO_ESTIMATE → MERGE_CONFLICT), proposes a 4-layer prioritized plan (quick wins → implementation → planning → waiting), and auto-routes to 10 downstream skills after user confirmation. Absorbs epic-status as Epic-only alias. 4-phase design: scan → propose → execute → rescan with before/after report
- **`settings.local.json.example` rewrite** — both project-level and user-level examples now include `_doc` blocks explaining the 3-layer permission model, pattern syntax, and recommended split between user-level vs project-level settings. Copied to `_template/` for `/init` reference
- **Pre-commit scope header validation** — `scripts/check-scope-headers.sh` validates that company rule files under `.claude/rules/{company}/` include a `Scope:` header. Supports `--staged` mode for git pre-commit hook and full-scan mode. Wired into `.git/hooks/pre-commit`
- **Cross-session knowledge system validated** — first real usage of `polaris-learnings.sh` (add + query) and `polaris-timeline.sh` (append + query), confirming both scripts work end-to-end with `~/.polaris/projects/work/` storage

## [1.36.0] - 2026-04-02

- **Cross-session knowledge system (Wave 2)** — new `~/.polaris/projects/$SLUG/` infrastructure for persistent cross-session data. Three components: (1) **learnings.jsonl** — typed knowledge entries (pattern/pitfall/preference/architecture/tool) with confidence 1-10, time-based decay (1pt/30d), key+type dedup on write, and preamble injection of top 5 entries at conversation start. Shell script `polaris-learnings.sh` handles add/query/confirm/list with jq (2) **timeline.jsonl** — append-only session event log (10 event types: skill_invoked, pr_opened, commit, checkpoint, etc.) for accurate standup reports and session recovery. Shell script `polaris-timeline.sh` handles append/query/checkpoints with --since filtering (today/Nh/Nd/date) (3) **`/checkpoint` skill** — save/resume/list session state. Captures branch, ticket, todo, recent timeline into a checkpoint event; resume parses and restores context. Integration: `feedback-and-memory.md` item 7 (learning write on non-obvious technical insights), `CLAUDE.md` preamble injection + context recovery step 4, `mechanism-registry.md` 3 new mechanisms, `skill-routing.md` checkpoint route

## [1.35.1] - 2026-04-02

- **fix-pr-review changeset self-check** — fixed timing gap where Step 3b removed inherited changesets but Step 6g only created a new one when changeset-bot warned (bot checked pre-cleanup state, so no warning was issued). Two fixes: (1) Step 3b now self-checks after cleanup — if no changeset with the PR's ticket key remains, creates one immediately (2) Step 6g detection changed from bot-warning-only to diff-scan-first (check `git diff` for missing changeset) with bot warning as fallback

## [1.35.0] - 2026-04-02

- **Learning v3.0 — discovery-first exploration** — fundamental shift from gap-directed to discovery-first approach. Step 1.5 gap pre-scan renamed to "Baseline Scan" — still runs but no longer filters exploration. Steps 2-3 research phase explores broadly without preconceptions, using novelty and unknown signals to drive selective deep-dives instead of known gaps. Deep mode Round 2 dispatches Researchers by "what's different" and "what concept we don't have" rather than lens list gaps. Round 3 compares findings against baseline with 4-type classification: confirms (known gap), new (unknown unknown), refines (our approach but more mature), skip (not applicable). Step 4 synthesis matrix highlights new discoveries first. Works for both framework and product project targets — same principle, different comparison anchors

## [1.34.0] - 2026-04-02

- **Shared references + review-lessons pipeline** — (1) New `references/github-slack-user-mapping.md` — 4-step lookup chain (context match → search username → gh API real name → plaintext fallback), replaces inline logic in review-inbox, review-pr, fix-pr-review (2) New `references/slack-message-format.md` — URL linebreak rule, mrkdwn vs GitHub MD differences, message length limits (3) `standup` adds post-standup review-lessons graduation gate — counts entries across repos, suggests graduation when >= 15 (4) `next` Level 4 adds review-lessons check when no active work context

## [1.33.0] - 2026-04-02

- **Quality pipeline hardening (5 fixes from feedback graduation)** — (1) `feature-branch-pr-gate` now runs `dev-quality-check` before creating feature PR — catches broken merges before CI (2) `dev-quality-check` adds coverage tool pre-flight check (`require.resolve`) instead of reactive error-driven install (3) `git-pr-workflow` Step 6.5 re-runs changeset hygiene after rebase; `fix-pr-review` adds proactive Step 3b changeset cleanup after rebase (not just reactive to changeset-bot) (4) Cascade rebase logic extracted to shared `references/cascade-rebase.md` with documented edge cases and fallback; `git-pr-workflow` and `fix-pr-review` now reference instead of inline (5) `work-on` batch mode validates sub-agent results include PR URL — flags completions without PR as incomplete

## [1.32.0] - 2026-04-02

- **Comprehensive rebase coverage across PR lifecycle** — three gaps closed: (1) `git-pr-workflow` v3.4.0 adds **Step 6.5 Rebase to Latest Base** — explicit rebase after commit/changeset and before opening PR, with cascade rebase for feature branch workflows and automatic conflict handling (2) `feature-branch-pr-gate` adds **Sibling Cascade Rebase** — when any task PR merges, all remaining open sibling task PRs are automatically rebased onto the updated feature branch, keeping diffs clean for reviewers (3) `feature-branch-pr-gate` adds **Feature Branch Rebase** — before creating the feature→develop PR, rebase the feature branch onto latest develop to ensure a clean diff. Together with existing coverage in `check-pr-approvals` (batch rebase) and `fix-pr-review` (pre-fix rebase), all PR states now have automatic rebase handling

## [1.31.1] - 2026-04-02

- **Auto-release on sync** — `sync-to-polaris.sh` now creates a GitHub Release (with CHANGELOG notes) automatically when pushing a new tag. Backfilled 27 missing releases (v1.11.0–v1.31.0) from CHANGELOG entries

## [1.31.0] - 2026-04-02

- **Learning v2.0 — gap-driven deep exploration with dual target** — External mode rewritten with three core improvements: (1) **Gap pre-scan** (Step 1.5) — scans backlog, mechanism-registry, and feedback memories before exploring, so research is directed at known problems (2) **Depth tiers** — Quick/Standard/Deep with auto-escalation for repos with `.claude/` directories; Deep mode uses 3-round multi-agent exploration (structure → targeted deep-dive → cross-reference) (3) **Dual target** — learnings can land in framework (`rules/`, `skills/`, `polaris-backlog.md`) OR product projects (project code, project rules, project CLAUDE.md), with target-specific gap sources and extraction categories. New triggers: "深入學", "deep dive", "像 gstack 那樣學"

## [1.30.0] - 2026-04-02

- **Sub-agent safety & resilience from gstack learning** — three new mechanisms in `sub-agent-delegation.md`: (1) **Safety hooks** — `scripts/safety-gate.sh` PreToolUse hook blocks Edit/Write outside allowed dirs + dangerous Bash patterns (rm -rf, force-push main, DROP TABLE). Configurable via `POLARIS_SAFE_DIRS` env var (2) **Self-regulation scoring** — sub-agents accumulate risk score per modification (+5-15% per event), hard-stop at >35% and report back to Strategist (3) **Pipeline restore points** — `git stash` before implementation in long-running skills (work-on, fix-bug, git-pr-workflow), auto-restore on failure or self-regulation stop

## [1.29.1] - 2026-04-02

- **Quality enforcement from gstack learning** — three mechanisms landed: (1) Re-test-after-fix rule in `git-pr-workflow` Step 3 — stale test results after code fix are invalid, must re-run (2) Verification Iron Rule in `verify-completion` — no completion claims without fresh verification + 5 named anti-rationalization patterns as canaries (3) Decision Classification framework in `sub-agent-delegation` — T1 mechanical / T2 taste / T3 user-challenge with escalation bias toward T2. All three registered in `mechanism-registry.md` Quality Gates section

## [1.29.0] - 2026-04-02

- **Standup unified entry point (v2.0)** — `/standup` is now the single entry point for all end-of-day and standup workflows. New Step 0 auto-triage guard checks `.daily-triage.json` freshness and runs `/my-triage` automatically when stale or missing. All end-of-day triggers ("下班", "收工", "EOD", "wrap up", etc.) now route to standup. `/end-of-day` deprecated to a redirect stub. Routing table consolidated from two rows to one

## [1.28.1] - 2026-04-02

- **Quick-fix batch: 4 backlog items** — `/init` Step 1 ASCII company name validation (reject CJK directory names). `wt-parallel` priority flipped to prefer builtin `isolation: "worktree"` over `wt` CLI. MEMORY.md integrity check added to memory hygiene rules. Scheduled agents / remote triggers documented in README architecture section (EN + zh-TW)

## [1.28.0] - 2026-04-02

- **`/init` v3.1 — 7 gap fixes from live validation** — JIRA smartSelect adds Description column + ticket prefix verification to prevent key confusion (GROW vs GT). Confluence Step 4 now uses CQL auto-detection for SA/SD folders, Standup/Release parent pages, and prompts for additional spaces. Projects Step 7 adds local repo reverse scan (cross-references `gh repo list` with `{base_dir}/` directories, surfaces `[local only]` repos). New Step 10a offers to clone missing repos after config write. Step 10 ensures `default_company` goes to root config only. Step 14 lists all deferred empty fields with fill-in guidance

## [1.27.0] - 2026-04-01

- **Cascade rebase for feature branch workflows** — `rebase-pr-branch.sh` now detects when a task PR's base is a feature branch (not develop/main/master), automatically rebases the feature branch onto its upstream first, then rebases the task branch. Eliminates diff bloat where task PRs show 40+ unrelated files from develop. Requires `ORG` env var. Updated in `check-pr-approvals` Step 2 and `fix-pr-review` Step 3
- **Changeset cleanup for inherited changesets** — `fix-pr-review` Step 6g-2 and `git-pr-workflow` Step 6 now scan for changesets that don't belong to the current PR's ticket key (inherited from dependency branches) and remove them. Ensures each PR has exactly one changeset matching its own ticket

## [1.26.0] - 2026-03-31

- **`learning` Batch mode (5th mode)** — new `/batch learn` flow that scans a repo's merged-PR history, skips already-extracted PRs (Layer 1 dedup by Source URL), batch-extracts review-lessons from the rest, and auto-triggers graduation with Step 2.5 semantic grouping. Triggers: "掃 review", "batch learn", "批次學習", "掃歷史 PR", "補齊 review lessons". Defaults to 3 months, cap 30 PRs/repo
- **Skill routing: batch learn** — learning skill description updated to include Batch mode triggers, no separate route needed (internal mode detection handles it)

## [1.25.1] - 2026-03-31

- **Review-lessons semantic grouping (Step 2.5)** — `review-lessons-graduation` now runs a semantic similarity pass before classification. Entries describing the same underlying coding pattern (even with different wording across PRs) are merged, combining their Source PRs. This unblocks graduation for patterns that were previously stuck at Source=1 per entry despite being validated by multiple PRs
- **Skill routing Anti-Pattern #5** — graduated feedback: fixing PR review comments must use `fix-pr-review` skill, not manual edits. Manual fixes skip comment replies, quality checks, and lesson extraction, breaking the learning pipeline
- **Backlog: review-lessons pipeline gaps** — 4 structural improvements tracked: semantic consolidation (done), periodic graduation trigger outside review skills, retroactive extraction for manually-fixed PRs, cross-pipeline dedup (review-lessons ↔ feedback memories)

## [1.25.0] - 2026-03-31

- **`my-epics` → `my-triage` rename + scope expansion** — skill now scans Epics, Bugs, and orphan Tasks/Stories (no parent). Bug group always displayed first in dashboard. JQL expanded with `issuetype` filter + `parent` post-filter. Step 5+6 merged to prevent triage state write being skipped on conversation interruption
- **`.epic-triage.json` → `.daily-triage.json`** — triage state file renamed, JSON schema updated (`epics` → `items`, added `type` field per item). Standup skill references updated accordingly
- **`/end-of-day` orchestrator skill** — new skill chains `/my-triage` → `/standup` in sequence. Triggers: "下班", "收工", "準備明天的工作", "EOD". Ensures triage state exists before standup TDT generation
- **Routing table updated** — `my-epics` → `my-triage`, added `end-of-day` route

## [1.24.0] - 2026-03-31

- **`get-pr-status.sh` shared script** — new `references/scripts/get-pr-status.sh` provides comprehensive single-PR status checking: CI status, review counts (deduplicated per reviewer), thread-based unresolved inline comment detection, mergeable state, and optional stale approval detection (`--include-stale`). Replaces inline `gh api` calls with consistent thread-aware comment analysis
- **`epic-status` v1.4.0** — Step 4 now delegates per-child-ticket PR status to `get-pr-status.sh` instead of inline `gh pr list` + `gh api .../comments`. Gains thread-based unresolved detection (previously only counted total comments) and reviewer deduplication
- **Backlog cleanup** — closed 2 invalid High items (`review-pr` Slack notification path was misdirected, changeset check belongs in project rules not generic skill). Split `get-pr-status.sh` Phase 2 migration into separate tracked item

## [1.23.1] - 2026-03-31

- **Workflow-guide mermaid diagrams updated** — removed deleted `sasd-review` from both diagrams; added `next`, `my-epics`, `epic-status`, `docs-sync`, `worklog-report` to Skill Orchestration diagram with proper edges (next→orchestrators, epic-status→gap routing, standup↔my-epics). Both EN and zh-TW files synced
- **docs-sync now covers mermaid diagrams** — Step 1 scans mermaid node IDs against skill catalog to detect drift; Step 2c includes explicit mermaid diagram update guidance (nodes, edges, class assignments, connectivity check prose)

## [1.23.0] - 2026-03-31

- **`/my-epics` triage skill** — new skill for personal Epic backlog triage. Queries JIRA for all assigned active Epics, validates actual status (catches board/status desync), sorts by priority + created date, checks GitHub PR progress for In Development items, and outputs a prioritized dashboard. Writes `.epic-triage.json` state file for standup integration
- **Standup TDT triage integration** — standup's TDT section now reads `.epic-triage.json` when available, sorting today's tasks by triage rank and showing progress traffic lights (🟢 ahead / ⚪ normal / 🔴 stuck) by comparing triage-time progress vs current state

## [1.22.2] - 2026-03-31

- **`/next` auto-continuation skill** — zero-input context router that reads todo list, git branch, git status, JIRA ticket state, and GitHub PR status to auto-determine the correct next action. 4-level decision tree (todo → git branch → JIRA status → PR status) with direct routing to existing skills. Trigger: "下一步", "next", "繼續", "continue"
- **work-on trigger cleanup** — removed "下一步" and "繼續" from work-on triggers (now handled by `/next`), added key distinction note

## [1.22.1] - 2026-03-31

- **`check-feature-pr.sh` shared script** — new `references/scripts/check-feature-pr.sh` consolidates feature PR status checking (task PR merge count, feature PR existence, review/CI/conflict status) into a single script. `feature-branch-pr-gate.md` Steps 2-4 and `epic-status` Step 3b now delegate to this script instead of inline gh commands
- **`references/scripts/` directory** — established shared scripts directory for cross-skill deterministic logic

## [1.22.0] - 2026-03-31

- **Skill logic consolidation** — extracted 7 shared reference docs from duplicated logic across 12 skills: `slack-pr-input.md` (Slack URL → PR URL parsing), `pr-input-resolver.md` (PR URL/number + local path resolution), `jira-story-points.md` (Story Points field ID query + write-back verification), `jira-subtask-creation.md` (batch create + estimate loop), `stale-approval-detection.md` (stale approval rule), `tdd-smart-judgment.md` (TDD file-level decision), `confluence-page-update.md` (search → version check → append flow)
- **Inline deduplication** — `feature-branch-pr-gate.md` inline copies in check-pr-approvals and git-pr-workflow replaced with reference pointers. sub-agent-roles Critic spec in git-pr-workflow annotated with cross-reference
- **epic-status v1.1.0** — Phase 1 now scans feature PR review/CI status (Step 3b) and detects unresolved inline comments (Step 4a-2, catches Copilot review and COMMENTED-state reviews). Phase 2 auto-routes gaps without user confirmation
- **Cleanup** — removed deprecated `kkday/ai-env.sh` (replaced by polaris-sync.sh)

## [1.21.0] - 2026-03-31

- **`epic-status` skill** — new skill for Epic progress tracking and gap closing. Phase 1 scans all child tickets' JIRA + GitHub status (branch/PR/CI/review) into a status matrix with completion percentages. Phase 2 routes gaps to existing skills (work-on, fix-pr-review, check-pr-approvals, verify-completion) with user confirmation
- **Feature Branch PR Gate** — new cross-cutting mechanism (`references/feature-branch-pr-gate.md`) that auto-creates feature branch → develop PRs when all task PRs are merged. Integrated into `epic-status`, `git-pr-workflow`, and `check-pr-approvals` — "discover it's ready, create it" philosophy instead of manual tracking
- **Slack channel routing** — epic-status and other skills now read `slack.channels.pr_review` for team-facing messages (review requests, PR updates) vs `slack.channels.ai_notifications` for self-only notifications. Prevents misdirected review requests
- **Skill routing update** — added epic-status triggers ("epic 進度", "離 merge 還多遠", "還差什麼", "補全")

## [1.20.0] - 2026-03-31

- **Sub-agent Completion Envelope** — all sub-agent roles now require a standard 3-line return header (`Status / Artifacts / Summary`) so orchestrators can programmatically determine success/failure without parsing prose. Added to `sub-agent-roles.md` and tracked in mechanism registry
- **Complexity Tier routing** — new section in `skill-routing.md` defines Fast / Standard / Full tiers based on task size. Prevents small tasks from incurring full-workflow overhead and large tasks from skipping planning
- **Goal-Backward Verification** — new Step 1.6 in `verify-completion` checks 4 layers (Exists → Substantive → Wired → Flowing) before running detailed test items. Catches "all tasks done but goal not met" situations like created-but-never-imported components
- **Runtime Context Awareness** — new §5 in `context-monitoring.md` with proactive 20-tool-call checkpoint and interim mitigation for context rot in long sessions. Hook-based runtime monitoring tracked in backlog
- **Mechanism registry updates** — added `subagent-completion-envelope` (Medium) and `proactive-context-check-at-20` (Medium) canary signals
- **Backlog: 3 future items** — context monitor PostToolUse hook, `/next` auto-continuation skill, wave-based parallel execution for large epics

> Inspired by [gsd-build/get-shit-done](https://github.com/gsd-build/get-shit-done) — context engineering patterns, goal-backward verification, and scale laddering concepts adapted for Polaris

## [1.19.0] - 2026-03-31

- **Bilingual docs (zh-TW)** — full Traditional Chinese README (`README.zh-TW.md`), workflow guide, and PM setup checklist. All docs have `English | 中文` language switcher at top
- **Daily learning scanner → Slack delivery** — scanner now sends article recommendations to Slack instead of committing to git. Eliminates git history pollution from transient queue data
- **Learning Setup mode** — new `/learning setup` (or `設定學習`) configures the daily scanner: auto-detects tech stack and repos from workspace config, asks for Slack channel and custom topics, assembles and creates RemoteTrigger. `/init` Step 13 delegates to this mode
- **`daily-learning-scan-spec.md` cleaned** — now a pure framework template (no instance-specific tech stack, repos, or channel IDs). All instance data lives in the trigger prompt, assembled by Setup mode
- **`docs-sync` skill** — generic version that detects skill/workflow changes and updates all bilingual documentation files (README, workflow-guide, chinese-triggers, quick-start). Replaces the old company-specific Confluence sync
- **Sync script updates** — `sync-to-polaris.sh` now syncs `docs/` directory and `README.zh-TW.md` to the template repo

## [1.18.0] - 2026-03-30

- **Three Pillars documentation rewrite** — restructured README and docs around three narrative pillars: Development Assistance (輔助開發), Self-Learning (自我學習), and Daily Operations (日常紀錄). Replaces the old skill-category table and moves self-evolution into Pillar 2 as the framework differentiator
- **Quick Start simplification** — merged 4 setup steps into 3, added post-`/init` folder structure example so new users see what they'll get before starting. Based on real user feedback about unclear workspace concept
- **Chinese docs sync** — `quick-start-zh.md` mirrors the three-pillar structure and simplified setup flow
- **Pillar tags in chinese-triggers.md** — each skill category header now shows which pillar it belongs to

## [1.17.0] - 2026-03-30

- **`/init` Step 13: Daily Learning Scanner** — new opt-in step at end of init wizard. Explains article selection logic (tech stack from Step 7 + AI/Agent news + architecture), lets user customize preferences (add topics, adjust volume), and auto-creates RemoteTrigger schedule if accepted. Users who decline can enable later via `/schedule`

## [1.16.0] - 2026-03-30

- **Feedback pre-write dedup** — before creating a feedback memory, scan existing entries for semantic overlap; merge if found (incrementing `trigger_count`) instead of creating duplicates. Post-merge check triggers graduation immediately if `trigger_count >= 3`
- **Dual-layer review-lesson dedup** — `review-pr` and `fix-pr-review` lesson extraction now checks both existing review-lessons AND main `rules/*.md` before writing, matching the dedup quality of `learning/PR` mode
- **Framework-level lesson tagging** — lesson extraction tags entries with `[framework]` when the pattern is about skill design, delegation, rules mechanisms, or memory management (not project coding patterns)
- **Review-lessons-graduation framework routing** — new § 3.5 routes `[framework]`-tagged lessons to workspace `rules/` instead of project `rules/`, closing the gap where framework-level learnings from code review had no path to framework rules
- **Mechanism registry** — added `feedback-pre-write-dedup` (High) to enforce dedup before feedback creation

## [1.15.0] - 2026-03-30

- **Framework Self-Iteration rule** — new `rules/framework-iteration.md` formalizing three iteration cadences (Micro/Meso/Macro), repositioning Challenger Audit as a milestone-only self-check (pre-release, not daily), and adding Framework Experience collection for positive signals
- **Framework Experience collection** — new `type: framework-experience` memory type captures what works (not just pain points): validated skill flows, successful graduations, cross-company pattern reuse. At most 1 per task, no graduation — observations, not corrections
- **Validated Pattern Promotion** — when >= 3 framework-experience memories describe the same pattern, surface as a candidate for rule rationale during organize-memory
- **Version Bump Reminder** — post-task reflection now reminds the user to consider a version bump when `rules/` or `skills/` files were modified
- **Mechanism registry expanded** — added `challenger-milestone-only` (High) and `framework-exp-once-per-task` (Low) to prevent Challenger overuse and memory pollution

## [1.14.0] - 2026-03-30

- **Challenger personas for daily workflows** — two new must-respond challenger sub-agents that review quality before user confirmation:
  - **🏛️ Architect Challenger** — challenges estimation results (complexity gaps, blind spots, scope misses) in `jira-estimation` Step 8.4a
  - **🔍 QA Challenger** — challenges test plans (missing negative cases, regression risks, boundary conditions) in `work-on` Step 5f
- **Must-respond protocol** — challenger findings are not advisory; every ⚠️ must be explicitly accepted or rejected (with reason) before proceeding
- Persona definitions added to `skills/references/sub-agent-roles.md`

## [1.13.0] - 2026-03-30

- **`/validate-mechanisms` skill** — Layer 3 of mechanism protection: periodic smoke test scanning 9 static canary signals (scope headers, bash patterns, routing table completeness, memory isolation, feedback frontmatter, hardcoded paths, ghost references)
- **Chinese trigger reference** — new `docs/chinese-triggers.md` with all skills grouped by category, Chinese/English trigger phrases, and disambiguation guides
- **L3 project CLAUDE.md template** — new `_template/project-claude-md.example` showing what belongs at project level (tech stack, conventions, testing, dev commands)
- **Default company config** — `default_company` field in workspace-config.yaml for single-client fallback; integrated into `use-company` skill and `multi-company-isolation` rule
- **Routing table updated** — added `validate-mechanisms` and `validate-isolation` to skill-routing.md

## [1.12.0] - 2026-03-30

- **Developer Workflow Guide** — new `docs/workflow-guide.md` extracted from company-specific RD workflow into a generic framework reference. Covers: ticket lifecycle (mermaid), AC closure gates, skill orchestration graph, Feature/Bug/Hotfix paths, code review pipeline, and continuous learning
- **README: Workflow orchestration section** — added link to workflow guide under "How it works"
- **sync-to-polaris.sh** — automated instance → template sync with `--push` flag (GitHub account switch for dual-account setups)

## [1.11.0] - 2026-03-30

**Drift Audit & Mechanism Registry** — stability pass after rapid v1.7–v1.10 iteration

- **Mechanism Registry** — new `rules/mechanism-registry.md` with 20 behavioral mechanisms, canary signals, and drift-risk ratings; post-task audit section added to `feedback-and-memory.md` for automatic compliance checks
- **Drift Audit fixes (Critical)** — removed phantom `dev-guide` skill references (4 files), fixed CLAUDE.md routing path (`rules/{company}/` → `rules/`), fixed graduation table paths in feedback-and-memory.md, added missing `name:` to use-company frontmatter
- **Skill genericization pass 2** — replaced `~/work/` hardcodes with `{base_dir}` across 16 skill files (65 occurrences); removed company-specific refs (b2c-web, member-ci, GT-XXX, KQT-14407) from 5 generic skills
- **Memory hygiene** — added `company: kkday` tag to 19 company-scoped memories; deleted 3 redundant/graduated memories; fixed stale content in 4 memories (Commander→Strategist, wrong paths)
- **CLAUDE.md Cross-Project Rules** — separated universal rules from company-specific rules set up via `/init`
- **sub-agent-delegation.md** — removed hardcoded "(Opus)" model assumption

## [1.10.0] - 2026-03-30

- **Skill description trim** — top 6 bloated skills (learning, refinement, review-inbox, fix-pr-review, work-on, check-pr-approvals) reduced from avg ~1300 to ~400 chars, saving ~4k tokens per conversation
- **fix-pr-review routing fix** — added colloquial Chinese triggers: "修 PR", "PR 有 review", "處理 review" so natural-language requests route correctly
- **kkday workspace-config** — added `bug_value`/`maintain_value` aliases under `requirement_source` for generic skill compatibility

## [1.9.2] - 2026-03-30

- **Hook matcher simplified** — uses Claude Code's `if: "Bash(git push*)"` field instead of firing on every Bash call + grep short-circuit; removes outdated "no command-level matchers" comment
- **PM Setup Checklist** — new `docs/pm-setup-checklist.md` with zero-terminal-commands handoff: what PMs need, what to ask their developer, daily commands, troubleshooting

## [1.9.1] - 2026-03-30

Challenger audit v1.9.0 quick-fixes (6-persona, 16 🔴 / 37 🟡 / 18 🟢):

- **Removed leaked company name** from `.gitignore` — `kkday/` replaced with generic comment
- **Chinese guide link at README top** — visible in first 5 lines, not buried in Quick Start
- **Multi-company in "Who is this for"** — freelancers/multi-client listed as a target audience
- **`/commands` note moved to Step 3** — before `/init`, not after Step 4
- **Post-/init validation step** — "try `work on PROJ-123` to verify setup" added to Quick Start
- **PM section: removed PR tracking** — dev-only operation removed from PM workflow
- **PM section: Max plan requirement** — cost callout added at top of PM workflow
- **PM section: troubleshooting tip** — "check MCP connections" one-liner added
- **YDY/TDT/BOS expanded** — acronym explained on first use in both README and Chinese guide
- **Refinement description clarified** — "Polaris reads codebase for you" note for PM users
- **Chinese guide end note** — links to English README for developer content
- **`/validate-isolation` in README** — linked in multi-company diagnostics list and post-setup guidance
- **Same-prefix resolution** — documented in multi-company-isolation.md routing rules
- **Company recovery prompt** — specific prompt format for post-compression company re-confirmation
- **13 new backlog items** from v1.9.0 audit findings (skill genericization, hook matcher, PM setup, etc.)

## [1.9.0] - 2026-03-30

- **Chinese Quick Start guide** — full `docs/quick-start-zh.md` covering prerequisites, setup steps, skill examples, and PM workflow in 中文; linked from README Quick Start section
- **PM & Scrum workflow narrative** — new README section mapping the complete sprint lifecycle to Polaris commands: sprint planning → standup → refinement → breakdown → worklog report, with bilingual trigger phrases and expected outputs

## [1.8.0] - 2026-03-30

- **Memory isolation enforcement** — hard-skip rule for mismatched `company:` field (skip silently, no cross-contamination), new hygiene check #6 for untagged company-specific memories, MEMORY.md index now supports `[company]` prefix for visual scanning
- **Company context persistence** — active company context now survives context compression: saved in milestone summaries, restored from todo list, explicit re-confirmation after compression events
- **`/validate-isolation` diagnostic skill** — scans L2 rules for missing scope headers, memory files for missing `company:` fields, cross-company directive conflicts, and MEMORY.md index format issues; outputs structured report with ✅/🟡/🔴 severity
- **Cross-reference in multi-company-isolation.md** — `/validate-isolation` now documented as the recommended diagnostic tool

## [1.7.0] - 2026-03-30

- **Memory company isolation** — memories now support `company:` frontmatter field to prevent cross-company rule bleed
- **`/init` scaffolds L2 rules** — new companies automatically get `.claude/rules/{company}/` with scoped copies of rule templates
- **`/use-company` skill** — explicitly set active company context for a conversation, complementing `/which-company` diagnostics
- **`/init` repo path flexibility** — no longer assumes `~/work/` as base dir; uses actual workspace root path
- **README bilingual integration** — Quick Start examples now show English/中文 side-by-side instead of separate blocks
- **CJK branch naming guard** — empty or invalid translations from CJK titles fall back to ticket key only (`task/PROJ-123`)
- **SA/SD Chinese alias update** — added 「寫 SA」「出 SA/SD」triggers, deprioritized misleading 「實作評估」
- **Stale backlog cleanup** — `review-pr` hardcoded paths already resolved in earlier genericization; item closed

## [1.6.0] - 2026-03-30

- **Excluded `polaris-backlog.md` from template** — framework backlog is maintainer-only, no longer confuses new users
- **Added "What not to touch" guide** in README — clarifies which files are framework internals vs. safe to customize
- **Added "Upgrading" section** in README — documents `sync-from-polaris.sh` for pulling framework updates
- **Moved Zhang Liang inspiration** to "About the name" section — frees hero section for practical info
- **Added Claude Code plan/tier note** — specifies that sub-agent features need Max plan or API access
- **Added clone path guidance** — warns against `~/work` default to avoid conflicts
- **Pre-push hook first-time bypass** — first push skips the quality gate with an informational message instead of blocking
- **CHANGELOG rewritten** — user-facing release notes style, concise per-version summaries
- **Sync script fixed** — L2 rules now sync from `_template/rule-examples/` (v1.5.0+ path)
- **Removed obsolete skills** (`auto-improve`, `check-pr-approvals`, `dev-guide`)
- **Removed `ONBOARDING.md`** — was already absorbed into README in v1.1.0

## [1.5.0] - 2026-03-30

- Added "What is Claude Code?" explainer for users new to the tool
- Added MCP install instructions with concrete `claude mcp add` example
- Added PM/Scrum workflow showcase (`standup`, `sprint-planning`)
- Added "Start here" role-based table pointing each role to their first command
- Added full bilingual skill routing (English + 中文)
- Moved rule examples from `.claude/rules/_example/` to `_template/rule-examples/` — no longer auto-loaded

## [1.4.0] - 2026-03-30

- Added multi-company isolation with scoped rules and `/which-company` diagnostic
- Added "Who is this for?" section and tiered prerequisites (Everyone / Dev / Optional)
- Added Chinese Quick Start examples (「做 PROJ-123」「修 bug」「估點」)
- Workspace config (`workspace-config.yaml`) is now gitignored — copy from template

## [1.3.0] - 2026-03-30

- All skills and rules genericized — no company-specific hardcodes remain
- L2 example rules translated to English
- Template ready for public distribution

## [1.2.0] - 2026-03-30

- Skill routing rewritten English-first with Chinese aliases
- Company-specific JIRA field IDs, URLs, and credentials removed from rules
- 12 skill trigger phrases updated

## [1.1.0] - 2026-03-30

- README rewritten: clear positioning, prerequisites, Quick Start walkthrough
- ONBOARDING.md absorbed into README (single entry point)
- MCP server dependencies documented

## [1.0.0] - 2026-03-30

- Identity established: Polaris, inspired by Zhang Liang (張良)
- Persona: Commander to Strategist — "listen first, then orchestrate"

## [0.9.0] - 2026-03-29

- `/init` v3: smartSelect interaction, AI repo detection, audit trail
- `learning` skill: external resource attribution
- Added VERSION file, CHANGELOG, and improvement backlog

## [0.8.0] - 2026-03-29

- Bidirectional sync scripts (`sync-from-upstream.sh`, `sync-from-polaris.sh`)
- Context monitoring and feedback auto-evolution rules
- CLAUDE.md genericized — company content moved to `rules/{company}/`

## [0.7.0] - 2026-03-29

- Two-layer config (root + company `workspace-config.yaml`)
- `/init` wizard v2 for interactive company setup
- All skills migrated to config-driven resolution

## [0.6.0] - 2026-03-28

- Template repo extracted from working instance
- Genericize pipeline (sed scripts strip company references)

## [0.5.0] - 2026-03-28

- Three-layer architecture (Workspace / Company / Project)
- Config consolidation into `workspace-config.yaml`

## [Pre-0.5]

Skills, rules, and references developed organically during daily usage in a production engineering team. No formal versioning.
