#!/usr/bin/env bash
# validate-refinement-inbox-record.sh — schema gate for breakdown-produced
# refinement return inbox records.
#
# Usage:
#   validate-refinement-inbox-record.sh <path/to/refinement-inbox/record.md>
#   validate-refinement-inbox-record.sh --self-test
#
# Exit: 0 = pass
#       1 = hard fail
#       2 = usage / missing file

set -euo pipefail

BODY_CAP_BYTES=8192

usage() {
  cat >&2 <<EOF
usage: $0 <path/to/refinement-inbox/record.md>
       $0 --self-test
EOF
  exit 2
}

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

extract_section() {
  local file="$1"
  local heading="$2"
  awk -v heading="$heading" '
    $0 == heading { in_section=1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$file"
}

body_byte_size() {
  local file="$1"
  awk '
    /^---$/ { if (fm==0) { fm=1; next } else { fm=2; next } }
    fm==2 { print }
  ' "$file" | wc -c | tr -d ' '
}

validate_file() {
  local file="$1"
  local errors=()

  if [[ ! -f "$file" ]]; then
    echo "error: inbox record not found: $file" >&2
    return 2
  fi

  local skill target source route epic source_task source_ticket source_sidecar count created consumed
  skill=$(extract_frontmatter_scalar "$file" "skill" || true)
  target=$(extract_frontmatter_scalar "$file" "target_skill" || true)
  source=$(extract_frontmatter_scalar "$file" "source" || true)
  route=$(extract_frontmatter_scalar "$file" "route" || true)
  epic=$(extract_frontmatter_scalar "$file" "epic" || true)
  source_task=$(extract_frontmatter_scalar "$file" "source_task" || true)
  source_ticket=$(extract_frontmatter_scalar "$file" "source_ticket" || true)
  source_sidecar=$(extract_frontmatter_scalar "$file" "source_sidecar" || true)
  count=$(extract_frontmatter_scalar "$file" "escalation_count" || true)
  created=$(extract_frontmatter_scalar "$file" "created_at" || true)
  consumed=$(extract_frontmatter_scalar "$file" "consumed" || true)

  if [[ "$skill" != "breakdown" ]]; then
    errors+=("frontmatter 'skill' must be 'breakdown' (got '$skill')")
  fi
  if [[ "$target" != "refinement" ]]; then
    errors+=("frontmatter 'target_skill' must be 'refinement' (got '$target')")
  fi
  if [[ "$source" != "scope-escalation" ]]; then
    errors+=("frontmatter 'source' must be 'scope-escalation' (got '$source')")
  fi
  if [[ "$route" != "refinement" ]]; then
    errors+=("frontmatter 'route' must be 'refinement' (got '$route')")
  fi
  if [[ -z "$epic" ]]; then
    errors+=("frontmatter 'epic' is required (JIRA Epic key or DP-NNN source id)")
  fi
  if [[ -z "$source_task" ]]; then
    errors+=("frontmatter 'source_task' is required")
  fi
  if [[ -z "$source_ticket" ]]; then
    errors+=("frontmatter 'source_ticket' is required")
  fi
  if [[ -z "$source_sidecar" ]]; then
    errors+=("frontmatter 'source_sidecar' is required as an audit pointer")
  fi
  if ! [[ "$count" =~ ^[12]$ ]]; then
    errors+=("frontmatter 'escalation_count' must be 1 or 2 (got '$count')")
  fi
  if ! [[ "$created" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    errors+=("frontmatter 'created_at' must be ISO 8601 with Z suffix (got '$created')")
  fi
  if ! [[ "$consumed" =~ ^(true|false)$ ]]; then
    errors+=("frontmatter 'consumed' must be true or false (got '$consumed')")
  fi

  local section section_body section_trim
  for section in "## Decision" "## Refinement Context" "## Decisions Needed" "## Source Audit"; do
    if ! grep -qF "$section" "$file"; then
      errors+=("missing required section '$section'")
    else
      section_body=$(extract_section "$file" "$section")
      section_trim=$(printf '%s' "$section_body" | tr -d '[:space:]')
      if [[ -z "$section_trim" ]]; then
        errors+=("required section '$section' is empty")
      fi
    fi
  done

  if grep -qF "## Raw Evidence" "$file"; then
    errors+=("inbox record must not contain '## Raw Evidence'; summarize planner context instead")
  fi

  local body_size
  body_size=$(body_byte_size "$file")
  if [[ "$body_size" -gt "$BODY_CAP_BYTES" ]]; then
    errors+=("body size ${body_size} bytes exceeds 8KB cap")
  fi

  if [[ "${#errors[@]}" -gt 0 ]]; then
    echo "✗ validate-refinement-inbox-record.sh FAIL — $file" >&2
    local e
    for e in "${errors[@]}"; do
      echo "  - $e" >&2
    done
    return 1
  fi

  echo "✓ validate-refinement-inbox-record.sh PASS — $file"
}

run_self_test() {
  local tmp inbox good bad
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  inbox="$tmp/specs/EPIC-478/refinement-inbox"
  mkdir -p "$inbox"
  good="$inbox/T3a-2-20260429T093000Z.md"
  cat >"$good" <<'EOF'
---
skill: breakdown
target_skill: refinement
source: scope-escalation
route: refinement
epic: EPIC-478
source_task: T3a
source_ticket: TASK-3711
source_sidecar: specs/companies/exampleco/EPIC-478/escalations/T3a-2.md
escalation_count: 2
created_at: 2026-04-29T09:30:00Z
consumed: false
---

## Decision

re-classified to refinement: AC boundary must be re-decided.

## Refinement Context

- Gate summary: ci-local remains over threshold after task-level repair.

## Decisions Needed

1. Decide whether the AC budget remains mandatory.

## Source Audit

- Source sidecar path is for audit only; refinement must not open it.
EOF

  echo "self-test: validating GOOD inbox record"
  validate_file "$good"

  bad="$inbox/T3a-2-bad.md"
  cat >"$bad" <<'EOF'
---
skill: engineering
target_skill: refinement
source: scope-escalation
route: refinement
epic: EPIC-478
source_task: T3a
source_ticket: TASK-3711
source_sidecar: specs/companies/exampleco/EPIC-478/escalations/T3a-2.md
escalation_count: 2
created_at: 2026-04-29T09:30:00Z
consumed: false
---

## Decision

Direct handoff.

## Refinement Context

Context.

## Decisions Needed

1. Decide.

## Raw Evidence

full logs

## Source Audit

Audit.
EOF

  echo "self-test: validating BAD inbox record (expect FAIL)"
  if validate_file "$bad" >/dev/null 2>&1; then
    echo "self-test failed: bad inbox record passed" >&2
    return 1
  fi

  echo "self-test: ALL PASS"
}

if [[ $# -lt 1 ]]; then
  usage
fi

case "$1" in
  --self-test)
    run_self_test
    ;;
  -h|--help)
    usage
    ;;
  *)
    validate_file "$1"
    ;;
esac
