#!/usr/bin/env bash
# write-producer-owned-artifact.sh — DP-226 T2 deterministic writer entrypoint.
#
# Single canonical writer for producer-owned artifacts (auto-pass ledger /
# resume JSON, breakdown initial-create task.md). Replaces the previous
# Bash heredoc workaround used by /auto-pass and breakdown skills during the
# DP-225 dogfood period.
#
# Behaviour:
#   1. Resolves the producer entry by --producer-token (token-first lookup,
#      uniqueness invariant enforced).
#   2. Verifies --path is covered by that producer's path_globs[].
#   3. Materialises the new content via temp file + atomic rename. For
#      artifacts whose validator must see the final path (task.md, resume
#      JSON), the writer backs up any existing content, performs the rename,
#      runs the validator, and rolls back on validator failure.
#   4. Resume artifact writes require --ledger-path AND --source-id; missing
#      context fails closed without writing.
#   5. Auto-pass report writes dispatch validate-auto-pass-report.sh after the
#      file reaches its final path, so ledger aggregation checks see the real
#      report location.
#
# Usage:
#   scripts/write-producer-owned-artifact.sh \
#     --producer-token <token> \
#     --path <absolute_target_path> \
#     --body-file <absolute_body_path> \
#     [--source-container <abs>] \
#     [--source-id <DP-NNN>] \
#     [--ledger-path <abs>] \
#     [--task-write-at <ISO-8601>] \
#     [--validator-arg KEY=VALUE]...
#
# Exit codes:
#   0  artifact written and validated
#   2  validation failure, missing context, glob mismatch, or unknown token
#
# Producer tokens (declared in scripts/lib/evidence-producers.json):
#   - auto-pass:source         → ledger create (initial start)
#   - auto-pass:breakdown      → ledger update at breakdown stage
#   - auto-pass:engineering    → ledger update at engineering stage
#   - auto-pass:verify         → ledger update at verify-AC stage; resume/report JSON
#   - breakdown:initial-create → tasks/T*/index.md or tasks/V*/index.md create
#   - refinement:design-doc    → refinement.json / refinement.md design doc write
#   - refinement:primary-doc   → refinement-owned container index.md primary doc
#   - refinement:inbox-record  → refinement-inbox/*.md amendment-request record

set -euo pipefail

PRODUCER_TOKEN=""
TARGET_PATH=""
BODY_FILE=""
SOURCE_CONTAINER=""
SOURCE_ID=""
LEDGER_PATH=""
TASK_WRITE_AT=""
EXTRA_VALIDATOR_ARGS=()

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/write-producer-owned-artifact.sh \
    --producer-token <token> \
    --path <absolute_target_path> \
    --body-file <absolute_body_path> \
    [--source-container <abs>] \
    [--source-id <DP-NNN>] \
    [--ledger-path <abs>] \
    [--task-write-at <ISO-8601>] \
    [--validator-arg KEY=VALUE]...
USAGE
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --producer-token) PRODUCER_TOKEN="${2:-}"; shift 2 ;;
    --path)           TARGET_PATH="${2:-}"; shift 2 ;;
    --body-file)      BODY_FILE="${2:-}"; shift 2 ;;
    --source-container) SOURCE_CONTAINER="${2:-}"; shift 2 ;;
    --source-id)      SOURCE_ID="${2:-}"; shift 2 ;;
    --ledger-path)    LEDGER_PATH="${2:-}"; shift 2 ;;
    --task-write-at)  TASK_WRITE_AT="${2:-}"; shift 2 ;;
    --validator-arg)  EXTRA_VALIDATOR_ARGS+=("${2:-}"); shift 2 ;;
    --help|-h)        usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

if [[ -z "$PRODUCER_TOKEN" || -z "$TARGET_PATH" || -z "$BODY_FILE" ]]; then
  echo "ERROR: --producer-token, --path, --body-file are required" >&2
  exit 2
fi
if [[ ! -f "$BODY_FILE" ]]; then
  echo "ERROR: --body-file does not exist: $BODY_FILE" >&2
  exit 2
fi
if [[ "$TARGET_PATH" != /* ]]; then
  echo "ERROR: --path must be absolute: $TARGET_PATH" >&2
  exit 2
fi

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCERS_JSON="$WORKSPACE_ROOT/scripts/lib/evidence-producers.json"
if [[ ! -f "$PRODUCERS_JSON" ]]; then
  echo "ERROR: producer table missing: $PRODUCERS_JSON" >&2
  exit 2
fi

# Resolve producer entry by token (token-first lookup with uniqueness check).
RESOLVED=$(POLARIS_TOKEN="$PRODUCER_TOKEN" TARGET_PATH_VAL="$TARGET_PATH" \
  PRODUCERS_JSON_VAL="$PRODUCERS_JSON" python3 - <<'PY' 2>/dev/null || true
import fnmatch
import json
import os
import sys

token = os.environ.get("POLARIS_TOKEN", "")
target = os.environ.get("TARGET_PATH_VAL", "")
producers_json = os.environ.get("PRODUCERS_JSON_VAL", "")

try:
    data = json.load(open(producers_json))
except Exception:
    print("STATUS=NO_TABLE")
    sys.exit(0)

producers = data.get("producers", []) or []
matching = [p for p in producers if token in (p.get("producer_tokens") or [])]
if len(matching) > 1:
    print("STATUS=TOKEN_NOT_UNIQUE")
    sys.exit(0)
if len(matching) == 0:
    print("STATUS=TOKEN_UNKNOWN")
    sys.exit(0)

entry = matching[0]
globs = entry.get("path_globs", []) or []
marker_kinds = ",".join(entry.get("marker_kinds", []) or [])
owning_skill = entry.get("owning_skill", "")

def match_any(path, globs):
    for g in globs:
        if fnmatch.fnmatch(path, g):
            return True
        parts = path.split("/")
        for i in range(len(parts)):
            tail = "/".join(parts[i:])
            if fnmatch.fnmatch(tail, g):
                return True
        g_alt = g.replace("**/", "*/").replace("/**", "/*")
        if fnmatch.fnmatch(path, g_alt):
            return True
    return False

if not match_any(target, globs):
    print("STATUS=PATH_OUT_OF_GLOBS")
    sys.exit(0)

print("STATUS=OK")
print(f"OWNING_SKILL={owning_skill}")
print(f"MARKER_KINDS={marker_kinds}")
PY
)

STATUS=$(printf '%s\n' "$RESOLVED" | sed -n 's/^STATUS=//p')
OWNING_SKILL=$(printf '%s\n' "$RESOLVED" | sed -n 's/^OWNING_SKILL=//p')
MARKER_KINDS=$(printf '%s\n' "$RESOLVED" | sed -n 's/^MARKER_KINDS=//p')

case "$STATUS" in
  OK) ;;
  TOKEN_NOT_UNIQUE)
    echo "ERROR: producer token '$PRODUCER_TOKEN' appears in multiple producer entries (token uniqueness violated)" >&2
    exit 2
    ;;
  TOKEN_UNKNOWN)
    echo "ERROR: producer token '$PRODUCER_TOKEN' is not registered in scripts/lib/evidence-producers.json producer_tokens[]" >&2
    exit 2
    ;;
  PATH_OUT_OF_GLOBS)
    echo "ERROR: target path '$TARGET_PATH' is not covered by producer '$PRODUCER_TOKEN' path_globs[]" >&2
    exit 2
    ;;
  *)
    echo "ERROR: producer resolution failed (status=$STATUS)" >&2
    exit 2
    ;;
esac

# Determine artifact kind from marker_kinds to drive validator dispatch.
artifact_kind=""
case "$MARKER_KINDS" in
  *verify_evidence_layout*|*verify_ac_dp110_evidence*)
    # DP-230 T12 / D31: verify-AC evidence layout writes (verify-report.md,
    # links.json, publication-manifest.json under verification/V*/).
    artifact_kind="verify_evidence_layout"
    ;;
  *auto_pass_ledger*|*auto_pass_resume*|*auto_pass_report*)
    if [[ "$TARGET_PATH" == *-resume.json ]]; then
      artifact_kind="auto_pass_resume"
    elif [[ "$TARGET_PATH" == *-report.json ]]; then
      artifact_kind="auto_pass_report"
    else
      artifact_kind="auto_pass_ledger"
    fi
    ;;
  *task_md_initial_create*)
    artifact_kind="task_md_initial_create"
    ;;
  *refinement_md_artifact*)
    # DP-274 D9: refinement design documents (refinement.json / refinement.md)
    # under a DP or Epic container are written through the refinement-owned
    # sanctioned writer branch; the content validator is selected by file kind.
    artifact_kind="refinement_design_doc"
    ;;
  *dp_index_status*|*epic_index_status*)
    # DP-274 D9: refinement-owned container index.md primary doc. Written through
    # the refinement-owned sanctioned writer branch (token refinement:primary-doc),
    # bound to the container index.md owning globs + primary-doc content validator.
    artifact_kind="refinement_primary_doc"
    ;;
  *refinement_inbox_record*)
    # DP-294 T5 / AC6: refinement-inbox amendment-request record (token
    # refinement:inbox-record). Same-shape producer write: token-first lookup +
    # glob check + atomic rename, with the canonical inbox-record content gate
    # (validate-refinement-inbox-record.sh) dispatched against the final path.
    artifact_kind="refinement_inbox_record"
    ;;
  *)
    artifact_kind="generic"
    ;;
esac

# Resume artifacts require ledger context (DP-226 R6 mitigation).
if [[ "$artifact_kind" == "auto_pass_resume" ]]; then
  if [[ -z "$LEDGER_PATH" || -z "$SOURCE_ID" ]]; then
    echo "ERROR: resume artifact write requires --ledger-path AND --source-id (DP-226 fail-closed)" >&2
    exit 2
  fi
  if [[ ! -f "$LEDGER_PATH" ]]; then
    echo "ERROR: --ledger-path file does not exist: $LEDGER_PATH" >&2
    exit 2
  fi
fi

# Ensure parent directory exists.
target_dir="$(dirname "$TARGET_PATH")"
mkdir -p "$target_dir"

# DP-368 T1: LOCK-readiness pre-write gate (refinement_primary_doc branch only).
#
# A refinement-owned container index.md status transition into LOCKED is the
# moment the source is declared handoff-ready. Bind that transition to the same
# readiness gates breakdown / auto-pass already trust: refinement-handoff-gate.sh
# (changed_files + artifact parity + schema) AND validate-refinement-lock-preflight.sh
# (every planned task is breakdown-ready). Either failing fails the LOCK closed.
#
# The gate fires ONLY on a non-LOCKED -> LOCKED transition (on-disk current status
# is absent or != LOCKED, body-file target status == LOCKED). A LOCKED -> LOCKED
# amendment is NOT a transition and must NOT re-fire the gate. A DISCUSSION (or
# any non-LOCKED) target is not a transition either, so ledger / task.md / report /
# DISCUSSION-index.md writes are never affected. dp (design-plans/) and jira-Epic
# (companies/{company}/{EPIC}/) containers are symmetric: the container is resolved
# purely by dirname(TARGET_PATH), with no source-type prefix hardcoding.
#
# The gate is placed BEFORE the final-path write to avoid any half-written LOCKED
# (pre-write gate; no rollback hole — fail closed means nothing is written). The
# gate uses its own exit; no POLARIS_*_BYPASS / POLARIS_SKILL_BOUNDARY_BYPASS env
# can silence it (aligned with the no-direct-evidence-write AC-NEG design).
#
# Reuse the canonical frontmatter status reader (same awk shape as
# archive-spec.sh / detect-closeout-drift.sh frontmatter_status); do NOT add a
# second parser.
frontmatter_status() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk -F ':' '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && /^status:/ {
      sub(/^[[:space:]]+/, "", $2)
      print $2
      exit
    }
  ' "$file"
}

if [[ "$artifact_kind" == "refinement_primary_doc" ]]; then
  current_status="$(frontmatter_status "$TARGET_PATH")"
  target_status="$(frontmatter_status "$BODY_FILE")"
  if [[ "$current_status" != "LOCKED" && "$target_status" == "LOCKED" ]]; then
    lock_container="$(dirname "$TARGET_PATH")"
    refinement_json="$lock_container/refinement.json"
    handoff_gate="$WORKSPACE_ROOT/scripts/refinement-handoff-gate.sh"
    lock_preflight="$WORKSPACE_ROOT/scripts/validate-refinement-lock-preflight.sh"
    readiness_exit=0
    if [[ -x "$handoff_gate" ]]; then
      "$handoff_gate" "$refinement_json" >&2 || readiness_exit=$?
    else
      echo "ERROR: missing LOCK-readiness gate: $handoff_gate" >&2
      readiness_exit=2
    fi
    if [[ "$readiness_exit" -eq 0 && -x "$lock_preflight" ]]; then
      "$lock_preflight" "$refinement_json" >&2 || readiness_exit=$?
    elif [[ "$readiness_exit" -eq 0 ]]; then
      echo "ERROR: missing LOCK-readiness gate: $lock_preflight" >&2
      readiness_exit=2
    fi
    if [[ "$readiness_exit" -ne 0 ]]; then
      echo "POLARIS_LOCK_READINESS_NOT_MET: $lock_container (handoff-gate / lock-preflight failed; status NOT flipped to LOCKED)" >&2
      exit 2
    fi
  fi
fi

# Backup existing content if final-path validation is required.
backup_file=""
needs_final_path_validation=0
case "$artifact_kind" in
  task_md_initial_create|auto_pass_resume|auto_pass_ledger|auto_pass_report|verify_evidence_layout|refinement_design_doc|refinement_primary_doc|refinement_inbox_record)
    needs_final_path_validation=1
    ;;
esac

if [[ "$needs_final_path_validation" -eq 1 && -f "$TARGET_PATH" ]]; then
  backup_file="$(mktemp -t producer-writer-backup.XXXXXX)"
  cp "$TARGET_PATH" "$backup_file"
fi

# Atomic write: write to a temp file in the same directory, then rename.
tmp_target="$(mktemp -p "$target_dir" .producer-writer-XXXXXX.tmp)"
trap 'rm -f "$tmp_target"' EXIT
cp "$BODY_FILE" "$tmp_target"

# Promote to final path.
mv -f "$tmp_target" "$TARGET_PATH"
trap - EXIT

rollback() {
  if [[ -n "$backup_file" && -f "$backup_file" ]]; then
    mv -f "$backup_file" "$TARGET_PATH"
  else
    rm -f "$TARGET_PATH"
  fi
}

# Validator dispatch.
validator_exit=0
case "$artifact_kind" in
  auto_pass_ledger)
    validator_cmd=("$WORKSPACE_ROOT/scripts/validate-auto-pass-ledger.sh" "$TARGET_PATH")
    if [[ -n "$SOURCE_CONTAINER" ]]; then
      validator_cmd+=(--source-container "$SOURCE_CONTAINER")
    fi
    if [[ -n "$SOURCE_ID" ]]; then
      validator_cmd+=(--source-id "$SOURCE_ID")
    fi
    if [[ -n "$TASK_WRITE_AT" ]]; then
      validator_cmd+=(--task-write-at "$TASK_WRITE_AT")
    fi
    if [[ -x "${validator_cmd[0]}" ]]; then
      "${validator_cmd[@]}" >&2 || validator_exit=$?
    fi
    ;;
  auto_pass_resume)
    validator_cmd=("$WORKSPACE_ROOT/scripts/validate-auto-pass-resume.sh"
                   --ledger "$LEDGER_PATH"
                   --resume-artifact "$TARGET_PATH"
                   --source-id "$SOURCE_ID")
    if [[ -x "${validator_cmd[0]}" ]]; then
      "${validator_cmd[@]}" >&2 || validator_exit=$?
    fi
    ;;
  auto_pass_report)
    validator_cmd=("$WORKSPACE_ROOT/scripts/validate-auto-pass-report.sh" "$TARGET_PATH")
    if [[ -x "${validator_cmd[0]}" ]]; then
      "${validator_cmd[@]}" >&2 || validator_exit=$?
    fi
    ;;
  task_md_initial_create)
    validator_cmd=("$WORKSPACE_ROOT/scripts/validate-task-md.sh" "$TARGET_PATH")
    if [[ -x "${validator_cmd[0]}" ]]; then
      "${validator_cmd[@]}" >&2 || validator_exit=$?
    fi
    ;;
  verify_evidence_layout)
    # DP-230 T12 / D31: only validate when all three layout artifacts are
    # present in the parent V*/ dir. Single-file writes during incremental
    # assembly should not fail the layout validator; the validator runs
    # once the bundle is complete.
    layout_dir="$(dirname "$TARGET_PATH")"
    validator_cmd=("$WORKSPACE_ROOT/scripts/validate-verify-evidence-layout.sh" "$layout_dir")
    if [[ -x "${validator_cmd[0]}" \
       && -f "$layout_dir/verify-report.md" \
       && -f "$layout_dir/links.json" \
       && -f "$layout_dir/publication-manifest.json" ]]; then
      "${validator_cmd[@]}" >&2 || validator_exit=$?
    fi
    ;;
  refinement_design_doc)
    # DP-274 D9: refinement design-doc content validator dispatch by file kind.
    #   refinement.json → schema validator (validate-refinement-json.sh).
    #   refinement.md   → generated derived view; render-refinement-md.sh --check
    #     asserts the .md matches the sibling refinement.json render. Only run the
    #     render check when the sibling json exists (a standalone .md write has no
    #     authoritative source to compare against; the json write is the canonical
    #     content gate).
    if [[ "$TARGET_PATH" == *refinement.json ]]; then
      validator_cmd=("$WORKSPACE_ROOT/scripts/validate-refinement-json.sh" "$TARGET_PATH")
      if [[ -x "${validator_cmd[0]}" ]]; then
        "${validator_cmd[@]}" >&2 || validator_exit=$?
      fi
    elif [[ "$TARGET_PATH" == *refinement.md ]]; then
      sibling_json="$(dirname "$TARGET_PATH")/refinement.json"
      validator_cmd=("$WORKSPACE_ROOT/scripts/render-refinement-md.sh" "$sibling_json" --check)
      if [[ -x "${validator_cmd[0]}" && -f "$sibling_json" ]]; then
        "${validator_cmd[@]}" >&2 || validator_exit=$?
      fi
    fi
    ;;
  refinement_primary_doc)
    # DP-274 D9: refinement-owned container index.md content gates.
    #   - All paths run the universal primary-doc content gates (Starlight
    #     authoring shape + workspace language policy); these are source-type
    #     agnostic and hermetic.
    #   - DP-backed container index.md additionally runs the full primary-doc
    #     authoring wrapper (validate-spec-primary-doc-authoring.sh), which layers
    #     DP metadata / sidebar / route-safe / DP-number guards. The wrapper only
    #     accepts design-plans/ (and epics/) primary-doc paths, so Epic-backed
    #     companies/{company}/{EPIC}/index.md writes rely on the universal gates
    #     above — this preserves source parity for the producer glob without the
    #     wrapper wrongly rejecting a legitimate Epic-backed parity write.
    starlight_validator="$WORKSPACE_ROOT/scripts/validate-starlight-authoring.sh"
    if [[ -x "$starlight_validator" ]]; then
      "$starlight_validator" check "$TARGET_PATH" >&2 || validator_exit=$?
    fi
    if [[ "$validator_exit" -eq 0 ]]; then
      language_validator="$WORKSPACE_ROOT/scripts/validate-language-policy.sh"
      if [[ -x "$language_validator" ]]; then
        "$language_validator" --blocking --mode artifact "$TARGET_PATH" >&2 || validator_exit=$?
      fi
    fi
    if [[ "$validator_exit" -eq 0 && "$TARGET_PATH" == */design-plans/* ]]; then
      primary_doc_validator="$WORKSPACE_ROOT/scripts/validate-spec-primary-doc-authoring.sh"
      if [[ -x "$primary_doc_validator" ]]; then
        "$primary_doc_validator" "$TARGET_PATH" >&2 || validator_exit=$?
      fi
    fi
    ;;
  refinement_inbox_record)
    # DP-294 T5 / AC6: canonical inbox-record content gate. Reuse the existing
    # validate-refinement-inbox-record.sh (breakdown scope-escalation schema);
    # no second validator. Inbox records are sidecars, not Starlight pages, so
    # only this schema gate applies.
    validator_cmd=("$WORKSPACE_ROOT/scripts/validate-refinement-inbox-record.sh" "$TARGET_PATH")
    if [[ -x "${validator_cmd[0]}" ]]; then
      "${validator_cmd[@]}" >&2 || validator_exit=$?
    fi
    ;;
esac

if [[ "$validator_exit" -ne 0 ]]; then
  echo "ERROR: post-write validator failed (artifact_kind=$artifact_kind, exit=$validator_exit); rolling back" >&2
  rollback
  [[ -n "$backup_file" && -f "$backup_file" ]] && rm -f "$backup_file"
  exit 2
fi

# Validator passed (or no validator dispatched); discard backup.
if [[ -n "$backup_file" && -f "$backup_file" ]]; then
  rm -f "$backup_file"
fi

# DP-294 T2 / AC2: amendment-time ledger refinement_hash re-anchor.
#
# When an amendment mutates a source's refinement design doc (refinement.json)
# AND the caller supplies the in-flight auto-pass --ledger-path, this writer —
# as the SINGLE canonical writer path — re-anchors that ledger's
# source.refinement_hash to the new canonical hash in the SAME action. The
# auto-pass runner / source gate stays a strict reader (no stale-but-ok branch):
# correctness is restored at write time, not synthesized at read time. The new
# hash is computed by reusing validate-auto-pass-ledger.sh --print-refinement-hash
# (canonical refinement_hash), never a second hash implementation here.
if [[ "$artifact_kind" == "refinement_design_doc" \
   && "$TARGET_PATH" == *refinement.json \
   && -n "$LEDGER_PATH" ]]; then
  if [[ ! -f "$LEDGER_PATH" ]]; then
    echo "ERROR: --ledger-path provided for amendment re-anchor but file missing: $LEDGER_PATH" >&2
    exit 2
  fi
  reanchor_container="$(dirname "$TARGET_PATH")"
  reanchor_cmd=("$WORKSPACE_ROOT/scripts/validate-auto-pass-ledger.sh" "$LEDGER_PATH"
                --source-container "$reanchor_container" --print-refinement-hash)
  if [[ -n "$SOURCE_ID" ]]; then
    reanchor_cmd+=(--source-id "$SOURCE_ID")
  fi
  # --print-refinement-hash prints the canonical hash to stdout even when the
  # ledger is currently stale (the print happens before the stale-check append).
  # Capture only the sha256: line; the validator's own exit status is expected to
  # be non-zero here (stale), so don't let pipefail abort.
  new_hash="$("${reanchor_cmd[@]}" 2>/dev/null | grep -E '^sha256:' | head -n1 || true)"
  if [[ -z "$new_hash" ]]; then
    echo "ERROR: failed to compute canonical refinement_hash for ledger re-anchor (ledger=$LEDGER_PATH container=$reanchor_container)" >&2
    exit 2
  fi
  POLARIS_NEW_HASH="$new_hash" python3 - "$LEDGER_PATH" <<'PY'
import json
import os
import sys
from pathlib import Path

ledger = Path(sys.argv[1])
new_hash = os.environ["POLARIS_NEW_HASH"]
data = json.loads(ledger.read_text(encoding="utf-8"))
src = data.get("source")
if not isinstance(src, dict):
    print("ERROR: ledger has no source object to re-anchor", file=sys.stderr)
    sys.exit(2)
src["refinement_hash"] = new_hash
tmp = ledger.with_suffix(ledger.suffix + ".reanchor.tmp")
tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
tmp.replace(ledger)
PY
  echo "[write-producer-owned-artifact] re-anchored ledger refinement_hash: $LEDGER_PATH -> $new_hash" >&2
fi

echo "[write-producer-owned-artifact] producer=$PRODUCER_TOKEN owning_skill=$OWNING_SKILL artifact_kind=$artifact_kind path=$TARGET_PATH" >&2
exit 0
