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

# Resolve the target repo from a `git -C <path> push` form when present; fall
# back to the Claude Code project dir / current toplevel. Shared by the
# branch-name gate below and the legacy gate body further down.
repo_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
if [[ -n "$command" ]]; then
  extracted="$(printf '%s' "$command" | grep -oE 'git -C [^ ]+' | head -1 | sed 's/git -C //' || true)"
  [[ -n "$extracted" ]] && repo_root="$extracted"
fi

# Gate: branch-name ASCII (DP-307 D4 / AC5). This is a self-contained push gate
# that runs independently of the legacy gate body below: it recognizes a push
# command, honours the DP-305-T3 --delete|--tags carve-out (AC-NEG2), resolves
# the pushed branch, and reuses the single-source judgment in
# validate-branch-name-ascii.sh (no re-implemented byte check). A non-ASCII
# branch name fails the push closed.
if [[ -n "$command" ]] \
  && printf '%s' "$command" | grep -qE '(^|[[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?push([[:space:]]|$)' \
  && ! printf '%s' "$command" | grep -qE -- '--delete|--tags' \
  && [[ -d "$repo_root" ]]; then
  push_branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  case "$push_branch" in
    ""|HEAD) : ;;
    *)
      BRANCH_ASCII_VALIDATOR="$ROOT_DIR/scripts/validate-branch-name-ascii.sh"
      [[ -f "$BRANCH_ASCII_VALIDATOR" ]] && bash "$BRANCH_ASCII_VALIDATOR" "$push_branch"
      ;;
  esac
fi

# DP-360 T3 / AC2 / AC-NEG4: push detection MUST be portable. The legacy `push\b`
# word-boundary anchor is not honoured by ERE on macOS bash 3.2 (it treats `\b` as a
# literal `b`), so on that platform the legacy hook silently exited 0 on EVERY push —
# the gates below never ran. Use the same `push([[:space:]]|$)` form as the branch-name
# gate above, which matches portably. A non-push command still exits 0 (the hook only
# governs pushes), but a real push now always proceeds to the gates (fail-closed).
[[ -z "$command" || "$command" =~ (^|[[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?push([[:space:]]|$) ]] || exit 0

[[ -d "$repo_root" ]] || exit 0

if printf '%s' "$command" | grep -qE -- '--delete|--tags'; then
  exit 0
fi

# Gate: runtime-instruction manifest freshness (DP-320 D1 / AC2 / EC2). This MUST
# run before the main/master/develop branch early-exit below: a stale manifest
# pushed directly to main would otherwise escape the legacy branch filter. The
# gate is fail-closed and verdict-equivalent to compile-runtime-instructions.sh
# --check, so it never blocks a fresh-manifest push regardless of target branch.
if [[ -x "$GATES_DIR/gate-runtime-instruction-manifest.sh" ]]; then
  bash "$GATES_DIR/gate-runtime-instruction-manifest.sh" --repo "$repo_root"
fi

branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
# DP-360 T3 / AC2 / AC-NEG4: the legacy `main|master|develop) exit 0` early-exit at
# :76 is REMOVED. main / master / develop / feat/* / chore/* (and every other named
# branch) now run the delivery gates below. The ONLY exit-0 here is the genuinely
# unresolvable case — empty branch / detached HEAD — which cannot be gated against a
# branch name; this is fail-stop-on-missing-input, not a fail-open branch skip. There
# is no env bypass for the named-branch gates.
case "$branch" in
  ""|HEAD) exit 0 ;;
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

# Gate: affected-scoped selftest closure (DP-360 T3 / AC2 / AC7 / AC-NEG5). Derive the
# changed-file set from the push payload (reusing the specs-collection resolver above),
# then run the affected selftest closure. A shared / high-fanout change escalates to
# the full backstop inside the runner; an unmapped code change fails closed (no silent
# pass). Runs only when the runner exists so older trees stay unaffected, but when
# present it is mandatory and fail-closed (no env bypass). Defined here so the
# specs_collection_changed_files helper is already in scope.
AFFECTED_RUNNER="$ROOT_DIR/scripts/selftest-affected-runner.sh"
if [[ -x "$AFFECTED_RUNNER" ]]; then
  affected_changed="$(specs_collection_changed_files "$input" "$repo_root" | sort -u)"
  if [[ -n "$affected_changed" ]]; then
    printf '%s\n' "$affected_changed" | bash "$AFFECTED_RUNNER" --root "$repo_root" --run
  fi
fi

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
