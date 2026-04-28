# Mechanism Registry

A registry of behavioral rules the Strategist must follow. Each entry has a **canary signal** — an observable symptom of violation. The post-task audit (see `feedback-and-memory.md § Post-Task Mechanism Audit`) checks these canaries after every task.

## How to Use

- **Post-task**: after completing a task, scan the High-drift mechanisms for violations in the current conversation
- **Periodic**: run `/validate-mechanisms` (future skill) for a full smoke test
- **On drift discovery**: if a mechanism was violated, record it as a feedback memory with the mechanism ID
- **Rationalizations & graduated mechanisms**: see `skills/references/mechanism-rationalizations.md` (per-section rationalizations) and `skills/references/deterministic-hooks-registry.md` (mechanisms graduated to hooks — auto-enforced, low audit priority)

## Registry

### Skill Routing (source: `rules/skill-routing.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `skill-first-invoke` | Invoke Skill tool as the first tool call when trigger matches | Any Read/Grep/Bash/MCP call before Skill tool on a matched trigger | High |
| `no-pre-process-skill-input` | Don't fetch Slack/JIRA/PR data before invoking skill | `gh api`, JIRA MCP, or Slack MCP call preceding Skill invocation | High |
| `no-manual-skill-steps` | Never partially execute skill steps by hand | Git/JIRA/Slack commands matching a skill's steps without Skill invocation | High |
| `hotfix-auto-ticket` | Fix intent + Slack URL + no JIRA key → create ticket before routing to bug-triage | Changeset or PR title missing JIRA key after hotfix flow | Medium |

### Delegation (source: `CLAUDE.md`, `rules/sub-agent-delegation.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `delegate-exploration` | > 3 files → dispatch Explorer sub-agent | > 5 consecutive Read/Grep in main session without conclusion | High |
| `delegate-implementation` | Multi-file edits → dispatch Implementer sub-agent | Edit/Write in main session across > 1 file (unless ≤ 3 lines) | High |
| `plan-first-large-scope` | > 3 files or arch decision → plan before code | Sub-agent producing 4+ file changes without prior plan | High |
| `model-tier-selection` | sonnet for explore/execute, haiku for JIRA batch ops (see `sub-agent-roles.md` § Model Tier) | JIRA batch sub-agent using sonnet; explore sub-agent with no model specified | Low |
| `all-code-changes-require-worktree` | Any op writing source files or mutating git state must run in a `git worktree add` copy. No exceptions, includes framework repo | Edit/Write on source files in main checkout path; `git checkout`/`switch`/`pull` in main checkout; sub-agent dispatched without `isolation: "worktree"` when its flow will write code | **Critical** |
| `worktree-for-batch-impl` | Batch mode Phase 2 sub-agents use `isolation: "worktree"` (specific case of `branch-switch-requires-worktree`) | Parallel implementation sub-agents without worktree isolation | Medium |
| `planning-skill-worktree-isolation` | Planning skills (Tier 2+) 跑 `pnpm install` / build / dev server 前必須先建立 worktree，不在主 checkout 執行 | Planning skill 在主 checkout path 跑 `pnpm -C {base_dir}/{repo} install` / build / dev server 而未先 `git worktree add`；或主 checkout 出現 `node_modules` / `.output/` diff | High |
| `breakdown-step14-no-checkout` | Breakdown Step 14 建 branch 只用 `git branch <name> <start>` + `git push`（禁 `checkout`/`pull`），順序依 `depends_on` 拓撲排序，從上游 branch 切出 | Breakdown session bash 歷史出現 `git checkout` / `git pull` 對主 checkout；或主 checkout HEAD/branch 在 Step 14 後有變化；或 branch 順序違反拓撲排序 | High |
| `breakdown-infra-first-applied` | Planning Path Step 5.5 必須跑 infra-first 決策樹，輸出 `decision_trace[]`；refinement Step 5 子單結構 preview 同步顯示 | Breakdown summary / task.md 缺 infra-first 決策記錄；或子單順序違反 decision tree；或 refinement preview § 子單結構 缺 infra-first 摘要行 | Medium |
| `subagent-completion-envelope` | All sub-agents return Status/Artifacts/Detail/Summary envelope. Summary ≤ 3 sentences; long analysis to Detail file | Sub-agent return without structured Status line; or Summary > 3 sentences with full analysis inline | High |
| `runtime-claims-need-runtime-evidence` | Sub-agent runtime claims (HTML location, API format, framework defaults) need actual execution evidence, not just source analysis | Strategist states runtime behavior as fact citing only sub-agent source-code analysis, no curl/test/dev-server evidence | High |

### Reference Discovery (source: `CLAUDE.md` § Reference Discovery)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `reference-index-scan` | Before skill execution, read `skills/references/INDEX.md` and pull in trigger-matched references | Skill executes JIRA operations (createJiraIssue, editJiraIssue, breakdown) without prior Read of INDEX.md or relevant reference files | **Critical** |

### Knowledge Compilation (source: `skills/references/knowledge-compilation-protocol.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `knowledge-source-of-truth-boundary` | Framework policy changes must be written in Atom layer first; derived outputs cannot become the only source of policy truth | Session edits translation/summary/generated docs that introduce new policy wording without corresponding update in `rules/*.md` or `skills/references/*.md` | High |
| `parallel-doc-naming-lock` | Parallel docs/reference generation must pre-lock filename/slug slots before fan-out; workers fill assigned slots only | Same concept lands as multiple ad-hoc filenames in one session (`*-protocol.md` and `*-workflow.md`) without prior slot map or coordinator decision | Medium |

### Feedback & Memory (source: `rules/feedback-and-memory.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `post-task-feedback-reflection` | After task completion, silently reflect for corrections/blocks/confirmations | Task ends with no reflection when user corrected behavior or command self-corrected | High |
| `feedback-pre-write-dedup` | Before creating feedback memory, scan for semantic overlap and merge if found | New feedback file created when an existing entry covers the same topic | High |
| `feedback-trigger-count-update` | After using a feedback memory, increment trigger_count (once per conversation) | Feedback memory trigger_count unchanged after conversation that referenced it | High |

| `feedback-backlog-classification` | New feedback memory that describes a framework gap must also write a backlog entry | FRAMEWORK_GAP feedback created without corresponding `polaris-backlog.md` entry | Medium |
| `project-backlog-classification` | Project memory with action items (待實施/下一步/需要解決) must also write FRAMEWORK_GAP items to backlog | Project memory containing "待實施" or "pending" without corresponding backlog entry | High |
| `memory-company-hard-skip` | Skip memories with mismatched company field | Company-scoped memory applied to a different company's work | Medium |
| `correction-driven-handbook-update` | User correction about repo-specific knowledge → pause work, update handbook (not feedback memory), resume with new understanding | Repo-specific correction (architecture, code convention, dev environment) saved as feedback memory instead of updating handbook | **Critical** |
| `repo-knowledge-to-handbook-not-feedback` | Repo-specific knowledge (code patterns, API conventions, test strategies, env setup) belongs in handbook sub-files, not feedback memories | New feedback memory created for repo-specific knowledge that should be in `{repo}/.claude/rules/handbook/*.md` | High |

### Handbook Lifecycle (source: `skills/references/repo-handbook.md`, `skills/references/explore-pattern.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `handbook-first-explore` | Explorer subagent reads handbook before codebase scanning | Explorer prompt missing handbook-first instruction; exploration repeats knowledge already in handbook | Medium |
| `explorer-handbook-ingest` | Strategist processes Explorer's Handbook Observations (gaps → write, stale → fix/mark) after exploration | Explorer returns Gaps/Stale observations but Strategist proceeds without updating handbook | Medium |
| `ingest-conflict-priority` | Handbook write priority: user correction > PR lesson > Explorer回寫 | Explorer-generated content overwrites a user-validated section | High |
| `event-driven-stale-hint` | Session start git diff shows handbook-related file changes → add stale-hint to affected section | `package.json` or `nuxt.config` changed in diff but no stale-hint added to handbook | Low |
| `batch-lint-sprint-planning` | Repo handbook batch lint runs during sprint-planning | Sprint planning completes without handbook lint report | Low |
| `handbook-injection-in-subagent` | Implementation sub-agent dispatch prompts must include handbook reading instruction for both company and repo handbooks: `{base_dir}/.claude/rules/{company}/handbook/index.md` + linked child docs, then `{repo}/.claude/rules/handbook/index.md` + linked child docs | Sub-agent writes code without prior Read of company handbook index and linked child docs; OR reads only handbook index but not referenced child files; OR violates coding convention already documented in company/repo handbook | High |
| `codecov-patch-fail-is-blocker` | Engineering revision mode treats failed `codecov/patch` / `codecov/patch/*` checks as CI blockers even when Codecov displays `author ... is not an activated member` or similar account visibility text | Revision reports Codecov patch failure as non-blocking due to author activation/member visibility text; OR PR completion proceeds with failed `codecov/patch/*` check unaddressed | **Critical** |

### Test Environment (source: DP-005, `skills/references/pipeline-handoff.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `test-command-in-task-md` | task.md must contain `## Test Command` section with project-specific test command from workspace-config `test_command` | task.md produced by breakdown missing `## Test Command` section; or section contains generic `npx vitest run` when workspace-config has a specific `test_command` | High |
| `test-env-hard-gate` | Engineering sub-agent must use task.md's Test Command to run tests; if test environment fails (exit ≠ 0, resolver error), stop and report — do not silently skip or fall back to CI-only | Engineering sub-agent runs `npx vitest run` instead of task.md's Test Command; or test failure is ignored and PR is opened without passing local tests | **Critical** |
| `task-md-test-env-section` | task.md must contain `## Test Environment` section with `Level: {static\|build\|runtime}` + workspace-config pointer + Fixtures declaration. breakdown Step 14.5 produces it; `scripts/validate-task-md.sh` enforces it | task.md missing `## Test Environment`; or Level value not one of `static`/`build`/`runtime`; or runtime-level Verify Command without Fixtures declared when Epic has mockoon fixtures | High |
| `engineering-reads-test-env` | engineering sub-agent must read `## Test Environment` section and prepare env per Level before running Verify Command (static: skip; build: run `pnpm build`; runtime: start `dev_environment.requires` + `start_command` + optionally mockoon) | engineering runs Verify Command without checking Test Environment Level; or runtime-level Verify Command executed without starting dev server / docker / fixtures (curl fails with connection refused) | High |

### Pipeline Artifact Schema (source: DP-025, `skills/references/pipeline-handoff.md` § Artifact Schemas)

Enforcement: deterministic via `pipeline-artifact-gate.sh` PreToolUse hook (validators in `scripts/validate-*.sh`). Bypass: `POLARIS_SKIP_ARTIFACT_GATE=1`. Audit priority: low.

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `refinement-schema-compliance` | `refinement.json` 必填欄位齊全（epic, version, modules[], acceptance_criteria[] with verification, dependencies[], edge_cases[]） | Edit/Write on refinement.json rejected by hook; OR committed file 缺必填欄位 | High |
| `task-md-full-schema` | task.md 必含 `## Operational Context`（JIRA key）、`## 改動範圍`、`## 估點理由`、`## Test Command`、`## Verify Command` + 非空 body | Edit/Write rejected by hook; OR task.md `## 改動範圍` 空或缺 `## Operational Context` | High |
| `task-md-deps-closure` | task.md `depends_on` 須 reference 同 Epic 內存在的 T*.md 且形成 DAG（無 cycle） | Edit/Write rejected for cyclic或missing target；OR verify-AC deadlock | High |
| `fixture-path-existence` | `## Test Environment` `Fixtures:` 路徑（非 N/A）須實際存在 | Edit/Write rejected for missing fixture path；OR runtime verify "fixtures not found" | High |
| `depends-on-linear-chain` | task.md `depends_on` 必須是 linear chain — 每個 task 最多 depend_on ≤ 1 其他 task | Edit/Write rejected by `is-linear-dag`；OR `depends_on: [A, B]` 其中 A、B 互不依賴 | Medium |

### Context Management (source: `rules/context-monitoring.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `post-compression-company-context` | After compression, re-confirm active company | Work continues post-compression without company context check | High |
| `proactive-context-check-at-20` | After 20+ tool calls without milestone, proactively save state and assess delegation | Long conversation without milestone summary or delegation assessment | Medium |
| `checkpoint-mode-at-25` | 25+ tool calls with pending work → checkpoint mode (save state + diff prev checkpoint + notify). Same applies to proactive session splits | Next-session memory drops items from prev checkpoint; OR "建議開新 session" without saving project memory first | High |
| `skill-completion-split` | After completing a skill, if next action is a different skill/topic → run checkpoint sequence + `checkpoint-todo-diff.sh` before notifying (see `context-monitoring.md` § 5a-bis) | Strategist switches from one skill to a different skill without checkpoint; or checkpoint written but `checkpoint-todo-diff.sh` not run | Medium |
| `checkpoint-todo-completeness` | When writing a checkpoint memory, run `scripts/checkpoint-todo-diff.sh` to verify all todo items have dispositions (done/carry-forward/dropped). Hard gate: notification blocked until diff passes | Checkpoint memory written with todo items missing from content; or session split notification sent before diff script confirms all items covered | High |

### Company Isolation (source: `rules/multi-company-isolation.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `scope-header-enforcement` | Company rule files must have `Scope:` header | File under `rules/{company}/` without scope header | Medium |

### Debugging & Verification (source: prior session violations, graduated 2026-04-04)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `fix-through-not-revert` | When implementation is broken, find root cause and fix — do not revert or add fallback as first response | Strategist proposes revert/fallback before investigating why the implementation failed | High |
| `query-original-impl` | Before changing an API call path, query the source-of-truth caller (e.g., your-backend calling api-lang) to confirm endpoint, auth, params, response format | API path changed without reading the original implementation that the change is supposed to match | High |
| `cross-repo-verification` | Cross-repo changes must be verified across all involved repos with full infra stack | Verification only runs in one repo when the ticket touches multiple repos; `workspace-config.requires` ignored | High |
| `env-follows-requires` | Dev environment must be started per `workspace-config.projects[].dev_environment.requires` — no shortcuts | Nuxt dev server started standalone when `requires: ["project-web-docker"]` is configured; Docker containers not running | High |
| `http-status-in-verification` | All endpoint verifications must check HTTP status code (200) + response body — status 200 is the minimum bar | Verification reports "data looks correct" without confirming HTTP 200 | Medium |
| `no-speculation-as-fact` | Do not repeat a speculation after user corrects it — once corrected, internalize the correction | Same wrong claim repeated after user already corrected it (e.g., "SIT 環境" after user said "我在 local") | Medium |
| `api-docs-before-replace` | When module behavior is unexpected, check official API docs before reading compiled source or proposing replacement. Replacement is T3 (needs user confirmation) | Sub-agent reads only `node_modules/` → concludes "module doesn't support X" → proposes replacement, no docs/npm README check | **Critical** |

### Library Changes (source: `skills/references/library-change-protocol.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `lib-exhaust-before-replace` | Before concluding a lib can't do X, exhaust three layers: official docs → GitHub issues → plugin/config combinations | Sub-agent proposes replacement citing only compiled source or "doesn't seem to work" without docs/issues evidence | **Critical** |
| `lib-replace-is-t3` | Replacing a framework-level module requires user confirmation (T3) | Framework module replaced without user confirmation in conversation | High |
| `lib-config-registration-check` | Impact assessment must check config-level registration (nuxt.config, webpack.config, composer.json plugins), not just `grep import` | Replacement proposed with "0 imports found" when lib is registered in framework config | High |
| `lib-lock-file-diff` | Upgrade evaluation must diff lock file for transitive dependency changes | Major/minor upgrade committed without lock file diff check | Medium |
| `lib-key-libraries-binding` | Handbook Key Libraries section designates concern→library bindings; replacement requires full protocol | Sub-agent replaces a library listed in Key Libraries without running the protocol | High |
| `lib-reviewer-upgrade-pause` | When PR reviewer suggests a library/module upgrade in revision mode, pause and ask user — do not unilaterally defer or dismiss | Revision-mode reply says "T3 deferred to next sprint" or "current version doesn't support this" without asking user whether to attempt the upgrade | High |

### Strategist Behavior (source: `CLAUDE.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `blind-spot-scan` | After producing a plan, protocol, or significant decision, pause and self-check (invert, edge cases, silent failure) before presenting or executing | Strategist presents a plan without any "what could go wrong" analysis; user discovers a blind spot the Strategist should have caught | Medium |
| `design-plan-creation` | When user starts a non-ticket design discussion, create `specs/design-plans/DP-NNN-{topic}/plan.md` in the first turn | Design discussion proceeds 3+ turns without a plan file; decisions only in conversation | **Critical** |
| `design-plan-decision-capture` | Each confirmed design decision (user says「可以」「同意」「乾淨」「好」「這樣做」) must update the plan file in the **very next tool call** — not batched, not deferred | Decision confirmed in conversation but plan file not updated before other tool calls | **Critical** |
| `design-plan-reference-at-impl` | Before implementation begins on a topic with an active design plan, read the plan file completely; do not rely on conversation memory | Strategist writes code / SKILL.md on a topic with existing plan file but no Read call on that plan in the current session | **Critical** |
| `design-plan-checklist-done` | Plan's Implementation Checklist must be fully checked before `status: IMPLEMENTED`. Deterministic backup: `design-plan-checklist-gate.sh` blocks the IMPLEMENTED edit when `[ ]` items remain | Edit/Write to plan.md with `status: IMPLEMENTED` blocked by hook when unchecked items exist | High |

### Quality Gates (source: `skills/references/engineer-delivery-flow.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `re-test-after-fix` | After fixing quality issues, re-run all tests before proceeding to commit | Git diff shows changes after last test run but commit proceeds without fresh test output | High |
| `fresh-verification-before-completion` | Every task completion must include fresh verification performed after the final code change | Task marked complete with rationalization phrases ("should work", "trivial change") and no verification output in conversation | High |
| `local-verification-hard-gate` | engineering (engineer-delivery-flow Step 3): every Layer A+B verification item must have PASS/SKIP/FAIL disposition with evidence. Unit test alone cannot substitute for behavioral verification when the AC requires running the server | Strategist proceeds to PR with only unit test output when [VERIFICATION] lists behavioral items (e.g., "切換語系後 footer 正確") | **Critical** |
| `verify-command-immutable-execute` | Step 3d: when task.md has `## Verify Command`, sub-agent must execute the exact command (no modifications) and include full output in evidence file. FAIL blocks PR | Sub-agent skips verify command, modifies the command, or claims PASS without showing actual command output in evidence | **Critical** |
| `tdd-bypass-no-assertion-weakening` | On any quality-gate failure, fix root cause — never weaken assertions, mock real deps, `.skip()`/delete tests, or `as any`/`@ts-ignore` to silence | Gate fail → prod code edit → test pass with assertion loosening / skip / type-suppression in diff; or new `.skip()` / `as any` / `@ts-ignore` on touched lines without justification | High |
| `engineering-no-ac-verify` | engineering does not run AC business-level verification — that's verify-AC's job. engineering only runs Phase 2.5 Sanity Gate (env up + HTTP 200) | engineering session executing verify-AC steps (逐項跑 AC 驗收 sub-task) instead of routing to verify-AC skill after PR | High |
| `verify-ac-no-judgement` | verify-AC presents observed vs expected as facts — does not judge FAIL reason; disposition is human-driven | verify-AC output contains "this is a bug in X" or "AC is wrong" instead of pure PASS/FAIL + disposition gate | High |
| `verify-ac-full-rerun` | verify-AC re-runs ALL AC (including previously PASS'd) to catch regression | verify-AC session skips PASS'd AC from last run | Medium |
| `verify-ac-http-status` | AC endpoint verification must assert HTTP status == 200 before checking body | verify-AC passes an AC based on "body looks right" without recording HTTP status | High |
| `bug-triage-ac-fail-detection` | When Bug description contains `[VERIFICATION_FAIL]`, bug-triage takes AC-FAIL Path — scoped to feature branch only, uses verify-AC's observed/expected as facts, does not redo verification | bug-triage runs generic Step 3 Explorer on a `[VERIFICATION_FAIL]` Bug (analyzes develop/main instead of feature branch, or re-verifies observed behavior) | High |
| `ac-fail-bug-branch-from-feature` | engineering opens fix branch for AC-FAIL Bug from the Epic's feature branch (extracted from `[VERIFICATION_FAIL]` block), not from develop | engineering creates fix branch from develop for a Bug whose description contains `[VERIFICATION_FAIL]` — fix never lands on the failing feature branch | High |
| `checklist-before-done` | Before declaring a task complete, review the session's original task list (checkpoint next steps, todo items) and confirm each item is done/carry-forward/dropped | Strategist says "done" or asks "要更新 checkpoint 嗎？" while unchecked items remain from the session's starting checklist | High |
| `defer-immediate-capture` | When a decision defers work to a later phase, capture it in todo (same session) or memory (future session) immediately — oral defer is not landed | Conversation contains "等 X 再處理 Y" pattern but no corresponding todo/memory entry created within the next 2 tool calls | High |
| `completion-gate-before-done-report` | Before any user-facing "done / complete / 可交付" report in engineering flow, run Step 8.5 `check-delivery-completion.sh`. This is behavioral L3, not a deterministic hook | Assistant reports completion for a delivery task without a preceding completion-gate invocation or evidence that Layer A/B gates were rechecked at report time | Medium |

### Delivery Flow Contract (source: `skills/references/engineer-delivery-flow.md` § Delivery Contract)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `delivery-flow-step-order` | engineer-delivery-flow steps must execute in order (1→2→3→3.5→4→5→5.5→6→7→8). No step may be skipped or reordered | Sub-agent jumps from Step 2 to Step 7 (skipping behavioral verify) or runs Step 7 before Step 4 | **Critical** |
| `delivery-flow-single-backbone` | All PR creation goes through engineer-delivery-flow (via engineering or git-pr-workflow). No standalone PR creation outside the flow | `gh pr create` called outside engineer-delivery-flow context (no evidence file, no simplify/quality/verify steps in conversation) | High |
| `vr-conditional-trigger` | Step 3.5 VR triggers when changed files hit a VR-configured domain page. Not triggering when no VR domain is configured is correct; skipping when a domain IS configured is a violation | VR domain exists in workspace-config and changed files match VR pages, but Step 3.5 was skipped | Medium |
| `pr-body-from-reference` | PR body must be built using `references/pr-body-builder.md` logic (template detection → section fill → AC Coverage) and sent via `--body-file`. Deterministic backup: `gate-pr-body-template.sh` in `polaris-pr-create.sh` blocks bodies that do not preserve repo PR template `##` headings or contain shell-escaped Markdown backticks | PR body written inline without reading pr-body-builder.md; repo template headings missing/out of order; backslash-backtick escape sequences appear in rendered body; AC Coverage section missing when JIRA AC exists | High |
| `evidence-file-completeness` | Evidence file must contain both `layer_a` and `layer_b` (Developer) or `layer_a` only (Admin). VR result (`vr` field) must be present when Step 3.5 triggered | Evidence file written without `layer_b` for Developer role, or missing `vr` field when VR was triggered | Medium |
| `epic-folder-structure-compliance` | All Epic artifacts (mockoon fixtures, VR baselines, verification evidence, task.md, refinement) must be written to `specs/{EPIC}/` per `references/epic-folder-structure.md`. No Epic data in `ai-config/` or other locations | Skill writes mockoon fixtures to `ai-config/{company}/mockoon-environments/` or verification evidence to `/tmp` only (without local copy in `specs/{EPIC}/verification/`) | Medium |
| `pre-work-rebase` | engineering must rebase before development (§ 4.5) / before revision (§ R0), not only at delivery flow Step 5. Rebase includes cascade when base is a feature branch. Conflict → stop, do not start coding | engineering starts coding (Edit/Write on source files) without prior `git rebase` in the same session; or rebase only appears after code changes (at delivery flow Step 5) with no pre-work rebase | High |
| `revision-r5-mandatory` | Revision mode R5（重跑完整驗收）mandatory for ALL revision paths（含 rebase-only）。Push without behavioral verification 永不允許。Deterministic backup: `verification-evidence-gate.sh` 攔截 `git push` | `git push` in revision mode without prior Layer B verification output; or Strategist rationalizes "只是 rebase，沒改 code" to skip R5 | **Critical** |
| `spec-status-mark-on-done` | 完成後須將 spec frontmatter `status` 標為 `IMPLEMENTED`。Writers: engineering Step 8a (Task), verify-AC (Epic 全 PASS), check-pr-approvals (MERGED Bug/ad-hoc)。Helper: `scripts/mark-spec-implemented.sh` | engineering 開完 PR 但 task.md status 未標記；或 Epic 全 PASS 後 refinement.md 仍非 IMPLEMENTED；或 setup-only Done 但 task.md 無 status | Medium |
| `engineering-consume-depends-on` | engineering 開 PR / rebase / 修 PR base 必須透過 `scripts/resolve-task-base.sh` 取得 base，不可讀 task.md frontmatter 字面值或 PR 既有 `baseRefName`。`gh pr create/edit --base X` 與 pre-work rebase target 必須 == 該腳本輸出。Revision R0 必須同步 PR base。Deterministic backup: `pr-base-gate.sh` 攔截不一致的 `--base` | `--base X` ≠ resolve-task-base.sh 輸出；或 pre-work rebase target 不一致；或讀 task.md `Base branch` 字面值/PR `baseRefName` 當 base；或 R0 rebase 後沒同步 PR base 欄位 | High |

### Scope Escalation (source: DP-044, `skills/engineering/SKILL.md` § 開發中 Scope Escalation, `skills/breakdown/SKILL.md` § Scope-Escalation Intake Path)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `engineering-escalation-sidecar-only` | engineering halts on scope expansion (gate fail outside Allowed Files + planner-owned field change); writes sidecar at `specs/{EPIC}/escalations/T{n}-{count}.md` only; never edits task.md from inside engineering | engineering session contains Edit/Write on `task.md`; OR engineering modifies Allowed Files / Test Command / Verify Command / Test Environment / depends_on / estimate inline; OR escalation conditions met but no sidecar produced before session end | **Critical** |
| `engineering-escalation-gate-closure` | Scope escalation sidecar must diagnose the whole failed gate: pass condition, baseline/actual, explained delta, proposed fixes, residual blockers, closure forecast, and required planner decisions. Necessary-but-insufficient fixes must be flagged before routing to breakdown | Sidecar only lists first out-of-scope file(s); OR closure forecast missing; OR later rerun exposes residual blockers already visible in the first gate output/math; OR breakdown receives a sidecar that cannot tell whether proposed scope change will make the gate pass | **Critical** |
| `escalation-count-cap` | Escalation lineage capped at 2; third escalation routes to `refinement`, not `breakdown`. Validator (`scripts/validate-escalation-sidecar.sh`) blocks `escalation_count > 2` and duplicate slots | Sidecar written with `escalation_count > 2` (validator should have blocked); OR session attempts a third sidecar on the same lineage and dispatches `breakdown` instead of `refinement`; OR validator FAIL ignored and engineering proceeds | High |
| `breakdown-escalation-intake` | breakdown reads sidecar (highest `count` for the lineage), may re-classify flavor, must log `accepted flavor: X` or `re-classified to Y: reason`; reuses Planning Path user-confirmation gate before any task.md edit / JIRA write; handles all `Required Planner Decisions` needed for gate closure; marks sidecar `processed: true` post-confirm | breakdown session updates task.md from a sidecar without an explicit accepted/re-classified line; OR only handles the first proposed fix while `Closure Forecast` says gate still fails; OR new user-confirmation gate invented instead of reusing Planning Path Step 8/11; OR sidecar not marked `processed: true` after writes complete | Medium |

### Deterministic Quality Hooks

Hook-enforced mechanisms (exit code driven, physically block). Full table + bypass flags + script paths in `skills/references/deterministic-hooks-registry.md` and `skills/references/mechanism-rationalizations.md` § Deterministic Quality Hooks — Detail. Audit priority: low.

### Skills Management (source: `CLAUDE.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `no-skill-create-modify-direct` | Create/modify skills only via `/skill-creator` | Direct SKILL.md edits without skill-creator invocation | Medium |

### Cross-Session Knowledge (source: `rules/feedback-and-memory.md`, `skills/references/cross-session-learnings.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `learning-write-post-task` | After task completion, write technical learnings if non-obvious insights were discovered (max 2 per task) | Task involving debugging or unexpected behavior completes with no `polaris-learnings.sh add` call | Medium |
| `learning-preamble-inject` | At conversation start, query top learnings and use as context | Conversation proceeds without querying learnings when `~/.polaris/projects/` exists | Medium |
| `timeline-milestone-events` | Log timeline events for skill invocations, PRs, commits, and errors | Skill invoked without corresponding `polaris-timeline.sh append` call | Low |

### Framework Iteration (source: `rules/framework-iteration.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `challenger-milestone-only` | Challenger Audit runs pre-release/pre-share only | Challenger triggered after a single PR or during daily work | High |
| `framework-exp-once-per-task` | At most 1 framework-experience memory per task | Multiple framework-experience memories with the same `last_triggered` date | Low |
| `docs-sync-on-version-bump` | After VERSION bump commit, run docs-sync before sync-to-polaris. **Deterministic backup:** `version-docs-lint-gate` hook blocks commit if VERSION staged + lint fails | VERSION bumped and pushed without docs-sync invocation | High |
| `backlog-staleness-scan` | Post-version-bump chain Step 2 + monthly standup fallback: scan backlog for stale items | Version bump completes without backlog scan; first standup of month skips scan when no bump happened that month | Medium |

### Cross-Session Continuity (source: `CLAUDE.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `cross-session-read-memory-file` | When user says "繼續 X", search MEMORY.md index then READ the full memory file before responding | Strategist reports "memory lost" or "no details" when MEMORY.md index has a matching entry | High |
| `cross-session-confirm-context` | After reading memory file, present reconstructed context to user for confirmation | New session starts work without summarizing what was decided/done/next from previous session | Medium |
| `cross-session-warm-folder-scan` | "繼續 X" memory 搜尋必須涵蓋 Hot + Warm folders + 遞迴 `find -iname`，不可只用 `ls \| grep`。Deterministic backup: `cross-session-warm-scan.sh` UserPromptSubmit hook | 只跑 `ls memory/ \| grep` / 讀 `MEMORY.md` index 即下結論；OR 結論「無相關 memory」但 Warm `{topic}/index.md` 含對應 entry；OR 忽略 hook 注入的 `[繼續] Memory matches detected` | Medium |

### Deterministic Enforcement (source: `CLAUDE.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `no-workaround-accumulation` | If ≥ 2 workarounds added for the same feature in one session, STOP and check design | Two or more helper functions / manual fixes added to bypass a single failing feature (e.g., ensure_redis + kill_port + manual pnpm install all for "env doesn't start") | **Critical** |
| `design-implementation-reconciliation` | When first execution fails, check design doc before adding fixes | Implementation fix committed without reading the corresponding design memory/plan | High |
| `env-hard-gate` | polaris-env.sh required health checks must exit non-zero on failure | polaris-env.sh prints [✗] for required service but exits 0, allowing downstream to proceed | High |
| `no-bandaid-as-feature` | Workaround helpers must not be committed as framework improvements | Git commit message frames a workaround (e.g., "ensure_redis") as a feature ("polaris-env.sh 補強") | High |

### Security (source: `rules/feedback-and-memory.md`, `scripts/skill-sanitizer.py`, `scripts/safety-gate.sh`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `memory-integrity-scan` | During organize-memory, scan all memory files with `scan-memory` for prompt injection | Memory file with HIGH/CRITICAL findings applied without flagging to user | Medium |
| `learning-intake-prescan` | `/learning` external mode Step 1.1: scan external repo SKILL.md files before exploration | External repo skills read into context without prior sanitizer scan | Medium |
| `safety-gate-active` | `safety-gate.sh` PreToolUse hook must be configured in settings.json. Codex fallback: run Bash via `scripts/codex-guarded-bash.sh` to enforce same policy table | Sub-agent executes dangerous bash pattern (reverse shell, pipe-to-shell) without hook block | High |
| `session-start-fast-check` | At conversation start, run git status/stash/branch check before responding | Session starts with WIP in working tree but no WIP report shown to user | High |
| `wip-branch-before-topic-switch` | When switching topics with uncommitted changes, commit WIP to a branch first | Unrelated changes mixed into a topic commit (files from previous work included in new commit) | High |

## Priority Audit Order

Post-task audit should check these first (highest drift risk, most impactful):

1. `no-workaround-accumulation` / `design-implementation-reconciliation`
1a. `design-plan-creation` / `design-plan-decision-capture` / `design-plan-reference-at-impl` (Critical — check-pr-approvals v2.10→v2.16 掉棒事件)
2. `skill-first-invoke` / `no-manual-skill-steps` / `reference-index-scan`
3. `api-docs-before-replace` / `lib-exhaust-before-replace` / `fix-through-not-revert` / `query-original-impl` (Critical — PROJ-123 root cause + library change protocol)
4. `delegate-exploration` / `delegate-implementation`
5. `cross-session-read-memory-file`
6. `correction-driven-handbook-update` (repo-specific → handbook, framework → feedback)
6a. `checkpoint-mode-at-25` (check during long sessions, not just post-task)
7. `re-test-after-fix` / `fresh-verification-before-completion` / `checklist-before-done`
8. `cross-repo-verification` / `env-follows-requires`
9. Deterministic hooks/scripts (`feedback-trigger-count-update` / `version-bump-reminder` / `cross-session-carry-forward` / etc.) — auto-enforced where active, low priority. See `deterministic-hooks-registry.md`
