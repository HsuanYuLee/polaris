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

# DP-419 T3 (AC-NF1 / AC-NEG1 / AC-NEG2 / AC-NEG3): self-referential delivery self-verify.
# Compatibility seam retained for the existing hermetic self-reference contract test.
# Normal pre-push execution no longer calls a full-corpus binary directly; changed-file
# routing below emits an explicit escalation sentinel for the PR/release backstop. Given
# this push's changed
# files, if the change is self-referential (its files intersect the delivery-gate script
# set, per the T2 classifier detect-self-referential-delivery.sh), the trust anchor is the
# CURRENT full governed selftest corpus going green — a
# superset that is harder to forge than the single old sub-gate being fixed. Return codes:
#   0  = self-referential AND current corpus green            -> caller may proceed
#   1  = self-referential CONFIRMED but corpus red/unavailable -> fail-closed (block)
#   10 = carve-out not applicable — either not self-referential, OR the self-ref scope is
#        undeterminable (missing input / classifier absent / classifier undecidable) ->
#        caller falls through to the normal (stricter) gate chain. Rationale: a CONFIRMED
#        self-ref change without a green corpus is dangerous and MUST block (AC-NF1/NEG2);
#        but "cannot determine self-ref scope" means the carve-out does not apply (old tree
#        / non-framework repo / fixture without the classifier), so defer to the normal
#        gate chain rather than hard-block EVERY push. Aligns with this file's existing `-x`
#        graceful-degradation convention.
# POLARIS_DETECT_SELFREF_BIN / POLARIS_AGGREGATE_SELFTESTS_BIN are *_BIN test-injection
# seams (NOT *_BYPASS): they only relocate the two external commands for hermetic
# selftests; the normal hook path leaves them at their canonical repo paths and never
# silences a gate.
selfref_self_verify() {
  local repo_root="$1"; shift
  local -a changed=("$@")
  # (1) missing input -> self-ref scope undeterminable -> carve-out N/A (return 10, fall
  #     through to the normal gate chain), NOT a hard block. Hard-blocking here would
  #     wrongly block every push whose changed set is underivable.
  [[ "${#changed[@]}" -gt 0 ]] || return 10
  local classifier="${POLARIS_DETECT_SELFREF_BIN:-$repo_root/scripts/detect-self-referential-delivery.sh}"
  local corpus="${POLARIS_AGGREGATE_SELFTESTS_BIN:-}"
  [[ -n "$corpus" ]] || return 10
  local out
  # (2) run the classifier; if it cannot run/decide (absent binary, exit != 0) the self-ref
  #     scope is undeterminable -> carve-out N/A (return 10), NOT a hard block (old tree /
  #     non-framework repo / fixture without the classifier defers to the normal chain).
  out="$(printf '%s\n' "${changed[@]}" | bash "$classifier" --stdin --repo-root "$repo_root" 2>/dev/null)" || return 10
  # (3) not self-referential -> carve-out N/A; caller uses the normal path.
  if ! printf '%s' "$out" | grep -Eq '"self_referential"[[:space:]]*:[[:space:]]*true'; then
    return 10
  fi
  # (4) self-referential CONFIRMED -> the CURRENT corpus (fresh self-check, not a stale
  #     snapshot marker) must be green. Green -> proceed (0); red / unavailable -> this is
  #     the ONLY hard-block (fail-closed, AC-NF1 / AC-NEG2).
  bash "$corpus" >/dev/null 2>&1 || return 1
  return 0
}

# Hidden test seam: `--selfref-self-verify --changed-file <p> [...] [--repo-root <dir>]`.
# Runs ONLY the decision function above and maps its return to the exit code the selftest
# asserts (0 proceed / 1 fail-closed / 10 non-self-referential). The normal hook path
# (no subcommand) is unchanged.
if [[ "${1:-}" == "--selfref-self-verify" ]]; then
  shift
  _selfref_repo="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  _selfref_cf=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --changed-file)
        [[ $# -ge 2 ]] || { echo "POLARIS_SELF_REFERENTIAL_BAD_ARGS: --changed-file requires a value" >&2; exit 1; }
        _selfref_cf+=("$2"); shift 2 ;;
      --repo-root)
        [[ $# -ge 2 ]] || { echo "POLARIS_SELF_REFERENTIAL_BAD_ARGS: --repo-root requires a value" >&2; exit 1; }
        _selfref_repo="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  set +e
  selfref_self_verify "$_selfref_repo" "${_selfref_cf[@]+"${_selfref_cf[@]}"}"
  _selfref_rc=$?
  set -e
  exit "$_selfref_rc"
fi

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
  if [[ -n "$branch_name" && "$branch_name" != "HEAD" ]]; then
    local upstream=""
    upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    if [[ -n "$upstream" ]]; then
      git -C "$repo" diff --name-only "$upstream...HEAD" 2>/dev/null || true
      return 0
    fi
    if git -C "$repo" rev-parse --verify "origin/$branch_name" >/dev/null 2>&1; then
      git -C "$repo" diff --name-only "origin/$branch_name...HEAD" 2>/dev/null || true
      return 0
    fi
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
    affected_plan="$(printf '%s\n' "$affected_changed" | bash "$AFFECTED_RUNNER" --root "$repo_root" --emit)"
    if [[ "$affected_plan" == "POLARIS_AFFECTED_FULL_CORPUS" ]]; then
      echo "pre-push: affected selector escalated shared/self-referential change; full corpus is required at the PR/pre-promotion backstop" >&2
    else
      printf '%s\n' "$affected_changed" | bash "$AFFECTED_RUNNER" --root "$repo_root" --run
    fi
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
