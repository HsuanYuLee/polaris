#!/usr/bin/env bash
set -euo pipefail

# finalize-engineering-delivery.sh — Developer-lane completion closer.
#
# This helper binds the pre-report completion gate to task lifecycle closeout
# and implementation worktree cleanup so agents do not report completion while
# forgetting the move-first pr-release closeout.
#
# Usage:
#   bash scripts/finalize-engineering-delivery.sh --repo <repo> --ticket <KEY> [--workspace <path>] [--status IMPLEMENTED]
#
# Exit: 0 = completion gate passed, task lifecycle finalized, cleanup attempted
#       1 = invalid input / lifecycle verification failed
#       2 = completion gate or mark-spec helper blocked

PREFIX="[polaris finalize-delivery]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT=""
TICKET=""
STATUS="IMPLEMENTED"

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/finalize-engineering-delivery.sh --repo <repo> --ticket <KEY> [--workspace <path>] [--status IMPLEMENTED]

Options:
  --repo <path>       Product repo root whose delivery gates should be checked.
  --ticket <KEY>      Task ticket key or DP pseudo-task id.
  --workspace <path>  Polaris workspace root. Defaults to this script's parent.
  --status <status>   Lifecycle status to write. Defaults to IMPLEMENTED.
USAGE
}

extract_frontmatter_scalar() {
  local file="$1"
  local key="$2"

  python3 - "$file" "$key" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
try:
    text = path.read_text(encoding="utf-8")
except OSError:
    sys.exit(0)

if not text.startswith("---\n"):
    sys.exit(0)

end = text.find("\n---\n", 4)
if end == -1:
    sys.exit(0)

for line in text[4:end].splitlines():
    if line.startswith(key + ":"):
        print(line.split(":", 1)[1].strip())
        sys.exit(0)
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_ROOT="${2:-}"
      shift 2
      ;;
    --ticket)
      TICKET="${2:-}"
      shift 2
      ;;
    --workspace)
      WORKSPACE_ROOT="${2:-}"
      shift 2
      ;;
    --status)
      STATUS="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "$PREFIX unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$REPO_ROOT" || -z "$TICKET" ]]; then
  echo "$PREFIX --repo and --ticket are required" >&2
  usage
  exit 1
fi

if [[ ! -d "$REPO_ROOT" ]]; then
  echo "$PREFIX repo not found: $REPO_ROOT" >&2
  exit 1
fi

if [[ ! -d "$WORKSPACE_ROOT" ]]; then
  echo "$PREFIX workspace not found: $WORKSPACE_ROOT" >&2
  exit 1
fi

case "$STATUS" in
  IMPLEMENTED|ABANDONED|LOCKED|DISCUSSION) ;;
  *)
    echo "$PREFIX invalid --status: $STATUS" >&2
    exit 1
    ;;
esac

REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
WORKSPACE_ROOT="$(cd "$WORKSPACE_ROOT" && pwd)"
WORKSPACE_SCRIPT_DIR="${WORKSPACE_ROOT}/scripts"
PARENT_CLOSEOUT_SCRIPT="${WORKSPACE_SCRIPT_DIR}/close-parent-spec-if-complete.sh"
CHECK_RELEASE_ELIGIBLE="${SCRIPT_DIR}/check-release-eligible.sh"
CHECK_RELEASE_COMPLETED="${WORKSPACE_SCRIPT_DIR}/check-release-completed.sh"
if [[ ! -x "$PARENT_CLOSEOUT_SCRIPT" ]]; then
  PARENT_CLOSEOUT_SCRIPT="${SCRIPT_DIR}/close-parent-spec-if-complete.sh"
fi
if [[ ! -x "$PARENT_CLOSEOUT_SCRIPT" ]]; then
  echo "$PREFIX close-parent helper not found for workspace or script dir" >&2
  exit 1
fi
if [[ ! -x "$CHECK_RELEASE_ELIGIBLE" ]]; then
  CHECK_RELEASE_ELIGIBLE="${WORKSPACE_SCRIPT_DIR}/check-release-eligible.sh"
fi
if [[ ! -x "$CHECK_RELEASE_COMPLETED" ]]; then
  CHECK_RELEASE_COMPLETED="${SCRIPT_DIR}/check-release-completed.sh"
fi

task_verify_report_path() {
  local task_md_path="$1"
  python3 - "$task_md_path" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
if path.name == "index.md":
    print(path.parent / "verify-report.md")
else:
    print(path.with_suffix("") / "verify-report.md")
PY
}

resolve_current_task_md_path() {
  local path="$1"
  if [[ -f "$path" ]]; then
    printf '%s\n' "$path"
    return 0
  fi

  python3 - "$path" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
parts = list(path.parts)
try:
    idx = parts.index("design-plans")
except ValueError:
    print(path)
    raise SystemExit(0)

if idx + 1 < len(parts) and parts[idx + 1] != "archive":
    archived = Path(*parts[:idx + 1], "archive", *parts[idx + 1:])
    print(archived)
else:
    print(path)
PY
}

resolve_stable_repo_root() {
  local repo="$1"
  local current wt=""

  current="$(cd "$repo" && pwd)"
  while IFS= read -r wt; do
    [[ -n "$wt" ]] || continue
    wt="$(cd "$wt" 2>/dev/null && pwd || true)"
    [[ -n "$wt" && "$wt" != "$current" && -d "$wt" ]] || continue
    printf '%s\n' "$wt"
    return 0
  done < <(git -C "$repo" worktree list --porcelain 2>/dev/null | awk '/^worktree / { print substr($0, 10) }')

  printf '%s\n' "$current"
}

ensure_task_verify_report() {
  local task_md_path=""
  local deliverable_head_sha=""
  local report_path=""

  task_md_path="$(bash "${SCRIPT_DIR}/resolve-task-md.sh" --scan-root "$WORKSPACE_ROOT" "$TICKET" 2>/dev/null || true)"
  if [[ -z "$task_md_path" || ! -f "$task_md_path" ]]; then
    return 0
  fi

  deliverable_head_sha="$(bash "${SCRIPT_DIR}/parse-task-md.sh" "$task_md_path" --no-resolve --field deliverable_head_sha 2>/dev/null || true)"
  if [[ -z "$deliverable_head_sha" ]]; then
    return 0
  fi

  report_path="$(task_verify_report_path "$task_md_path")"
  if [[ -f "$report_path" ]]; then
    return 0
  fi

  echo "$PREFIX generating missing task verify report for ${TICKET}@${deliverable_head_sha}" >&2
  bash "${SCRIPT_DIR}/write-task-verify-report.sh" \
    --repo "$REPO_ROOT" \
    --ticket "$TICKET" \
    --task-md "$task_md_path" \
    --head-sha "$deliverable_head_sha" \
    --status PASS >/dev/null
}

# Description: DP-360 T7 — record the T-task delivery PASS into the canonical
#   task.md `deliverable.verification` block, replacing the retired head-sha-keyed
#   completion_gate marker (D2 — no marker dual-write). This is the single writer
#   of the T-task delivery verification status: it runs only after
#   check-delivery-completion.sh has already passed, so the recorded status is PASS.
#   The deliverable block (pr_url / pr_state / head_sha) already exists in task.md
#   at this point; this only adds/updates the nested `verification:` sub-block.
#   Idempotent — re-running finalize with the block already PASS is a byte-identical
#   no-op. Reads the delivery head from task.md (artifact field, never a branch ref;
#   AC-NEG1).
# Args:        none (reads $TICKET, $WORKSPACE_ROOT, $SCRIPT_DIR globals)
# Side effects: rewrites the resolved task.md deliverable.verification sub-block.
write_deliverable_verification() {
  local task_md_path=""
  local work_item_id=""
  local head_sha=""

  task_md_path="$(bash "${SCRIPT_DIR}/resolve-task-md.sh" --scan-root "$WORKSPACE_ROOT" "$TICKET" 2>/dev/null || true)"
  if [[ -z "$task_md_path" || ! -f "$task_md_path" ]]; then
    return 0
  fi

  work_item_id="$(bash "${SCRIPT_DIR}/parse-task-md.sh" "$task_md_path" --no-resolve --field work_item_id 2>/dev/null || true)"
  head_sha="$(bash "${SCRIPT_DIR}/parse-task-md.sh" "$task_md_path" --no-resolve --field deliverable_head_sha 2>/dev/null || true)"

  # Missing authority inputs => fail closed: do not synthesize a delivery record
  # from partial data (canonical-contract-governance.md § Fail closed on missing
  # inputs). A T-task without a delivered head has no delivery block to stamp.
  if [[ -z "$work_item_id" || -z "$head_sha" ]]; then
    echo "$PREFIX skipping deliverable.verification stamp: missing work_item_id/deliverable_head_sha for ${TICKET}" >&2
    return 0
  fi

  TASK_MD_TARGET="$task_md_path" python3 - <<'PY' >&2 || return 1
import os
import sys
from pathlib import Path

task_md = Path(os.environ["TASK_MD_TARGET"])
text = task_md.read_text(encoding="utf-8")
if not text.startswith("---\n"):
    sys.stderr.write(f"[polaris finalize-delivery] task.md missing frontmatter: {task_md}\n")
    raise SystemExit(1)
end = text.find("\n---\n", 4)
if end == -1:
    sys.stderr.write(f"[polaris finalize-delivery] task.md frontmatter unterminated: {task_md}\n")
    raise SystemExit(1)

# text[:end] is the frontmatter (opening `---` + content, no trailing newline);
# text[end:] is "\n---\n" + the markdown body. Splitting here keeps the closing
# fence intact in `body` so the rebuilt file stays a well-formed frontmatter doc.
fm_lines = text[:end].splitlines()
body = text[end:]

# Locate the `deliverable:` block — it must already exist (pr_url/pr_state/head_sha
# were written by the engineering delivery step). The verification sub-block is a
# child under `deliverable:`; we replace any existing one and append a fresh PASS.
out = []
i = 0
n = len(fm_lines)
stamped = False
while i < n:
    line = fm_lines[i]
    if line.rstrip() == "deliverable:":
        out.append(line)
        i += 1
        # Walk the deliverable children (2-space indent), dropping any existing
        # `verification:` sub-block so a re-run stays idempotent.
        while i < n and (not fm_lines[i].strip() or fm_lines[i].startswith("  ")):
            child = fm_lines[i]
            if child.startswith("  ") and child.strip().startswith("verification:"):
                i += 1
                # Skip the existing verification sub-tree (deeper than 2-space).
                while i < n and (not fm_lines[i].strip() or fm_lines[i].startswith("    ")):
                    i += 1
                continue
            out.append(child)
            i += 1
        # Append the canonical PASS verification sub-block. A T-task delegates AC
        # verification to its sibling V-task (Verification Handoff), so its own
        # ac_counts are 0 — the gate that just passed is a binary delivery PASS,
        # the same semantics the retired completion_gate marker carried.
        out.append("  verification:")
        out.append("    status: PASS")
        out.append("    ac_counts:")
        out.append("      ac_total: 0")
        out.append("      ac_pass: 0")
        out.append("      ac_fail: 0")
        out.append("      ac_manual_required: 0")
        out.append("      ac_uncertain: 0")
        stamped = True
        continue
    out.append(line)
    i += 1

if not stamped:
    sys.stderr.write(
        "[polaris finalize-delivery] task.md has no `deliverable:` block to stamp; "
        "the engineering delivery step must record pr_url/pr_state/head_sha first\n"
    )
    raise SystemExit(1)

new_text = "\n".join(out) + body
if new_text == text:
    print(f"[polaris finalize-delivery] deliverable.verification already PASS; no-op: {task_md}")
else:
    task_md.write_text(new_text, encoding="utf-8")
    print(f"[polaris finalize-delivery] stamped deliverable.verification PASS: {task_md}")
PY
}

planner_baseline_snapshot_path() {
  local task_md_path="$1"
  local task_id="$2"

  if [[ -z "$task_id" ]]; then
    task_id="$(bash "${SCRIPT_DIR}/parse-task-md.sh" "$task_md_path" --no-resolve --field task_jira_key 2>/dev/null || true)"
  fi
  [[ -n "$task_id" ]] || return 1

  python3 - "$task_id" "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path

task_id, repo_root = sys.argv[1:3]
roots = [Path(repo_root)]
git_file = Path(repo_root) / ".git"
if git_file.is_file():
    text = git_file.read_text(encoding="utf-8", errors="ignore").strip()
    if text.startswith("gitdir:"):
        git_dir = (git_file.parent / text.split(":", 1)[1].strip()).resolve()
        common = git_dir.parent.parent
        if common.name == ".git":
            roots.append(common.parent)

candidates = []
seen = set()
for root in roots:
    snap_dir = root / ".polaris" / "evidence" / "baseline-snapshot"
    for path in snap_dir.glob(f"{task_id}-*.json"):
        resolved = str(path.resolve())
        if resolved not in seen:
            candidates.append(path)
            seen.add(resolved)

if not candidates:
    raise SystemExit(1)
candidates.sort(key=lambda p: (p.stat().st_mtime, str(p)))
print(candidates[-1])
PY
}

check_planner_baseline_snapshot() {
  local task_md_path=""
  local snapshot=""

  task_md_path="$(bash "${SCRIPT_DIR}/resolve-task-md.sh" --scan-root "$WORKSPACE_ROOT" "$TICKET" 2>/dev/null || true)"
  if [[ -z "$task_md_path" || ! -f "$task_md_path" ]]; then
    echo "$PREFIX unable to resolve task.md for planner-owned baseline snapshot check: ${TICKET}" >&2
    exit 2
  fi

  if ! snapshot="$(planner_baseline_snapshot_path "$task_md_path" "$TICKET" 2>/dev/null)" || [[ -z "$snapshot" ]]; then
    echo "$PREFIX BLOCKED: missing planner-owned baseline snapshot for ${TICKET}" >&2
    echo "$PREFIX Re-run engineering branch setup; do not create a post-hoc snapshot for an active task." >&2
    exit 2
  fi

  if ! bash "${SCRIPT_DIR}/validate-task-md.sh" --snapshot "$snapshot" "$task_md_path" >/dev/null; then
    echo "$PREFIX BLOCKED: planner-owned task.md fields changed after branch setup for ${TICKET}" >&2
    echo "$PREFIX Snapshot: $snapshot" >&2
    echo "$PREFIX Route through engineering scope escalation -> breakdown; do not edit task.md in place." >&2
    exit 2
  fi
  echo "$PREFIX planner-owned baseline snapshot passed: $snapshot" >&2
}

ensure_task_verify_report
check_planner_baseline_snapshot

COMPLETION_TASK_MD_PATH="$(bash "${SCRIPT_DIR}/resolve-task-md.sh" --scan-root "$WORKSPACE_ROOT" "$TICKET" 2>/dev/null || true)"
if [[ -z "$COMPLETION_TASK_MD_PATH" || ! -f "$COMPLETION_TASK_MD_PATH" ]]; then
  echo "$PREFIX unable to resolve task.md for completion gate: ${TICKET}" >&2
  exit 2
fi

echo "$PREFIX running completion gate for ${TICKET} ..." >&2
if ! POLARIS_COMPLETION_TASK_MD="$COMPLETION_TASK_MD_PATH" bash "${SCRIPT_DIR}/check-delivery-completion.sh" --repo "$REPO_ROOT" --ticket "$TICKET"; then
  echo "$PREFIX completion gate blocked; task lifecycle was not changed" >&2
  exit 2
fi

TASK_MD_PATH="$(bash "${SCRIPT_DIR}/resolve-task-md.sh" --scan-root "$WORKSPACE_ROOT" "$TICKET" 2>/dev/null || true)"
if [[ -z "$TASK_MD_PATH" || ! -f "$TASK_MD_PATH" ]]; then
  echo "$PREFIX unable to resolve task.md for shared release eligibility gate: ${TICKET}" >&2
  exit 1
fi

release_eligibility_env=(POLARIS_COMPLETION_TASK_MD="$TASK_MD_PATH")
release_aggregate_stub=""
if [[ -z "${POLARIS_COMPLETION_AGGREGATE_SELFTESTS_BIN:-}" ]]; then
  release_aggregate_stub="$(mktemp -t polaris-release-eligible-aggregate-covered.XXXXXX.sh)"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' '# Aggregate corpus already passed in finalize-engineering-delivery.sh.'
    printf '%s\n' 'exit 0'
  } >"$release_aggregate_stub"
  chmod +x "$release_aggregate_stub"
  release_eligibility_env+=(POLARIS_COMPLETION_AGGREGATE_SELFTESTS_BIN="$release_aggregate_stub")
fi

if ! env "${release_eligibility_env[@]}" bash "$CHECK_RELEASE_ELIGIBLE" --repo "$REPO_ROOT" --task-md "$TASK_MD_PATH"; then
  [[ -n "$release_aggregate_stub" ]] && rm -f "$release_aggregate_stub"
  echo "$PREFIX shared release eligibility gate blocked; task lifecycle was not changed" >&2
  exit 2
fi
[[ -n "$release_aggregate_stub" ]] && rm -f "$release_aggregate_stub"

# DP-360 T7: record the delivery PASS into the canonical task.md
# `deliverable.verification` block (single source of truth), replacing the retired
# head-sha-keyed completion_gate marker (D2 — no marker dual-write). Stamped only
# after both completion and release eligibility gates have passed; idempotent
# re-runs are a no-op. Keep this after release eligibility because that shared
# gate can re-run check-delivery-completion, whose planner-owned baseline check
# must see the pre-stamp task.md.
write_deliverable_verification

echo "$PREFIX marking task lifecycle: ${TICKET} -> ${STATUS}" >&2
if ! bash "${SCRIPT_DIR}/mark-spec-implemented.sh" "$TICKET" --status "$STATUS" --workspace "$WORKSPACE_ROOT"; then
  echo "$PREFIX mark-spec-implemented failed after completion gate passed" >&2
  exit 2
fi

TASK_MD_PATH="$(bash "${SCRIPT_DIR}/resolve-task-md.sh" --scan-root "$WORKSPACE_ROOT" "$TICKET" 2>/dev/null || true)"
if [[ -z "$TASK_MD_PATH" || ! -f "$TASK_MD_PATH" ]]; then
  echo "$PREFIX unable to resolve finalized task.md for ${TICKET}" >&2
  exit 1
fi

case "$TASK_MD_PATH" in
  */tasks/pr-release/*.md) ;;
  *)
    echo "$PREFIX finalized task is not under tasks/pr-release/: $TASK_MD_PATH" >&2
    exit 1
    ;;
esac

ACTUAL_STATUS="$(extract_frontmatter_scalar "$TASK_MD_PATH" "status")"
if [[ "$ACTUAL_STATUS" != "$STATUS" ]]; then
  echo "$PREFIX finalized task status mismatch: expected ${STATUS}, got ${ACTUAL_STATUS:-<empty>} in ${TASK_MD_PATH}" >&2
  exit 1
fi

RELEASE_GATE_REPO_ROOT="$(resolve_stable_repo_root "$REPO_ROOT")"

echo "$PREFIX cleaning implementation worktree for ${TICKET} ..." >&2
cd "$WORKSPACE_ROOT"
if ! bash "${SCRIPT_DIR}/engineering-clean-worktree.sh" --task-md "$TASK_MD_PATH" --repo "$REPO_ROOT"; then
  echo "$PREFIX implementation worktree cleanup failed after task lifecycle finalized" >&2
  exit 2
fi

echo "$PREFIX attempting parent spec closeout for ${TICKET} ..." >&2
if ! bash "$PARENT_CLOSEOUT_SCRIPT" --task-md "$TASK_MD_PATH" --workspace "$WORKSPACE_ROOT"; then
  echo "$PREFIX parent spec closeout failed after task lifecycle finalized" >&2
  exit 2
fi

CURRENT_TASK_MD_PATH="$(resolve_current_task_md_path "$TASK_MD_PATH")"
if ! bash "$CHECK_RELEASE_COMPLETED" --repo "$RELEASE_GATE_REPO_ROOT" --task-md "$CURRENT_TASK_MD_PATH"; then
  echo "$PREFIX shared release completed gate blocked after lifecycle closeout" >&2
  exit 2
fi

echo "$PREFIX ✅ finalized ${TICKET}: ${TASK_MD_PATH}" >&2
