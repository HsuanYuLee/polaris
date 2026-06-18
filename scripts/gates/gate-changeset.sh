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

if [[ -z "$TASK_MD" ]]; then
  branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    exit 0
  fi
  TASK_MD="$(bash "$RESOLVE_BY_BRANCH" --scan-root "$WORKSPACE_SCRIPTS/.." "$branch" 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "$TASK_MD" ]]; then
  # Non-managed branch/admin workflow.
  exit 0
fi

if [[ ! -f "$TASK_MD" ]]; then
  echo "$PREFIX BLOCKED: resolved task.md does not exist: $TASK_MD" >&2
  exit 2
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
