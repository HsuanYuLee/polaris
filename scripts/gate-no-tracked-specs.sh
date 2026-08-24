#!/usr/bin/env bash
# 為什麼這一道還在（門檻 2026-08-13，見 .claude/instructions/core/bootstrap.md）：
#   個人的規劃內容進這個 repo，然後跟著 template 出去到公開的地方；混在一批正常檔案裡看不出來。
set -euo pipefail

# gate-no-tracked-specs.sh
#
# docs-manager specs are local canonical planning/execution artifacts. They are
# intentionally ignored and must not enter workspace/template git history.
#
# A spine source's .spine/ is the same kind of thing — loop state and the
# measurement ledger are rewritten every round — so it is protected too.
#
# issues/ as a whole is now the user's own git repository and is ignored by this
# one, so nothing under it can be tracked here anyway. This guard stays because
# the ignore rule is a decision someone can undo in one line, and the thing it
# would let through — execution state entering framework history — is exactly what
# the guard names. Its scope is contract vs. execution state, not a directory.

PREFIX="[polaris gate-no-tracked-specs]"
PROTECTED_PREFIXES=(
  "docs-manager/src/content/docs/specs/"
  # git ls-files recurses into a literal directory prefix, but a pathspec with a
  # wildcard segment needs an explicit trailing /* or it matches nothing.
  "issues/*/.spine/*"
)
REPO_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/gate-no-tracked-specs.sh [--repo <path>]"
      exit 0
      ;;
    *) shift ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO_ROOT" ]] || exit 0

tracked="$(git -C "$REPO_ROOT" ls-files -- "${PROTECTED_PREFIXES[@]}" 2>/dev/null || true)"
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
  git -C "$REPO_ROOT" rm -r --cached --ignore-unmatch -- ${PROTECTED_PREFIXES[*]}

Keep the local files on disk; remove them from git index only.
EOF
exit 2
