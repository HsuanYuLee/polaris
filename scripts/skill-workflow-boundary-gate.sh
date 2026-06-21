#!/usr/bin/env bash
# skill-workflow-boundary-gate.sh — DP-230 D40 skill session mutation boundary gate.
#
# Establishes a per-skill session baseline of the working tree and, at handoff
# time, enforces that the session only touched files inside that skill's
# owning scope. Wired into refinement-handoff-gate.sh, the breakdown /
# engineering / verify-AC closeout steps, and the /auto-pass orchestrator
# cross-skill transition.
#
# Usage:
#   skill-workflow-boundary-gate.sh \
#     --skill <refinement|breakdown|engineering|verify-AC> \
#     --start \
#     --source-container /abs/path/to/source-container \
#     [--session-id <id>] [--repo <repo-root>] \
#     [--task-md </abs/path/to/task.md>]      # engineering only
#
#   skill-workflow-boundary-gate.sh \
#     --skill <refinement|breakdown|engineering|verify-AC> \
#     --check \
#     --source-container /abs/path/to/source-container \
#     [--session-id <id>] [--repo <repo-root>] \
#     [--task-md </abs/path/to/task.md>]
#
# Behavior:
#   --start  Capture session baseline (HEAD sha + dirty tracked paths +
#            task/* delivery branch ref snapshot) at
#            "${POLARIS_RUNTIME_DIR:-<repo>/.polaris/runtime}/skill-workflow-boundary/{skill}-{session_id}.json".
#            Dirty files already in the working tree at --start are recorded
#            as the "pre-existing dirty baseline carve-out" set.
#   --check  Compute the file set added/modified between baseline and HEAD +
#            working tree. Subtract the carve-out set. Any remaining file
#            that does not match the skill's owning_scope glob is a
#            mutation boundary violation; exit 1 with
#            POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:{skill} on stderr.
#            For --skill verify-AC ONLY, also compares the task/* delivery
#            branch ref snapshot against the baseline: any baseline task/* ref
#            that was MOVED to a different commit or REMOVED during the session
#            is a delivery branch mutation and fails closed with the same
#            marker (DP-303 S2). engineering legitimately creates/advances
#            task/* branches, so the ref-shift guard does not apply to it.
#
# task/* delivery branch ref-shift detection (DP-303 S2 / AC2 / AC3 / AC-NEG3):
#   verify-AC umbrella integration must run on a throwaway
#   "verify-integration-{source}-{Vn}" branch and must never check out, advance,
#   or delete a task/* delivery branch. To enforce this deterministically the
#   gate snapshots task/* refs at --start and re-checks them at --check (for
#   --skill verify-AC), so a delivery branch move/removal is caught even when no
#   in-scope file changed (ref-only mutation). Throwaway "verify-integration-*"
#   branches are EXCLUDED from the snapshot so creating/deleting them is not
#   mistaken for a delivery branch shift (EC2/R2). Newly-created task/* refs are
#   not flagged (concurrent-session noise in a shared repo).
#
# Owning scope (relative to --source-container or repo root as marked):
#   refinement   : <container>/refinement.json
#                  <container>/refinement.md
#                  <container>/index.md
#                  <container>/artifacts/**
#                  <container>/jira-comments/**
#                  <container>/refinement-inbox/**
#                  <container>/plan.md            (DP-backed legacy)
#   breakdown    : <container>/tasks/T*/index.md, T*.md, V*/index.md, V*.md
#                  <container>/tasks/**           (folder-native task artifacts)
#                  <container>/refinement-inbox/**
#   engineering  : files listed in task.md "## Allowed Files"
#                  (--task-md required)
#   verify-AC    : <container>/verification/V*/**
#                  <container>/tasks/V*/**
#                  <container>/refinement-inbox/**
#
# Bypass policy (AC-NEG16):
#   POLARIS_LANGUAGE_POLICY_BYPASS and POLARIS_SKILL_BOUNDARY_BYPASS are
#   IGNORED. The gate always evaluates the actual diff and always fails
#   closed on out-of-scope mutations.
#
# Exit codes:
#   0  baseline written (--start) or diff respects boundary (--check)
#   1  --check found an out-of-scope mutation (POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED)
#   2  usage / input / IO error

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"

usage() {
  sed -n '3,58p' "$SCRIPT_PATH" >&2
  exit 2
}

ACTION=""
SKILL=""
CONTAINER=""
SESSION_ID="${POLARIS_SKILL_BOUNDARY_SESSION_ID:-}"
REPO=""
TASK_MD=""
# DP-273 Wall B: --check + --cleanup-stale-on-pass removes the baseline once the
# refinement handoff boundary check PASSes (EC4 defense-in-depth). Opt-in so
# ordinary in-session re-checks keep their baseline.
CLEANUP_STALE_ON_PASS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill) SKILL="${2:-}"; shift 2 ;;
    --start) ACTION="start"; shift ;;
    --check) ACTION="check"; shift ;;
    --source-container) CONTAINER="${2:-}"; shift 2 ;;
    --session-id) SESSION_ID="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --cleanup-stale-on-pass) CLEANUP_STALE_ON_PASS=1; shift ;;
    --help|-h) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

if [[ -z "$SKILL" || -z "$ACTION" || -z "$CONTAINER" ]]; then
  echo "ERROR: --skill, --start|--check and --source-container are required" >&2
  usage
fi

case "$SKILL" in
  refinement|breakdown|engineering|verify-AC) ;;
  *)
    echo "ERROR: unsupported --skill: $SKILL (expected refinement|breakdown|engineering|verify-AC)" >&2
    exit 2
    ;;
esac

if [[ ! -d "$CONTAINER" ]]; then
  echo "ERROR: --source-container is not a directory: $CONTAINER" >&2
  exit 2
fi

if [[ -z "$REPO" ]]; then
  REPO="$(git -C "$CONTAINER" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$REPO" ]]; then
  echo "ERROR: could not resolve git repo for $CONTAINER" >&2
  exit 2
fi

# Resolve symlinks so /tmp -> /private/tmp etc don't confuse relpath.
CONTAINER_REAL="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$CONTAINER")"
REPO_REAL="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$REPO")"
REL_CONTAINER="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$CONTAINER_REAL" "$REPO_REAL")"
REL_CONTAINER="${REL_CONTAINER%/}"

RUNTIME_DIR="${POLARIS_RUNTIME_DIR:-$REPO_REAL/.polaris/runtime}"
BASELINE_DIR="$RUNTIME_DIR/skill-workflow-boundary"
mkdir -p "$BASELINE_DIR"

if [[ -z "$SESSION_ID" ]]; then
  # Session id is stable across the lifetime of one skill + container pair, so
  # --start and --check inside the same session resolve to the same baseline
  # path even when HEAD advances between them (e.g. /auto-pass commits the
  # refinement output before transitioning to breakdown). Distinct sessions
  # for the same skill must pass --session-id explicitly.
  SESSION_ID="$(printf '%s|%s' "$SKILL" "$CONTAINER_REAL" \
    | python3 -c "import hashlib,sys; print(hashlib.sha1(sys.stdin.read().encode()).hexdigest()[:16])")"
fi

BASELINE_PATH="$BASELINE_DIR/${SKILL}-${SESSION_ID}.json"

# Description: Emit a JSON object mapping each task/* delivery branch name to
#              its current commit sha. Throwaway verify-integration-* branches
#              are excluded so their create/delete lifecycle is never read as a
#              delivery branch ref shift (DP-303 S2 / EC2 / R2).
# Args:        none (reads refs from $REPO_REAL via git for-each-ref)
# Side effects: none (read-only); prints JSON object to stdout
snapshot_task_refs() {
  git -C "$REPO_REAL" for-each-ref --format='%(refname:short) %(objectname)' \
    'refs/heads/task/*' 2>/dev/null \
    | python3 -c "
import json, sys
refs = {}
for line in sys.stdin:
    line = line.rstrip('\n')
    if not line:
        continue
    parts = line.split(' ', 1)
    if len(parts) != 2:
        continue
    name, sha = parts
    # Throwaway verify-AC integration branches are NOT delivery branches.
    if name.startswith('verify-integration-'):
        continue
    refs[name] = sha
print(json.dumps(refs, sort_keys=True))
"
}

emit_engineering_scope() {
  local task_md="$1"
  if [[ ! -f "$task_md" ]]; then
    echo "ERROR: --task-md not found: $task_md" >&2
    exit 2
  fi
  python3 - "$task_md" <<'PY'
import re, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()
m = re.search(r"^## Allowed Files\s*\n(.*?)(?=^## |\Z)", text, re.DOTALL | re.MULTILINE)
if not m:
    sys.exit(0)
for line in m.group(1).splitlines():
    line = line.strip()
    if not line.startswith("- "):
        continue
    item = line[2:].strip().strip("`").strip()
    if item:
        print(item)
PY
}

emit_recursive() {
  local prefix="$1"
  printf '%s\n' "$prefix/*"
  local d
  for d in 1 2 3 4 5 6 7 8; do
    local stars=""
    local i
    for ((i=0; i<d; i++)); do
      stars+="*/"
    done
    printf '%s%s*\n' "$prefix/" "$stars"
  done
}

emit_scope_patterns() {
  local container="$REL_CONTAINER"
  case "$SKILL" in
    refinement)
      printf '%s\n' "${container}/refinement.md"
      printf '%s\n' "${container}/refinement.json"
      printf '%s\n' "${container}/index.md"
      printf '%s\n' "${container}/plan.md"
      emit_recursive "${container}/artifacts"
      emit_recursive "${container}/jira-comments"
      emit_recursive "${container}/refinement-inbox"
      ;;
    breakdown)
      printf '%s\n' "${container}/tasks/T*.md"
      printf '%s\n' "${container}/tasks/V*.md"
      printf '%s\n' "${container}/tasks/T*/index.md"
      printf '%s\n' "${container}/tasks/V*/index.md"
      emit_recursive "${container}/tasks"
      emit_recursive "${container}/refinement-inbox"
      ;;
    engineering)
      if [[ -z "$TASK_MD" ]]; then
        echo "ERROR: --task-md is required for engineering scope" >&2
        exit 2
      fi
      emit_engineering_scope "$TASK_MD"
      ;;
    verify-AC)
      emit_recursive "${container}/verification"
      printf '%s\n' "${container}/tasks/V*.md"
      printf '%s\n' "${container}/tasks/V*/index.md"
      emit_recursive "${container}/tasks"
      emit_recursive "${container}/refinement-inbox"
      ;;
  esac
}

action_start() {
  local head_sha
  head_sha="$(git -C "$REPO_REAL" rev-parse HEAD 2>/dev/null || echo "")"
  local dirty_list
  dirty_list="$(git -C "$REPO_REAL" status --porcelain=v1 -z --untracked-files=all 2>/dev/null \
    | python3 -c "
import json, sys
data = sys.stdin.buffer.read().decode('utf-8', errors='replace')
files = []
for entry in data.split('\0'):
    if not entry or len(entry) < 4:
        continue
    files.append(entry[3:])
print(json.dumps(files))
")"
  local task_refs_json
  task_refs_json="$(snapshot_task_refs)"
  python3 - "$BASELINE_PATH" "$SKILL" "$SESSION_ID" "$REL_CONTAINER" "$head_sha" "$dirty_list" "$TASK_MD" "$task_refs_json" <<'PY'
import json, os, sys
out_path, skill, session_id, rel_container, head_sha, dirty_json, task_md, task_refs_json = sys.argv[1:]
payload = {
    "skill": skill,
    "session_id": session_id,
    "rel_container": rel_container,
    "head_sha": head_sha,
    "dirty_at_start": json.loads(dirty_json),
    "task_md": task_md,
    "task_refs_at_start": json.loads(task_refs_json),
}
tmp = out_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)
os.replace(tmp, out_path)
PY
  echo "PASS: skill-workflow-boundary baseline written: $BASELINE_PATH" >&2
  echo "$BASELINE_PATH"
}

action_check() {
  if [[ ! -f "$BASELINE_PATH" ]]; then
    cat >&2 <<EOF
POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:${SKILL}
  - no baseline at $BASELINE_PATH; --start was not called for this session.
EOF
    exit 1
  fi
  local baseline_head
  baseline_head="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['head_sha'])" "$BASELINE_PATH")"
  local carve_json
  carve_json="$(python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1]))['dirty_at_start']))" "$BASELINE_PATH")"

  # DP-303 S2: task/* delivery branch ref-shift detection (verify-AC only).
  # verify-AC umbrella integration must not check out / advance / delete any
  # task/* delivery branch ref — it runs on a throwaway verify-integration-*
  # branch instead. Compare the current task/* ref snapshot against the
  # baseline and flag any delivery branch ref that was MOVED to a different
  # commit or REMOVED during the session (the precise forbidden mutation).
  #
  # Scope decisions:
  #   - Only verify-AC is checked: engineering legitimately creates/advances a
  #     task/* delivery branch, so the ref-shift guard does not apply to it.
  #   - Only baseline refs that moved/were removed are flagged. A newly-created
  #     task/* ref is NOT flagged, because in a shared repo unrelated concurrent
  #     sessions create task/* branches and those are not this session's
  #     mutation. The throwaway verify-integration-* branch verify-AC itself
  #     creates is already excluded by snapshot_task_refs (AC-NEG3).
  if [[ "$SKILL" == "verify-AC" ]]; then
  local baseline_task_refs_json current_task_refs_json
  baseline_task_refs_json="$(python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get('task_refs_at_start', {})))" "$BASELINE_PATH")"
  current_task_refs_json="$(snapshot_task_refs)"
  python3 - "$SKILL" "$REL_CONTAINER" "$baseline_task_refs_json" "$current_task_refs_json" <<'PY'
import json
import sys

skill, rel_container, baseline_json, current_json = sys.argv[1:]

baseline = json.loads(baseline_json)
current = json.loads(current_json)

shifts = []
# Only inspect delivery branches that existed at session start. A moved or
# removed baseline ref is the forbidden verify-AC mutation; newly created refs
# are excluded as concurrent-session noise.
for name in sorted(baseline):
    before = baseline.get(name)
    after = current.get(name)
    if before == after:
        continue
    if after is None:
        shifts.append(f"removed: {name} (was {before})")
    else:
        shifts.append(f"moved: {name} {before} -> {after}")

if shifts:
    print(f"POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:{skill}", file=sys.stderr)
    print(f"  skill={skill} container={rel_container}", file=sys.stderr)
    print("  task/* delivery branch ref shift detected during the skill "
          "session (use a throwaway verify-integration-* branch instead):",
          file=sys.stderr)
    for s in shifts:
        print(f"  - {s}", file=sys.stderr)
    print("  (POLARIS_LANGUAGE_POLICY_BYPASS / POLARIS_SKILL_BOUNDARY_BYPASS env "
          "are ignored by this gate.)", file=sys.stderr)
    sys.exit(1)
PY
  fi

  local committed_changes=""
  if [[ -n "$baseline_head" ]]; then
    committed_changes="$(git -C "$REPO_REAL" diff --name-only "$baseline_head" HEAD 2>/dev/null || true)"
  fi
  local current_dirty=""
  current_dirty="$(git -C "$REPO_REAL" status --porcelain=v1 -z --untracked-files=all 2>/dev/null \
    | python3 -c "
import sys
data = sys.stdin.buffer.read().decode('utf-8', errors='replace')
for entry in data.split('\0'):
    if not entry or len(entry) < 4:
        continue
    print(entry[3:])
")"

  local scope_patterns
  scope_patterns="$(emit_scope_patterns)"

  python3 - "$SKILL" "$REL_CONTAINER" "$carve_json" "$scope_patterns" "$committed_changes" "$current_dirty" <<'PY'
import fnmatch
import json
import sys

skill, rel_container, carve_json, scope_patterns_text, committed_changes, current_dirty = sys.argv[1:]

carve = set(json.loads(carve_json))
scope_patterns = [p for p in scope_patterns_text.splitlines() if p.strip()]

# Framework runtime / git internal paths are never source mutations.
RUNTIME_PREFIXES = (".polaris/", ".git/")
RUNTIME_DIRS = (".polaris", ".git")

changed = set()
for blob in (committed_changes, current_dirty):
    for line in blob.splitlines():
        line = line.strip()
        if not line:
            continue
        if line in RUNTIME_DIRS:
            continue
        if any(line.startswith(p) for p in RUNTIME_PREFIXES):
            continue
        changed.add(line)

remaining = sorted(p for p in changed if p not in carve)

def matches_any(path, patterns):
    for pat in patterns:
        if fnmatch.fnmatchcase(path, pat):
            return True
    return False

violations = [p for p in remaining if not matches_any(p, scope_patterns)]

if violations:
    print(f"POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:{skill}", file=sys.stderr)
    print(f"  skill={skill} container={rel_container}", file=sys.stderr)
    for v in violations:
        print(f"  - out-of-scope mutation: {v}", file=sys.stderr)
    print("  (POLARIS_LANGUAGE_POLICY_BYPASS / POLARIS_SKILL_BOUNDARY_BYPASS env "
          "are ignored by this gate.)", file=sys.stderr)
    sys.exit(1)

print(f"PASS: skill-workflow-boundary respected for {skill} ({rel_container})")
PY
  # Defense-in-depth (DP-273 Wall B, EC4): when explicitly asked to retire a
  # stale baseline on PASS, remove it so a later release-tail closeout cannot
  # re-trip on a left-over refinement baseline against a delivery diff. This is
  # opt-in (--cleanup-stale-on-pass) so ordinary in-session re-checks keep their
  # baseline; cleanup is bound to the PASS path only (never before the check
  # succeeds).
  if [[ "$CLEANUP_STALE_ON_PASS" -eq 1 && -f "$BASELINE_PATH" ]]; then
    rm -f "$BASELINE_PATH"
  fi
}

case "$ACTION" in
  start) action_start ;;
  check) action_check ;;
  *) echo "ERROR: --start or --check required" >&2; exit 2 ;;
esac
