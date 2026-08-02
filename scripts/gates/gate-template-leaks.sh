#!/usr/bin/env bash
set -euo pipefail

# gate-template-leaks.sh
#
# Workspace PR-time / push-time gate: scan tracked files for template leaks
# (live company slug, JIRA prefix, internal Slack ID, internal URL) before they
# can reach a workspace PR or be pushed to remote. Wraps scripts/scan-template-leaks.sh
# in workspace mode with --blocking so leak scan failure exits non-zero.
#
# Recurrence prevention contract (rules/framework-iteration.md
# § "Template-Facing Examples Must Be Generic"):
#   * scan-template-leaks was previously only invoked inside sync-to-polaris.sh
#     (post-merge). By the time leaks were detected the workspace PR had already
#     merged, forcing a hard-reset + replacement PR.
#   * This gate runs the same scan at workspace PR creation (via
#     scripts/check-framework-pr-gate.sh) and at git push time (via
#     .git/hooks/pre-push installed by scripts/install-git-hooks.sh) so leaks
#     are caught before merge.

PREFIX="[polaris gate-template-leaks]"
REPO_ROOT=""

usage() {
  cat >&2 <<EOF
Usage: bash scripts/gates/gate-template-leaks.sh [--repo <path>]

Runs scripts/scan-template-leaks.sh --blocking against the workspace root. When a
delivery record for this commit declares destination=template, the company-directory
carve-outs are dropped for the paths this push changes. Exits 0 on no material hits;
exits 1 on hits; exits 2 on usage or environment error.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) shift ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi

if [[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT" ]]; then
  echo "$PREFIX ERROR: cannot resolve repo root (--repo not given and not in git)." >&2
  exit 2
fi

SCAN="$REPO_ROOT/scripts/scan-template-leaks.sh"
if [[ ! -x "$SCAN" ]]; then
  echo "$PREFIX ERROR: scan-template-leaks.sh missing or not executable at $SCAN" >&2
  exit 2
fi

# Which way this push is going, read from the delivery record rather than assumed.
# The workspace scan carves out company directories because company surfaces never
# sync — true for a workspace-bound source, false for a template-bound one. Bound
# to a --source flag that is always "workspace", the carve-out silently made a live
# slug legitimate at PR time and a leak at sync time, so leaks reached merge before
# anything noticed. The declaration decides it now.
DELIVERY_GATE="$REPO_ROOT/scripts/gates/gate-spine-delivery.sh"
TEMPLATE_BOUND=""
if [[ -f "$DELIVERY_GATE" ]]; then
  while IFS=$'\t' read -r rec_source _rec_state rec_destination; do
    [[ -n "$rec_source" ]] || continue
    [[ "$rec_destination" == "template" ]] && TEMPLATE_BOUND="$rec_source"
  done < <(bash "$DELIVERY_GATE" --repo "$REPO_ROOT" --print-records 2>/dev/null || true)
fi

STRICT=()
if [[ -n "$TEMPLATE_BOUND" ]]; then
  # Only what this push adds. A template-bound source must not produce company
  # content; company files that were already here belong to someone else's
  # workspace-bound work and are not this push's business.
  base_ref="origin/main"
  git -C "$REPO_ROOT" rev-parse --verify --quiet "$base_ref" >/dev/null 2>&1 || base_ref="HEAD~1"
  CHANGED=()
  while IFS= read -r changed; do
    [[ -n "$changed" ]] && CHANGED+=(--only-path "$changed")
  done < <(git -C "$REPO_ROOT" diff --name-only "$base_ref"...HEAD 2>/dev/null || true)

  # An empty changed set must not turn into "scan everything strictly": that would
  # flag every company file in the workspace over a push that adds none of them.
  if [[ ${#CHANGED[@]} -gt 0 ]]; then
    echo "$PREFIX $TEMPLATE_BOUND declares destination=template — company carve-outs off for this push's changed paths." >&2
    STRICT=(--strict-company "${CHANGED[@]}")
  fi
fi

echo "$PREFIX scanning workspace tracked files for template leaks..." >&2
if "$SCAN" --workspace "$REPO_ROOT" --source workspace --blocking "${STRICT[@]+"${STRICT[@]}"}"; then
  echo "$PREFIX ✅ no material template leaks." >&2
  exit 0
fi

# scan-template-leaks already emitted POLARIS_TEMPLATE_LEAK summary to stderr.
echo "$PREFIX BLOCKED: workspace contains template leak hits. Fix workspace source per rules/framework-iteration.md § Template-Facing Examples Must Be Generic before pushing/PR." >&2
exit 1
