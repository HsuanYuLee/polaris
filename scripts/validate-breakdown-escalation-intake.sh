#!/usr/bin/env bash
# validate-breakdown-escalation-intake.sh — breakdown-side gate for DP-044
# scope-escalation intake decisions.
#
# This script validates the planner decision *before* breakdown edits task.md,
# writes JIRA, or marks an engineering escalation sidecar as processed.
#
# Usage:
#   validate-breakdown-escalation-intake.sh \
#     --sidecar specs/EPIC/escalations/T3a-1.md \
#     --route engineering|refinement|wait|baseline_approval|task_update \
#     --closes-gate true|false \
#     --flavor plan-defect|scope-drift|env-drift \
#     --disposition "accepted flavor: env-drift" \
#     --decision "storage helper typing folded into T3a" \
#     --decision "residual baseline/env handled by waiting for sibling baseline correction"
#
#   validate-breakdown-escalation-intake.sh --self-test
#
# Exit: 0 = pass
#       1 = hard fail; do not write task.md/JIRA/processed:true
#       2 = usage error
#
# Why this exists:
#   Engineering sidecars describe gate closure. Breakdown must not reduce a
#   failed CI gate to the first Allowed Files delta. If a sidecar says a partial
#   fix is insufficient, route=engineering is only legal after the planner
#   explicitly handles the residual decisions and declares closes-gate=true.

set -euo pipefail

ALLOWED_ROUTES_REGEX='^(engineering|refinement|wait|baseline_approval|task_update)$'
ALLOWED_FLAVORS_REGEX='^(plan-defect|scope-drift|env-drift)$'

usage() {
  cat >&2 <<EOF
usage: $0 --sidecar <path> --route <route> --closes-gate <true|false> --flavor <flavor> --disposition <text> --decision <text> [--decision <text>...]
       $0 --self-test

routes: engineering | refinement | wait | baseline_approval | task_update
flavor: plan-defect | scope-drift | env-drift
disposition: "accepted flavor: X" when X matches sidecar flavor, or "re-classified to X: reason" when it differs
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

required_decision_count() {
  local text="$1"
  local count
  count=$(printf '%s\n' "$text" | awk '
    /^[[:space:]]*([0-9]+\.|-|\*)[[:space:]]+/ { n++ }
    END { print n + 0 }
  ')
  if [[ "$count" -eq 0 ]] && [[ -n "$(printf '%s' "$text" | tr -d '[:space:]')" ]]; then
    count=1
  fi
  printf '%s\n' "$count"
}

is_negative_forecast() {
  local text="$1"
  printf '%s\n' "$text" | grep -qiE \
    '(^|[^[:alpha:]])(no|fail|fails|failed|insufficient|not sufficient|still fail|cannot pass|won'\''t pass|不會過|仍會失敗|仍然失敗|不足|無法通過|不能回 engineering|不可回 engineering)([^[:alpha:]]|$)'
}

mentions_residual_decision() {
  local text="$1"
  printf '%s\n' "$text" | grep -qiE \
    '(residual|baseline|env|environment|upstream|sibling|wait|refinement|剩餘|殘留|基線|環境|等待|上游|同線|同支|改開 refinement|退 refinement)'
}

validate_flavor_disposition() {
  local source_flavor="$1"
  local final_flavor="$2"
  local disposition="$3"

  if [[ "$final_flavor" == "$source_flavor" ]]; then
    printf '%s\n' "$disposition" | grep -qiE "^accepted flavor:[[:space:]]*${final_flavor}([[:space:]]|$)"
    return $?
  fi

  printf '%s\n' "$disposition" | grep -qiE "^re-classified to[[:space:]]+${final_flavor}:[[:space:]]*[^[:space:]].*"
}

validate() {
  local sidecar="$1"
  local route="$2"
  local closes_gate="$3"
  local flavor="$4"
  local disposition="$5"
  shift 5
  local decisions=("$@")
  local errors=()

  if [[ ! -f "$sidecar" ]]; then
    echo "error: sidecar not found: $sidecar" >&2
    return 2
  fi
  if ! [[ "$route" =~ $ALLOWED_ROUTES_REGEX ]]; then
    errors+=("route must be one of engineering|refinement|wait|baseline_approval|task_update (got '$route')")
  fi
  if ! [[ "$closes_gate" =~ ^(true|false)$ ]]; then
    errors+=("closes-gate must be true or false (got '$closes_gate')")
  fi
  if ! [[ "$flavor" =~ $ALLOWED_FLAVORS_REGEX ]]; then
    errors+=("flavor must be one of plan-defect|scope-drift|env-drift (got '$flavor')")
  fi
  local source_flavor
  source_flavor=$(extract_frontmatter_scalar "$sidecar" "flavor" || true)
  if ! [[ "$source_flavor" =~ $ALLOWED_FLAVORS_REGEX ]]; then
    errors+=("sidecar frontmatter 'flavor' must be one of plan-defect|scope-drift|env-drift (got '$source_flavor')")
  fi
  if [[ -z "$(printf '%s' "$disposition" | tr -d '[:space:]')" ]]; then
    errors+=("--disposition is required and must contain the breakdown flavor disposition")
  elif [[ "$source_flavor" =~ $ALLOWED_FLAVORS_REGEX && "$flavor" =~ $ALLOWED_FLAVORS_REGEX ]] && ! validate_flavor_disposition "$source_flavor" "$flavor" "$disposition"; then
    if [[ "$flavor" == "$source_flavor" ]]; then
      errors+=("--disposition must start with 'accepted flavor: $flavor' when breakdown keeps the engineering flavor")
    else
      errors+=("--disposition must start with 're-classified to $flavor: <reason>' when breakdown changes engineering flavor '$source_flavor'")
    fi
  fi
  if [[ "${#decisions[@]}" -eq 0 ]]; then
    errors+=("at least one --decision is required")
  fi

  local closure required closure_trim required_trim
  closure=$(extract_section "$sidecar" "## Closure Forecast" || true)
  required=$(extract_section "$sidecar" "## Required Planner Decisions" || true)
  closure_trim=$(printf '%s' "$closure" | tr -d '[:space:]')
  required_trim=$(printf '%s' "$required" | tr -d '[:space:]')

  if [[ -z "$closure_trim" ]]; then
    errors+=("sidecar missing non-empty '## Closure Forecast'")
  fi
  if [[ -z "$required_trim" ]]; then
    errors+=("sidecar missing non-empty '## Required Planner Decisions'")
  fi

  local decision_text decision_count required_count
  decision_text=$(printf '%s\n' "${decisions[@]}")
  decision_count="${#decisions[@]}"
  required_count=$(required_decision_count "$required")

  if [[ "$route" == "engineering" && "$closes_gate" != "true" ]]; then
    errors+=("route=engineering requires --closes-gate true; failed gates cannot be routed back to engineering")
  fi

  if is_negative_forecast "$closure"; then
    if [[ "$route" == "engineering" ]]; then
      if [[ "$decision_count" -lt "$required_count" ]]; then
        errors+=("sidecar Closure Forecast is negative/insufficient and has $required_count required planner decisions, but intake supplied only $decision_count decision(s)")
      fi
      if mentions_residual_decision "$required" && ! mentions_residual_decision "$decision_text"; then
        errors+=("sidecar requires residual/baseline/env handling, but intake decisions do not mention such handling")
      fi
    fi
    if [[ "$route" == "task_update" && "$closes_gate" != "true" ]]; then
      errors+=("route=task_update with a negative Closure Forecast requires --closes-gate true; otherwise do not mark processed")
    fi
  fi

  if [[ "$route" == "baseline_approval" ]] && ! mentions_residual_decision "$decision_text"; then
    errors+=("route=baseline_approval must include a baseline/env decision in --decision")
  fi

  if [[ "${#errors[@]}" -gt 0 ]]; then
    echo "✗ validate-breakdown-escalation-intake.sh FAIL — $sidecar" >&2
    local e
    for e in "${errors[@]}"; do
      echo "  - $e" >&2
    done
    echo "  action: do not edit task.md, do not write JIRA, do not set processed:true" >&2
    return 1
  fi

  echo "✓ validate-breakdown-escalation-intake.sh PASS — route=$route closes_gate=$closes_gate flavor=$flavor"
}

run_self_test() {
  local tmp sidecar
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  sidecar="$tmp/T3a-1.md"
  cat >"$sidecar" <<'EOF'
---
skill: engineering
ticket: TASK-3711
epic: EPIC-478
flavor: env-drift
escalation_count: 1
timestamp: 2026-04-27T07:34:56Z
truncated: false
scrubbed: true
---

## Summary

Storage helper typing is necessary but insufficient; residual baseline drift remains.

## Closure Forecast

No — storage-only permission is insufficient. It can remove two errors, but ci-local will still fail.

## Required Planner Decisions

1. Decide whether storage helper typing edits are folded into T3a.
2. Decide how the residual +12 baseline/env mismatch is resolved before engineering resumes.
EOF

  echo "self-test: partial route to engineering must FAIL"
  if validate "$sidecar" "engineering" "true" "plan-defect" \
      "re-classified to plan-defect: storage helper belongs to this task" \
      "storage helper typing folded into T3a" >/dev/null 2>&1; then
    echo "self-test failed: partial engineering decision passed" >&2
    return 1
  fi

  echo "self-test: accepted flavor requires accepted disposition"
  if validate "$sidecar" "wait" "false" "env-drift" \
      "re-classified to env-drift: missing accepted wording" \
      "residual baseline/env handled by waiting for sibling baseline correction" >/dev/null 2>&1; then
    echo "self-test failed: accepted flavor with re-classified wording passed" >&2
    return 1
  fi

  echo "self-test: complete route to engineering must PASS"
  validate "$sidecar" "engineering" "true" "env-drift" \
    "accepted flavor: env-drift" \
    "storage helper typing folded into T3a" \
    "residual baseline/env handled by waiting for sibling baseline correction before engineering resumes"

  echo "self-test: re-classified disposition must PASS"
  validate "$sidecar" "refinement" "false" "plan-defect" \
    "re-classified to plan-defect: storage helper belongs to the original task and residual scope needs replanning" \
    "residual baseline/env indicates deeper planning drift; route refinement instead of engineering"

  echo "self-test: route to refinement with closes=false must PASS"
  validate "$sidecar" "refinement" "false" "env-drift" \
    "accepted flavor: env-drift" \
    "residual baseline/env indicates deeper planning drift; route refinement instead of engineering"
}

if [[ $# -eq 1 && "$1" == "--self-test" ]]; then
  run_self_test
  exit $?
fi

sidecar=""
route=""
closes_gate=""
flavor=""
disposition=""
decisions=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sidecar)
      [[ $# -ge 2 ]] || usage
      sidecar="$2"
      shift 2
      ;;
    --route)
      [[ $# -ge 2 ]] || usage
      route="$2"
      shift 2
      ;;
    --closes-gate)
      [[ $# -ge 2 ]] || usage
      closes_gate="$2"
      shift 2
      ;;
    --flavor)
      [[ $# -ge 2 ]] || usage
      flavor="$2"
      shift 2
      ;;
    --disposition)
      [[ $# -ge 2 ]] || usage
      disposition="$2"
      shift 2
      ;;
    --decision)
      [[ $# -ge 2 ]] || usage
      decisions+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$sidecar" || -z "$route" || -z "$closes_gate" || -z "$flavor" || -z "$disposition" ]]; then
  usage
fi

validate "$sidecar" "$route" "$closes_gate" "$flavor" "$disposition" "${decisions[@]}"
