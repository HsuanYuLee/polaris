# Sub-agent Delegation Rules

## Delegation Patterns

- When there are multiple independent improvement points, prefer running sub-agents in parallel to save time
- When deep investigation is needed (e.g., finding all files that violate a convention), use a sub-agent to avoid bloating the main conversation context
- **Worktree isolation for batch implementation**: each sub-agent in `work-on` batch mode Phase 2 must use `isolation: "worktree"` to prevent file overwrites or git conflicts during parallel development. Not required for single-ticket sub-agents, but recommended when multiple files are changed
- **Plan-first**: before a sub-agent writes any code, if the estimated impact exceeds 3 files or requires an architectural decision (create new vs. extend existing component, cross-module changes), enter Plan mode and produce an implementation plan before executing
- **Explore-then-Implement**: when scanning the codebase, use the adaptive exploration mode from `skills/references/explore-pattern.md`. Goal: keep the implementation phase's context window clean
- **Sub-agent Talent Pool**: all sub-agent dispatching should reference the role definitions in `skills/references/sub-agent-roles.md`

## Model Tiers

When launching a sub-agent, specify the model based on task type to balance cost and quality. Planning decisions (SA/SD design, Epic breakdown strategy, scope challenge) stay with the main agent (Opus) and are not delegated:

| Task Type | model parameter | Examples |
|-----------|----------------|---------|
| **Explore / Analyze** | `"sonnet"` | Explore subagent, PR review, code analysis, Phase 1 ticket analysis |
| **Execute / Fix** | `"sonnet"` | Implementation sub-agent, fix-pr-review worktree, CI fixes, rebase conflict |
| **JIRA template operations** | `"haiku"` | Batch create sub-tasks, batch create tickets, readiness checklist comparison |

> See `skills/references/sub-agent-roles.md` for the full role definitions.

## Operational Rules

- **Prefer local repo for reading files**: when `{base_dir}/<repo>` exists, sub-agents must use the Read tool or local git commands to read files — do not use `gh api repos/.../contents/` for remote reads. Remote mode is only a fallback when no local clone exists
- **Verify permissions before batch operations**: before launching multiple parallel sub-agents (e.g., batch PR review, cross-repo PR creation), run one complete cycle with a single sub-agent to confirm bash permissions are correct, then launch the rest
- **Worktree for operations requiring isolation**: operations like fix-pr-review that must not affect the current development branch should use `isolation: "worktree"`. Note: project-level `settings.local.json` project-specific patterns are not available inside a worktree
- **General permissions go in user-level `~/.claude/settings.json`**: sub-agents running in sub-projects or worktrees fall back to user-level settings

## Known Platform Limitations

- **Sub-agents cannot call the Skill tool**: sub-agents must read `SKILL.md` files directly and execute the steps inline. This means updates to a skill's SKILL.md are picked up automatically (sub-agents read the current version), but the execution is duplicated rather than delegated. Not a bug — this is a Claude Code platform constraint
- **"Plan mode" is prompt-level, not Claude Code native**: when rules say "enter Plan mode", this means the Strategist instructs the sub-agent to produce a plan before coding — it does NOT refer to Claude Code's built-in `--plan` flag. Consider adopting native plan mode for large-impact sub-agent tasks (> 3 files) in future versions
