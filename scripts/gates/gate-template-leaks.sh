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

Runs scripts/scan-template-leaks.sh --source workspace --blocking against the
workspace root. Exits 0 on no material hits; exits 1 on hits; exits 2 on usage
or environment error.
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

echo "$PREFIX scanning workspace tracked files for template leaks..." >&2
if "$SCAN" --workspace "$REPO_ROOT" --source workspace --blocking; then
  echo "$PREFIX ✅ no material template leaks." >&2
  exit 0
fi

# scan-template-leaks already emitted POLARIS_TEMPLATE_LEAK summary to stderr.
echo "$PREFIX BLOCKED: workspace contains template leak hits. Fix workspace source per rules/framework-iteration.md § Template-Facing Examples Must Be Generic before pushing/PR." >&2
exit 1
