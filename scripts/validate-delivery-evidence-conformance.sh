#!/usr/bin/env bash
# Purpose: DP-417 T15 — framework-release delivery-evidence conformance gate.
#   Framework-DP-only: source.type != dp => no-op PASS (product epics never go through /framework-release,
#   canonical-contract-governance.md § Source Parity carve-out). Two faces:
#     --mode pre-release : fail-closed. Per required task the delivered head MUST be resolvable via the
#                          DP-360 § Closeout Delivered-Head Authority order — (1) an explicit --task-head-sha
#                          override, (2) the task.md `deliverable.head_sha` delivery block — and be shape-valid
#                          (7-40 hex). pr_url/pr_state are OPTIONAL provenance: direct-commit-to-feat
#                          self-iteration delivery has a real head (supplied via the override map) but no PR;
#                          only a recorded pr_state is shape-checked (OPEN|MERGED; CLOSED = stale/superseded).
#                          Enumerates EVERY non-conformant task at once, replacing the late generic no-PR
#                          failure / closeout die. Fail-closed only if the head is resolvable via NEITHER path;
#                          never falls back to a branch ref or a completion-gate marker filename head.
#     --mode planning    : front-load. For a framework DP, print (non-failing) the delivery-evidence contract
#                          each required task must satisfy at /framework-release, so the plan is shaped
#                          conformant up front and never enters the reject-rewrite loop. Non-failing: at
#                          planning time the delivery block does not exist yet and a task's branch is
#                          derive-generated, so there is no non-redundant fail condition; enforcement lives
#                          in --mode pre-release.
#   Required deliverable task = task_shape=implementation T task, or branch-bearing V task (V + declared Task branch).
#   Reuses the DP-360 canonical reader scripts/parse-task-md.sh (deliverable.head_sha/pr_state, task_shape,
#   task_branch, work_item_id) and the same --task-head-sha map syntax as framework-release-closeout.sh;
#   does NOT implement a second delivery-block reader or a second head resolver.
# Inputs:
#   --mode planning|pre-release          (required)
#   --source-refinement-json <path>      (resolve source.type + derive tasks dir)
#   --tasks-dir <dir>                    (enumerate task.md under a tasks/ dir; planning)
#   --task-md <path> [--task-md ...]     (explicit resolved task.md list; framework-release-pr-lane pre-release)
#   --task-head-sha "WID=sha,WID=sha"    (DP-360 authority order #1 override map; pre-release)
# Outputs: exit 0 PASS/no-op; exit 2 POLARIS_DELIVERY_EVIDENCE_NON_CONFORMANT (per-task enumeration on stderr)
#          or POLARIS_DELIVERY_EVIDENCE_USAGE on bad args.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="${SCRIPT_DIR}/parse-task-md.sh"

MODE=""
REFINEMENT_JSON=""
TASKS_DIR=""
TASK_HEAD_OVERRIDES=""
declare -a TASK_MDS=()

die_usage() { echo "POLARIS_DELIVERY_EVIDENCE_USAGE: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --source-refinement-json) REFINEMENT_JSON="${2:-}"; shift 2 ;;
    --tasks-dir) TASKS_DIR="${2:-}"; shift 2 ;;
    --task-md) TASK_MDS+=("${2:-}"); shift 2 ;;
    --task-head-sha) TASK_HEAD_OVERRIDES="${2:-}"; shift 2 ;;
    --help|-h) sed -n '2,36p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die_usage "unknown arg: $1" ;;
  esac
done

# DP-360 delivered-head authority resolution order #1: explicit --task-head-sha override map,
# syntax "DP-NNN-T1=<sha1>,DP-NNN-T2=<sha2>" (same map syntax as framework-release-closeout.sh).
# Direct-commit-to-feat self-iteration delivery has a real head but no PR / delivery block; the
# override map is the sanctioned way to supply that head at release without fabricating a PR URL.
head_override_get() {
  local wid="$1" pair k v
  [[ -n "$TASK_HEAD_OVERRIDES" ]] || return 0
  local IFS=','
  for pair in $TASK_HEAD_OVERRIDES; do
    k="${pair%%=*}"
    v="${pair#*=}"
    if [[ "$k" == "$wid" && "$k" != "$pair" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  done
  return 0
}

[[ "$MODE" == "planning" || "$MODE" == "pre-release" ]] || die_usage "--mode must be planning|pre-release"
[[ -x "$PARSE_TASK_MD" || -f "$PARSE_TASK_MD" ]] || die_usage "canonical reader not found: $PARSE_TASK_MD"

# Walk up from a starting dir to the owning refinement.json (path resolution, not a delivery reader).
find_refinement_json() {
  local d="$1"
  while [[ -n "$d" && "$d" != "/" ]]; do
    [[ -f "$d/refinement.json" ]] && { printf '%s\n' "$d/refinement.json"; return 0; }
    d="$(dirname "$d")"
  done
  return 1
}

if [[ -z "$REFINEMENT_JSON" ]]; then
  if [[ -n "$TASKS_DIR" ]]; then
    REFINEMENT_JSON="$(find_refinement_json "$TASKS_DIR" || true)"
  elif [[ ${#TASK_MDS[@]} -gt 0 ]]; then
    REFINEMENT_JSON="$(find_refinement_json "$(dirname "${TASK_MDS[0]}")" || true)"
  fi
fi

# Framework-DP-only gate: product epics (source.type=jira) never run /framework-release, so no-op PASS.
source_type=""
if [[ -n "$REFINEMENT_JSON" && -f "$REFINEMENT_JSON" ]]; then
  source_type="$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get("source") or {}).get("type") or "")' "$REFINEMENT_JSON" 2>/dev/null || true)"
fi
if [[ "$source_type" != "dp" ]]; then
  echo "delivery-evidence-conformance[$MODE]: source.type='${source_type:-unknown}' != dp; framework-release-only gate no-op PASS" >&2
  exit 0
fi

# Enumerate candidate task.md when no explicit --task-md list was supplied (planning / source-level).
if [[ ${#TASK_MDS[@]} -eq 0 ]]; then
  scan_dir="$TASKS_DIR"
  if [[ -z "$scan_dir" && -n "$REFINEMENT_JSON" ]]; then
    scan_dir="$(dirname "$REFINEMENT_JSON")/tasks"
  fi
  if [[ ! -d "$scan_dir" ]]; then
    # Tasks not derived yet (e.g. a pre-breakdown LOCK preflight sees only refinement.json).
    # Nothing to check; the fail-closed enforcement runs later in --mode pre-release.
    echo "delivery-evidence-conformance[$MODE]: no tasks dir at '${scan_dir:-<none>}' (tasks not derived yet); nothing to check" >&2
    exit 0
  fi
  while IFS= read -r f; do
    [[ -n "$f" ]] && TASK_MDS+=("$f")
  done < <(
    find "$scan_dir" -maxdepth 2 \( -name 'index.md' -o -name 'T*.md' -o -name 'V*.md' \) 2>/dev/null \
      | grep -Ev '/pr-release/|/archive/' | sort -u
  )
  # Empty enumeration (framework DP dir with no candidate task.md) is benign: nothing to check.
  # Only an explicit --task-md list of zero would be misuse, and that path never enumerates.
  if [[ ${#TASK_MDS[@]} -eq 0 ]]; then
    echo "delivery-evidence-conformance[$MODE]: no candidate task.md under '$scan_dir'; nothing to check" >&2
    exit 0
  fi
fi
[[ ${#TASK_MDS[@]} -gt 0 ]] || die_usage "no task.md files to check"

# Canonical reader field helper (DP-360 parse-task-md; --no-resolve avoids the resolve-task-base subcall).
pf() { bash "$PARSE_TASK_MD" "$1" --no-resolve --field "$2" 2>/dev/null || true; }

declare -a VIOLATIONS=()
CHECKED=0
for tmd in "${TASK_MDS[@]}"; do
  if [[ ! -f "$tmd" ]]; then
    VIOLATIONS+=("$tmd: task.md not found")
    continue
  fi
  wid="$(pf "$tmd" work_item_id)"
  shape="$(pf "$tmd" task_shape)"
  branch="$(pf "$tmd" task_branch)"

  is_required=0
  # T implementation task (task_kind derived from work_item_id -T marker; audit/confirmation shapes excluded).
  if [[ "$wid" =~ -T[0-9]+ && "$shape" == "implementation" ]]; then
    is_required=1
  fi
  # Branch-bearing V task (has a Task branch => framework-release treats it as a release-stack deliverable).
  if [[ "$wid" =~ -V[0-9]+ && -n "$branch" && "$branch" != "N/A" ]]; then
    is_required=1
  fi
  [[ $is_required -eq 1 ]] || continue

  CHECKED=$((CHECKED + 1))
  label="${wid:-$tmd}"

  if [[ "$MODE" == "planning" ]]; then
    # Front-load only. At planning time the DP-360 delivery block does not exist yet by design, and a
    # task's branch is derive-generated, so there is no non-redundant fail-closed condition here — the
    # planning face surfaces the framework-release delivery-evidence contract each required task must
    # satisfy so the plan/implementation is shaped conformant up front. Fail-closed enforcement lives
    # in --mode pre-release (run at the framework-release preflight).
    branch_note="$branch"
    [[ -n "$branch" && "$branch" != "N/A" ]] || branch_note="<derived at breakdown>"
    echo "delivery-evidence-conformance[planning]: $label -> /framework-release will require a resolvable delivered head (DP-360 authority order: --task-head-sha override OR task.md deliverable.head_sha; pr_url/pr_state optional provenance, CLOSED=stale); branch=$branch_note" >&2
    continue
  fi

  # pre-release: resolve the delivered head via the DP-360 § Closeout Delivered-Head Authority order —
  #   (1) explicit --task-head-sha override, (2) task.md deliverable.head_sha delivery block.
  # Fail-closed only if BOTH are absent; never fall back to a branch ref or a completion-gate marker
  # filename head. pr_url/pr_state are OPTIONAL provenance metadata: direct-commit-to-feat self-iteration
  # delivery has a real head (supplied via the override map) but no PR / delivery block; only when a
  # delivery block records pr_state is it shape-checked (OPEN|MERGED; CLOSED = stale/superseded).
  override_head="$(head_override_get "$wid")"
  block_head="$(pf "$tmd" deliverable_head_sha)"
  if [[ -n "$override_head" ]]; then
    resolved_head="$override_head"; head_source="--task-head-sha override"
  else
    resolved_head="$block_head"; head_source="deliverable.head_sha"
  fi

  if [[ -z "$resolved_head" ]]; then
    VIOLATIONS+=("$label: no delivered head resolvable (neither --task-head-sha $wid=<sha> override nor task.md deliverable.head_sha; DP-360 authority order exhausted; no fallback to branch ref / marker filename head)")
    continue
  fi
  if [[ ! "$resolved_head" =~ ^[0-9a-f]{7,40}$ ]]; then
    VIOLATIONS+=("$label: delivered head malformed ($head_source): '$resolved_head' (expected 7-40 hex)")
  fi
  # pr_state is optional provenance; only enforce its shape when a delivery block records it.
  pr_state="$(pf "$tmd" deliverable_pr_state)"
  if [[ -n "$pr_state" ]]; then
    case "$pr_state" in
      OPEN|MERGED) : ;;
      CLOSED) VIOLATIONS+=("$label: deliverable.pr_state=CLOSED (stale/superseded delivery; re-deliver before release)") ;;
      *) VIOLATIONS+=("$label: deliverable.pr_state invalid: '$pr_state' (expected OPEN|MERGED when present)") ;;
    esac
  fi
done

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
  echo "POLARIS_DELIVERY_EVIDENCE_NON_CONFORMANT: ${#VIOLATIONS[@]} non-conformant task(s) [mode=$MODE, source=DP]" >&2
  for v in "${VIOLATIONS[@]}"; do echo "  - $v" >&2; done
  exit 2
fi

if [[ "$MODE" == "planning" ]]; then
  echo "delivery-evidence-conformance[planning]: PASS (${CHECKED} required task(s); delivery-evidence contract surfaced)" >&2
else
  echo "delivery-evidence-conformance[pre-release]: PASS (${CHECKED} required task(s) conformant)" >&2
fi
exit 0
