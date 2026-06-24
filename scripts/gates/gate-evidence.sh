#!/usr/bin/env bash
set -euo pipefail

# gate-evidence.sh — Portable git-hook gate (DP-032 Wave δ)
# Extracted from scripts/verification-evidence-gate.sh for cross-LLM portability.
# Can be called from: git pre-commit/pre-push hooks, polaris-pr-create.sh, or directly.
#
# Usage:
#   bash scripts/gates/gate-evidence.sh [--repo <path>] [--ticket <KEY>] [--task-md <path>]
#   bash scripts/gates/gate-evidence.sh [--repo <path>] --aggregate-release \
#        --source <DP-NNN> --bundled-tasks <T1,T2,...>
#
# Exit: 0 = pass/skip, 2 = block
# Bypass: POLARIS_SKIP_EVIDENCE=1
#
# DP-303 S4 (amended DP-360 T7): --aggregate-release switches the gate to
# aggregate mode. A bundle PR has no single delivery head; instead each bundled
# task's task.md deliverable block records its own delivery head
# (deliverable.head_sha) + PASS verification (deliverable.verification.status).
# The aggregate path treats those per-task blocks as satisfying the evidence gate
# so the canonical bundle build path (polaris-pr-create.sh --aggregate-release)
# does not need --skip-gates. DP-360 T7 retires the head-sha-keyed completion_gate
# marker: the task.md deliverable block is the sole evidence record, so there is
# no separate marker to forge — the recorded head + PASS in the block is the
# proof (the pre-push gate makes any pushed head verified-by-construction).

PREFIX="[polaris gate-evidence]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_SCRIPT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT=""
TICKET=""
TASK_MD=""
AGGREGATE_RELEASE=0
AGG_SOURCE=""
AGG_BUNDLED_TASKS=""
BEHAVIOR_ONLY="${POLARIS_GATE_EVIDENCE_BEHAVIOR_ONLY:-0}"
CHECK_VERIFICATION_PASSED="${ROOT_SCRIPT_DIR}/check-verification-passed.sh"
PARSE_TASK_MD="${ROOT_SCRIPT_DIR}/parse-task-md.sh"
RESOLVE_TASK_MD="${ROOT_SCRIPT_DIR}/resolve-task-md.sh"

MAIN_CHECKOUT_LIB="${ROOT_SCRIPT_DIR}/lib/main-checkout.sh"
VERIFICATION_EVIDENCE_LIB="${ROOT_SCRIPT_DIR}/lib/verification-evidence.sh"
SPECS_ROOT_LIB="${ROOT_SCRIPT_DIR}/lib/specs-root.sh"
EVIDENCE_CLASSIFIER="${ROOT_SCRIPT_DIR}/lib/evidence-classifier.sh"
if [[ -f "$MAIN_CHECKOUT_LIB" ]]; then
  # shellcheck source=../lib/main-checkout.sh
  . "$MAIN_CHECKOUT_LIB"
fi
if [[ -f "$VERIFICATION_EVIDENCE_LIB" ]]; then
  # shellcheck source=../lib/verification-evidence.sh
  . "$VERIFICATION_EVIDENCE_LIB"
fi
if [[ -f "$SPECS_ROOT_LIB" ]]; then
  # shellcheck source=../lib/specs-root.sh
  . "$SPECS_ROOT_LIB"
fi

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="$2"; shift 2 ;;
    --ticket) TICKET="$2"; shift 2 ;;
    --task-md) TASK_MD="$2"; shift 2 ;;
    --aggregate-release) AGGREGATE_RELEASE=1; shift ;;
    --source) AGG_SOURCE="$2"; shift 2 ;;
    --bundled-tasks) AGG_BUNDLED_TASKS="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/gates/gate-evidence.sh [--repo <path>] [--ticket <KEY>] [--task-md <path>]"
      echo "       bash scripts/gates/gate-evidence.sh [--repo <path>] --aggregate-release --source <DP-NNN> --bundled-tasks <T1,T2,...>"
      echo "  --repo <path>     Target repo (default: git rev-parse --show-toplevel)"
      echo "  --ticket <KEY>    JIRA ticket key (default: extract from branch name)"
      echo "  --task-md <path>  Work order path for conditional Layer C VR evidence"
      echo "  --aggregate-release          Aggregate bundle PR mode (per-task marker check)"
      echo "  --source <DP-NNN>            Bundle source DP id (with --aggregate-release)"
      echo "  --bundled-tasks T1,T2,...    Bundled task ids (with --aggregate-release)"
      exit 0
      ;;
    *) shift ;;
  esac
done

# Default repo
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO_ROOT" ]] || exit 0

# Bypass
if [[ "${POLARIS_SKIP_EVIDENCE:-}" == "1" ]]; then
  echo "$PREFIX POLARIS_SKIP_EVIDENCE=1 — bypassing." >&2
  exit 0
fi

# resolve_bundled_task_md: echo the canonical task.md path for a bundled work item
# id, or empty if it cannot be resolved.
# Args: $1 = repo root, $2 = work_item_id
resolve_bundled_task_md() {
  local repo="$1" work_item_id="$2"
  local main_checkout="$repo"
  if declare -F resolve_main_checkout >/dev/null 2>&1; then
    main_checkout="$(resolve_main_checkout "$repo" 2>/dev/null || echo "$repo")"
  fi
  [[ -x "$RESOLVE_TASK_MD" ]] || return 0
  # Probe the workspace root that owns docs-manager specs (markers anchor at main
  # checkout, but specs may live under a parent workspace root).
  local probe="$main_checkout"
  while [[ -n "$probe" && "$probe" != "/" ]]; do
    if [[ -d "$probe/docs-manager/src/content/docs/specs" ]]; then
      bash "$RESOLVE_TASK_MD" --scan-root "$probe" --include-archive "$work_item_id" 2>/dev/null | head -n 1
      return 0
    fi
    probe="$(dirname "$probe")"
  done
  return 0
}

# task_delivery_head: echo the recorded delivery head (deliverable.head_sha) for a
# bundled task.md, or empty if unset. DP-360 T7: the task.md deliverable block is
# the sole delivery-evidence record (the head-sha completion_gate marker is
# retired); this head + the PASS status below are read straight from the block.
# Args: $1 = task.md path
task_delivery_head() {
  local task_md="$1"
  [[ -x "$PARSE_TASK_MD" && -f "$task_md" ]] || return 0
  bash "$PARSE_TASK_MD" "$task_md" --no-resolve --field deliverable_head_sha 2>/dev/null || true
  return 0
}

# task_verification_status: echo deliverable.verification.status for a bundled
# task.md (PASS / FAIL / empty). DP-360 T7: replaces the completion_gate marker
# status read; the PASS authority now lives in the task.md deliverable block.
# Args: $1 = task.md path
task_verification_status() {
  local task_md="$1"
  [[ -x "$PARSE_TASK_MD" && -f "$task_md" ]] || return 0
  bash "$PARSE_TASK_MD" "$task_md" --no-resolve --field deliverable_verification_status 2>/dev/null || true
  return 0
}

# run_aggregate_evidence_gate: validate that every bundled task's task.md
# deliverable block records a delivery head (deliverable.head_sha) AND a PASS
# verification (deliverable.verification.status=PASS). DP-360 T7: the head-sha
# completion_gate marker is retired; the task.md block is the sole evidence
# source. The pre-push gate makes any pushed head verified-by-construction, so a
# block recording head + PASS is the durable delivery proof. Fails closed
# (exit 2) on any unresolvable task, missing head, or non-PASS status. Branch
# refs are never consulted (AC-NEG1).
run_aggregate_evidence_gate() {
  echo "$PREFIX aggregate mode: validating bundled-task deliverable blocks for ${AGG_SOURCE}." >&2
  if [[ -z "$AGG_SOURCE" || -z "$AGG_BUNDLED_TASKS" ]]; then
    echo "$PREFIX BLOCKED: --aggregate-release requires --source and --bundled-tasks." >&2
    exit 2
  fi

  local IFS=','
  local raw_tasks=()
  read -r -a raw_tasks <<<"$AGG_BUNDLED_TASKS"
  unset IFS

  local failures=0
  local task_id work_item_id delivery_head status
  for task_id in "${raw_tasks[@]}"; do
    task_id="$(printf '%s' "$task_id" | tr -d '[:space:]')"
    [[ -n "$task_id" ]] || continue

    # Accept both bare task ids (T1) and fully-qualified work item ids (DP-303-T1).
    if [[ "$task_id" == "$AGG_SOURCE"* ]]; then
      work_item_id="$task_id"
    else
      work_item_id="${AGG_SOURCE}-${task_id}"
    fi

    local task_md
    task_md="$(resolve_bundled_task_md "$REPO_ROOT" "$work_item_id")"
    if [[ -z "$task_md" || ! -f "$task_md" ]]; then
      echo "$PREFIX BLOCKED: cannot resolve task.md for bundled task ${work_item_id}." >&2
      failures=$((failures + 1))
      continue
    fi

    delivery_head="$(task_delivery_head "$task_md")"
    if [[ -z "$delivery_head" || "$delivery_head" == "N/A" || "$delivery_head" == "null" ]]; then
      echo "$PREFIX BLOCKED: bundled task ${work_item_id} has no recorded delivery head (deliverable.head_sha) in its task.md block." >&2
      failures=$((failures + 1))
      continue
    fi

    status="$(task_verification_status "$task_md")"
    if [[ "$status" != "PASS" ]]; then
      echo "$PREFIX BLOCKED: bundled task ${work_item_id} deliverable.verification.status is '${status:-<empty>}', expected PASS." >&2
      failures=$((failures + 1))
      continue
    fi

    echo "$PREFIX ✅ ${work_item_id}: deliverable block PASS @ ${delivery_head}." >&2
  done

  if [[ "$failures" -gt 0 ]]; then
    echo "$PREFIX BLOCKED: ${failures} bundled task(s) failed aggregate evidence check for ${AGG_SOURCE}." >&2
    exit 2
  fi
  echo "$PREFIX ✅ aggregate evidence gate passed for ${AGG_SOURCE} (all bundled-task deliverable blocks PASS)." >&2
  exit 0
}

if [[ "$AGGREGATE_RELEASE" -eq 1 ]]; then
  REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  run_aggregate_evidence_gate
fi

extract_task_key_from_branch() {
  local branch="$1"
  local key=""
  key="$(printf '%s' "$branch" | grep -oE 'DP-[0-9]{3}-T[0-9]+[a-z]*' | head -n 1 || true)"
  if [[ -n "$key" ]]; then
    printf '%s' "$key"
    return 0
  fi
  printf '%s' "$branch" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -n 1 || true
}

resolve_task_md_for_branch() {
  local repo_root="$1"
  local current_branch=""
  local main_checkout=""

  [[ -x "$ROOT_SCRIPT_DIR/resolve-task-md.sh" ]] || return 1
  current_branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ -n "$current_branch" ]] || return 1

  if declare -F resolve_main_checkout >/dev/null 2>&1; then
    main_checkout="$(resolve_main_checkout "$repo_root" 2>/dev/null || true)"
  fi
  [[ -n "$main_checkout" ]] || main_checkout="$repo_root"

  bash "$ROOT_SCRIPT_DIR/resolve-task-md.sh" --scan-root "$main_checkout" --current 2>/dev/null | head -n 1
}

json_field() {
  local payload="$1"
  local field="$2"
  python3 - "$payload" "$field" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
value = data.get(sys.argv[2])
if value is None:
    print("")
elif isinstance(value, list):
    for item in value:
        print(item)
else:
    print(value)
PY
}

emit_shared_gate_block() {
  local payload="$1"
  local status reason
  status="$(json_field "$payload" status)"
  reason="$(json_field "$payload" blocking_reason)"

  case "$reason" in
    missing_layer_b)
      local tmp_evidence durable_evidence
      tmp_evidence="$(verification_evidence_tmp_path "$TICKET" "$HEAD_SHA")"
      durable_evidence="$(verification_evidence_durable_path "$REPO_ROOT" "$TICKET" "$HEAD_SHA" 2>/dev/null || true)"
      echo "$PREFIX BLOCKED: No verification evidence for ${TICKET}" >&2
      echo "" >&2
      echo "Expected:" >&2
      echo "  ${tmp_evidence}  (D15 — head_sha-bound, written by run-verify-command.sh)" >&2
      echo "  ${durable_evidence}  (durable mirror, written by run-verify-command.sh)" >&2
      echo "" >&2
      echo "Run scripts/run-verify-command.sh --task-md <path> [--ticket ${TICKET}] to produce evidence." >&2
      echo "If this is a non-ticket PR, set POLARIS_SKIP_EVIDENCE=1" >&2
      ;;
    stale_layer_b)
      echo "$PREFIX BLOCKED: stale verification evidence for ${TICKET}; no evidence matches HEAD ${HEAD_SHA}" >&2
      echo "  Re-run scripts/run-verify-command.sh against the current HEAD." >&2
      ;;
    invalid_layer_b)
      local layer_b_path
      layer_b_path="$(json_field "$payload" artifacts_checked | head -n 1 || true)"
      echo "$PREFIX BLOCKED: head_sha-bound evidence file is malformed for ${TICKET}" >&2
      [[ -n "$layer_b_path" ]] && echo "  ${layer_b_path}: invalid_layer_b" >&2
      echo "" >&2
      echo "Evidence must contain: ticket, head_sha, writer=run-verify-command.sh, exit_code, at." >&2
      echo "Re-run: scripts/run-verify-command.sh --task-md <path> --ticket ${TICKET}" >&2
      ;;
    fail_layer_b)
      local layer_b_path
      layer_b_path="$(json_field "$payload" artifacts_checked | head -n 1 || true)"
      echo "$PREFIX BLOCKED: Verification evidence shows FAIL for ${TICKET}" >&2
      [[ -n "$layer_b_path" ]] && echo "  ${layer_b_path}: exit_code != 0" >&2
      echo "  Fix the underlying issue and re-run scripts/run-verify-command.sh." >&2
      ;;
    missing_layer_c)
      local vr_tmp vr_durable
      vr_tmp="$(vr_evidence_tmp_path "$TICKET" "$HEAD_SHA")"
      vr_durable="$(vr_evidence_durable_path "$REPO_ROOT" "$TICKET" "$HEAD_SHA" 2>/dev/null || true)"
      echo "$PREFIX BLOCKED: No Layer C VR evidence for ${TICKET}" >&2
      echo "" >&2
      echo "Expected:" >&2
      echo "  ${vr_tmp}  (Layer C — head_sha-bound, written by run-visual-snapshot.sh)" >&2
      echo "  ${vr_durable}  (durable mirror, written by run-visual-snapshot.sh)" >&2
      echo "" >&2
      echo "Run scripts/run-visual-snapshot.sh --task-md <path> --mode baseline, then --mode compare." >&2
      ;;
    stale_layer_c)
      echo "$PREFIX BLOCKED: stale Layer C VR evidence for ${TICKET}; no evidence matches HEAD ${HEAD_SHA}" >&2
      echo "" >&2
      echo "Run scripts/run-visual-snapshot.sh --task-md <path> --mode baseline, then --mode compare." >&2
      ;;
    invalid_layer_c|fail_layer_c|manual_required_layer_c|uncertain_layer_c|blocked_env_layer_c|in_progress_layer_c)
      local vr_path
      vr_path="$(json_field "$payload" artifacts_checked | tail -n 1 || true)"
      echo "$PREFIX BLOCKED: Layer C VR evidence is malformed or not passing for ${TICKET}" >&2
      [[ -n "$vr_path" ]] && echo "  ${vr_path}: status must be PASS (normalized outcome ${status})" >&2
      echo "" >&2
      echo "Evidence must contain: ticket, head_sha, writer=run-visual-snapshot.sh, mode=compare, status=PASS, at." >&2
      ;;
    *)
      echo "$PREFIX BLOCKED: shared verification gate failed for ${TICKET}" >&2
      echo "  status=${status:-unknown} reason=${reason:-unknown}" >&2
      ;;
  esac
}

# DP-351 G1: feat-aggregation evidence awareness. On a feat/DP-NNN -> main release
# push (the feature-branch aggregation release model, DP-334), the release diff is
# the union of already-delivered per-task changes. Each constituent task carried
# its own head_sha-bound verification evidence at its own PR; re-asserting that on
# the aggregated feat HEAD is impossible (the aggregated SHA never matched any one
# task's evidence) and historically forced a manual POLARIS_SKIP_EVIDENCE on the
# release push. Instead, treat the aggregation as exempt iff every canonical
# pr-release task already has a PASS completion_gate / ac_verification marker — the
# SAME markers closeout consumes (no new evidence file type). Any missing marker or
# an unresolvable / empty pr-release task set fails closed; the message never tells
# the operator to set POLARIS_SKIP_EVIDENCE.
#
# Returns: 0 = aggregation evidence satisfied (exempt); 2 = fail-closed.
# This function only runs when the head branch is exactly feat/DP-NNN (anchored),
# so a per-task branch (task/DP-NNN-Tn-... -> feat) never triggers it and keeps the
# default behavioral head-bound-evidence requirement.

# Resolve a PASS marker for one constituent pr-release task, keyed on that task's
# OWN head_sha (NOT the aggregated feat HEAD). DP-351 T2: per-task evidence is
# written at each task's own PR head — never at the feat aggregation SHA — so the
# gate must read each task's recorded head and look up the marker bound to it.
# Two existing marker types satisfy the task (no new evidence source): the
# completion_gate / ac_verification marker (via EVIDENCE_CLASSIFIER marker-pass)
# OR the persistent Layer B verify marker (.polaris/evidence/verify/, exit_code 0).
# Args: $1 = work_item_id, $2 = that task's own head_sha (from task.md frontmatter)
# Returns: 0 = a PASS marker resolves for the task at its own head; 1 = none found.
aggregation_task_pass_evidence() {
  local work_item_id="$1"
  local task_head="$2"
  [[ -n "$task_head" ]] || return 1
  if bash "$EVIDENCE_CLASSIFIER" marker-pass --repo "$REPO_ROOT" \
       --work-item-id "$work_item_id" --head-sha "$task_head" >/dev/null 2>&1; then
    return 0
  fi
  local roots=("$REPO_ROOT")
  if declare -F resolve_main_checkout >/dev/null 2>&1; then
    local mc
    mc="$(resolve_main_checkout "$REPO_ROOT" 2>/dev/null || true)"
    [[ -n "$mc" && "$mc" != "$REPO_ROOT" ]] && roots+=("$mc")
  fi
  local root marker
  for root in "${roots[@]}"; do
    for marker in "$root"/.polaris/evidence/verify/polaris-verified-"$work_item_id"-"$task_head"*.json; do
      [[ -f "$marker" ]] || continue
      if python3 -c "import json,sys;d=json.load(open(sys.argv[1]));sys.exit(0 if d.get('exit_code')==0 and d.get('ticket')==sys.argv[2] else 1)" "$marker" "$work_item_id" 2>/dev/null; then
        return 0
      fi
    done
  done
  return 1
}

check_feat_aggregation_evidence() {
  local feat_dp="$1"
  local specs_root=""
  local container=""
  local work_item_id=""
  local task_head=""
  local any_task=0
  local missing=0

  # Worktree-aware specs root resolution (mirrors gate-work-source.sh feat lane,
  # DP-351 T1): when the release runs from a feat/DP-NNN worktree the canonical
  # specs tree lives only in the main checkout, so a bare $REPO_ROOT/docs-manager
  # lookup would falsely fail. resolve_specs_root chains to the main checkout via
  # resolve_main_checkout. When it cannot resolve, leave container empty so the
  # fail-closed path below fires — the gate never falls open.
  if declare -F resolve_specs_root >/dev/null 2>&1; then
    specs_root="$(resolve_specs_root "$REPO_ROOT" 2>/dev/null || true)"
  fi
  if [[ -n "$specs_root" && -d "$specs_root" ]]; then
    for candidate in "$specs_root/design-plans/${feat_dp}-"*; do
      [[ -d "$candidate" ]] || continue
      container="$candidate"
      break
    done
    if [[ -z "$container" ]]; then
      # Maybe the DP was archived between delivery and release.
      for candidate in "$specs_root/design-plans/archive/${feat_dp}-"*; do
        [[ -d "$candidate" ]] || continue
        container="$candidate"
        break
      done
    fi
  fi

  if [[ -z "$container" ]]; then
    echo "$PREFIX BLOCKED: feat-aggregation evidence requires a resolvable DP container for ${feat_dp}; none found under the canonical specs root." >&2
    echo "$PREFIX Confirm the DP container exists under docs-manager/.../design-plans/${feat_dp}-* (or archive/) before opening the feat -> main release PR." >&2
    return 2
  fi

  # Enumerate the canonical pr-release task set: one completion_gate /
  # ac_verification PASS marker is required per task. EVIDENCE_CLASSIFIER
  # marker-pass is the SAME reader closeout uses — worktree-aware, status=PASS,
  # head_sha-bound, evidence-artifact resolvable — so this reuses the existing
  # marker contract instead of introducing a second reader.
  while IFS= read -r -d '' task_file; do
    work_item_id="$(table_field_for_aggregation 'Task ID' "$task_file")"
    [[ -n "$work_item_id" ]] || work_item_id="$(table_field_for_aggregation 'work_item_id' "$task_file")"
    [[ -n "$work_item_id" ]] || continue
    any_task=1
    # Read THIS task's own head_sha from its task.md frontmatter deliverable block;
    # the marker bound to that head — never the aggregated feat HEAD ($HEAD_SHA) —
    # is the evidence. head_sha is nested under `deliverable:` so it is indented;
    # scope the scan to the frontmatter (between the first two `---`) and allow
    # leading whitespace.
    task_head="$(awk -F: '
      /^---[[:space:]]*$/ { fm++; next }
      fm==1 && /^[[:space:]]*head_sha:[[:space:]]*/ { v=$2; gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); print v; exit }
    ' "$task_file")"
    if ! aggregation_task_pass_evidence "$work_item_id" "$task_head"; then
      echo "$PREFIX BLOCKED: feat-aggregation evidence missing for constituent task ${work_item_id}." >&2
      echo "$PREFIX No PASS completion_gate / verify marker resolves for ${work_item_id}@${task_head:-<no head_sha in task.md frontmatter>}; deliver that task (engineering / verify-AC) before the release push." >&2
      missing=1
    fi
  done < <(
    find "$container/tasks/pr-release" \
      -type f \( -path '*/T*/index.md' -o -name 'T*.md' \) -print0 2>/dev/null
  )

  if [[ "$any_task" -eq 0 ]]; then
    echo "$PREFIX BLOCKED: feat-aggregation evidence requires a non-empty pr-release task set for ${feat_dp}; none resolved under ${container}/tasks/pr-release." >&2
    return 2
  fi
  if [[ "$missing" -ne 0 ]]; then
    return 2
  fi

  echo "$PREFIX ✅ feat-aggregation evidence satisfied for ${feat_dp}: every pr-release task has a PASS marker." >&2
  return 0
}

# table_field_for_aggregation <field> <task-md>: read a markdown table-form
# Operational Context field (| field | value |). Mirrors the table_field readers
# in gate-work-source.sh / check-delivery-completion.sh; kept local so this gate
# does not need to source those scripts just for a one-row lookup.
table_field_for_aggregation() {
  local field="$1"
  local file="$2"
  awk -F '|' -v key="$field" '
    /^[[:space:]]*\|[[:space:]]*-+/ { next }
    NF >= 3 {
      f = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
      if (f == key) {
        v = $3
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
  ' "$file"
}

# Extract ticket/task identity from branch if not provided.
if [[ -z "$TICKET" ]]; then
  branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  TICKET="$(extract_task_key_from_branch "$branch")"
fi

# No ticket → framework/docs PR, allow
if [[ -z "$TICKET" ]]; then
  exit 0
fi

# Resolve HEAD SHA
HEAD_SHA=""
if [[ -d "$REPO_ROOT/.git" || -f "$REPO_ROOT/.git" ]]; then
  HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
fi

# DP-351 G1: feat-aggregation evidence branch — must run BEFORE the release_bump /
# metadata_only classifier and the behavioral head-bound-evidence requirement.
# Trigger condition: the head branch is exactly feat/DP-NNN (the DP-334
# feature-branch aggregation release model targets main). The anchored regex
# excludes per-task branches (task/DP-NNN-Tn-... -> feat) and main/other heads, so
# the aggregation exemption never widens to a non-release head. A matching head
# always goes through the marker-verification path (never the metadata free-pass),
# so the exemption is earned by real per-task evidence, not granted on branch name.
if [[ -n "$HEAD_SHA" ]]; then
  feat_head_branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ "$feat_head_branch" =~ ^feat/(DP-[0-9]+)$ ]]; then
    if check_feat_aggregation_evidence "${BASH_REMATCH[1]}"; then
      exit 0
    fi
    exit 2
  fi
fi

# DP-294 AC4: metadata-only / release-bump deltas are exempt from head_sha-bound
# verification evidence via the shared deterministic classifier — no manual
# POLARIS_SKIP_EVIDENCE needed. Behavioral deltas fall through and stay
# fail-closed below. This is the SAME rule the closeout consumer
# (check-local-extension-completion.sh) applies, sourced from one classifier lib.
if [[ -n "$HEAD_SHA" && -x "$EVIDENCE_CLASSIFIER" ]]; then
  cls_base="$(git -C "$REPO_ROOT" merge-base origin/main HEAD 2>/dev/null || true)"
  if [[ -n "$cls_base" && "$cls_base" != "$HEAD_SHA" ]]; then
    cls_disp="$(bash "$EVIDENCE_CLASSIFIER" classify --repo "$REPO_ROOT" --range "${cls_base}..${HEAD_SHA}" 2>/dev/null || true)"
  else
    cls_disp="$(bash "$EVIDENCE_CLASSIFIER" classify --repo "$REPO_ROOT" --head "$HEAD_SHA" 2>/dev/null || true)"
  fi
  case "$cls_disp" in
    release_bump|metadata_only)
      echo "$PREFIX ${cls_disp} delta — exempt from head_sha-bound evidence (DP-294 AC4 classifier; no manual skip)." >&2
      exit 0
      ;;
  esac
fi

evidence_root="$(verification_evidence_root_for_repo "$REPO_ROOT" 2>/dev/null || true)"
if [[ "$BEHAVIOR_ONLY" != "1" ]]; then
  if [[ -z "$TASK_MD" ]]; then
    TASK_MD="$(resolve_task_md_for_branch "$REPO_ROOT" || true)"
  fi

  if [[ -n "$TASK_MD" && -f "$TASK_MD" && -x "$CHECK_VERIFICATION_PASSED" ]]; then
    set +e
    shared_gate_json="$(bash "$CHECK_VERIFICATION_PASSED" --task-md "$TASK_MD" --repo "$REPO_ROOT" --ticket "$TICKET" --head-sha "$HEAD_SHA" --format json 2>/dev/null)"
    shared_gate_rc=$?
    set -e
    case "$shared_gate_rc" in
      0)
        echo "$PREFIX ✅ shared verification gate passed for ${TICKET} @ ${HEAD_SHA}." >&2
        ;;
      2)
        emit_shared_gate_block "$shared_gate_json"
        exit 2
        ;;
      *)
        echo "$PREFIX BLOCKED: shared verification gate resolver error for ${TICKET}" >&2
        echo "  task.md=${TASK_MD}" >&2
        echo "  Re-run ${CHECK_VERIFICATION_PASSED} directly to inspect the contract failure." >&2
        exit 2
        ;;
    esac
  else
    tmp_evidence="$(verification_evidence_tmp_path "$TICKET" "$HEAD_SHA")"
    durable_evidence="$(verification_evidence_durable_path "$REPO_ROOT" "$TICKET" "$HEAD_SHA" 2>/dev/null || true)"
    EVIDENCE_FILE="$(verification_evidence_resolve_existing_path "$REPO_ROOT" "$TICKET" "$HEAD_SHA" 2>/dev/null || true)"
    if [[ -z "$EVIDENCE_FILE" ]]; then
      echo "$PREFIX BLOCKED: No verification evidence for ${TICKET}" >&2
      echo "" >&2
      echo "Expected:" >&2
      echo "  ${tmp_evidence}  (D15 — head_sha-bound, written by run-verify-command.sh)" >&2
      echo "  ${durable_evidence}  (durable mirror, written by run-verify-command.sh)" >&2
      echo "" >&2
      echo "Run scripts/run-verify-command.sh --task-md <path> [--ticket ${TICKET}] to produce evidence." >&2
      echo "If this is a non-ticket PR, set POLARIS_SKIP_EVIDENCE=1" >&2
      exit 2
    fi

    if ! valid="$(verification_evidence_validate_file "$EVIDENCE_FILE" "$TICKET" "$HEAD_SHA" 2>/dev/null)"; then
      valid="${valid:-invalid: parse error}"
    fi
    if [[ "$valid" != "valid" ]]; then
      echo "$PREFIX BLOCKED: head_sha-bound evidence file is malformed for ${TICKET}" >&2
      echo "  ${EVIDENCE_FILE}: ${valid}" >&2
      echo "" >&2
      echo "Evidence must contain: ticket, head_sha, writer=run-verify-command.sh, exit_code, at." >&2
      echo "Re-run: scripts/run-verify-command.sh --task-md <path> --ticket ${TICKET}" >&2
      exit 2
    fi

    if ! exit_code_pass="$(verification_evidence_is_pass "$EVIDENCE_FILE" 2>/dev/null)"; then
      exit_code_pass="${exit_code_pass:-exit_code != 0}"
    fi
    if [[ "$exit_code_pass" != "pass" ]]; then
      echo "$PREFIX BLOCKED: Verification evidence shows FAIL for ${TICKET}" >&2
      echo "  ${EVIDENCE_FILE}: ${exit_code_pass}" >&2
      echo "  Fix the underlying issue and re-run scripts/run-verify-command.sh." >&2
      exit 2
    fi

    echo "$PREFIX ✅ D15 evidence valid for ${TICKET} @ ${HEAD_SHA}." >&2
    if [[ -z "$TASK_MD" || ! -f "$TASK_MD" ]]; then
      echo "$PREFIX Layer C VR skip: task.md not resolved." >&2
      exit 0
    fi
    echo "$PREFIX Layer C VR skip: shared verification gate unavailable; fallback only validated Layer B." >&2
  fi
fi

# Layer D: conditional behavior contract evidence. Only tasks that declare
# verification.behavior_contract.applies=true require this gate.
behavior_state="$(python3 - "$TASK_MD" <<'PY'
import csv
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()

def parse_scalar(value):
    value = value.strip()
    if value == "":
        return None
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    if value == "[]":
        return []
    if value.startswith("[") and value.endswith("]"):
        body = value[1:-1].strip()
        if not body:
            return []
        return [parse_scalar(part.strip()) for part in next(csv.reader([body], skipinitialspace=True))]
    if value == "true":
        return True
    if value == "false":
        return False
    return value

def frontmatter(all_lines):
    if not all_lines or all_lines[0].strip() != "---":
        return []
    for idx in range(1, len(all_lines)):
        if all_lines[idx].strip() == "---":
            return all_lines[1:idx]
    return []

def behavior_contract(fm_lines):
    in_verification = False
    in_behavior = False
    current_list_key = None
    data = None
    for raw in fm_lines:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        stripped = raw.strip()
        if indent == 0:
            in_behavior = False
            current_list_key = None
            if ":" not in stripped:
                in_verification = False
                continue
            key, _, value = stripped.partition(":")
            in_verification = key.strip() == "verification" and value.strip() == ""
            continue
        if not in_verification:
            continue
        if indent == 2 and ":" in stripped:
            current_list_key = None
            key, _, value = stripped.partition(":")
            if key.strip() == "behavior_contract":
                parsed = parse_scalar(value.strip())
                data = {} if parsed is None else parsed
                in_behavior = isinstance(data, dict)
            else:
                in_behavior = False
            continue
        if data is None or not isinstance(data, dict) or not in_behavior:
            continue
        if indent == 4 and ":" in stripped:
            key, _, value = stripped.partition(":")
            key = key.strip()
            value = value.strip()
            if value == "":
                data[key] = []
                current_list_key = key
            else:
                data[key] = parse_scalar(value)
                current_list_key = None
            continue
        if current_list_key and indent >= 6 and stripped.startswith("- "):
            data[current_list_key].append(parse_scalar(stripped[2:].strip()))
    return data or {}

bc = behavior_contract(frontmatter(lines))
print(json.dumps({
    "present": bool(bc),
    "applies": bc.get("applies") is True,
    "mode": bc.get("mode", ""),
    "assertions": bc.get("assertions") or [],
}, ensure_ascii=False))
PY
)"
behavior_present="$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("present") else "0")' "$behavior_state")"
behavior_applies="$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("applies") else "0")' "$behavior_state")"

if [[ "$behavior_present" != "1" ]]; then
  echo "$PREFIX Layer D behavior skip: task.md has no verification.behavior_contract." >&2
  exit 0
fi
if [[ "$behavior_applies" != "1" ]]; then
  echo "$PREFIX Layer D behavior skip: behavior_contract.applies=false." >&2
  exit 0
fi

safe_ticket="$(printf '%s' "$TICKET" | tr -c 'A-Za-z0-9._-' '-')"
behavior_candidates="$(
  {
    find /tmp -maxdepth 1 -type f -name "polaris-behavior-${safe_ticket}-${HEAD_SHA}-*.json" 2>/dev/null
    find /private/tmp -maxdepth 1 -type f -name "polaris-behavior-${safe_ticket}-${HEAD_SHA}-*.json" 2>/dev/null
    if [[ -d "${evidence_root}/behavior/${safe_ticket}" ]]; then
      find "${evidence_root}/behavior/${safe_ticket}" -maxdepth 1 -type f -name "polaris-behavior-${safe_ticket}-${HEAD_SHA}-*.json" 2>/dev/null
    fi
  } | sort -u
)"

if [[ -z "$behavior_candidates" ]]; then
  stale_behavior="$(
    {
      find /tmp -maxdepth 1 -type f -name "polaris-behavior-${safe_ticket}-*.json" 2>/dev/null
      find /private/tmp -maxdepth 1 -type f -name "polaris-behavior-${safe_ticket}-*.json" 2>/dev/null
      if [[ -d "${evidence_root}/behavior/${safe_ticket}" ]]; then
        find "${evidence_root}/behavior/${safe_ticket}" -maxdepth 1 -type f -name "polaris-behavior-${safe_ticket}-*.json" 2>/dev/null
      fi
    } | while IFS= read -r path; do
      if [[ "$path" != *-"$HEAD_SHA"-*.json ]]; then
        printf '%s\n' "$path"
        break
      fi
    done || true
  )"
  if [[ -n "$stale_behavior" ]]; then
    echo "$PREFIX BLOCKED: stale behavior evidence for ${TICKET}; no evidence matches HEAD ${HEAD_SHA}" >&2
  else
    echo "$PREFIX BLOCKED: No behavior contract evidence for ${TICKET}" >&2
  fi
  echo "" >&2
  echo "Expected:" >&2
  echo "  /tmp/polaris-behavior-${safe_ticket}-${HEAD_SHA}-{context_hash}.json" >&2
  echo "  ${evidence_root}/behavior/${safe_ticket}/polaris-behavior-${safe_ticket}-${HEAD_SHA}-{context_hash}.json" >&2
  echo "" >&2
  echo "Run scripts/run-behavior-contract.sh --task-md <path> --mode baseline, then --mode compare." >&2
  exit 2
fi

behavior_valid="$(python3 - "$TICKET" "$HEAD_SHA" "$behavior_state" $behavior_candidates <<'PY'
import json
import sys

ticket = sys.argv[1]
head_sha = sys.argv[2]
task_contract = json.loads(sys.argv[3])
paths = sys.argv[4:]
errors = []
valid_assertion_statuses = {"PASS", "FAIL", "MANUAL_REQUIRED", "NOT_COVERED"}
task_assertions = [str(item).strip() for item in task_contract.get("assertions", []) if str(item).strip()]

def assertion_key(value):
    return str(value or "").strip().casefold()

for path in paths:
    try:
        data = json.load(open(path, encoding="utf-8"))
        assert data.get("writer") == "run-behavior-contract.sh", "writer mismatch"
        assert data.get("ticket") == ticket, "ticket mismatch"
        assert data.get("head_sha") == head_sha, "head_sha mismatch"
        assert data.get("mode") == "compare", "mode must be compare"
        assert data.get("status") == "PASS", f"status must be PASS, got {data.get('status')!r}"
        assert data.get("at"), "missing at"
        assert data.get("context_hash"), "missing context_hash"
        media = list(data.get("screenshots") or []) + list(data.get("videos") or [])
        assert media, "missing screenshots/videos"
        if data.get("behavior_mode") in {"parity", "hybrid"}:
            assert data.get("baseline_evidence") not in {None, "", "N/A"}, "missing baseline_evidence"
        if task_assertions:
            assertion_results = data.get("assertion_results")
            assert isinstance(assertion_results, list), "missing assertion_results"
            by_assertion = {}
            for item in assertion_results:
                assert isinstance(item, dict), "assertion_results item must be object"
                status = str(item.get("status", "")).strip().upper()
                assert status in valid_assertion_statuses, f"invalid assertion status {status!r}"
                assertion = item.get("assertion") or item.get("name") or item.get("id")
                if assertion:
                    by_assertion.setdefault(assertion_key(assertion), status)
            missing = [item for item in task_assertions if assertion_key(item) not in by_assertion]
            assert not missing, "missing assertion_results for task assertions: " + ", ".join(missing)
        print("valid")
        raise SystemExit(0)
    except SystemExit:
        raise
    except Exception as exc:
        errors.append(f"{path}: {exc}")
print("invalid: " + "; ".join(errors))
PY
)"

if [[ "$behavior_valid" != "valid" ]]; then
  echo "$PREFIX BLOCKED: behavior evidence is malformed or not passing for ${TICKET}" >&2
  echo "  ${behavior_valid}" >&2
  echo "" >&2
  echo "Evidence must contain: ticket, head_sha, writer=run-behavior-contract.sh, mode=compare, status=PASS, at, media refs, and assertion_results for task assertions." >&2
  exit 2
fi

echo "$PREFIX ✅ behavior evidence valid for ${TICKET} @ ${HEAD_SHA}." >&2
exit 0
