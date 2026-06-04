#!/usr/bin/env bash
set -uo pipefail

# Purpose: verify-AC owning writer for ac_verification lifecycle metadata AND
#          the DP-201 ac_verification proof marker. It atomically replaces the
#          latest ac_verification block in a V*.md task file, appends one entry
#          to ac_verification_log, and — for terminal verdict statuses — emits a
#          durable .polaris/evidence/ac-verification/{work_item}-{head}.json
#          marker anchored at the main checkout (DP-281). Pattern mirrors
#          scripts/write-completion-gate-marker.sh.
# Inputs:  <v-task-md> + flags (see Usage); no env required for marker I/O.
# Outputs: updated V*.md frontmatter; for terminal status, a durable marker
#          JSON. Exit code contract below.
#
# Usage:
#   scripts/write-ac-verification.sh <v-task-md> \
#     --status <PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|BLOCKED_ENV|IN_PROGRESS> \
#     --last-run-at <iso8601> \
#     --ac-total <n> \
#     --ac-pass <n> \
#     --ac-fail <n> \
#     --ac-manual-required <n> \
#     --ac-uncertain <n> \
#     [--human-disposition <passed|rejected|deferred>] \
#     [--summary <text>] \
#     [--source-id <DP-NNN>] \
#     [--work-item-id <DP-NNN-V1>] \
#     [--head-sha <sha>]
#
# Marker (DP-281):
#   When --status is a terminal verdict (PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|
#   BLOCKED_ENV), --source-id / --work-item-id / --head-sha are REQUIRED and a
#   proof marker is emitted to
#   <main-checkout>/.polaris/evidence/ac-verification/{work_item}-{head}.json.
#   --status IN_PROGRESS only updates frontmatter and emits no marker.
#
# Exit:
#   0 success
#   1 inconsistent write after retries OR marker emit failed; caller must halt
#   2 invalid input

MAX_RETRIES=3
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_TASK_MD="${SCRIPT_DIR}/validate-task-md.sh"

# DP-281 D3: framework artifact markers anchor at the main checkout, even when
# this writer runs inside a `git worktree add` copy. Source the shared resolver
# helper instead of recomputing the rule (same pattern as
# scripts/write-completion-gate-marker.sh).
if [[ -f "$SCRIPT_DIR/lib/main-checkout.sh" ]]; then
  # shellcheck source=lib/main-checkout.sh
  . "$SCRIPT_DIR/lib/main-checkout.sh"
fi

die() {
  printf '[write-ac-verification] ERROR: %s\n' "$1" >&2
  exit 2
}

fail_inconsistent() {
  printf '\n' >&2
  printf '====================================================================\n' >&2
  printf 'HARD STOP - ac_verification write failed\n' >&2
  printf '====================================================================\n' >&2
  printf 'task.md: %s\n' "$TASK_MD" >&2
  printf 'cause  : %s\n' "$1" >&2
  printf 'V*.md is in inconsistent state - verification ran but task.md was not updated. Manual recovery required.\n' >&2
  printf '====================================================================\n' >&2
  exit 1
}

usage() {
  sed -n '3,46p' "$0" >&2
}

is_non_negative_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

TASK_MD="${1:-}"
[[ -n "$TASK_MD" ]] || { usage; exit 2; }
shift || true

STATUS=""
LAST_RUN_AT=""
AC_TOTAL=""
AC_PASS=""
AC_FAIL=""
AC_MANUAL_REQUIRED=""
AC_UNCERTAIN=""
HUMAN_DISPOSITION=""
SUMMARY=""
SOURCE_ID=""
WORK_ITEM_ID=""
HEAD_SHA=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --status) STATUS="${2:-}"; shift 2 ;;
    --last-run-at) LAST_RUN_AT="${2:-}"; shift 2 ;;
    --ac-total) AC_TOTAL="${2:-}"; shift 2 ;;
    --ac-pass) AC_PASS="${2:-}"; shift 2 ;;
    --ac-fail) AC_FAIL="${2:-}"; shift 2 ;;
    --ac-manual-required) AC_MANUAL_REQUIRED="${2:-}"; shift 2 ;;
    --ac-uncertain) AC_UNCERTAIN="${2:-}"; shift 2 ;;
    --human-disposition) HUMAN_DISPOSITION="${2:-}"; shift 2 ;;
    --summary) SUMMARY="${2:-}"; shift 2 ;;
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --work-item-id) WORK_ITEM_ID="${2:-}"; shift 2 ;;
    --head-sha) HEAD_SHA="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -f "$TASK_MD" ]] || die "task.md not found: $TASK_MD"
case "$(basename "$TASK_MD")" in
  V*.md) ;;
  index.md)
    [[ "$(basename "$(dirname "$TASK_MD")")" =~ ^V[0-9]+[a-z]*$ ]] || die "folder-native task must be V*/index.md"
    ;;
  *) die "ac_verification can only be written to V*.md or V*/index.md" ;;
esac

case "$STATUS" in
  PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|BLOCKED_ENV|IN_PROGRESS) ;;
  *) die "--status must be PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|BLOCKED_ENV|IN_PROGRESS" ;;
esac

[[ -n "$LAST_RUN_AT" ]] || die "--last-run-at is required"
printf '%s' "$LAST_RUN_AT" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?$' \
  || die "--last-run-at must be ISO 8601"

for value_name in AC_TOTAL AC_PASS AC_FAIL AC_MANUAL_REQUIRED AC_UNCERTAIN; do
  value="${!value_name}"
  [[ -n "$value" ]] || die "--$(printf '%s' "$value_name" | tr '[:upper:]_' '[:lower:]-') is required"
  is_non_negative_int "$value" || die "$value_name must be a non-negative integer"
done

if [[ $((AC_PASS + AC_FAIL + AC_MANUAL_REQUIRED + AC_UNCERTAIN)) -ne "$AC_TOTAL" ]]; then
  die "ac_pass + ac_fail + ac_manual_required + ac_uncertain must equal ac_total"
fi

if [[ "$STATUS" != "PASS" && "$STATUS" != "IN_PROGRESS" && -z "$HUMAN_DISPOSITION" ]]; then
  die "--human-disposition is required when status is $STATUS"
fi
if [[ -n "$HUMAN_DISPOSITION" ]]; then
  case "$HUMAN_DISPOSITION" in
    passed|rejected|deferred) ;;
    *) die "--human-disposition must be passed|rejected|deferred" ;;
  esac
fi

# DP-281 D4: terminal verdict statuses emit a proof marker; IN_PROGRESS does
# not. A terminal status REQUIRES --source-id / --work-item-id / --head-sha so
# the marker filename + payload can align with the auto-pass-runner probe
# (AC-NEG1: never silently skip the marker on a missing flag).
is_terminal_verdict() {
  case "$1" in
    PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|BLOCKED_ENV) return 0 ;;
    *) return 1 ;;
  esac
}

if is_terminal_verdict "$STATUS"; then
  [[ -n "$SOURCE_ID" ]] || die "--source-id is required when status is terminal ($STATUS); marker would be skipped silently"
  [[ -n "$WORK_ITEM_ID" ]] || die "--work-item-id is required when status is terminal ($STATUS); marker would be skipped silently"
  [[ -n "$HEAD_SHA" ]] || die "--head-sha is required when status is terminal ($STATUS); marker would be skipped silently"
fi

TASK_MD="$(cd "$(dirname "$TASK_MD")" && pwd)/$(basename "$TASK_MD")"
TASK_DIR="$(dirname "$TASK_MD")"

# DP-281 D3/D5/D6: emit the ac_verification proof marker for terminal verdicts.
# Anchored at the main checkout via resolve_main_checkout so worktree-internal
# calls (auto-pass) and main-checkout readers (auto-pass-runner probe) agree on
# the path. Returns non-zero on any write failure so the caller can fail-stop
# (AC-NEG2: a marker emit failure must surface as exit 1, never a false exit 0).
emit_ac_verification_marker() {
  local main_checkout="" out=""
  if declare -F resolve_main_checkout >/dev/null 2>&1; then
    # Resolve from the V*.md location so worktree context is honoured even when
    # the caller's CWD is elsewhere.
    main_checkout="$(resolve_main_checkout "$TASK_DIR" 2>/dev/null || true)"
  fi
  if [[ -n "$main_checkout" ]]; then
    out="${main_checkout}/.polaris/evidence/ac-verification/${WORK_ITEM_ID}-${HEAD_SHA}.json"
  else
    # No git context (resolver failed) — fall back to CWD-relative path so
    # callers outside a repo still get a useful marker.
    out=".polaris/evidence/ac-verification/${WORK_ITEM_ID}-${HEAD_SHA}.json"
  fi

  mkdir -p "$(dirname "$out")" || return 1

  python3 - "$SOURCE_ID" "$WORK_ITEM_ID" "$HEAD_SHA" "$STATUS" \
    "$AC_TOTAL" "$AC_PASS" "$AC_FAIL" "$AC_MANUAL_REQUIRED" "$AC_UNCERTAIN" \
    "$HUMAN_DISPOSITION" "$SUMMARY" "$LAST_RUN_AT" "$TASK_MD" "$out" <<'PY' || return 1
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

(
    source_id,
    work_item_id,
    head_sha,
    status,
    ac_total,
    ac_pass,
    ac_fail,
    ac_manual_required,
    ac_uncertain,
    human_disposition,
    summary,
    last_run_at,
    task_md,
    out,
) = sys.argv[1:15]

freshness = {"head_sha": head_sha, "last_run_at": last_run_at}
task_path = Path(task_md)
if task_path.is_file():
    freshness["task_artifact_sha256"] = hashlib.sha256(task_path.read_bytes()).hexdigest()
    freshness["source_artifact"] = task_path.as_posix()

payload = {
    "schema_version": 1,
    "marker_kind": "ac_verification",
    "writer": "verify-AC",
    "owning_skill": "verify-AC",
    "source_id": source_id,
    "work_item_id": work_item_id,
    # Compatibility aliases for legacy readers that key off `ticket` / top-level
    # `head_sha` (e.g. check-local-extension-completion.sh
    # check_ac_verification_evidence). The canonical key is work_item_id /
    # freshness.head_sha; aliases keep one marker readable by every consumer.
    "ticket": work_item_id,
    "head_sha": head_sha,
    "status": status,
    "ac_counts": {
        "ac_total": int(ac_total),
        "ac_pass": int(ac_pass),
        "ac_fail": int(ac_fail),
        "ac_manual_required": int(ac_manual_required),
        "ac_uncertain": int(ac_uncertain),
    },
    "human_disposition": human_disposition or None,
    "freshness": freshness,
    "at": datetime.now(timezone.utc).isoformat(),
    "summary": summary or None,
}
Path(out).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(out)
PY
}

attempt=0
last_error=""

while [[ "$attempt" -lt "$MAX_RETRIES" ]]; do
  attempt=$((attempt + 1))
  tmp_file="$(mktemp "${TASK_DIR}/.ac-verification.XXXXXX")" || die "failed to create temp file"

  if ! write_error=$(python3 - "$TASK_MD" "$tmp_file" "$STATUS" "$LAST_RUN_AT" "$AC_TOTAL" "$AC_PASS" "$AC_FAIL" "$AC_MANUAL_REQUIRED" "$AC_UNCERTAIN" "$HUMAN_DISPOSITION" "$SUMMARY" <<'PY' 2>&1
import sys
from pathlib import Path

(
    task_path,
    tmp_path,
    status,
    last_run_at,
    ac_total,
    ac_pass,
    ac_fail,
    ac_manual_required,
    ac_uncertain,
    human_disposition,
    summary,
) = sys.argv[1:12]

path = Path(task_path)
content = path.read_text(encoding="utf-8")

def yaml_scalar(value: str) -> str:
    if value == "":
        return ""
    if any(ch in value for ch in [":", "#", "\n", '"', "'"]) or any(ch.isspace() for ch in value) or value.strip() != value:
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return value

if content.startswith("---\n"):
    end = content.find("\n---\n", 4)
else:
    end = -1

if end == -1:
    fm_lines = []
    body = content
else:
    fm_lines = content[4:end].splitlines()
    body = content[end + len("\n---\n"):]

cleaned = []
existing_log_children = []
i = 0
while i < len(fm_lines):
    raw = fm_lines[i]
    if raw.startswith("ac_verification:"):
        i += 1
        while i < len(fm_lines) and (not fm_lines[i] or fm_lines[i][0].isspace()):
            i += 1
        continue
    if raw.startswith("ac_verification_log:"):
        inline = raw.split(":", 1)[1].strip()
        i += 1
        if inline in ("", None):
            while i < len(fm_lines) and (not fm_lines[i] or fm_lines[i][0].isspace()):
                existing_log_children.append(fm_lines[i])
                i += 1
        continue
    cleaned.append(raw)
    i += 1

while cleaned and not cleaned[-1].strip():
    cleaned.pop()

block = [
    "ac_verification:",
    f"  status: {status}",
    f"  last_run_at: {last_run_at}",
    f"  ac_total: {ac_total}",
    f"  ac_pass: {ac_pass}",
    f"  ac_fail: {ac_fail}",
    f"  ac_manual_required: {ac_manual_required}",
    f"  ac_uncertain: {ac_uncertain}",
]
if human_disposition:
    block.append(f"  human_disposition: {human_disposition}")

log_children = [line for line in existing_log_children if line.strip()]
log_children.extend([
    f"  - time: {last_run_at}",
    f"    status: {status}",
    f"    ac_total: {ac_total}",
    f"    ac_pass: {ac_pass}",
    f"    ac_fail: {ac_fail}",
    f"    ac_manual_required: {ac_manual_required}",
    f"    ac_uncertain: {ac_uncertain}",
])
if human_disposition:
    log_children.append(f"    human_disposition: {human_disposition}")
if summary:
    log_children.append(f"    summary: {yaml_scalar(summary)}")

new_fm = cleaned + block + ["ac_verification_log:"] + log_children
new_content = "---\n" + "\n".join(new_fm).rstrip() + "\n---\n" + body
Path(tmp_path).write_text(new_content, encoding="utf-8")
PY
  ); then
    last_error="python writer failed: ${write_error}"
    rm -f "$tmp_file"
  elif ! mv_error=$(mv "$tmp_file" "$TASK_MD" 2>&1); then
    last_error="atomic mv failed: ${mv_error}"
    rm -f "$tmp_file" 2>/dev/null || true
  else
    verify_result=$(python3 - "$TASK_MD" "$LAST_RUN_AT" <<'PY' 2>&1
import sys
from pathlib import Path

path, expected = sys.argv[1:3]
text = Path(path).read_text(encoding="utf-8")
if not text.startswith("---\n"):
    print("NO_FRONTMATTER")
    raise SystemExit(1)
end = text.find("\n---\n", 4)
if end == -1:
    print("NO_FRONTMATTER_END")
    raise SystemExit(1)
frontmatter = text[4:end].splitlines()
in_block = False
found = ""
for raw in frontmatter:
    if raw == "ac_verification:":
        in_block = True
        continue
    if in_block and raw and not raw[0].isspace():
        break
    if not in_block:
        continue
    stripped = raw.strip()
    if stripped.startswith("last_run_at:"):
        found = stripped.split(":", 1)[1].strip()
        break
if found != expected:
    print(f"LAST_RUN_MISMATCH:{found}")
    raise SystemExit(1)
print("OK")
PY
    ) || true
    if [[ "$verify_result" != "OK" ]]; then
      last_error="read-back verification failed: ${verify_result}"
    elif ! validate_output=$(bash "$VALIDATE_TASK_MD" "$TASK_MD" 2>&1); then
      last_error="validate-task-md failed after write: ${validate_output}"
    else
      echo "[write-ac-verification] OK: wrote ac_verification to $TASK_MD" >&2
      # DP-281 D4/D6: frontmatter is now consistent. For terminal verdicts emit
      # the durable proof marker; a marker write failure is a hard stop (exit 1)
      # so the V*.md and the marker never drift into a false-success state.
      if is_terminal_verdict "$STATUS"; then
        if ! marker_path="$(emit_ac_verification_marker)"; then
          fail_inconsistent "ac_verification marker emit failed for ${WORK_ITEM_ID}-${HEAD_SHA}"
        fi
        echo "[write-ac-verification] OK: wrote ac_verification marker to $marker_path" >&2
      fi
      exit 0
    fi
  fi

  sleep "$attempt"
done

fail_inconsistent "$last_error"
