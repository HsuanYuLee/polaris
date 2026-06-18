#!/usr/bin/env bash
# gate-work-source.sh — block Polaris PR creation without a legal work source.
#
# Exit:
#   0 = PASS / non-Polaris repo skip
#   2 = BLOCKED

set -euo pipefail

PREFIX="[polaris gate-work-source]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_ROOT=""
TASK_MD=""

# shellcheck source=../lib/specs-root.sh
. "$ROOT_DIR/scripts/lib/specs-root.sh"

usage() {
  cat >&2 <<'EOF'
usage: gate-work-source.sh [--repo <path>] [--task-md <path>]

Blocks PR creation in Polaris-governed repositories unless the current branch
resolves to a legal task.md work source. There is no emergency bypass.
EOF
}

abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
  fi
}

is_polaris_governed_repo() {
  local repo="$1"
  [[ -f "$repo/workspace-config.yaml" ]] && return 0
  [[ -d "$repo/.polaris" ]] && return 0
  [[ -f "$repo/AGENTS.md" && -x "$repo/scripts/polaris-pr-create.sh" ]] && return 0
  [[ -f "$repo/CLAUDE.md" && -x "$repo/scripts/polaris-pr-create.sh" ]] && return 0
  return 1
}

table_field() {
  local field="$1"
  local file="$2"
  awk -F '|' -v key="$field" '
    /^[[:space:]]*\|[[:space:]]*-+/ { next }
    NF >= 3 {
      f = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
      if (f == key) {
        v = $3
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
  ' "$file"
}

resolve_task_by_branch_fallback() {
  local repo="$1"
  local branch="$2"
  local specs_root=""
  specs_root="$(resolve_specs_root "$repo" 2>/dev/null || true)"
  [[ -d "$specs_root" ]] || return 1

  while IFS= read -r -d '' file; do
    if [[ "$(table_field "Task branch" "$file")" == "$branch" ]]; then
      printf '%s\n' "$file"
      return 0
    fi
  done < <(
    find "$specs_root" \
      \( -type d \( -name .git -o -name .worktrees -o -name node_modules -o -name archive \) -prune \) \
      -o \
      \( -type f \( -path '*/tasks/T*.md' -o -path '*/tasks/T*/index.md' -o -path '*/tasks/pr-release/T*.md' -o -path '*/tasks/pr-release/T*/index.md' \) -print0 \)
  )
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="$2"; shift 2 ;;
    --repo=*) REPO_ROOT="${1#--repo=}"; shift ;;
    --task-md) TASK_MD="$2"; shift 2 ;;
    --task-md=*) TASK_MD="${1#--task-md=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX ERROR: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
REPO_ROOT="$(abs_path "$REPO_ROOT")"

if ! is_polaris_governed_repo "$REPO_ROOT"; then
  echo "$PREFIX skip: repository is not Polaris-governed." >&2
  exit 0
fi

current_branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ -z "$current_branch" || "$current_branch" == "HEAD" ]]; then
  echo "$PREFIX BLOCKED: cannot resolve current branch; PR creation requires a legal work source." >&2
  exit 2
fi

if [[ "$current_branch" =~ ^(main|master|develop)$ || "$current_branch" =~ ^release/ ]]; then
  echo "$PREFIX BLOCKED: PR creation from protected/default branch is not a legal work source." >&2
  exit 2
fi

# DP-217 chore-followup lane: release-tail manifest / housekeeping fixes that
# don't deserve a new task.md. The lane only triggers when:
#   - branch matches chore/DP-NNN-<slug>
#   - the corresponding DP container exists under docs-manager/.../design-plans/
#   - at least one tasks/pr-release/T*.md or T*/index.md is status: IMPLEMENTED
# Other chore/* branches still fail the gate; this is not a generic escape.
if [[ "$current_branch" =~ ^chore/(DP-[0-9]+)- ]]; then
  chore_dp="${BASH_REMATCH[1]}"
  chore_container=""
  for candidate in "$REPO_ROOT/docs-manager/src/content/docs/specs/design-plans/${chore_dp}-"*; do
    [[ -d "$candidate" ]] || continue
    chore_container="$candidate"
    break
  done
  if [[ -z "$chore_container" ]]; then
    # Maybe DP was archived between release and follow-up.
    for candidate in "$REPO_ROOT/docs-manager/src/content/docs/specs/design-plans/archive/${chore_dp}-"*; do
      [[ -d "$candidate" ]] || continue
      chore_container="$candidate"
      break
    done
  fi
  if [[ -n "$chore_container" ]]; then
    chore_parent_implemented=0
    while IFS= read -r task_file; do
      [[ -f "$task_file" ]] || continue
      if grep -qE "^status: IMPLEMENTED" "$task_file"; then
        chore_parent_implemented=1
        break
      fi
    done < <(find "$chore_container/tasks/pr-release" -maxdepth 3 -type f \
              \( -name "T*.md" -o -name "index.md" \) 2>/dev/null)
    if [[ "$chore_parent_implemented" -eq 1 ]]; then
      echo "$PREFIX ✅ chore-followup lane: branch=$current_branch parent_dp=$chore_dp IMPLEMENTED" >&2
      exit 0
    fi
    echo "$PREFIX BLOCKED: chore-followup lane requires parent DP $chore_dp to have an IMPLEMENTED pr-release task." >&2
    exit 2
  fi
  echo "$PREFIX BLOCKED: chore-followup lane could not resolve DP container for $chore_dp." >&2
  exit 2
fi

# DP-334 feat/DP-NNN -> main release PR lane: under the feature-branch
# aggregation release model, framework DP delivery merges per-task branches into
# feat/DP-NNN, then opens a single feat/DP-NNN -> main release PR. That release
# PR is created from the feat/DP-NNN branch itself, which has no table-form
# `Task branch` binding, so without this lane gate-work-source would block it.
# The lane only triggers when:
#   - branch is exactly feat/DP-NNN (anchored ^...$, so feat/DP-334-foo does not
#     match and still falls through to the task.md resolver)
#   - the corresponding DP container exists under docs-manager/.../design-plans/
#   - at least one tasks/pr-release/T*.md or T*/index.md is status: IMPLEMENTED
# Other feat/* branches still fall through; this is not a generic escape.
if [[ "$current_branch" =~ ^feat/(DP-[0-9]+)$ ]]; then
  feat_dp="${BASH_REMATCH[1]}"
  feat_container=""
  for candidate in "$REPO_ROOT/docs-manager/src/content/docs/specs/design-plans/${feat_dp}-"*; do
    [[ -d "$candidate" ]] || continue
    feat_container="$candidate"
    break
  done
  if [[ -z "$feat_container" ]]; then
    # Maybe DP was archived between delivery and release.
    for candidate in "$REPO_ROOT/docs-manager/src/content/docs/specs/design-plans/archive/${feat_dp}-"*; do
      [[ -d "$candidate" ]] || continue
      feat_container="$candidate"
      break
    done
  fi
  if [[ -n "$feat_container" ]]; then
    feat_release_implemented=0
    while IFS= read -r task_file; do
      [[ -f "$task_file" ]] || continue
      if grep -qE "^status: IMPLEMENTED" "$task_file"; then
        feat_release_implemented=1
        break
      fi
    done < <(find "$feat_container/tasks/pr-release" -maxdepth 3 -type f \
              \( -name "T*.md" -o -name "index.md" \) 2>/dev/null)
    if [[ "$feat_release_implemented" -eq 1 ]]; then
      echo "$PREFIX ✅ feat-release lane: branch=$current_branch dp=$feat_dp IMPLEMENTED" >&2
      exit 0
    fi
    echo "$PREFIX BLOCKED: feat-release lane requires DP $feat_dp to have an IMPLEMENTED pr-release task." >&2
    exit 2
  fi
  echo "$PREFIX BLOCKED: feat-release lane could not resolve DP container for $feat_dp." >&2
  exit 2
fi

if [[ -z "$TASK_MD" ]]; then
  resolver="$ROOT_DIR/scripts/resolve-task-md.sh"
  if [[ ! -x "$resolver" ]]; then
    echo "$PREFIX BLOCKED: missing task resolver: $resolver" >&2
    exit 2
  fi
  if ! TASK_MD="$(cd "$REPO_ROOT" && bash "$resolver" --scan-root "$REPO_ROOT" --current 2>/dev/null | head -n 1)"; then
    TASK_MD=""
  fi
  if [[ -z "$TASK_MD" ]]; then
    TASK_MD="$(resolve_task_by_branch_fallback "$REPO_ROOT" "$current_branch" 2>/dev/null || true)"
  fi
fi

if [[ -z "$TASK_MD" || ! -f "$TASK_MD" ]]; then
  cat >&2 <<EOF
$PREFIX BLOCKED: PR creation requires a legal work source.

Current branch: $current_branch
Expected: a task.md / tasks/<Tn>/index.md whose Operational Context binds
Task branch to the current branch.

Create or resolve a Polaris work source first:
  DP/refinement -> breakdown -> engineering task.md -> PR

Emergency, triviality, and maintainer intent do not bypass this gate.
EOF
  exit 2
fi

task_branch="$(table_field "Task branch" "$TASK_MD")"

# DP-237 follow-up: aggregate-release lane. engineering-branch-setup.sh
# --aggregate-release writes `bundle_branch_alias: bundle-DP-NNN-vX.Y.Z` into
# each bundled task.md frontmatter. When the current branch matches that alias,
# the gate treats this as a legal aggregate-release source even though the
# table-form `Task branch` field still points at the per-task branch.
#
# DP-334 Migration Boundaries: this bundle_branch_alias acceptance is RETAINED as
# a bootstrap fallback only. Framework DP delivery now keys off feat/DP-NNN
# aggregation (engineering-branch-setup.sh creates feat/DP-NNN; the Task branch
# field binds the per-task branch whose base is feat/DP-NNN, so the table-form
# `Task branch` check below already accepts the feat-lifecycle work source).
# Removal criteria: removed in DP-334 once it self-releases under the feat model
# (AC7 PASS); see
# docs-manager/.../DP-334-framework-release-feature-branch-aggregation-release-model/index.md
# § Migration Boundaries.
bundle_branch_alias=""
bundle_branch_alias="$(awk '
  /^---$/ { fm++; next }
  fm == 1 && /^bundle_branch_alias:/ {
    sub(/^bundle_branch_alias:[[:space:]]*/, "")
    print
    exit
  }
' "$TASK_MD" 2>/dev/null || true)"

if [[ "$task_branch" != "$current_branch" && "$bundle_branch_alias" != "$current_branch" ]]; then
  cat >&2 <<EOF
$PREFIX BLOCKED: task.md branch binding mismatch.

Current branch:         $current_branch
Task branch:            ${task_branch:-<missing>}
Bundle branch alias:    ${bundle_branch_alias:-<missing>}
Task source:            $TASK_MD
EOF
  exit 2
fi

validator="$ROOT_DIR/scripts/validate-task-md.sh"
if [[ ! -x "$validator" ]]; then
  echo "$PREFIX BLOCKED: missing task validator: $validator" >&2
  exit 2
fi

if ! (cd "$REPO_ROOT" && bash "$validator" "$TASK_MD" >/dev/null); then
  echo "$PREFIX BLOCKED: task source failed schema validation: $TASK_MD" >&2
  echo "Fix the task artifact before creating a PR." >&2
  exit 2
fi

echo "$PREFIX ✅ source valid: $TASK_MD" >&2
