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
# specs-root.sh sources main-checkout.sh lazily (only inside
# resolve_specs_workspace_root); the DP-393 chore guard needs resolve_main_checkout
# up front, so source it explicitly here.
# shellcheck source=../lib/main-checkout.sh
. "$ROOT_DIR/scripts/lib/main-checkout.sh"

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

canonical_existing_path() {
  python3 - "$1" <<'PY'
import pathlib
import sys

try:
    print(pathlib.Path(sys.argv[1]).resolve(strict=True))
except (OSError, RuntimeError):
    raise SystemExit(1)
PY
}

# canonical_task_source <repo> <task_md>
#   Require the task source to be the canonical workspace specs artifact, not a
#   same-shaped file from /tmp or a linked worktree's local-only partial view.
#   Path containment uses resolved path components (not a string prefix), then
#   delegates DP-number collision detection to the existing uniqueness validator.
canonical_task_source() {
  local repo="$1"
  local task_md="$2"
  local workspace_root=""
  local specs_root=""
  local task_real=""
  local specs_real=""

  workspace_root="$(resolve_specs_workspace_root "$ROOT_DIR" 2>/dev/null || true)"
  if [[ -n "$workspace_root" ]]; then
    specs_root="$(resolve_specs_root "$workspace_root" 2>/dev/null || true)"
  fi
  task_real="$(canonical_existing_path "$task_md" 2>/dev/null || true)"
  if [[ -n "$specs_root" ]]; then
    specs_real="$(canonical_existing_path "$specs_root" 2>/dev/null || true)"
  fi

  if [[ -z "$specs_root" || -z "$task_real" || -z "$specs_real" ]] || ! python3 - "$task_real" "$specs_real" <<'PY'
import pathlib
import sys

task = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
try:
    task.relative_to(root)
except ValueError:
    raise SystemExit(1)
PY
  then
    cat >&2 <<EOF
$PREFIX BLOCKED: explicit or resolved task.md is outside the canonical workspace specs root.
POLARIS_WORK_SOURCE_NON_CANONICAL_TASK

Task source:          ${task_real:-$task_md}
Canonical specs root: ${specs_real:-<unresolved>}
Repository:           $repo

Use the task.md under the main workspace's canonical specs tree. A copied task
from /tmp or a linked worktree local overlay is not source authority.
EOF
    return 2
  fi

  case "$task_real" in
    "$specs_real"/design-plans/*)
      local uniqueness="$ROOT_DIR/scripts/validate-dp-number-uniqueness.sh"
      if [[ ! -x "$uniqueness" ]] || ! bash "$uniqueness" --specs-root "$specs_real" >/dev/null; then
        echo "$PREFIX BLOCKED: canonical DP identity inventory is ambiguous." >&2
        echo "POLARIS_WORK_SOURCE_DP_IDENTITY_AMBIGUOUS" >&2
        return 2
      fi
      ;;
  esac

  printf '%s\n' "$task_real"
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

# ── DP-393 chore-followup framework-owned change guard ────────────────────────
# The chore-followup lane below only checks that the parent DP is IMPLEMENTED; it
# historically did NOT inspect the branch's changed files, so a chore/DP-NNN
# branch could smuggle a framework-owned behavior change (scripts/**, .claude
# rules/skills/hooks, generated runtime targets, config surfaces) into a release-
# tail housekeeping PR and skip the DP-backed task.md work-order flow. This guard
# resolves a worktree-aware diff base, computes the branch's changed files with
# the same `git diff --name-only base..HEAD` primitive gate-changed-files-scope.sh
# uses, then classifies each changed path with a fixed denylist/allowlist:
#   - denylist (framework-owned behavior surfaces) → BLOCK
#   - allowlist (release-tail manifest / housekeeping) → permitted
#   - anything else (incl. generated runtime targets) → BLOCK (fail-closed)
# Deny takes precedence over allow, so a diff touching both is BLOCKed (EC1). The
# guard is not routed through gate-changed-files-scope.sh itself because that gate
# requires a resolved task.md Allowed Files authority, which a chore-followup release
# tail intentionally does not have. The diff primitive and glob matching remain the
# shared reuse point.

# chore_changed_file_is_denied <path>: framework-owned behavior surface denylist.
# Mirrors the framework-owned path list in
# .claude/rules/workspace-self-development.md. Returns 0 when denied.
chore_changed_file_is_denied() {
  local path="$1"
  case "$path" in
    .claude/skills/*|.claude/rules/*|.claude/hooks/*|.claude/references/*|.claude/instructions/*) return 0 ;;
    scripts/*) return 0 ;;
    .agents/*|.codex/*) return 0 ;;
    .github/copilot-instructions.md) return 0 ;;
    mise.toml|workspace-config.yaml) return 0 ;;
  esac
  return 1
}

# chore_changed_file_is_allowed <path>: release-tail manifest / housekeeping
# allowlist. Generated runtime targets (CLAUDE.md / AGENTS.md / .codex/AGENTS.md /
# .github/copilot-instructions.md) are deliberately NOT in the allowlist and so
# fall through to a fail-closed BLOCK (EC2). Returns 0 when allowed.
chore_changed_file_is_allowed() {
  local path="$1"
  case "$path" in
    VERSION|package.json|CHANGELOG.md) return 0 ;;
    .changeset/*) return 0 ;;
    docs-manager/src/content/docs/specs/design-plans/*) return 0 ;;
  esac
  return 1
}

# chore_resolve_diff_base <repo> <dp>: echo the worktree-aware diff base for the
# chore branch's changed-file computation, or return 1 (fail-closed) when no base
# can be resolved. Three scenarios (EC3):
#   1. feat/DP-NNN exists  → base = merge-base(HEAD, feat/DP-NNN)
#   2. no feat/DP-NNN but a main/master merge-base exists → base = that merge-base
#   3. neither resolvable  → return 1 (caller BLOCKs; the lane never falls open)
# resolve_main_checkout (sourced transitively via specs-root.sh) makes ref
# resolution work from inside a linked worktree as well as the main checkout.
chore_resolve_diff_base() {
  local repo="$1"
  local dp="$2"
  local main_root=""
  main_root="$(resolve_main_checkout "$repo" 2>/dev/null || true)"
  [[ -n "$main_root" ]] || return 1
  local base=""
  local feat_ref="feat/$dp"
  if git -C "$repo" rev-parse --verify --quiet "$feat_ref^{commit}" >/dev/null 2>&1; then
    base="$(git -C "$repo" merge-base HEAD "$feat_ref" 2>/dev/null || true)"
  fi
  if [[ -z "$base" ]]; then
    local main_ref
    for main_ref in origin/main main origin/master master; do
      if git -C "$repo" rev-parse --verify --quiet "$main_ref^{commit}" >/dev/null 2>&1; then
        base="$(git -C "$repo" merge-base HEAD "$main_ref" 2>/dev/null || true)"
        [[ -n "$base" ]] && break
      fi
    done
  fi
  [[ -n "$base" ]] || return 1
  printf '%s\n' "$base"
}

# chore_guard_changed_files <repo> <dp>: enforce the denylist/allowlist over the
# chore branch's changed files. Returns 0 when every changed file is permitted,
# 2 when a framework-owned change is present or the diff base is unresolvable.
# Emits the offending path(s) and repair guidance to stderr on BLOCK (AC-NF2).
chore_guard_changed_files() {
  local repo="$1"
  local dp="$2"
  local base=""
  if ! base="$(chore_resolve_diff_base "$repo" "$dp")"; then
    cat >&2 <<EOF
$PREFIX BLOCKED: chore-followup lane could not resolve a diff base for $current_branch.
Cannot verify the branch only touches release-tail housekeeping, so the lane
fails closed. Push feat/$dp (or ensure a main merge-base exists), or route the
change through a DP-backed task.md work order.
EOF
    return 2
  fi
  local changed=""
  changed="$(git -C "$repo" diff --name-only "$base..HEAD" 2>/dev/null || true)"
  local offending=()
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if chore_changed_file_is_denied "$path"; then
      offending+=("$path (framework-owned behavior surface)")
    elif chore_changed_file_is_allowed "$path"; then
      continue
    else
      offending+=("$path (not a release-tail housekeeping path)")
    fi
  done <<EOF
$changed
EOF
  if [[ "${#offending[@]}" -gt 0 ]]; then
    {
      echo "$PREFIX BLOCKED: chore-followup lane is release-tail housekeeping only;"
      echo "framework-owned behavior changes must go through a DP-backed task.md."
      echo "Offending changed files:"
      for path in "${offending[@]}"; do
        echo "  - $path"
      done
      echo "Route the change through: DP/refinement -> breakdown -> engineering task.md -> PR."
    } >&2
    return 2
  fi
  return 0
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
      # DP-393: the parent DP being IMPLEMENTED is necessary but not sufficient.
      # The chore-followup lane is release-tail housekeeping only, so also require
      # the branch's changed files to stay off framework-owned behavior surfaces.
      if ! chore_guard_changed_files "$REPO_ROOT" "$chore_dp"; then
        exit 2
      fi
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
#   - the corresponding DP container exists under the canonical specs root
#     (design-plans/), resolved worktree-aware via resolve_specs_root
#   - at least one tasks/pr-release/T*.md or T*/index.md is status: IMPLEMENTED
# Other feat/* branches still fall through; this is not a generic escape.
if [[ "$current_branch" =~ ^feat/(DP-[0-9]+)$ ]]; then
  feat_dp="${BASH_REMATCH[1]}"
  # Resolve the canonical specs root in a worktree-aware way. When the release run
  # launches from a feat/DP-NNN worktree, the specs container lives only in the
  # main checkout, so a bare per-worktree path lookup would not find it and the
  # lane would falsely BLOCK. resolve_specs_root chains to the main checkout (via
  # resolve_main_checkout), mirroring resolve_task_by_branch_fallback above. When
  # the specs root cannot be resolved (e.g. no canonical specs tree at all), leave
  # feat_container empty so the existing "could not resolve DP container" fail-
  # closed path below fires — the gate never falls open.
  feat_specs_root=""
  feat_specs_root="$(resolve_specs_root "$REPO_ROOT" 2>/dev/null || true)"
  feat_container=""
  if [[ -n "$feat_specs_root" && -d "$feat_specs_root" ]]; then
    for candidate in "$feat_specs_root/design-plans/${feat_dp}-"*; do
      [[ -d "$candidate" ]] || continue
      feat_container="$candidate"
      break
    done
    if [[ -z "$feat_container" ]]; then
      # Maybe DP was archived between delivery and release.
      for candidate in "$feat_specs_root/design-plans/archive/${feat_dp}-"*; do
        [[ -d "$candidate" ]] || continue
        feat_container="$candidate"
        break
      done
    fi
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

if [[ -z "$TASK_MD" ]]; then
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

if ! TASK_MD="$(canonical_task_source "$REPO_ROOT" "$TASK_MD")"; then
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
