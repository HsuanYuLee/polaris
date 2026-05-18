#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_REF=""
PATHS=()

usage() {
  cat <<'USAGE'
Usage: bash scripts/check-python-third-party.sh [--root <repo>] [--base <ref>] [--path <file>]... [--self-test]

Fails when changed Python files import third-party modules not declared in root
pyproject.toml dependencies.
USAGE
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/scripts"
  cp "$0" "$tmp/scripts/check-python-third-party.sh"
  cat >"$tmp/pyproject.toml" <<'TOML'
[project]
dependencies = ["PyYAML>=6"]
TOML
  cat >"$tmp/ok.py" <<'PY'
import json
import yaml
PY
  cat >"$tmp/bad.py" <<'PY'
import requests
PY
  bash "$tmp/scripts/check-python-third-party.sh" --root "$tmp" --path ok.py >/dev/null
  if bash "$tmp/scripts/check-python-third-party.sh" --root "$tmp" --path bad.py >/tmp/check-python-third-party.out 2>&1; then
    echo "expected undeclared Python import to fail" >&2
    exit 1
  fi
  grep -q "third-party import 'requests' is not declared" /tmp/check-python-third-party.out
  echo "PASS: check-python-third-party selftest"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_DIR="$2"; shift 2 ;;
    --base) BASE_REF="$2"; shift 2 ;;
    --path) PATHS+=("$2"); shift 2 ;;
    --self-test) run_self_test; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "check-python-third-party: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

python3 - "$ROOT_DIR" "$BASE_REF" "${PATHS[@]}" <<'PY'
from __future__ import annotations

import ast
import re
import subprocess
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11 on older system PATHs.
    tomllib = None

root = Path(sys.argv[1]).resolve()
base = sys.argv[2]
explicit = [Path(p) for p in sys.argv[3:]]
package_imports = {
    "pyyaml": {"yaml"},
}

def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(root))
    except ValueError:
        return str(path)

def changed_files() -> list[Path]:
    if explicit:
        return [(root / p if not p.is_absolute() else p) for p in explicit]
    ref = base or "origin/main"
    names: set[str] = set()
    for cmd in (
        ["git", "-C", str(root), "diff", "--name-only", f"{ref}..HEAD"],
        ["git", "-C", str(root), "diff", "--name-only"],
        ["git", "-C", str(root), "diff", "--cached", "--name-only"],
        ["git", "-C", str(root), "ls-files", "--others", "--exclude-standard"],
    ):
        try:
            out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
        except Exception:
            continue
        names.update(line.strip() for line in out.splitlines() if line.strip())
    return [root / name for name in sorted(names)]

def declared_import_roots() -> set[str]:
    pyproject = root / "pyproject.toml"
    if not pyproject.is_file():
        return set()
    pyproject_text = pyproject.read_text(encoding="utf-8")
    if tomllib is not None:
        data = tomllib.loads(pyproject_text)
        deps = data.get("project", {}).get("dependencies", [])
    else:
        match = re.search(r"(?ms)^dependencies\s*=\s*\[(.*?)\]", pyproject_text)
        deps = re.findall(r"['\"]([^'\"]+)['\"]", match.group(1)) if match else []
    result: set[str] = set()
    for dep in deps if isinstance(deps, list) else []:
        if not isinstance(dep, str):
            continue
        name = re.split(r"[<>=!~;\[\] ]", dep, maxsplit=1)[0].lower().replace("_", "-")
        result.add(name.replace("-", "_"))
        result.update(package_imports.get(name, set()))
    return result

stdlib = set(getattr(sys, "stdlib_module_names", set()))
if not stdlib:
    stdlib = {
        "argparse",
        "ast",
        "collections",
        "contextlib",
        "datetime",
        "functools",
        "hashlib",
        "importlib",
        "itertools",
        "json",
        "math",
        "os",
        "pathlib",
        "re",
        "shutil",
        "subprocess",
        "sys",
        "tempfile",
        "typing",
    }
declared = declared_import_roots()
errors: list[str] = []
for path in changed_files():
    if path.suffix != ".py" or not path.is_file():
        continue
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    for node in ast.walk(tree):
        names: list[str] = []
        if isinstance(node, ast.Import):
            names = [alias.name.split(".", 1)[0] for alias in node.names]
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            names = [node.module.split(".", 1)[0]]
        for name in names:
            if name not in stdlib and name not in declared:
                errors.append(f"{rel(path)}: third-party import {name!r} is not declared in pyproject.toml")

for error in errors:
    print(error, file=sys.stderr)
if errors:
    print(f"FAIL: Python third-party gate ({len(errors)} issue(s))", file=sys.stderr)
    sys.exit(1)
print("PASS: Python third-party gate")
PY
