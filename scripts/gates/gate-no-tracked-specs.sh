#!/usr/bin/env bash
set -euo pipefail

# gate-no-tracked-specs.sh
#
# docs-manager specs are local canonical planning/execution artifacts. They are
# intentionally ignored and must not enter workspace/template git history.

PREFIX="[polaris gate-no-tracked-specs]"
PROTECTED_PREFIX="docs-manager/src/content/docs/specs/"
REPO_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/gates/gate-no-tracked-specs.sh [--repo <path>]"
      exit 0
      ;;
    *) shift ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO_ROOT" ]] || exit 0

tracked="$(git -C "$REPO_ROOT" ls-files -- "$PROTECTED_PREFIX" 2>/dev/null || true)"
if [[ -z "$tracked" ]]; then
  echo "$PREFIX ✅ no tracked docs-manager specs." >&2
  exit 0
fi

cat >&2 <<EOF
$PREFIX BLOCKED: docs-manager specs are tracked by git.

These paths are local-only planning/execution artifacts and must not enter
workspace/template history:

$tracked

Fix:
  git -C "$REPO_ROOT" rm --cached --ignore-unmatch -- $PROTECTED_PREFIX

Keep the local files on disk; remove them from git index only.
EOF
exit 2
