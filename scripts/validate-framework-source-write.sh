#!/usr/bin/env bash
# Purpose: Validate framework/control-plane source writes against the active task.md
#          lineage and Allowed Files contract. This is the single authority used by
#          Claude hooks, Codex adapters, guarded bash, and the framework PR gate.
# Exit:    0 = allowed/no framework source touched; 2 = blocked or invalid input.
set -euo pipefail

REPO=""
MODE="pre-write"
TASK_MD="${POLARIS_TASK_MD:-${POLARIS_FRAMEWORK_TASK_MD:-}}"
WRITER=""
BASE="${POLARIS_FRAMEWORK_SOURCE_BASE:-HEAD}"
SELF_CHECK_WIRING=0
PATHS=()
COMMAND_STRING=""

usage() {
  sed -n '2,18p' "$0" >&2
  cat >&2 <<'USAGE'
Usage:
  validate-framework-source-write.sh --repo <repo> --mode <pre-write|diff-audit|pr-gate> \
    --writer <writer> [--task-md <task.md>] [--path <path> ...] [--changed-file <path> ...]
  validate-framework-source-write.sh --repo <repo> --command "<shell command>" [--task-md <task.md>]
  validate-framework-source-write.sh --repo <repo> --self-check-wiring
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --writer) WRITER="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --path|--changed-file) PATHS+=("${2:-}"); shift 2 ;;
    --command) COMMAND_STRING="${2:-}"; shift 2 ;;
    --self-check-wiring) SELF_CHECK_WIRING=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "POLARIS_FRAMEWORK_SOURCE_WRITE_BLOCKED:usage unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
REPO="$(cd "$REPO" && pwd)"
OWNED_PATHS_JSON="$REPO/scripts/lib/framework-source-owned-paths.json"

if [[ ! -f "$OWNED_PATHS_JSON" ]]; then
  echo "POLARIS_FRAMEWORK_SOURCE_WRITE_BLOCKED:missing owned-path registry: $OWNED_PATHS_JSON" >&2
  exit 2
fi

if [[ "$SELF_CHECK_WIRING" -eq 1 ]]; then
  python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
required = {
    ".claude/hooks/pre-framework-source-write.sh": "validate-framework-source-write.sh",
    ".claude/hooks/post-framework-source-diff-audit.sh": "validate-framework-source-write.sh",
    ".codex/hooks/pre-framework-source-write.sh": "validate-framework-source-write.sh",
    ".codex/hooks/post-framework-source-diff-audit.sh": "validate-framework-source-write.sh",
    "scripts/codex-guarded-bash.sh": "validate-framework-source-write.sh",
    "scripts/check-framework-pr-gate.sh": "W17 framework source write authority",
    ".codex/config.toml": "pre-framework-source-write.sh",
}
missing = []
for rel, needle in required.items():
    path = repo / rel
    if not path.is_file():
        missing.append(f"{rel}: missing")
        continue
    text = path.read_text(encoding="utf-8")
    if needle not in text:
        missing.append(f"{rel}: missing {needle}")
settings = repo / ".claude/settings.json"
if settings.is_file():
    text = settings.read_text(encoding="utf-8")
    for needle in ("pre-framework-source-write.sh", "post-framework-source-diff-audit.sh"):
        if needle not in text:
            missing.append(f".claude/settings.json: missing {needle}")
else:
    missing.append(".claude/settings.json: missing")
registry = repo / ".claude/rules/mechanism-registry.md"
if registry.is_file():
    text = registry.read_text(encoding="utf-8")
    for hook in ("pre-framework-source-write.sh", "post-framework-source-diff-audit.sh"):
        if hook not in text or "scripts/validate-framework-source-write.sh" not in text:
            missing.append(f"mechanism-registry.md: missing parity row for {hook}")
else:
    missing.append(".claude/rules/mechanism-registry.md: missing")
if missing:
    print("POLARIS_FRAMEWORK_SOURCE_WRITE_BLOCKED:self-check-wiring", file=sys.stderr)
    for item in missing:
        print(f"  - {item}", file=sys.stderr)
    sys.exit(2)
print("PASS: framework source write wiring delegates to validate-framework-source-write.sh")
PY
  exit $?
fi

if [[ "$MODE" == "pr-gate" && "${#PATHS[@]}" -eq 0 && -z "$COMMAND_STRING" ]]; then
  while IFS= read -r p; do
    [[ -n "$p" ]] && PATHS+=("$p")
  done < <(git -C "$REPO" diff --name-only "$BASE" HEAD 2>/dev/null || true)
  while IFS= read -r p; do
    [[ -n "$p" ]] && PATHS+=("$p")
  done < <(git -C "$REPO" status --porcelain=v1 -z --untracked-files=all 2>/dev/null \
    | python3 -c 'import sys; data=sys.stdin.buffer.read().decode("utf-8","replace"); [print(e[3:]) for e in data.split("\0") if e and len(e) >= 4]')
fi

PY_ARGS=("$REPO" "$OWNED_PATHS_JSON" "$MODE" "$TASK_MD" "$WRITER" "$COMMAND_STRING")
if [[ "${#PATHS[@]}" -gt 0 ]]; then
  PY_ARGS+=("${PATHS[@]}")
fi

python3 - "${PY_ARGS[@]}" <<'PY'
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
        r'(?:>|>>)\s*([A-Za-z0-9_./{}$@:+-]+)',
        r'\btee(?:\s+-a)?\s+([A-Za-z0-9_./{}$@:+-]+)',
        r'\b(?:touch|rm|mkdir|rmdir)\s+(?:-[A-Za-z0-9]+\s+)*([A-Za-z0-9_./{}$@:+-]+)',
        r'\b(?:cp|mv)\s+(?:-[A-Za-z0-9]+\s+)*(?:[A-Za-z0-9_./{}$@:+-]+\s+)+([A-Za-z0-9_./{}$@:+-]+)',
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

all_paths = [relpath(p) for p in paths] + [relpath(p) for p in expand_command_paths(command)]
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
    block("unknown-writer", [f"writer={writer}", f"allowed={', '.join(sorted(allowed_writers))}"])

if mode == "pr-gate" and not task_md:
    print("PASS: framework source PR wiring checked; no task-md bound to this aggregate lane")
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
    block("outside-allowed-files", [f"{p} not in task.md Allowed Files" for p in violations])

print(f"PASS: framework source write allowed for {len(framework_paths)} path(s) via {writer}")
PY
