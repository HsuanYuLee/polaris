# Changelog

All notable changes to Polaris are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/).

> Versions before 1.4.0 were retroactively tagged during the initial development sprint.

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
