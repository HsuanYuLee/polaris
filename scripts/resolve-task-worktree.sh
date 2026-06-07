#!/usr/bin/env bash
# Resolve the active engineering task worktree path for a given source / work item.
#
# Contract (AC33 + DP-294 AC1):
#   - Inputs: --source-id <DP-NNN | JIRA-EPIC-KEY> --work-item-id <Tn | DP-NNN-Tn | EPIC-KEY-Tn>
#   - Canonical delivery-branch resolution covers BOTH delivery modes:
#       * per-task delivery → `task/{TASK_KEY}-*` branch (default), and
#       * bundle delivery   → the `bundle_branch_alias` declared in the work
#         item's task.md frontmatter (aggregate-release mode). When the task.md
#         declares a bundle_branch_alias, the bundle worktree is checked out on
#         that exact branch (NOT a task/ branch), so the resolver matches the
#         worktree whose branch equals the alias.
#   - Looks up `git worktree list --porcelain`.
#   - Single match → print absolute worktree path, exit 0.
#   - Zero matches → print "NONE", exit 0 (caller may decide blocking).
#   - Multiple matches → fail-stop, stderr `POLARIS_DISPATCH_WORKTREE_AMBIGUOUS`, exit 2.
#
# Used by /auto-pass and /verify-AC dispatch to populate envelope `worktree_resolution`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# main-checkout.sh provides resolve_main_checkout (worktree → main checkout);
# specs-root.sh provides resolve_specs_root (canonical specs root SoT). DP-294 T1
# reads the canonical bundle_branch_alias from the work item's task.md, which
# lives in the main checkout's specs tree. specs-root.sh only sources
# main-checkout.sh lazily inside a function, so source it explicitly here to get
# resolve_main_checkout at top level.
# shellcheck source=lib/main-checkout.sh
. "$SCRIPT_DIR/lib/main-checkout.sh"
# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  resolve-task-worktree.sh --source-id <SOURCE_ID> --work-item-id <WORK_ITEM_ID> [--repo <repo_root>] [--format text|json]
  resolve-task-worktree.sh --selftest

Outputs (text format, default):
  - absolute worktree path on single match
  - literal NONE on zero match

Outputs (json format):
  - {"status": "FOUND",     "path": "<abs>", "task_key": "<key>"}
  - {"status": "NONE",      "path": null,    "task_key": "<key>"}
  - status AMBIGUOUS does not emit json; fail-stop on stderr.
EOF
}

SOURCE_ID=""
WORK_ITEM_ID=""
REPO=""
FORMAT="text"
SELFTEST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-id)
      SOURCE_ID="${2:-}"
      shift 2
      ;;
    --work-item-id)
      WORK_ITEM_ID="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --format)
      FORMAT="${2:-text}"
      shift 2
      ;;
    --selftest)
      SELFTEST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Derive canonical task key. The work item id can be either fully-qualified
# (`DP-230-T13` / `EXAMPLE-500-T2`) or short-form (`T13`). If short-form, we
# concatenate with the source id.
derive_task_key() {
  local source_id="$1" work_item_id="$2"
  if [[ -z "$work_item_id" ]]; then
    echo ""
    return 0
  fi
  case "$work_item_id" in
    T[0-9]*|V[0-9]*)
      if [[ -z "$source_id" ]]; then
        echo ""
        return 0
      fi
      printf '%s-%s\n' "$source_id" "$work_item_id"
      ;;
    *)
      printf '%s\n' "$work_item_id"
      ;;
  esac
}

resolve_repo_root() {
  local repo="$1"
  if [[ -n "$repo" ]]; then
    # Resolve worktree → real repo top-level so that callers running inside a
    # worktree still find sibling .worktrees/ entries.
    git -C "$repo" rev-parse --show-toplevel 2>/dev/null || {
      echo "ERROR: --repo not inside a git working tree: $repo" >&2
      return 2
    }
  else
    git rev-parse --show-toplevel 2>/dev/null || {
      echo "ERROR: not inside a git working tree (pass --repo)" >&2
      return 2
    }
  fi
}

# Derive the short work-item id (`T9` / `V1`) used as the tasks/ subdir name,
# from either short-form (`V1`) or fully-qualified (`DP-294-V1`) input.
short_work_item() {
  local wid="$1"
  if [[ "$wid" =~ ([TV][0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "$wid"
  fi
}

# Read `bundle_branch_alias` from a task.md YAML frontmatter block. Reuses the
# SAME awk parse shape that gate-work-source.sh / resolve-task-md-by-branch.sh /
# framework-release-closeout.sh already use, keeping a single source of truth for
# bundle detection — the resolver must NOT introduce a second bundle detector.
# Echoes the alias value (empty when absent).
bundle_branch_alias_for_task() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk '
    /^---$/ { fm++; next }
    fm == 1 && /^bundle_branch_alias:/ {
      sub(/^bundle_branch_alias:[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print
      exit
    }
  ' "$file" 2>/dev/null || true
}

# Locate the work item's task.md under the canonical specs tree of the repo's
# main checkout, covering both DP-backed (design-plans/) and JIRA Epic-backed
# (companies/) sources (source parity). Echoes the path or nothing.
locate_task_md() {
  local source_id="$1" short_item="$2" repo="$3"
  [[ -n "$source_id" && -n "$short_item" ]] || return 0
  local main_co specs_root cand
  main_co="$(resolve_main_checkout "$repo" 2>/dev/null)" || return 0
  specs_root="$(resolve_specs_root "$main_co" 2>/dev/null)" || return 0
  for cand in \
    "$specs_root"/design-plans/"$source_id"-*/tasks/"$short_item"/index.md \
    "$specs_root"/companies/*/"$source_id"/tasks/"$short_item"/index.md; do
    if [[ -f "$cand" ]]; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  return 0
}

# Resolve the delivery branch alias for a work item: the bundle_branch_alias
# from its task.md when bundle-delivered, otherwise empty (per-task delivery).
resolve_delivery_alias() {
  local source_id="$1" work_item_id="$2" repo="$3"
  local short_item task_md
  short_item="$(short_work_item "$work_item_id")"
  task_md="$(locate_task_md "$source_id" "$short_item" "$repo")"
  [[ -n "$task_md" ]] || return 0
  bundle_branch_alias_for_task "$task_md"
}

resolve_task_worktree() {
  local source_id="$1" work_item_id="$2" repo_override="$3" format="$4"
  local task_key
  task_key="$(derive_task_key "$source_id" "$work_item_id")"
  if [[ -z "$task_key" ]]; then
    echo "ERROR: --work-item-id required (and --source-id when short-form Tn)" >&2
    return 2
  fi

  local repo
  repo="$(resolve_repo_root "$repo_override")" || return $?

  # `git worktree list --porcelain` is stable across git versions and yields
  # records separated by blank lines:
  #   worktree <abs path>
  #   HEAD <sha>
  #   branch refs/heads/<name>
  local listing
  listing="$(git -C "$repo" worktree list --porcelain 2>/dev/null)" || {
    echo "ERROR: git worktree list failed in $repo" >&2
    return 2
  }

  # Canonical delivery-branch resolution. When the work item's task.md declares a
  # bundle_branch_alias (aggregate-release / bundle delivery), match the worktree
  # whose branch equals that alias EXACTLY. Otherwise (per-task delivery) match
  # the canonical `task/{task_key}-*` branch shape. The two modes are mutually
  # exclusive per task.md declaration, so there is no cross-mode collision.
  local delivery_alias
  delivery_alias="$(resolve_delivery_alias "$source_id" "$work_item_id" "$repo")"

  local matches
  if [[ -n "$delivery_alias" ]]; then
    # Bundle mode: exact match on refs/heads/<alias>.
    matches="$(printf '%s\n' "$listing" | awk -v alias="$delivery_alias" '
      BEGIN { wt=""; br="" }
      /^worktree /   { if (wt!="" && br!="") emit(); wt=$2; br="" }
      /^branch /     { br=$2 }
      /^$/           { if (wt!="" && br!="") emit(); wt=""; br="" }
      END            { if (wt!="" && br!="") emit() }
      function emit() {
        if (br == "refs/heads/" alias) {
          print wt
        }
      }
    ')"
  else
    # Per-task mode: match `task/{task_key}-*` (canonical task branch shape, see
    # resolve-task-branch.sh). The trailing `-` ensures we do not collide with
    # e.g. `task/DP-230-T1` matching `DP-230-T13`.
    matches="$(printf '%s\n' "$listing" | awk -v key="$task_key" '
      BEGIN { wt=""; br="" }
      /^worktree /   { if (wt!="" && br!="") emit(); wt=$2; br="" }
      /^branch /     { br=$2 }
      /^$/           { if (wt!="" && br!="") emit(); wt=""; br="" }
      END            { if (wt!="" && br!="") emit() }
      function emit() {
        # br looks like refs/heads/task/<task_key>-<slug>
        prefix="refs/heads/task/" key "-"
        if (substr(br, 1, length(prefix)) == prefix) {
          print wt
        }
      }
    ')"
  fi

  local count
  count="$(printf '%s\n' "$matches" | grep -c . || true)"

  if [[ "$count" -gt 1 ]]; then
    echo "POLARIS_DISPATCH_WORKTREE_AMBIGUOUS: multiple worktrees match task_key=$task_key" >&2
    printf '%s\n' "$matches" >&2
    return 2
  fi

  if [[ "$count" -eq 0 ]]; then
    if [[ "$format" == "json" ]]; then
      printf '{"status":"NONE","path":null,"task_key":"%s"}\n' "$task_key"
    else
      echo "NONE"
    fi
    return 0
  fi

  local path
  path="$(printf '%s\n' "$matches" | head -n 1)"

  if [[ "$format" == "json" ]]; then
    printf '{"status":"FOUND","path":"%s","task_key":"%s"}\n' "$path" "$task_key"
  else
    printf '%s\n' "$path"
  fi
  return 0
}

if [[ "$SELFTEST" -eq 1 ]]; then
  echo "resolve-task-worktree.sh: --selftest is a no-op marker; run scripts/selftests/resolve-task-worktree-selftest.sh" >&2
  exit 0
fi

if [[ -z "$WORK_ITEM_ID" ]]; then
  usage
  exit 2
fi

resolve_task_worktree "$SOURCE_ID" "$WORK_ITEM_ID" "$REPO" "$FORMAT"
