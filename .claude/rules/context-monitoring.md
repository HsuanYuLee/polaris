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
- If in doubt, use memory or todo to restore lost state

### 5. Segment Large Tasks

When a task is expected to produce many tool calls (> 30):
- Create a todo list to break the work into phases before starting
- Record output at each completed todo to ensure compression doesn't affect subsequent steps
- Delegate batch operations (e.g., creating multiple JIRA sub-tasks) to a sub-agent for one-shot completion
