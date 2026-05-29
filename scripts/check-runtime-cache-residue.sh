#!/usr/bin/env bash
# check-runtime-cache-residue.sh — block repo-local runtime cache residue.
#
# Purpose:
#   Scan runtime cache directories for residue files. By default, any file
#   under .polaris/runtime/external-writes/, .codex/external-writes/, or
#   .codex/tmp/ is flagged. When --source-container is provided, derive a
#   source key (DP-NNN / KB2CW-NNN / GT-NNN / KQT-NNN / PR-NNNN,
#   case-insensitive) from the container path basename and apply a scope
#   filter to .polaris/runtime/external-writes/: only flag files whose
#   filename prefix matches the current source key (^{source_key}-,
#   case-insensitive) or files with no recognizable source key prefix
#   (orphan residue). Cross-source residue from parallel sessions is
#   intentionally not flagged. .codex/external-writes/ and .codex/tmp/ are
#   forbidden old-runtime locations and are always flagged regardless of
#   scope. Falls back to workspace-wide flag behavior when no source key
#   can be derived from the container path.
# Inputs:
#   --repo <workspace-root>          (default: ".")
#   --source-container <path>        (optional; enables scope filter)
# Outputs:
#   stdout "PASS: no runtime cache residue" on success; stderr BLOCKED
#   message + residue file list on failure. Exit 0 PASS, 1 residue found,
#   2 contract violation (bad args / missing repo).

set -euo pipefail

repo="."
source_container=""

usage() {
  cat >&2 <<'EOF'
usage: check-runtime-cache-residue.sh [--repo <workspace-root>] [--source-container <path>]

Blocks when temporary runtime cache files remain in:
  .polaris/runtime/external-writes/
  .codex/external-writes/
  .codex/tmp/

When --source-container is provided, .polaris/runtime/external-writes/ residue
is filtered by source key (DP-NNN / KB2CW-NNN / GT-NNN / KQT-NNN / PR-NNNN)
derived from the container path basename; cross-source parallel-session
drafts are not flagged. .codex/** residue is always flagged (forbidden
old-runtime locations) regardless of scope. Without --source-container, or
when no source key can be derived, the gate falls back to workspace-wide
flag behavior.

Durable drafts must be moved to the owning source container, for example:
  {source_container}/jira-comments/
  {source_container}/artifacts/external-writes/
  {source_container}/artifacts/research/
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --source-container)
      source_container="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "check-runtime-cache-residue: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$repo" || ! -d "$repo" ]]; then
  echo "check-runtime-cache-residue: --repo not found: ${repo:-<empty>}" >&2
  exit 2
fi

repo="$(cd "$repo" && pwd)"
if [[ -n "$source_container" ]]; then
  if [[ "$source_container" = /* ]]; then
    source_container_abs="$source_container"
  else
    source_container_abs="$repo/$source_container"
  fi
else
  source_container_abs=""
fi

# Derive source key from source container path basename.
# Pattern: (DP|KB2CW|GT|KQT|PR)-<digits>, case-insensitive.
# Returns empty when no recognizable key can be derived; in that case the
# scope filter is disabled and the script falls back to workspace-wide
# flag behavior on .polaris/runtime/external-writes/.
derive_source_key() {
  local container_path="$1"
  if [[ -z "$container_path" ]]; then
    printf '%s' ''
    return 0
  fi
  local base lower
  base="$(basename "$container_path")"
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" =~ ^(dp|kb2cw|gt|kqt|pr)-([0-9]+) ]]; then
    local prefix="${BASH_REMATCH[1]}"
    local num="${BASH_REMATCH[2]}"
    local upper_prefix
    upper_prefix="$(printf '%s' "$prefix" | tr '[:lower:]' '[:upper:]')"
    printf '%s-%s' "$upper_prefix" "$num"
    return 0
  fi
  printf '%s' ''
}

# Decide whether a .polaris/runtime/external-writes/ filename belongs to the
# current source or should be skipped as cross-source parallel-session draft.
# Returns 0 (flag) when same-source or orphan, 1 (skip) when cross-source.
# Only called when source_key is non-empty.
should_flag_polaris_filename() {
  local filename="$1"
  local source_key="$2"
  local lower_name lower_key
  lower_name="$(printf '%s' "$filename" | tr '[:upper:]' '[:lower:]')"
  lower_key="$(printf '%s' "$source_key" | tr '[:upper:]' '[:lower:]')"

  # Same-source: filename starts with "{source_key}-" (case-insensitive).
  # The trailing hyphen acts as a word boundary so DP-26 does not match
  # filenames starting with dp-261- (avoids substring false positive).
  if [[ "$lower_name" == "${lower_key}-"* ]]; then
    return 0
  fi
  # Cross-source: filename starts with a different recognizable source key
  # (^(dp|kb2cw|gt|kqt|pr)-<digits>-). Skip.
  if [[ "$lower_name" =~ ^(dp|kb2cw|gt|kqt|pr)-[0-9]+- ]]; then
    return 1
  fi
  # Orphan: no recognizable source key prefix; flag (no silent pass).
  return 0
}

source_key=''
if [[ -n "$source_container_abs" ]]; then
  source_key="$(derive_source_key "$source_container_abs")"
fi

scan_dirs=(
  ".polaris/runtime/external-writes"
  ".codex/external-writes"
  ".codex/tmp"
)

residue=()
for rel in "${scan_dirs[@]}"; do
  dir="$repo/$rel"
  [[ -d "$dir" ]] || continue
  while IFS= read -r -d '' path; do
    rel_path="${path#"$repo"/}"
    # Scope filter applies only to .polaris/runtime/external-writes/ and
    # only when a source key was derived. .codex/** is forbidden regardless.
    if [[ -n "$source_key" && "$rel" == ".polaris/runtime/external-writes" ]]; then
      filename="$(basename "$path")"
      if ! should_flag_polaris_filename "$filename" "$source_key"; then
        continue
      fi
    fi
    residue+=("$rel_path")
  done < <(find "$dir" -type f -print0 2>/dev/null)
done

if [[ "${#residue[@]}" -eq 0 ]]; then
  echo "PASS: no runtime cache residue"
  exit 0
fi

cat >&2 <<'EOF'
BLOCKED: runtime cache residue found.

These paths are temporary transport or forbidden old scratch locations. Move
durable content to the owning source container, or delete it if it has no
durable value.
EOF

printf '\nResidue files:\n' >&2
printf '  - %s\n' "${residue[@]}" >&2

if [[ -n "$source_container_abs" ]]; then
  rel_container="${source_container_abs#"$repo"/}"
  cat >&2 <<EOF

Suggested durable destinations under:
  ${rel_container}

  - ${rel_container}/jira-comments/YYYYMMDD-{slug}.md
  - ${rel_container}/artifacts/external-writes/YYYYMMDD-{slug}.md
  - ${rel_container}/artifacts/research/YYYY-MM-DD-{slug}.md
EOF
else
  cat >&2 <<'EOF'

Pass --source-container <path> to print source-specific durable destinations.
EOF
fi

exit 1
