#!/usr/bin/env bash
set -euo pipefail

# Purpose: framework self-development handbook routing validator.
#
# Reads a list of changed files (or single explicit file) and decides whether
# the change hits Polaris-owned surfaces. When hits are detected, the routing
# verdict requires loading .claude/rules/handbook/framework/index.md as the
# framework self-development handbook SoT. Product repo / company handbook
# paths must NOT be mis-routed into the framework handbook.
#
# Inputs:
#   --changed-files <path>  Newline-separated file list (e.g. from
#                           `git diff --name-only`). Repeatable lines are
#                           classified independently.
#   --file <path>           Single explicit file to classify (repeatable).
#                           Useful for selftest fixtures.
#   --mode <verdict|diff>   verdict (default): emit routing verdict to stdout
#                           and exit 0. diff: same classification but emit
#                           any framework-owned hits to stderr (used by PR
#                           gate observability).
#   -h | --help             Show usage.
#
# Outputs:
#   stdout: routing verdict JSON:
#     {
#       "schema_version": 1,
#       "framework_handbook_required": true|false,
#       "framework_handbook_topics": [...],
#       "framework_owned_hits": [...],
#       "product_repo_paths": [...],
#       "unclassified": [...]
#     }
#
# Exit code:
#   0 = classification produced (routing verdict on stdout)
#   2 = contract violation (file missing, bad invocation)
#
# Routing classification:
#   - framework-owned (handbook required):
#       .claude/**, .agents/**, .codex/**, .github/copilot-instructions.md,
#       scripts/**, mise.toml, workspace-config.yaml,
#       .claude/instructions/manifest.yaml,
#       CLAUDE.md, AGENTS.md (root generated targets),
#       docs-manager/src/content/docs/specs/design-plans/DP-*
#   - product-repo / company-handbook (excluded, must NOT mis-route):
#       <company>/polaris-config/<project>/handbook/**,
#       <company>/polaris-config/<project>/generated-scripts/**,
#       _template/**
#   - Mixed hit (both surfaces) → framework_handbook_required=true AND
#     product_repo_paths populated; caller must load both handbooks.
#   - Framework DP release topology routing is additive topic guidance:
#       DP source paths and framework source entrypoint references require
#       .claude/rules/handbook/framework/release-topology.md in addition to
#       the framework handbook index.

PREFIX="[polaris validate-framework-handbook-routing]"

CHANGED_FILES_PATHS=()
EXPLICIT_FILES=()
MODE="verdict"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/validate-framework-handbook-routing.sh
       [--changed-files <path>]...
       [--file <path>]...
       [--mode verdict|diff]

Modes:
  verdict (default): emit JSON routing verdict to stdout.
  diff:              emit framework-owned hits to stderr (for PR gate
                     observability); JSON verdict still on stdout.

Exit:
  0  classification produced
  2  contract violation
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --changed-files)
      [[ $# -ge 2 ]] || { echo "$PREFIX --changed-files requires a path." >&2; exit 2; }
      CHANGED_FILES_PATHS+=("$2"); shift 2 ;;
    --file)
      [[ $# -ge 2 ]] || { echo "$PREFIX --file requires a path." >&2; exit 2; }
      EXPLICIT_FILES+=("$2"); shift 2 ;;
    --mode)
      [[ $# -ge 2 ]] || { echo "$PREFIX --mode requires a value." >&2; exit 2; }
      MODE="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "$PREFIX unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$MODE" != "verdict" && "$MODE" != "diff" ]]; then
  echo "$PREFIX --mode must be 'verdict' or 'diff' (got '$MODE')." >&2
  exit 2
fi

if [[ "${#CHANGED_FILES_PATHS[@]}" -eq 0 && "${#EXPLICIT_FILES[@]}" -eq 0 ]]; then
  echo "$PREFIX BLOCKED: must supply at least one --changed-files or --file." >&2
  exit 2
fi

# Materialize the candidate path set, deduplicating while preserving order.
# Use an indexed array with a linear-scan check to stay portable to bash 3.2
# (macOS default), where `declare -A` is not available.
CANDIDATES=()

push_candidate() {
  local p="$1" existing
  # Trim leading/trailing whitespace.
  p="${p#"${p%%[![:space:]]*}"}"
  p="${p%"${p##*[![:space:]]}"}"
  [[ -z "$p" ]] && return 0
  # Strip leading ./
  p="${p#./}"
  for existing in "${CANDIDATES[@]+"${CANDIDATES[@]}"}"; do
    [[ "$existing" == "$p" ]] && return 0
  done
  CANDIDATES+=("$p")
}

for cf in "${CHANGED_FILES_PATHS[@]+"${CHANGED_FILES_PATHS[@]}"}"; do
  if [[ ! -f "$cf" ]]; then
    echo "$PREFIX BLOCKED: --changed-files path does not exist: $cf" >&2
    exit 2
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    push_candidate "$line"
  done < "$cf"
done

for ef in "${EXPLICIT_FILES[@]+"${EXPLICIT_FILES[@]}"}"; do
  push_candidate "$ef"
done

# Classification helpers.

is_framework_owned() {
  local path="$1"
  case "$path" in
    .claude/*|.agents/*|.codex/*)
      return 0 ;;
    .github/copilot-instructions.md)
      return 0 ;;
    scripts/*)
      return 0 ;;
    mise.toml|workspace-config.yaml)
      return 0 ;;
    .claude/instructions/manifest.yaml)
      return 0 ;;
    CLAUDE.md|AGENTS.md)
      return 0 ;;
    docs-manager/src/content/docs/specs/design-plans/DP-*)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

is_product_repo_path() {
  local path="$1"
  case "$path" in
    _template/*)
      return 0 ;;
    */polaris-config/*/handbook/*)
      return 0 ;;
    */polaris-config/*/generated-scripts/*)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

FRAMEWORK_HITS=()
FRAMEWORK_TOPICS=()
PRODUCT_PATHS=()
UNCLASSIFIED=()

push_framework_topic() {
  local topic="$1" existing
  for existing in "${FRAMEWORK_TOPICS[@]+"${FRAMEWORK_TOPICS[@]}"}"; do
    [[ "$existing" == "$topic" ]] && return 0
  done
  FRAMEWORK_TOPICS+=("$topic")
}

collect_framework_topics_for_path() {
  local path="$1"

  push_framework_topic ".claude/rules/handbook/framework/index.md"

  case "$path" in
    docs-manager/src/content/docs/specs/design-plans/DP-*|.claude/skills/references/refinement-source-mode.md|.claude/skills/references/breakdown-dp-intake-flow.md|.claude/skills/references/engineering-entry-resolution.md|.claude/skills/framework-release/SKILL.md|.claude/rules/handbook/framework/release-topology.md)
      push_framework_topic ".claude/rules/handbook/framework/release-topology.md"
      ;;
    *)
      ;;
  esac
}

for path in "${CANDIDATES[@]+"${CANDIDATES[@]}"}"; do
  if is_framework_owned "$path"; then
    FRAMEWORK_HITS+=("$path")
    collect_framework_topics_for_path "$path"
  elif is_product_repo_path "$path"; then
    PRODUCT_PATHS+=("$path")
  else
    UNCLASSIFIED+=("$path")
  fi
done

required="false"
if [[ "${#FRAMEWORK_HITS[@]}" -gt 0 ]]; then
  required="true"
fi

# Build JSON arrays manually (no jq dep, no nameref) to remain portable to
# bash 3.2 (macOS). Accept items as positional args.
json_array() {
  local first=1 item escaped
  if [[ "$#" -eq 0 ]]; then
    printf '[]'
    return 0
  fi
  printf '['
  for item in "$@"; do
    escaped="${item//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    if [[ "$first" -eq 1 ]]; then
      first=0
    else
      printf ','
    fi
    printf '"%s"' "$escaped"
  done
  printf ']'
}

{
  printf '{'
  printf '"schema_version":1,'
  printf '"framework_handbook_required":%s,' "$required"
  printf '"framework_handbook_topics":'
  json_array "${FRAMEWORK_TOPICS[@]+"${FRAMEWORK_TOPICS[@]}"}"
  printf ','
  printf '"framework_owned_hits":'
  json_array "${FRAMEWORK_HITS[@]+"${FRAMEWORK_HITS[@]}"}"
  printf ','
  printf '"product_repo_paths":'
  json_array "${PRODUCT_PATHS[@]+"${PRODUCT_PATHS[@]}"}"
  printf ','
  printf '"unclassified":'
  json_array "${UNCLASSIFIED[@]+"${UNCLASSIFIED[@]}"}"
  printf '}\n'
}

if [[ "$MODE" == "diff" && "${#FRAMEWORK_HITS[@]}" -gt 0 ]]; then
  echo "$PREFIX framework-owned surfaces hit; loading .claude/rules/handbook/framework/index.md required." >&2
  for hit in "${FRAMEWORK_HITS[@]}"; do
    printf '  - %s\n' "$hit" >&2
  done
  if [[ "${#FRAMEWORK_TOPICS[@]}" -gt 0 ]]; then
    echo "$PREFIX framework handbook topics:" >&2
    for topic in "${FRAMEWORK_TOPICS[@]}"; do
      printf '  - %s\n' "$topic" >&2
    done
  fi
fi

exit 0
