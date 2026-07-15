#!/usr/bin/env bash
# Purpose: DP-419 T2 D1 deterministic self-referential-DP-delivery classifier.
#          Given a set of a DP's planned-task "Allowed Files" paths, decide
#          deterministically whether the DP is a self-referential delivery gate
#          (its Allowed Files intersect the delivery-gate script set) and emit
#          the matched gate/lane/lib members. Canonical contract:
#          .claude/skills/references/self-referential-dp-delivery.md (D4 script
#          set = manifest kind=gate|hook scripts + the 3 delivery lane
#          entrypoints + the scripts/lib/*.sh those scripts source).
# Inputs:  Allowed Files paths (repo-root-relative or absolute-under-repo-root)
#          via repeatable --allowed-file, positional args, or --stdin
#          (newline-separated). Overrides: --repo-root <dir> (default
#          POLARIS_WORKSPACE_ROOT / git toplevel / script parent),
#          --manifest <path> (default <repo-root>/scripts/manifest.json).
# Outputs: stdout JSON {"self_referential": true|false, "matched": [...]} on
#          exit 0; fail-closed exit 2 + POLARIS_* marker on stderr for missing
#          input / missing tool / missing manifest.
# Side effects: read-only (reads manifest + delivery-gate/lane/lib script files);
#          no writes, no git state change.
#
# Portability: indexed arrays + linear-scan dedup so this runs on bash 3.2
# (macOS default), where `declare -A` is unavailable.

set -euo pipefail

# The single source of the delivery lane entrypoints (D4). These are the
# delivery-flow hooks/gates invoked at push / PR-gate / release time; the
# manifest kind=gate|hook scripts and the scripts/lib/*.sh they source complete
# the script set. Keep this list aligned with self-referential-dp-delivery.md.
LANE_ENTRYPOINTS=(
  ".claude/hooks/pre-push-quality-gate.sh"
  "scripts/check-framework-pr-gate.sh"
  "scripts/framework-release-pr-lane.sh"
)

REPO_ROOT=""
MANIFEST=""
READ_STDIN=0
INPUT_FILES=()

usage() {
  cat <<'USAGE'
Usage: detect-self-referential-delivery.sh [options] [ALLOWED_FILE...]

Classify whether a DP's planned-task Allowed Files make it a self-referential
delivery gate (Allowed Files intersect the delivery-gate script set).

Options:
  --allowed-file <path>  An Allowed File path (repeatable).
  --stdin                Read newline-separated Allowed File paths from stdin.
  --repo-root <dir>      Repo root (default: POLARIS_WORKSPACE_ROOT / git
                         toplevel / script parent dir).
  --manifest <path>      scripts/manifest.json path (default:
                         <repo-root>/scripts/manifest.json).
  -h, --help             Show this help.

Output (stdout, exit 0): {"self_referential": bool, "matched": [paths]}
Fail-closed (exit 2): missing input / missing jq / missing manifest, with a
POLARIS_* marker on stderr.
USAGE
}

# Emit a POLARIS_* structured marker and fail closed (exit 2).
die() {
  echo "$1" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allowed-file)
      [[ $# -ge 2 ]] || die "POLARIS_SELF_REFERENTIAL_BAD_ARGS: --allowed-file requires a value"
      INPUT_FILES+=("$2")
      shift 2
      ;;
    --stdin)
      READ_STDIN=1
      shift
      ;;
    --repo-root)
      [[ $# -ge 2 ]] || die "POLARIS_SELF_REFERENTIAL_BAD_ARGS: --repo-root requires a value"
      REPO_ROOT="$2"
      shift 2
      ;;
    --manifest)
      [[ $# -ge 2 ]] || die "POLARIS_SELF_REFERENTIAL_BAD_ARGS: --manifest requires a value"
      MANIFEST="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do INPUT_FILES+=("$1"); shift; done
      ;;
    -*)
      die "POLARIS_SELF_REFERENTIAL_BAD_ARGS: unknown option $1"
      ;;
    *)
      INPUT_FILES+=("$1")
      shift
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "POLARIS_TOOL_MISSING:jq (install via 'mise install')"

# Resolve repo root: explicit override > POLARIS_WORKSPACE_ROOT > git toplevel >
# script parent dir. Never synthesize; fail closed only on missing manifest.
if [[ -z "$REPO_ROOT" ]]; then
  if [[ -n "${POLARIS_WORKSPACE_ROOT:-}" && -d "${POLARIS_WORKSPACE_ROOT}" ]]; then
    REPO_ROOT="$POLARIS_WORKSPACE_ROOT"
  else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if GIT_TOP="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
      REPO_ROOT="$GIT_TOP"
    else
      REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
    fi
  fi
fi
REPO_ROOT="${REPO_ROOT%/}"
[[ -d "$REPO_ROOT" ]] || die "POLARIS_SELF_REFERENTIAL_REPO_ROOT_MISSING:${REPO_ROOT}"

[[ -n "$MANIFEST" ]] || MANIFEST="${REPO_ROOT}/scripts/manifest.json"
[[ -f "$MANIFEST" ]] || die "POLARIS_SELF_REFERENTIAL_MANIFEST_MISSING:${MANIFEST}"

# Collect stdin input when requested.
if [[ "$READ_STDIN" -eq 1 ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    INPUT_FILES+=("$line")
  done
fi

# Fail closed on missing input (no Allowed Files supplied on any channel).
HAVE_INPUT=0
for f in "${INPUT_FILES[@]+"${INPUT_FILES[@]}"}"; do
  [[ -n "${f// /}" ]] && { HAVE_INPUT=1; break; }
done
[[ "$HAVE_INPUT" -eq 1 ]] || die "POLARIS_SELF_REFERENTIAL_NO_INPUT: no Allowed Files provided (use --allowed-file / positional / --stdin)"

# Normalize a path to repo-root-relative form: trim whitespace, strip a leading
# repo-root prefix (absolute-under-repo-root) and a leading './'.
normalize_path() {
  local p="$1"
  p="${p#"${p%%[![:space:]]*}"}"   # ltrim
  p="${p%"${p##*[![:space:]]}"}"   # rtrim
  [[ -z "$p" ]] && { printf '%s' ""; return; }
  if [[ "$p" == "${REPO_ROOT}/"* ]]; then
    p="${p#"${REPO_ROOT}/"}"
  fi
  p="${p#./}"
  printf '%s' "$p"
}

# --- delivery-gate script set (SET) -----------------------------------------
# Indexed array + linear-scan membership to stay bash-3.2 portable.
SET=()
set_contains() {
  local needle="$1" x
  for x in "${SET[@]+"${SET[@]}"}"; do
    [[ "$x" == "$needle" ]] && return 0
  done
  return 1
}

# Build SET: manifest kind=gate|hook scripts + the 3 lane entrypoints + the
# scripts/lib/*.sh those scripts source (fixed-point over libs too).
build_delivery_gate_set() {
  local base=() p rel file libref libpath
  local queue=() next=() scanned=() s already

  # (1) manifest kind=gate|hook scripts.
  while IFS= read -r p; do
    [[ -n "$p" ]] && base+=("$p")
  done < <(jq -r '.scripts[]? | select(.kind == "gate" or .kind == "hook") | .path' "$MANIFEST")

  # (2) delivery lane entrypoints.
  for p in "${LANE_ENTRYPOINTS[@]}"; do
    base+=("$p")
  done

  for p in "${base[@]+"${base[@]}"}"; do
    set_contains "$p" || SET+=("$p")
  done

  # (3) fixed-point lib expansion: a scripts/lib/*.sh sourced by any member is
  # itself a member (multi-layer self-reference), including libs sourced by libs.
  queue=("${base[@]+"${base[@]}"}")
  while [[ "${#queue[@]}" -gt 0 ]]; do
    next=()
    for rel in "${queue[@]+"${queue[@]}"}"; do
      already=0
      for s in "${scanned[@]+"${scanned[@]}"}"; do
        [[ "$s" == "$rel" ]] && { already=1; break; }
      done
      [[ "$already" -eq 1 ]] && continue
      scanned+=("$rel")
      file="${REPO_ROOT}/${rel}"
      [[ -f "$file" ]] || continue
      while IFS= read -r libref; do
        [[ -n "$libref" ]] || continue
        libpath="scripts/${libref}"
        if [[ -f "${REPO_ROOT}/${libpath}" ]] && ! set_contains "$libpath"; then
          SET+=("$libpath")
          next+=("$libpath")
        fi
      done < <(grep -hoE 'lib/[A-Za-z0-9._-]+\.sh' "$file" 2>/dev/null | sort -u || true)
    done
    queue=("${next[@]+"${next[@]}"}")
  done
}

build_delivery_gate_set

# --- intersect Allowed Files with the delivery-gate set ----------------------
MATCHED=()
matched_contains() {
  local needle="$1" x
  for x in "${MATCHED[@]+"${MATCHED[@]}"}"; do
    [[ "$x" == "$needle" ]] && return 0
  done
  return 1
}
for f in "${INPUT_FILES[@]+"${INPUT_FILES[@]}"}"; do
  norm="$(normalize_path "$f")"
  [[ -z "$norm" ]] && continue
  if set_contains "$norm" && ! matched_contains "$norm"; then
    MATCHED+=("$norm")
  fi
done

# Emit machine-readable JSON via jq (safe escaping, sorted unique matched).
if [[ "${#MATCHED[@]}" -gt 0 ]]; then
  matched_json="$(printf '%s\n' "${MATCHED[@]}" | jq -R . | jq -s '. | sort | unique')"
else
  matched_json='[]'
fi
jq -n --argjson matched "$matched_json" \
  '{self_referential: ($matched | length > 0), matched: $matched}'
