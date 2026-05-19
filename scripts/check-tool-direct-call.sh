#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_REF=""
PATHS=()

usage() {
  cat <<'USAGE'
Usage: bash scripts/check-tool-direct-call.sh [--root <repo>] [--base <ref>] [--path <script>]... [--self-test]

Fails when changed shell scripts introduce bare root tool calls instead of using
Polaris tool resolution boundaries.
USAGE
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/scripts"
  cp "$0" "$tmp/scripts/check-tool-direct-call.sh"
  cat >"$tmp/scripts/ok.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
polaris_with_runtime_tools node --version
polaris_require_delivery_tool gh
SH
  cat >"$tmp/scripts/bad.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
node tool.mjs
gh pr view 1
SH
  bash "$tmp/scripts/check-tool-direct-call.sh" --root "$tmp" >/dev/null
  bash "$tmp/scripts/check-tool-direct-call.sh" --root "$tmp" --path scripts/ok.sh >/dev/null
  if bash "$tmp/scripts/check-tool-direct-call.sh" --root "$tmp" --path scripts/bad.sh >/tmp/check-tool-direct-call.out 2>&1; then
    echo "expected bare root tool calls to fail" >&2
    exit 1
  fi
  grep -q '\[POLARIS_TOOL_MISSING\] tool=node profile=core remediation=' /tmp/check-tool-direct-call.out
  grep -q '\[POLARIS_TOOL_MISSING\] tool=gh profile=delivery remediation=' /tmp/check-tool-direct-call.out
  echo "PASS: check-tool-direct-call selftest"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_DIR="$2"; shift 2 ;;
    --base) BASE_REF="$2"; shift 2 ;;
    --path) PATHS+=("$2"); shift 2 ;;
    --self-test) run_self_test; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "check-tool-direct-call: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

PY_ARGS=("$ROOT_DIR" "$BASE_REF")
if [[ "${#PATHS[@]}" -gt 0 ]]; then
  PY_ARGS+=("${PATHS[@]}")
fi

python3 - "${PY_ARGS[@]}" <<'PY'
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
base = sys.argv[2]
explicit = [Path(p) for p in sys.argv[3:]]
tools = {
    "node": "core",
    "pnpm": "core",
    "jq": "core",
    "rg": "core",
    "gh": "delivery",
}
allowed_commands = {
    ".", ":", "[", "bash", "break", "case", "cd", "command", "continue", "do",
    "done", "echo", "elif", "else", "esac", "exit", "export", "false", "fi",
    "for", "function", "if", "local", "printf", "pwd", "read", "return", "set",
    "shift", "source", "then", "true", "while",
    "polaris_require_delivery_tool", "polaris_require_mise_tool",
    "polaris_with_runtime_tools",
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

def baseline() -> set[tuple[str, str, str]]:
    path = root / "scripts/tool-direct-call-inventory.txt"
    if not path.is_file():
        return set()
    rows = set()
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines:
        return rows
    header = lines[0].split("\t")
    for line in lines[1:]:
        if not line.strip():
            continue
        values = line.split("\t")
        if len(values) != len(header):
            continue
        row = dict(zip(header, values))
        rows.add((row.get("path", ""), row.get("line", ""), row.get("tool", "")))
    return rows

def functions(text: str) -> set[str]:
    result = set()
    for line in text.splitlines():
        match = re.match(r"\s*([A-Za-z_][A-Za-z0-9_-]*)\s*\(\)\s*\{", line)
        if match:
            result.add(match.group(1))
    return result

base_rows = baseline()
errors: list[str] = []
for path in changed_files():
    if path.suffix != ".sh" or not path.is_file() or not rel(path).startswith("scripts/"):
        continue
    text = path.read_text(encoding="utf-8")
    local_functions = functions(text)
    heredoc_until = None
    for lineno, raw in enumerate(text.splitlines(), start=1):
        if heredoc_until:
            if raw.strip() == heredoc_until:
                heredoc_until = None
            continue
        heredoc = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", raw)
        if heredoc:
            heredoc_until = heredoc.group(1)
            continue
        line = raw.split("#", 1)[0].strip()
        if not line or line.endswith("() {") or line in {"}", "do", "then", "else"}:
            continue
        if "=" in line and re.match(r"^[A-Za-z_][A-Za-z0-9_]*(\+)?=", line):
            continue
        token = re.sub(r"^(if|then|elif|while|until|do|else)\s+", "", line).lstrip("! (")
        token = re.split(r"\s+", token, maxsplit=1)[0].split("=", 1)[0].strip("\"'")
        if not token or token in allowed_commands or token in local_functions:
            continue
        if token in tools and (rel(path), str(lineno), token) not in base_rows:
            profile = tools[token]
            errors.append(
                f"{rel(path)}:{lineno}: [POLARIS_TOOL_MISSING] tool={token} "
                f"profile={profile} remediation=\"route through scripts/lib/tool-resolution.sh "
                "or add an explicit owner disposition\""
            )

for error in errors:
    print(error, file=sys.stderr)
if errors:
    print(f"FAIL: tool direct-call gate ({len(errors)} issue(s))", file=sys.stderr)
    sys.exit(1)
print("PASS: tool direct-call gate")
PY
