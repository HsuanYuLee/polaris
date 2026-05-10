#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH=""
QUIET=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/check-script-manifest.sh [--root <repo>] [--manifest <path>] [--quiet]

Validates scripts/manifest.json against the scripts filesystem.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_DIR="$2"
      shift 2
      ;;
    --manifest)
      MANIFEST_PATH="$2"
      shift 2
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$MANIFEST_PATH" ]]; then
  MANIFEST_PATH="${ROOT_DIR}/scripts/manifest.json"
fi

python3 - "$ROOT_DIR" "$MANIFEST_PATH" "$QUIET" <<'PY'
import glob
import json
import os
import sys

root = os.path.abspath(sys.argv[1])
manifest_path = os.path.abspath(sys.argv[2])
quiet = sys.argv[3] == "1"

allowed_kind = {"gate", "writer", "resolver", "release", "selftest", "support", "legacy", "debug"}
allowed_runner = {"bash", "python3", "node"}
allowed_lifecycle = {"hot_path", "support_path", "legacy_keep", "sunset_candidate", "sunset_ready"}
allowed_relocation = {"stay", "move_with_wrapper", "move_direct", "delete_after_gate"}
required = {
    "path",
    "kind",
    "runner",
    "owner_surface",
    "selftest",
    "lifecycle",
    "relocation",
}


def rel(path):
    return os.path.relpath(path, root)


def fail(message):
    errors.append(message)


errors = []

if not os.path.exists(manifest_path):
    print(f"script manifest missing: {manifest_path}", file=sys.stderr)
    sys.exit(1)

try:
    with open(manifest_path, "r", encoding="utf-8") as fh:
        manifest = json.load(fh)
except Exception as exc:
    print(f"script manifest is not valid JSON: {exc}", file=sys.stderr)
    sys.exit(1)

entries = manifest.get("scripts")
if not isinstance(entries, list):
    print("script manifest must contain scripts[]", file=sys.stderr)
    sys.exit(1)

seen = {}
for index, row in enumerate(entries):
    label = row.get("path", f"<row {index}>") if isinstance(row, dict) else f"<row {index}>"
    if not isinstance(row, dict):
        fail(f"{label}: row must be an object")
        continue

    missing = sorted(required - set(row.keys()))
    if missing:
        fail(f"{label}: missing required field(s): {', '.join(missing)}")

    path = row.get("path")
    if not isinstance(path, str) or not path:
        fail(f"{label}: path must be a non-empty string")
        continue
    if path.startswith("/") or ".." in path.split("/"):
        fail(f"{path}: path must be repo-root relative and cannot contain '..'")
        continue
    if path in seen:
        fail(f"{path}: duplicate manifest row also seen at row {seen[path]}")
    seen[path] = index

    if not path.startswith("scripts/"):
        fail(f"{path}: manifest path must live under scripts/")
    target = os.path.join(root, path)
    if not os.path.isfile(target):
        fail(f"{path}: target script does not exist")

    kind = row.get("kind")
    if kind not in allowed_kind:
        fail(f"{path}: invalid kind {kind!r}")

    runner = row.get("runner")
    if runner not in allowed_runner:
        fail(f"{path}: invalid runner {runner!r}")
    elif path.endswith(".sh") and runner != "bash":
        fail(f"{path}: .sh scripts must declare runner=bash")
    elif path.endswith(".py") and runner != "python3":
        fail(f"{path}: .py scripts must declare runner=python3")
    elif path.endswith(".mjs") and runner != "node":
        fail(f"{path}: .mjs scripts must declare runner=node")

    owner_surface = row.get("owner_surface")
    if not isinstance(owner_surface, str) or not owner_surface.strip():
        fail(f"{path}: owner_surface must be a non-empty string")

    lifecycle = row.get("lifecycle")
    if lifecycle not in allowed_lifecycle:
        fail(f"{path}: invalid lifecycle {lifecycle!r}")

    relocation = row.get("relocation")
    if relocation not in allowed_relocation:
        fail(f"{path}: invalid relocation {relocation!r}")

    selftest = row.get("selftest")
    if selftest == "N/A":
        reason = row.get("selftest_reason")
        if not isinstance(reason, str) or not reason.strip():
            fail(f"{path}: selftest=N/A requires selftest_reason")
    elif isinstance(selftest, str) and selftest:
        if selftest.startswith("/") or ".." in selftest.split("/"):
            fail(f"{path}: selftest must be repo-root relative and cannot contain '..'")
        elif not os.path.isfile(os.path.join(root, selftest)):
            fail(f"{path}: declared selftest does not exist: {selftest}")
    else:
        fail(f"{path}: selftest must be a script path or N/A")

    if lifecycle == "sunset_ready":
        if not row.get("replacement_authority") and not row.get("no_active_consumer_evidence"):
            fail(f"{path}: sunset_ready requires replacement_authority or no_active_consumer_evidence")
    if relocation == "move_with_wrapper":
        if not row.get("wrapper_removal_criteria"):
            fail(f"{path}: move_with_wrapper requires wrapper_removal_criteria")
        if not row.get("relocation_verification"):
            fail(f"{path}: move_with_wrapper requires relocation_verification")

root_scripts = {
    rel(path)
    for pattern in ("*.sh", "*.py", "*.mjs")
    for path in glob.glob(os.path.join(root, "scripts", pattern))
    if os.path.isfile(path)
}
missing_root = sorted(root_scripts - set(seen.keys()))
for path in missing_root:
    fail(f"{path}: root script missing manifest row")

coverage = manifest.get("coverage", {})
patterns = coverage.get("entrypoint_patterns", []) if isinstance(coverage, dict) else []
if patterns is None:
    patterns = []
if not isinstance(patterns, list):
    fail("coverage.entrypoint_patterns must be a list when present")
else:
    for pattern in patterns:
        if not isinstance(pattern, str) or pattern.startswith("/") or ".." in pattern.split("/"):
            fail(f"invalid coverage entrypoint pattern: {pattern!r}")
            continue
        for path in glob.glob(os.path.join(root, pattern)):
            if os.path.isfile(path) and os.path.splitext(path)[1] in {".sh", ".py", ".mjs"}:
                rpath = rel(path)
                if rpath not in seen:
                    fail(f"{rpath}: coverage entrypoint missing manifest row from pattern {pattern}")

if errors:
    print("check-script-manifest FAIL", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    sys.exit(1)

if not quiet:
    print(f"check-script-manifest PASS ({len(entries)} manifest rows, {len(root_scripts)} root scripts covered)")
PY
