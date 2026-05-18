#!/usr/bin/env bash
set -euo pipefail

BASE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/check-dp196-diff-scope.sh [--base REF]" >&2
      exit 0
      ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

if [[ -z "$BASE" ]]; then
  BASE="$(git merge-base origin/main HEAD)"
fi

changed_files="$(git diff --name-only "$BASE"...HEAD)"
diff_text="$(git diff "$BASE"...HEAD)"

PATH=/usr/bin:/bin bash scripts/check-framework-pr-gate-selftest.sh
echo "PASS: framework PR gate self-test without PATH rg dependency"

if grep -q '^docs-manager/src/content/docs/specs/design-plans/archive/DP-188-' <<<"$changed_files"; then
  echo "DP-188 archive files must not be changed by DP-196" >&2
  grep '^docs-manager/src/content/docs/specs/design-plans/archive/DP-188-' <<<"$changed_files" >&2
  exit 1
fi
echo "PASS: DP-188 archive diff is empty"

for path in ".claude/skills/references/repo-handbook.md" ".claude/skills/references/epic-verification-workflow.md" ".claude/skills/references/pipeline-handoff.md"; do
  if grep -Fxq "$path" <<<"$changed_files"; then
    echo "phased oversized reference must stay unchanged in DP-196: $path" >&2
    exit 1
  fi
done
echo "PASS: phased oversized reference content unchanged"

if grep -Eq '^\.claude/(hooks|rules)/' <<<"$changed_files"; then
  echo "DP-196 must not change .claude/hooks or .claude/rules" >&2
  grep -E '^\.claude/(hooks|rules)/' <<<"$changed_files" >&2
  exit 1
fi
if grep -Eiq '(pip|brew|npm|pnpm|yarn|mise|cargo|go|uv)[[:space:]]+install|install[[:space:]]+(rg|yq)' <<<"$diff_text"; then
  echo "DP-196 must not introduce runtime install commands" >&2
  exit 1
fi
echo "PASS: no hook/rule/runtime dependency expansion"

grep -Fq 'LIMIT_VALUES=(500 500 50)' scripts/lint-reference-line-count.sh || {
  echo "canonical DP-188 limit tuple changed" >&2
  exit 1
}
echo "PASS: canonical DP-188 line-count limits preserved"

echo "PASS: DP-196 diff scope"
