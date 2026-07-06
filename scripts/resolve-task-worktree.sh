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

# Locate a task.md in either active tasks/ or completed tasks/pr-release/.
locate_any_task_md() {
  local source_id="$1" short_item="$2" repo="$3"
  [[ -n "$source_id" && -n "$short_item" ]] || return 0
  local main_co specs_root cand
  main_co="$(resolve_main_checkout "$repo" 2>/dev/null)" || return 0
  specs_root="$(resolve_specs_root "$main_co" 2>/dev/null)" || return 0
  for cand in \
    "$specs_root"/design-plans/"$source_id"-*/tasks/"$short_item"/index.md \
    "$specs_root"/design-plans/"$source_id"-*/tasks/pr-release/"$short_item"/index.md \
    "$specs_root"/companies/*/"$source_id"/tasks/"$short_item"/index.md \
    "$specs_root"/companies/*/"$source_id"/tasks/pr-release/"$short_item"/index.md; do
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

frontmatter_depends_on_last_t() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk '
    /^---$/ { fm++; next }
    fm == 1 && /^depends_on:/ {
      line=$0
      gsub(/^depends_on:[[:space:]]*\[/, "", line)
      gsub(/\][[:space:]]*$/, "", line)
      n=split(line, parts, ",")
      for (i=1; i<=n; i++) {
        dep=parts[i]
        gsub(/^[[:space:]"'\''`]+|[[:space:]"'\''`]+$/, "", dep)
        if (dep ~ /-T[0-9]+[a-z]?$/ || dep ~ /^T[0-9]+[a-z]?$/) {
          last=dep
        }
      }
      if (last != "") print last
      exit
    }
  ' "$file" 2>/dev/null || true
}

operational_context_value() {
  local file="$1" field="$2"
  [[ -f "$file" ]] || return 0
  awk -F '|' -v field="$field" '
    $0 ~ /^\|/ {
      key=$2
      val=$3
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      if (key == field) {
        print val
        exit
      }
    }
  ' "$file" 2>/dev/null || true
}

deliverable_head_sha() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk '
    /^deliverable:/ { in_deliverable=1; next }
    in_deliverable && /^[^[:space:]][^:]*:/ { exit }
    in_deliverable && /^[[:space:]]+head_sha:/ {
      sub(/^[[:space:]]+head_sha:[[:space:]]*/, "")
      print
      exit
    }
  ' "$file" 2>/dev/null || true
}

resolve_ref() {
  local repo="$1" ref="$2"
  [[ -n "$ref" ]] || return 1
  git -C "$repo" rev-parse --verify --quiet "$ref^{commit}" \
    || git -C "$repo" rev-parse --verify --quiet "refs/heads/$ref^{commit}" \
    || git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/$ref^{commit}"
}

resolve_v_integration_authority() {
  local source_id="$1" work_item_id="$2" repo="$3"
  local short_item v_task dep dep_short dep_task head base_ref
  short_item="$(short_work_item "$work_item_id")"
  [[ "$short_item" == V* ]] || return 1
  v_task="$(locate_any_task_md "$source_id" "$short_item" "$repo")"
  [[ -n "$v_task" ]] || {
    echo "POLARIS_VERIFY_INTEGRATION_AUTHORITY_MISSING: V task not found for $source_id-$short_item" >&2
    return 1
  }

  dep="$(frontmatter_depends_on_last_t "$v_task")"
  if [[ -n "$dep" ]]; then
    dep_short="$(short_work_item "$dep")"
    dep_task="$(locate_any_task_md "$source_id" "$dep_short" "$repo")"
    if [[ -n "$dep_task" ]]; then
      head="$(deliverable_head_sha "$dep_task")"
      if [[ -n "$head" ]]; then
        printf '%s\n' "$head"
        return 0
      fi
    fi
  fi

  base_ref="$(operational_context_value "$v_task" "Base branch")"
  if [[ -n "$base_ref" ]]; then
    resolve_ref "$repo" "$base_ref" && return 0
  fi

  echo "POLARIS_VERIFY_INTEGRATION_AUTHORITY_MISSING: no predecessor deliverable head or resolvable Base branch for $source_id-$short_item" >&2
  return 1
}

worktree_for_branch() {
  local branch="$1" repo="$2"
  [[ -n "$branch" && -n "$repo" ]] || return 0
  git -C "$repo" worktree list --porcelain 2>/dev/null | awk -v branch="$branch" '
    BEGIN { wt=""; br="" }
    /^worktree /   { if (wt!="" && br!="") emit(); wt=$2; br="" }
    /^branch /     { br=$2 }
    /^$/           { if (wt!="" && br!="") emit(); wt=""; br="" }
    END            { if (wt!="" && br!="") emit() }
    function emit() {
      if (br == "refs/heads/" branch) {
        print wt
      }
    }
  ' || true
}

resolve_or_create_verify_integration_worktree() {
  local source_id="$1" work_item_id="$2" repo="$3"
  local short_item branch wt_path head repo_name
  short_item="$(short_work_item "$work_item_id")"
  [[ "$short_item" == V* ]] || return 1

  branch="verify-integration-${source_id}-${short_item}"
  repo_name="$(basename "$repo")"
  wt_path="$repo/.worktrees/${repo_name}-${branch}"

  local existing
  existing="$(worktree_for_branch "$branch" "$repo")"
  if [[ -n "$existing" ]]; then
    printf '%s\n' "$existing"
    return 0
  fi

  head="$(resolve_v_integration_authority "$source_id" "$work_item_id" "$repo")" || return 1

  if ! git -C "$repo" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
    git -C "$repo" branch "$branch" "$head" || return 1
  fi

  if [[ -e "$wt_path" ]]; then
    echo "POLARIS_VERIFY_INTEGRATION_WORKTREE_BLOCKED: path exists without registered worktree: $wt_path" >&2
    return 2
  fi

  git -C "$repo" worktree add -q "$wt_path" "$branch" || return 1
  printf '%s\n' "$wt_path"
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
    local short_item integration_path
    short_item="$(short_work_item "$work_item_id")"
    if [[ "$short_item" == V* && -z "$delivery_alias" ]]; then
      integration_path="$(resolve_or_create_verify_integration_worktree "$source_id" "$work_item_id" "$repo")" || return $?
      if [[ "$format" == "json" ]]; then
        printf '{"status":"FOUND","path":"%s","task_key":"%s","kind":"verify_integration"}\n' "$integration_path" "$task_key"
      else
        printf '%s\n' "$integration_path"
      fi
      return 0
    fi
    if [[ "$format" == "json" ]]; then
      printf '{"status":"NONE","path":null,"task_key":"%s","kind":null}\n' "$task_key"
    else
      echo "NONE"
    fi
    return 0
  fi

  local path
  path="$(printf '%s\n' "$matches" | head -n 1)"

  if [[ "$format" == "json" ]]; then
    printf '{"status":"FOUND","path":"%s","task_key":"%s","kind":"implementation"}\n' "$path" "$task_key"
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
