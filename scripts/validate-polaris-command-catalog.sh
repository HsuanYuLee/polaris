#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG_PATH="${ROOT_DIR}/scripts/command-catalog.json"
PACKAGE_PATH="${ROOT_DIR}/package.json"

usage() {
  cat <<'USAGE'
Usage: bash scripts/validate-polaris-command-catalog.sh [--root <repo>] [--catalog <path>]

Validates the Polaris common command catalog against root package scripts and script owners.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_DIR="${2:-}"
      CATALOG_PATH="${ROOT_DIR}/scripts/command-catalog.json"
      PACKAGE_PATH="${ROOT_DIR}/package.json"
      shift 2
      ;;
    --catalog)
      CATALOG_PATH="${2:-}"
      shift 2
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

python3 - "$ROOT_DIR" "$CATALOG_PATH" "$PACKAGE_PATH" <<'PY'
import json
import os
import re
import sys

root, catalog_path, package_path = sys.argv[1:4]
errors = []
required_categories = {"viewer", "toolchain", "scripts", "maintainer"}
required_ids = {
    "viewer.dev",
    "viewer.preview",
    "viewer.status",
    "viewer.stop",
    "viewer.verify",
    "toolchain.install",
    "toolchain.doctor",
    "toolchain.manifest",
    "scripts.check",
    "commands.check",
    "maintainer.framework-release",
    "maintainer.framework-docs-health",
}

def fail(message):
    errors.append(message)

try:
    with open(catalog_path, encoding="utf-8") as fh:
        catalog = json.load(fh)
except Exception as exc:
    print(f"command catalog is not valid JSON: {exc}", file=sys.stderr)
    sys.exit(1)

try:
    with open(package_path, encoding="utf-8") as fh:
        package = json.load(fh)
except Exception as exc:
    print(f"package.json is not valid JSON: {exc}", file=sys.stderr)
    sys.exit(1)

if catalog.get("version") != 1:
    fail("version must be 1")

categories = catalog.get("categories")
if not isinstance(categories, list):
    fail("categories must be an array")
else:
    missing = sorted(required_categories - set(categories))
    if missing:
        fail(f"missing required categories: {', '.join(missing)}")

commands = catalog.get("commands")
if not isinstance(commands, list) or not commands:
    fail("commands must be a non-empty array")
    commands = []

scripts = package.get("scripts") if isinstance(package, dict) else {}
if not isinstance(scripts, dict):
    fail("package.json scripts must be an object")
    scripts = {}

seen = set()
valid_id = re.compile(r"^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$")
for idx, row in enumerate(commands):
    label = f"commands[{idx}]"
    if not isinstance(row, dict):
        fail(f"{label}: row must be an object")
        continue
    cid = row.get("id")
    if not isinstance(cid, str) or not valid_id.match(cid):
        fail(f"{label}: invalid id {cid!r}")
        continue
    if cid in seen:
        fail(f"{cid}: duplicate command id")
    seen.add(cid)

    category = row.get("category")
    if category not in required_categories:
        fail(f"{cid}: invalid category {category!r}")
    surface = row.get("surface")
    if surface not in {"human", "skill", "maintainer-only"}:
        fail(f"{cid}: invalid surface {surface!r}")
    canonical = row.get("canonical")
    implementation = row.get("implementation")
    owner = row.get("owner")
    lifecycle = row.get("lifecycle")
    for key, value in (
        ("canonical", canonical),
        ("implementation", implementation),
        ("owner", owner),
        ("lifecycle", lifecycle),
    ):
        if not isinstance(value, str) or not value.strip():
            fail(f"{cid}: {key} must be a non-empty string")

    if surface == "human":
        if not isinstance(canonical, str) or not canonical.startswith("pnpm "):
            fail(f"{cid}: human commands must use pnpm canonical surface")
        else:
            script_name = canonical.split()[1]
            package_script = scripts.get(script_name)
            if package_script is None:
                fail(f"{cid}: package.json is missing script {script_name!r}")
            elif package_script != implementation:
                fail(f"{cid}: package script {script_name!r} does not match implementation")
        if isinstance(owner, str) and owner.startswith("scripts/"):
            owner_path = os.path.join(root, owner)
            if not os.path.isfile(owner_path):
                fail(f"{cid}: owner script does not exist: {owner}")

    if surface == "maintainer-only" and isinstance(canonical, str) and canonical.startswith("pnpm "):
        fail(f"{cid}: maintainer-only commands must not be exposed as root pnpm scripts")

missing_ids = sorted(required_ids - seen)
if missing_ids:
    fail(f"missing required command ids: {', '.join(missing_ids)}")

if errors:
    print("validate-polaris-command-catalog FAIL", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    sys.exit(1)

print(f"PASS: Polaris command catalog ({len(commands)} commands)")
PY
