---
name: checkpoint
description: Save, resume, or list session checkpoints for long-running work. Captures current state (branch, ticket, todo, recent activity) so you can resume after interruptions or context compression.
triggers:
  - "checkpoint"
  - "存檔"
  - "save checkpoint"
  - "resume"
  - "恢復"
  - "list checkpoints"
  - "列出存檔"
version: 1.0.0
---

# /checkpoint — Session State Save & Resume

Three modes: **save**, **resume**, **list**.

## Mode Detection

| User says | Mode |
|-----------|------|
| "checkpoint", "存檔", "save checkpoint", "save state" | save |
| "resume", "恢復", "resume checkpoint", "接回去" | resume |
| "list checkpoints", "列出存檔", "show checkpoints" | list |

If ambiguous, default to **save**.

---

## Mode: save

Capture the current session state for later recovery.

### Step 1 — Gather State

Collect in parallel:
1. **Git branch**: `git -C {workspace_root} branch --show-current`
2. **Git status**: `git -C {workspace_root} status --short` (first 20 lines)
3. **JIRA ticket**: extract from branch name or active todo context
4. **Todo list**: current todo items and their statuses
5. **Recent timeline**: `polaris-timeline.sh query --last 5` (if timeline exists)

### Step 2 — Build Checkpoint Note

Compose a single-line note summarizing the state:

```
branch:{branch} ticket:{ticket} phase:{current_phase} next:{next_action}
```

Example: `branch:task/GT-500-auth ticket:GT-500 phase:implementation next:write-tests`

### Step 3 — Write to Timeline

```bash
POLARIS_WORKSPACE_ROOT={workspace_root} \
  {base_dir}/.claude/skills/references/scripts/polaris-timeline.sh append \
  --event checkpoint \
  --branch "{branch}" \
  --ticket "{ticket}" \
  --company "{company}" \
  --note "{checkpoint_note}"
```

### Step 4 — Confirm to User

```
Checkpoint saved.
  Branch: {branch}
  Ticket: {ticket}
  Phase: {phase}
  Next: {next_action}

Resume with: /checkpoint resume
```

---

## Mode: resume

Restore context from the most recent checkpoint (or a specific one).

### Step 1 — Read Checkpoints

```bash
POLARIS_WORKSPACE_ROOT={workspace_root} \
  {base_dir}/.claude/skills/references/scripts/polaris-timeline.sh checkpoints --last 5
```

### Step 2 — Select Checkpoint

- If user specified a timestamp or index, use that checkpoint
- Otherwise, use the most recent one

### Step 3 — Restore Context

Parse the checkpoint note to extract:
- `branch` → verify it still exists: `git -C {workspace_root} branch --list "{branch}"`
- `ticket` → read JIRA ticket for current status
- `phase` / `next` → reconstruct the todo list

### Step 4 — Verify Branch State

```bash
git -C {workspace_root} branch --show-current
```

If current branch differs from checkpoint branch, ask user if they want to switch.

### Step 5 — Report Restored State

```
Checkpoint restored (from {timestamp}).
  Branch: {branch}
  Ticket: {ticket}
  Status: {jira_status}
  Next action: {next_action}

Ready to continue. Say "next" or describe what to do.
```

---

## Mode: list

Show recent checkpoints for review.

### Step 1 — Query Checkpoints

```bash
POLARIS_WORKSPACE_ROOT={workspace_root} \
  {base_dir}/.claude/skills/references/scripts/polaris-timeline.sh checkpoints --last 10
```

### Step 2 — Format Output

Display as a table:

```
Recent Checkpoints:
  #  Time                Branch              Ticket    Note
  1  2026-04-02 14:30    task/GT-500-auth    GT-500    phase:implementation next:write-tests
  2  2026-04-02 10:15    task/GT-499-api     GT-499    phase:pr next:fix-review
  3  2026-04-01 17:00    task/GT-498-refactor GT-498   phase:done next:merge
```

---

## Preamble

Read `skills/references/polaris-project-dir.md` for slug resolution. The workspace root is the git root of the current working directory.
