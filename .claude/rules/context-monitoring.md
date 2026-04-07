# Context Window Self-Monitoring

## Core Principle

Long conversations trigger context compression (the system automatically truncates earlier messages). The Strategist must proactively manage context usage to avoid information loss or duplicated work.

## Monitoring Rules

### 1. Delegate Heavy Exploration, Keep Main Context Clean

- Need to read > 3 files or grep multiple patterns → dispatch sub-agent (Explore)
- Need to analyze large diffs (> 500 lines) → dispatch sub-agent
- **Never** issue > 5 consecutive Read/Grep tool calls in the main session without producing a conclusion

### 2. Milestone Wrap-Up

After completing an independent phase (e.g., ticket breakdown done, PR created, review finished):
- Record key decisions and artifacts (URLs, branch names, ticket keys) in a brief summary
- Do not re-reference intermediate data no longer needed (large diffs, API responses, file listings)
- If subsequent steps need earlier information, keep key values in the summary, not raw data

### 3. Avoid Re-Reading Files

- Do not read the same file more than twice in one conversation (unless it was modified)
- Note key information from reads (config values, function signatures, API paths) in your reply; reference directly later
- If you need to repeatedly consult a file's structure, read it once and note the essentials

### 4. Compression Awareness

When the system indicates context was compressed:
- Review the current task's todo list to confirm progress is intact
- Re-confirm key artifacts (branch name, PR URL, ticket key) are still available
- **Re-confirm active company context** — check todo list or recent messages for which company was active. If unclear, ask the user before proceeding (wrong company context can cause rule/memory cross-contamination)
- If in doubt, use memory or todo to restore lost state

### 4a. Company Context Preservation

The active company context (set by `/use-company`, JIRA ticket routing, or user declaration) must survive context compression:

- **Before compression risk** (long conversation, many tool calls): include the active company name in milestone wrap-up summaries and todo items (e.g., "Working on ACME — ticket ACME-123")
- **After compression**: if the active company is no longer visible in context, check the todo list first, then ask the user with a specific prompt: "I've lost track of the active company context after compression. You were working on [Company A / Company B / ?] — which should I resume with? (You can also run `/use-company` to set it.)" — never guess or default silently
- **Multi-company sessions**: when switching companies mid-conversation, record the switch in a todo item so it survives compression

### 5. Runtime Context Awareness

The rules above are self-enforced by the Strategist. For additional protection, a runtime monitoring mechanism can detect context pressure:

**Current mechanism** (prompt-level):
- The Strategist follows the rules in §1-4 above through self-discipline
- Post-task audit (see `mechanism-registry.md`) catches violations after the fact

**Future enhancement** (hook-level, tracked in backlog):
- A `PostToolUse` hook could monitor context window usage percentage
- At 35% remaining → inject advisory warning ("consider wrapping up current phase")
- At 25% remaining → inject urgent warning ("save state and delegate remaining work")
- This would catch context rot that self-monitoring misses in long sessions

**Interim mitigation**: When a conversation has exceeded 20 tool calls without completing a major milestone, the Strategist should proactively:
1. Write a milestone summary of progress so far
2. Assess whether remaining work should be delegated to a sub-agent
3. If the conversation is approaching a natural break, suggest the user start a fresh session

### 5a. Checkpoint Mode on Context Pressure

When **tool call count exceeds 25** AND there are **pending todo items or unfinished work**, the Strategist must proactively enter checkpoint mode:

1. **Save checkpoint memory** — write a `type: project` memory with:
   - What was completed in this session
   - What is still pending (with enough context to resume)
   - Key artifacts (branch name, PR URL, ticket key, file paths)
2. **Diff previous checkpoint** — apply the Cross-Session Carry-Forward Check (see `feedback-and-memory.md`) to ensure nothing is silently dropped
3. **Notify the user**: "Context 接近極限，已存檔。建議開新 session 繼續，輸入「繼續 {topic}」即可接續。"

**Why:** v1.71.0 retrospective — a long debugging session consumed all context on fixing gzip headers, then wrote a next-session memory that dropped pending items from the previous checkpoint (JIRA report, verification ticket update). By the time the session ended, the Strategist had lost awareness of earlier obligations.

**The key behavior:** checkpoint mode is not "stop working" — it's "save state thoroughly before context compression makes you forget." The cost of a 30-second checkpoint is far less than a dropped deliverable.

### 5b. Checklist Review Before Declaring Done

Before declaring a task complete (saying "done", asking "要更新 checkpoint 嗎？", or proposing to move on), the Strategist must review the session's original task list:

1. **Recall the starting checklist** — the checkpoint's "next steps", todo items, or the user's original request items
2. **For each item**, confirm one of three dispositions:
   - **(a) Done** — completed in this session
   - **(b) Carry-forward** — still pending, will note in checkpoint
   - **(c) Dropped** — no longer relevant, with reason
3. **If any item has no disposition**, the task is not complete — address or explicitly carry-forward before declaring done

**Why:** VR session (2026-04-07) — 8/8 zero-diff pass was the technical milestone, but the checkpoint also listed "JIRA 截圖替換" as a next step. The Strategist declared completion without checking the list, and the JIRA update was only caught because the user noticed. The carry-forward check at checkpoint-write time doesn't catch this — the gap is between "technical success" and "all deliverables addressed."

**The key behavior:** "Tests pass" ≠ "task complete." The starting checklist defines what "done" means, not the technical milestone.

### 6. Segment Large Tasks

When a task is expected to produce many tool calls (> 30):
- Create a todo list to break the work into phases before starting
- Record output at each completed todo to ensure compression doesn't affect subsequent steps
- Delegate batch operations (e.g., creating multiple JIRA sub-tasks) to a sub-agent for one-shot completion
