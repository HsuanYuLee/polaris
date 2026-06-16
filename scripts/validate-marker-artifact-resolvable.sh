#!/usr/bin/env bash
set -euo pipefail

# Purpose: DP-325 T5 / AC9 — full-surface detector for marker source_artifact
#          path-staleness (D class). Scans every completion_gate / ac_verification
#          / task_snapshot marker under .polaris/evidence/ and asserts each marker
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
EVIDENCE_ROOT="$EVIDENCE_ROOT" RESOLVER="$RESOLVER" SCAN_ROOT="$REPO_ROOT" python3 - <<'PY'
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

evidence_root = Path(os.environ["EVIDENCE_ROOT"])
resolver = os.environ["RESOLVER"]
scan_root = os.environ["SCAN_ROOT"]

# marker_kind -> evidence subdirectory holding that kind's markers.
KIND_DIRS = {
    "completion_gate": "completion-gate",
    "ac_verification": "ac-verification",
    "task_snapshot": "task-snapshot",
}


def relocate(work_item_id):
    """Re-resolve a moved task.md by work_item_id via the canonical resolver.

    Args:
        work_item_id: the marker's identity key (e.g. DP-325-T5).

    Returns:
        The resolved absolute task.md path as a string, or None when the
        resolver cannot locate a single artifact. --include-archive lets the
        resolver reach pr-release/ and container-archive locations.
    """
    if not work_item_id:
        return None
    try:
        out = subprocess.run(
            ["bash", resolver, "--scan-root", scan_root, "--include-archive", work_item_id],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except Exception:
        return None
    if out.returncode != 0:
        return None
    path = out.stdout.strip().splitlines()
    if not path:
        return None
    candidate = Path(path[-1].strip())
    return str(candidate) if candidate.is_file() else None


def marker_resolves(data):
    """Decide whether a marker's source_artifact is still resolvable.

    Returns a (ok, reason) tuple. A marker with no source_artifact is treated as
    out of scope (ok). A marker whose frozen path exists is ok. Otherwise the
    marker must be re-resolvable by work_item_id with a matching
    task_artifact_sha256; if it is path-only (no sha to re-verify) or the
    re-resolved file does not match the recorded sha, it fails closed.
    """
    freshness = data.get("freshness") or {}
    artifact = freshness.get("evidence_artifact") or freshness.get("source_artifact")
    if not artifact:
        return True, "no source_artifact (out of scope)"
    if Path(artifact).is_file():
        return True, "frozen path resolves"

    recorded_sha = freshness.get("task_artifact_sha256")
    work_item_id = data.get("work_item_id")
    if not recorded_sha:
        return False, "path-only marker (no task_artifact_sha256 to re-resolve)"

    relocated = relocate(work_item_id)
    if not relocated:
        return False, f"unresolvable by work_item_id={work_item_id}"
    actual_sha = hashlib.sha256(Path(relocated).read_bytes()).hexdigest()
    if actual_sha != recorded_sha:
        return False, f"relocated artifact sha mismatch ({relocated})"
    return True, f"re-resolved via work_item_id -> {relocated}"


scanned = 0
unresolvable = []
for kind, subdir in KIND_DIRS.items():
    marker_dir = evidence_root / subdir
    if not marker_dir.is_dir():
        continue
    for marker_path in sorted(marker_dir.glob("*.json")):
        try:
            data = json.loads(marker_path.read_text(encoding="utf-8"))
        except Exception as exc:
            unresolvable.append((marker_path, f"invalid JSON: {exc}"))
            continue
        if data.get("marker_kind") != kind:
            # Tolerate stray files; only scan markers of the expected kind.
            continue
        scanned += 1
        ok, reason = marker_resolves(data)
        if not ok:
            unresolvable.append((marker_path, reason))

if unresolvable:
    for marker_path, reason in unresolvable:
        sys.stderr.write(f"POLARIS_MARKER_ARTIFACT_UNRESOLVABLE:{marker_path} ({reason})\n")
    sys.stderr.write(
        f"[validate-marker-artifact-resolvable] FAIL: {len(unresolvable)} "
        f"unresolvable marker(s) of {scanned} scanned\n"
    )
    raise SystemExit(2)

print(f"[validate-marker-artifact-resolvable] PASS: {scanned} marker(s) resolvable")
raise SystemExit(0)
PY
