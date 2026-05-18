#!/usr/bin/env bash
# Backfill frontmatter for D2 transport artifacts under specs artifacts/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"

usage() {
  cat >&2 <<'USAGE'
usage: migrate-specs-artifact-frontmatter.sh [--workspace <path>] [--report <path>] [--dry-run]

Scans artifacts/external-writes/**/*.md and artifacts/research/**/*.md under the
resolved specs root. Missing metadata is inferred from path and filename.
Files that cannot be inferred are listed in manual-fix-required.txt and are not
modified with placeholder metadata.
USAGE
}

workspace_root=""
report_path=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      workspace_root="${2:-}"
      [[ -n "$workspace_root" ]] || { usage; exit 2; }
      shift 2
      ;;
    --report)
      report_path="${2:-}"
      [[ -n "$report_path" ]] || { usage; exit 2; }
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

workspace_root="$(resolve_specs_workspace_root "${workspace_root:-$(pwd)}")"
specs_root="$(resolve_specs_root "$workspace_root")"

if [[ -z "$report_path" ]]; then
  report_path="$workspace_root/.polaris/evidence/specs-artifact-frontmatter/manual-fix-required.txt"
fi
mkdir -p "$(dirname "$report_path")"
: >"$report_path"

artifact_type_for_path() {
  case "$1" in
    */artifacts/external-writes/*) printf 'external-write\n' ;;
    */artifacts/research/*) printf 'research-snapshot\n' ;;
    *) return 1 ;;
  esac
}

source_for_path() {
  local rel="$1"
  case "$rel" in
    design-plans/*)
      printf '%s\n' "$rel" | grep -Eo 'DP-[0-9]{3}' | head -1 || return 1
      ;;
    companies/*/*)
      printf '%s\n' "$rel" | tr '/' '\n' | grep -E '^[A-Z][A-Z0-9]*-[0-9]+$' | head -1 || return 1
      ;;
    *)
      return 1
      ;;
  esac
}

created_for_file() {
  local base="$1"
  if [[ "$base" =~ ([0-9]{4})-([0-9]{2})-([0-9]{2}) ]]; then
    printf '%s-%s-%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    return 0
  fi
  if [[ "$base" =~ ([0-9]{4})([0-9]{2})([0-9]{2}) ]]; then
    printf '%s-%s-%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    return 0
  fi
  return 1
}

created_for_anchor() {
  local rel="$1"
  local container="" anchor=""
  case "$rel" in
    design-plans/archive/DP-[0-9][0-9][0-9]-*/*)
      container="$specs_root/design-plans/archive/$(printf '%s\n' "$rel" | awk -F/ '{print $3}')"
      ;;
    design-plans/DP-[0-9][0-9][0-9]-*/*)
      container="$specs_root/design-plans/$(printf '%s\n' "$rel" | awk -F/ '{print $2}')"
      ;;
    companies/*/archive/*/*)
      container="$specs_root/companies/$(printf '%s\n' "$rel" | awk -F/ '{print $2 "/archive/" $4}')"
      ;;
    companies/*/*/*)
      container="$specs_root/companies/$(printf '%s\n' "$rel" | awk -F/ '{print $2 "/" $3}')"
      ;;
    *)
      return 1
      ;;
  esac
  for anchor in "$container/index.md" "$container/plan.md" "$container/refinement.md"; do
    [[ -f "$anchor" ]] || continue
    awk -F: '
      NR == 1 && $0 == "---" { in_fm = 1; next }
      in_fm && $0 == "---" { exit }
      in_fm && /^created:/ {
        value = $0
        sub(/^created:[[:space:]]*/, "", value)
        gsub(/["'\'']/, "", value)
        print value
        found = 1
        exit
      }
      END { exit(found ? 0 : 1) }
    ' "$anchor" && return 0
  done
  return 1
}

has_key() {
  local file="$1" key="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && $0 ~ "^" key "[[:space:]]*:" { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$file"
}

has_frontmatter() {
  [[ "$(head -n 1 "$1" 2>/dev/null || true)" == "---" ]]
}

insert_frontmatter() {
  local file="$1" artifact_type="$2" source="$3" created="$4"
  local tmp
  tmp="$(mktemp -t specs-artifact-frontmatter.XXXXXX)"
  if has_frontmatter "$file"; then
    awk -v artifact_type="$artifact_type" -v source="$source" -v created="$created" '
      BEGIN { inserted = 0 }
      NR == 1 && $0 == "---" { print; in_fm = 1; next }
      in_fm && $0 == "---" && !inserted {
        print "artifact_type: " artifact_type
        print "source: " source
        print "created: " created
        inserted = 1
        print
        next
      }
      { print }
    ' "$file" >"$tmp"
  else
    {
      printf '%s\n' '---'
      printf 'artifact_type: %s\n' "$artifact_type"
      printf 'source: %s\n' "$source"
      printf 'created: %s\n' "$created"
      printf '%s\n' '---'
      cat "$file"
    } >"$tmp"
  fi
  mv "$tmp" "$file"
}

changed=0
manual=0

while IFS= read -r -d '' file; do
  rel="${file#"$specs_root"/}"
  artifact_type="$(artifact_type_for_path "$rel" || true)"
  source="$(source_for_path "$rel" || true)"
  created="$(created_for_file "$(basename "$file")" || created_for_file "$(dirname "$rel")" || created_for_anchor "$rel" || true)"

  if [[ -z "$artifact_type" || -z "$source" || -z "$created" ]]; then
    printf '%s\tartifact_type=%s\tsource=%s\tcreated=%s\n' "$rel" "${artifact_type:-MISSING}" "${source:-MISSING}" "${created:-MISSING}" >>"$report_path"
    manual=$((manual + 1))
    continue
  fi

  if has_key "$file" artifact_type && has_key "$file" source && has_key "$file" created; then
    continue
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    printf 'WOULD_UPDATE\t%s\n' "$rel"
  else
    insert_frontmatter "$file" "$artifact_type" "$source" "$created"
  fi
  changed=$((changed + 1))
done < <(find "$specs_root" \( -path '*/artifacts/external-writes/*.md' -o -path '*/artifacts/research/*.md' \) -type f -print0 2>/dev/null)

if [[ "$manual" -gt 0 ]]; then
  printf 'MANUAL_REQUIRED: %s file(s); report: %s\n' "$manual" "$report_path" >&2
  exit 1
fi

printf 'PASS: specs artifact frontmatter migration changed=%s report=%s\n' "$changed" "$report_path"
