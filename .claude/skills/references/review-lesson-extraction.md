# Review Lesson Extraction

Shared logic for extracting learnable patterns from PR review comments, deduplicating against existing knowledge, and writing directly to repo handbook sub-files.

Used by: `learning` (PR mode, Batch mode), `fix-pr-review` (Step 12.5)

## Sub-agent Prompt Template

Spawn sub-agents (`model: "sonnet"`) to extract patterns from merged PRs. Maximum 5 parallel sub-agents; batch if more.

```
You are analyzing a merged PR to extract learnable patterns from its review comments.

## PR Info
- Repo: {org}/{repo}
- PR: #<number>
- URL: https://github.com/{org}/{repo}/pull/<number>

## Your Task
1. Read the PR review comments: `gh api repos/{org}/{repo}/pulls/<number>/comments --paginate`
2. Read the review summaries: `gh api repos/{org}/{repo}/pulls/<number>/reviews --paginate`
3. Read the PR diff: `gh pr diff <number> --repo {org}/{repo}`
4. For each review comment that teaches something generalizable, extract:
   - The pattern/rule (what should be done)
   - Why it matters (from the reviewer's explanation or inferred from context)
   - The topic category (e.g., typescript-type-safety, error-handling, nuxt-ssr-caching, vitest-testing-patterns, naming-conventions, code-organization, vue-component-patterns, server-api-patterns)

## What to Extract
- Framework idiomatic patterns (Vue/Nuxt/TypeScript correct usage)
- Error handling conventions
- Type safety patterns
- Performance decisions
- Testing conventions
- Component design principles
- Architecture patterns
- Naming and code organization conventions

## What to Skip
- Typos, missing imports, copy-paste errors (one-off mistakes, not patterns)
- Pure formatting issues (handled by linters)
- One-off business-logic-specific comments (not generalizable)
- Nit-level style suggestions
- Comments that are questions or discussions without a clear conclusion
- "LGTM" or approval-only reviews with no substantive comments

## Return Format
Return a JSON array:
[
  {
    "rule": "Description of the pattern/rule",
    "why": "Why this matters",
    "topic": "topic-category-kebab-case",
    "source_pr": "https://github.com/{org}/{repo}/pull/<number>",
    "source_date": "YYYY-MM-DD"
  }
]
If no learnable patterns found, return an empty array [].
```

## Three-Layer Classification

Before writing any pattern, classify it into one of three layers:

| Layer | Scope | Write target |
|-------|-------|-------------|
| **Repo-specific** | Applies only to this repo's stack, architecture, or conventions | `{repo}/.claude/rules/handbook/` |
| **Company-level** | Applies across multiple repos in the same company | `rules/{company}/handbook/` |
| **Framework-level** | Applies across all companies and repos | Mark `[framework]`, write as feedback memory instead |

Reference `repo-handbook.md` Step 3b for the full three-layer classification logic. When in doubt, default to repo-specific — it is always safe to start narrow and promote later.

## Deduplication Logic

Before writing any lessons, load existing knowledge to avoid duplicates:

1. **Read all handbook sub-files** in `{base_dir}/<repo>/.claude/rules/handbook/*.md`
2. **Read all main rule files** in `{base_dir}/<repo>/.claude/rules/*.md` (excluding `handbook/` subdirectory)
3. Also check `{base_dir}/.claude/rules/*.md` (workspace-level rules)

For each extracted pattern, compare against existing lessons and rules:
- **Semantically identical** (same rule, same reasoning) → skip, count as duplicate
- **Related but adds a new angle** (same topic, different aspect) → keep, will be appended to existing topic file
- **Entirely new** → keep, will create a new topic file or append to the closest existing one

## Write Format

Write extracted patterns directly to `{base_dir}/<repo>/.claude/rules/handbook/`:

**File naming**: Topic-based, kebab-case `.md` files (e.g., `typescript-type-safety.md`, `error-handling.md`). Append to existing files of the same topic — do not create a new file if one with the matching topic already exists.

**Entry format** (each top-level `- ` counts as 1 entry):

```markdown
# {Topic Title}

- {Rule description — clear, actionable, generalizable}
  - Why: {reasoning from the reviewer or inferred from the fix}
  - Source: https://github.com/{org}/{repo}/pull/<number> (YYYY-MM-DD)
```

When appending to an existing file, add new entries after the last existing entry (before EOF). Do not modify existing entries.

> **Bootstrap note**: If the repo does not yet have a handbook directory, create it. The first lesson extraction for a repo bootstraps the handbook.

### Reverse Sync

After writing, reverse-sync the handbook back to ai-config (source of truth):

```bash
{base_dir}/polaris-sync.sh --reverse {project-name}
```

Where `{project-name}` is derived from the repo directory name (e.g., `acme-web-app`).
