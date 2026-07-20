"""Structured validator authority extracted from scripts/validate-manifest-parity.sh."""

import glob
import json
import os
import sys

root = os.path.abspath(sys.argv[1])
manifest_path = os.path.abspath(sys.argv[2])
quiet = sys.argv[3] == "1"

if not os.path.exists(manifest_path):
    print(
        f"validate-manifest-parity: manifest missing: {manifest_path}", file=sys.stderr
    )
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
