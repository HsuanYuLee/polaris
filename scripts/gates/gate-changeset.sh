#!/usr/bin/env bash
set -euo pipefail

# gate-changeset.sh — Developer delivery gate for task-bound changesets.
# Blocks completion/PR creation when a repo has .changeset/config.json but the
# mechanically expected task changeset was not created.
#
# Usage:
#   bash scripts/gates/gate-changeset.sh [--repo <path>] [--task-md <path>]
#
# Exit: 0 = pass/skip, 2 = block
# Bypass: POLARIS_SKIP_CHANGESET_GATE=1

PREFIX="[polaris gate-changeset]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_SCRIPTS="${SCRIPT_DIR}/.."
RESOLVE_BY_BRANCH="${WORKSPACE_SCRIPTS}/resolve-task-md-by-branch.sh"
POLARIS_CHANGESET="${WORKSPACE_SCRIPTS}/polaris-changeset.sh"

REPO_ROOT=""
TASK_MD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/gates/gate-changeset.sh [--repo <path>] [--task-md <path>]"
      exit 0
      ;;
    *) shift ;;
  esac
done

if [[ "${POLARIS_SKIP_CHANGESET_GATE:-}" == "1" ]]; then
  echo "$PREFIX POLARIS_SKIP_CHANGESET_GATE=1 — bypassing." >&2
  exit 0
fi

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO_ROOT" ]] || exit 0

# Repos without changesets do not participate in this gate.
if [[ ! -f "$REPO_ROOT/.changeset/config.json" ]]; then
  exit 0
fi

# RESOLVED_TASK_MDS holds the FULL resolved candidate set (one per line). When
# --task-md is supplied it is the single member; when resolved by branch it is
# every task.md matching the branch (a bundle alias legitimately multi-matches).
# TASK_MD stays the first member so the per-task changeset contract below is
# unchanged; the release-stage exemption (DP-319) consults the full set.
RESOLVED_TASK_MDS=""
if [[ -n "$TASK_MD" ]]; then
  RESOLVED_TASK_MDS="$TASK_MD"
else
  branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    exit 0
  fi
  # Resolve the branch against the repo being gated ($REPO_ROOT). In every real
  # callsite the gate script lives in that same repo, so this equals the prior
  # "$WORKSPACE_SCRIPTS/.." while also resolving multi-match members correctly in
  # hermetic fixtures (DP-319 all-members rule).
  RESOLVED_TASK_MDS="$(bash "$RESOLVE_BY_BRANCH" --scan-root "$REPO_ROOT" "$branch" 2>/dev/null || true)"
  TASK_MD="$(printf '%s\n' "$RESOLVED_TASK_MDS" | head -n 1 || true)"
fi

if [[ -z "$TASK_MD" ]]; then
  # Non-managed branch/admin workflow.
  exit 0
fi

if [[ ! -f "$TASK_MD" ]]; then
  echo "$PREFIX BLOCKED: resolved task.md does not exist: $TASK_MD" >&2
  exit 2
fi

# is_release_stage_exempt: DP-319 — release-stage exemption keyed off the
# pr-release TASK LIFECYCLE POSITION, not container archive timing or branch
# naming. A framework-release bundle finalizes every member task.md into
# */tasks/pr-release/*; once that has happened the bundle PR delta is
# legitimately behavioral (it carries the members' implementation), so the
# per-task changeset / PR-title contracts must NOT tear it apart.
#
# all-members rule (AC5): EVERY resolved member must live under */tasks/pr-release/*.
# If any member is still in tasks/Tn/ (active development), the bundle is not
# release-staged — fall through to the per-task contract. Echoes nothing; returns
# 0 when release-stage exempt, 1 otherwise (including empty input).
is_release_stage_exempt() {
  local members="$1"
  local saw_member=0 line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    saw_member=1
    case "$line" in
      */tasks/pr-release/*) ;;
      *) return 1 ;;
    esac
  done <<<"$members"
  [[ "$saw_member" -eq 1 ]]
}

# DP-319: this exemption runs BEFORE the changeset check and the
# evidence-classifier so an impl-bearing (behavioral) bundle delta is not
# misclassified and blocked (EC2 / AC1). It does not relax any other gate.
if is_release_stage_exempt "$RESOLVED_TASK_MDS"; then
  echo "$PREFIX ✅ release-stage (all members in tasks/pr-release/) — exempt from per-task changeset (DP-319; pr-release lifecycle position)." >&2
  exit 0
fi

if bash "$POLARIS_CHANGESET" check --task-md "$TASK_MD" --repo "$REPO_ROOT"; then
  echo "$PREFIX ✅ changeset present for $(basename "$TASK_MD")." >&2
  exit 0
fi

# DP-305 AC8: release-bump / metadata-only push deltas are exempt — the release
# tail consumes the accumulated changesets via `mise run release:version`, so a
# resolved member task.md legitimately has no pending changeset on a release-bump
# HEAD. Classify the push delta via the SAME shared classifier gate-evidence.sh
# uses (DP-294); behavioral deltas fall through and stay fail-closed below. No
# manual POLARIS_SKIP_CHANGESET_GATE needed.
#
# DP-334 AC5: the release-stage exemption keys off the push-delta classifier
# (release_bump / metadata_only), not the legacy bundle model. It is therefore
# lifecycle-agnostic and already correct for the feat/DP-NNN model, where the
# version is squashed once at the feat HEAD (release:version consumes the
# accumulated member changesets there). No bundle_branch_alias coupling exists in
# this gate.
EVIDENCE_CLASSIFIER="${WORKSPACE_SCRIPTS}/lib/evidence-classifier.sh"
HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
if [[ -n "$HEAD_SHA" && -x "$EVIDENCE_CLASSIFIER" ]]; then
  cls_base="$(git -C "$REPO_ROOT" merge-base origin/main HEAD 2>/dev/null || true)"
  if [[ -n "$cls_base" && "$cls_base" != "$HEAD_SHA" ]]; then
    cls_disp="$(bash "$EVIDENCE_CLASSIFIER" classify --repo "$REPO_ROOT" --range "${cls_base}..${HEAD_SHA}" 2>/dev/null || true)"
  else
    cls_disp="$(bash "$EVIDENCE_CLASSIFIER" classify --repo "$REPO_ROOT" --head "$HEAD_SHA" 2>/dev/null || true)"
  fi
  case "$cls_disp" in
    release_bump|metadata_only)
      echo "$PREFIX ${cls_disp} delta — exempt from task-bound changeset (DP-305 AC8 classifier; no manual skip)." >&2
      exit 0
      ;;
  esac
fi

cat >&2 <<EOF
$PREFIX BLOCKED: missing task changeset.
  Repo:    $REPO_ROOT
  Task.md: $TASK_MD

Fix:
  bash "$POLARIS_CHANGESET" new --task-md "$TASK_MD" --repo "$REPO_ROOT"
EOF
exit 2
