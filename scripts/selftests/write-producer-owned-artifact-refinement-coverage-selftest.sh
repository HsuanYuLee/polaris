#!/usr/bin/env bash
# Purpose: DP-274 T3 (D9) — verify scripts/write-producer-owned-artifact.sh has a
#          sanctioned writer branch for refinement design documents (refinement.md /
#          refinement.json) AND for the refinement-owned container index.md primary
#          doc, both bound to the refinement owning glob + content validator, while
#          non-owning skills / non-glob paths stay BLOCKED.
# Inputs:  none (self-contained; uses tmpdir fixtures + repo-tracked validators).
# Outputs: stdout "PASS" + exit 0 on success; diagnostic + non-zero exit on failure.
# Side effects: writes/cleans fixtures under tmpdir only; the sanctioned-write happy
#          path targets a tmpdir DP / Epic container so no tracked specs are mutated.
#
# Cases (refinement design doc, artifact_kind=refinement_design_doc):
#   AC5     sanctioned write — correct producer token (refinement:design-doc) +
#           owning refinement glob (DP-backed refinement.json) + valid body → exit
#           0, file written, content validator dispatched.
#   AC5     sanctioned write — same for an Epic-backed refinement.json path
#           (companies/{company}/{EPIC}/refinement.json) → exit 0 (source parity).
#   AC-NEG2 non-glob path — correct token but path NOT in the refinement owning
#           glob (arbitrary .md elsewhere) → exit 2 PATH_OUT_OF_GLOBS, no write.
#   AC-NEG2 non-owning skill — a foreign producer token (breakdown:initial-create)
#           writing to a refinement.json path → exit 2 (path not covered by that
#           producer's globs), no write. Token-first lookup must NOT let any
#           skill / any .md bypass the owning-skill binding.
#   AC-NEG2 content validator failure — correct token + owning glob but an invalid
#           refinement.json body → exit 2 (validator rollback), no surviving write.
#
# Cases (container index.md primary doc, artifact_kind=refinement_primary_doc):
#   AC5     sanctioned write — correct producer token (refinement:primary-doc) +
#           owning DP container index.md glob + Starlight-valid LOCKED body → exit
#           0, file written, primary-doc content validator dispatched, status field
#           lands on disk. T4 will reuse this token to flip status:SUPERSEDED.
#   AC-NEG2 non-glob path — refinement:primary-doc token but path NOT in any
#           refinement owning glob (arbitrary .md at repo root) → exit 2, no write.
#   AC-NEG2 non-owning skill — a foreign producer token (breakdown:initial-create)
#           writing to a container index.md path → exit 2 (path not covered by that
#           producer's globs), no write.
#   AC-NEG2 content validator failure — correct token + owning glob but an invalid
#           index.md body (missing description, duplicate H1) → exit 2 (rollback),
#           no surviving write.

set -euo pipefail

if ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$ROOT_DIR" ]]; then
  :
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
WRITER="$ROOT_DIR/scripts/write-producer-owned-artifact.sh"
PRODUCERS_JSON="$ROOT_DIR/scripts/lib/evidence-producers.json"
WORKDIR="$(mktemp -d -t dp274-refinement-writer.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -x "$WRITER" ]]; then
  echo "FAIL: writer not executable: $WRITER" >&2
  exit 1
fi
if [[ ! -f "$PRODUCERS_JSON" ]]; then
  echo "FAIL: producers table missing: $PRODUCERS_JSON" >&2
  exit 1
fi

# Contract assertion: the refinement-md-writer entry declares the sanctioned token,
# the token is unique across producer_tokens[] (no broad bypass token), and the
# owning globs cover BOTH DP-backed and Epic-backed refinement.json (source parity).
python3 - <<PY
import json, sys
data = json.load(open("$PRODUCERS_JSON"))
seen = {}
refinement_entry = None
for p in data.get("producers", []):
    for t in (p.get("producer_tokens") or []):
        if t in seen:
            print(f"FAIL (token-uniqueness): token '{t}' duplicated in producer entries", file=sys.stderr)
            sys.exit(1)
        seen[t] = True
    if "refinement:design-doc" in (p.get("producer_tokens") or []):
        refinement_entry = p
if refinement_entry is None:
    print("FAIL: producer_tokens[] missing 'refinement:design-doc' on a refinement entry", file=sys.stderr)
    sys.exit(1)
if refinement_entry.get("owning_skill") != "refinement":
    print("FAIL: refinement:design-doc token must bind to owning_skill=refinement", file=sys.stderr)
    sys.exit(1)
globs = refinement_entry.get("path_globs") or []
need_dp = any("design-plans/DP-" in g and g.endswith("refinement.json") for g in globs)
need_epic = any("companies/" in g and g.endswith("refinement.json") for g in globs)
if not (need_dp and need_epic):
    print("FAIL: refinement owning globs must cover BOTH DP-backed and Epic-backed refinement.json (source parity)", file=sys.stderr)
    sys.exit(1)
# Container index.md primary doc: the spec-index-status-writer entry must declare
# the refinement:primary-doc token, the token is unique, it binds to
# owning_skill=refinement, and its globs cover BOTH DP-backed and Epic-backed
# container index.md (source parity).
index_entry = None
for p in data.get("producers", []):
    if "refinement:primary-doc" in (p.get("producer_tokens") or []):
        index_entry = p
if index_entry is None:
    print("FAIL: producer_tokens[] missing 'refinement:primary-doc' on a refinement index entry", file=sys.stderr)
    sys.exit(1)
if index_entry.get("owning_skill") != "refinement":
    print("FAIL: refinement:primary-doc token must bind to owning_skill=refinement", file=sys.stderr)
    sys.exit(1)
iglobs = index_entry.get("path_globs") or []
inew_dp = any("design-plans/DP-" in g and g.endswith("index.md") for g in iglobs)
inew_epic = any("companies/" in g and g.endswith("index.md") for g in iglobs)
if not (inew_dp and inew_epic):
    print("FAIL: refinement:primary-doc owning globs must cover BOTH DP-backed and Epic-backed container index.md (source parity)", file=sys.stderr)
    sys.exit(1)
PY

# Synthesize a schema-complete, location-consistent refinement.json body for the
# given target directory. The validator (validate-refinement-json.sh) requires
# source.container / source.plan_path to exist and to point at the target's own
# directory, so the body is built per target path. Hermetic: no dependency on
# gitignored tracked specs that may be absent in a fresh clone.
write_valid_body() {
  local target_path="$1" body_out="$2"
  local container; container="$(dirname "$target_path")"
  mkdir -p "$container"
  : >"$container/index.md"
  CONTAINER="$container" python3 - "$body_out" <<'PY'
import json, os, sys
container = os.environ["CONTAINER"]
body = {
    "epic": None,
    "source": {
        "type": "dp",
        "id": "DP-999",
        "container": container,
        "plan_path": os.path.join(container, "index.md"),
        "jira_key": None,
    },
    "version": "1.0",
    "schema_version": "1.0",
    "created_at": "2026-06-03T00:00:00Z",
    "modules": [{"path": "scripts/x.sh", "action": "modify"}],
    "acceptance_criteria": [
        {"id": "AC1", "text": "t", "verification": {"method": "unit_test", "detail": "d"}}
    ],
    "dependencies": [],
    "edge_cases": [],
    "predecessor_audit": [],
    "adversarial_pass": [{"ac_id": "AC1", "attack": "a", "enforce": "e"}],
    "changed_files": ["scripts/x.sh"],
    "tasks": [
        {
            "id": "T1", "kind": "T", "title": "新增 sanctioned writer fixture", "scope": "建立 refinement writer selftest fixture。",
            "modules": ["scripts/x.sh"],
            "ac_ids": ["AC1"], "dependencies": [],
            "verification": {"method": "unit_test", "detail": "echo PASS", "verify_command": "echo PASS"},
        }
    ],
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(body, fh)
PY
}

write_valid_jira_body() {
  local target_path="$1" body_out="$2"
  local container; container="$(dirname "$target_path")"
  mkdir -p "$container"
  : >"$container/index.md"
  EPIC_KEY="$(basename "$container")" python3 - "$body_out" <<'PY'
import json, os, sys
body = {
    "epic": os.environ["EPIC_KEY"],
    "source": {
        "type": "jira",
        "repo": "example-product",
        "base_branch": "main",
    },
    "version": "1.0",
    "schema_version": "1.0",
    "created_at": "2026-06-03T00:00:00Z",
    "modules": [{"path": "scripts/x.sh", "action": "modify"}],
    "acceptance_criteria": [
        {"id": "AC1", "text": "t", "verification": {"method": "unit_test", "detail": "d"}}
    ],
    "dependencies": [],
    "edge_cases": [],
    "predecessor_audit": [],
    "adversarial_pass": [{"ac_id": "AC1", "attack": "a", "enforce": "e"}],
    "changed_files": ["scripts/x.sh"],
    "tasks": [
        {
            "id": "T1", "kind": "T", "title": "新增 sanctioned writer fixture", "scope": "建立 refinement writer selftest fixture。",
            "modules": ["scripts/x.sh"],
            "ac_ids": ["AC1"], "dependencies": [],
            "verification": {"method": "unit_test", "detail": "echo PASS", "verify_command": "echo PASS"},
        }
    ],
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(body, fh)
PY
}

# DP-444 AC2: the caller-owned body must be snapshotted before any refinement
# preflight, and only that writer-owned snapshot may be promoted.
python3 - "$WRITER" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
snapshot = 'cp "$BODY_FILE" "$tmp_target"'
preflight = '--candidate-for "$TARGET_PATH"'
promotion = 'mv -f "$tmp_target" "$TARGET_PATH"'
try:
    snapshot_at = text.index(snapshot)
    preflight_at = text.index(preflight)
    promotion_at = text.index(promotion)
except ValueError as exc:
    print(f"FAIL (candidate-snapshot): writer snapshot contract is incomplete: {exc}", file=sys.stderr)
    raise SystemExit(1)
if not snapshot_at < preflight_at < promotion_at:
    print("FAIL (candidate-snapshot): snapshot/preflight/promotion ordering regressed", file=sys.stderr)
    raise SystemExit(1)
if '"$BODY_FILE"' in text[snapshot_at + len(snapshot):promotion_at]:
    print("FAIL (candidate-snapshot): writer rereads caller-owned body after snapshot", file=sys.stderr)
    raise SystemExit(1)
PY

# AC5 happy path (DP-backed): sanctioned write to a tmpdir DP container
# refinement.json. Using a tmpdir target keeps the tracked specs tree untouched;
# the writer's glob match is path-shape based (tail glob), so a tmpdir DP-*
# container path matches.
dp_target="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-999-fixture-refinement-coverage/refinement.json"
dp_body="$WORKDIR/dp-body.json"
write_valid_body "$dp_target" "$dp_body"
set +e
"$WRITER" \
  --producer-token refinement:design-doc \
  --path "$dp_target" \
  --body-file "$dp_body" >"$WORKDIR/dp-happy.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (dp-happy): expected exit 0, got $rc" >&2
  cat "$WORKDIR/dp-happy.out" >&2
  exit 1
fi
if [[ ! -f "$dp_target" ]]; then
  echo "FAIL (dp-happy): writer reported success but file missing" >&2
  exit 1
fi
grep -q 'artifact_kind=refinement_design_doc' "$WORKDIR/dp-happy.out"

# AC5 happy path (Epic-backed source parity): sanctioned write to a tmpdir Epic
# container refinement.json.
epic_target="$WORKDIR/docs-manager/src/content/docs/specs/companies/exampleco/EX-1234/refinement.json"
epic_body="$WORKDIR/epic-body.json"
write_valid_jira_body "$epic_target" "$epic_body"
set +e
"$WRITER" \
  --producer-token refinement:design-doc \
  --path "$epic_target" \
  --body-file "$epic_body" >"$WORKDIR/epic-happy.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (epic-happy): expected exit 0, got $rc" >&2
  cat "$WORKDIR/epic-happy.out" >&2
  exit 1
fi
if [[ ! -f "$epic_target" ]]; then
  echo "FAIL (epic-happy): writer reported success but file missing" >&2
  exit 1
fi

# AC-NEG2 (non-glob path): correct token but path NOT in refinement owning glob.
oos_target="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-999-fixture-refinement-coverage/not-a-refinement-doc.md"
set +e
"$WRITER" \
  --producer-token refinement:design-doc \
  --path "$oos_target" \
  --body-file "$dp_body" >"$WORKDIR/neg-glob.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (neg-glob): expected exit 2, got $rc" >&2
  cat "$WORKDIR/neg-glob.out" >&2
  exit 1
fi
grep -q 'not covered by producer' "$WORKDIR/neg-glob.out"
if [[ -f "$oos_target" ]]; then
  echo "FAIL (neg-glob): writer should not have created the file" >&2
  exit 1
fi

# AC-NEG2 (non-owning skill): a foreign producer token writing to a refinement.json
# path must be BLOCKED — the refinement glob is bound to the refinement owning skill,
# not borrowable by another skill's token.
neg_skill_target="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-997-fixture-non-owning/refinement.json"
neg_skill_body="$WORKDIR/neg-skill-body.json"
write_valid_body "$neg_skill_target" "$neg_skill_body"
rm -f "$neg_skill_target"  # ensure no pre-existing file before the blocked write
set +e
"$WRITER" \
  --producer-token breakdown:initial-create \
  --path "$neg_skill_target" \
  --body-file "$neg_skill_body" >"$WORKDIR/neg-skill.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (neg-skill): non-owning token must be BLOCKED on refinement.json path; expected exit 2, got $rc" >&2
  cat "$WORKDIR/neg-skill.out" >&2
  exit 1
fi
grep -q 'not covered by producer' "$WORKDIR/neg-skill.out"
if [[ -f "$neg_skill_target" ]]; then
  echo "FAIL (neg-skill): non-owning token should not have created the file" >&2
  exit 1
fi

# AC-NEG2 (content validator failure): correct token + owning glob but invalid body
# → content validator fails, writer rolls back; no surviving write.
invalid_body="$WORKDIR/invalid-refinement.json"
printf '{"not":"a valid refinement schema"}' >"$invalid_body"
invalid_target="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-998-fixture-invalid-refinement/refinement.json"
mkdir -p "$(dirname "$invalid_target")"
set +e
"$WRITER" \
  --producer-token refinement:design-doc \
  --path "$invalid_target" \
  --body-file "$invalid_body" >"$WORKDIR/neg-content.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (neg-content): invalid refinement body must fail content validator; expected exit 2, got $rc" >&2
  cat "$WORKDIR/neg-content.out" >&2
  exit 1
fi
if [[ -f "$invalid_target" ]]; then
  echo "FAIL (neg-content): writer should have rolled back the invalid write" >&2
  exit 1
fi

# DP-444 AC2 / AC-NF1: LOCKED refinement.json amendments must compare the
# on-disk current file with the candidate before the atomic rename. Run the
# same protected-mutation fixture under DP-backed and Epic-shaped containers.
run_locked_protected_mutation_case() {
  local label="$1" target="$2" source_type="${3:-dp}"
  local current_body="$WORKDIR/${label}-current.json"
  local candidate="$WORKDIR/${label}-candidate.json"
  local container; container="$(dirname "$target")"
  local ledger="$container/artifacts/auto-pass/ledger.json"
  local derived="$container/refinement.md"

  if [[ "$source_type" == "jira" ]]; then
    write_valid_jira_body "$target" "$current_body"
  else
    write_valid_body "$target" "$current_body"
  fi
  cp "$current_body" "$target"
  cat >"$container/index.md" <<'EOF'
---
title: "LOCKED refinement writer fixture"
status: LOCKED
---
EOF
  printf '%s\n' 'derived view must remain byte-identical' >"$derived"
  mkdir -p "$(dirname "$ledger")"
  printf '%s\n' 'ledger sentinel must remain byte-identical' >"$ledger"
  cp "$current_body" "$candidate"
  python3 - "$candidate" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
data["scope"] = ["protected scope rewrite"]
p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

  local target_before ledger_before derived_before rc=0
  target_before="$(cksum "$target")"
  ledger_before="$(cksum "$ledger")"
  derived_before="$(cksum "$derived")"
  "$WRITER" \
    --producer-token refinement:design-doc \
    --path "$target" \
    --body-file "$candidate" \
    --source-container "$container" \
    --source-id DP-999 \
    --ledger-path "$ledger" >"$WORKDIR/${label}-locked.out" 2>&1 || rc=$?
  if [[ "$rc" -ne 2 ]]; then
    echo "FAIL ($label): protected LOCKED mutation expected exit 2, got $rc" >&2
    cat "$WORKDIR/${label}-locked.out" >&2
    exit 1
  fi
  grep -q 'POLARIS_LOCKED_SCOPE_VIOLATION' "$WORKDIR/${label}-locked.out" || {
    echo "FAIL ($label): protected mutation missing LOCKED-scope marker" >&2
    cat "$WORKDIR/${label}-locked.out" >&2
    exit 1
  }
  [[ "$(cksum "$target")" == "$target_before" ]] || {
    echo "FAIL ($label): target changed before protected-mutation rejection" >&2
    exit 1
  }
  [[ "$(cksum "$ledger")" == "$ledger_before" ]] || {
    echo "FAIL ($label): ledger changed before protected-mutation rejection" >&2
    exit 1
  }
  [[ "$(cksum "$derived")" == "$derived_before" ]] || {
    echo "FAIL ($label): derived view changed before protected-mutation rejection" >&2
    exit 1
  }
}

run_locked_protected_mutation_case \
  "locked-dp" \
  "$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-994-locked-writer/refinement.json"
run_locked_protected_mutation_case \
  "locked-epic" \
  "$WORKDIR/docs-manager/src/content/docs/specs/companies/exampleco/EX-994/refinement.json" \
  jira

# DP-444 AC2: malformed candidate must be rejected before replacing an existing
# LOCKED target, with a dedicated pre-write marker.
malformed_target="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-993-malformed-candidate/refinement.json"
malformed_current="$WORKDIR/malformed-current.json"
write_valid_body "$malformed_target" "$malformed_current"
cp "$malformed_current" "$malformed_target"
cat >"$(dirname "$malformed_target")/index.md" <<'EOF'
---
title: "Malformed candidate fixture"
status: LOCKED
---
EOF
malformed_before="$(cksum "$malformed_target")"
rc=0
"$WRITER" \
  --producer-token refinement:design-doc \
  --path "$malformed_target" \
  --body-file "$invalid_body" >"$WORKDIR/malformed-prewrite.out" 2>&1 || rc=$?
if [[ "$rc" -ne 2 ]] || ! grep -q 'POLARIS_REFINEMENT_CANDIDATE_INVALID' "$WORKDIR/malformed-prewrite.out"; then
  echo "FAIL (malformed-prewrite): malformed LOCKED candidate was not rejected before write" >&2
  cat "$WORKDIR/malformed-prewrite.out" >&2
  exit 1
fi
[[ "$(cksum "$malformed_target")" == "$malformed_before" ]] || {
  echo "FAIL (malformed-prewrite): target changed before malformed-candidate rejection" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Container index.md primary doc (artifact_kind=refinement_primary_doc).
# ---------------------------------------------------------------------------

# Synthesize a Starlight-valid DP container index.md body. LOCKED status keeps
# the fixture clean (SUPERSEDED would additionally require supersession summary
# metadata, which the validator correctly enforces but is the caller's concern,
# not this writer-capability test). The body is intentionally minimal but valid:
# frontmatter title/description/status + a single non-H1 section.
write_valid_index_body() {
  local body_out="$1" title="$2" status="${3:-LOCKED}"
  cat >"$body_out" <<EOF
---
title: "$title"
description: "DP-274 T3 sanctioned-writer selftest 用的 container index fixture。"
status: $status
---

## 背景

供 selftest 使用的 container index 內容，會被 sanctioned writer 整份覆寫；涵蓋 AC1。
EOF
}

# AC5 happy path (DP-backed index.md): sanctioned write to a tmpdir DP container
# index.md. The writer glob match is path-shape based, so a tmpdir DP-* path matches.
idx_target="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-999-fixture-index-coverage/index.md"
idx_body="$WORKDIR/idx-body.md"
mkdir -p "$(dirname "$idx_target")"
idx_refinement="$(dirname "$idx_target")/refinement.json"
idx_refinement_body="$WORKDIR/idx-refinement.json"
write_valid_body "$idx_refinement" "$idx_refinement_body"
cp "$idx_refinement_body" "$idx_refinement"
bash "$ROOT_DIR/scripts/render-refinement-md.sh" "$idx_refinement" >"$(dirname "$idx_target")/refinement.md"
# This selftest owns sanctioned-writer coverage, not the DISCUSSION -> LOCKED
# transition readiness contract. Keep the current fixture LOCKED so the primary
# doc rewrite exercises LOCKED -> LOCKED and does not depend on unrelated
# handoff-advisory fixtures.
write_valid_index_body "$idx_target" "DP-999 Fixture Index Coverage" LOCKED
write_valid_index_body "$idx_body" "DP-999 Fixture Index Coverage"
set +e
"$WRITER" \
  --producer-token refinement:primary-doc \
  --path "$idx_target" \
  --body-file "$idx_body" >"$WORKDIR/idx-happy.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (idx-happy): expected exit 0, got $rc" >&2
  cat "$WORKDIR/idx-happy.out" >&2
  exit 1
fi
if [[ ! -f "$idx_target" ]]; then
  echo "FAIL (idx-happy): writer reported success but index.md missing" >&2
  exit 1
fi
grep -q 'artifact_kind=refinement_primary_doc' "$WORKDIR/idx-happy.out" || {
  echo "FAIL (idx-happy): expected artifact_kind=refinement_primary_doc in writer output" >&2
  cat "$WORKDIR/idx-happy.out" >&2
  exit 1
}
# Status field must land on disk (T4 relies on this to flip status:SUPERSEDED).
grep -q '^status: LOCKED$' "$idx_target" || {
  echo "FAIL (idx-happy): status field did not land in the written index.md" >&2
  exit 1
}

# AC-NEG2 (non-glob path): refinement:primary-doc token but path NOT in any
# refinement owning glob (arbitrary .md at repo root) → BLOCKED, no write.
idx_oos_target="$WORKDIR/some-arbitrary-readme.md"
set +e
"$WRITER" \
  --producer-token refinement:primary-doc \
  --path "$idx_oos_target" \
  --body-file "$idx_body" >"$WORKDIR/idx-neg-glob.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (idx-neg-glob): expected exit 2, got $rc" >&2
  cat "$WORKDIR/idx-neg-glob.out" >&2
  exit 1
fi
grep -q 'not covered by producer' "$WORKDIR/idx-neg-glob.out"
if [[ -f "$idx_oos_target" ]]; then
  echo "FAIL (idx-neg-glob): writer should not have created the file" >&2
  exit 1
fi

# AC-NEG2 (non-owning skill): a foreign producer token writing to a container
# index.md path must be BLOCKED — the index.md glob is bound to the refinement
# owning skill, not borrowable by another skill's token. breakdown:initial-create
# globs are tasks/T*/index.md & tasks/V*/index.md, so a CONTAINER index.md
# (design-plans/DP-*/index.md, no tasks/ segment) is out of its globs.
idx_neg_skill_target="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-996-fixture-index-non-owning/index.md"
mkdir -p "$(dirname "$idx_neg_skill_target")"
set +e
"$WRITER" \
  --producer-token breakdown:initial-create \
  --path "$idx_neg_skill_target" \
  --body-file "$idx_body" >"$WORKDIR/idx-neg-skill.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (idx-neg-skill): non-owning token must be BLOCKED on container index.md path; expected exit 2, got $rc" >&2
  cat "$WORKDIR/idx-neg-skill.out" >&2
  exit 1
fi
grep -q 'not covered by producer' "$WORKDIR/idx-neg-skill.out"
if [[ -f "$idx_neg_skill_target" ]]; then
  echo "FAIL (idx-neg-skill): non-owning token should not have created the index.md" >&2
  exit 1
fi

# AC-NEG2 (content validator failure): correct token + owning glob but invalid
# index.md body (missing description + duplicate H1) → content validator fails,
# writer rolls back; no surviving write.
idx_invalid_body="$WORKDIR/invalid-index.md"
cat >"$idx_invalid_body" <<'EOF'
---
title: "Bad Fixture"
status: LOCKED
---

# Bad Fixture
# Duplicate H1
EOF
idx_invalid_target="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/DP-995-fixture-invalid-index/index.md"
mkdir -p "$(dirname "$idx_invalid_target")"
set +e
"$WRITER" \
  --producer-token refinement:primary-doc \
  --path "$idx_invalid_target" \
  --body-file "$idx_invalid_body" >"$WORKDIR/idx-neg-content.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (idx-neg-content): invalid index.md body must fail content validator; expected exit 2, got $rc" >&2
  cat "$WORKDIR/idx-neg-content.out" >&2
  exit 1
fi
if [[ -f "$idx_invalid_target" ]]; then
  echo "FAIL (idx-neg-content): writer should have rolled back the invalid index.md write" >&2
  exit 1
fi

echo "PASS"
