#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

require_text() {
  local file="$1"
  local pattern="$2"
  if ! grep -Fq -- "$pattern" "$file"; then
    echo "FAIL: missing pattern in $file: $pattern" >&2
    exit 1
  fi
}

expect_fail() {
  local label="$1"
  shift
  if "$@" >"$TMP/$label.out" 2>&1; then
    echo "FAIL: $label unexpectedly passed" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  fi
}

require_text "$ROOT/.claude/rules/skill-routing.md" "Trigger × Source-State Matrix"
require_text "$ROOT/.claude/rules/skill-routing.md" 'LOCKED` + current DP-backed source | `auto-pass DP-NNN`'
require_text "$ROOT/.claude/rules/skill-routing.md" 'DISCUSSION` / missing artifact / stale artifact | `refinement DP-NNN`'
require_text "$ROOT/.claude/rules/skill-routing.md" 'workspace PR opened + verification stale | `auto-pass DP-NNN` refresh verify-AC'
require_text "$ROOT/.claude/rules/skill-routing.md" "prose-only rule 自行逐 stage dispatch"
require_text "$ROOT/.claude/skills/breakdown/SKILL.md" "AUTO_PASS_LEDGER_PATH=<absolute ledger path>"
require_text "$ROOT/.claude/skills/references/breakdown-dp-intake-flow.md" "Auto-pass Ledger Consent"
require_text "$ROOT/.claude/skills/references/breakdown-dp-intake-flow.md" '--task-write-at "{task_write_iso8601}"'
require_text "$ROOT/.claude/skills/auto-pass/SKILL.md" "Routing Policy"
require_text "$ROOT/.claude/skills/auto-pass/SKILL.md" "refresh verify-AC，不重跑 breakdown"

SOURCE="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-998-routing-fixture"
mkdir -p "$SOURCE"
cat >"$SOURCE/index.md" <<'MD'
---
title: "DP-998: routing fixture"
description: "auto-pass routing fixture"
status: LOCKED
locked_at: 2026-05-19
---

# DP-998 fixture
MD

cat >"$SOURCE/refinement.md" <<'MD'
---
title: "DP-998 Refinement"
description: "auto-pass routing fixture refinement"
---

## Scope

此 fixture 用於驗證 auto-pass routing ledger consent。
MD

python3 - "$SOURCE/refinement.json" "$SOURCE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = Path(sys.argv[2])
payload = {
    "version": "1",
    "created_at": "2026-05-19T10:00:00+08:00",
    "source": {
        "type": "dp",
        "id": "DP-998",
        "container": str(source),
        "plan_path": str(source / "index.md"),
        "jira_key": None,
    },
    "modules": [{"path": ".claude/rules/skill-routing.md", "action": "modify"}],
    "acceptance_criteria": [
        {"id": "AC1", "text": "fixture", "category": "functional", "negative": False, "verification": {"method": "unit_test", "detail": "fixture"}}
    ],
    "dependencies": [],
    "edge_cases": [],
    "predecessor_audit": [],
}
path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

HASH="$(python3 - "$SOURCE" <<'PY'
import hashlib
import sys
from pathlib import Path

source = Path(sys.argv[1])
digest = hashlib.sha256()
for name in ("refinement.md", "refinement.json"):
    path = source / name
    digest.update(name.encode("utf-8"))
    digest.update(b"\0")
    digest.update(path.read_bytes())
    digest.update(b"\0")
print("sha256:" + digest.hexdigest())
PY
)"

LEDGER="$TMP/valid-routing-ledger.json"
python3 - "$LEDGER" "$SOURCE" "$HASH" <<'PY'
import json
import sys
from pathlib import Path

path, source, ref_hash = sys.argv[1:4]
payload = {
    "schema_version": "1",
    "source": {
        "id": "DP-998",
        "container": source,
        "refinement_hash": ref_hash,
    },
    "started_at": "2026-05-19T10:00:00+08:00",
    "resumed_at": None,
    "terminal_status": None,
    "consent_policy": {
        "auto_reestimate": True,
        "auto_resplit": True,
        "auto_task_repair": True,
    },
    "consent_excludes": [
        "base_branch_force_push",
        "force_push_without_lease",
        "history_rewrite",
        "merge",
        "release",
        "deploy",
        "production_write",
        "jira_child_write",
        "jira_comment_write",
        "jira_worklog_write",
        "task_scope_outside_mutation",
    ],
    "task_snapshot": [],
    "stage_events": [],
    "loop_counters": {
        "engineering_to_breakdown": 0,
        "breakdown_to_refinement_inbox": 0,
    },
    "drift_retry": {},
    "pause": None,
}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

bash "$ROOT/scripts/validate-auto-pass-ledger.sh" "$LEDGER" \
  --source-container "$SOURCE" \
  --source-id DP-998 \
  --task-write-at "2026-05-19T10:01:00+08:00"

pushd "$TMP" >/dev/null
expect_fail "relative-ledger-path" bash "$ROOT/scripts/validate-auto-pass-ledger.sh" "valid-routing-ledger.json" \
  --source-container "$SOURCE" \
  --source-id DP-998
popd >/dev/null

SOURCE_MISMATCH="$TMP/source-mismatch.json"
cp "$LEDGER" "$SOURCE_MISMATCH"
python3 - "$SOURCE_MISMATCH" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["source"]["id"] = "DP-997"
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail "source-mismatch" bash "$ROOT/scripts/validate-auto-pass-ledger.sh" "$SOURCE_MISMATCH" \
  --source-container "$SOURCE" \
  --source-id DP-998

STALE="$TMP/stale.json"
cp "$LEDGER" "$STALE"
python3 - "$STALE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["source"]["refinement_hash"] = "sha256:stale"
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
expect_fail "stale-artifact" bash "$ROOT/scripts/validate-auto-pass-ledger.sh" "$STALE" \
  --source-container "$SOURCE" \
  --source-id DP-998

echo "PASS: auto-pass routing and ledger consent selftest"
