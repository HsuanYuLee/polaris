#!/usr/bin/env bash
# Archive completed spec containers.
#
# Usage:
#   archive-spec.sh [--workspace <path>] [--dry-run] <DP-NNN|TICKET|spec-path>
#   archive-spec.sh [--workspace <path>] --sweep --dry-run
#   archive-spec.sh [--workspace <path>] --sweep --apply
#
# Moves:
#   specs/design-plans/DP-NNN-*         -> specs/design-plans/archive/DP-NNN-*
#   specs/companies/{company}/{TICKET}  -> specs/companies/{company}/archive/{TICKET}
#
# Only parent specs with status IMPLEMENTED or ABANDONED may be archived.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY_RUN=0
APPLY=0
SWEEP=0
SOURCE=""

usage() {
  sed -n '2,21p' "$0" >&2
}

abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
  fi
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

frontmatter_status() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk -F ':' '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && /^status:/ {
      sub(/^[[:space:]]+/, "", $2)
      print $2
      exit
    }
  ' "$file"
}

rel_path() {
  local path="$1"
  printf '%s\n' "${path#"$WORKSPACE_ROOT"/}"
}

resolve_dp_by_id() {
  local dp_id="$1"
  local -a matches=()
  local match=""

  while IFS= read -r -d '' match; do
    matches+=("$match")
  done < <(find "$WORKSPACE_ROOT/specs/design-plans" -maxdepth 1 -type d -name "${dp_id}-*" -print0 2>/dev/null)

  [[ ${#matches[@]} -gt 0 ]] || fail "no active design plan found for ${dp_id}"
  [[ ${#matches[@]} -eq 1 ]] || {
    printf 'ERROR: %s resolved to multiple active design plans:\n' "$dp_id" >&2
    printf '  %s\n' "${matches[@]}" >&2
    exit 1
  }
  printf '%s\n' "${matches[0]}"
}

resolve_ticket_by_key() {
  local ticket="$1"
  local -a matches=()
  local company_dir=""

  for company_dir in "$WORKSPACE_ROOT"/specs/companies/*/; do
    [[ -d "$company_dir" ]] || continue
    [[ "$(basename "$company_dir")" == "archive" ]] && continue
    if [[ -d "${company_dir}${ticket}" ]]; then
      matches+=("${company_dir}${ticket}")
    fi
  done

  [[ ${#matches[@]} -gt 0 ]] || fail "no active company spec found for ${ticket}"
  [[ ${#matches[@]} -eq 1 ]] || {
    printf 'ERROR: %s resolved to multiple active company specs:\n' "$ticket" >&2
    printf '  %s\n' "${matches[@]}" >&2
    exit 1
  }
  printf '%s\n' "${matches[0]}"
}

resolve_direct_path() {
  local input="$1"
  local path container rel

  [[ -e "$input" ]] || fail "path not found: $input"
  path="$(abs_path "$input")"
  if [[ -f "$path" ]]; then
    path="$(dirname "$path")"
  fi

  case "$path" in
    "$WORKSPACE_ROOT"/specs/design-plans/archive/*|"$WORKSPACE_ROOT"/specs/companies/*/archive/*)
      fail "spec is already archived: $path"
      ;;
  esac

  rel="${path#"$WORKSPACE_ROOT"/}"
  case "$rel" in
    specs/design-plans/DP-[0-9][0-9][0-9]-*|specs/design-plans/DP-[0-9][0-9][0-9]-*/*)
      container="$WORKSPACE_ROOT/$(printf '%s\n' "$rel" | awk -F/ '{print $1 "/" $2 "/" $3}')"
      ;;
    specs/companies/*/*|specs/companies/*/*/*)
      container="$WORKSPACE_ROOT/$(printf '%s\n' "$rel" | awk -F/ '{print $1 "/" $2 "/" $3 "/" $4}')"
      ;;
    *)
      fail "path is not inside an active spec container: $input"
      ;;
  esac

  [[ -d "$container" ]] || fail "resolved container is not a directory: $container"
  printf '%s\n' "$container"
}

metadata_for_container() {
  local container="$1"
  local kind="" anchor="" destination="" company="" status=""

  case "$container" in
    "$WORKSPACE_ROOT"/specs/design-plans/archive/*|"$WORKSPACE_ROOT"/specs/companies/*/archive/*)
      fail "spec is already archived: $container"
      ;;
  esac

  case "$container" in
    "$WORKSPACE_ROOT"/specs/design-plans/DP-[0-9][0-9][0-9]-*)
      kind="dp"
      anchor="$container/plan.md"
      destination="$WORKSPACE_ROOT/specs/design-plans/archive/$(basename "$container")"
      ;;
    "$WORKSPACE_ROOT"/specs/companies/*/*)
      kind="company"
      if [[ -f "$container/refinement.md" ]]; then
        anchor="$container/refinement.md"
      else
        anchor="$container/plan.md"
      fi
      company="$(basename "$(dirname "$container")")"
      destination="$WORKSPACE_ROOT/specs/companies/$company/archive/$(basename "$container")"
      ;;
    *)
      fail "unsupported spec container: $container"
      ;;
  esac

  [[ ! -e "$destination" ]] || fail "archive destination already exists: $destination"
  if [[ -f "$anchor" ]]; then
    status="$(frontmatter_status "$anchor")"
  fi

  printf '%s|%s|%s|%s\n' "$kind" "$anchor" "$status" "$destination"
}

sweep_containers() {
  local path="" company_dir=""

  if [[ -d "$WORKSPACE_ROOT/specs/design-plans" ]]; then
    while IFS= read -r -d '' path; do
      printf '%s\n' "$path"
    done < <(find "$WORKSPACE_ROOT/specs/design-plans" -maxdepth 1 -type d -name 'DP-[0-9][0-9][0-9]-*' -print0 2>/dev/null)
  fi

  if [[ -d "$WORKSPACE_ROOT/specs/companies" ]]; then
    for company_dir in "$WORKSPACE_ROOT"/specs/companies/*; do
      [[ -d "$company_dir" ]] || continue
      [[ "$(basename "$company_dir")" == "archive" ]] && continue
      while IFS= read -r -d '' path; do
        [[ "$(basename "$path")" == "archive" ]] && continue
        printf '%s\n' "$path"
      done < <(find "$company_dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
    done
  fi

  return 0
}

sweep_report() {
  local container="" kind="" anchor="" status="" destination=""
  local action="" reason="" source_rel="" destination_rel=""

  printf 'TYPE\tSTATUS\tACTION\tSOURCE\tDESTINATION\tREASON\n'
  while IFS= read -r container; do
    [[ -n "$container" ]] || continue
    IFS='|' read -r kind anchor status destination < <(metadata_for_container "$container")
    source_rel="$(rel_path "$container")"
    destination_rel="$(rel_path "$destination")"

    case "$status" in
      IMPLEMENTED|ABANDONED)
        action="archive"
        reason="terminal status"
        ;;
      "")
        action="skip"
        if [[ -f "$anchor" ]]; then
          reason="missing status"
        else
          reason="missing parent anchor"
        fi
        ;;
      *)
        action="skip"
        reason="non-terminal status"
        ;;
    esac

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "${status:-MISSING}" "$action" "$source_rel" "$destination_rel" "$reason"
  done < <(sweep_containers)

  return 0
}

run_sweep() {
  local mode="$1"
  local report_file="" line="" kind="" status="" action="" source_rel="" destination_rel="" reason=""
  local source_abs="" destination_abs="" moved=0

  report_file="$(mktemp -t archive-spec-sweep.XXXXXX)"
  trap 'rm -f "$report_file"' RETURN

  sweep_report >"$report_file"
  cat "$report_file"

  [[ "$mode" == "apply" ]] || return 0

  while IFS=$'\t' read -r kind status action source_rel destination_rel reason; do
    [[ "$kind" == "TYPE" ]] && continue
    [[ "$action" == "archive" ]] || continue
    source_abs="$WORKSPACE_ROOT/$source_rel"
    destination_abs="$WORKSPACE_ROOT/$destination_rel"
    [[ -d "$source_abs" ]] || fail "sweep source disappeared before apply: $source_abs"
    [[ ! -e "$destination_abs" ]] || fail "archive destination already exists: $destination_abs"
    mkdir -p "$(dirname "$destination_abs")"
    mv "$source_abs" "$destination_abs"
    echo "ARCHIVED: $source_rel -> $destination_rel"
    moved=$((moved + 1))
  done <"$report_file"

  if [[ "$moved" -gt 0 ]]; then
    sync_hook="$WORKSPACE_ROOT/scripts/docs-viewer-sync-hook.sh"
    if [[ -x "$sync_hook" ]]; then
      "$sync_hook" "$WORKSPACE_ROOT" "$WORKSPACE_ROOT/specs" >/dev/null 2>&1 || true
    fi
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      WORKSPACE_ROOT="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    --sweep)
      SWEEP=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$SOURCE" ]]; then
        SOURCE="$1"
        shift
      else
        fail "unexpected argument: $1"
      fi
      ;;
  esac
done

[[ -d "$WORKSPACE_ROOT" ]] || fail "workspace not found: $WORKSPACE_ROOT"
WORKSPACE_ROOT="$(cd "$WORKSPACE_ROOT" && pwd)"

if [[ "$SWEEP" -eq 1 ]]; then
  [[ -z "$SOURCE" ]] || fail "--sweep does not accept a source argument"
  if [[ "$DRY_RUN" -eq 1 && "$APPLY" -eq 1 ]]; then
    fail "--sweep accepts only one of --dry-run or --apply"
  fi
  if [[ "$APPLY" -eq 1 ]]; then
    run_sweep "apply"
  elif [[ "$DRY_RUN" -eq 1 ]]; then
    run_sweep "dry-run"
  else
    fail "--sweep requires --dry-run or --apply"
  fi
  exit 0
fi

[[ "$APPLY" -eq 0 ]] || fail "--apply is only valid with --sweep"
[[ -n "$SOURCE" ]] || { usage; exit 2; }

container=""
if [[ "$SOURCE" =~ ^DP-[0-9]{3}$ ]]; then
  container="$(resolve_dp_by_id "$SOURCE")"
elif [[ "$SOURCE" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
  container="$(resolve_ticket_by_key "$SOURCE")"
else
  container="$(resolve_direct_path "$SOURCE")"
fi

IFS='|' read -r kind anchor status destination < <(metadata_for_container "$container")

[[ -f "$anchor" ]] || fail "parent anchor not found for ${kind} spec: $anchor"
case "$status" in
  IMPLEMENTED|ABANDONED) ;;
  "")
    fail "cannot archive $(basename "$container"): missing status in $anchor"
    ;;
  *)
    fail "cannot archive $(basename "$container"): status must be IMPLEMENTED or ABANDONED (got $status)"
    ;;
esac

[[ ! -e "$destination" ]] || fail "archive destination already exists: $destination"

archive_parent="$(dirname "$destination")"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY-RUN: would archive $container -> $destination"
  exit 0
fi

mkdir -p "$archive_parent"
mv "$container" "$destination"
echo "ARCHIVED: $container -> $destination"

sync_hook="$WORKSPACE_ROOT/scripts/docs-viewer-sync-hook.sh"
if [[ -x "$sync_hook" ]]; then
  "$sync_hook" "$WORKSPACE_ROOT" "$destination" >/dev/null 2>&1 || true
fi
