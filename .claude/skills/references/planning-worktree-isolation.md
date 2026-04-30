# Planning Skill Worktree Isolation

Planning skills (refinement / breakdown / bug-triage / sasd-review) that run **runtime verification** — build, dev server, Lighthouse, curl SSR output, bug reproduction — must do so in a **dedicated git worktree**, never in the user's main checkout.

## Why

Planning skills increasingly need live signal beyond static code reading:

| Skill | Typical runtime verification |
|-------|------------------------------|
| refinement | Tier 2+ baseline measurements (Lighthouse, SSR timing, curl diff) |
| breakdown | Estimation sanity-check (run tests, measure scope via grep+build), infra-first AC rehearsal |
| bug-triage | Bug reproduction, stack inspection, confirming which branch exhibits defect |
| sasd-review | Technical feasibility probe (does the proposed API path work? does the config honor this option?) |

These operations typically:
- Modify `node_modules/` via `pnpm install` / `composer install`
- Occupy dev ports (3000/3001/…)
- Produce `.output/`, `dist/`, build artifacts
- Require checking out a specific ref (usually `origin/develop` or the feature branch)

**If the user's main checkout is on a WIP branch, any of the above directly interferes with their in-flight work.**

## Absolute Rules

**Never mutate the user's main checkout.** The user may be on any branch, with any amount of uncommitted/untracked work. The skill is **forbidden** to:

- ❌ `git checkout <branch>` — switches the main checkout's HEAD
- ❌ `git stash push` — touches the user's working tree
- ❌ `git pull` — updates the main checkout
- ❌ `pnpm install` / `pnpm build` / `pnpm serve` in the main checkout
- ❌ Multi-step workarounds like "stash first, then checkout develop, then create worktree"

`git worktree add` is itself an isolation primitive — it creates an independent checkout pointing at the specified ref; the main checkout's HEAD / index / working tree are completely untouched.

## Execution Flow

Replace `{skill}` with the actual skill name (`refinement` / `breakdown` / `bug-triage` / `sasd-review`) and `{TICKET_KEY}` with the ticket being processed.

### 1. Decide the base ref

| Skill context | Base ref |
|---------------|----------|
| refinement / breakdown Planning Path / sasd-review | `origin/develop` (or `origin/main`, per repo convention) |
| bug-triage for `[VERIFICATION_FAIL]` Bug | feature branch from the `[VERIFICATION_FAIL]` block (the branch that failed AC) |
| bug-triage for generic Bug | `origin/develop` unless user specifies otherwise |

### 2. Fetch (do not pull)

```bash
git -C {repo} fetch origin {base_ref}
```

### 3. Create worktree

```bash
git -C {repo} worktree add -B {skill}/{TICKET_KEY} \
  {base_dir}/.worktrees/{repo}-{skill}-{TICKET_KEY} origin/{base_ref}
```

The main checkout's state is completely unchanged after this command.

### 4. All subsequent bash uses the worktree path

```bash
pnpm -C {worktree_path} install
pnpm -C {worktree_path}/apps/main build
node {worktree_path}/apps/main/.output/server/index.mjs
curl http://localhost:3001/...
```

### 5. Cleanup after the skill finishes

```bash
git -C {repo} worktree remove {base_dir}/.worktrees/{repo}-{skill}-{TICKET_KEY}
git -C {repo} branch -D {skill}/{TICKET_KEY}
```

If the worktree has uncommitted exploratory changes (intended), commit them to the scratch branch first, or use `worktree remove --force`. Do not carry them back to the main checkout.

## Canary Signal (self-check)

Before any `git` / package-manager command, ask:

> "Will this change the HEAD / branch / working tree of the user's main checkout?"

- **Yes** → stop, retarget the command at the worktree path
- **No** (e.g., `worktree add`, `fetch`, read-only `log` / `diff`) → proceed

## Sub-agent Dispatch

When delegating runtime verification to a sub-agent:

- Prefer `isolation: "worktree"` in the Agent tool call (the platform creates a fresh worktree for the sub-agent), OR
- Pass the already-created worktree path explicitly in the prompt and state: "你的工作目錄是 `{worktree_path}`，所有檔案操作必須在此目錄下。不要使用原始 workspace 路徑 `{original_path}`。"

See `rules/sub-agent-delegation.md` § Worktree path translation.

## Exceptions (no worktree required)

Worktree isolation is **not** required when the skill only:

- Reads JIRA / Confluence / Slack via MCP
- Writes markdown / JSON artifacts to `{company_specs_dir}/{TICKET_KEY}/` (the spec folder is outside the repo checkout, so it's always safe)
- Runs static code reads (`Read`, `Grep`, `Glob`) against the main checkout — these don't mutate state

The worktree requirement kicks in the moment the skill needs to run `pnpm install`, build, start a server, or run tests.

## Tier Guidance per Skill

| Skill | Default | Upgrade to worktree when… |
|-------|---------|---------------------------|
| refinement | No worktree | Tier 2+ (need baseline Lighthouse / SSR timing / infra-level verification) |
| breakdown | No worktree | Planning Path needs to run tests/build to size tickets; infra-first decision requires rehearsal |
| bug-triage | No worktree | Need to start dev server to reproduce bug; `[VERIFICATION_FAIL]` Bug (feature branch checkout) |
| sasd-review | No worktree | Technical feasibility probe (does the module actually support option X? does endpoint actually return this shape?) |

If the answer to "do I need to run a build / server / install?" is yes, create the worktree — even for a single command. The cost of `worktree add` is seconds; the cost of corrupting the user's WIP is hours.
