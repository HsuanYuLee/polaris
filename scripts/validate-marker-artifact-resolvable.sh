#!/usr/bin/env bash
set -euo pipefail

# Purpose: DP-325 T5 / AC9 — full-surface detector for marker source_artifact
#          path-staleness (D class). DP-360 T7 retires the completion_gate /
#          ac_verification head-sha markers, so this scans the remaining
#          task_snapshot marker under .polaris/evidence/ and asserts each marker
#          that carries a freshness.source_artifact is still resolvable: either the
#          frozen path resolves on disk, OR the marker can be re-resolved by its
#          work_item_id (via the canonical resolve-task-md.sh) and verified against
#          the recorded freshness.task_artifact_sha256. A marker whose frozen path
#          is gone AND cannot be re-resolved is fail-closed (path-only-and-stale).
# Inputs:  --repo <abs> (default: main checkout resolved from cwd / POLARIS_WORKSPACE_ROOT)
#          [--evidence-root <abs>]  override the .polaris/evidence root to scan.
# Outputs: stdout summary; exit 0 when every marker resolves; exit 2 with a
#          structured POLARIS_MARKER_ARTIFACT_UNRESOLVABLE:<marker> line per
#          stale marker. Exit 64 on usage error.
# Reuse:   relocation reuses scripts/resolve-task-md.sh (the canonical work_item_id
#          -> task.md resolver). This script does NOT introduce a second resolver.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-task-md.sh"
PREFIX="[validate-marker-artifact-resolvable]"

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/validate-marker-artifact-resolvable.sh [--repo <abs>] [--evidence-root <abs>]

Scans completion_gate / ac_verification / task_snapshot markers and fails closed
when a marker's frozen source_artifact path is gone and cannot be re-resolved by
its work_item_id + task_artifact_sha256.
USAGE
  exit 64
}

REPO_ROOT=""
EVIDENCE_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --evidence-root) EVIDENCE_ROOT="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

# Resolve the repo root (main checkout) so the default evidence scan anchors on
# the durable .polaris/evidence tree even when invoked from a worktree.
if [[ -z "$REPO_ROOT" ]]; then
  if [[ -n "${POLARIS_WORKSPACE_ROOT:-}" ]]; then
    REPO_ROOT="$POLARIS_WORKSPACE_ROOT"
  else
    REPO_ROOT="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
fi

if [[ -z "$EVIDENCE_ROOT" ]]; then
  EVIDENCE_ROOT="$REPO_ROOT/.polaris/evidence"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  exit 2
fi

if [[ ! -d "$EVIDENCE_ROOT" ]]; then
  echo "$PREFIX no evidence root at $EVIDENCE_ROOT (nothing to scan)" >&2
  exit 0
fi

# The python program collects unresolvable markers. For each marker that is
# path-only-and-stale, it asks this shell wrapper to relocate by work_item_id
# through the canonical resolver, then verifies task_artifact_sha256. We keep the
# resolver call in shell (subprocess) and let python own the structured scan +
# sha verification (Decision Priority: readability of the structured walk).
EVIDENCE_ROOT="$EVIDENCE_ROOT" RESOLVER="$RESOLVER" SCAN_ROOT="$REPO_ROOT" python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_marker_artifact_resolvable_1.py"
