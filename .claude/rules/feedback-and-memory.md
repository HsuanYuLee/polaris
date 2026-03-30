# Automatic Feedback Mechanism

After completing a full task (opening a PR, fixing review comments, estimation, reviewing a PR, etc.), silently reflect on the conversation:

1. **User corrected a behavior** → save a feedback memory recording the rule + Why + How to apply
2. **The same feedback memory is referenced >= 3 times** → trigger the Rule Graduation process (see below)
3. **Blocked by a hook or permission denied** → immediately record the command and a suggested pattern; before the task ends, list all blocked commands and fix them (general → `~/.claude/settings.json`, project-specific → `settings.local.json`)
4. **A command failed and was self-corrected** (wrong path guess, wrong parameter, wrong API format, etc.) → record the "wrong command → correct command" pair as a feedback memory
5. **Stuck for more than 2 rounds without resolution** → record the root cause and final solution in a feedback memory
6. **User confirmed a non-obvious approach** (accepted an unusual choice with "yes" / "exactly") → save a positive feedback memory. If the confirmation relates to a **framework-level behavior** (skill routing, delegation, reflection mechanism), save a `type: framework-experience` memory instead (see `rules/framework-iteration.md`)

Execute silently. Only notify the user and wait for confirmation before writing when a feedback worth recording is found. Items 3 and 4 may be recorded without user confirmation.

## Pre-Write Dedup Check

Before creating a new feedback memory, scan existing feedback memories for semantic overlap:

1. **Read all `type: feedback` entries** in the memory directory (use MEMORY.md index for quick scan)
2. **Compare** the new feedback's core rule against existing entries — same topic, same file/mechanism, or same behavioral correction = overlap
3. **If overlap found** → merge into the existing entry:
   - Update the content to incorporate the new evidence/context
   - Increment `trigger_count` by 1, update `last_triggered` to today
   - Do NOT create a new file
4. **If no overlap** → create a new file as normal
5. **Post-merge graduation check** — if the merged entry's `trigger_count >= 3`, immediately trigger the Rule Graduation process (see § Feedback → Rule Graduation)

This check prevents duplicate feedback accumulation and ensures graduation triggers at the earliest opportunity.

## Post-Task Mechanism Audit

After the feedback reflection above, also scan for **mechanism violations** using `rules/mechanism-registry.md`. This is the second layer of the silent post-task check:

1. Review the conversation for canary signals of the **top 5 priority mechanisms** (see registry § Priority Audit Order)
2. If a violation is found:
   - Record a feedback memory with the mechanism ID (e.g., `name: Violated skill-first-invoke`)
   - Include what happened, why it drifted, and the corrective action
3. If no violations → no action needed (don't log "all clear")

This audit runs silently alongside the feedback reflection — no separate user notification. The mechanism registry is the source of truth for what to check.

## Automatic Polaris Backlog Writes

Signals about improving the framework itself should flow into `.claude/polaris-backlog.md`. The following situations trigger a write:

| Signal | Condition | Write Location |
|--------|-----------|----------------|
| New feedback memory added | Pain point is framework-level (skill flow, rule mechanism, config structure) not company-specific business logic | Backlog High or Medium |
| Hook block / permission denied | Same class of pattern blocked >= 2 times | Backlog High |
| `/learning` external mode recommendation | Recommendation marked "worth tracking" by user but not acted on immediately | Backlog Medium or Low |
| User mentions "Polaris should..." / "the framework could be improved..." | Write directly | Backlog by severity |
| Gap found during skill execution (broken flow, manual steps required) | Record the missing automation | Backlog Medium |
| Framework-experience memories >= 3 for same pattern | Validated pattern candidate — surface during organize-memory | See `rules/framework-iteration.md` § Validated Pattern Promotion |

**Write format:** `- [ ] **{title}** — {one-line description} — source: {feedback/learning/user/observation}`

**Do not write to backlog:** company-specific processes (JIRA fields, PR conventions), project-specific rules, one-off bug fixes.

## Feedback Memory Frontmatter Spec

All feedback memories must include trigger tracking fields:

```yaml
---
name: Human-readable title for the rule
description: One-line description (used to determine relevance)
type: feedback
company: acme              # Company scope (omit for workspace-wide memories)
trigger_count: 1          # Number of times referenced/applied (= 1 when first created)
last_triggered: 2026-03-29  # Date last referenced
---
```

### Trigger Count Update Rules

A "reference" is counted when **a decision is made or behavior is guided based on a feedback memory** during a conversation:

1. After reading a feedback memory, increment `trigger_count` and update `last_triggered` to today's date
2. If the same feedback is referenced multiple times within the same conversation, count it only once
3. Pure hygiene checks (scanning frontmatter) do not count as a reference

## Feedback → Rule Graduation (Auto-Evolution)

When `trigger_count >= 3`, trigger the graduation process:

### Step 1: Identify the Target Rule File

Based on the semantic content of the feedback, find the most appropriate file in `.claude/rules/`:

| Feedback Topic | Target File |
|----------------|-------------|
| Sub-agent delegation behavior | `rules/sub-agent-delegation.md` (or `rules/{company}/` if company-scoped) |
| PR / Review workflow | `rules/{company}/pr-and-review.md` |
| JIRA conventions | `rules/{company}/jira-conventions.md` |
| Skill usage | `rules/skill-routing.md` |
| Other | Determine by semantics, or suggest creating a new rule file |

### Step 2: Draft the Rule Text

Convert the feedback content into rule format:
- Remove the `Why:` / `How to apply:` structure; rewrite in the rule file's style (declarative sentences + bullets)
- Preserve the core rule and rationale, integrated into the context of the target section
- Do not add a "from feedback" annotation

### Step 3: Present to User for Confirmation

```
Feedback Graduation Proposal

"{feedback name}" has been referenced {N} times and is ready to be promoted to a rule:

Target: {rules/company/xxx.md} § {section}
Content to add:
  {drafted rule text}

Upon confirmation I will:
1. Write the content into the target rule file
2. Delete the corresponding feedback memory
3. Update the MEMORY.md index
```

### Step 4: Execute After User Confirmation

1. Merge the drafted text into the target rule file at the appropriate location
2. Delete the feedback memory file
3. Remove the entry from MEMORY.md
4. Briefly list all changes at the end of the reply

### Manual Trigger

When the user says "organize feedback" / "graduate feedback" → scan all feedback memories:
- `trigger_count >= 3` → enter the graduation process
- `trigger_count == 0` and `last_triggered` is more than 30 days ago → suggest deletion (may be outdated)
- Otherwise → leave unchanged

## Real-Time Collection of Rejected Commands

When a permission denial occurs during execution, immediately record the command and a suggested pattern. Before the task ends, list all rejected/manually-allowed commands, suggest patterns to add, and write them after user confirmation (general → `~/.claude/settings.json`, project-specific → `settings.local.json`).

## Memory Company Isolation

Memories in a multi-company workspace can cross-apply to the wrong company. Use the `company:` frontmatter field to scope memories:

- **When saving a memory** that is specific to one company's workflow, codebase, or conventions → include `company: {company_name}` in frontmatter
- **Workspace-wide memories** (Polaris framework, universal preferences, cross-company feedback) → omit the `company:` field entirely
- **When in doubt** → omit `company:` (workspace-wide is the safe default)

The `company:` field applies to all memory types (feedback, project, reference, user), not just feedback.

### Hard-Skip Rule (Enforcement)

When reading memories and an active company context is known:

1. **Check `company:` field** against the current active company
2. If `company:` is present **and does not match** the active company → **skip the memory entirely** (do not read its content, do not apply its guidance)
3. If `company:` is absent → treat as workspace-wide, always apply
4. If no active company context is set → apply all memories (no filtering)

Log skipped memories silently (do not notify the user). If a skipped memory is later needed across companies, remove its `company:` field to make it workspace-wide.

### MEMORY.md Index Format

Each entry in MEMORY.md should include a company tag when applicable:

```
- [filename.md](filename.md) — description                          ← workspace-wide
- [filename.md](filename.md) — [acme] description                   ← company-scoped
```

The `[company]` prefix in the index enables quick visual scanning without opening each file.

## Memory Hygiene Checks (Incremental Throughout Conversation)

**When to trigger:**
- A memory entry is read during the conversation → check only that entry
- During silent reflection after task completion → also scan memories referenced in this session
- User says "organize memory" / "clean up memory" → full scan of all memories

**What to check:**
1. **Redundant** — memory content already exists in CLAUDE.md or `.claude/rules/` → delete
2. **Outdated** — description says "superseded" or "outdated" → delete immediately
3. **Contains TODOs** — includes "pending fix" / "TODO" → check whether it has been completed
4. **Overlapping** — two memory entries are highly similar in content → merge into one
5. **Frontmatter quality** — missing `trigger_count` / `last_triggered` → fill in (`trigger_count: 1`, `last_triggered` from file modification date)
6. **Company isolation** — memory content is company-specific but missing `company:` field → add the appropriate `company:` value; memory has `company:` but the company no longer exists in workspace config → suggest deletion
