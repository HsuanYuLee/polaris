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
allowed_test_profiles = {"core", "runtime", "delivery", "full", "release"}
required_baseline_fields = {"owner", "reason", "remediation_task", "expiry", "scope"}
required_governed_test_fields = {
    "id",
    "command",
    "profiles",
    "changed_paths",
    "fixtures",
    "enrolled",
    "owner",
}
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

test_governance = manifest.get("test_governance")
if test_governance is not None:
    if not isinstance(test_governance, dict):
        fail("test_governance must be an object")
    else:
        baseline_schema = test_governance.get("baseline_schema")
        if not isinstance(baseline_schema, list) or set(baseline_schema) != required_baseline_fields:
            fail("test_governance.baseline_schema must equal owner/reason/remediation_task/expiry/scope")
        baseline = test_governance.get("baseline", [])
        if not isinstance(baseline, list):
            fail("test_governance.baseline must be a list")
        else:
            for index, row in enumerate(baseline):
                label = f"test_governance.baseline[{index}]"
                if not isinstance(row, dict):
                    fail(f"{label}: row must be an object")
                    continue
                missing = sorted(required_baseline_fields - set(row.keys()))
                if missing:
                    fail(f"{label}: missing required field(s): {', '.join(missing)}")
                for key in required_baseline_fields:
                    if not isinstance(row.get(key), str) or not row.get(key, "").strip():
                        fail(f"{label}: {key} must be a non-empty string")

governed_tests = manifest.get("governed_tests", [])
if not isinstance(governed_tests, list):
    fail("governed_tests must be a list when present")
else:
    seen_test_ids = {}
    for index, row in enumerate(governed_tests):
        label = row.get("id", f"<governed test {index}>") if isinstance(row, dict) else f"<governed test {index}>"
        if not isinstance(row, dict):
            fail(f"{label}: governed test row must be an object")
            continue
        missing = sorted(required_governed_test_fields - set(row.keys()))
        if missing:
            fail(f"{label}: missing required field(s): {', '.join(missing)}")
        test_id = row.get("id")
        if not isinstance(test_id, str) or not test_id.strip():
            fail(f"{label}: id must be a non-empty string")
        elif test_id in seen_test_ids:
            fail(f"{test_id}: duplicate governed test id also seen at row {seen_test_ids[test_id]}")
        else:
            seen_test_ids[test_id] = index
        command = row.get("command")
        if not isinstance(command, str) or not command.strip():
            fail(f"{label}: command must be a non-empty string")
        profiles = row.get("profiles")
        if not isinstance(profiles, list) or not profiles:
            fail(f"{label}: profiles must be a non-empty list")
        else:
            for profile in profiles:
                if profile not in allowed_test_profiles:
                    fail(f"{label}: invalid profile {profile!r}")
        for list_key in ("changed_paths", "fixtures"):
            value = row.get(list_key)
            if not isinstance(value, list):
                fail(f"{label}: {list_key} must be a list")
            elif any(not isinstance(item, str) or item.startswith("/") or ".." in item.split("/") for item in value):
                fail(f"{label}: {list_key} entries must be repo-root relative strings")
        if not isinstance(row.get("enrolled"), bool):
            fail(f"{label}: enrolled must be boolean")
        if not isinstance(row.get("owner"), str) or not row.get("owner", "").strip():
            fail(f"{label}: owner must be a non-empty string")

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

if [[ -f "${ROOT_DIR}/scripts/command-catalog.json" && -x "${ROOT_DIR}/scripts/validate-polaris-command-catalog.sh" ]]; then
  bash "${ROOT_DIR}/scripts/validate-polaris-command-catalog.sh" --root "${ROOT_DIR}" >/dev/null
fi
