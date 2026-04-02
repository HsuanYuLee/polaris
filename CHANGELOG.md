# Changelog

All notable changes to Polaris are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/).

> Versions before 1.4.0 were retroactively tagged during the initial development sprint.

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
