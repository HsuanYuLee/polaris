# Post-Task Reflection Checkpoint

A **required** final step in every write skill. This step makes the post-task reflection from `rules/feedback-and-memory.md` deterministic — it's baked into the skill flow, not relying on AI self-discipline alone.

## Why This Exists

Two consecutive PROJ-483 sessions produced 12+ mechanism violations with zero feedback written. Root cause: the Strategist was always "still fixing", so the task-completion trigger never fired. By embedding reflection as a named skill step, it becomes impossible to skip.

## Who Executes

- **Main session (Strategist)**: always executes this step after the skill completes
- **Sub-agent**: does NOT execute this step — sub-agents return results to the Strategist, who then reflects

## Checklist (execute silently, ~30 seconds)

### 1. Behavioral Feedback Scan

| Signal | Action |
|--------|--------|
| User corrected a behavior during this task | Save/merge feedback memory (rule + Why + How to apply) |
| A command failed and was self-corrected | Save feedback memory (wrong → correct pair) |
| Stuck > 2 rounds before resolution | Save feedback memory (root cause + solution) |
| User confirmed a non-obvious approach | Save positive feedback / framework-experience memory |
| Hook blocked or permission denied | Record command + suggest pattern fix |

### 2. Technical Learning Check

If a non-obvious technical insight was discovered → `polaris-learnings.sh add` (max 2 per task). See `cross-session-learnings.md` for types.

### 3. Mechanism Audit (top 5)

Scan the conversation against the top 5 priority canaries from `rules/mechanism-registry.md`:

1. `no-workaround-accumulation` / `design-implementation-reconciliation`
2. `skill-first-invoke` / `no-manual-skill-steps`
3. `fix-through-not-revert` / `query-original-impl`
4. `delegate-exploration` / `delegate-implementation`
5. `post-task-feedback-reflection`

If a violation is found → save feedback memory with the mechanism ID.

### 4. Graduation Check

If any feedback memory was updated and now has `trigger_count >= 3` → initiate Rule Graduation (see `rules/feedback-and-memory.md`).

### 5. Checkpoint Todo-Diff (when splitting session)

If the next action is a different skill or topic (see `rules/context-monitoring.md` § 5a-bis), run the checkpoint verification before notifying the user:

1. **Write the checkpoint memory** (type: project) with all pending items
2. **Run `scripts/checkpoint-todo-diff.sh`** — pass current todo items and the checkpoint file path:
   ```bash
   scripts/checkpoint-todo-diff.sh --todo-items "item1|item2|item3" --checkpoint-file /path/to/memory/file.md
   ```
3. **If the script exits non-zero** (missing items) → fix the checkpoint before proceeding. Every todo item must appear in the checkpoint as done, carry-forward, or dropped (with reason)
4. **Only after the diff passes** → notify the user with the session split message + trigger phrase

This is a **hard gate**: the session split notification cannot be sent until the diff passes. The cost of a 10-second re-check is trivial compared to a dropped deliverable discovered next session.

## SKILL.md Integration

Add this section as the **final step** of any write skill:

```markdown
## Step N: Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
```

Adjust the relative path based on skill directory depth.
