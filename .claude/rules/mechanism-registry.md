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

### Delegation (source: `CLAUDE.md`, `rules/sub-agent-delegation.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `delegate-exploration` | > 3 files → dispatch Explorer sub-agent | > 5 consecutive Read/Grep in main session without conclusion | High |
| `delegate-implementation` | Multi-file edits → dispatch Implementer sub-agent | Edit/Write in main session across > 1 file (unless ≤ 3 lines) | High |
| `plan-first-large-scope` | > 3 files or arch decision → plan before code | Sub-agent producing 4+ file changes without prior plan | High |
| `model-tier-selection` | sonnet for explore/execute, haiku for JIRA batch ops | JIRA batch sub-agent using sonnet; explore sub-agent with no model specified | Low |
| `worktree-for-batch-impl` | Batch mode Phase 2 sub-agents use `isolation: "worktree"` | Parallel implementation sub-agents without worktree isolation | Medium |
| `subagent-completion-envelope` | All sub-agents must return Status/Artifacts/Summary envelope | Sub-agent return without structured Status line | Medium |

### Feedback & Memory (source: `rules/feedback-and-memory.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `post-task-feedback-reflection` | After task completion, silently reflect for corrections/blocks/confirmations | Task ends with no reflection when user corrected behavior or command self-corrected | High |
| `feedback-pre-write-dedup` | Before creating feedback memory, scan for semantic overlap and merge if found | New feedback file created when an existing entry covers the same topic | High |
| `feedback-trigger-count-update` | After using a feedback memory, increment trigger_count (once per conversation) | Feedback memory trigger_count unchanged after conversation that referenced it | High |
| `graduation-at-three-triggers` | trigger_count >= 3 → initiate graduation to rule | Feedback memory with count >= 3 still existing without graduation proposal | High |
| `feedback-backlog-classification` | New feedback memory that describes a framework gap must also write a backlog entry | FRAMEWORK_GAP feedback created without corresponding `polaris-backlog.md` entry | Medium |
| `memory-company-hard-skip` | Skip memories with mismatched company field | Company-scoped memory applied to a different company's work | Medium |

### Context Management (source: `rules/context-monitoring.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `max-five-consecutive-reads` | Max 5 Read/Grep calls before conclusion or delegation | 6+ consecutive Read/Grep without intervening conclusion | High |
| `no-file-reread` | Don't read same file > 2 times unless modified | Same file path in > 2 Read calls in one conversation | Medium |
| `post-compression-company-context` | After compression, re-confirm active company | Work continues post-compression without company context check | High |
| `proactive-context-check-at-20` | After 20+ tool calls without milestone, proactively save state and assess delegation | Long conversation without milestone summary or delegation assessment | Medium |

### Bash Execution (source: `rules/bash-command-splitting.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `no-cd-in-bash` | Never use `cd` in Bash; use tool path parameters | `cd ` appearing in any Bash command | High |
| `no-independent-cmd-chaining` | Don't chain independent commands with `&&` | Multiple independent commands joined by `&&` in one Bash call | High |

### Company Isolation (source: `rules/multi-company-isolation.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `scope-header-enforcement` | Company rule files must have `Scope:` header | File under `rules/{company}/` without scope header | Medium |

### Quality Gates (source: `skills/git-pr-workflow/SKILL.md`, `skills/verify-completion/SKILL.md`)

| ID | Rule | Canary Signal | Drift |
|----|------|---------------|-------|
| `re-test-after-fix` | After fixing quality issues, re-run all tests before proceeding to commit | Git diff shows changes after last test run but commit proceeds without fresh test output | High |
| `fresh-verification-before-completion` | Every task completion must include fresh verification performed after the final code change | Task marked complete with rationalization phrases ("should work", "trivial change") and no verification output in conversation | High |

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
| `docs-sync-on-version-bump` | After VERSION bump commit, run docs-sync before sync-to-polaris | VERSION bumped and pushed without docs-sync invocation | High |

## Priority Audit Order

Post-task audit should check these first (highest drift risk, most impactful):

1. `skill-first-invoke` / `no-manual-skill-steps`
2. `delegate-exploration` / `delegate-implementation`
3. `post-task-feedback-reflection`
4. `re-test-after-fix` / `fresh-verification-before-completion`
5. `no-cd-in-bash` / `no-independent-cmd-chaining`
6. `feedback-trigger-count-update` / `graduation-at-three-triggers`
