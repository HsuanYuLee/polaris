#!/usr/bin/env bash
# Purpose: Hold a source to the destination its human declared at freeze time.
# Inputs:  --source <dir> (a sources/* directory), --changed <path> (repeatable;
#          defaults to the staged file list).
# Outputs: exit 0 when the changes respect the declaration; exit 1 otherwise.
#
# Where a source's output is allowed to land is a human decision, taken once, at
# the one gate a human actually attends. Recording it turns "is this a company
# leak?" from a content question answered by pattern-guessing into a path
# question answered by reading the declaration.
#
# For destination: workspace this checks a deliberately small safe subset rather
# than modelling the whole sync set. sync-to-polaris.sh copies through explicitly
# named steps whose labels are not paths, so the full set cannot be derived
# cheaply or without drift. An unrecognised path therefore fails rather than
# passes: over-restrictive, never over-permissive.

set -euo pipefail

SOURCE_DIR=""
CHANGED=()

die() {
  # Description: print a POLARIS marker plus context to stderr and exit 1.
  # Args: $1 = marker, $2.. = message lines
  local marker="$1"
  shift
  echo "$marker" >&2
  printf '%s\n' "$@" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)  SOURCE_DIR="${2:-}"; shift 2 ;;
    --changed) CHANGED+=("${2:-}"); shift 2 ;;
    -h|--help)
      echo "Usage: check-source-destination.sh --source <dir> [--changed <path>]..." >&2
      exit 2
      ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$SOURCE_DIR" ]] || die "POLARIS_SOURCE_DESTINATION_USAGE" \
  "--source is required"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
INDEX="$SOURCE_DIR/index.md"
[[ -f "$INDEX" ]] || die "POLARIS_SOURCE_DESTINATION_NO_INDEX" \
  "no index.md under $SOURCE_DIR"

# Frontmatter only: a `destination:` further down the body is prose, not a
# declaration, and must not be mistaken for one.
destination="$(awk '
  NR == 1 && $0 == "---" { inside = 1; next }
  inside && $0 == "---"   { exit }
  inside && /^destination:[[:space:]]*/ {
    sub(/^destination:[[:space:]]*/, "")
    gsub(/[[:space:]]*(#.*)?$/, "")
    print
    exit
  }
' "$INDEX")"

[[ -n "$destination" ]] || die "POLARIS_SOURCE_DESTINATION_MISSING" \
  "$INDEX declares no destination." \
  "" \
  "Add one to the frontmatter. It is required, not optional: a source without a" \
  "declared destination is exactly the silent third state this check exists to" \
  "remove." \
  "" \
  "  destination: workspace   # stays here; never reaches the template repo" \
  "  destination: template    # ships to the Polaris template repo"

case "$destination" in
  workspace|template) ;;
  *) die "POLARIS_SOURCE_DESTINATION_INVALID" \
       "unknown destination '$destination' in $INDEX (expected workspace or template)" ;;
esac

if [[ ${#CHANGED[@]} -eq 0 ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && CHANGED+=("$line")
  done < <(git -C "$ROOT" diff --cached --name-only 2>/dev/null || true)
fi

if [[ "$destination" == "template" ]]; then
  # Template-bound output may live anywhere that syncs; whether its *content* is
  # generic enough is scan-template-leaks.sh's question, not this one.
  echo "PASS: $SOURCE_DIR declares destination=template; no path restriction applies"
  exit 0
fi

# Company directories are the ones carrying their own workspace-config.yaml —
# the same rule sync-to-polaris.sh uses to decide what to exclude.
companies=()
for candidate in "$ROOT"/*/; do
  name="$(basename "$candidate")"
  [[ -f "$candidate/workspace-config.yaml" ]] && companies+=("$name")
done

is_workspace_only() {
  # Description: decide whether a path is certain never to reach the template.
  # Args: $1 = repo-relative path
  # Returns: 0 when the path is provably workspace-only, 1 when unknown.
  local path="$1"

  # Ignored files are not tracked, and sync copies from the tracked tree.
  git -C "$ROOT" check-ignore -q "$path" 2>/dev/null && return 0

  case "$path" in
    sources/*) return 0 ;;
  esac

  local company
  for company in "${companies[@]:-}"; do
    case "$path" in
      "$company"/*) return 0 ;;
      .claude/skills/"$company"/*) return 0 ;;
      .claude/rules/"$company"/*) return 0 ;;
    esac
  done

  # A maintainer-only skill is skipped by sync's own frontmatter check.
  if [[ "$path" == .claude/skills/*/SKILL.md ]]; then
    grep -q 'scope:.*maintainer-only' "$ROOT/$path" 2>/dev/null && return 0
  fi

  return 1
}

offenders=()
for path in "${CHANGED[@]:-}"; do
  [[ -n "$path" ]] || continue
  is_workspace_only "$path" || offenders+=("$path")
done

if [[ ${#offenders[@]} -gt 0 ]]; then
  {
    echo "POLARIS_SOURCE_DESTINATION_ESCAPE"
    echo "$SOURCE_DIR declares destination=workspace, but these paths are not"
    echo "provably workspace-only and may sync to the template repo:"
    echo
    printf '  %s\n' "${offenders[@]}"
    echo
    echo "Two ways out:"
    echo "  1. Move the file somewhere that never syncs — a company-scoped skill"
    echo "     (.claude/skills/{company}/), a company rule dir, or sources/."
    echo "  2. Change the declaration to destination: template, and make the"
    echo "     content generic. That is a human decision; re-freeze it."
  } >&2
  exit 1
fi

echo "PASS: $SOURCE_DIR declares destination=workspace; all ${#CHANGED[@]} changed path(s) stay here"
