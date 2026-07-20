"""Structured validator authority extracted from scripts/validate-marker-artifact-resolvable.sh."""

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
# DP-360 T7: the head-sha-keyed completion_gate / ac_verification markers are
# retired (delivery head + PASS now live in the task.md `deliverable` block);
# only the task_snapshot planning-freshness marker remains in scope (AC-NEG3 —
# task_snapshot guard must keep working).
KIND_DIRS = {
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
            [
                "bash",
                resolver,
                "--scan-root",
                scan_root,
                "--include-archive",
                work_item_id,
            ],
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
        sys.stderr.write(
            f"POLARIS_MARKER_ARTIFACT_UNRESOLVABLE:{marker_path} ({reason})\n"
        )
    sys.stderr.write(
        f"[validate-marker-artifact-resolvable] FAIL: {len(unresolvable)} "
        f"unresolvable marker(s) of {scanned} scanned\n"
    )
    raise SystemExit(2)

print(f"[validate-marker-artifact-resolvable] PASS: {scanned} marker(s) resolvable")
raise SystemExit(0)
