# Mechanism Registry

A registry of behavioral rules the Strategist must follow. Each entry has a **canary signal** — an observable symptom of violation. The post-task audit (see `feedback-and-memory.md § Post-Task Mechanism Audit`) checks these canaries after every task.

## How to Use

- **Post-task**: after completing a task, scan the High-drift mechanisms for violations in the current conversation
- **Periodic**: run `/validate-mechanisms` (future skill) for a full smoke test
- **On drift discovery**: if a mechanism was violated, record it as a feedback memory with the mechanism ID

## Registry

### Skill Routing (source: `rules/skill-routing.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `skill-first-invoke` | Invoke Skill tool as the first tool call when trigger matches | Any Read/Grep/Bash/MCP call before Skill tool on a matched trigger | High |
| `no-pre-process-skill-input` | Don't fetch Slack/JIRA/PR data before invoking skill | `gh api`, JIRA MCP, or Slack MCP call preceding Skill invocation | High |
| `no-manual-skill-steps` | Never partially execute skill steps by hand | Git/JIRA/Slack commands matching a skill's steps without Skill invocation | High |
| `hotfix-auto-ticket` | Fix intent + Slack URL + no JIRA key → create ticket before routing to bug-triage | Changeset or PR title missing JIRA key after hotfix flow | Medium |

#### Common Rationalizations — Skill Routing

> See `skills/references/mechanism-rationalizations.md` § Common Rationalizations — Skill Routing.

### Delegation (source: `CLAUDE.md`, `rules/sub-agent-delegation.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `delegate-exploration` | > 3 files → dispatch Explorer sub-agent | > 5 consecutive Read/Grep in main session without conclusion | High |
| `delegate-implementation` | Multi-file edits → dispatch Implementer sub-agent | Edit/Write in main session across > 1 file (unless ≤ 3 lines) | High |
| `plan-first-large-scope` | > 3 files or arch decision → plan before code | Sub-agent producing 4+ file changes without prior plan | High |
| `model-tier-selection` | sonnet for explore/execute, haiku for JIRA batch ops (see `sub-agent-roles.md` § Model Tier) | JIRA batch sub-agent using sonnet; explore sub-agent with no model specified | Low |
| `worktree-for-batch-impl` | Batch mode Phase 2 sub-agents use `isolation: "worktree"` | Parallel implementation sub-agents without worktree isolation | Medium |
| `planning-skill-worktree-isolation` | Planning skills (refinement Tier 2+ / breakdown Planning Path / bug-triage AC-FAIL + 復現 / sasd-review 可行性驗證) 跑 `pnpm install` / build / dev server 前必須先建立 worktree，不得在主 checkout 執行。見 `skills/references/planning-worktree-isolation.md` | Planning skill 在主 checkout path 跑 `pnpm -C {base_dir}/{repo} install` / build / dev server 而未先 `git worktree add`；或主 checkout 出現 `node_modules` / `.output/` diff | High |
| `breakdown-step14-no-checkout` | Breakdown Step 14 建立 feature / task branch 只用 `git branch <name> <start>`（不帶 `-b`）+ `git push`，禁止 `git checkout -b` / `git checkout develop` / `git pull origin develop`。確保使用者 WIP 不受干擾 | Breakdown session 的 bash 歷史出現 `git checkout` / `git pull` 針對主 checkout path；或主 checkout 的 HEAD / branch / working tree 在 Step 14 執行後有變化 | High |
| `breakdown-infra-first-applied` | Planning Path breakdown 必須在 Step 5.5 跑 `skills/references/infra-first-decision.md` 決策樹，輸出含 `decision_trace[]`；不得繞回舊的 `visual_regression`-config fallback（除非 refinement.json 缺失或匹配 exceptions）。Refinement Step 5 的 § 子單結構 preview 也須同步顯示決策結果 | Breakdown session 跑 Planning Path 卻 breakdown summary / task.md 缺少 infra-first 決策記錄（「infra 子單 N 張，ordering {rule}」或 skipped reason）；或輸出的子單順序違反 decision tree（e.g., AC 全 unit_test 仍插入 infra 子單）；或 refinement preview § 子單結構 缺少 infra-first 摘要行 | Medium |
| `subagent-completion-envelope` | All sub-agents must return Status/Artifacts/Detail/Summary envelope. Summary ≤ 3 sentences; long analysis goes to Detail file (see `sub-agent-roles.md` § Completion Envelope + Summary vs Detail Separation) | Sub-agent return without structured Status line; or Summary exceeds 3 sentences with full analysis inline instead of Detail file | High |
| `runtime-claims-need-runtime-evidence` | Sub-agent conclusions about runtime behavior (HTML location, API format, framework defaults) must be verified with actual execution before the Strategist adopts them | Strategist states a runtime behavior as fact citing only sub-agent source code analysis, without curl/test/dev-server evidence | High |

### Reference Discovery (source: `CLAUDE.md` § Reference Discovery)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `reference-index-scan` | Before skill execution, read `skills/references/INDEX.md` and pull in trigger-matched references | Skill executes JIRA operations (createJiraIssue, editJiraIssue, breakdown) without prior Read of INDEX.md or relevant reference files | **Critical** |

#### Common Rationalizations — Reference Discovery and Delegation

> See `skills/references/mechanism-rationalizations.md` § Common Rationalizations — Reference Discovery and § Common Rationalizations — Delegation.

### Feedback & Memory (source: `rules/feedback-and-memory.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `post-task-feedback-reflection` | After task completion, silently reflect for corrections/blocks/confirmations | Task ends with no reflection when user corrected behavior or command self-corrected | High |
| `feedback-pre-write-dedup` | Before creating feedback memory, scan for semantic overlap and merge if found | New feedback file created when an existing entry covers the same topic | High |
| `feedback-trigger-count-update` | After using a feedback memory, increment trigger_count (once per conversation) | Feedback memory trigger_count unchanged after conversation that referenced it | High |
| `feedback-backlog-classification` | New feedback memory that describes a framework gap must also write a backlog entry | FRAMEWORK_GAP feedback created without corresponding `polaris-backlog.md` entry | Medium |
| `project-backlog-classification` | Project memory with action items (待實施/下一步/需要解決) must also write FRAMEWORK_GAP items to backlog | Project memory containing "待實施" or "pending" without corresponding backlog entry | High |
| `memory-company-hard-skip` | Skip memories with mismatched company field | Company-scoped memory applied to a different company's work | Medium |
| `cross-session-carry-forward` | Writing next-session memory must diff previous checkpoint's pending items — no silent drops | New project memory's "next steps" missing items from previous checkpoint without (a) done / (b) carry-forward / (c) dropped disposition | **Critical** |
| `correction-driven-handbook-update` | User correction about repo-specific knowledge → pause work, update handbook (not feedback memory), resume with new understanding | Repo-specific correction (architecture, code convention, dev environment) saved as feedback memory instead of updating handbook | **Critical** |
| `repo-knowledge-to-handbook-not-feedback` | Repo-specific knowledge (code patterns, API conventions, test strategies, env setup) belongs in handbook sub-files, not feedback memories | New feedback memory created for repo-specific knowledge that should be in `{repo}/.claude/rules/handbook/*.md` | High |

#### Common Rationalizations — Handbook vs Feedback

> See `skills/references/mechanism-rationalizations.md` § Common Rationalizations — Handbook vs Feedback.

### Handbook Lifecycle (source: `skills/references/repo-handbook.md`, `skills/references/explore-pattern.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `handbook-first-explore` | Explorer subagent reads handbook before codebase scanning | Explorer prompt missing handbook-first instruction; exploration repeats knowledge already in handbook | Medium |
| `explorer-handbook-ingest` | Strategist processes Explorer's Handbook Observations (gaps → write, stale → fix/mark) after exploration | Explorer returns Gaps/Stale observations but Strategist proceeds without updating handbook | Medium |
| `ingest-conflict-priority` | Handbook write priority: user correction > PR lesson > Explorer回寫 | Explorer-generated content overwrites a user-validated section | High |
| `event-driven-stale-hint` | Session start git diff shows handbook-related file changes → add stale-hint to affected section | `package.json` or `nuxt.config` changed in diff but no stale-hint added to handbook | Low |
| `batch-lint-sprint-planning` | Repo handbook batch lint runs during sprint-planning | Sprint planning completes without handbook lint report | Low |
| `handbook-injection-in-subagent` | Implementation sub-agent dispatch prompts must include handbook reading instruction (`{repo}/.claude/rules/handbook/`) | Sub-agent writes code without prior Read of handbook index.md; implementation violates coding convention already documented in handbook | High |

### Test Environment (source: DP-005, `skills/references/pipeline-handoff.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `test-command-in-task-md` | task.md must contain `## Test Command` section with project-specific test command from workspace-config `test_command` | task.md produced by breakdown missing `## Test Command` section; or section contains generic `npx vitest run` when workspace-config has a specific `test_command` | High |
| `test-env-hard-gate` | Engineering sub-agent must use task.md's Test Command to run tests; if test environment fails (exit ≠ 0, resolver error), stop and report — do not silently skip or fall back to CI-only | Engineering sub-agent runs `npx vitest run` instead of task.md's Test Command; or test failure is ignored and PR is opened without passing local tests | **Critical** |

### Context Management (source: `rules/context-monitoring.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `max-five-consecutive-reads` | Max 5 Read/Grep calls before conclusion or delegation | 6+ consecutive Read/Grep without intervening conclusion | High |
| `no-file-reread` | Don't read same file > 2 times unless modified | Same file path in > 2 Read calls in one conversation | Medium |
| `post-compression-company-context` | After compression, re-confirm active company | Work continues post-compression without company context check | High |
| `proactive-context-check-at-20` | After 20+ tool calls without milestone, proactively save state and assess delegation | Long conversation without milestone summary or delegation assessment | Medium |
| `checkpoint-mode-at-25` | 25+ tool calls with pending work → enter checkpoint mode (save state + diff previous checkpoint + notify new session). Also applies to proactive session splits: save memory before notifying, never after | Long session ends with next-session memory that drops items from previous checkpoint; OR Strategist says "建議開新 session" without having saved a project memory first | High |
| `skill-completion-split` | After completing a skill, if next action is a different skill/topic → run checkpoint sequence + `checkpoint-todo-diff.sh` before notifying (see `context-monitoring.md` § 5a-bis) | Strategist switches from one skill to a different skill without checkpoint; or checkpoint written but `checkpoint-todo-diff.sh` not run | Medium |
| `checkpoint-todo-completeness` | When writing a checkpoint memory, run `scripts/checkpoint-todo-diff.sh` to verify all todo items have dispositions (done/carry-forward/dropped). Hard gate: notification blocked until diff passes | Checkpoint memory written with todo items missing from content; or session split notification sent before diff script confirms all items covered | High |

### Bash Execution (source: `rules/bash-command-splitting.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `no-cd-in-bash` | Never use `cd` in Bash; use tool path parameters | `cd ` appearing in any Bash command | High |
| `no-independent-cmd-chaining` | Don't chain independent commands with `&&` | Multiple independent commands joined by `&&` in one Bash call | High |

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
| `api-docs-before-replace` | When a module's behavior doesn't match expectations, query official API docs (function signatures, parameters) BEFORE reading compiled source or proposing replacement. Replacement is a T3 decision requiring user confirmation | Sub-agent reads only `node_modules/` compiled source → concludes "module doesn't support X" → proposes replacement, without checking official docs or npm README | **Critical** |

#### Common Rationalizations — Debugging & Verification

> See `skills/references/mechanism-rationalizations.md` § Common Rationalizations — Debugging & Verification.

### Library Changes (source: `skills/references/library-change-protocol.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `lib-exhaust-before-replace` | Before concluding a lib can't do X, exhaust three layers: official docs → GitHub issues → plugin/config combinations | Sub-agent proposes replacement citing only compiled source or "doesn't seem to work" without docs/issues evidence | **Critical** |
| `lib-replace-is-t3` | Replacing a framework-level module requires user confirmation (T3) | Framework module replaced without user confirmation in conversation | High |
| `lib-config-registration-check` | Impact assessment must check config-level registration (nuxt.config, webpack.config, composer.json plugins), not just `grep import` | Replacement proposed with "0 imports found" when lib is registered in framework config | High |
| `lib-lock-file-diff` | Upgrade evaluation must diff lock file for transitive dependency changes | Major/minor upgrade committed without lock file diff check | Medium |
| `lib-key-libraries-binding` | Handbook Key Libraries section designates concern→library bindings; replacement requires full protocol | Sub-agent replaces a library listed in Key Libraries without running the protocol | High |
| `lib-reviewer-upgrade-pause` | When PR reviewer suggests a library/module upgrade in revision mode, pause and ask user — do not unilaterally defer or dismiss | Revision-mode reply says "T3 deferred to next sprint" or "current version doesn't support this" without asking user whether to attempt the upgrade | High |

#### Common Rationalizations — Library Changes

> See `skills/references/library-change-protocol.md` § Common Rationalizations (canonical source).

### Strategist Behavior (source: `CLAUDE.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `blind-spot-scan` | After producing a plan, protocol, or significant decision, pause and self-check (invert, edge cases, silent failure) before presenting or executing | Strategist presents a plan without any "what could go wrong" analysis; user discovers a blind spot the Strategist should have caught | Medium |
| `design-plan-creation` | When user starts a non-ticket design discussion (triggers in `skill-routing.md` § design-plan row, or multi-turn architecture back-and-forth), create `specs/design-plans/DP-NNN-{topic}/plan.md` in the first turn | Design discussion proceeds 3+ turns without a plan file existing; decisions accumulate only in conversation | **Critical** |
| `design-plan-decision-capture` | Each confirmed design decision (user says「可以」「同意」「乾淨」「好」「這樣做」) must update the plan file in the **very next tool call** — not batched, not deferred | Decision confirmed in conversation but plan file not updated before other tool calls | **Critical** |
| `design-plan-reference-at-impl` | Before implementation begins on a topic with an active design plan, read the plan file completely; do not rely on conversation memory | Strategist writes code / SKILL.md on a topic with existing plan file but no Read call on that plan in the current session | **Critical** |
| `design-plan-checklist-done` | Plan's Implementation Checklist must be fully checked before declaring done; each item ticked off in the file (not in memory) as it completes. **Deterministic:** `scripts/design-plan-checklist-gate.sh` PreToolUse hook blocks Edit/Write that sets `status: IMPLEMENTED` when `[ ]` items remain | Edit/Write to plan.md with `status: IMPLEMENTED` blocked by hook when unchecked items exist | High |

#### Common Rationalizations — Design Plan

> See `skills/references/mechanism-rationalizations.md` § Common Rationalizations — Design Plan.

### Quality Gates (source: `skills/references/engineer-delivery-flow.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `re-test-after-fix` | After fixing quality issues, re-run all tests before proceeding to commit | Git diff shows changes after last test run but commit proceeds without fresh test output | High |
| `fresh-verification-before-completion` | Every task completion must include fresh verification performed after the final code change | Task marked complete with rationalization phrases ("should work", "trivial change") and no verification output in conversation | High |
| `local-verification-hard-gate` | engineering (engineer-delivery-flow Step 3): every Layer A+B verification item must have PASS/SKIP/FAIL disposition with evidence. Unit test alone cannot substitute for behavioral verification when the AC requires running the server | Strategist proceeds to PR with only unit test output when [VERIFICATION] lists behavioral items (e.g., "切換語系後 footer 正確") | **Critical** |
| `verify-command-immutable-execute` | Step 3d: when task.md has `## Verify Command`, sub-agent must execute the exact command (no modifications) and include full output in evidence file. FAIL blocks PR | Sub-agent skips verify command, modifies the command, or claims PASS without showing actual command output in evidence | **Critical** |
| `engineering-no-ac-verify` | engineering does not run AC business-level verification — that's verify-AC's job. engineering only runs Phase 2.5 Sanity Gate (env up + HTTP 200) | engineering session executing verify-AC steps (逐項跑 AC 驗收 sub-task) instead of routing to verify-AC skill after PR | High |
| `verify-ac-no-judgement` | verify-AC presents observed vs expected as facts — does not judge FAIL reason; disposition is human-driven | verify-AC output contains "this is a bug in X" or "AC is wrong" instead of pure PASS/FAIL + disposition gate | High |
| `verify-ac-full-rerun` | verify-AC re-runs ALL AC (including previously PASS'd) to catch regression | verify-AC session skips PASS'd AC from last run | Medium |
| `verify-ac-http-status` | AC endpoint verification must assert HTTP status == 200 before checking body | verify-AC passes an AC based on "body looks right" without recording HTTP status | High |
| `bug-triage-ac-fail-detection` | When Bug description contains `[VERIFICATION_FAIL]`, bug-triage takes AC-FAIL Path — scoped to feature branch only, uses verify-AC's observed/expected as facts, does not redo verification | bug-triage runs generic Step 3 Explorer on a `[VERIFICATION_FAIL]` Bug (analyzes develop/main instead of feature branch, or re-verifies observed behavior) | High |
| `ac-fail-bug-branch-from-feature` | engineering opens fix branch for AC-FAIL Bug from the Epic's feature branch (extracted from `[VERIFICATION_FAIL]` block), not from develop | engineering creates fix branch from develop for a Bug whose description contains `[VERIFICATION_FAIL]` — fix never lands on the failing feature branch | High |
| `checklist-before-done` | Before declaring a task complete, review the session's original task list (checkpoint next steps, todo items) and confirm each item is done/carry-forward/dropped | Strategist says "done" or asks "要更新 checkpoint 嗎？" while unchecked items remain from the session's starting checklist | High |
| `defer-immediate-capture` | When a decision defers work to a later phase, capture it in todo (same session) or memory (future session) immediately — oral defer is not landed | Conversation contains "等 X 再處理 Y" pattern but no corresponding todo/memory entry created within the next 2 tool calls | High |

### Delivery Flow Contract (source: `skills/references/engineer-delivery-flow.md` § Delivery Contract)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `delivery-flow-step-order` | engineer-delivery-flow steps must execute in order (1→2→3→3.5→4→5→5.5→6→7→8). No step may be skipped or reordered | Sub-agent jumps from Step 2 to Step 7 (skipping behavioral verify) or runs Step 7 before Step 4 | **Critical** |
| `delivery-flow-single-backbone` | All PR creation goes through engineer-delivery-flow (via engineering or git-pr-workflow). No standalone PR creation outside the flow | `gh pr create` called outside engineer-delivery-flow context (no evidence file, no simplify/quality/verify steps in conversation) | High |
| `vr-conditional-trigger` | Step 3.5 VR triggers when changed files hit a VR-configured domain page. Not triggering when no VR domain is configured is correct; skipping when a domain IS configured is a violation | VR domain exists in workspace-config and changed files match VR pages, but Step 3.5 was skipped | Medium |
| `pr-body-from-reference` | PR body must be built using `references/pr-body-builder.md` logic (template detection → section fill → AC Coverage). Manual PR body construction bypasses AC Coverage and Bug RCA detection | PR body written inline without reading pr-body-builder.md; AC Coverage section missing when JIRA AC exists | High |
| `evidence-file-completeness` | Evidence file must contain both `layer_a` and `layer_b` (Developer) or `layer_a` only (Admin). VR result (`vr` field) must be present when Step 3.5 triggered | Evidence file written without `layer_b` for Developer role, or missing `vr` field when VR was triggered | Medium |
| `epic-folder-structure-compliance` | All Epic artifacts (mockoon fixtures, VR baselines, verification evidence, task.md, refinement) must be written to `specs/{EPIC}/` per `references/epic-folder-structure.md`. No Epic data in `ai-config/` or other locations | Skill writes mockoon fixtures to `ai-config/{company}/mockoon-environments/` or verification evidence to `/tmp` only (without local copy in `specs/{EPIC}/verification/`) | Medium |

### Deterministic Quality Hooks (source: PROJ-123 restraint mechanisms, 2026-04-10)

These mechanisms are enforced by **scripts + hooks** (exit code driven), not behavioral rules. They physically block the action — the Strategist cannot bypass them without env var override.

| ID | Rule | Enforcement | Script |
|----|------|-------------|--------|
| `verification-evidence-required` | `gh pr create` blocked unless `/tmp/polaris-verified-{TICKET}.json` exists with valid ticket, timestamp (< 4h), and non-empty results | PreToolUse hook on Bash, exit 2 to block | `scripts/verification-evidence-gate.sh` |
| `quality-evidence-required` | `git commit` blocked unless `/tmp/polaris-quality-{branch}.json` exists with `all_passed: true`. Bypass: `POLARIS_SKIP_QUALITY=1` or `wip:` commit message prefix. Skipped for main/develop and framework repo | PreToolUse hook on Bash, exit 2 to block | `scripts/quality-gate.sh` |
| `test-sequence-warning` | When sequence test-fail → production-file-edit → test-pass is detected, inject warning about wrong-fix pattern | PostToolUse hook on Bash + Edit, stdout injection | `scripts/test-sequence-tracker.sh` |
| `context-pressure-monitor` | At 20/25/35 tool calls, inject escalating warnings to save state and delegate. Counts Bash/Edit/Write/Read/Grep/Glob/Agent calls. State: `/tmp/polaris-session-calls.txt`. Reset on reboot | PostToolUse hook, stdout injection (advisory, not blocking) | `scripts/context-pressure-monitor.sh` |
| `version-docs-lint-gate` | `git commit` blocked when VERSION is staged but `readme-lint.py` fails (phantom skills, count drift, undocumented skills). Bypass: `POLARIS_SKIP_DOCS_LINT=1`. Only fires in repos with VERSION file. Hook lives in `settings.json` with repo-detection logic (non-framework repos auto-skip) | PreToolUse hook on Bash, exit 2 to block | `.claude/hooks/version-docs-lint-gate.sh` |
| `no-hooks-in-local-settings` | `settings.local.json` must not contain a `hooks` key — shallow merge silently overrides all `settings.json` hooks. `/validate` check 10 warns; `polaris-sync.sh` deploy warns | `/validate` Mechanisms mode + `polaris-sync.sh` post-deploy check (advisory) | — |

For evidence file spec, writer script, bypass flags, and hook script reference — see `skills/references/mechanism-rationalizations.md` § Deterministic Quality Hooks — Detail.

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
| `version-bump-reminder` | After task completion, if committed files include `rules/` or `skills/` paths, remind user about version bump | Commit modifying `skills/` or `rules/` files followed by session end without version bump reminder | **Critical** |

#### Common Rationalizations — Version Bump Reminder

> See `skills/references/mechanism-rationalizations.md` § Common Rationalizations — Version Bump Reminder.

### Cross-Session Continuity (source: `CLAUDE.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `cross-session-read-memory-file` | When user says "繼續 X", search MEMORY.md index then READ the full memory file before responding | Strategist reports "memory lost" or "no details" when MEMORY.md index has a matching entry | High |
| `cross-session-confirm-context` | After reading memory file, present reconstructed context to user for confirmation | New session starts work without summarizing what was decided/done/next from previous session | Medium |

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
| `safety-gate-active` | `safety-gate.sh` PreToolUse hook must be configured in settings.json | Sub-agent executes dangerous bash pattern (reverse shell, pipe-to-shell) without hook block | High |
| `session-start-fast-check` | At conversation start, run git status/stash/branch check before responding | Session starts with WIP in working tree but no WIP report shown to user | High |
| `wip-branch-before-topic-switch` | When switching topics with uncommitted changes, commit WIP to a branch first | Unrelated changes mixed into a topic commit (files from previous work included in new commit) | High |

## Priority Audit Order

Post-task audit should check these first (highest drift risk, most impactful):

1. `no-workaround-accumulation` / `design-implementation-reconciliation`
1a. `design-plan-creation` / `design-plan-decision-capture` / `design-plan-reference-at-impl` (Critical — check-pr-approvals v2.10→v2.16 掉棒事件)
2. `skill-first-invoke` / `no-manual-skill-steps` / `reference-index-scan`
3. `api-docs-before-replace` / `lib-exhaust-before-replace` / `fix-through-not-revert` / `query-original-impl` (Critical — PROJ-123 root cause + library change protocol)
4. `delegate-exploration` / `delegate-implementation`
5. `cross-session-read-memory-file` / `cross-session-carry-forward`
6. `post-task-feedback-reflection` / `correction-driven-handbook-update` (correction = immediate trigger; repo-specific → handbook, framework → feedback)
6a. `checkpoint-mode-at-25` (check during long sessions, not just post-task)
7. `re-test-after-fix` / `fresh-verification-before-completion` / `checklist-before-done`
8. `cross-repo-verification` / `env-follows-requires`
9. `no-cd-in-bash` / `no-independent-cmd-chaining`
10. `feedback-trigger-count-update`
11. `version-bump-reminder` (Critical — 6 consecutive misses discovered 2026-04-09)
12. `verification-evidence-required` / `quality-evidence-required` / `test-sequence-warning` (deterministic hooks — low audit priority because hooks enforce automatically)
