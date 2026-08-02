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
#     .git/hooks/pre-push installed by .claude/skills/framework-release/scripts/install-git-hooks.sh) so leaks
#     are caught before merge.

PREFIX="[polaris gate-template-leaks]"
REPO_ROOT=""

usage() {
  cat >&2 <<EOF
Usage: bash .claude/skills/framework-release/scripts/gate-template-leaks.sh [--repo <path>]

Runs scripts/scan-template-leaks.sh --blocking against the workspace root. Exits 0
on no material hits; exits 1 on hits; exits 2 on usage or environment error.
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

SCAN="$REPO_ROOT/.claude/skills/framework-release/scripts/scan-template-leaks.sh"
if [[ ! -x "$SCAN" ]]; then
  echo "$PREFIX ERROR: scan-template-leaks.sh missing or not executable at $SCAN" >&2
  exit 2
fi

# v3.85.0 read the delivery record here and, for a destination=template push,
# dropped the scan's company carve-outs over the changed paths. The reasoning was
# that those carve-outs rest on "company surfaces never sync", which a template-bound
# delivery invalidates. Measured afterwards, it does not: sync copies
# .claude/rules/*.md at one level only and skips skills declaring company-only, so
# the carved-out set and the copied set do not intersect for any destination, and
# sync re-scans the template tree itself after copying. The strict reading therefore
# added no detection the default scan lacks — this round's own leak, in an L1 rule,
# was caught by the plain scan — while blocking the first delivery that legitimately
# touched a company handbook. The premise was mine and was never measured; the
# wiring is gone rather than worked around.

echo "$PREFIX scanning workspace tracked files for template leaks..." >&2
if "$SCAN" --workspace "$REPO_ROOT" --source workspace --blocking; then
  echo "$PREFIX ✅ no material template leaks." >&2
  exit 0
fi

# scan-template-leaks already emitted POLARIS_TEMPLATE_LEAK summary to stderr.
echo "$PREFIX BLOCKED: workspace contains template leak hits. Fix workspace source per rules/framework-iteration.md § Template-Facing Examples Must Be Generic before pushing/PR." >&2
exit 1
