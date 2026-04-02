# Polaris Project Directory

Cross-session data lives in `~/.polaris/projects/$SLUG/`. This directory holds files that persist across conversations: learnings, timeline events, and checkpoints.

## Slug Resolution

The slug identifies a workspace uniquely on this machine.

**Resolution order:**
1. `$POLARIS_PROJECT_SLUG` environment variable (if set)
2. Basename of the workspace root directory (e.g., `/Users/me/work` -> `work`)

## Directory Structure

```
~/.polaris/
└── projects/
    └── $SLUG/
        ├── learnings.jsonl      # Cross-session knowledge (see cross-session-learnings.md)
        └── timeline.jsonl       # Session event log (see session-timeline.md)
```

## Ensure-Dir Convention

All scripts that write to the project directory must create it if missing:

```bash
SLUG="${POLARIS_PROJECT_SLUG:-$(basename "$POLARIS_WORKSPACE_ROOT")}"
PROJECT_DIR="$HOME/.polaris/projects/$SLUG"
mkdir -p "$PROJECT_DIR"
```

The `POLARIS_WORKSPACE_ROOT` is passed by the caller (the Strategist or skill) — it's the git root of the workspace being worked on.

## When Scripts Are Called

Scripts are invoked by the Strategist or sub-agents during conversation. They are **not** hooks — they run on-demand via Bash tool calls. The Strategist decides when to write learnings or timeline events based on the rules in `feedback-and-memory.md` and `session-timeline.md`.
