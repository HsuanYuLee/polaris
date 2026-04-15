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

When the system indicates context was compressed, immediately recover session state:

1. **Check todo list** — confirm current task progress is intact
2. **Check recent messages** — re-confirm active company context, branch name, ticket key, PR URL
3. **Check artifacts on disk** — look for recent plans, checkpoints, or notes that the previous context produced but are no longer visible:
   - Todo items often contain key artifact paths and decision context
   - Git branch name encodes the ticket being worked on
4. **Check session timeline** — `polaris-timeline.sh query --last 10` for recent activity context; recent git log shows what was committed in this session
5. **If company context is unclear** — ask the user before proceeding (wrong company causes rule/memory cross-contamination)
6. **Never guess** — if critical state (which ticket, which repo, which company) is lost and unrecoverable from the above sources, ask rather than assume

### 4a. Company Context Preservation

The active company context (set by `/use-company`, JIRA ticket routing, or user declaration) must survive context compression:

- **Before compression risk** (long conversation, many tool calls): include the active company name in milestone wrap-up summaries and todo items (e.g., "Working on ACME — ticket ACME-123")
- **After compression**: if the active company is no longer visible in context, check the todo list first, then ask the user with a specific prompt: "I've lost track of the active company context after compression. You were working on [Company A / Company B / ?] — which should I resume with? (You can also run `/use-company` to set it.)" — never guess or default silently
- **Multi-company sessions**: when switching companies mid-conversation, record the switch in a todo item so it survives compression

### 5. Runtime Context Awareness

The rules above are self-enforced by the Strategist. For additional protection, a runtime monitoring mechanism can detect context pressure:

**Deterministic mechanism** (hook-level):
- `scripts/context-pressure-monitor.sh` is a PostToolUse hook that counts Bash/Edit/Write/Read/Grep/Glob/Agent calls
- State: `/tmp/polaris-session-calls.txt` (one timestamp per call, session-scoped)
- At **20 calls** → advisory: "consider wrapping up current phase"
- At **25 calls** → urgent: "save state, delegate remaining work"
- At **35 calls** → critical: "enter checkpoint mode NOW"
- Registered in `mechanism-registry.md` § Deterministic Quality Hooks

**Behavioral backup** (prompt-level):
- The Strategist follows the rules in §1-4 above through self-discipline
- Post-task audit (see `mechanism-registry.md`) catches violations after the fact
- The hook warnings are advisory (stdout injection, not blocking) — the Strategist must act on them

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

**Proactive session split = checkpoint mode.** When the Strategist decides to suggest switching to a new session (work nature change, long-running task completed, remaining work is independent), the same checkpoint sequence applies: save memory first, then notify. The notification is a statement, not a suggestion — "已存檔，開新 session 輸入「繼續 {topic}」接續", not "建議開新 session". The word "建議" implies optional, which lets the save step get skipped.

### 5b. Defer = Immediate Capture

When a conversation decision defers work to a later phase ("等 X 再處理 Y", "精簡時一起看", "下一步再決定"), the deferred item must be captured **immediately** — not after the current task completes:

- If the deferred phase is **in this session** → add to todo list
- If the deferred phase is **in a future session** → write to memory
- **If the decision is a design decision in an ongoing design discussion** → update the active `.claude/design-plans/{topic}.md` file (see `skills/design-plan/SKILL.md`)

An oral defer ("我們等精簡時再看") without a corresponding todo/memory/plan entry is **not landed**. The Strategist treats it as untracked and captures it before moving on.

**Why:** jira-worklog consolidation session (2026-04-13) — "等精簡時決定 jira-worklog 位置" was agreed verbally but never added to the consolidation todo list. When consolidation executed, the item was invisible and dropped. The user discovered the gap post-task.

**Design decision variant (2026-04-15, check-pr-approvals v2.16.0)** — in a multi-turn design discussion, an early decision ("轉狀態回 IN DEVELOPMENT → 乾淨") got overwritten by later phrasing ("engineering 零改動"). When implementation started, the early decision was silently dropped. Mitigation: design discussions trigger `design-plan` skill at the start; each confirmed decision updates the plan file in the **very next tool call**. See mechanism-registry `design-plan-creation` / `design-plan-reference-at-impl`.

### 5c. Checklist Review Before Declaring Done

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
