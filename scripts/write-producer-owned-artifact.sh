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

# Backup existing content if final-path validation is required.
backup_file=""
needs_final_path_validation=0
case "$artifact_kind" in
  task_md_initial_create|auto_pass_resume|auto_pass_ledger|auto_pass_report|verify_evidence_layout)
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

echo "[write-producer-owned-artifact] producer=$PRODUCER_TOKEN owning_skill=$OWNING_SKILL artifact_kind=$artifact_kind path=$TARGET_PATH" >&2
exit 0
