# Sub-Agent Reference

> **When to load**: when dispatching sub-agents and needing model tier guidance, T1/T2/T3 decision classification, self-regulation scoring, restore points, fan-in validation, write isolation model, or safety hook configuration. Extracted from `rules/sub-agent-delegation.md`. Loaded on-demand.

## Model Tiers

When launching a sub-agent, specify the model based on task type to balance cost and quality. Planning decisions (SA/SD design, Epic breakdown strategy, scope challenge) stay with the main agent and are not delegated:

| Task Type | model parameter | Examples |
|-----------|----------------|---------|
| **Explore / Analyze** | `"sonnet"` | Explore subagent, PR review, code analysis, Phase 1 ticket analysis |
| **Execute / Fix** | `"sonnet"` | Implementation sub-agent, engineering revision mode, CI fixes, rebase conflict |
| **JIRA template operations** | `"haiku"` | Batch create sub-tasks, batch create tickets, readiness checklist comparison |

> See `skills/references/sub-agent-roles.md` for dispatch standards (Completion Envelope, model tiers), specialized protocols (QA Challenger, Architect Challenger, Critic), and common prompt patterns.

## Decision Classification

When a sub-agent encounters a decision point during planning or implementation, classify it into one of three tiers:

| Tier | Name | When to use | Action |
|------|------|-------------|--------|
| **T1** | Mechanical | Single correct answer derivable from code/config/conventions | Decide automatically, no confirmation needed |
| **T2** | Taste | Multiple valid approaches, guided by project principles | Choose the approach most aligned with existing patterns, note the decision in the plan, proceed without asking |
| **T3** | User-challenge | Irreversible, cross-module, or involves a tradeoff the user hasn't expressed preference on | Stop and ask the user before proceeding |

### Examples

| Decision | Tier | Reasoning |
|----------|------|-----------|
| Which test framework to use | T1 | Read package.json — one correct answer |
| File naming convention | T1 | Follow existing repo patterns |
| Component structure (single file vs split) | T2 | Multiple valid approaches — pick what matches neighbors |
| API response format (REST vs GraphQL) | T3 | Architectural, irreversible, user preference unknown |
| Delete vs deprecate a module | T3 | Irreversible, affects other teams |
| Add error handling style (try/catch vs Result type) | T2 | Follow existing codebase convention |

### Escalation bias

When uncertain between T2 and T3, prefer T2 (decide and note) over T3 (stop and ask). Unnecessary confirmation requests slow down the workflow more than a suboptimal-but-reversible choice. The key question: "Can this be easily changed later?" If yes → T2. If no → T3.

## Self-Regulation Scoring

Sub-agents performing implementation work should maintain a mental "risk score" that accumulates as they make changes. When the score exceeds a threshold, they must stop and report back to the Strategist rather than continuing.

### Risk Score Accumulation

| Event | Score Impact |
|-------|-------------|
| Each file modified | +5% |
| Reverting a previous change | +15% |
| Modifying a file not in the original plan | +15% |
| Modifying a file outside task.md Allowed Files list | +15% |
| Fixing a test that broke due to own changes | +10% |
| Third consecutive edit to the same file | +10% |
| Change touches cross-module boundary | +10% |

### Thresholds

| Score | Action |
|-------|--------|
| < 20% | Continue normally |
| 20-35% | Add a caution note to the return summary |
| > 35% | **Stop immediately.** Return to the Strategist with: current state, what was attempted, what went wrong, and a recommendation for how to proceed |

### Why this matters

AI agents have a tendency to "push through" problems — making fix-on-fix-on-fix changes that compound errors. A human developer would step back and reconsider after the second unexpected failure. This scoring mechanism simulates that instinct. The numbers are approximate — the key behavior is to stop digging when the hole gets deep.

## Pipeline Restore Points

Long-running skills that modify code must create a restore point before starting. This allows clean rollback if the pipeline fails partway through.

### When to create a restore point

Before a sub-agent begins implementation work (Phase 2 of engineering, git-pr-workflow quality fixes), if there are uncommitted changes in the working tree:

1. Run `git stash push -m "polaris-restore-{ticket}-{timestamp}"`
2. Record the stash ref in the sub-agent's context
3. Proceed with implementation

If the working tree is clean (no uncommitted changes), skip the stash — the current HEAD commit is the implicit restore point.

### When to restore

If the sub-agent triggers a self-regulation stop (score > 35%) or encounters an unrecoverable error:

1. `git checkout -- .` to discard all uncommitted changes
2. If a stash was created, `git stash pop` to restore the pre-pipeline state
3. Report the failure to the Strategist with the restore point info

### Scope

| Skill | Restore point location |
|-------|----------------------|
| `engineering` Phase 2 | Before implementation sub-agent starts coding |
| `engineering` revision mode | Before applying review fixes |
| `git-pr-workflow` | Before quality-fix loop starts |

Skills that only read data (my-triage, standup, review-pr analysis phase) do not need restore points.

## Fan-In Validation

When the Strategist dispatches multiple parallel sub-agents and needs to synthesize their results, validate all completion envelopes before proceeding. This prevents silent partial failures from corrupting synthesis.

### Validation steps

1. **Before dispatch**: record the expected agent set (e.g., `expected: ["explorer_a", "explorer_b", "critic"]`)
2. **On each return**: check the completion envelope:
   - `Status` must be present (`DONE`, `BLOCKED`, or `PARTIAL`)
   - `Artifacts` must be non-empty for `DONE` status (otherwise the agent returned "success" with no output)
   - `Summary` must be present and non-trivial (not just "done")
3. **Before synthesis**: verify all expected agents have returned. If any is missing or returned `BLOCKED`/`PARTIAL`:
   - Missing → report to user, do not synthesize with incomplete data
   - `BLOCKED` → read the `Blocker:` line, decide whether to retry or escalate
   - `PARTIAL` → read the `Remaining:` line, decide whether partial data is sufficient for synthesis

### Why this matters

The real risk in parallel sub-agent execution is not "agent didn't return" (Claude Code's Agent tool blocks until return) — it's "agent returned `DONE` with empty or garbage content." The envelope validation catches this before the Strategist builds conclusions on incomplete data.

## Write Isolation Model

Three tiers of isolation for sub-agent file operations, ordered by increasing safety:

| Tier | Mechanism | When to Use | Tradeoff |
|------|-----------|-------------|----------|
| **Shared** | Sub-agent writes directly to the current workspace | Single sub-agent, ≤ 3 files, sequential execution | Fast, but conflicts if multiple agents write simultaneously |
| **Worktree** | `isolation: "worktree"` — Claude Code creates a temporary git worktree | Parallel implementation sub-agents, batch mode, any operation that must not affect the current branch | Safe from conflicts; worktree auto-cleaned if no changes. Path translation required (see `rules/sub-agent-delegation.md` § Operational Rules) |
| **Cross-repo** | Sub-agent operates on a different local repo (e.g., `{base_dir}/other-repo`) | Changes span multiple repositories (e.g., API + consumer) | Each repo is independently safe; cross-repo atomicity depends on PR coordination |

### Selection Guide

```
Single sub-agent, small change?  → Shared
Parallel sub-agents?             → Worktree (mandatory for batch mode Phase 2)
Fix-pr-review on non-current branch? → Worktree
Multiple repos?                  → Cross-repo + worktree per repo if parallel
```

### Future: Per-Agent Write Buffer

Inspired by LangGraph's per-task write buffer + atomic merge pattern. Currently blocked on Claude Code platform support for per-agent tool restrictions. When available, each sub-agent would write to an isolated buffer, and the Strategist would review + merge atomically. Tracked in backlog as "Per-agent isolation config in frontmatter."

## Known Platform Limitations

- **Sub-agents cannot call the Skill tool**: sub-agents must read `SKILL.md` files directly and execute the steps inline. This means updates to a skill's SKILL.md are picked up automatically (sub-agents read the current version), but the execution is duplicated rather than delegated. Not a bug — this is a Claude Code platform constraint
- **"Plan mode" is prompt-level, not Claude Code native**: when rules say "enter Plan mode", this means the Strategist instructs the sub-agent to produce a plan before coding — it does NOT refer to Claude Code's built-in `--plan` flag. Consider adopting native plan mode for large-impact sub-agent tasks (> 3 files) in future versions

## Safety Hooks

`scripts/safety-gate.sh` provides deterministic enforcement against dangerous operations. Configure it as a PreToolUse hook in `settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|Bash",
        "command": "POLARIS_SAFE_DIRS=\"/path/to/repo\" /path/to/scripts/safety-gate.sh"
      }
    ]
  }
}
```

The script blocks:
- **Edit/Write** to files outside `POLARIS_SAFE_DIRS` (if set)
- **Bash** commands matching dangerous patterns (rm -rf /, git push --force main, DROP TABLE, etc.)

This is especially important for sub-agents which may operate with less contextual judgment than the main Strategist session. The hook fires deterministically — no prompt-level instruction can bypass it.
