# Pipeline Handoff Artifact

Defines the **evidence artifact** dropped at skill handoff points so the next skill in the pipeline can on-demand verify raw findings without re-exploring.

This reference extends `pipeline-handoff.md` (which defines role boundaries and task.md schema) with the evidence layer. DP-024 P4.

## Why

Skill pipeline (`refinement → breakdown → engineering → verify-AC → bug-triage`) currently hands off **conclusion documents only** (refinement.md, task.md, JIRA comments). Raw tool return — grep matches, error traces, endpoint responses, commit hashes — gets lost after the producing skill's session ends.

Result: the next skill either (a) trusts conclusions blindly, or (b) re-greps/re-runs to verify. (b) wastes context and risks drift.

Handoff artifact = compact, scrubbed snapshot of the supporting evidence, written at the handoff seam. Default behaviour: the next skill's sub-agent trusts the conclusion and skips the artifact. Only when the conclusion is ambiguous, contradicted, or needs verification does the sub-agent open it.

## File Location and Naming

Write handoff artifacts to the **same** `specs/{EPIC_OR_TICKET}/artifacts/` folder already used for sub-agent Completion Envelope Detail files (see `sub-agent-roles.md` § Summary vs Detail Separation). This intentionally collapses two concepts:

- **Detail file** (Completion Envelope): written by a sub-agent, read by its dispatching Strategist in the current skill
- **Handoff artifact** (this doc): written at skill end, read by the next skill's sub-agent

Both sit in the same folder and follow the same format. The difference is the **consumer**, not the file.

**Filename**: `{skill}-{scope}-{ticket_key}-{timestamp}.md`

| Part | Format | Example |
|------|--------|---------|
| skill | skill name slug | `bug-triage`, `engineering`, `verify-ac` |
| scope | optional scope qualifier, omit if not meaningful | `root-cause`, `ac-fail`, `verify-fail` |
| ticket_key | primary JIRA key being worked on | `TASK-123`, `PROJ-123` |
| timestamp | UTC, seconds-precision, `Z` suffix | `2026-04-22T153000Z` |

Full example: `specs/PROJ-123/artifacts/bug-triage-root-cause-TASK-123-2026-04-22T153000Z.md`

When `scope` is not needed the segment is dropped: `engineering-TASK-123-2026-04-22T154500Z.md`.

## Artifact Format

```markdown
---
skill: bug-triage
ticket: TASK-123
scope: root-cause
timestamp: 2026-04-22T15:30:00Z
truncated: false
scrubbed: true
---

## Summary

≤ 500 字 conclusion in the conversation's language (Traditional Chinese or English).
Routing decisions for the consumer can be made from this section alone.

Structure suggestion:
- 1–2 sentences of the headline finding
- Key file paths / line numbers
- Next-step direction

## Raw Evidence

Supporting tool return — grep matches, error traces, endpoint responses, git diff
excerpts, test output. Capped at 20KB after secret scrubbing. Truncation (if applied)
inserts a single `[truncated, N bytes omitted]` marker between kept head and tail.
```

### Required Frontmatter Fields

| Field | Type | Description |
|-------|------|-------------|
| `skill` | string | Producing skill slug |
| `ticket` | string | Primary JIRA key |
| `scope` | string | Optional — qualifies multi-mode skills (e.g., `root-cause` vs `ac-fail`) |
| `timestamp` | string (ISO 8601) | UTC, with `Z` suffix |
| `truncated` | bool | `true` when 20KB cap forced truncation |
| `scrubbed` | bool | `true` when `snapshot-scrub.py` was applied |

### Size Cap (Hard Limit 20KB)

Content after scrubbing must be ≤ 20KB. If raw evidence exceeds the cap:

1. Keep head (first **13000 bytes**)
2. Insert marker `\n\n[truncated, N bytes omitted]\n\n` (where N = total raw bytes − kept bytes)
3. Keep tail (last **6000 bytes**)

Head + marker + tail ≤ 19100 bytes, well under the cap. Frontmatter and `## Summary` section are outside the cap calculation (they live on top; the cap only applies to `## Raw Evidence` content).

### Secret Scrubbing

All artifacts must pass through `scripts/snapshot-scrub.py` before write. The script replaces matches of the patterns below with `[REDACTED:kind]` markers:

| Pattern family | Kind marker |
|----------------|-------------|
| GitHub PAT / OAuth / server tokens | `github-*` |
| OpenAI / Anthropic API keys | `openai-like`, `anthropic` |
| Slack bot/user/app tokens | `slack-*` |
| AWS access keys (standard + temporary) | `aws-*` |
| Bearer tokens in HTTP headers | `bearer` |
| Basic auth in URLs | `basic-auth` |
| Atlassian / generic `api_token`-labelled strings | `api-token` |
| Generic `password|secret|token|api_key = ...` | `secret` |

If scrubbing is skipped (unusual — only for evidence that must preserve exact token values, e.g. a security review), set `scrubbed: false` and flag the artifact in the JIRA handoff comment so the reader knows to handle with care.

## Per-Skill Write Policy (「結論不自明」判定 — per-skill, not shared heuristic)

Each producing skill decides its own write rules. Keep the rule concrete: what **scope** produces an artifact, and what **content** goes into Raw Evidence.

### bug-triage

| Path | Artifact? | Scope | Raw Evidence content |
|------|-----------|-------|----------------------|
| Full Path (Step 3, Explorer dispatched) | **Write** | `root-cause` | File paths + grep matches; line ranges of suspect code; commit hashes referenced; PR diff excerpts; stack traces / error output from ticket |
| AC-FAIL Path (Step 2-AF.2, Explorer dispatched) | **Write** | `ac-fail` | Same as root-cause plus `[VERIFICATION_FAIL]` block from Bug description; mapping of AC# → suspect code location |
| Fast Path (Step 2, inline, ≤ 3 files) | **Skip** | — | Conclusion is self-evident from ticket + trivial file read; no evidence to preserve |

### engineering

| Path | Artifact? | Scope | Raw Evidence content |
|------|-----------|-------|----------------------|
| First-cut delivery (PR opened, transitioning to QA) | **Write** | — (scope omitted) | Final commit SHAs on the branch; test command + full output (pass/fail counts, timing); quality-gate results (lint, typecheck, coverage); Layer B behavioral verify output (curl output, screenshots paths, dev-server logs); evidence-file JSON contents; task.md items marked PASS/FAIL/SKIP |
| Revision mode (fix on existing PR) | **Write** | `revision` | Delta commit SHAs; re-test output; Layer B re-verify output; responses to review comments; any regression catches |
| Batch mode (parallel sub-agents) | **Write per ticket** | — | Same as first-cut, one artifact per ticket |

Filename examples:
- `engineering-TASK-123-2026-04-22T154500Z.md` (first-cut)
- `engineering-revision-TASK-123-2026-04-22T170000Z.md` (revision)

Why write unconditionally: engineering's work IS the delivered change. verify-AC needs the Layer B evidence trail to understand what was tested locally vs what it's about to re-verify. This is also the Completion Envelope Detail file for the dispatching Strategist — single file, dual consumer (see § Interaction with Existing Mechanisms below).

### verify-AC

| Path | Artifact? | Scope | Raw Evidence content |
|------|-----------|-------|----------------------|
| PASS (all AC pass) | **Skip** | — | Comment + JIRA transition are sufficient; no downstream handoff |
| FAIL → 實作偏差 disposition (per-AC Bug created) | **Write per Bug** | `verify-fail` | AC# + expected vs observed (including HTTP status when applicable); failing step transcript (curl output / playwright trace / evidence paths); env snapshot (dev server URL, fixture path, commit SHA under test); AC ticket description excerpt; links to evidence attachments |
| FAIL → 規格問題 disposition | **Skip** | — | Routes back to refinement (a planning skill), not through the artifact consumer chain |
| PENDING (MANUAL_REQUIRED / UNCERTAIN) | **Skip** | — | Human judgement pending; artifact premature |

Filename: `verify-ac-verify-fail-{BUG_KEY}-{timestamp}.md` (one per Bug created for 實作偏差)

Why: bug-triage AC-FAIL Path (`[VERIFICATION_FAIL]` block detection in Bug description) uses the Bug description as primary work order. The artifact adds the raw observed/expected evidence verify-AC collected, so bug-triage's Explorer can triangulate the broken code without re-running the AC.

## On-Demand Read — Dispatch Prompt Template

Consumer skills **must not** blindly read the artifact. Default = trust the conclusion document (task.md, JIRA comment). Read the artifact only when needed.

Injection point in the consumer sub-agent dispatch prompt:

```text
## Evidence Artifact (on-demand)

Upstream skills may have dropped a handoff artifact with raw supporting evidence.
Do not read by default. Open only when:

- The work order (task.md / JIRA comment) is ambiguous or missing detail
- You need to verify a claim (e.g., a file path, an error message, a response shape)
- You suspect the conclusion is stale or inconsistent with the current codebase

Location: `specs/{EPIC_OR_TICKET}/artifacts/{skill}-*.md`
Format: `## Summary` (≤500 字 decision digest) + `## Raw Evidence` (capped raw output)
Read the Summary first; only scan Raw Evidence when Summary does not answer your question.
```

Place this block **after** the work-order reading instruction (so the sub-agent still treats task.md / JIRA comment as the primary input).

## Interaction with Existing Mechanisms

| Existing | Relationship |
|----------|--------------|
| Completion Envelope Detail (`sub-agent-roles.md`) | Same folder, same format. The producing skill's Detail file IS the handoff artifact — no separate write |
| `pipeline-handoff.md` task.md schema | task.md is still the primary contract. Artifact is supplementary |
| `epic-folder-structure.md` | `artifacts/` folder is already canonical; this reference pins the content format |
| `safety-gate.sh` | Different scope — gate blocks dangerous commands; scrub filters secret strings. Patterns are mostly disjoint |

## Script

- **Writer-side scrub + cap**: `scripts/snapshot-scrub.py` (stdin → stdout, or `--file path` in place)
- **Typical invocation** (inside a sub-agent Bash step):
  ```bash
  python3 scripts/snapshot-scrub.py --file specs/PROJ-123/artifacts/bug-triage-root-cause-TASK-123-2026-04-22T153000Z.md
  ```
  The script reads the file, scrubs secrets in `## Raw Evidence`, applies the 20KB cap, updates frontmatter `scrubbed` / `truncated` booleans, and rewrites the file in place.

## Source

- Design plan: `specs/design-plans/DP-024-memory-system-enhancement/plan.md` § D3 + D5
- Pilot handoff: bug-triage → engineering (2026-04-22 confirmed)
- Follow-up expansion: engineering → verify-AC, verify-AC FAIL → bug-triage
