#!/usr/bin/env bash
# Validate framework script dependencies against Polaris-managed contracts.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="diff"
BASE_BRANCH=""
PATHS=()

usage() {
  cat <<'EOF'
Usage:
  scripts/validate-script-dependencies.sh [--mode diff|audit] [--base <ref>] [--path <script>]...

Checks framework scripts for unmanaged third-party dependencies.

Modes:
  diff   blocking mode for changed scripts
  audit  advisory mode for a wider scan; reports issues but exits 0

Baseline / allowlist entries must use the shared DP-184 D8 schema:
  owner, reason, remediation_task, expiry, scope
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --base)
      BASE_BRANCH="${2:-}"
      shift 2
      ;;
    --path)
      PATHS+=("${2:-}")
      shift 2
      ;;
    --help|-h)
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

case "$MODE" in
  diff|audit) ;;
  *) echo "invalid --mode: $MODE" >&2; exit 2 ;;
esac

PY_ARGS=("$ROOT_DIR" "$MODE" "$BASE_BRANCH")
if [[ "${#PATHS[@]}" -gt 0 ]]; then
  PY_ARGS+=("${PATHS[@]}")
fi

python3 - "${PY_ARGS[@]}" <<'PY'
from __future__ import annotations

import ast
import json
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
mode = sys.argv[2]
base = sys.argv[3]
explicit_paths = [Path(p) for p in sys.argv[4:] if p]

errors: list[str] = []
warnings: list[str] = []

SHELL_ALLOWED = {
    ".", ":", "[", "alias", "awk", "basename", "bash", "break", "cat", "cd",
    "chmod", "command", "continue", "cp", "curl", "cut", "date", "dirname",
    "done", "echo", "env", "eval", "exec", "exit", "export", "false", "fi", "find", "for",
    "gh", "git", "grep", "head", "if", "jq", "kill", "ln", "local", "lsof", "mkdir",
    "mise", "mv", "node", "nohup", "open", "pnpm", "printf", "pwd", "python",
    "python3", "read", "readonly", "return", "rg", "rm", "screen", "sed", "set",
    "shift", "shopt", "sleep", "sort", "source", "tail", "tee", "test", "tr",
    "trap", "true", "umask", "uniq", "wc", "while", "xargs",
    "polaris_require_delivery_tool", "polaris_require_mise_tool",
    "polaris_require_python", "polaris_with_runtime_tools",
}
NODE_BUILTINS = {
    "assert", "buffer", "child_process", "crypto", "events", "fs", "http",
    "https", "module", "os", "path", "process", "stream", "url", "util",
}
DIRECT_TOOL_POLICY = {
    "node": ("framework", "root_mise", "core", "true"),
    "pnpm": ("framework", "root_mise", "core", "true"),
    "jq": ("framework", "root_mise", "core", "true"),
    "rg": ("framework", "root_mise", "core", "true"),
    "gh": ("delivery", "system", "delivery", "false"),
}
TICKET_SCOPED_TOOLS = {
    "playwright", "vitest", "jest", "tsx", "ts-node",
}
VALID_DISPOSITIONS = {
    "accepted_current_debt",
    "false_positive",
    "migrated_to_resolver",
    "follow_up_required",
}
INVENTORY_PATH = root / "scripts/tool-direct-call-inventory.txt"
DISPOSITION_PATH = root / "scripts/tool-direct-call-inventory-disposition.txt"


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(root))
    except Exception:
        return str(path)


def record(path: Path, message: str) -> None:
    target = warnings if mode == "audit" else errors
    target.append(f"{rel(path)}: {message}")


def load_tsv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    rows: list[dict[str, str]] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines:
        return rows
    header = lines[0].split("\t")
    for lineno, line in enumerate(lines[1:], start=2):
        if not line.strip():
            continue
        values = line.split("\t")
        if len(values) != len(header):
            errors.append(f"{rel(path)}: line {lineno}: invalid TSV column count")
            continue
        rows.append(dict(zip(header, values)))
    return rows


def disposition_key(row: dict[str, str]) -> tuple[str, str, str]:
    return (row.get("path", ""), row.get("line", ""), row.get("tool", ""))


inventory_rows = load_tsv(INVENTORY_PATH)
disposition_rows = load_tsv(DISPOSITION_PATH)
disposition_by_key = {disposition_key(row): row for row in disposition_rows}


def validate_inventory_disposition() -> None:
    if not inventory_rows:
        return
    required = {"path", "line", "tool", "disposition", "owner_decision", "remediation_task", "expiry", "scope"}
    if not DISPOSITION_PATH.is_file():
        errors.append(
            f"{rel(DISPOSITION_PATH)}: missing disposition file for scripts/tool-direct-call-inventory.txt"
        )
        return
    for row in disposition_rows:
        missing = sorted(required - set(row))
        if missing:
            errors.append(f"{rel(DISPOSITION_PATH)}: missing columns: {', '.join(missing)}")
            return
        disposition = row.get("disposition", "")
        if disposition not in VALID_DISPOSITIONS:
            errors.append(
                f"{rel(DISPOSITION_PATH)}: {row.get('path')}:{row.get('line')}:{row.get('tool')} "
                f"has invalid disposition {disposition!r}"
            )
        if not row.get("owner_decision") or not row.get("remediation_task") or not row.get("expiry"):
            errors.append(
                f"{rel(DISPOSITION_PATH)}: {row.get('path')}:{row.get('line')}:{row.get('tool')} "
                "must include owner_decision, remediation_task, and expiry"
            )
    inventory_keys = {disposition_key(row) for row in inventory_rows}
    disposition_keys = set(disposition_by_key)
    for key in sorted(inventory_keys - disposition_keys):
        errors.append(
            f"{rel(DISPOSITION_PATH)}: missing disposition for baseline direct call "
            f"{key[0]}:{key[1]} tool={key[2]}"
        )
    for key in sorted(disposition_keys - inventory_keys):
        errors.append(
            f"{rel(DISPOSITION_PATH)}: disposition has no matching T1 baseline row "
            f"{key[0]}:{key[1]} tool={key[2]}"
        )


def git_changed_files() -> list[Path]:
    if explicit_paths:
        return [(root / p if not p.is_absolute() else p) for p in explicit_paths]
    if not base:
        try:
            base_ref = subprocess.check_output(
                ["git", "-C", str(root), "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
        except Exception:
            base_ref = "origin/main"
    else:
        base_ref = base
    commands = [
        ["git", "-C", str(root), "diff", "--name-only", f"{base_ref}..HEAD"],
        ["git", "-C", str(root), "diff", "--name-only"],
        ["git", "-C", str(root), "diff", "--cached", "--name-only"],
        ["git", "-C", str(root), "ls-files", "--others", "--exclude-standard"],
    ]
    files: set[str] = set()
    for cmd in commands:
        try:
            out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
        except Exception:
            continue
        files.update(line.strip() for line in out.splitlines() if line.strip())
    return [root / f for f in sorted(files)]


def audit_files() -> list[Path]:
    return sorted(
        p for p in root.glob("scripts/**/*")
        if p.is_file() and p.suffix in {".sh", ".py", ".mjs", ".js", ".cjs"}
    )


def target_files() -> list[Path]:
    candidates = audit_files() if mode == "audit" and not explicit_paths else git_changed_files()
    return [
        p for p in candidates
        if p.is_file()
        and rel(p).startswith("scripts/")
        and p.suffix in {".sh", ".py", ".mjs", ".js", ".cjs"}
    ]


def shell_functions(text: str) -> set[str]:
    names: set[str] = set()
    for line in text.splitlines():
        m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_-]*)\s*\(\)\s*\{", line)
        if m:
            names.add(m.group(1))
    return names


def scan_shell(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    functions = shell_functions(text)
    heredoc_until: str | None = None
    for lineno, raw in enumerate(text.splitlines(), start=1):
        if heredoc_until:
            if raw.strip() == heredoc_until:
                heredoc_until = None
            continue
        heredoc = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", raw)
        if heredoc:
            heredoc_until = heredoc.group(1)
        line = raw.split("#", 1)[0].strip()
        if not line or line.endswith("() {") or line in {"}", "do", "then", "else"}:
            continue
        hardcoded = re.search(r"(/Applications/Visual Studio Code\.app/\S*|/(?:usr/local|opt/homebrew)/bin)/(node|pnpm|jq|rg|gh)\b", line)
        if hardcoded:
            tool = hardcoded.group(2)
            owner, authority, profile, goes_to_mise = DIRECT_TOOL_POLICY[tool]
            record(
                path,
                f"line {lineno}: POLARIS_TOOL_HARDCODED_PATH tool={tool} owner={owner} "
                f"install_authority={authority} runtime_profile={profile} goes_to_mise={goes_to_mise} "
                "hint=resolve through scripts/lib/tool-resolution.sh",
            )
        if "=" in line and re.match(r"^[A-Za-z_][A-Za-z0-9_]*(\+)?=", line):
            continue
        line = re.sub(r"^(if|then|elif|while|until|do|else)\s+", "", line)
        line = line.lstrip("! (")
        token = re.split(r"\s+", line, maxsplit=1)[0]
        token = token.split("=", 1)[0]
        token = token.strip("\"'")
        if token in DIRECT_TOOL_POLICY:
            key = (rel(path), str(lineno), token)
            disposition = disposition_by_key.get(key, {}).get("disposition", "")
            if disposition in VALID_DISPOSITIONS:
                continue
            owner, authority, profile, goes_to_mise = DIRECT_TOOL_POLICY[token]
            record(
                path,
                f"line {lineno}: POLARIS_TOOL_DIRECT_CALL tool={token} owner={owner} "
                f"install_authority={authority} runtime_profile={profile} goes_to_mise={goes_to_mise} "
                "hint=call through scripts/lib/tool-resolution.sh or add an explicit inventory disposition",
            )
            continue
        if token in TICKET_SCOPED_TOOLS:
            record(
                path,
                f"line {lineno}: POLARIS_TICKET_SCOPED_TOOL_DIRECT_CALL tool={token} owner=ticket "
                "install_authority=task_required_tools runtime_profile=ticket-scoped goes_to_mise=false "
                "hint=declare this in task.md Required Tools; do not add it to root mise",
            )
            continue
        if not token or token in functions or token in SHELL_ALLOWED:
            continue
        if token in {"case", "esac", ";;"} or token.endswith(")") or token.endswith(";;"):
            continue
        if token.startswith("$") or token.startswith("[[") or token.startswith("(("):
            continue
        record(path, f"line {lineno}: unmanaged shell command {token!r}")


def scan_python(path: Path) -> None:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    stdlib = getattr(sys, "stdlib_module_names", set())
    for node in ast.walk(tree):
        names: list[str] = []
        if isinstance(node, ast.Import):
            names = [alias.name.split(".", 1)[0] for alias in node.names]
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            names = [node.module.split(".", 1)[0]]
        for name in names:
            if name not in stdlib:
                record(path, f"third-party Python import {name!r} is not declared")


def nearest_package_json(path: Path) -> Path | None:
    cur = path.parent
    while cur != root.parent:
        candidate = cur / "package.json"
        if candidate.is_file():
            return candidate
        if cur == root:
            break
        cur = cur.parent
    return None


def package_deps(pkg_path: Path | None) -> set[str]:
    if not pkg_path:
        return set()
    data = json.loads(pkg_path.read_text(encoding="utf-8"))
    deps: set[str] = set()
    for key in ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies"):
        value = data.get(key)
        if isinstance(value, dict):
            deps.update(value)
    return deps


def node_package_name(spec: str) -> str:
    if spec.startswith("@"):
        return "/".join(spec.split("/")[:2])
    return spec.split("/", 1)[0]


def scan_node(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    specs = re.findall(r"(?:import\s+(?:[^'\"]+\s+from\s+)?|require\()\s*['\"]([^'\"]+)['\"]", text)
    deps = package_deps(nearest_package_json(path))
    for spec in specs:
        if spec.startswith((".", "/", "node:")):
            continue
        pkg = node_package_name(spec)
        if pkg in NODE_BUILTINS:
            continue
        if pkg not in deps:
            record(path, f"Node package import {pkg!r} is not declared in owning package.json")


validate_inventory_disposition()

for script in target_files():
    try:
        if script.suffix == ".sh":
            scan_shell(script)
        elif script.suffix == ".py":
            scan_python(script)
        elif script.suffix in {".mjs", ".js", ".cjs"}:
            scan_node(script)
    except Exception as exc:
        record(script, f"scan failed: {exc}")

for item in warnings:
    print(f"ADVISORY: {item}", file=sys.stderr)
for item in errors:
    print(f"ERROR: {item}", file=sys.stderr)

if errors:
    print(f"FAIL: script dependency governance ({len(errors)} issue(s))", file=sys.stderr)
    sys.exit(1)

print("PASS: script dependency governance")
PY
