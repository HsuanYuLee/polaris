# Changelog

All notable changes to Polaris are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/).

> Versions before 1.4.0 were retroactively tagged during the initial development sprint.

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
