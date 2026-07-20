"""Structured validator authority extracted from scripts/validate-framework-source-write.sh."""

import fnmatch
import json
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
registry = Path(sys.argv[2])
mode, task_md, writer, command = sys.argv[3:7]
paths = list(sys.argv[7:])


def block(reason, details=()):
    print(f"POLARIS_FRAMEWORK_SOURCE_WRITE_BLOCKED:{reason}", file=sys.stderr)
    for detail in details:
        print(f"  - {detail}", file=sys.stderr)
    sys.exit(2)


def relpath(raw):
    if not raw:
        return ""
    text = raw.strip().strip("'\"")
    if not text:
        return ""
    p = Path(text)
    if p.is_absolute():
        try:
            return p.resolve().relative_to(repo).as_posix()
        except ValueError:
            return ""
    rel = p.as_posix()
    while rel.startswith("./"):
        rel = rel[2:]
    return rel


def expand_command_paths(cmd):
    if not cmd:
        return []
    found = []
    patterns = [
        r"(?:>|>>)\s*([A-Za-z0-9_./{}$@:+-]+)",
        r"\btee(?:\s+-a)?\s+([A-Za-z0-9_./{}$@:+-]+)",
        r"\b(?:touch|rm|mkdir|rmdir)\s+(?:-[A-Za-z0-9]+\s+)*([A-Za-z0-9_./{}$@:+-]+)",
        r"\b(?:cp|mv)\s+(?:-[A-Za-z0-9]+\s+)*(?:[A-Za-z0-9_./{}$@:+-]+\s+)+([A-Za-z0-9_./{}$@:+-]+)",
        r'\bsed\s+(?:-[A-Za-z0-9]+\s+)*-i(?:\s+["\'][^"\']*["\'])?\s+(?:[^\s]+\s+)+([A-Za-z0-9_./{}$@:+-]+)',
    ]
    for pat in patterns:
        found.extend(re.findall(pat, cmd))
    return found


try:
    cfg = json.loads(registry.read_text(encoding="utf-8"))
except Exception as exc:
    block("registry", [f"{registry}: {exc}"])

owned_globs = cfg.get("owned_path_globs") or []
allowed_writers = set(cfg.get("allowed_writers") or [])
if not owned_globs:
    block("registry", ["owned_path_globs is empty"])

all_paths = [relpath(p) for p in paths] + [
    relpath(p) for p in expand_command_paths(command)
]
all_paths = [p for p in all_paths if p]


def matches_one(path, pat):
    if pat.endswith("/**"):
        prefix = pat[:-3].rstrip("/") + "/"
        return path.startswith(prefix)
    return fnmatch.fnmatchcase(path, pat)


def matches(path, patterns):
    return any(matches_one(path, pat) for pat in patterns)


framework_paths = sorted({p for p in all_paths if matches(p, owned_globs)})
if not framework_paths:
    print("PASS: no framework source write detected")
    sys.exit(0)

if not writer:
    block("missing-writer", [f"framework paths: {', '.join(framework_paths)}"])
if writer not in allowed_writers:
    block(
        "unknown-writer",
        [f"writer={writer}", f"allowed={', '.join(sorted(allowed_writers))}"],
    )

if mode == "pr-gate" and not task_md:
    print(
        "PASS: framework source PR wiring checked; no task-md bound to this aggregate lane"
    )
    sys.exit(0)

if not task_md:
    block("missing-task-md", framework_paths)

task_path = Path(task_md)
if not task_path.is_absolute():
    task_path = (repo / task_path).resolve()
if not task_path.is_file():
    block("task-md-not-found", [str(task_path)])

text = task_path.read_text(encoding="utf-8")
status_match = re.search(r"^status:\s*(\S+)", text, re.MULTILINE)
status = status_match.group(1) if status_match else ""
if status in {"IMPLEMENTED", "ABANDONED"}:
    block("inactive-task", [f"{task_path}: status={status}"])
if not status:
    block("missing-task-status", [str(task_path)])

m = re.search(r"^## Allowed Files\s*\n(.*?)(?=^## |\Z)", text, re.DOTALL | re.MULTILINE)
if not m:
    block("missing-allowed-files", [str(task_path)])
allowed = []
for line in m.group(1).splitlines():
    item = line.strip()
    if not item.startswith("- "):
        continue
    item = item[2:].strip().strip("`").strip()
    if item:
        allowed.append(item)
if not allowed:
    block("empty-allowed-files", [str(task_path)])

violations = [p for p in framework_paths if not matches(p, allowed)]
if violations:
    block(
        "outside-allowed-files",
        [f"{p} not in task.md Allowed Files" for p in violations],
    )

print(
    f"PASS: framework source write allowed for {len(framework_paths)} path(s) via {writer}"
)
