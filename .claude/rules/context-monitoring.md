# Context Monitoring

## Core Rule

Rely on native runtime compaction and Polaris checkpoint artifacts, not long prose self-monitoring. When context risk appears, preserve resumable state before changing topic or skill.

## Deterministic Mechanisms

| Mechanism | Owner | Purpose |
|-----------|-------|---------|
| `context-pressure-monitor.sh` | hook | Advisory tool-call pressure signal |
| `post-compact-context-restore.sh` | hook | Re-inject branch / ticket / dirty-state summary after compaction |
| `stop-todo-check.sh` | hook | Blocks premature stop when substantial todos remain |
| `checkpoint` skill | user workflow | Explicit save / restore / list session state |

## Behavioral Fallback

If compaction or long-running work risks losing state:

1. Record current branch, task/DP/ticket, PR URL, evidence paths, and remaining gates.
2. Account for every user-requested item as done, carry-forward, or dropped with reason.
3. If switching skill/topic, write a checkpoint memory and run `scripts/checkpoint-todo-diff.sh`.
4. Resume from disk artifacts and deterministic resolver output, not memory guesses.

## Prohibitions

- Do not use context risk as a reason to skip a mandatory gate.
- Do not silently drop earlier checklist items after a technical milestone passes.
- Do not guess company / repo / task context after compaction; resolve it from artifacts or ask.
