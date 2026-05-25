#!/usr/bin/env bash
set -euo pipefail

# close-parent-spec-if-complete.sh
#
# Best-effort parent lifecycle closer for task-based specs.
#
# Usage:
#   bash scripts/close-parent-spec-if-complete.sh --task-md <task.md> [--workspace <path>] [--dry-run] [--archive-terminal-parent]
#   CLOSE_PARENT_SPEC_SELFTEST=1 bash scripts/close-parent-spec-if-complete.sh
#
# Behavior:
#   - Given a task under specs/**/tasks/ or specs/**/tasks/pr-release/, find the
#     canonical parent index.md / refinement.md / plan.md.
#   - If any active sibling task remains under tasks/, NOOP.
#   - If any pr-release sibling task is not status: IMPLEMENTED, NOOP.
#   - If all sibling tasks are implemented, check off task checklist items,
#     rewrite moved task links to tasks/pr-release/*.md or tasks/pr-release/*/index.md, and mark the parent
#     spec IMPLEMENTED.
#   - Parent status closeout is delegated to reconcile-spec-lifecycle.mjs using
#     the resolved parent file path, avoiding key-based parent/task collisions.
#   - With --archive-terminal-parent, a design-plan parent closed by this helper
#     is immediately archived through archive-spec.sh after the status write.

PREFIX="[polaris parent-closeout]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/tool-resolution.sh
. "${SCRIPT_DIR}/lib/tool-resolution.sh"
TASK_MD=""
DRY_RUN=0
ARCHIVE_TERMINAL_PARENT=0

usage() {
  sed -n '3,23p' "$0" >&2
}

run_selftest() {
  local tmpdir dp_dir company_dir
  tmpdir="$(mktemp -d -t parent-closeout-selftest.XXXXXX)"
  tmpdir="$(cd "$tmpdir" && pwd -P)"
  trap "rm -rf '$tmpdir'" EXIT
  cat >"$tmpdir/mise.toml" <<'TOML'
[tools]
node = "22.12.0"
TOML
  if [[ -n "${MISE_TRUSTED_CONFIG_PATHS:-}" ]]; then
    export MISE_TRUSTED_CONFIG_PATHS="$tmpdir/mise.toml:$MISE_TRUSTED_CONFIG_PATHS"
  else
    export MISE_TRUSTED_CONFIG_PATHS="$tmpdir/mise.toml"
  fi

  dp_dir="$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-999-parent-closeout"
  mkdir -p "$dp_dir/tasks/pr-release"
  cat >"$dp_dir/plan.md" <<'MD'
---
title: "DP-999 parent closeout"
description: "DP-999 parent closeout smoke fixture."
topic: parent closeout smoke
created: 2026-04-30
status: LOCKED
locked_at: 2026-04-30
---

# DP-999

## Implementation Checklist

- [ ] T1: First task — `tasks/T1.md`
- [ ] T2: Second task — `tasks/T2.md`

## Work Orders

| Task | Work order |
|------|------------|
| T1 | `tasks/T1.md` |
| T2 | `tasks/T2.md` |
MD
  for task in T1 T2; do
    cat >"$dp_dir/tasks/pr-release/${task}.md" <<MD
---
title: "DP-999 ${task}"
description: "DP-999 ${task} parent closeout smoke fixture."
status: IMPLEMENTED
---
# ${task}

> Source: DP-999 | Task: DP-999-${task} | JIRA: N/A | Repo: polaris-framework
MD
  done

  env -u CLOSE_PARENT_SPEC_SELFTEST bash "$0" --task-md "$dp_dir/tasks/pr-release/T2.md" --workspace "$tmpdir" >/dev/null
  grep -q '^status: IMPLEMENTED$' "$dp_dir/plan.md" || {
    echo "[selftest] DP parent was not marked IMPLEMENTED" >&2
    return 1
  }
  grep -q 'tasks/pr-release/T1.md' "$dp_dir/plan.md" || {
    echo "[selftest] DP task links were not rewritten" >&2
    return 1
  }
  [[ -d "$dp_dir" ]] || {
    echo "[selftest] default DP closeout unexpectedly archived parent" >&2
    return 1
  }

  dp_dir="$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-998-parent-archive-closeout"
  mkdir -p "$dp_dir/tasks/pr-release"
  cat >"$dp_dir/plan.md" <<'MD'
---
title: "DP-998 parent archive closeout"
description: "DP-998 parent archive closeout smoke fixture."
topic: parent archive closeout smoke
created: 2026-05-02
status: LOCKED
locked_at: 2026-05-02
---

# DP-998

## Implementation Checklist

- [ ] T1: First task — `tasks/T1.md`
MD
  cat >"$dp_dir/tasks/pr-release/T1.md" <<'MD'
---
title: "DP-998 T1"
description: "DP-998 T1 archive closeout smoke fixture."
status: IMPLEMENTED
---
# T1

> Source: DP-998 | Task: DP-998-T1 | JIRA: N/A | Repo: polaris-framework
MD
  mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-998-unrelated-active-duplicate"
  cat >"$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-998-unrelated-active-duplicate/plan.md" <<'MD'
---
title: "DP-998 duplicate id smoke"
description: "DP-998 duplicate id smoke fixture."
topic: duplicate id smoke
created: 2026-05-05
status: LOCKED
locked_at: 2026-05-05
---

# DP-998 duplicate id smoke
MD

  env -u CLOSE_PARENT_SPEC_SELFTEST bash "$0" --task-md "$dp_dir/tasks/pr-release/T1.md" --workspace "$tmpdir" --archive-terminal-parent >/dev/null
  [[ ! -d "$dp_dir" ]] || {
    echo "[selftest] explicit archive mode did not move active DP parent" >&2
    return 1
  }
  [[ -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-998-parent-archive-closeout/plan.md" ]] || {
    echo "[selftest] explicit archive mode missing archived DP parent" >&2
    return 1
  }
  [[ -d "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-998-unrelated-active-duplicate" ]] || {
    echo "[selftest] explicit archive mode moved the wrong duplicate DP parent" >&2
    return 1
  }

  company_dir="$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/EPIC-999"
  mkdir -p "$company_dir/tasks/pr-release"
  cat >"$company_dir/refinement.md" <<'MD'
---
title: "EPIC-999 parent closeout"
description: "EPIC-999 parent closeout smoke fixture."
status: LOCKED
---
# EPIC-999 — Parent closeout smoke

## Implementation Checklist

- [ ] T1: Product task — `tasks/T1.md`
MD
  cat >"$company_dir/tasks/pr-release/T1.md" <<'MD'
---
title: "EPIC-999 T1"
description: "EPIC-999 T1 parent closeout smoke fixture."
status: IMPLEMENTED
---
# T1

> Source: EPIC-999 | Task: TASK-9999 | JIRA: TASK-9999 | Repo: exampleco-b2c-web
MD

  env -u CLOSE_PARENT_SPEC_SELFTEST bash "$0" --task-md "$company_dir/tasks/pr-release/T1.md" --workspace "$tmpdir" >/dev/null
  grep -q '^status: IMPLEMENTED$' "$company_dir/refinement.md" || {
    echo "[selftest] product parent was not marked IMPLEMENTED" >&2
    return 1
  }

  dp_dir="$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-997-folder-native-parent-closeout"
  mkdir -p "$dp_dir/tasks/pr-release/T1" "$dp_dir/tasks/pr-release/T2"
  cat >"$dp_dir/index.md" <<'MD'
---
title: "DP-997 folder-native parent closeout"
description: "DP-997 folder-native parent closeout smoke fixture."
topic: folder-native parent closeout smoke
created: 2026-05-06
status: LOCKED
locked_at: 2026-05-06
---

# DP-997

## Implementation Checklist

- [ ] T1: First task — `tasks/T1/index.md`
- [ ] T2: Second task — `tasks/T2/index.md`

## Work Orders

| Task | Work order |
|------|------------|
| T1 | `tasks/T1/index.md` |
| T2 | `tasks/T2/index.md` |
MD
  for task in T1 T2; do
    cat >"$dp_dir/tasks/pr-release/${task}/index.md" <<MD
---
title: "DP-997 ${task}"
description: "DP-997 ${task} folder-native parent closeout smoke fixture."
status: IMPLEMENTED
---
# ${task}

> Source: DP-997 | Task: DP-997-${task} | JIRA: N/A | Repo: polaris-framework
MD
  done

  env -u CLOSE_PARENT_SPEC_SELFTEST bash "$0" --task-md "$dp_dir/tasks/pr-release/T2/index.md" --workspace "$tmpdir" >/dev/null
  grep -q '^status: IMPLEMENTED$' "$dp_dir/index.md" || {
    echo "[selftest] folder-native DP parent was not marked IMPLEMENTED" >&2
    return 1
  }
  grep -q 'tasks/pr-release/T1/index.md' "$dp_dir/index.md" || {
    echo "[selftest] folder-native DP task links were not rewritten" >&2
    return 1
  }

  dp_dir="$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-994-markdown-link-parent-closeout"
  mkdir -p "$dp_dir/tasks/pr-release/T1" "$dp_dir/tasks/pr-release/T2"
  cat >"$dp_dir/index.md" <<'MD'
---
title: "DP-994 markdown link parent closeout"
description: "DP-994 markdown link parent closeout smoke fixture."
topic: markdown link parent closeout smoke
created: 2026-05-06
status: LOCKED
locked_at: 2026-05-06
---

# DP-994

## Implementation Checklist

- [ ] [T1](./tasks/T1/): First task
- [ ] [T2](./tasks/T2/): Second task

## Work Orders

| Task | Work order |
|------|------------|
| T1 | [T1](./tasks/T1/) |
| T2 | [T2](./tasks/T2/) |
MD
  for task in T1 T2; do
    cat >"$dp_dir/tasks/pr-release/${task}/index.md" <<MD
---
title: "DP-994 ${task}"
description: "DP-994 ${task} markdown link parent closeout smoke fixture."
status: IMPLEMENTED
---
# ${task}

> Source: DP-994 | Task: DP-994-${task} | JIRA: N/A | Repo: polaris-framework
MD
  done

  env -u CLOSE_PARENT_SPEC_SELFTEST bash "$0" --task-md "$dp_dir/tasks/pr-release/T2/index.md" --workspace "$tmpdir" >/dev/null
  grep -q '^status: IMPLEMENTED$' "$dp_dir/index.md" || {
    echo "[selftest] markdown-link DP parent was not marked IMPLEMENTED" >&2
    return 1
  }
  grep -q '\[T1\](\./tasks/pr-release/T1/)' "$dp_dir/index.md" || {
    echo "[selftest] markdown-link DP task links were not rewritten" >&2
    return 1
  }

  dp_dir="$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-996-folder-native-active-sibling"
  mkdir -p "$dp_dir/tasks/T2" "$dp_dir/tasks/pr-release/T1"
  cat >"$dp_dir/index.md" <<'MD'
---
title: "DP-996 folder-native active sibling"
description: "DP-996 folder-native active sibling smoke fixture."
topic: folder-native active sibling smoke
created: 2026-05-06
status: LOCKED
locked_at: 2026-05-06
---

# DP-996

## Implementation Checklist

- [ ] T1: First task — `tasks/T1/index.md`
- [ ] T2: Active task — `tasks/T2/index.md`

## Work Orders

| Task | Title | Status |
|------|-------|--------|
| T1 | First task | PLANNED |
| T2 | Active task | PLANNED |
MD
  cat >"$dp_dir/tasks/pr-release/T1/index.md" <<'MD'
---
title: "DP-996 T1"
description: "DP-996 T1 folder-native active sibling smoke fixture."
status: IMPLEMENTED
---
# T1

> Source: DP-996 | Task: DP-996-T1 | JIRA: N/A | Repo: polaris-framework
MD
  cat >"$dp_dir/tasks/T2/index.md" <<'MD'
---
title: "DP-996 T2"
description: "DP-996 T2 active sibling smoke fixture."
---
# T2

> Source: DP-996 | Task: DP-996-T2 | JIRA: N/A | Repo: polaris-framework
MD

  env -u CLOSE_PARENT_SPEC_SELFTEST bash "$0" --task-md "$dp_dir/tasks/pr-release/T1/index.md" --workspace "$tmpdir" >/dev/null
  ! grep -q '^status: IMPLEMENTED$' "$dp_dir/index.md" || {
    echo "[selftest] folder-native DP parent closed while active sibling remained" >&2
    return 1
  }
  grep -q '| T1 | First task | IMPLEMENTED |' "$dp_dir/index.md" || {
    echo "[selftest] active sibling closeout did not sync completed Work Orders status" >&2
    return 1
  }
  grep -q '| T2 | Active task | PLANNED |' "$dp_dir/index.md" || {
    echo "[selftest] active sibling closeout rewrote active Work Orders status" >&2
    return 1
  }

  dp_dir="$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-992-active-implementation-before-verification"
  mkdir -p "$dp_dir/tasks/T2" "$dp_dir/tasks/V1" "$dp_dir/tasks/pr-release/T1"
  cat >"$dp_dir/index.md" <<'MD'
---
title: "DP-992 active implementation before verification"
description: "DP-992 active implementation before verification smoke fixture."
topic: active implementation before verification smoke
created: 2026-05-10
status: LOCKED
locked_at: 2026-05-10
---

# DP-992

## Implementation Checklist

- [ ] T1: First task — `tasks/T1/index.md`
- [ ] T2: Active task — `tasks/T2/index.md`
- [ ] V1: Dogfood verification — `tasks/V1/index.md`
MD
  cat >"$dp_dir/tasks/pr-release/T1/index.md" <<'MD'
---
title: "DP-992 T1"
description: "DP-992 T1 active implementation before verification smoke fixture."
status: IMPLEMENTED
---
# T1

> Source: DP-992 | Task: DP-992-T1 | JIRA: N/A | Repo: polaris-framework
MD
  cat >"$dp_dir/tasks/T2/index.md" <<'MD'
---
title: "DP-992 T2"
description: "DP-992 T2 active implementation before verification smoke fixture."
---
# T2

> Source: DP-992 | Task: DP-992-T2 | JIRA: N/A | Repo: polaris-framework
MD
  cat >"$dp_dir/tasks/V1/index.md" <<'MD'
---
title: "DP-992 V1"
description: "DP-992 V1 active verification smoke fixture."
---
# V1

> Source: DP-992 | Task: DP-992-V1 | JIRA: N/A | Repo: polaris-framework
MD
  env -u CLOSE_PARENT_SPEC_SELFTEST bash "$0" --task-md "$dp_dir/tasks/pr-release/T1/index.md" --workspace "$tmpdir" >/dev/null
  ! grep -q '^status: IMPLEMENTED$' "$dp_dir/index.md" || {
    echo "[selftest] active implementation task with V blocker closed parent too early" >&2
    return 1
  }

  dp_dir="$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-993-active-verification-blocker"
  mkdir -p "$dp_dir/tasks/V1" "$dp_dir/tasks/pr-release/T1"
  cat >"$dp_dir/index.md" <<'MD'
---
title: "DP-993 active verification blocker"
description: "DP-993 active verification blocker smoke fixture."
topic: active verification blocker smoke
created: 2026-05-10
status: LOCKED
locked_at: 2026-05-10
---

# DP-993

## Implementation Checklist

- [ ] T1: First task — `tasks/T1/index.md`
- [ ] V1: Dogfood verification — `tasks/V1/index.md`
MD
  cat >"$dp_dir/tasks/pr-release/T1/index.md" <<'MD'
---
title: "DP-993 T1"
description: "DP-993 T1 active verification blocker smoke fixture."
status: IMPLEMENTED
---
# T1

> Source: DP-993 | Task: DP-993-T1 | JIRA: N/A | Repo: polaris-framework
MD
  cat >"$dp_dir/tasks/V1/index.md" <<'MD'
---
title: "DP-993 V1"
description: "DP-993 V1 active verification blocker smoke fixture."
---
# V1

> Source: DP-993 | Task: DP-993-V1 | JIRA: N/A | Repo: polaris-framework
MD
  if env -u CLOSE_PARENT_SPEC_SELFTEST bash "$0" --task-md "$dp_dir/tasks/pr-release/T1/index.md" --workspace "$tmpdir" >/dev/null 2>&1; then
    echo "[selftest] active V task did not block parent closeout" >&2
    return 1
  fi
  ! grep -q '^status: IMPLEMENTED$' "$dp_dir/index.md" || {
    echo "[selftest] active V task allowed parent implemented status" >&2
    return 1
  }

  dp_dir="$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-995-folder-native-parent-archive"
  mkdir -p "$dp_dir/tasks/pr-release/T1"
  cat >"$dp_dir/index.md" <<'MD'
---
title: "DP-995 folder-native parent archive"
description: "DP-995 folder-native parent archive smoke fixture."
topic: folder-native parent archive smoke
created: 2026-05-06
status: LOCKED
locked_at: 2026-05-06
---

# DP-995

## Implementation Checklist

- [ ] T1: First task — `tasks/T1/index.md`
MD
  cat >"$dp_dir/tasks/pr-release/T1/index.md" <<'MD'
---
title: "DP-995 T1"
description: "DP-995 T1 folder-native parent archive smoke fixture."
status: IMPLEMENTED
---
# T1

> Source: DP-995 | Task: DP-995-T1 | JIRA: N/A | Repo: polaris-framework
MD

  env -u CLOSE_PARENT_SPEC_SELFTEST bash "$0" --task-md "$dp_dir/tasks/pr-release/T1/index.md" --workspace "$tmpdir" --archive-terminal-parent >/dev/null
  [[ ! -d "$dp_dir" ]] || {
    echo "[selftest] folder-native explicit archive mode did not move active DP parent" >&2
    return 1
  }
  [[ -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-995-folder-native-parent-archive/index.md" ]] || {
    echo "[selftest] folder-native explicit archive mode missing archived DP index" >&2
    return 1
  }

  echo "[selftest] PASS"
}

if [[ "${CLOSE_PARENT_SPEC_SELFTEST:-0}" == "1" ]]; then
  run_selftest
  exit $?
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md)
      TASK_MD="${2:-}"
      shift 2
      ;;
    --workspace)
      WORKSPACE_ROOT="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --archive-terminal-parent)
      ARCHIVE_TERMINAL_PARENT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "$PREFIX unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

[[ -n "$TASK_MD" ]] || {
  echo "$PREFIX --task-md is required" >&2
  usage
  exit 64
}
[[ -f "$TASK_MD" ]] || { echo "$PREFIX task.md not found: $TASK_MD" >&2; exit 64; }
[[ -d "$WORKSPACE_ROOT" ]] || { echo "$PREFIX workspace not found: $WORKSPACE_ROOT" >&2; exit 64; }

WORKSPACE_ROOT="$(cd "$WORKSPACE_ROOT" && pwd)"
TASK_MD="$(cd "$(dirname "$TASK_MD")" && pwd)/$(basename "$TASK_MD")"

info_file="$(mktemp)"
trap 'rm -f "$info_file"' EXIT

python3 - "$TASK_MD" "$WORKSPACE_ROOT" "$DRY_RUN" >"$info_file" <<'PY'
import json
import re
import sys
from pathlib import Path

task_md = Path(sys.argv[1]).resolve()
workspace = Path(sys.argv[2]).resolve()
dry_run = sys.argv[3] == "1"

def emit(**kwargs):
    print(json.dumps(kwargs, ensure_ascii=False))

def frontmatter_status(path: Path) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return ""
    if not text.startswith("---\n"):
        return ""
    end = text.find("\n---\n", 4)
    if end == -1:
        return ""
    for line in text[4:end].splitlines():
        if line.startswith("status:"):
            return line.split(":", 1)[1].strip()
    return ""

def ac_verification_status(path: Path) -> str:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return ""
    in_block = False
    for line in lines:
        if line == "ac_verification:":
            in_block = True
            continue
        if in_block and line and not line.startswith((" ", "-")) and ":" in line:
            break
        if in_block:
            match = re.match(r"\s+status:\s*(\S+)", line)
            if match:
                return match.group(1)
    return ""

parts = task_md.parts
if "tasks" not in parts:
    emit(action="noop", reason="task path is not under tasks/", task_md=str(task_md))
    sys.exit(0)

tasks_index = len(parts) - 1 - list(reversed(parts)).index("tasks")
tasks_dir = Path(*parts[: tasks_index + 1])
parent_dir = tasks_dir.parent

if not parent_dir.exists():
    emit(action="noop", reason="parent dir not found", task_md=str(task_md))
    sys.exit(0)

is_design_plan = "/specs/design-plans/" in str(parent_dir)
if is_design_plan:
    parent_file = parent_dir / "index.md"
    if not parent_file.exists():
        parent_file = parent_dir / "plan.md"
    match = re.match(r"(DP-\d{3})(?:-|$)", parent_dir.name)
    parent_key = match.group(1) if match else ""
else:
    parent_file = parent_dir / "index.md"
    if not parent_file.exists():
        parent_file = parent_dir / "refinement.md"
    if not parent_file.exists():
        parent_file = parent_dir / "plan.md"
    parent_key = parent_dir.name

if not parent_file.exists():
    emit(action="noop", reason="parent refinement.md/plan.md not found", parent_dir=str(parent_dir))
    sys.exit(0)

active_tasks = []
active_implementation_tasks = []
active_verification_tasks = []
abandoned_tasks = []
# AC-NEG13 carve-out: ABANDONED active siblings are tracked separately and do
# not block parent closeout. They remain in place (not moved to pr-release/)
# and their status is preserved (not silently migrated to IMPLEMENTED).
for p in sorted(tasks_dir.iterdir()):
    if p.name == "pr-release":
        continue
    if p.is_file() and re.fullmatch(r"[TV]\d+[a-z]*\.md", p.name):
        status_path = p
        item = p
    elif p.is_dir() and re.fullmatch(r"[TV]\d+[a-z]*", p.name) and (p / "index.md").is_file():
        status_path = p / "index.md"
        item = p / "index.md"
    else:
        continue
    if frontmatter_status(status_path) == "ABANDONED":
        abandoned_tasks.append(item)
        continue
    active_tasks.append(item)
    if item.name.startswith("V") or (item.name == "index.md" and item.parent.name.startswith("V")):
        active_verification_tasks.append(item)
    else:
        active_implementation_tasks.append(item)

pr_release = tasks_dir / "pr-release"
completed_tasks = []
if pr_release.exists():
    for p in sorted(pr_release.iterdir()):
        if p.is_file() and re.fullmatch(r"[TV]\d+[a-z]*\.md", p.name):
            completed_tasks.append(p)
        elif p.is_dir() and re.fullmatch(r"[TV]\d+[a-z]*", p.name) and (p / "index.md").is_file():
            completed_tasks.append(p / "index.md")

def task_stem(path: Path) -> str:
    if path.name == "index.md" and path.parent.name != "pr-release":
        return path.parent.name
    return path.stem

implemented_stems = {
    task_stem(p) for p in completed_tasks
    if frontmatter_status(p) == "IMPLEMENTED"
}
# AC-NEG13: ABANDONED siblings should reflect ABANDONED status in the Work Orders
# table, not be silently migrated to IMPLEMENTED.
abandoned_stems_for_work_orders = {
    (p.parent.name if p.name == "index.md" else p.stem)
    for p in abandoned_tasks
}

def sync_work_orders_status(text, stems, abandoned=None):
    abandoned = abandoned or set()
    if not stems and not abandoned:
        return text

    lines = text.splitlines()
    out = []
    in_work_orders = False
    table_started = False
    status_idx = None
    task_idx = None

    for line in lines:
        stripped = line.strip()
        if line.startswith("## "):
            in_work_orders = stripped == "## Work Orders"
            table_started = False
            status_idx = None
            task_idx = None
            out.append(line)
            continue

        if not in_work_orders:
            out.append(line)
            continue

        if not stripped.startswith("|") or "|" not in stripped[1:]:
            if table_started:
                in_work_orders = False
                table_started = False
                status_idx = None
                task_idx = None
            out.append(line)
            continue

        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if status_idx is None:
            lowered = [cell.lower() for cell in cells]
            status_idx = next((idx for idx, cell in enumerate(lowered) if "status" in cell or "狀態" in cell), -1)
            task_idx = next((idx for idx, cell in enumerate(lowered) if "task" in cell or "work order" in cell or "單" in cell), 0)
            table_started = True
            out.append(line)
            continue

        if all(re.fullmatch(r":?-{3,}:?", cell.replace(" ", "")) for cell in cells):
            out.append(line)
            continue

        if status_idx >= 0 and status_idx < len(cells):
            row_text = " ".join(cells)
            task_cell = cells[task_idx] if task_idx is not None and task_idx < len(cells) else row_text
            matched_status = None
            for stem in stems:
                if re.search(rf"(?<![A-Z0-9]){re.escape(stem)}(?![a-zA-Z0-9])", task_cell) or re.search(rf"tasks/(?:pr-release/)?{re.escape(stem)}(?:\.md|/)", row_text):
                    matched_status = "IMPLEMENTED"
                    break
            if matched_status is None:
                for stem in abandoned:
                    if re.search(rf"(?<![A-Z0-9]){re.escape(stem)}(?![a-zA-Z0-9])", task_cell) or re.search(rf"tasks/(?:pr-release/)?{re.escape(stem)}(?:\.md|/)", row_text):
                        matched_status = "ABANDONED"
                        break
            if matched_status is not None:
                cells[status_idx] = matched_status
                line = "| " + " | ".join(cells) + " |"
        out.append(line)

    new_text = "\n".join(out)
    if text.endswith("\n"):
        new_text += "\n"
    return new_text

text = parent_file.read_text(encoding="utf-8")
status_synced_text = sync_work_orders_status(text, implemented_stems, abandoned_stems_for_work_orders)
status_synced = status_synced_text != text
if status_synced and not dry_run:
    parent_file.write_text(status_synced_text, encoding="utf-8")
text = status_synced_text

if active_implementation_tasks:
    emit(
        action="noop",
        reason="active sibling tasks remain",
        parent=str(parent_file),
        active=[str(p) for p in active_tasks],
        work_orders_status_synced=status_synced,
    )
    sys.exit(0)
if active_verification_tasks:
    emit(
        action="block",
        reason="active verification tasks remain",
        parent=str(parent_file),
        active=[str(p) for p in active_verification_tasks],
    )
    sys.exit(0)
if active_tasks:
    emit(
        action="noop",
        reason="active sibling tasks remain",
        parent=str(parent_file),
        active=[str(p) for p in active_tasks],
    )
    sys.exit(0)

if not completed_tasks:
    emit(action="noop", reason="no pr-release sibling tasks found", parent=str(parent_file))
    sys.exit(0)

unfinished = [
    str(p) for p in completed_tasks
    if frontmatter_status(p) != "IMPLEMENTED"
]
if unfinished:
    emit(
        action="noop",
        reason="pr-release sibling tasks are not all IMPLEMENTED",
        parent=str(parent_file),
        unfinished=unfinished,
    )
    sys.exit(0)

bad_verifications = [
    str(p) for p in completed_tasks
    if task_stem(p).startswith("V") and ac_verification_status(p) != "PASS"
]
if bad_verifications:
    emit(
        action="block",
        reason="verification tasks are not PASS",
        parent=str(parent_file),
        unfinished=bad_verifications,
    )
    sys.exit(0)

completed_stems = {task_stem(p) for p in completed_tasks}
# AC-NEG13: ABANDONED active siblings are treated as terminal-done for the
# purposes of checklist completion (do not block parent closeout) but their
# paths remain under tasks/ — they should NOT be rewritten to pr-release/.
def abandoned_stem(path: Path) -> str:
    return path.parent.name if path.name == "index.md" else path.stem
abandoned_stems = {abandoned_stem(p) for p in abandoned_tasks}
terminal_stems = completed_stems | abandoned_stems

def rewrite_task_path(match: re.Match[str], suffix: str) -> str:
    prefix = match.group(1) or ""
    task_key = match.group(2)
    return f"{prefix}tasks/pr-release/{task_key}{suffix}"

def rewrite_links(value: str) -> str:
    def maybe_rewrite(match: re.Match[str], suffix: str, group_idx: int) -> str:
        # AC-NEG13: do not rewrite ABANDONED siblings' tasks/ paths to pr-release/
        # because ABANDONED tasks stay under tasks/.
        captured = match.group(group_idx)
        stem = captured[: -len(".md")] if captured.endswith(".md") else captured
        if stem in abandoned_stems:
            return match.group(0)
        return rewrite_task_path(match, suffix)

    value = re.sub(
        r"(\./)?tasks/(?!pr-release/)([TV]\d+[a-z]*)/index\.md",
        lambda match: maybe_rewrite(match, "/index.md", 2),
        value,
    )
    value = re.sub(
        r"(\./)?tasks/(?!pr-release/)([TV]\d+[a-z]*)/(?=[)`])",
        lambda match: maybe_rewrite(match, "/", 2),
        value,
    )
    return re.sub(
        r"(\./)?tasks/(?!pr-release/)([TV]\d+[a-z]*\.md)",
        lambda match: maybe_rewrite(match, ".md", 2),
        value,
    )

def task_refs_from_line(value: str) -> set[str]:
    refs = set(re.findall(r"(?:\./)?tasks/(?:pr-release/)?([TV]\d+[a-z]*)\.md", value))
    refs.update(re.findall(r"(?:\./)?tasks/(?:pr-release/)?([TV]\d+[a-z]*)/index\.md", value))
    refs.update(re.findall(r"(?:\./)?tasks/(?:pr-release/)?([TV]\d+[a-z]*)/(?=[)`])", value))
    return refs

lines = text.splitlines()
out = []
in_checklist = False
remaining_unchecked = 0
for line in lines:
    if line.startswith("## "):
        in_checklist = line.strip() == "## Implementation Checklist"
        out.append(line)
        continue

    new_line = rewrite_links(line)
    if in_checklist and re.search(r"- \[ \]", new_line):
        refs = task_refs_from_line(new_line)
        prefix = re.match(r"\s*- \[ \]\s*([TV]\d+[a-z]*)(?=[:\s])", new_line)
        if prefix:
            refs.add(prefix.group(1))
        if refs and refs.issubset(terminal_stems):
            new_line = new_line.replace("- [ ]", "- [x]", 1)
        else:
            remaining_unchecked += 1
    out.append(new_line)

new_text = "\n".join(out)
if text.endswith("\n"):
    new_text += "\n"

if remaining_unchecked:
    if new_text != text and not dry_run:
        parent_file.write_text(new_text, encoding="utf-8")
    emit(
        action="noop",
        reason="parent checklist still has unchecked non-task items",
        parent=str(parent_file),
        remaining_unchecked=remaining_unchecked,
    )
    sys.exit(0)

if new_text != text and not dry_run:
    parent_file.write_text(new_text, encoding="utf-8")

emit(
    action="close",
    parent=str(parent_file),
    parent_key=parent_key,
    parent_type="design-plan" if is_design_plan else "spec",
    task_count=len(completed_tasks),
    dry_run=dry_run,
)
PY

action="$(python3 - "$info_file" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(data.get("action", "noop"))
PY
)"

if [[ "$action" == "block" ]]; then
  python3 - "$info_file" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
reason = data.get("reason", "blocked")
parent = data.get("parent", "")
suffix = f" ({parent})" if parent else ""
print(f"[polaris parent-closeout] BLOCKED: {reason}{suffix}")
PY
  exit 2
fi

if [[ "$action" != "close" ]]; then
  python3 - "$info_file" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
reason = data.get("reason", "not complete")
parent = data.get("parent", "")
suffix = f" ({parent})" if parent else ""
print(f"[polaris parent-closeout] NOOP: {reason}{suffix}")
PY
  exit 0
fi

parent_file="$(python3 - "$info_file" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["parent"])
PY
)"
parent_key="$(python3 - "$info_file" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["parent_key"])
PY
)"
parent_type="$(python3 - "$info_file" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["parent_type"])
PY
)"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "$PREFIX DRY-RUN: would mark ${parent_type} parent IMPLEMENTED: ${parent_file}"
  exit 0
fi

reconcile_out="$(POLARIS_WORKSPACE_ROOT="$WORKSPACE_ROOT" polaris_with_runtime_tools node "${SCRIPT_DIR}/reconcile-spec-lifecycle.mjs" --specs-root "${WORKSPACE_ROOT}/docs-manager/src/content/docs/specs" --apply --no-archive "$parent_file")"
if ! grep -q '^status: IMPLEMENTED$' "$parent_file"; then
  echo "$PREFIX failed to close parent through lifecycle reconciler: ${parent_file}" >&2
  printf '%s\n' "$reconcile_out" >&2
  exit 1
fi

if [[ "$ARCHIVE_TERMINAL_PARENT" -eq 1 ]]; then
  case "$parent_file" in
    */specs/design-plans/archive/*|*/specs/companies/*/archive/*)
      echo "$PREFIX archive skipped: parent already under archive (${parent_file})"
      ;;
    *)
      bash "${SCRIPT_DIR}/archive-spec.sh" --workspace "$WORKSPACE_ROOT" "$parent_file"
      ;;
  esac
fi

echo "$PREFIX ✅ parent implemented: ${parent_file}"
