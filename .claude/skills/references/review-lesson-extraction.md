# Review Lesson Extraction

Shared logic for extracting learnable patterns from PR review comments, deduplicating against existing knowledge, and writing to review-lessons files.

Used by: `learning` (PR mode, Batch mode), `review-pr` (Step 6.5)

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

## Deduplication Logic

Before writing any lessons, load existing knowledge to avoid duplicates:

1. **Read all review-lesson files** in `{base_dir}/<repo>/.claude/rules/review-lessons/*.md`
2. **Read all main rule files** in `{base_dir}/<repo>/.claude/rules/*.md` (excluding `review-lessons/` subdirectory)
3. Also check `{base_dir}/.claude/rules/*.md` (workspace-level rules)

For each extracted pattern, compare against existing lessons and rules:
- **Semantically identical** (same rule, same reasoning) → skip, count as duplicate
- **Related but adds a new angle** (same topic, different aspect) → keep, will be appended to existing topic file
- **Entirely new** → keep, will create a new topic file or append to the closest existing one

## Write Format

Write extracted patterns to `{base_dir}/<repo>/.claude/rules/review-lessons/` :

**File naming**: Topic-based, kebab-case `.md` files (e.g., `typescript-type-safety.md`, `error-handling.md`). Append to existing files of the same topic — do not create a new file if one with the matching topic already exists.

**Entry format** (each top-level `- ` counts as 1 entry):

```markdown
# {Topic Title}

- {Rule description — clear, actionable, generalizable}
  - Why: {reasoning from the reviewer or inferred from the fix}
  - Source: https://github.com/{org}/{repo}/pull/<number> (YYYY-MM-DD)
```

When appending to an existing file, add new entries after the last existing entry (before EOF). Do not modify existing entries.

### Reverse Sync

After writing, reverse-sync review-lessons back to ai-config (source of truth):

```bash
{base_dir}/polaris-sync.sh --reverse {project-name}
```

Where `{project-name}` is derived from the repo directory name (e.g., `acme-web-app`).

## Graduation Check

After extraction, check whether graduation should trigger:

| Mode | Condition | Action |
|------|-----------|--------|
| **PR mode** (incremental) | Count total `^- ` lines across all review-lesson files in the repo. If >= 15 → trigger | `Invoke review-lessons-graduation to consolidate review-lessons in <repo>.` |
| **PR mode** (below threshold) | Count < 15 | Report: "目前 {repo} 有 X 條 review-lessons，累積到 15 條後會自動觸發 graduation。" |
| **Batch mode** | Always trigger (batch is designed to fill the pipeline) | `Invoke review-lessons-graduation for {repo} (manual trigger — includes Step 2.5 semantic grouping).` |
