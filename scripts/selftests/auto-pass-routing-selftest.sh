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

reject_text() {
  local file="$1"
  local pattern="$2"
  if grep -Fq -- "$pattern" "$file"; then
    echo "FAIL: unexpected DP-only pattern still present in $file: $pattern" >&2
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

# -----------------------------------------------------------------------------
# Phase 1 — Source-neutral routing prose assertions (AC-NF4)
# -----------------------------------------------------------------------------

# Source-neutral matrix shape: {KEY} placeholder + refinement-owned source wording.
require_text "$ROOT/.claude/rules/skill-routing.md" "Trigger × Source-State Matrix"
require_text "$ROOT/.claude/rules/skill-routing.md" 'LOCKED` + current refinement artifact | `/auto-pass {KEY}`'
require_text "$ROOT/.claude/rules/skill-routing.md" 'DISCUSSION` / missing artifact / stale artifact | `refinement {KEY}`'
require_text "$ROOT/.claude/rules/skill-routing.md" 'workspace PR opened + verification stale | `auto-pass {KEY}` refresh verify-AC'
require_text "$ROOT/.claude/rules/skill-routing.md" "prose-only rule 自行逐 stage dispatch"
require_text "$ROOT/.claude/rules/skill-routing.md" "DP-backed 與 JIRA Epic-backed source 共用同一條 routing matrix"
require_text "$ROOT/.claude/rules/skill-routing.md" "framework workspace 專屬"

# Reject leftover DP-only matrix entries from pre-T16 baseline.
reject_text "$ROOT/.claude/rules/skill-routing.md" 'LOCKED` + current DP-backed source | `auto-pass DP-NNN`'
reject_text "$ROOT/.claude/rules/skill-routing.md" 'no DP source'

# Canonical contract governance source-parity rule (AC-NF4 + AC-NF1 pointer).
require_text "$ROOT/.claude/rules/canonical-contract-governance.md" "Source Parity"
require_text "$ROOT/.claude/rules/canonical-contract-governance.md" "DP-backed source"
require_text "$ROOT/.claude/rules/canonical-contract-governance.md" "JIRA Epic-backed source"
require_text "$ROOT/.claude/rules/canonical-contract-governance.md" "No DP-only writer path"
require_text "$ROOT/.claude/rules/canonical-contract-governance.md" "No DP-only routing prose"
require_text "$ROOT/.claude/rules/canonical-contract-governance.md" "spec-source-parity-allowlist.txt"
require_text "$ROOT/.claude/rules/canonical-contract-governance.md" "validate-spec-source-parity.sh"

# Existing breakdown / auto-pass references stay source-neutral (regression guard for T9).
require_text "$ROOT/.claude/skills/breakdown/SKILL.md" "AUTO_PASS_LEDGER_PATH=<absolute ledger path>"
require_text "$ROOT/.claude/skills/references/breakdown-dp-intake-flow.md" "Auto-pass Ledger Consent"
require_text "$ROOT/.claude/skills/references/breakdown-dp-intake-flow.md" '--task-write-at "{task_write_iso8601}"'
require_text "$ROOT/.claude/skills/auto-pass/SKILL.md" "Routing Policy"
require_text "$ROOT/.claude/skills/auto-pass/SKILL.md" "refresh verify-AC，不重跑 breakdown"

# -----------------------------------------------------------------------------
# Phase 2 — Parameterized ledger validation across DP / JIRA source types (AC-NF4)
# -----------------------------------------------------------------------------

# build_source_container <slug-relative-path> <source-type> <source-id>
# Materializes a refinement-owned source container with index.md + refinement.md +
# refinement.json under $TMP, then writes its sha256 refinement_hash to stdout.
build_source_container() {
  local rel="$1"
  local source_type="$2"
  local source_id="$3"
  local container="$TMP/$rel"

  mkdir -p "$container"

  cat >"$container/index.md" <<MD
---
title: "${source_id}: routing fixture"
description: "auto-pass routing fixture"
status: LOCKED
locked_at: 2026-05-19
---

# ${source_id} fixture
MD

  cat >"$container/refinement.md" <<MD
---
title: "${source_id} Refinement"
description: "auto-pass routing fixture refinement"
---

## Scope

此 fixture 用於驗證 auto-pass routing ledger consent (${source_type})。
MD

  python3 - "$container/refinement.json" "$container" "$source_type" "$source_id" <<'PY'
import json
import sys
from pathlib import Path

ref_json_path, container, source_type, source_id = sys.argv[1:5]
container_path = Path(container)
payload = {
    "version": "1",
    "created_at": "2026-05-19T10:00:00+08:00",
    "source": {
        "type": source_type,
        "id": source_id,
        "container": str(container_path),
        "plan_path": str(container_path / "index.md"),
        "jira_key": source_id if source_type == "jira" else None,
    },
    "modules": [{"path": ".claude/rules/skill-routing.md", "action": "modify"}],
    "acceptance_criteria": [
        {"id": "AC1", "text": "fixture", "category": "functional", "negative": False, "verification": {"method": "unit_test", "detail": "fixture"}}
    ],
    "dependencies": [],
    "edge_cases": [],
    "predecessor_audit": [],
}
Path(ref_json_path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

  python3 - "$container" <<'PY'
import hashlib
import sys
from pathlib import Path

container = Path(sys.argv[1])
digest = hashlib.sha256()
for name in ("refinement.md", "refinement.json"):
    path = container / name
    digest.update(name.encode("utf-8"))
    digest.update(b"\0")
    digest.update(path.read_bytes())
    digest.update(b"\0")
print("sha256:" + digest.hexdigest())
PY
}

# write_ledger <output-path> <container> <source-type> <source-id> <refinement-hash>
write_ledger() {
  local out="$1"
  local container="$2"
  local source_type="$3"
  local source_id="$4"
  local ref_hash="$5"

  python3 - "$out" "$container" "$source_type" "$source_id" "$ref_hash" <<'PY'
import json
import sys
from pathlib import Path

out, container, source_type, source_id, ref_hash = sys.argv[1:6]
payload = {
    "schema_version": "1",
    "source": {
        "id": source_id,
        "container": container,
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
# Include source.type only when present so we exercise both shapes.
if source_type:
    payload["source"]["type"] = source_type
# DP-228 AC14 (T7): JIRA source requires jira_status_transition + jira_status_consent_record.
if source_type in ("jira", "bug"):
    payload["consent_policy"]["jira_status_transition"] = True
    payload["jira_status_consent_record"] = {
        "session_id": "selftest-session",
        "source_id": source_id,
        "granted_at": "2026-05-19T09:55:00+08:00",
        "ttl_seconds": 7200,
    }
Path(out).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

# Two parameterized fixtures: DP-backed (DP-998) + JIRA Epic-backed (EXAMPLE-9999).
# Both must validate symmetrically through the same ledger writer path.
FIXTURES=(
  "docs-manager/src/content/docs/specs/design-plans/DP-998-routing-fixture|dp|DP-998"
  "docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-9999|jira|EXAMPLE-9999"
)

for entry in "${FIXTURES[@]}"; do
  IFS='|' read -r rel source_type source_id <<<"$entry"
  container="$TMP/$rel"
  hash_value="$(build_source_container "$rel" "$source_type" "$source_id")"
  ledger="$TMP/${source_id}-routing-ledger.json"
  write_ledger "$ledger" "$container" "$source_type" "$source_id" "$hash_value"

  # Positive case: validator accepts a locked container with matching hash for both
  # DP-backed and JIRA Epic-backed sources (single writer path, no source-type fast lane).
  bash "$ROOT/scripts/validate-auto-pass-ledger.sh" "$ledger" \
    --source-container "$container" \
    --source-id "$source_id" \
    --task-write-at "2026-05-19T10:01:00+08:00"

  # Negative case 1: relative ledger path is rejected for both source types.
  pushd "$TMP" >/dev/null
  expect_fail "${source_id}-relative-ledger-path" \
    bash "$ROOT/scripts/validate-auto-pass-ledger.sh" "${source_id}-routing-ledger.json" \
    --source-container "$container" \
    --source-id "$source_id"
  popd >/dev/null

  # Negative case 2: source.id mismatch is rejected for both source types.
  mismatch="$TMP/${source_id}-source-mismatch.json"
  cp "$ledger" "$mismatch"
  python3 - "$mismatch" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["source"]["id"] = data["source"]["id"] + "-MISMATCH"
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  expect_fail "${source_id}-source-mismatch" \
    bash "$ROOT/scripts/validate-auto-pass-ledger.sh" "$mismatch" \
    --source-container "$container" \
    --source-id "$source_id"

  # Negative case 3: stale refinement_hash is rejected for both source types.
  stale="$TMP/${source_id}-stale.json"
  cp "$ledger" "$stale"
  python3 - "$stale" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["source"]["refinement_hash"] = "sha256:stale"
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  expect_fail "${source_id}-stale-artifact" \
    bash "$ROOT/scripts/validate-auto-pass-ledger.sh" "$stale" \
    --source-container "$container" \
    --source-id "$source_id"
done

echo "PASS: auto-pass routing and ledger consent selftest (DP-backed + JIRA Epic-backed source parity)"
