#!/usr/bin/env bash
# Purpose: block framework-owned diffs from product delivery PRs.
# Inputs:  --repo PATH --base REF [--head REF] [--mode product|framework]
# Outputs: PASS line, or POLARIS_FRAMEWORK_SCOPE_ESCALATION_REQUIRED + exit 2.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/framework-scope-escalation-gate.sh --repo PATH --base REF [--head REF] [--mode product|framework]

Product mode blocks framework-owned paths and instructs the caller to isolate the
diff into a DP-backed framework workstream. Framework mode allows them.
USAGE
  exit 2
}

REPO=""
BASE=""
HEAD="HEAD"
MODE="product"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --head) HEAD="${2:-}"; shift 2 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "framework-scope-escalation-gate: unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$REPO" && -n "$BASE" ]] || usage
[[ -d "$REPO" ]] || { echo "framework-scope-escalation-gate: repo not found: $REPO" >&2; exit 2; }
case "$MODE" in
  product|framework) ;;
  *) echo "framework-scope-escalation-gate: invalid mode: $MODE" >&2; exit 2 ;;
esac

changed=()
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  changed+=("$path")
done < <(git -C "$REPO" diff --name-only "$BASE" "$HEAD" --)
framework_hits=()
for path in "${changed[@]}"; do
  case "$path" in
    .claude/skills/*|.claude/rules/*|.claude/instructions/*|.codex/*|.agents/*|\
    scripts/auto-pass-*|scripts/framework-*|scripts/polaris-*|scripts/validate-auto-pass-*|\
    scripts/verify-cross-llm-*|scripts/check-framework-*|CLAUDE.md|AGENTS.md)
      framework_hits+=("$path")
      ;;
  esac
done

if [[ "$MODE" == "product" && ${#framework_hits[@]} -gt 0 ]]; then
  {
    echo "POLARIS_FRAMEWORK_SCOPE_ESCALATION_REQUIRED: product delivery contains framework-owned diff"
    printf '  - %s\n' "${framework_hits[@]}"
    echo "Move these changes into a DP-backed framework workstream seed/handoff or an existing DP-backed framework source; do not include them in the product PR."
  } >&2
  exit 2
fi

echo "PASS: framework scope escalation gate (${MODE}, ${#framework_hits[@]} framework-owned changed file(s))"
