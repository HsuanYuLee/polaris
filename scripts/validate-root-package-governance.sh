#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: bash scripts/validate-root-package-governance.sh [--root <repo>]

Validates root package.json / pnpm-workspace.yaml governance for Polaris.

Root package.json is allowed to expose thin aliases for compatibility and
package-local Node workflows. It must not become the root runtime manager and
must not declare third-party dependencies.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_DIR="${2:-}"
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

python3 - "$ROOT_DIR" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
errors = []

def fail(message):
    errors.append(message)

pkg_path = root / "package.json"
workspace_path = root / "pnpm-workspace.yaml"
lockfile_path = root / "pnpm-lock.yaml"
if not pkg_path.is_file():
    fail("package.json is missing")
    package = {}
else:
    try:
        package = json.loads(pkg_path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"package.json is invalid JSON: {exc}")
        package = {}

if not workspace_path.is_file():
    fail("pnpm-workspace.yaml is missing")
    workspace_text = ""
else:
    workspace_text = workspace_path.read_text(encoding="utf-8")

if not lockfile_path.is_file():
    fail("pnpm-lock.yaml is missing")

if package.get("private") is not True:
    fail("package.json private must be true")
if package.get("packageManager") != "pnpm@10.10.0":
    fail("package.json packageManager must be pnpm@10.10.0")
engines = package.get("engines")
if not isinstance(engines, dict) or engines.get("node") != ">=22.12.0":
    fail("package.json engines.node must be >=22.12.0")

for field in ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies"):
    value = package.get(field)
    if isinstance(value, dict) and value:
        fail(f"root package.json must not declare third-party {field}")

scripts = package.get("scripts")
required_scripts = {
    "viewer:dev": "bash scripts/polaris-viewer.sh --detach --mode dev --port ${PORT:-8080} --no-open",
    "viewer:preview": "bash scripts/polaris-viewer.sh --detach --preview --port ${PORT:-3334} --no-open",
    "viewer:status": "bash scripts/polaris-viewer.sh --status --port ${PORT:-8080}",
    "viewer:stop": "bash scripts/polaris-viewer.sh --stop --port ${PORT:-8080}",
    "viewer:verify": "bash scripts/polaris-toolchain.sh run docs.viewer.verify -- --ports ${PORT:-3334} --preview",
    "toolchain:install": "bash scripts/polaris-toolchain.sh install --required",
    "toolchain:doctor": "bash scripts/polaris-toolchain.sh doctor --required",
    "toolchain:manifest": "bash scripts/polaris-toolchain.sh manifest --required",
    "scripts:check": "bash scripts/check-script-manifest.sh",
    "commands:check": "bash scripts/validate-polaris-command-catalog.sh",
}
if not isinstance(scripts, dict):
    fail("package.json scripts must be an object")
    scripts = {}

for name, expected in required_scripts.items():
    actual = scripts.get(name)
    if actual != expected:
        fail(f"package.json script {name!r} must be thin alias: {expected}")

for name, command in scripts.items():
    if not isinstance(command, str):
        fail(f"package.json script {name!r} must be a string")
        continue
    if "\n" in command or "&&" in command or ";" in command:
        fail(f"package.json script {name!r} must remain a thin alias, not inline orchestration")
    if not command.startswith("bash scripts/"):
        fail(f"package.json script {name!r} must delegate to bash scripts/*")

workspace_packages = []
for raw_line in workspace_text.splitlines():
    line = raw_line.strip()
    if line.startswith("- "):
        workspace_packages.append(line[2:].strip().strip("'\""))

required_packages = {"docs-manager", "tools/polaris-toolchain", "scripts/e2e", "scripts/mockoon"}
missing = sorted(required_packages - set(workspace_packages))
if missing:
    fail(f"pnpm-workspace.yaml missing packages: {', '.join(missing)}")

if errors:
    print("validate-root-package-governance FAIL", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    sys.exit(1)

print("PASS: root package governance")
PY
