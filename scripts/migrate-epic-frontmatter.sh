#!/usr/bin/env bash
# migrate-epic-frontmatter.sh
#
# DP-228-T11 — Backfill Epic specs frontmatter:
#   * companies/<co>/<KEY-NNN>/index.md
#   * companies/<co>/<KEY-NNN>/refinement.md
#
# Adds the three governed fields when missing:
#   * priority      — pulled from JIRA MCP if --jira-priority-cmd is provided;
#                     otherwise fallback to P3 + priority_source: fallback-p3.
#   * topic         — slugified from frontmatter title (or key as last resort).
#   * created       — git log first-commit date for the file, falling back to
#                     mtime when the file is untracked.
#
# CLI:
#   --workspace-root <path>    Override resolver-derived workspace root.
#   --dry-run                  Report planned edits; do not write.
#   --apply                    Write edits (default mode without --dry-run is no-op).
#   --include-archive          Include companies/*/archive/** (default excluded).
#   --jira-priority-cmd <cmd>  Optional command invoked as `<cmd> <KEY>` returning
#                              a priority token on stdout. Empty stdout = unreachable.
#
# Idempotent: rerunning with --apply yields zero changes once fields exist.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"

usage() {
  cat >&2 <<'USAGE'
usage: migrate-epic-frontmatter.sh [--workspace-root <path>] [--dry-run|--apply]
                                   [--include-archive] [--jira-priority-cmd <cmd>]
USAGE
}

workspace_root=""
mode="dry-run"
include_archive=0
jira_cmd=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root)
      workspace_root="${2:-}"
      [[ -n "$workspace_root" ]] || { usage; exit 2; }
      shift 2
      ;;
    --dry-run)
      mode="dry-run"
      shift
      ;;
    --apply)
      mode="apply"
      shift
      ;;
    --include-archive)
      include_archive=1
      shift
      ;;
    --jira-priority-cmd)
      jira_cmd="${2:-}"
      [[ -n "$jira_cmd" ]] || { usage; exit 2; }
      shift 2
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

EPIC_KEY_RE='^[A-Z][A-Z0-9]*-[0-9]+$'

# slugify: lowercase, strip non-ASCII, collapse non-alnum -> single dash,
# trim leading/trailing dashes. Falls back to "" if nothing usable remains.
slugify() {
  local raw="$1"
  printf '%s' "$raw" \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr -c 'a-z0-9' '-' \
    | LC_ALL=C sed -E 's/-+/-/g; s/^-//; s/-$//' \
    | LC_ALL=C cut -c1-60
}

# extract a top-level frontmatter scalar value (best-effort; strips quotes)
fm_get() {
  local file="$1" key="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && $0 ~ "^" key "[[:space:]]*:" {
      value = $0
      sub("^" key "[[:space:]]*:[[:space:]]*", "", value)
      gsub(/^["'\'']|["'\'']$/, "", value)
      print value
      exit
    }
  ' "$file"
}

fm_has() {
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

# Resolve `created` from git history (first commit touching the file) or mtime.
resolve_created() {
  local file="$1" workspace="$2"
  local git_root="" rel=""
  if git_root="$(git -C "$workspace" rev-parse --show-toplevel 2>/dev/null)"; then
    rel="${file#"$git_root"/}"
    local date=""
    date="$(git -C "$git_root" log --diff-filter=A --follow --format=%cs -- "$rel" 2>/dev/null | tail -1)"
    if [[ -n "$date" ]]; then
      printf '%s\n' "$date"
      return 0
    fi
  fi
  # Fallback: file mtime as YYYY-MM-DD (portable across GNU/BSD `date`).
  local mtime=""
  if mtime="$(stat -f '%Sm' -t '%Y-%m-%d' "$file" 2>/dev/null)"; then
    printf '%s\n' "$mtime"
    return 0
  fi
  if mtime="$(stat -c '%y' "$file" 2>/dev/null | cut -d' ' -f1)"; then
    printf '%s\n' "$mtime"
    return 0
  fi
  return 1
}

# Pull priority from MCP-backed hook command. Empty stdout = unreachable.
resolve_priority() {
  local key="$1"
  if [[ -z "$jira_cmd" ]]; then
    return 1
  fi
  local out=""
  out="$(eval "$jira_cmd" "$key" 2>/dev/null || true)"
  out="$(printf '%s' "$out" | tr -d '[:space:]')"
  if [[ -z "$out" ]]; then
    return 1
  fi
  printf '%s\n' "$out"
}

# Compute topic slug from frontmatter title; strip "Refinement —" prefix and
# the "<KEY-NNN>:" prefix to focus on the topic words.
resolve_topic() {
  local file="$1" key="$2"
  local title=""
  title="$(fm_get "$file" title)"
  if [[ -z "$title" ]]; then
    slugify "$key"
    return 0
  fi
  # Strip leading "Refinement — " or "Refinement - "
  title="$(printf '%s' "$title" | LC_ALL=C sed -E 's/^[Rr]efinement[[:space:]]*[—-][[:space:]]*//')"
  # Strip leading "KEY-NNN:" or "KEY-NNN -"
  title="$(printf '%s' "$title" | LC_ALL=C sed -E 's/^[A-Z][A-Z0-9]*-[0-9]+[[:space:]]*[:：-][[:space:]]*//')"
  local slug=""
  slug="$(slugify "$title")"
  if [[ -z "$slug" ]]; then
    slug="$(slugify "$key")"
  fi
  printf '%s\n' "$slug"
}

# Insert new frontmatter lines immediately before the closing `---`.
# Already-present keys are skipped (idempotency).
insert_frontmatter_fields() {
  local file="$1"
  shift
  local -a kv=("$@")
  local tmp inject
  tmp="$(mktemp -t epic-frontmatter.XXXXXX)"
  inject="$(mktemp -t epic-frontmatter-inject.XXXXXX)"
  printf '%s\n' "${kv[@]}" >"$inject"
  awk -v inject_file="$inject" '
    BEGIN {
      while ((getline line < inject_file) > 0) {
        lines[++n] = line
      }
      close(inject_file)
      inserted = 0
    }
    NR == 1 && $0 == "---" { print; in_fm = 1; next }
    in_fm && $0 == "---" && !inserted {
      for (i = 1; i <= n; i++) {
        if (length(lines[i]) > 0) print lines[i]
      }
      inserted = 1
      print
      next
    }
    { print }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
  rm -f "$inject"
}

changed_files=0
planned_files=0

process_file() {
  local file="$1" key="$2"
  has_frontmatter "$file" || return 0

  local -a additions=()
  local need_priority=0 need_topic=0 need_created=0

  if ! fm_has "$file" priority; then need_priority=1; fi
  if ! fm_has "$file" topic; then need_topic=1; fi
  if ! fm_has "$file" created; then need_created=1; fi

  if [[ "$need_priority" -eq 0 && "$need_topic" -eq 0 && "$need_created" -eq 0 ]]; then
    return 0
  fi

  if [[ "$need_priority" -eq 1 ]]; then
    local prio=""
    if prio="$(resolve_priority "$key")"; then
      additions+=("priority: $prio")
    else
      additions+=("priority: P3")
      additions+=("priority_source: fallback-p3")
    fi
  fi

  if [[ "$need_topic" -eq 1 ]]; then
    local topic=""
    topic="$(resolve_topic "$file" "$key")"
    additions+=("topic: $topic")
  fi

  if [[ "$need_created" -eq 1 ]]; then
    local created=""
    if created="$(resolve_created "$file" "$workspace_root")"; then
      additions+=("created: $created")
    else
      printf 'WARN\tcannot resolve created for %s\n' "$file" >&2
      return 0
    fi
  fi

  if [[ "$mode" == "dry-run" ]]; then
    printf 'WOULD_UPDATE\t%s\t%s\n' "$file" "${additions[*]}"
    planned_files=$((planned_files + 1))
    return 0
  fi

  insert_frontmatter_fields "$file" "${additions[@]}"
  changed_files=$((changed_files + 1))
  printf 'UPDATED\t%s\n' "$file"
}

# Drive: iterate every active company Epic container.
shopt -s nullglob
for company_dir in "$specs_root/companies"/*/; do
  [[ -d "$company_dir" ]] || continue
  for epic_dir in "$company_dir"*/; do
    epic_dir="${epic_dir%/}"
    base="$(basename "$epic_dir")"

    if [[ "$base" == "archive" ]]; then
      if [[ "$include_archive" -eq 1 ]]; then
        for arch_epic_dir in "$epic_dir"/*/; do
          arch_epic_dir="${arch_epic_dir%/}"
          arch_base="$(basename "$arch_epic_dir")"
          [[ "$arch_base" =~ $EPIC_KEY_RE ]] || continue
          for f in "$arch_epic_dir/index.md" "$arch_epic_dir/refinement.md"; do
            [[ -f "$f" ]] || continue
            process_file "$f" "$arch_base"
          done
        done
      fi
      continue
    fi

    [[ "$base" =~ $EPIC_KEY_RE ]] || continue
    for f in "$epic_dir/index.md" "$epic_dir/refinement.md"; do
      [[ -f "$f" ]] || continue
      process_file "$f" "$base"
    done
  done
done
shopt -u nullglob

if [[ "$mode" == "dry-run" ]]; then
  printf 'DRY_RUN: %s file(s) would be updated\n' "$planned_files"
else
  printf 'APPLIED: %s file(s) updated\n' "$changed_files"
fi
