#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/memory-hygiene-tiering.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MEMORY="$TMP/memory"
SPECS="$TMP/specs"
mkdir -p "$MEMORY" "$SPECS/design-plans/DP-900-locked" "$SPECS/design-plans/DP-901-implemented"

cat >"$SPECS/design-plans/DP-900-locked/index.md" <<'EOF'
---
title: "DP-900 locked fixture"
status: LOCKED
---
EOF

cat >"$SPECS/design-plans/DP-901-implemented/index.md" <<'EOF'
---
title: "DP-901 implemented fixture"
status: IMPLEMENTED
---
EOF

cat >"$MEMORY/MEMORY.md" <<'EOF'
# Memory Index

## Hot

- [Locked](locked_snapshot.md)
- [Implemented](implemented_snapshot.md)
- [Graduated](graduated.md)
- [Nested](nested.md)
- [Fresh](fresh.md)
- [Old](old_no_created.md)
- [Newer](hot_newer.md)
- [Older](hot_older.md)
EOF

cat >"$MEMORY/locked_snapshot.md" <<'EOF'
---
name: locked snapshot
description: locked is still active
type: project
snapshot_of: DP-900
snapshot_taken: 2026-05-19
last_triggered: 2026-05-18
trigger_count: 1
---
EOF

cat >"$MEMORY/implemented_snapshot.md" <<'EOF'
---
name: implemented snapshot
description: implemented is terminal
type: project
snapshot_of: DP-901
snapshot_taken: 2026-05-19
trigger_count: 0
topic: dp-901
---
EOF

cat >"$MEMORY/graduated.md" <<'EOF'
---
name: graduated feedback
description: promoted to rule
type: feedback
graduated_to: .claude/rules/feedback-and-memory.md
trigger_count: 0
---
EOF

cat >"$MEMORY/nested.md" <<'EOF'
---
name: nested fixture
description: nested metadata fixture
metadata:
  type: project
  topic: nested-topic
last_triggered: 2026-05-18
trigger_count: 1
---
EOF

cat >"$MEMORY/fresh.md" <<'EOF'
---
name: fresh fixture
description: fresh write
type: feedback
created: 2026-05-19
trigger_count: 0
---
EOF

cat >"$MEMORY/old_no_created.md" <<'EOF'
---
name: old no created
description: should backfill created from mtime
type: project
trigger_count: 0
topic: old-topic
---
EOF

cat >"$MEMORY/hot_newer.md" <<'EOF'
---
name: hot newer
description: ordering fixture
type: feedback
last_triggered: 2026-05-18
trigger_count: 1
---
EOF

cat >"$MEMORY/hot_older.md" <<'EOF'
---
name: hot older
description: ordering fixture
type: feedback
last_triggered: 2026-05-10
trigger_count: 1
---
EOF

touch -t 202605010000 "$MEMORY/old_no_created.md"

PLAN="$TMP/plan.json"
POLARIS_SPECS_ROOT="$SPECS" python3 "$SCRIPT" dry-run --memory-dir "$MEMORY" --today 2026-05-19 --json >"$PLAN"

python3 - "$PLAN" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1]))
summary = data["summary"]
assert summary["stale_snapshot"] == 1, summary
assert summary["graduated_feedback"] == 1, summary
assert summary["nested_frontmatter"] == 1, summary
assert summary["fresh_write_hot"] == 1, summary
assert summary["created_backfill"] >= 1, summary
by_file = {item["file"]: item for item in data["classifications"]}
assert by_file["locked_snapshot.md"]["flags"]["stale_snapshot"] is False
assert by_file["implemented_snapshot.md"]["flags"]["stale_snapshot"] is True
assert by_file["fresh.md"]["flags"]["fresh_write_hot"] is True
assert by_file["old_no_created.md"]["created_backfill"] == "2026-05-01"
hot_order = data["hot_order"]
assert hot_order.index("hot_newer.md") < hot_order.index("hot_older.md"), hot_order
PY

POLARIS_SPECS_ROOT="$SPECS" python3 "$SCRIPT" decay-scan --memory-dir "$MEMORY" --today 2026-05-19 >"$TMP/decay.out"
grep -q "stale snapshot candidates" "$TMP/decay.out"
grep -q "graduated feedback candidates" "$TMP/decay.out"

POLARIS_SPECS_ROOT="$SPECS" python3 "$SCRIPT" apply --memory-dir "$MEMORY" --today 2026-05-19 <"$PLAN" >"$TMP/apply.out"
grep -q "created: 2026-05-01" "$MEMORY/old-topic/old_no_created.md"
grep -q "## Frontmatter normalization" "$MEMORY/.migration-log.md"

echo "PASS: memory-hygiene-tiering selftest"
