#!/usr/bin/env bash
# Validate docs-manager specs collection shape.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"

usage() {
  cat >&2 <<'USAGE'
usage: validate-specs-collection-shape.sh [--workspace <path>] --all
       validate-specs-collection-shape.sh [--workspace <path>] <file-or-dir>...

Validates markdown under docs-manager/src/content/docs/specs:
- docs collection pages require frontmatter title + description
- D2 transport markdown under artifacts/external-writes/ and artifacts/research/ require
  artifact_type + source + created
- existing sidecars under jira-comments/, escalations/, refinement-inbox/, tests/ are skipped
USAGE
}

workspace_root=""
mode_all=0
paths=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      workspace_root="${2:-}"
      [[ -n "$workspace_root" ]] || { usage; exit 2; }
      shift 2
      ;;
    --all)
      mode_all=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      paths+=("$1")
      shift
      ;;
  esac
done

if [[ "$mode_all" -eq 0 && ${#paths[@]} -eq 0 ]]; then
  usage
  exit 2
fi

specs_root="$(resolve_specs_root "$workspace_root")"
workspace_root="$(resolve_specs_workspace_root "${workspace_root:-$(pwd)}")"

is_markdown() {
  case "$1" in
    *.md|*.mdx|*.markdown|*.mdown|*.mkdn|*.mkd|*.mdwn) return 0 ;;
    *) return 1 ;;
  esac
}

rel_to_specs() {
  local path="$1"
  local abs
  if [[ "$path" = /* ]]; then
    abs="$path"
  else
    abs="$workspace_root/$path"
  fi
  case "$abs" in
    "$specs_root"/*) printf '%s\n' "${abs#"$specs_root"/}" ;;
    *) return 1 ;;
  esac
}

has_frontmatter_key() {
  local file="$1" key="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && $0 ~ "^" key "[[:space:]]*:" {
      value = $0
      sub("^[^:]+:[[:space:]]*", "", value)
      if (value != "") found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "$file"
}

is_excluded_sidecar() {
  case "$1" in
    */jira-comments/*|jira-comments/*|*/escalations/*|escalations/*|*/refinement-inbox/*|refinement-inbox/*|*/tests/*|tests/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_d2_transport() {
  case "$1" in
    */artifacts/external-writes/*.md|artifacts/external-writes/*.md|*/artifacts/research/*.md|artifacts/research/*.md)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_file() {
  local file="$1"
  local rel="$2"
  local errors=0

  is_markdown "$file" || return 0

  if is_excluded_sidecar "$rel"; then
    return 0
  fi

  if is_d2_transport "$rel"; then
    for key in artifact_type source created; do
      if ! has_frontmatter_key "$file" "$key"; then
        printf 'ERROR: D2 transport artifact missing `%s`: %s\n' "$key" "$rel" >&2
        errors=$((errors + 1))
      fi
    done
    return "$errors"
  fi

  for key in title description; do
    if ! has_frontmatter_key "$file" "$key"; then
      printf 'ERROR: docs collection page missing `%s`: %s\n' "$key" "$rel" >&2
      errors=$((errors + 1))
    fi
  done
  return "$errors"
}

collect_files() {
  if [[ "$mode_all" -eq 1 ]]; then
    find "$specs_root" -type f \( -name '*.md' -o -name '*.mdx' -o -name '*.markdown' -o -name '*.mdown' -o -name '*.mkdn' -o -name '*.mkd' -o -name '*.mdwn' \) -print
    return 0
  fi

  local input abs
  for input in "${paths[@]}"; do
    if [[ "$input" = /* ]]; then
      abs="$input"
    else
      abs="$workspace_root/$input"
    fi
    [[ -e "$abs" ]] || {
      printf 'ERROR: path not found: %s\n' "$input" >&2
      return 1
    }
    if [[ -d "$abs" ]]; then
      find "$abs" -type f \( -name '*.md' -o -name '*.mdx' -o -name '*.markdown' -o -name '*.mdown' -o -name '*.mkdn' -o -name '*.mkd' -o -name '*.mdwn' \) -print
    else
      printf '%s\n' "$abs"
    fi
  done
}

tmp_files="$(mktemp -t validate-specs-collection-shape.XXXXXX)"
trap 'rm -f "$tmp_files"' EXIT

collect_files >"$tmp_files"

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_specs_collection_shape_1.py" "$specs_root" "$tmp_files"

echo "PASS: specs collection shape"
