#!/usr/bin/env bash
# Pre-push delivery gate.
#
# Legacy versions checked /tmp/.quality-gate-passed-* marker files. That marker
# flow is retired; push readiness now delegates to the same portable gates used
# by generated git hooks and PR creation.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$HOOK_DIR/../.." && pwd)"
GATES_DIR="$ROOT_DIR/scripts/gates"
SPECS_COLLECTION_VALIDATOR="$ROOT_DIR/scripts/validate-specs-collection-shape.sh"

input="$(cat || true)"
if [[ -z "$input" && -n "${CLAUDE_TOOL_INPUT:-}" ]]; then
  input="$CLAUDE_TOOL_INPUT"
fi

command="$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get("tool_input",{}).get("command",""))
except Exception:
    print("")
' 2>/dev/null || true)"

[[ -z "$command" || "$command" =~ (^|[[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?push\b ]] || exit 0

repo_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
if [[ -n "$command" ]]; then
  extracted="$(printf '%s' "$command" | grep -oE 'git -C [^ ]+' | head -1 | sed 's/git -C //' || true)"
  [[ -n "$extracted" ]] && repo_root="$extracted"
fi

[[ -d "$repo_root" ]] || exit 0

if printf '%s' "$command" | grep -qE -- '--delete|--tags'; then
  exit 0
fi

branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
case "$branch" in
  ""|HEAD|main|master|develop) exit 0 ;;
esac

if [[ -x "$GATES_DIR/gate-ci-local.sh" ]]; then
  bash "$GATES_DIR/gate-ci-local.sh" --repo "$repo_root" --push-mode
fi

if [[ -x "$GATES_DIR/gate-evidence-producer-whitelist.sh" ]]; then
  bash "$GATES_DIR/gate-evidence-producer-whitelist.sh" --repo "$repo_root"
fi

if [[ -x "$GATES_DIR/gate-revision-rebase.sh" ]]; then
  bash "$GATES_DIR/gate-revision-rebase.sh" --repo "$repo_root"
fi

if [[ -x "$GATES_DIR/gate-evidence.sh" ]]; then
  bash "$GATES_DIR/gate-evidence.sh" --repo "$repo_root"
fi

if [[ -x "$GATES_DIR/gate-changeset.sh" ]]; then
  bash "$GATES_DIR/gate-changeset.sh" --repo "$repo_root"
fi

# DP-230 D20: manifest parity must hold before any framework push reaches a
# workspace PR. Runs only when the validator script exists so older trees
# without the gate stay unaffected.
if [[ -x "$repo_root/scripts/validate-manifest-parity.sh" ]]; then
  bash "$repo_root/scripts/validate-manifest-parity.sh" --root "$repo_root" --quiet
fi

# DP-230 D21: template leak gate at push time prevents workspace PRs from
# landing live company slugs that sync-to-polaris would catch only post-merge.
if [[ -x "$GATES_DIR/gate-template-leaks.sh" ]]; then
  bash "$GATES_DIR/gate-template-leaks.sh" --repo "$repo_root"
fi

specs_collection_changed_files() {
  local data="$1"
  local repo="$2"
  local line="" local_ref="" local_sha="" remote_ref="" remote_sha=""
  local branch_name=""

  if [[ -n "$data" && ! "$data" =~ ^[[:space:]]*\{ ]]; then
    while read -r local_ref local_sha remote_ref remote_sha _rest; do
      [[ -n "${local_sha:-}" ]] || continue
      if [[ -n "${remote_sha:-}" && ! "$remote_sha" =~ ^0+$ ]]; then
        git -C "$repo" diff --name-only "$remote_sha" "$local_sha" 2>/dev/null || true
      else
        branch_name="${local_ref#refs/heads/}"
        if [[ "$branch_name" != "$local_ref" ]] && git -C "$repo" rev-parse --verify "origin/$branch_name" >/dev/null 2>&1; then
          git -C "$repo" diff --name-only "origin/$branch_name...$local_sha" 2>/dev/null || true
        else
          git -C "$repo" diff --name-only "$local_sha^" "$local_sha" 2>/dev/null || true
        fi
      fi
    done <<<"$data"
    return 0
  fi

  branch_name="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -n "$branch_name" && "$branch_name" != "HEAD" ]] && git -C "$repo" rev-parse --verify "origin/$branch_name" >/dev/null 2>&1; then
    git -C "$repo" diff --name-only "origin/$branch_name...HEAD" 2>/dev/null || true
    return 0
  fi
  git -C "$repo" diff --name-only HEAD~1..HEAD 2>/dev/null || true
}

should_run_specs_collection_shape() {
  local file=""
  while IFS= read -r file; do
    case "$file" in
      docs-manager/src/content.config.ts|\
      scripts/validate-specs-collection-shape.sh|\
      scripts/selftests/validate-specs-collection-shape-selftest.sh|\
      scripts/migrate-specs-artifact-frontmatter.sh|\
      scripts/selftests/migrate-specs-artifact-frontmatter-selftest.sh|\
      scripts/archive-spec.sh|\
      scripts/selftests/archive-spec-selftest.sh|\
      .claude/hooks/pre-push-quality-gate.sh|\
      .claude/skills/references/refinement-source-mode.md|\
      .claude/skills/references/authoring-preflight.md|\
      .claude/skills/references/starlight-authoring-contract.md|\
      docs-manager/src/content/docs/specs/*)
        return 0
        ;;
    esac
  done
  return 1
}

if [[ -x "$SPECS_COLLECTION_VALIDATOR" ]]; then
  changed_files="$(specs_collection_changed_files "$input" "$repo_root" | sort -u)"
  if should_run_specs_collection_shape <<<"$changed_files"; then
    bash "$SPECS_COLLECTION_VALIDATOR" --workspace "$repo_root" --all
  fi
fi
