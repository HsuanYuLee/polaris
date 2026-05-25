#!/usr/bin/env bash
# validate-manifest-parity.sh — DP-230 D20.
#
# Enforces parity between scripts/manifest.json and the on-disk script tree.
# Where check-script-manifest.sh validates row schema + root-level scripts
# coverage, this validator extends the coverage scope to scripts/lib/*.py and
# scripts/selftests/*.sh so new helper libs and selftests cannot land without
# explicit manifest ownership metadata.
#
# Failure mode: prints one `POLARIS_MANIFEST_MISSING: {script_path}` line per
# unregistered script to stderr and exits 1. PASS prints a quiet summary on
# stdout (suppressed with --quiet).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH=""
QUIET=0

usage() {
  cat <<'USAGE'
Usage: bash scripts/validate-manifest-parity.sh [--root <repo>] [--manifest <path>] [--quiet]

Scans scripts/*.sh, scripts/lib/*.py, and scripts/selftests/*.sh and verifies
that every file is registered in scripts/manifest.json. Missing entries emit
`POLARIS_MANIFEST_MISSING: {path}` to stderr and exit 1.
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
      echo "validate-manifest-parity: unknown argument: $1" >&2
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

if not os.path.exists(manifest_path):
    print(f"validate-manifest-parity: manifest missing: {manifest_path}", file=sys.stderr)
    sys.exit(2)

try:
    with open(manifest_path, "r", encoding="utf-8") as fh:
        manifest = json.load(fh)
except Exception as exc:
    print(f"validate-manifest-parity: manifest not valid JSON: {exc}", file=sys.stderr)
    sys.exit(2)

entries = manifest.get("scripts")
if not isinstance(entries, list):
    print("validate-manifest-parity: manifest.scripts[] missing", file=sys.stderr)
    sys.exit(2)

registered = set()
for row in entries:
    if isinstance(row, dict):
        path = row.get("path")
        if isinstance(path, str):
            registered.add(path)


def collect(globs):
    found = set()
    for pattern in globs:
        for absolute in glob.glob(os.path.join(root, pattern)):
            if os.path.isfile(absolute):
                found.add(os.path.relpath(absolute, root))
    return found


target_globs = [
    "scripts/*.sh",
    "scripts/lib/*.py",
    "scripts/selftests/*.sh",
]
filesystem = collect(target_globs)
missing = sorted(filesystem - registered)

if missing:
    for path in missing:
        print(f"POLARIS_MANIFEST_MISSING: {path}", file=sys.stderr)
    print(
        f"validate-manifest-parity: FAIL ({len(missing)} script(s) missing from manifest)",
        file=sys.stderr,
    )
    sys.exit(1)

if not quiet:
    print(
        f"validate-manifest-parity: PASS ({len(filesystem)} scripts covered across "
        f"{len(target_globs)} glob(s))"
    )
PY
