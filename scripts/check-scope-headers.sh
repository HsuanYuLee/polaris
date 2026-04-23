#!/usr/bin/env bash
# check-scope-headers.sh — Validates that company rule files have Scope: headers
#
# Usage:
#   As a pre-commit hook:  scripts/check-scope-headers.sh --staged
#   Full scan:             scripts/check-scope-headers.sh [rules_dir]
#
# Company rule files live under .claude/rules/{company}/*.md.
# Each must contain a "> **Scope: {company}**" line within the first 10 lines.
# Files directly under .claude/rules/ (L1 universal rules) are not checked.
#
# Exit 0 = all pass, Exit 1 = violations found

set -euo pipefail

RULES_DIR="${1:-.claude/rules}"

# --- Staged mode: only check staged .md files under rules/{company}/ ---
if [[ "${1:-}" == "--staged" ]]; then
  files=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep -E '\.claude/rules/[^/]+/.+\.md$' || true)
  if [[ -z "$files" ]]; then
    exit 0  # No company rule files staged
  fi
else
  # --- Full scan: find all company rule files ---
  if [[ ! -d "$RULES_DIR" ]]; then
    echo "Rules directory not found: $RULES_DIR" >&2
    exit 0
  fi
  files=$(find "$RULES_DIR" -mindepth 2 -name '*.md' -type f 2>/dev/null || true)
  if [[ -z "$files" ]]; then
    exit 0  # No company rule files exist
  fi
fi

violations=()

while IFS= read -r file; do
  [[ -z "$file" ]] && continue

  # Extract expected company name from path: any/path/{company}/foo.md → company
  # Works for both relative (.claude/rules/acme/x.md) and absolute paths
  company=$(basename "$(dirname "$file")")

  # Check first 10 lines for Scope: header
  if ! head -10 "$file" | grep -qiE '>[[:space:]]*\*?\*?Scope:[[:space:]]' 2>/dev/null; then
    violations+=("$file (missing Scope: header, expected company: $company)")
  fi
done <<< "$files"

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "=== Scope Header Violations ===" >&2
  echo "" >&2
  echo "Company rule files must include a Scope: header in the first 10 lines:" >&2
  echo '  > **Scope: {company}** — applies only when working on {company} tickets.' >&2
  echo "" >&2
  for v in "${violations[@]}"; do
    echo "  - $v" >&2
  done
  echo "" >&2
  echo "See: .claude/rules/multi-company-isolation.md" >&2
  exit 1
fi

exit 0
