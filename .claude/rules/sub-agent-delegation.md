# Sub-agent Delegation Rules

> For model tiers, decision classification (T1/T2/T3), self-regulation scoring, pipeline restore points, fan-in validation, write isolation model, known platform limitations, and safety hook configuration — see `skills/references/sub-agent-reference.md`.

## Delegation Patterns

- When there are multiple independent improvement points, prefer running sub-agents in parallel to save time
- When deep investigation is needed (e.g., finding all files that violate a convention), use a sub-agent to avoid bloating the main conversation context
- **Plan-first**: before a sub-agent writes any code, if the estimated impact exceeds 3 files or requires an architectural decision (create new vs. extend existing component, cross-module changes), enter Plan mode and produce an implementation plan before executing
- **Explore-then-Implement**: when scanning the codebase, use the adaptive exploration mode from `skills/references/explore-pattern.md`. Goal: keep the implementation phase's context window clean
- **Sub-agent Talent Pool**: all sub-agent dispatching should reference the role definitions in `skills/references/sub-agent-roles.md`
- **Runtime claims require runtime evidence**: when a sub-agent's analysis concludes something about runtime behavior (HTML output location, API response format, rendering result, framework default behavior), the Strategist must verify with actual execution (curl, dev server, test run) before adopting the conclusion. Source code analysis is a hypothesis, not evidence — frameworks have plugins, configs, and runtime overrides that change behavior. This applies even when the sub-agent's reasoning sounds plausible

## Operational Rules

- **Prefer local repo for reading files**: when `{base_dir}/<repo>` exists, sub-agents must use the Read tool or local git commands to read files — do not use `gh api repos/.../contents/` for remote reads. Remote mode is only a fallback when no local clone exists
- **Verify permissions before batch operations**: before launching multiple parallel sub-agents (e.g., batch PR review, cross-repo PR creation), run one complete cycle with a single sub-agent to confirm bash permissions are correct, then launch the rest
- **All code changes = worktree (universal default)**: any operation that writes to source files (Edit, Write, Bash with sed/patch/etc.) or changes git state (checkout, switch, pull rebase, stash+switch) must run inside a `git worktree add` copy. This applies to **all repos** including the framework repo — there is no "stay on current branch" exception. Assume the user's main checkout always has parallel WIP (editing, dev server, another session) that must not be disturbed. Applies to Strategist, all skills, and all sub-agents. Exceptions: read-only inspection (`git show <branch>:path`, `gh api`, Read, Grep, Glob), pure JIRA/Confluence/Slack operations, and memory/todo/plan file edits (these are session state, not source code). Worktree path convention: `{base_dir}/.worktrees/{repo}-{purpose}-{ticket_or_topic}`. Cleanup with `git worktree remove` + delete temp branch after done
- **Worktree for operations requiring isolation**: specific applications of the universal rule — `engineering` batch mode Phase 2 sub-agents use `isolation: "worktree"`; `engineering` revision mode uses worktree; planning skills Tier 2+ (refinement, breakdown, sasd-review, bug-triage 復現) use worktree before running `pnpm install`/build/dev server. Note: project-level `settings.local.json` project-specific patterns are not available inside a worktree
- **Worktree path translation**: when a sub-agent runs in a worktree, file paths from the parent context (e.g., `{base_dir}/repo/src/...`) point to the original workspace, not the worktree copy. The dispatch prompt must explicitly state: "你的工作目錄是 `{worktree_path}`，所有檔案操作必須在此目錄下。不要使用原始 workspace 路徑 `{original_path}`。" This prevents the sub-agent from accidentally reading/writing files in the wrong workspace
- **General permissions go in user-level `~/.claude/settings.json`**: sub-agents running in sub-projects or worktrees fall back to user-level settings
