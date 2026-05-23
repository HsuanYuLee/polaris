#!/usr/bin/env bash
# scripts/spec-source-resolver.sh
#
# Polaris shared source resolver — auto-pass / breakdown / lifecycle 共用的
# source resolution authority。把 `spec-source-resolver.md` reference 落成
# deterministic helper。
#
# 輸入：
#   --source-id <DP-NNN|JIRA-KEY>
#   --artifact-path <abs path>
#   --specs-root <path>   override（selftest 用；fall back 到 resolve-specs-root.sh）
#   --include-archive     archive 命名空間也納入 lookup
#   --json                明示輸出 JSON（預設即為 JSON）
#
# 輸出：JSON to stdout
#   {
#     "source_type":   "dp" | "jira",
#     "source_id":     "DP-228" | "EXAMPLE-556" | ...,
#     "container":     "<abs path to spec folder>",
#     "primary_doc":   "<abs path to index.md|plan.md|refinement.md>",
#     "refinement_md": "<abs path or empty>",
#     "refinement_json": "<abs path or empty>",
#     "status":        "<frontmatter status or empty>",
#     "archived":      true | false,
#     "readiness":     [ "archived-read-only" | "missing-refinement-md" | ... ]
#   }
#
# Exit codes：
#   0   resolved（含 archived read-only）
#   2   duplicate match            → stderr POLARIS_SOURCE_DUPLICATE
#   2   no match                   → stderr POLARIS_SOURCE_MISSING
#   2   invalid input / usage      → stderr POLARIS_SOURCE_INVALID
#   1   internal error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"

usage() {
  cat >&2 <<'USAGE'
usage:
  spec-source-resolver.sh --source-id <DP-NNN|JIRA-KEY> [options]
  spec-source-resolver.sh --artifact-path <abs path>     [options]

options:
  --specs-root <path>     override specs root（selftest fixture 用）
  --include-archive       active + archive 同時 lookup（預設只看 active）
  --json                  顯式宣告 JSON 輸出（預設即 JSON）

exit:
  0   resolved (active 或 archive read-only)
  2   duplicate / missing / invalid input（stderr 含 POLARIS_SOURCE_* code）
  1   internal error
USAGE
}

err_code() {
  local code="$1" msg="$2"
  printf '%s: %s\n' "$code" "$msg" >&2
}

fail_invalid() { err_code "POLARIS_SOURCE_INVALID" "$1"; exit 2; }
fail_missing() { err_code "POLARIS_SOURCE_MISSING" "$1"; exit 2; }
fail_dup()     { err_code "POLARIS_SOURCE_DUPLICATE" "$1"; exit 2; }

#####################################
# Arg parsing
#####################################
SOURCE_ID=""
ARTIFACT_PATH=""
SPECS_ROOT_OVERRIDE=""
INCLUDE_ARCHIVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-id)
      SOURCE_ID="${2:-}"
      [[ -n "$SOURCE_ID" ]] || { usage; exit 2; }
      shift 2
      ;;
    --artifact-path)
      ARTIFACT_PATH="${2:-}"
      [[ -n "$ARTIFACT_PATH" ]] || { usage; exit 2; }
      shift 2
      ;;
    --specs-root)
      SPECS_ROOT_OVERRIDE="${2:-}"
      [[ -n "$SPECS_ROOT_OVERRIDE" ]] || { usage; exit 2; }
      shift 2
      ;;
    --include-archive)
      INCLUDE_ARCHIVE=1
      shift
      ;;
    --json)
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

if [[ -n "$SOURCE_ID" && -n "$ARTIFACT_PATH" ]]; then
  fail_invalid "use either --source-id or --artifact-path, not both"
fi

if [[ -z "$SOURCE_ID" && -z "$ARTIFACT_PATH" ]]; then
  fail_invalid "missing input: --source-id or --artifact-path required"
fi

#####################################
# Resolve specs root
#####################################
if [[ -n "$SPECS_ROOT_OVERRIDE" ]]; then
  SPECS_ROOT="$(cd "$SPECS_ROOT_OVERRIDE" 2>/dev/null && pwd)" \
    || fail_invalid "specs root not a directory: $SPECS_ROOT_OVERRIDE"
else
  SPECS_ROOT="$(resolve_specs_root)" || { printf 'unable to resolve specs root\n' >&2; exit 1; }
fi

abs_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    printf '%s\n' "$p"
  else
    printf '%s\n' "$(cd "$(dirname "$p")" 2>/dev/null && pwd)/$(basename "$p")"
  fi
}

#####################################
# Frontmatter status extractor
#####################################
frontmatter_status() {
  local file="$1"
  [[ -f "$file" ]] || { printf '\n'; return 0; }
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

#####################################
# Classify path → archived?
#####################################
is_archive_path() {
  local p="$1"
  case "$p" in
    "$SPECS_ROOT"/design-plans/archive/*|"$SPECS_ROOT"/companies/*/archive/*)
      return 0
      ;;
  esac
  return 1
}

#####################################
# Locate DP container by id
#####################################
locate_dp() {
  local dp_id="$1"
  local -a active=() archived=()
  local match=""

  if [[ -d "$SPECS_ROOT/design-plans" ]]; then
    while IFS= read -r -d '' match; do
      active+=("$match")
    done < <(find "$SPECS_ROOT/design-plans" -maxdepth 1 -type d -name "${dp_id}-*" -print0 2>/dev/null)
  fi

  if [[ -d "$SPECS_ROOT/design-plans/archive" ]]; then
    while IFS= read -r -d '' match; do
      archived+=("$match")
    done < <(find "$SPECS_ROOT/design-plans/archive" -maxdepth 1 -type d -name "${dp_id}-*" -print0 2>/dev/null)
  fi

  # Duplicate detection（先檢查 active）
  if [[ "${#active[@]}" -gt 1 ]]; then
    printf 'active dp matches: %s\n' "${active[*]}" >&2
    fail_dup "$dp_id resolved to multiple active design plans"
  fi
  if [[ "${#archived[@]}" -gt 1 ]]; then
    printf 'archived dp matches: %s\n' "${archived[*]}" >&2
    fail_dup "$dp_id resolved to multiple archived design plans"
  fi
  if [[ "${#active[@]}" -ge 1 && "${#archived[@]}" -ge 1 ]]; then
    printf 'active vs archive collision: active=%s archive=%s\n' "${active[0]}" "${archived[0]}" >&2
    fail_dup "$dp_id exists in both active and archive namespaces"
  fi

  if [[ "${#active[@]}" -eq 1 ]]; then
    printf '%s\t%s\n' "active" "${active[0]}"
    return 0
  fi
  if [[ "${#archived[@]}" -eq 1 ]]; then
    if [[ "$INCLUDE_ARCHIVE" -eq 1 ]]; then
      printf '%s\t%s\n' "archive" "${archived[0]}"
      return 0
    fi
    # 直接給 source id 時，沒帶 --include-archive 的 archive-only 仍 fail missing；
    # 直接給 archive path 才會 archived read-only。
    fail_missing "no active design plan found for $dp_id (archive: ${archived[0]})"
  fi
  fail_missing "no design plan found for $dp_id"
}

#####################################
# Locate JIRA / company container by key
#####################################
locate_jira() {
  local ticket="$1"
  local -a active=() archived=()
  local company_dir=""

  if [[ -d "$SPECS_ROOT/companies" ]]; then
    for company_dir in "$SPECS_ROOT"/companies/*/; do
      [[ -d "$company_dir" ]] || continue
      local base
      base="$(basename "$company_dir")"
      [[ "$base" == "archive" ]] && continue
      if [[ -d "${company_dir}${ticket}" ]]; then
        active+=("${company_dir%/}/${ticket}")
      fi
      if [[ -d "${company_dir}archive/${ticket}" ]]; then
        archived+=("${company_dir%/}/archive/${ticket}")
      fi
    done
  fi

  if [[ "${#active[@]}" -gt 1 ]]; then
    printf 'active jira matches: %s\n' "${active[*]}" >&2
    fail_dup "$ticket resolved to multiple active company specs"
  fi
  if [[ "${#archived[@]}" -gt 1 ]]; then
    printf 'archived jira matches: %s\n' "${archived[*]}" >&2
    fail_dup "$ticket resolved to multiple archived company specs"
  fi
  if [[ "${#active[@]}" -ge 1 && "${#archived[@]}" -ge 1 ]]; then
    printf 'active vs archive collision: active=%s archive=%s\n' "${active[0]}" "${archived[0]}" >&2
    fail_dup "$ticket exists in both active and archive namespaces"
  fi

  if [[ "${#active[@]}" -eq 1 ]]; then
    printf '%s\t%s\n' "active" "${active[0]}"
    return 0
  fi
  if [[ "${#archived[@]}" -eq 1 ]]; then
    if [[ "$INCLUDE_ARCHIVE" -eq 1 ]]; then
      printf '%s\t%s\n' "archive" "${archived[0]}"
      return 0
    fi
    fail_missing "no active company spec found for $ticket (archive: ${archived[0]})"
  fi
  fail_missing "no company spec found for $ticket"
}

#####################################
# Resolve direct artifact path → container + namespace
#####################################
resolve_direct_artifact_path() {
  local input="$1"
  local path archived_flag namespace rel container

  path="$(abs_path "$input")"
  [[ -e "$path" ]] || fail_missing "artifact path not found: $input"
  if [[ -f "$path" ]]; then
    path="$(dirname "$path")"
  fi
  path="$(cd "$path" && pwd)"

  if is_archive_path "$path"; then
    archived_flag=1
  else
    archived_flag=0
  fi

  rel="${path#"$SPECS_ROOT"/}"
  case "$rel" in
    design-plans/DP-[0-9][0-9][0-9]*-*|design-plans/DP-[0-9][0-9][0-9]*-*/*)
      # active DP container
      container="$SPECS_ROOT/$(printf '%s' "$rel" | awk -F/ '{print $1 "/" $2}')"
      namespace="active"
      ;;
    design-plans/archive/DP-[0-9][0-9][0-9]*-*|design-plans/archive/DP-[0-9][0-9][0-9]*-*/*)
      container="$SPECS_ROOT/$(printf '%s' "$rel" | awk -F/ '{print $1 "/" $2 "/" $3}')"
      namespace="archive"
      ;;
    companies/*/archive/*)
      # companies/{company}/archive/{TICKET}/...
      container="$SPECS_ROOT/$(printf '%s' "$rel" | awk -F/ '{print $1 "/" $2 "/" $3 "/" $4}')"
      namespace="archive"
      ;;
    companies/*/*)
      # companies/{company}/{TICKET}/...
      container="$SPECS_ROOT/$(printf '%s' "$rel" | awk -F/ '{print $1 "/" $2 "/" $3}')"
      namespace="active"
      ;;
    *)
      fail_invalid "artifact path is not inside a spec container: $input"
      ;;
  esac

  [[ -d "$container" ]] || fail_missing "resolved container does not exist: $container"
  printf '%s\t%s\n' "$namespace" "$container"
}

#####################################
# Classify container → source_type & source_id
#####################################
classify_container() {
  local container="$1"
  local name
  name="$(basename "$container")"
  case "$container" in
    "$SPECS_ROOT"/design-plans/DP-*|"$SPECS_ROOT"/design-plans/archive/DP-*)
      local dp_id
      dp_id="$(printf '%s' "$name" | awk -F- '{print $1 "-" $2}')"
      printf '%s\t%s\n' "dp" "$dp_id"
      ;;
    "$SPECS_ROOT"/companies/*/archive/*|"$SPECS_ROOT"/companies/*/*)
      printf '%s\t%s\n' "jira" "$name"
      ;;
    *)
      fail_invalid "unsupported container shape: $container"
      ;;
  esac
}

#####################################
# Pick primary doc by source_type and container
#####################################
pick_primary_doc() {
  local container="$1" source_type="$2"
  local candidate
  case "$source_type" in
    dp)
      for candidate in "$container/index.md" "$container/plan.md"; do
        [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
      done
      ;;
    jira)
      for candidate in "$container/index.md" "$container/refinement.md" "$container/plan.md"; do
        [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
      done
      ;;
  esac
  printf '\n'
}

#####################################
# Emit JSON
#####################################
emit_json() {
  local source_type="$1" source_id="$2" container="$3" primary_doc="$4"
  local refinement_md="$5" refinement_json="$6" status="$7" archived="$8"
  shift 8
  local -a readiness=()
  if [[ $# -gt 0 ]]; then
    readiness=("$@")
  fi

  python3 - "$source_type" "$source_id" "$container" "$primary_doc" \
                 "$refinement_md" "$refinement_json" "$status" "$archived" \
                 "${readiness[@]+"${readiness[@]}"}" <<'PY'
import json, sys
args = sys.argv[1:]
fixed = args[:8]
readiness = args[8:]
source_type, source_id, container, primary_doc, refinement_md, refinement_json, status, archived = fixed
out = {
    "source_type": source_type,
    "source_id": source_id,
    "container": container,
    "primary_doc": primary_doc,
    "refinement_md": refinement_md,
    "refinement_json": refinement_json,
    "status": status,
    "archived": archived.lower() == "true",
    "readiness": readiness,
}
print(json.dumps(out, ensure_ascii=False, indent=2))
PY
}

#####################################
# Main resolution
#####################################
NAMESPACE=""
CONTAINER=""
SOURCE_TYPE=""
RESOLVED_SOURCE_ID=""

# 使用 command substitution 直接 propagate exit codes（subshell fail_* exit 2 才會傳出）
if [[ -n "$SOURCE_ID" ]]; then
  case "$SOURCE_ID" in
    DP-[0-9][0-9][0-9]|DP-[0-9][0-9][0-9][0-9])
      _line="$(locate_dp "$SOURCE_ID")"
      NAMESPACE="${_line%%$'\t'*}"
      CONTAINER="${_line#*$'\t'}"
      SOURCE_TYPE="dp"
      RESOLVED_SOURCE_ID="$SOURCE_ID"
      ;;
    [A-Z][A-Z0-9]*-[0-9]*)
      _line="$(locate_jira "$SOURCE_ID")"
      NAMESPACE="${_line%%$'\t'*}"
      CONTAINER="${_line#*$'\t'}"
      SOURCE_TYPE="jira"
      RESOLVED_SOURCE_ID="$SOURCE_ID"
      ;;
    *)
      fail_invalid "unrecognised source id shape: $SOURCE_ID"
      ;;
  esac
else
  _line="$(resolve_direct_artifact_path "$ARTIFACT_PATH")"
  NAMESPACE="${_line%%$'\t'*}"
  CONTAINER="${_line#*$'\t'}"
  _line="$(classify_container "$CONTAINER")"
  SOURCE_TYPE="${_line%%$'\t'*}"
  RESOLVED_SOURCE_ID="${_line#*$'\t'}"
fi

#####################################
# Compose output
#####################################
PRIMARY_DOC="$(pick_primary_doc "$CONTAINER" "$SOURCE_TYPE")"

REFINEMENT_MD=""
REFINEMENT_JSON=""
[[ -f "$CONTAINER/refinement.md" ]] && REFINEMENT_MD="$CONTAINER/refinement.md"
[[ -f "$CONTAINER/refinement.json" ]] && REFINEMENT_JSON="$CONTAINER/refinement.json"

STATUS=""
if [[ -n "$PRIMARY_DOC" ]]; then
  STATUS="$(frontmatter_status "$PRIMARY_DOC")"
fi
# JIRA / company fallback：若 primary 沒寫 status，試 refinement.md
if [[ -z "$STATUS" && -n "$REFINEMENT_MD" ]]; then
  STATUS="$(frontmatter_status "$REFINEMENT_MD")"
fi

ARCHIVED="false"
if [[ "$NAMESPACE" == "archive" ]]; then
  ARCHIVED="true"
fi

# readiness 信號
READINESS=()
if [[ "$ARCHIVED" == "true" ]]; then
  READINESS+=("archived-read-only")
fi
[[ -z "$PRIMARY_DOC" ]] && READINESS+=("missing-primary-doc")
[[ -z "$REFINEMENT_MD" ]] && READINESS+=("missing-refinement-md")
[[ -z "$REFINEMENT_JSON" ]] && READINESS+=("missing-refinement-json")
[[ -z "$STATUS" ]] && READINESS+=("missing-status")

if [[ "${#READINESS[@]}" -gt 0 ]]; then
  emit_json \
    "$SOURCE_TYPE" "$RESOLVED_SOURCE_ID" "$CONTAINER" "$PRIMARY_DOC" \
    "$REFINEMENT_MD" "$REFINEMENT_JSON" "$STATUS" "$ARCHIVED" \
    "${READINESS[@]}"
else
  emit_json \
    "$SOURCE_TYPE" "$RESOLVED_SOURCE_ID" "$CONTAINER" "$PRIMARY_DOC" \
    "$REFINEMENT_MD" "$REFINEMENT_JSON" "$STATUS" "$ARCHIVED"
fi
