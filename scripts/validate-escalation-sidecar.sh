#!/usr/bin/env bash
# validate-escalation-sidecar.sh — schema enforcer for engineering scope-escalation
#                                  sidecars (DP-044).
#
# Usage:
#   validate-escalation-sidecar.sh <path/to/specs/{EPIC}/escalations/T{n}-{count}.md>
#   validate-escalation-sidecar.sh --self-test
#
# Exit:  0 = pass
#        1 = warning (advisory; non-blocking)
#        2 = hard fail (block engineering halt; stderr lists violations)
#
# Schema source: skills/references/handoff-artifact.md (mirrored, with field
#                reductions per DP-044 D7) + skills/references/escalation-flavor-guide.md
# Called by:     skills/engineering/SKILL.md § 開發中 Scope Escalation step,
#                after Write of the sidecar.

set -euo pipefail

# 20 KB cap on body (post-frontmatter content), mirroring handoff-artifact.md.
SIDECAR_CAP_BYTES=20480
ALLOWED_FLAVORS_REGEX='^(plan-defect|scope-drift|env-drift)$'
ESCALATION_COUNT_MAX=2

usage() {
  cat >&2 <<EOF
usage: $0 <path/to/sidecar.md>
       $0 --self-test
EOF
  exit 2
}

# ---------------------------------------------------------------------------
# Helper: extract a YAML scalar from the first --- block.
# ---------------------------------------------------------------------------
extract_frontmatter_scalar() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    /^---$/ { if (fm==0) { fm=1; next } else { exit } }
    fm==1 {
      if (/^[[:space:]]/) next
      n = split($0, parts, ":")
      if (n >= 2) {
        k = parts[1]
        sub(/^[[:space:]]+/, "", k); sub(/[[:space:]]+$/, "", k)
        if (k == key) {
          val = $0
          sub(/^[^:]*:[[:space:]]*/, "", val)
          sub(/[[:space:]]+$/, "", val)
          print val
          exit
        }
      }
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: byte length of section body (post-frontmatter).
# ---------------------------------------------------------------------------
body_byte_size() {
  local file="$1"
  awk '
    /^---$/ { if (fm==0) { fm=1; next } else { fm=2; next } }
    fm==2 { print }
  ' "$file" | wc -c | tr -d ' '
}

# ---------------------------------------------------------------------------
# Helper: extract a markdown section body (until next ## heading).
# ---------------------------------------------------------------------------
extract_section() {
  local file="$1"
  local heading="$2"
  awk -v heading="$heading" '
    $0 == heading { in_section=1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Lineage check — count sibling sidecars in the same escalations/ folder.
# Returns the highest escalation_count seen across the lineage, EXCLUDING the
# file under validation (so a count=2 sidecar's own count doesn't trigger the
# cap rule against itself).
# ---------------------------------------------------------------------------
max_lineage_count() {
  local sidecar="$1"
  local task_id
  task_id=$(basename "$sidecar" | sed -E 's/-[0-9]+\.md$//')
  local dir
  dir=$(dirname "$sidecar")
  local highest=0
  local self_real
  self_real=$(cd "$dir" && pwd)/$(basename "$sidecar")
  shopt -s nullglob
  for f in "$dir/${task_id}-"*.md; do
    [[ -f "$f" ]] || continue
    local f_real
    f_real=$(cd "$(dirname "$f")" && pwd)/$(basename "$f")
    if [[ "$f_real" == "$self_real" ]]; then
      continue
    fi
    local c
    c=$(extract_frontmatter_scalar "$f" "escalation_count" || true)
    if [[ "$c" =~ ^[0-9]+$ ]] && [[ "$c" -gt "$highest" ]]; then
      highest="$c"
    fi
  done
  shopt -u nullglob
  printf '%s\n' "$highest"
}

# ---------------------------------------------------------------------------
# Main validator.
# ---------------------------------------------------------------------------
validate_file() {
  local FILE="$1"
  local errors=()

  if [[ ! -f "$FILE" ]]; then
    echo "error: file not found: $FILE" >&2
    return 2
  fi

  # Filename pattern: T{n}-{count}.md (count = 1 or 2).
  local base
  base=$(basename "$FILE")
  if ! [[ "$base" =~ ^T[0-9]+[a-z]*-[12]\.md$ ]]; then
    errors+=("filename '$base' does not match required pattern T{n}[suffix]-{count}.md (count ∈ {1,2})")
  fi

  # ---- Frontmatter required fields ----
  local skill ticket epic flavor count timestamp truncated scrubbed
  skill=$(extract_frontmatter_scalar "$FILE" "skill" || true)
  ticket=$(extract_frontmatter_scalar "$FILE" "ticket" || true)
  epic=$(extract_frontmatter_scalar "$FILE" "epic" || true)
  flavor=$(extract_frontmatter_scalar "$FILE" "flavor" || true)
  count=$(extract_frontmatter_scalar "$FILE" "escalation_count" || true)
  timestamp=$(extract_frontmatter_scalar "$FILE" "timestamp" || true)
  truncated=$(extract_frontmatter_scalar "$FILE" "truncated" || true)
  scrubbed=$(extract_frontmatter_scalar "$FILE" "scrubbed" || true)

  if [[ "$skill" != "engineering" ]]; then
    errors+=("frontmatter 'skill' must be 'engineering' (got '$skill')")
  fi
  if [[ -z "$ticket" ]]; then
    errors+=("frontmatter 'ticket' is required (current task JIRA key)")
  fi
  if [[ -z "$epic" ]]; then
    errors+=("frontmatter 'epic' is required (parent Epic key)")
  fi
  if ! [[ "$flavor" =~ $ALLOWED_FLAVORS_REGEX ]]; then
    errors+=("frontmatter 'flavor' must be one of plan-defect|scope-drift|env-drift (got '$flavor') — see skills/references/escalation-flavor-guide.md")
  fi
  if ! [[ "$count" =~ ^[12]$ ]]; then
    errors+=("frontmatter 'escalation_count' must be 1 or 2 (got '$count') — see DP-044 D5")
  fi
  if ! [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    errors+=("frontmatter 'timestamp' must be ISO 8601 with Z suffix (got '$timestamp')")
  fi
  if ! [[ "$truncated" =~ ^(true|false)$ ]]; then
    errors+=("frontmatter 'truncated' must be a bool (true|false), got '$truncated'")
  fi
  if ! [[ "$scrubbed" =~ ^(true|false)$ ]]; then
    errors+=("frontmatter 'scrubbed' must be a bool (true|false), got '$scrubbed'")
  fi

  # ---- Body sections ----
  if ! grep -qF "## Summary" "$FILE"; then
    errors+=("missing required section '## Summary'")
  else
    local summary_body summary_chars
    summary_body=$(extract_section "$FILE" "## Summary")
    summary_chars=$(printf '%s' "$summary_body" | wc -c | tr -d ' ')
    if [[ "$summary_chars" -gt 500 ]]; then
      errors+=("'## Summary' body exceeds 500 chars (got $summary_chars) — D7 cap")
    fi
    if [[ "$summary_chars" -eq 0 ]]; then
      errors+=("'## Summary' body is empty")
    fi
  fi
  if ! grep -qF "## Raw Evidence" "$FILE"; then
    errors+=("missing required section '## Raw Evidence'")
  fi

  # ---- Size cap on body (frontmatter excluded) ----
  local body_size
  body_size=$(body_byte_size "$FILE")
  if [[ "$body_size" -gt "$SIDECAR_CAP_BYTES" ]]; then
    errors+=("body size ${body_size} bytes exceeds 20KB cap — run 'python3 scripts/snapshot-scrub.py --file $FILE' to truncate")
  fi

  # ---- Lineage cap (DP-044 D5) ----
  # max_lineage_count() excludes the file under validation, so `prior` is the
  # highest count among other sidecars in the same lineage.
  if [[ "$count" =~ ^[12]$ ]]; then
    local prior duplicate
    prior=$(max_lineage_count "$FILE")
    # If lineage already has a count=2 sidecar, no further sidecar may be added.
    if [[ "$prior" -ge "$ESCALATION_COUNT_MAX" ]]; then
      errors+=("lineage already has escalation_count=$prior — cap reached (DP-044 D5: route to refinement, not breakdown)")
    fi
    # Numbering must be sequential: count == prior + 1 (or count == 1 if no prior).
    if [[ "$count" -gt $(( prior + 1 )) ]]; then
      errors+=("escalation_count=$count skips a slot (highest prior in lineage is $prior; expected $((prior + 1)))")
    fi
    # Duplicate slot — another sibling already uses this count value.
    duplicate=$(
      task_id_local=$(basename "$FILE" | sed -E 's/-[0-9]+\.md$//')
      dir_local=$(dirname "$FILE")
      self_real_local=$(cd "$dir_local" && pwd)/$(basename "$FILE")
      shopt -s nullglob
      for f in "$dir_local/${task_id_local}-"*.md; do
        [[ -f "$f" ]] || continue
        f_real=$(cd "$(dirname "$f")" && pwd)/$(basename "$f")
        if [[ "$f_real" == "$self_real_local" ]]; then continue; fi
        c=$(extract_frontmatter_scalar "$f" "escalation_count" || true)
        if [[ "$c" == "$count" ]]; then
          echo "$f"
          break
        fi
      done
      shopt -u nullglob
    )
    if [[ -n "$duplicate" ]]; then
      errors+=("escalation_count=$count duplicates an existing sibling: $duplicate")
    fi
  fi

  if [[ "${#errors[@]}" -gt 0 ]]; then
    echo "✗ validate-escalation-sidecar.sh FAIL — $FILE" >&2
    local e
    for e in "${errors[@]}"; do
      echo "  - $e" >&2
    done
    return 2
  fi

  echo "✓ validate-escalation-sidecar.sh PASS — $FILE"
  return 0
}

# ---------------------------------------------------------------------------
# Self-test mode — writes a minimal valid sidecar to a temp dir and validates.
# ---------------------------------------------------------------------------
run_self_test() {
  local tmp
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  local epic_dir="$tmp/specs/EPIC-1/escalations"
  mkdir -p "$epic_dir"

  local good="$epic_dir/T3-1.md"
  cat >"$good" <<'EOF'
---
skill: engineering
ticket: ABC-123
epic: EPIC-1
flavor: env-drift
escalation_count: 1
timestamp: 2026-04-27T10:00:00Z
truncated: false
scrubbed: true
---

## Summary

CI gate `tsc:baseline` failed; failing files normalize to `apps/main/libs/KkStorage.ts`,
which is outside this task's Allowed Files. Proposed flavor: env-drift (sibling task
not yet merged).

## Raw Evidence

```
$ ci-local.sh --repo
[FAIL] tsc:baseline (12 new errors in KkStorage.ts)
```
EOF
  echo "self-test: validating GOOD sidecar"
  if ! validate_file "$good"; then
    echo "self-test: FAIL — good sidecar rejected" >&2
    return 1
  fi

  # Bad sidecar — invalid flavor + missing Summary.
  local bad="$epic_dir/T4-1.md"
  cat >"$bad" <<'EOF'
---
skill: engineering
ticket: ABC-456
epic: EPIC-1
flavor: bogus-flavor
escalation_count: 1
timestamp: 2026-04-27T10:00:00Z
truncated: false
scrubbed: true
---

## Raw Evidence

(no summary above)
EOF
  echo "self-test: validating BAD sidecar (expect FAIL)"
  if validate_file "$bad" 2>/dev/null; then
    echo "self-test: FAIL — bad sidecar incorrectly passed" >&2
    return 1
  fi

  # Lineage cap — write count=2 then verify count=1 again would not be permitted
  # by the prior-cap rule. Here we just confirm count=2 is accepted alone.
  local second="$epic_dir/T3-2.md"
  cat >"$second" <<'EOF'
---
skill: engineering
ticket: ABC-123
epic: EPIC-1
flavor: plan-defect
escalation_count: 2
timestamp: 2026-04-27T11:00:00Z
truncated: false
scrubbed: true
---

## Summary

Second escalation on the same lineage; planner re-classified flavor.

## Raw Evidence

```
$ ci-local.sh --repo
[FAIL] tsc:baseline (still failing after first revision)
```
EOF
  echo "self-test: validating second-iteration sidecar (count=2)"
  if ! validate_file "$second"; then
    echo "self-test: FAIL — count=2 sidecar rejected" >&2
    return 1
  fi

  echo "self-test: ALL PASS"
  return 0
}

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  usage
fi

case "$1" in
  --self-test)
    run_self_test
    exit $?
    ;;
  -h|--help)
    usage
    ;;
  *)
    validate_file "$1"
    exit $?
    ;;
esac
