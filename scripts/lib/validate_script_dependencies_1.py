"""Structured validator authority extracted from scripts/validate-script-dependencies.sh."""

from __future__ import annotations

import ast
import json
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
    ".",
    ":",
    "[",
    "alias",
    "awk",
    "basename",
    "bash",
    "break",
    "cat",
    "cd",
    "chmod",
    "cmp",
    "command",
    "continue",
    "cp",
    "curl",
    "cut",
    "date",
    "diff",
    "dirname",
    "done",
    "echo",
    "env",
    "eval",
    "exec",
    "exit",
    "export",
    "false",
    "fi",
    "find",
    "for",
    "gh",
    "git",
    "grep",
    "head",
    "if",
    "jq",
    "kill",
    "ln",
    "local",
    "lsof",
    "mkdir",
    "mise",
    "mv",
    "node",
    "nohup",
    "open",
    "pnpm",
    "printf",
    "pwd",
    "python",
    "python3",
    "read",
    "readonly",
    "return",
    "rg",
    "rm",
    "screen",
    "sed",
    "set",
    "shift",
    "shopt",
    "sleep",
    "sort",
    "source",
    "tail",
    "tee",
    "test",
    "tr",
    "trap",
    "true",
    "touch",
    "umask",
    "uniq",
    "wc",
    "while",
    "xargs",
    "declare",
    "polaris_require_delivery_tool",
    "polaris_require_mise_tool",
    "polaris_require_python",
    "polaris_with_runtime_tools",
}
NODE_BUILTINS = {
    "assert",
    "buffer",
    "child_process",
    "crypto",
    "events",
    "fs",
    "http",
    "https",
    "module",
    "os",
    "path",
    "process",
    "stream",
    "url",
    "util",
}
DIRECT_TOOL_POLICY = {
    "node": ("framework", "root_mise", "core", "true"),
    "pnpm": ("framework", "root_mise", "core", "true"),
    "jq": ("framework", "root_mise", "core", "true"),
    "rg": ("framework", "root_mise", "core", "true"),
    "gh": ("delivery", "system", "delivery", "false"),
}
TICKET_SCOPED_TOOLS = {
    "playwright",
    "vitest",
    "jest",
    "tsx",
    "ts-node",
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
    required = {
        "path",
        "line",
        "tool",
        "disposition",
        "owner_decision",
        "remediation_task",
        "expiry",
        "scope",
    }
    if not DISPOSITION_PATH.is_file():
        errors.append(
            f"{rel(DISPOSITION_PATH)}: missing disposition file for scripts/tool-direct-call-inventory.txt"
        )
        return
    for row in disposition_rows:
        missing = sorted(required - set(row))
        if missing:
            errors.append(
                f"{rel(DISPOSITION_PATH)}: missing columns: {', '.join(missing)}"
            )
            return
        disposition = row.get("disposition", "")
        if disposition not in VALID_DISPOSITIONS:
            errors.append(
                f"{rel(DISPOSITION_PATH)}: {row.get('path')}:{row.get('line')}:{row.get('tool')} "
                f"has invalid disposition {disposition!r}"
            )
        if (
            not row.get("owner_decision")
            or not row.get("remediation_task")
            or not row.get("expiry")
        ):
            errors.append(
                f"{rel(DISPOSITION_PATH)}: {row.get('path')}:{row.get('line')}:{row.get('tool')} "
                "must include owner_decision, remediation_task, and expiry"
            )
        if disposition == "accepted_current_debt":
            errors.append(
                f"{rel(DISPOSITION_PATH)}: {row.get('path')}:{row.get('line')}:{row.get('tool')} "
                "must not use accepted_current_debt; use migrated_to_resolver, false_positive, or follow_up_required"
            )
        if row.get("expiry") == "M-future":
            errors.append(
                f"{rel(DISPOSITION_PATH)}: {row.get('path')}:{row.get('line')}:{row.get('tool')} "
                "must not use expiry=M-future"
            )
        if row.get("remediation_task") == "DP-202-follow-up":
            errors.append(
                f"{rel(DISPOSITION_PATH)}: {row.get('path')}:{row.get('line')}:{row.get('tool')} "
                "must not use remediation_task=DP-202-follow-up"
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
                [
                    "git",
                    "-C",
                    str(root),
                    "rev-parse",
                    "--abbrev-ref",
                    "--symbolic-full-name",
                    "@{upstream}",
                ],
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
        p
        for p in root.glob("scripts/**/*")
        if p.is_file() and p.suffix in {".sh", ".py", ".mjs", ".js", ".cjs"}
    )


def target_files() -> list[Path]:
    candidates = (
        audit_files() if mode == "audit" and not explicit_paths else git_changed_files()
    )
    return [
        p
        for p in candidates
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
    rel_path = rel(path)
    is_selftest = rel_path.startswith("scripts/selftests/")
    heredoc_until: str | None = None
    single_quote_python = False
    continuation = False
    for lineno, raw in enumerate(text.splitlines(), start=1):
        if continuation:
            heredoc = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", raw)
            if heredoc:
                heredoc_until = heredoc.group(1)
                continuation = False
                continue
            continuation = raw.rstrip().endswith("\\")
            continue
        if single_quote_python:
            if raw.strip() == "'":
                single_quote_python = False
            continue
        if heredoc_until:
            if raw.strip() == heredoc_until:
                heredoc_until = None
            continue
        if re.search(r"\bpython3\s+-c\s+'", raw):
            single_quote_python = True
            continue
        heredoc = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", raw)
        if heredoc:
            heredoc_until = heredoc.group(1)
            continue
        # DP-230 T6: selftest portability convention. Selftests must derive
        # ROOT_DIR via scripts/lib/selftest-bootstrap.sh init_ROOT_DIR(), not
        # via `git rev-parse --show-toplevel`, which fails in fresh git clone
        # / detached HEAD / submodule scenarios.
        if is_selftest:
            stripped_for_check = raw.split("#", 1)[0]
            if re.search(r"\bgit\s+rev-parse\s+--show-toplevel\b", stripped_for_check):
                record(
                    path,
                    f"line {lineno}: POLARIS_SELFTEST_GIT_REV_PARSE_FORBIDDEN "
                    "hint=replace `git rev-parse --show-toplevel` with "
                    '`source "$(dirname "${BASH_SOURCE[0]}")/../lib/selftest-bootstrap.sh"; '
                    'init_ROOT_DIR "${BASH_SOURCE[0]}"` (DP-230 T6 AC15)',
                )
        line = raw.split("#", 1)[0].strip()
        if raw.rstrip().endswith("\\"):
            continuation = True
            continue
        if (
            not line
            or line.endswith("() {")
            or line in {"{", "}", "do", "then", "else"}
            or line.startswith("}")
        ):
            continue
        if line.startswith("-"):
            continue
        # AC34 attack: alias wrappers around managed tools must be flagged.
        # Match: alias name='<managed_tool> ...' or alias name="<managed_tool> ..."
        alias_match = re.match(
            r"\s*alias\s+[A-Za-z_][A-Za-z0-9_]*=(?P<q>['\"])(?P<body>[^'\"]+)(?P=q)",
            raw,
        )
        if alias_match:
            body = alias_match.group("body").strip()
            alias_token = re.split(r"\s+", body, maxsplit=1)[0]
            if alias_token in DIRECT_TOOL_POLICY:
                key = (rel(path), str(lineno), alias_token)
                disposition = disposition_by_key.get(key, {}).get("disposition", "")
                if disposition not in VALID_DISPOSITIONS:
                    owner, authority, profile, goes_to_mise = DIRECT_TOOL_POLICY[
                        alias_token
                    ]
                    record(
                        path,
                        f"line {lineno}: POLARIS_TOOL_DIRECT_CALL tool={alias_token} owner={owner} "
                        f"install_authority={authority} runtime_profile={profile} goes_to_mise={goes_to_mise} "
                        "hint=alias wrapping managed tool must go through scripts/lib/tool-resolution.sh",
                    )
                    continue
        hardcoded = re.search(
            r"(/Applications/Visual Studio Code\.app/\S*|/(?:usr/local|opt/homebrew)/bin)/(node|pnpm|jq|rg|gh)\b",
            line,
        )
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
        if "=" in line and re.match(r"^[A-Za-z_][A-Za-z0-9_]*(\+)?=", line):
            continue
        token = re.split(r"\s+", line, maxsplit=1)[0]
        token = token.split("=", 1)[0]
        token = token.strip("\"';")
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
        if token.startswith("polaris_"):
            continue
        if (
            token in {"case", "esac", ";;"}
            or token.endswith(")")
            or token.endswith(";;")
        ):
            continue
        if token.startswith("$") or token.startswith("[[") or token.startswith("(("):
            continue
        record(path, f"line {lineno}: unmanaged shell command {token!r}")


SUBPROCESS_CALLABLES = {"run", "call", "check_call", "check_output", "Popen"}
# Framework-internal Python helpers are referenced by relative module path /
# script path; recognising them prevents false positives when one framework
# Python script shells out to another (AC-NEG14). Anything that does NOT match
# a managed tool name (DIRECT_TOOL_POLICY) is already ignored by the scanner,
# but interpreter-style invocations (python3 / sys.executable) deserve an
# explicit allow so that the scanner cannot be tightened later without
# revisiting this list.
FRAMEWORK_PY_INTERPRETERS = {"python", "python3"}


def _subprocess_first_token(expr: ast.AST) -> tuple[str | None, str | None]:
    """Return (first_token, kind) where kind is 'list', 'str', 'fstring', or None.

    ``first_token`` is the literal string sitting in the executable slot of the
    subprocess call (e.g. ``"rg"`` for ``subprocess.run(["rg", ...])`` or
    ``subprocess.run("rg -n …", shell=True)``). Returns ``(None, None)`` when
    the executable slot is dynamic and cannot be statically resolved.
    """

    if isinstance(expr, (ast.List, ast.Tuple)):
        if not expr.elts:
            return None, None
        head = expr.elts[0]
        if isinstance(head, ast.Constant) and isinstance(head.value, str):
            return head.value, "list"
        return None, "list"
    if isinstance(expr, ast.Constant) and isinstance(expr.value, str):
        token = expr.value.strip().split()
        return (token[0] if token else None), "str"
    if isinstance(expr, ast.JoinedStr):
        if not expr.values:
            return None, None
        first = expr.values[0]
        if isinstance(first, ast.Constant) and isinstance(first.value, str):
            token = first.value.strip().split()
            if token:
                return token[0], "fstring"
        return None, "fstring"
    return None, None


def _subprocess_call_target(call: ast.Call) -> str | None:
    """Return ``"subprocess.<name>"`` when this looks like a subprocess call."""

    func = call.func
    if isinstance(func, ast.Attribute):
        owner = func.value
        if (
            isinstance(owner, ast.Name)
            and owner.id == "subprocess"
            and func.attr in SUBPROCESS_CALLABLES
        ):
            return f"subprocess.{func.attr}"
    if isinstance(func, ast.Name) and func.id in SUBPROCESS_CALLABLES:
        # ``from subprocess import run`` style is allowed but rare; treat the
        # bare name as subprocess.<name> for diagnostic purposes only.
        return f"subprocess.{func.id}"
    return None


def scan_python(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    tree = ast.parse(text, filename=str(path))
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

        if isinstance(node, ast.Call):
            target = _subprocess_call_target(node)
            if not target or not node.args:
                continue
            first_token, kind = _subprocess_first_token(node.args[0])
            if not first_token:
                continue
            if first_token in FRAMEWORK_PY_INTERPRETERS:
                # Framework Python -> Python invocation (AC-NEG14 whitelist).
                continue
            if first_token not in DIRECT_TOOL_POLICY:
                continue
            key = (rel(path), str(node.lineno), first_token)
            disposition = disposition_by_key.get(key, {}).get("disposition", "")
            if disposition in VALID_DISPOSITIONS:
                continue
            owner, authority, profile, goes_to_mise = DIRECT_TOOL_POLICY[first_token]
            invocation = f"{target}({kind})"
            record(
                path,
                f"line {node.lineno}: POLARIS_PYTHON_SUBPROCESS_TOOL_DIRECT_CALL "
                f"tool={first_token} owner={owner} install_authority={authority} "
                f"runtime_profile={profile} goes_to_mise={goes_to_mise} "
                f"invocation={invocation} "
                "hint=import scripts/lib/tool_resolution.resolve_tool() and pass the absolute path",
            )


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
    for key in (
        "dependencies",
        "devDependencies",
        "optionalDependencies",
        "peerDependencies",
    ):
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
    specs = re.findall(
        r"(?:import\s+(?:[^'\"]+\s+from\s+)?|require\()\s*['\"]([^'\"]+)['\"]", text
    )
    deps = package_deps(nearest_package_json(path))
    for spec in specs:
        if spec.startswith((".", "/", "node:")):
            continue
        pkg = node_package_name(spec)
        if pkg in NODE_BUILTINS:
            continue
        if pkg not in deps:
            record(
                path,
                f"Node package import {pkg!r} is not declared in owning package.json",
            )


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
    print(
        f"FAIL: script dependency governance ({len(errors)} issue(s))", file=sys.stderr
    )
    sys.exit(1)

print("PASS: script dependency governance")
