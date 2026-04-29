# Cross-Session Learnings

A JSONL knowledge base that accumulates insights across conversations. Each entry captures something non-obvious learned during a task — patterns, pitfalls, preferences, architecture decisions, or tool usage.

## Why This Exists

Claude Code conversations start with a blank slate (beyond CLAUDE.md and rules). Memory files capture behavioral rules, but **project-specific technical knowledge** (e.g., "this repo's tests need `--forceExit`", "the payment module has a circular dependency with auth") gets lost between sessions. Learnings bridge that gap.

## Entry Schema

```jsonl
{"key":"vue-ref-setup","type":"pattern","content":"Vue composables must call useRoute() at setup top-level, not inside callbacks","confidence":8,"source":"PR #2049 review","company":"acme","created":"2026-04-01","last_confirmed":"2026-04-01"}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | string | yes | Short kebab-case identifier for dedup (e.g., `vitest-force-exit`) |
| `type` | enum | yes | `pattern` / `pitfall` / `preference` / `architecture` / `tool` |
| `content` | string | yes | The learning — one or two sentences, actionable |
| `confidence` | int | yes | 1-10, initial value set by writer |
| `source` | string | yes | Where it was learned (PR number, ticket, conversation context) |
| `company` | string | no | Company scope (omit for workspace-wide learnings) |
| `created` | date | yes | ISO date of creation |
| `last_confirmed` | date | yes | ISO date of last confirmation/use |

### Types

| Type | When to use | Example |
|------|-------------|---------|
| `pattern` | Recurring code/workflow pattern that works | "Nuxt 3 server routes need `defineEventHandler` wrapper" |
| `pitfall` | Something that breaks unexpectedly | "Running vitest in monorepo root picks up wrong config" |
| `preference` | User or team preference not in rules | "This team prefers named exports over default exports" |
| `architecture` | Structural decision or constraint | "Payment module depends on auth via event bus, not direct import" |
| `tool` | CLI/tool usage insight | "gh pr merge needs --delete-branch to clean up remote" |

## Confidence Decay

Confidence decays over time to surface fresh, relevant knowledge:

```
effective_confidence = confidence - floor((today - last_confirmed) / 30)
```

- Decays 1 point per 30 days since last confirmed
- Minimum effective confidence: 0 (entry becomes invisible but not deleted)
- **Confirmation** resets `last_confirmed` to today and optionally boosts `confidence`

## Dedup Rules

When adding a new entry:
1. Check if an entry with the same `key` AND `type` exists
2. If found: **merge** — update `content` (if new content provided), set `confidence` to max(existing, new), update `last_confirmed` to today
3. If not found: append new entry

## Preamble Injection

At conversation start (or after context compression), the Strategist should:

1. Run `polaris-learnings.sh query --top 5 --min-confidence 3`
2. If results exist, mentally note them as project context (do not output to user unless asked)
3. Use these learnings to inform decisions throughout the conversation

The top 5 are selected by effective confidence (after decay), filtered by active company context.

## When to Write Learnings

Integrated into the post-task reflection (see `rules/feedback-and-memory.md`):

| Signal | Action |
|--------|--------|
| A non-obvious technical fact was discovered during the task | Write a `pattern` or `architecture` entry |
| A command/approach failed unexpectedly | Write a `pitfall` entry |
| User corrected a technical assumption (not a behavioral preference) | Write a `pitfall` or `pattern` entry |
| User expressed a technical preference not covered by rules | Write a `preference` entry |
| A tool trick or CLI flag made a difference | Write a `tool` entry |

**Constraints:**
- At most 2 learnings per task (avoid noise)
- Only write when the insight is **non-obvious** — don't record things derivable from package.json, README, or existing rules
- Learnings are NOT feedback memories — feedback captures behavioral corrections for the Strategist; learnings capture technical knowledge about the codebase/tools

## Pipeline Learning Tags

In addition to the five general types above, the learning pipeline supports **tagged entries** that carry structured metadata and flow into specific handbook targets. Tagged entries use one of the general types (typically `pitfall` or `pattern`) but add a `tag` field and structured `metadata` for downstream processing.

### `plan-gap` Tag

Captures plan/spec deficiencies discovered during engineering revision mode (D3/D7 of DP-002). When a PR review reveals that the original plan missed something, the user fills in "why the plan missed this" — that reason becomes a learning entry.

**Write timing**: engineering revision mode detects plan gap or spec issue → user confirms rollback and provides gap reason (R3a in engineering SKILL.md).

**Entry schema** (extends base JSONL entry):

```jsonl
{"key":"plan-gap-missing-i18n-edge","type":"pitfall","content":"Breakdown missed i18n plural forms — AC only covered singular","confidence":7,"source":"GT-521 PR #2088","company":"kkday","created":"2026-04-15","last_confirmed":"2026-04-15","tag":"plan-gap","metadata":{"subtag":"breakdown","ticket":"GT-521","pr_url":"https://github.com/kkday-it/b2c-web/pull/2088","reviewer_signal":"Reviewer pointed out plural forms break in zh-TW","gap_reason":"Breakdown AC template has no i18n pluralization check","classification":"plan_gap"}}
```

| Metadata field | Type | Required | Description |
|----------------|------|----------|-------------|
| `subtag` | `"refinement"` \| `"breakdown"` \| `"epic"` | yes | Which upstream stage had the gap |
| `ticket` | string | yes | JIRA ticket key where the gap was found |
| `pr_url` | string | yes | PR that surfaced the gap |
| `reviewer_signal` | string | yes | One-line summary of what the reviewer pointed out |
| `gap_reason` | string | yes | User's answer to "why did the plan miss this?" |
| `classification` | `"plan_gap"` \| `"spec_issue"` | yes | `plan_gap` = plan missed a case; `spec_issue` = AC itself was wrong |

**Handbook flow target**:
- `subtag: "refinement"` or `subtag: "epic"` → refinement checklist (future `skills/references/refinement-checklist.md` or inline section in refinement SKILL.md)
- `subtag: "breakdown"` → breakdown checklist (future `skills/references/breakdown-checklist.md` or inline section in breakdown SKILL.md)

### `review-lesson` Tag

Captures coding patterns and conventions learned from PR review comments during engineering revision mode (R6 in engineering SKILL.md). Unlike `review-lesson-extraction.md` (which writes directly to handbook during `/learning` or engineering revision mode), this tag queues the lesson for batch promotion — appropriate when the lesson needs accumulation evidence before becoming a handbook rule.

**Write timing**: engineering revision mode completes code drift fix → extracts lesson from review comment → writes to learning queue.

**Entry schema** (extends base JSONL entry):

```jsonl
{"key":"review-lesson-server-route-error-handling","type":"pattern","content":"Nuxt server routes must return { statusCode, body } on error, not throw createError()","confidence":6,"source":"KB2CW-3788 PR #2102","company":"kkday","created":"2026-04-15","last_confirmed":"2026-04-15","tag":"review-lesson","metadata":{"ticket":"KB2CW-3788","pr_url":"https://github.com/kkday-it/b2c-web/pull/2102","review_comment":"createError() in server routes causes unhandled rejection in production","lesson":"Nuxt server routes must return error objects, not throw createError()","repo":"kkday-it/b2c-web","file_path":"server/api/product/detail.ts"}}
```

| Metadata field | Type | Required | Description |
|----------------|------|----------|-------------|
| `ticket` | string | yes | JIRA ticket key |
| `pr_url` | string | yes | PR where the review comment appeared |
| `review_comment` | string | yes | Reviewer's original comment (abbreviated) |
| `lesson` | string | yes | Generalized handbook entry draft extracted from the comment |
| `repo` | string | yes | `owner/repo` format |
| `file_path` | string | no | File path that triggered the comment (for grouping) |

**Handbook flow target**: repo-level handbook at `{repo}/.claude/rules/handbook/` — the specific sub-file is determined by the `lesson` topic (e.g., error-handling → `error-handling.md`).

### Relationship to `review-lesson-extraction.md`

Two distinct pathways exist for review lessons:

| Pathway | Trigger | Write target | When to use |
|---------|---------|-------------|-------------|
| **Direct write** (`review-lesson-extraction.md`) | `/learning` PR mode, batch PR scan | Immediately writes to repo handbook | High-confidence patterns from merged PRs with clear reviewer consensus |
| **Queue + promote** (`review-lesson` tag) | engineering revision mode R6 | Learning queue → promoted to handbook when confirmed | Single-PR observations that need accumulation before becoming rules |

The two pathways are complementary. Direct write handles batch extraction from historical PRs. The queue pathway handles real-time, incremental lesson capture during active development. A lesson that enters the queue and later appears in a batch extraction is deduplicated by the standard `key` + `type` merge logic.

## Promotion Pipeline (Tagged Entries)

Tagged learning entries (`plan-gap`, `review-lesson`) accumulate in the JSONL knowledge base and are promoted into handbook/checklist entries when confirmed as valid patterns. No fixed threshold — promote when the pattern is clearly established (multiple entries pointing to the same blind spot, or user confirms the pattern).

### Promotion Triggers

| Trigger | Mechanism | Scope |
|---------|-----------|-------|
| **Manual trigger** | User runs `/learning --promote plan-gap` or `/learning --promote review-lesson` | Specified tag |
| **On-write check** | When a new tagged entry is written, check if related entries form a clear pattern | The newly-written tag |

### Promotion Flow

1. **Identify candidates**: query learning entries by tag, group by promotion key:
   - `plan-gap`: group by `metadata.subtag`
   - `review-lesson`: group by `metadata.repo` + lesson topic similarity
2. **Present to user**: "These N learnings point to the same blind spot. Proposed handbook/checklist entry: {draft}. Confirm?"
3. **User confirms** → write to target:
   - `plan-gap` → append checklist item to the appropriate refinement/breakdown reference (create the reference file if it doesn't exist yet)
   - `review-lesson` → append entry to repo handbook sub-file (following `review-lesson-extraction.md` write format)
4. **Mark promoted**: add `"promoted": true` and `"promoted_to": "{target_file_path}"` to each promoted entry. Promoted entries remain in the JSONL file (for audit trail) but are excluded from future promotion scans and `query` results.

### Promoted Entry Schema Extension

```jsonl
{"key":"...","type":"...","tag":"plan-gap","promoted":true,"promoted_to":"skills/references/refinement-checklist.md","promoted_at":"2026-05-01",...}
```

| Field | Type | Description |
|-------|------|-------------|
| `promoted` | boolean | `true` when the entry has been promoted to a handbook/checklist |
| `promoted_to` | string | Relative path of the target file the entry was promoted into |
| `promoted_at` | date | ISO date of promotion |

### Handbook Write Targets (Summary)

| Tag | Subtag / Grouping | Target | Notes |
|-----|-------------------|--------|-------|
| `plan-gap` | `subtag: "refinement"` | `skills/references/refinement-checklist.md` | Checklist items for refinement quality gates |
| `plan-gap` | `subtag: "breakdown"` | `skills/references/breakdown-checklist.md` | Checklist items for breakdown quality gates |
| `plan-gap` | `subtag: "epic"` | `skills/references/refinement-checklist.md` | Epic-level gaps typically originate in refinement |
| `review-lesson` | `repo` + topic | `{repo}/.claude/rules/handbook/{topic}.md` | Repo-specific coding conventions |

**Note**: `refinement-checklist.md` and `breakdown-checklist.md` do not need to exist yet. They will be created on first promotion.

## Script Interface

See `scripts/polaris-learnings.sh` for the CLI:

```bash
# Add or merge a learning
polaris-learnings.sh add --key "vue-ref-setup" --type pattern \
  --content "Vue composables must call useRoute() at setup top-level" \
  --confidence 8 --source "PR #2049"

# Query top N entries by effective confidence (decay applied)
polaris-learnings.sh query --top 5 --min-confidence 3

# Semantic query (vector similarity) — requires reindex first
polaris-learnings.sh query --semantic "how do Vue composables work?" --top 5

# Confirm an entry (reset decay)
polaris-learnings.sh confirm --key "vue-ref-setup"

# List all entries with effective confidence
polaris-learnings.sh list

# Build or refresh the semantic embeddings index
polaris-learnings.sh reindex           # only re-embed changed/new entries
polaris-learnings.sh reindex --force   # rebuild all vectors
```

Environment variables:
- `POLARIS_WORKSPACE_ROOT` — workspace root path (required)
- `POLARIS_PROJECT_SLUG` — override slug (optional)
- `POLARIS_COMPANY` — filter by company (optional, used by query; applies to both confidence and semantic modes)
- `POLARIS_VENV` — Python venv for semantic query (default: `~/.polaris/venv`)
- `POLARIS_EMBED_MODEL` — embedding model (default: `sentence-transformers/all-MiniLM-L6-v2`, 384-dim)

## Semantic Query (DP-024 P3)

`query --semantic "text"` finds entries by vector similarity rather than key match — useful when you remember the concept but not the slug (e.g., "hydration bug" finds `ssr-client-mismatch` without the exact key).

**Setup (one-time):**

```bash
scripts/polaris-embed-setup.sh     # creates ~/.polaris/venv and installs fastembed
polaris-learnings.sh reindex       # builds ~/.polaris/projects/{slug}/embeddings.json
```

**Storage:** `~/.polaris/projects/{slug}/embeddings.json` — one record per `{key}::{type}` with `embedding_model`, `embedding_version`, `text_hash` (sha256 of content, first 16 hex chars), and `vector` (JSON array, 384 float32 for the default model).

**Model versioning:** each index record stores its model+version. `reindex` re-embeds entries whose `embedding_model`, `embedding_version`, or `text_hash` differ from the current target (content drift, model upgrade, or forced rebuild). Query refuses to run if `POLARIS_EMBED_MODEL` doesn't match what the index was built with — fail-fast rather than silently return garbage similarity.

**Company hard-skip:** semantic query applies the same filter as confidence-mode query — entries with a `company` field that doesn't match the active `POLARIS_COMPANY` are skipped before scoring. Entries without a `company` field are treated as workspace-wide.

**Dependencies:** Python 3.13 venv with [`fastembed`](https://github.com/qdrant/fastembed) (pulls in `onnxruntime` + `numpy`). Model auto-downloads on first use (~90MB for `all-MiniLM-L6-v2`, cached under `~/.cache/huggingface/`). Subsequent embeds: ~10ms per query.
