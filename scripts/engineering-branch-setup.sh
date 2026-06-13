#!/usr/bin/env bash
# scripts/engineering-branch-setup.sh — DP-032 Wave γ D4
#
# Atomic branch + worktree creation for engineering first-cut. Replaces the
# multi-step LLM-driven flow (read base → create-branch.sh → manual worktree)
# with a single deterministic script. Eliminates first-cut pre-dev rebase
# (new branch from origin/{base} HEAD is already at tip — no rebase needed).
#
# Contract:
#   engineering-branch-setup.sh <task_md> [--repo-base DIR]
#
# Steps:
#   1. parse-task-md.sh → task_jira_key, summary, resolved_base, repo
#   2. Verify resolved_base exists on origin (git ls-remote)
#   3. git fetch origin {resolved_base}
#   4. Resolve branch name from task.md `Task branch` contract
#   5. Duplicate guard: refuse same-ticket local/remote branches and stale worktree paths
#   6. git branch {resolved_task_branch} origin/{resolved_base}
#   7. Derive worktree path: {repo_base}/.worktrees/{repo}-engineering-{KEY}
#   8. git worktree add {worktree_path} {resolved_task_branch}
#   9. stdout last line: absolute worktree path (for caller consumption)
#
# Exit codes:
#   0  Success — worktree created, path on stdout
#   1  Recoverable error — branch already exists (prints existing branch info)
#   2  Fatal error — base not found / parse failure / usage error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"
CASCADE_REBASE_CHAIN="$SCRIPT_DIR/cascade-rebase-chain.sh"
RESOLVE_TASK_BRANCH="$SCRIPT_DIR/resolve-task-branch.sh"
VALIDATE_TASK_MD="$SCRIPT_DIR/validate-task-md.sh"
VALIDATE_TASK_MD_DEPS="$SCRIPT_DIR/validate-task-md-deps.sh"
VALIDATE_BREAKDOWN_READY="$SCRIPT_DIR/validate-breakdown-ready.sh"
RESOLVE_TASK_BASE="$SCRIPT_DIR/resolve-task-base.sh"
WORKTREE_CLEANUP="$SCRIPT_DIR/engineering-worktree-cleanup.sh"

usage() {
  cat <<EOF >&2
Usage:
  $(basename "$0") <task_md> [--repo-base DIR] [--auto-stash]
  $(basename "$0") --aggregate-release --source DP-NNN --version vX.Y.Z \\
      --task-md <path> [--task-md <path> ...] [--repo-base DIR]

Default mode creates a task branch + worktree atomically from
origin/{resolved_base} HEAD.

Aggregate-release mode (DP-230 D16) creates a bundle branch named
"bundle-DP-NNN-vX.Y.Z" from origin/main and writes bundle_branch_alias into
each --task-md frontmatter so framework-release-closeout can resolve per-task
head SHAs against the bundle PR identity (no per-task summary slug).

Options:
  --repo-base DIR        Base directory for .worktrees/ (default: git toplevel)
  --auto-stash           Stash unrelated dirty files before dispatch; overlap
                         with Allowed Files still blocks.
  --aggregate-release    Switch to bundle PR identity mode.
  --source DP-NNN        Source DP id; required with --aggregate-release.
  --version vX.Y.Z       Release version tag; required with --aggregate-release.
  --task-md PATH         Task work order (repeatable in aggregate-release mode).

Exit:  0 = success, 1 = branch exists, 2 = fatal error.
EOF
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Sanitize summary into a branch-safe slug (kebab-case, max 40 chars)
slugify() {
  local input="$1"
  echo "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//;s/-$//' \
    | cut -c1-40
}

worktree_for_branch() {
  local branch="$1"
  git worktree list --porcelain 2>/dev/null | awk -v branch="refs/heads/${branch}" '
    /^worktree / { wt = substr($0, 10); next }
    /^branch / {
      if (substr($0, 8) == branch) {
        print wt
      }
    }
  '
}

maybe_auto_stash_dirty_main() {
  local repo="$1"
  local task_json="$2"
  local dirty=""
  local overlap=""
  local stash_ref=""

  [[ "$AUTO_STASH" -eq 1 ]] || return 0
  dirty="$(git -C "$repo" -c core.quotePath=false status --porcelain --untracked-files=all | awk '{print $2}' | sed '/^$/d' || true)"
  [[ -n "$dirty" ]] || return 0

  overlap="$(printf '%s\n' "$dirty" | python3 -c '
import fnmatch
import json
import sys

task = json.loads(sys.argv[1])
allowed = [str(item).strip("`") for item in (task.get("allowed_files") or [])]
for raw in sys.stdin:
    path = raw.strip()
    if path and any(fnmatch.fnmatch(path, pattern) for pattern in allowed):
        print(path)
' "$task_json")"
  if [[ -n "$overlap" ]]; then
    echo "ERROR: dirty files overlap task Allowed Files; refusing auto-stash" >&2
    printf '%s\n' "$overlap" >&2
    exit 2
  fi

  git -C "$repo" stash push -u -m "polaris-auto-stash ${TASK_KEY}" -- $(printf '%s\n' "$dirty") >/dev/null || {
    echo "ERROR: auto-stash failed" >&2
    exit 2
  }
  stash_ref="$(git -C "$repo" stash list | sed -n '1s/:.*//p')"
  echo "✓ Auto-stashed unrelated dirty files: ${stash_ref:-stash@{0}}" >&2

  if [[ -n "${AUTO_PASS_LEDGER_PATH:-}" && -f "$AUTO_PASS_LEDGER_PATH" ]]; then
    python3 - "$AUTO_PASS_LEDGER_PATH" "${stash_ref:-stash@{0}}" "$TASK_KEY" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["pre_dispatch_stash"] = {
    "stash_ref": sys.argv[2],
    "work_item_id": sys.argv[3],
    "created_at": datetime.now(timezone.utc).isoformat(),
}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  fi
}

trust_mise_in_worktree() {
  local worktree="$1"
  command -v mise >/dev/null 2>&1 || return 0
  [[ -f "$worktree/mise.toml" || -f "$worktree/.mise.toml" ]] || return 0
  (cd "$worktree" && mise trust --quiet >/dev/null 2>&1) || {
    echo "WARN: mise trust --quiet failed in $worktree; continuing without trust" >&2
  }
}

task_collection_dir() {
  local task_md="$1"
  local dir
  dir="$(dirname "$task_md")"
  if [[ "$(basename "$dir")" =~ ^[TV][0-9]+[a-z]*$ ]]; then
    dir="$(dirname "$dir")"
  fi
  if [[ "$(basename "$dir")" == "pr-release" ]]; then
    dir="$(dirname "$dir")"
  fi
  printf '%s\n' "$dir"
}

is_canonical_pipeline_task() {
  local task_md="$1"
  [[ "$task_md" == *"/docs-manager/src/content/docs/specs/"* ]] || return 1
  grep -q '^> Source: .* | Task: .* | JIRA: .* | Repo: ' "$task_md"
}

run_readiness_pack() {
  local task_md="$1"
  local tasks_dir=""

  if ! is_canonical_pipeline_task "$task_md"; then
    echo "ℹ Readiness pack skipped for non-canonical selftest/legacy task: $task_md" >&2
    return 0
  fi

  tasks_dir="$(task_collection_dir "$task_md")"
  echo "ℹ Running engineering readiness pack before branch setup..." >&2

  bash "$VALIDATE_TASK_MD" "$task_md" >/dev/null || {
    echo "ERROR: readiness pack failed: validate-task-md.sh" >&2
    return 1
  }
  bash "$VALIDATE_TASK_MD_DEPS" "$tasks_dir" >/dev/null || {
    echo "ERROR: readiness pack failed: validate-task-md-deps.sh" >&2
    return 1
  }
  bash "$VALIDATE_BREAKDOWN_READY" "$task_md" >/dev/null || {
    echo "ERROR: readiness pack failed: validate-breakdown-ready.sh" >&2
    return 1
  }
  bash "$RESOLVE_TASK_BASE" "$task_md" >/dev/null || {
    echo "ERROR: readiness pack failed: resolve-task-base.sh" >&2
    return 1
  }
  bash "$RESOLVE_TASK_BRANCH" "$task_md" >/dev/null || {
    echo "ERROR: readiness pack failed: resolve-task-branch.sh" >&2
    return 1
  }
}

write_baseline_snapshot() {
  local repo="$1"
  local task_md="$2"
  local head_sha="$3"
  local evidence_repo="$repo"
  local git_file=""
  local git_dir=""
  local common_dir=""
  local out_dir=""
  local tmp=""

  git_file="$repo/.git"
  if [[ -f "$git_file" ]]; then
    git_dir="$(sed -n 's/^gitdir: //p' "$git_file" | head -n 1)"
    if [[ -n "$git_dir" ]]; then
      git_dir="$(cd "$repo" && cd "$(dirname "$git_dir")" && pwd)/$(basename "$git_dir")"
      common_dir="$(cd "$(dirname "$git_dir")/.." 2>/dev/null && pwd || true)"
      if [[ -n "$common_dir" && "$(basename "$common_dir")" == ".git" ]]; then
        evidence_repo="$(dirname "$common_dir")"
      fi
    fi
  fi

  out_dir="$evidence_repo/.polaris/evidence/baseline-snapshot"
  mkdir -p "$out_dir"
  tmp="$(mktemp -t polaris-baseline-snapshot.XXXXXX.json)"
  python3 - "$PARSE_TASK_MD" "$task_md" "$head_sha" "$tmp" "$out_dir" <<'PY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

parser, task_md, head_sha, tmp_path, out_dir = sys.argv[1:6]
proc = subprocess.run(
    ["bash", parser, task_md, "--no-resolve"],
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    check=True,
)
data = json.loads(proc.stdout)
identity = data.get("identity") or {}
op = data.get("operational_context") or {}
task_id = identity.get("work_item_id") or op.get("task_id") or op.get("task_jira_key")
if not task_id:
    raise SystemExit("missing task identity for baseline snapshot")

def digest(value):
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()

planner_owned = {
    "verify_command": data.get("verify_command") or "",
    "depends_on": (data.get("frontmatter") or {}).get("depends_on") or [],
    "base_branch": op.get("base_branch") or "",
    "allowed_files": data.get("allowed_files") or [],
}
snapshot = {
    "schema_version": 1,
    "writer": "engineering-branch-setup.sh",
    "task_id": task_id,
    "task_md": str(Path(task_md).resolve()),
    "head_sha": head_sha,
    "planner_owned": planner_owned,
    "hashes": {
        "verify_command_sha256": digest(planner_owned["verify_command"]),
        "depends_on_sha256": digest(planner_owned["depends_on"]),
        "base_branch_sha256": digest(planner_owned["base_branch"]),
        "allowed_files_sha256": digest(planner_owned["allowed_files"]),
    },
    "task_artifact_sha256": hashlib.sha256(Path(task_md).read_bytes()).hexdigest(),
}
tmp = Path(tmp_path)
tmp.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
target = Path(out_dir) / f"{task_id}-{head_sha}.json"
tmp.replace(target)
print(target)
PY
  rm -f "$tmp"
}

task_branch_refs() {
  local task_key="$1"
  git for-each-ref --format='%(refname:short)' \
    "refs/heads/task/${task_key}-*" \
    "refs/remotes/origin/task/${task_key}-*" 2>/dev/null | sort -u
}

emit_duplicate_branch_error() {
  local task_key="$1"
  local branch_name="$2"
  local existing_refs="$3"

  echo "ERROR: existing task branch detected for ${task_key}; refusing to open a duplicate engineering branch." >&2
  echo "  Expected branch: ${branch_name}" >&2
  echo "  Existing refs:" >&2
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    local branch="${ref#origin/}"
    local wt=""
    wt="$(worktree_for_branch "$branch")"
    if [[ -n "$wt" ]]; then
      echo "    - ${ref} (worktree: ${wt})" >&2
    else
      echo "    - ${ref}" >&2
    fi
  done <<<"$existing_refs"
  echo "  → Existing branches are not reused for first-cut. Switch to revision mode if it has a PR, or clean the stale branch before retrying." >&2
}

cleanup_existing_worktree() {
  local repo="$1"
  local task_key="$2"
  local worktree_path="$3"

  if [[ ! -f "$WORKTREE_CLEANUP" ]]; then
    echo "ERROR: cleanup helper missing: $WORKTREE_CLEANUP" >&2
    return 2
  fi

  echo "ℹ Cleaning existing worktree before creating a fresh one: $worktree_path" >&2
  bash "$WORKTREE_CLEANUP" --repo "$repo" --worktree "$worktree_path" --identity "$task_key" --apply >/dev/null || {
    echo "ERROR: existing worktree is unsafe or could not be cleaned: $worktree_path" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# Selftest
# ---------------------------------------------------------------------------
if [[ "${ENGINEERING_BRANCH_SETUP_SELFTEST:-}" == "1" ]]; then
  PASS=0; FAIL=0; TOTAL=0
  _assert() {
    TOTAL=$((TOTAL + 1))
    if [[ "$1" == "$2" ]]; then
      PASS=$((PASS + 1))
    else
      FAIL=$((FAIL + 1))
      echo "FAIL [$TOTAL]: expected='$2' got='$1' — $3" >&2
    fi
  }

  TMPDIR_ST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_ST"' EXIT

  # Setup: bare remote + local clone
  REMOTE="$TMPDIR_ST/remote.git"
  LOCAL="$TMPDIR_ST/local"
  git init --bare "$REMOTE" >/dev/null 2>&1
  git clone "$REMOTE" "$LOCAL" >/dev/null 2>&1
  (
    cd "$LOCAL"
    git checkout -b main >/dev/null 2>&1
    echo "init" > file.txt
    git add file.txt && git commit -m "init" >/dev/null 2>&1
    git push -u origin main >/dev/null 2>&1
  )

  TASK_MD="$TMPDIR_ST/task.md"
  cat > "$TASK_MD" <<'TASK'
# T1 — Fix login validation

> Epic: PROJ-100 | JIRA: PROJ-101 | Repo: my-app

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | PROJ-101 |
| Parent Epic | PROJ-100 |
| Base branch | main |
| Task branch | task/PROJ-101-contract-branch-name |
| Depends on | — |

## Test Command

echo ok

## Allowed Files

- `src/**`
TASK

  # Unset selftest env to avoid infinite recursion when calling self
  _run() { env -u ENGINEERING_BRANCH_SETUP_SELFTEST POLARIS_SKIP_BASELINE_SNAPSHOT=1 bash "$SCRIPT_DIR/engineering-branch-setup.sh" "$@"; }

  # T1: successful branch + worktree creation
  out=$(cd "$LOCAL" && _run "$TASK_MD" --repo-base "$TMPDIR_ST" 2>/dev/null)
  rc=$?
  _assert "$rc" "0" "T1: should succeed"
  # Last line should be a worktree path
  wt_path=$(echo "$out" | tail -1)
  [[ -d "$wt_path" ]] && t="exists" || t="missing"
  _assert "$t" "exists" "T1: worktree directory should exist"
  # Branch should match task.md Task branch even when the summary slug differs.
  (cd "$LOCAL" && git show-ref --verify --quiet refs/heads/task/PROJ-101-contract-branch-name) && t="found" || t="missing"
  _assert "$t" "found" "T1: task.md Task branch should exist"

  # T2: no reuse — running again should clean the old worktree and create a fresh one.
  old_inode=$(python3 - "$wt_path" <<'PY'
import os, sys
print(os.stat(sys.argv[1]).st_ino)
PY
)
  out=$(cd "$LOCAL" && _run "$TASK_MD" --repo-base "$TMPDIR_ST" 2>/dev/null)
  rc=$?
  _assert "$rc" "0" "T2: re-run should create a fresh worktree"
  wt_path=$(echo "$out" | tail -1)
  new_inode=$(python3 - "$wt_path" <<'PY'
import os, sys
print(os.stat(sys.argv[1]).st_ino)
PY
)
  [[ "$old_inode" != "$new_inode" ]] && t="fresh" || t="reused"
  _assert "$t" "fresh" "T2: re-run must not reuse the previous worktree directory"

  # T3: guard — same ticket with a different existing branch should block
  git -C "$LOCAL" branch task/PROJ-101-other-attempt main >/dev/null 2>&1
  TASK_MD_DUP="$TMPDIR_ST/task-duplicate.md"
  sed 's/Fix login validation/Another implementation/' "$TASK_MD" > "$TASK_MD_DUP"
  out=$(cd "$LOCAL" && _run "$TASK_MD_DUP" --repo-base "$TMPDIR_ST" 2>/dev/null)
  rc=$?
  _assert "$rc" "1" "T3: duplicate same-ticket branch should exit 1"

  # T4: guard — stale worktree path should block before creating a branch
  TASK_MD_WT="$TMPDIR_ST/task-worktree-path.md"
  sed 's/PROJ-101/PROJ-102/g; s/Fix login validation/Second task/' "$TASK_MD" > "$TASK_MD_WT"
  mkdir -p "$TMPDIR_ST/.worktrees/my-app-engineering-PROJ-102"
  out=$(cd "$LOCAL" && _run "$TASK_MD_WT" --repo-base "$TMPDIR_ST" 2>/dev/null)
  rc=$?
  _assert "$rc" "1" "T4: stale worktree path should exit 1"
  (cd "$LOCAL" && git show-ref --verify --quiet refs/heads/task/PROJ-102-second-task) && t="created" || t="missing"
  _assert "$t" "missing" "T4: stale worktree path must not leave a new branch"

  # T5: error — nonexistent task_md
  out=$(cd "$LOCAL" && _run "/nonexistent.md" 2>/dev/null)
  rc=$?
  _assert "$rc" "2" "T5: missing task_md should exit 2"

  # T6: error — no args
  out=$(env -u ENGINEERING_BRANCH_SETUP_SELFTEST bash "$SCRIPT_DIR/engineering-branch-setup.sh" 2>/dev/null)
  rc=$?
  _assert "$rc" "2" "T6: no args should exit 2"

  # T7: slugify tests
  s=$(slugify "Fix Login Validation Bug")
  _assert "$s" "fix-login-validation-bug" "T7a: slugify basic"
  s=$(slugify "JP 旅遊 DX Main-Page")
  _assert "$s" "jp-dx-main-page" "T7b: slugify non-ascii → collapsed dashes"

  # Cleanup worktree
  (cd "$LOCAL" && git worktree remove "$wt_path" --force >/dev/null 2>&1) || true

  echo ""
  echo "engineering-branch-setup.sh selftest: $PASS/$TOTAL passed, $FAIL failed"
  [[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
fi

# ---------------------------------------------------------------------------
# Aggregate-release helpers (DP-230 D16)
# ---------------------------------------------------------------------------

# Write `bundle_branch_alias: <value>` into a task.md YAML frontmatter block.
# - If the file has no frontmatter, prepend a fresh frontmatter block.
# - If bundle_branch_alias already exists, replace its value.
# - Otherwise append the key inside the existing block.
write_bundle_branch_alias() {
  local task_md="$1"
  local alias="$2"
  python3 - "$task_md" "$alias" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
alias = sys.argv[2]
content = path.read_text(encoding="utf-8")
lines = content.split("\n")

if not lines or lines[0] != "---":
    new = ["---", f"bundle_branch_alias: {alias}", "---", ""] + lines
    path.write_text("\n".join(new), encoding="utf-8")
    raise SystemExit(0)

try:
    close = lines.index("---", 1)
except ValueError:
    print(f"ERROR: unclosed frontmatter in {path}", file=sys.stderr)
    sys.exit(2)

fm = lines[1:close]
replaced = False
for i, line in enumerate(fm):
    if re.match(r"^bundle_branch_alias\s*:", line):
        fm[i] = f"bundle_branch_alias: {alias}"
        replaced = True
        break
if not replaced:
    fm.append(f"bundle_branch_alias: {alias}")

new = ["---", *fm, "---", *lines[close + 1:]]
path.write_text("\n".join(new), encoding="utf-8")
PY
}

run_aggregate_release() {
  local source_id="$1"
  local version_tag="$2"
  local repo_base="$3"
  shift 3
  local task_mds=()
  if [[ "$#" -gt 0 ]]; then
    task_mds=("$@")
  fi

  # Contract validation: source id pattern + version pattern.
  if [[ ! "$source_id" =~ ^DP-[0-9]+$ ]]; then
    echo "ERROR: --source must match DP-NNN (got: $source_id)" >&2
    return 2
  fi
  if [[ ! "$version_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: --version must match vX.Y.Z (got: $version_tag)" >&2
    return 2
  fi
  local abs_task_mds=()
  local task_md
  if [[ "${#task_mds[@]}" -gt 0 ]]; then
    for task_md in "${task_mds[@]}"; do
      if [[ ! -f "$task_md" ]]; then
        echo "ERROR: --task-md not found: $task_md" >&2
        return 2
      fi
      abs_task_mds+=("$(cd "$(dirname "$task_md")" && pwd)/$(basename "$task_md")")
    done
  fi

  local repo_toplevel
  repo_toplevel="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  if [[ -z "$repo_base" ]]; then
    repo_base="$repo_toplevel"
  fi

  # Resolve bundle branch identity from --source + --version only. The bundle
  # branch is intentionally NOT derived from any task summary slug; that legacy
  # path was the DP-226 P11 regression (per-task summary leaks into bundle PR
  # identity). Single canonical name: bundle-DP-NNN-vX.Y.Z.
  local branch_name="bundle-${source_id}-${version_tag}"

  # Verify main exists on origin.
  echo "ℹ Fetching origin/main for aggregate-release base..." >&2
  if ! git ls-remote --exit-code origin "refs/heads/main" >/dev/null 2>&1; then
    echo "ERROR: aggregate-release requires origin/main to exist" >&2
    return 2
  fi
  git fetch origin main >/dev/null 2>&1 || {
    echo "ERROR: git fetch origin main failed" >&2
    return 2
  }

  # Duplicate guard: refuse if branch or remote already exists.
  if git show-ref --verify --quiet "refs/heads/${branch_name}" 2>/dev/null; then
    echo "ERROR: bundle branch already exists locally: ${branch_name}" >&2
    echo "  → Switch to revision mode or clean the stale bundle branch before retrying." >&2
    return 1
  fi
  if git show-ref --verify --quiet "refs/remotes/origin/${branch_name}" 2>/dev/null; then
    echo "ERROR: bundle branch already exists on origin: ${branch_name}" >&2
    return 1
  fi

  # Worktree path derived from bundle identity, not per-task slug.
  local wt_dir="${repo_base}/.worktrees"
  local wt_path="${wt_dir}/polaris-framework-aggregate-release-${source_id}-${version_tag}"
  if [[ -d "$wt_path" ]]; then
    if [[ ! -f "$WORKTREE_CLEANUP" ]]; then
      echo "ERROR: cleanup helper missing: $WORKTREE_CLEANUP" >&2
      return 2
    fi
    bash "$WORKTREE_CLEANUP" --repo "$repo_toplevel" --worktree "$wt_path" --identity "$branch_name" --apply >/dev/null || {
      echo "ERROR: existing aggregate-release worktree could not be cleaned: $wt_path" >&2
      return 1
    }
  fi

  # Create branch + worktree from origin/main HEAD.
  git branch "$branch_name" "origin/main" 2>/dev/null || {
    echo "ERROR: git branch $branch_name origin/main failed" >&2
    return 2
  }
  echo "✓ Created bundle branch: $branch_name" >&2

  mkdir -p "$wt_dir"
  git worktree add "$wt_path" "$branch_name" 2>/dev/null || {
    echo "ERROR: git worktree add failed for $wt_path $branch_name" >&2
    git branch -d "$branch_name" 2>/dev/null || true
    return 2
  }
  echo "✓ Bundle worktree created: $wt_path" >&2
  trust_mise_in_worktree "$wt_path"

  # Write bundle_branch_alias into each task.md frontmatter.
  local t
  if [[ "${#abs_task_mds[@]}" -gt 0 ]]; then
    for t in "${abs_task_mds[@]}"; do
      write_bundle_branch_alias "$t" "$branch_name" || {
        echo "ERROR: failed to write bundle_branch_alias into $t" >&2
        return 2
      }
      echo "✓ Wrote bundle_branch_alias=$branch_name into $t" >&2
    done
  fi

  # Machine-readable last line: bundle worktree path.
  echo "$wt_path"
  return 0
}

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
TASK_MD=""
REPO_BASE=""
AUTO_STASH=0
AGGREGATE_RELEASE=0
AGG_SOURCE_ID=""
AGG_VERSION_TAG=""
AGG_TASK_MDS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-base) REPO_BASE="$2"; shift 2 ;;
    --auto-stash) AUTO_STASH=1; shift ;;
    --aggregate-release) AGGREGATE_RELEASE=1; shift ;;
    --source) AGG_SOURCE_ID="${2:-}"; shift 2 ;;
    --version) AGG_VERSION_TAG="${2:-}"; shift 2 ;;
    --task-md) AGG_TASK_MDS+=("${2:-}"); shift 2 ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "ERROR: unknown option: $1" >&2; usage; exit 2 ;;
    *)
      if [[ -z "$TASK_MD" ]]; then
        TASK_MD="$1"
      else
        echo "ERROR: unexpected argument: $1" >&2; usage; exit 2
      fi
      shift
      ;;
  esac
done

if [[ "$AGGREGATE_RELEASE" -eq 1 ]]; then
  if [[ -n "$TASK_MD" ]]; then
    echo "ERROR: --aggregate-release uses --task-md exclusively; do not pass a positional task.md" >&2
    exit 2
  fi
  if [[ -z "$AGG_SOURCE_ID" || -z "$AGG_VERSION_TAG" ]]; then
    echo "ERROR: --aggregate-release requires --source DP-NNN and --version vX.Y.Z" >&2
    usage
    exit 2
  fi
  if [[ "${#AGG_TASK_MDS[@]}" -gt 0 ]]; then
    run_aggregate_release "$AGG_SOURCE_ID" "$AGG_VERSION_TAG" "$REPO_BASE" "${AGG_TASK_MDS[@]}"
  else
    run_aggregate_release "$AGG_SOURCE_ID" "$AGG_VERSION_TAG" "$REPO_BASE"
  fi
  exit $?
fi

if [[ "${#AGG_TASK_MDS[@]}" -gt 0 || -n "$AGG_SOURCE_ID" || -n "$AGG_VERSION_TAG" ]]; then
  echo "ERROR: --source / --version / --task-md require --aggregate-release" >&2
  exit 2
fi

if [[ -z "$TASK_MD" ]]; then
  usage
  exit 2
fi

if [[ ! -f "$TASK_MD" ]]; then
  echo "ERROR: task_md not found: $TASK_MD" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Step 1: Parse task.md
TASK_JSON=$("$PARSE_TASK_MD" "$TASK_MD" 2>/dev/null)
if [[ $? -ne 0 || -z "$TASK_JSON" ]]; then
  echo "ERROR: parse-task-md.sh failed for $TASK_MD" >&2
  exit 2
fi

TASK_KEY=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); oc=d.get('operational_context',{}); m=d.get('metadata',{}); print(oc.get('task_jira_key') or m.get('jira') or '')" 2>/dev/null)
SUMMARY=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('header',{}).get('summary') or '')" 2>/dev/null)
RESOLVED_BASE=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('resolved_base') or '')" 2>/dev/null)
REPO_NAME=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('metadata',{}).get('repo') or '')" 2>/dev/null)
BRANCH_CHAIN=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('operational_context',{}).get('branch_chain') or '')" 2>/dev/null)
BASE_BRANCH=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('operational_context',{}).get('base_branch') or '')" 2>/dev/null)

if [[ -z "$TASK_KEY" ]]; then
  echo "ERROR: task_jira_key not found in $TASK_MD" >&2
  exit 2
fi
if [[ -z "$RESOLVED_BASE" || "$RESOLVED_BASE" == "null" ]]; then
  echo "ERROR: could not resolve base branch from $TASK_MD" >&2
  exit 2
fi

run_readiness_pack "$TASK_MD" || exit 2
maybe_auto_stash_dirty_main "$(git rev-parse --show-toplevel)" "$TASK_JSON"

# Step 1.5: If breakdown supplied an explicit branch chain, align upstream
# branches before cutting the task branch. The task branch does not exist yet,
# so cascade-rebase-chain skips the missing last link.
if [[ -n "$BRANCH_CHAIN" && -f "$CASCADE_REBASE_CHAIN" ]]; then
  if [[ "$BASE_BRANCH" == task/* && "$RESOLVED_BASE" != "$BASE_BRANCH" ]]; then
    echo "ℹ Stacked base resolved to $RESOLVED_BASE; skipping stale branch-chain cascade for completed upstream." >&2
  else
  echo "ℹ Aligning branch chain before task branch creation..." >&2
  "$CASCADE_REBASE_CHAIN" --repo "$(git rev-parse --show-toplevel)" --task-md "$TASK_MD" --skip-missing-last >/dev/null || {
    echo "ERROR: branch chain rebase failed; resolve upstream branch first." >&2
    exit 2
  }
  fi
fi

# Step 2: Verify resolved_base exists on remote
if ! git ls-remote --exit-code origin "refs/heads/$RESOLVED_BASE" >/dev/null 2>&1; then
  echo "ERROR: base branch '$RESOLVED_BASE' not found on origin." >&2
  echo "  → Run /breakdown to update task.md or verify the base branch exists." >&2
  exit 2
fi

# Step 3: Fetch latest
echo "ℹ Fetching origin/$RESOLVED_BASE..." >&2
git fetch origin "$RESOLVED_BASE" >/dev/null 2>&1 || {
  echo "ERROR: git fetch origin $RESOLVED_BASE failed" >&2
  exit 2
}

# Step 4: Resolve branch name from task.md contract
if [[ ! -x "$RESOLVE_TASK_BRANCH" ]]; then
  echo "ERROR: resolve-task-branch.sh not executable at $RESOLVE_TASK_BRANCH" >&2
  exit 2
fi
BRANCH_NAME="$("$RESOLVE_TASK_BRANCH" "$TASK_MD" 2>/tmp/polaris-resolve-task-branch.err)" || {
  cat /tmp/polaris-resolve-task-branch.err >&2 2>/dev/null || true
  echo "ERROR: failed to resolve task branch from $TASK_MD" >&2
  exit 2
}

# Step 4.5: Derive worktree path before creating any branch. If the path is
# already present, fail before touching refs; otherwise a retry can leave a
# branch behind without a usable worktree.
if [[ -z "$REPO_BASE" ]]; then
  REPO_BASE=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
WT_DIR="${REPO_BASE}/.worktrees"
WT_NAME="${REPO_NAME:-repo}-engineering-${TASK_KEY}"
WT_PATH="${WT_DIR}/${WT_NAME}"

# Step 4.6: Same-ticket duplicate guard. A different slug for the same ticket
# is almost always an accidental second first-cut. Exact local branch reuse is
# handled below; exact remote branch still blocks because first-cut would fork
# from the base branch instead of resuming the existing remote work.
EXISTING_TASK_REFS="$(task_branch_refs "$TASK_KEY")"
DUPLICATE_REFS=""
if [[ -n "$EXISTING_TASK_REFS" ]]; then
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    if [[ "$ref" == "$BRANCH_NAME" ]]; then
      continue
    fi
    DUPLICATE_REFS="${DUPLICATE_REFS}${ref}"$'\n'
  done <<<"$EXISTING_TASK_REFS"
fi

if [[ -n "$DUPLICATE_REFS" ]]; then
  emit_duplicate_branch_error "$TASK_KEY" "$BRANCH_NAME" "$DUPLICATE_REFS"
  exit 1
fi

if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH_NAME" 2>/dev/null; then
  emit_duplicate_branch_error "$TASK_KEY" "$BRANCH_NAME" "origin/$BRANCH_NAME"
  exit 1
fi

EXACT_BRANCH_EXISTS=0
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
  EXACT_BRANCH_EXISTS=1
  echo "ℹ Branch $BRANCH_NAME already exists." >&2
  EXISTING_WT="$(worktree_for_branch "$BRANCH_NAME")"
  if [[ -n "$EXISTING_WT" ]]; then
    cleanup_existing_worktree "$(git rev-parse --show-toplevel)" "$TASK_KEY" "$EXISTING_WT" || exit 1
  fi
  echo "ℹ Branch exists; creating a fresh worktree." >&2
fi

if [[ -d "$WT_PATH" ]]; then
  cleanup_existing_worktree "$(git rev-parse --show-toplevel)" "$TASK_KEY" "$WT_PATH" || exit 1
fi

# Check if branch already exists
if [[ "$EXACT_BRANCH_EXISTS" -eq 0 ]]; then
  # Step 5: Create branch from origin/{resolved_base}.
  # DP-307 D6/AC7: branch creation is local-only (`git branch` + `git worktree
  # add`); this script never pushes a refspec. The remote push happens later via
  # the delivery flow / polaris-pr-create wrapper, which reads HEAD from git
  # rather than interpolating a task-title-derived var into a refspec. Keep it so
  # — covered by lint-bash-variable-utf8-boundary refspec detection.
  git branch "$BRANCH_NAME" "origin/$RESOLVED_BASE" 2>/dev/null || {
    echo "ERROR: git branch $BRANCH_NAME origin/$RESOLVED_BASE failed" >&2
    exit 2
  }
  echo "✓ Created branch: $BRANCH_NAME" >&2
fi

# Step 7: Create worktree
mkdir -p "$WT_DIR"

git worktree add "$WT_PATH" "$BRANCH_NAME" 2>/dev/null || {
  echo "ERROR: git worktree add failed for $WT_PATH $BRANCH_NAME" >&2
  # Cleanup branch if we just created it
  git branch -d "$BRANCH_NAME" 2>/dev/null || true
  exit 2
}

echo "✓ Worktree created: $WT_PATH" >&2
trust_mise_in_worktree "$WT_PATH"

if [[ "${POLARIS_SKIP_BASELINE_SNAPSHOT:-}" != "1" ]]; then
  BASELINE_HEAD_SHA="$(git -C "$WT_PATH" rev-parse HEAD)"
  BASELINE_SNAPSHOT="$(write_baseline_snapshot "$WT_PATH" "$TASK_MD" "$BASELINE_HEAD_SHA")" || {
    echo "ERROR: failed to write planner-owned baseline snapshot" >&2
    exit 2
  }
  echo "✓ Baseline snapshot written: $BASELINE_SNAPSHOT" >&2
fi

# Step 8: Output worktree path (last line = machine-readable)
echo "$WT_PATH"
