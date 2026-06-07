#!/usr/bin/env bash
# Purpose: DP-294 T5 / AC6 — selftest for the refinement-inbox canonical producer
#          token. Asserts (a) the deterministic writer
#          (scripts/write-producer-owned-artifact.sh) accepts the
#          `refinement:inbox-record` token and writes an inbox record that passes
#          validate-refinement-inbox-record.sh, and (b) the
#          no-direct-evidence-write.sh hook recognizes the same token+glob and
#          bypasses, while a token+path mismatch stays fail-closed.
# Inputs:  none (hermetic tmp body + tail-matched inbox glob paths).
# Outputs: PASS/FAIL lines; exit 0 (all pass) / 1 (any fail).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRITER="$ROOT/scripts/write-producer-owned-artifact.sh"
HOOK="$ROOT/.claude/hooks/no-direct-evidence-write.sh"
INBOX_VALIDATOR="$ROOT/scripts/validate-refinement-inbox-record.sh"
for f in "$WRITER" "$HOOK" "$INBOX_VALIDATOR"; do
  [[ -x "$f" ]] || { echo "FAIL: missing/not executable: $f" >&2; exit 1; }
done

TMP="$(mktemp -d -t refinement-inbox-producer-XXXX)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1" >&2; }

# Canonical inbox record body (breakdown scope-escalation schema). Must pass
# validate-refinement-inbox-record.sh.
BODY="$TMP/body.md"
cat >"$BODY" <<'EOF'
---
skill: breakdown
target_skill: refinement
source: scope-escalation
route: refinement
source_type: dp
source_id: DP-999
source_task: T1
source_ticket: N/A
source_sidecar: docs-manager/src/content/docs/specs/design-plans/DP-999-inbox/escalations/T1-1.md
escalation_count: 1
created_at: 2026-06-07T00:00:00Z
consumed: false
---

## Decision

re-classified to refinement: AC boundary must be re-decided.

## Refinement Context

- Gate summary: scope exceeded the planned task boundary.

## Decisions Needed

1. Decide whether the AC budget remains mandatory.

## Source Audit

- Source sidecar path is for audit only; refinement must not open it.
EOF

# Tail-matched inbox glob path (writer resolves the producer table from its own
# location, so the absolute target only needs a glob-matching suffix).
INBOX_DIR="$TMP/repo/docs-manager/src/content/docs/specs/design-plans/DP-999-inbox/refinement-inbox"
mkdir -p "$INBOX_DIR"
TARGET="$INBOX_DIR/T1-1-20260607T000000Z.md"

# === (a) writer accepts the canonical token + writes a valid inbox record =====
if bash "$WRITER" --producer-token refinement:inbox-record \
     --path "$TARGET" --body-file "$BODY" >/dev/null 2>&1; then
  ok
else
  bad "writer should accept refinement:inbox-record token (exit 0)"
fi

if [[ -f "$TARGET" ]]; then ok; else bad "writer should materialize the inbox record at TARGET"; fi

if bash "$INBOX_VALIDATOR" "$TARGET" >/dev/null 2>&1; then
  ok
else
  bad "written inbox record should pass validate-refinement-inbox-record.sh"
fi

# Writer must reject the token when the path is outside the inbox globs.
OUT_OF_GLOBS="$TMP/repo/docs-manager/src/content/docs/specs/design-plans/DP-999-inbox/notes.md"
if bash "$WRITER" --producer-token refinement:inbox-record \
     --path "$OUT_OF_GLOBS" --body-file "$BODY" >/dev/null 2>&1; then
  bad "writer should reject inbox token for a non-inbox path (exit 2)"
else
  ok
fi

# === (b) no-direct-evidence-write hook recognizes token+glob bypass ===========
INBOX_REL="docs-manager/src/content/docs/specs/design-plans/DP-999-inbox/refinement-inbox/T1-1-20260607T000000Z.md"
hook_input() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1"; }

if hook_input "$INBOX_REL" | POLARIS_PRODUCER=refinement:inbox-record bash "$HOOK" >/dev/null 2>&1; then
  ok
else
  bad "hook should bypass write for refinement:inbox-record token on an inbox glob"
fi

# token present but path is protected-but-not-inbox -> fail-closed (exit 2).
NON_INBOX_REL="docs-manager/src/content/docs/specs/design-plans/DP-999-inbox/notes.md"
if hook_input "$NON_INBOX_REL" | POLARIS_PRODUCER=refinement:inbox-record bash "$HOOK" >/dev/null 2>&1; then
  bad "hook should deny inbox token on a non-inbox protected path (exit 2)"
else
  ok
fi

# unknown token on an inbox path -> fail-closed (exit 2).
if hook_input "$INBOX_REL" | POLARIS_PRODUCER=refinement:not-a-token bash "$HOOK" >/dev/null 2>&1; then
  bad "hook should deny an unregistered producer token (exit 2)"
else
  ok
fi

echo "[refinement-inbox-producer-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
