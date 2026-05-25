#!/usr/bin/env bash
# refinement-handoff-gate.sh — hard gate before refinement hands off to breakdown.
#
# Usage:
#   refinement-handoff-gate.sh <spec-container|refinement.md|refinement.json>
#
# Exit:
#   0 = refinement.json exists and passes schema validation
#   1 = handoff blocked (missing or invalid artifact)
#   2 = usage/path error

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: refinement-handoff-gate.sh <spec-container|refinement.md|refinement.json>

Examples:
  refinement-handoff-gate.sh specs/companies/exampleco/EPIC-495
  refinement-handoff-gate.sh specs/companies/exampleco/EPIC-495/refinement.md
  refinement-handoff-gate.sh specs/companies/exampleco/EPIC-495/refinement.json
EOF
  exit 2
}

if [[ $# -ne 1 ]]; then
  usage
fi

input="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="$script_dir/validate-refinement-json.sh"
ac_coverage_validator="$script_dir/validate-refinement-ac-coverage.sh"
parity_validator="$script_dir/validate-refinement-artifact-parity.sh"
residue_checker="$script_dir/check-runtime-cache-residue.sh"

if [[ ! -x "$validator" ]]; then
  echo "BLOCKED: validator not executable: $validator" >&2
  exit 2
fi

json_path=""
case "$input" in
  */refinement.json|refinement.json)
    json_path="$input"
    ;;
  */refinement.md|refinement.md)
    json_path="$(dirname "$input")/refinement.json"
    ;;
  *)
    if [[ -d "$input" ]]; then
      json_path="$input/refinement.json"
    else
      echo "BLOCKED: path is neither a specs directory nor refinement artifact: $input" >&2
      exit 2
    fi
    ;;
esac

if [[ ! -f "$json_path" ]]; then
  cat >&2 <<EOF
BLOCKED: refinement handoff requires a machine-readable artifact.
Missing: $json_path

Run refinement Step 7 first: produce refinement.json from the finalized refinement.md,
including current predecessor_audit / writeback data, then rerun this gate before
telling the user to proceed to breakdown.
EOF
  exit 1
fi

validator_output=""
validator_status=0
set +e
validator_output="$("$validator" "$json_path" 2>&1)"
validator_status=$?
set -e
if [[ "$validator_status" -ne 0 ]]; then
  printf '%s\n' "$validator_output" >&2
  if printf '%s\n' "$validator_output" | grep -q 'strong-bound schema'; then
    first_field="$(printf '%s\n' "$validator_output" | sed -n 's/^.*strong-bound schema: //p' | head -n 1)"
    echo "POLARIS_REFINEMENT_JSON_SCHEMA_VIOLATION: ${first_field:-unknown}" >&2
    exit 2
  fi
  cat >&2 <<EOF

BLOCKED: refinement.json exists but does not satisfy the pipeline handoff schema.
Fix the artifact, including predecessor_audit / writeback fields, before proceeding to breakdown.
EOF
  exit 1
fi
printf '%s\n' "$validator_output"

repo_root="$(cd "$script_dir/.." && pwd)"
handbook="$repo_root/.claude/skills/references/ac-required-by-surface-defaults.yaml"
ac_coverage_args=("$json_path" --handbook "$handbook")
if [[ -n "${POLARIS_AC_COMPANY_OVERRIDE:-}" ]]; then
  ac_coverage_args+=(--company-override "$POLARIS_AC_COMPANY_OVERRIDE")
fi
if [[ -x "$ac_coverage_validator" ]]; then
  "$ac_coverage_validator" "${ac_coverage_args[@]}"
fi

if [[ -x "$parity_validator" ]]; then
  "$parity_validator" "$(dirname "$json_path")"
fi

lib_dir="$script_dir/lib"
python3 "$lib_dir/refinement-section-presence-advisory.py" --mode predecessor "$json_path"
python3 "$lib_dir/refinement-section-presence-advisory.py" --mode adversarial "$json_path"
python3 "$lib_dir/refinement-decision-ac-coverage.py" "$json_path"
python3 "$lib_dir/refinement-module-ac-coverage.py" "$json_path"
python3 "$lib_dir/refinement-script-help-advisory.py" "$json_path"
python3 "$lib_dir/refinement-selftest-parity.py" "$json_path"
python3 "$lib_dir/refinement-release-surface-advisory.py" "$json_path"
python3 "$lib_dir/refinement-referrer-cascade.py" "$json_path"
python3 "$lib_dir/refinement-intra-dp-consistency.py" "$json_path"
python3 "$lib_dir/refinement-ac-id-shape.py" "$json_path"
if [[ -x "$script_dir/render-refinement-md.sh" && -f "$lib_dir/refinement-md-hand-edit-detector.py" ]]; then
  python3 "$lib_dir/refinement-md-hand-edit-detector.py" "$json_path"
fi

source_container="$(cd "$(dirname "$json_path")" && pwd)"

if [[ -x "$residue_checker" ]]; then
  "$residue_checker" --repo "$repo_root" --source-container "$source_container"
fi

# DP-230 D40 skill-workflow boundary check (refinement handoff time).
# If a refinement session baseline exists at runtime, verify the session
# only touched refinement-owned scope. Missing baseline is treated as
# advisory (no enforcement) so legacy invocations without the baseline
# step keep working; the gate becomes hard once refinement SKILL.md
# Step 0 calls --start at session entry.
boundary_gate="$script_dir/skill-workflow-boundary-gate.sh"
if [[ -x "$boundary_gate" ]]; then
  # Resolve the repo that actually owns this source container; this may
  # differ from $repo_root when refinement runs inside a worktree / fixture.
  boundary_repo="$(git -C "$source_container" rev-parse --show-toplevel 2>/dev/null || echo "$repo_root")"
  boundary_real_container="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$source_container")"
  runtime_dir="${POLARIS_RUNTIME_DIR:-$boundary_repo/.polaris/runtime}"
  baseline_dir="$runtime_dir/skill-workflow-boundary"
  refn_baseline_id="$(printf '%s|%s' refinement "$boundary_real_container" \
    | python3 -c "import hashlib,sys; print(hashlib.sha1(sys.stdin.read().encode()).hexdigest()[:16])")"
  refn_baseline_path="$baseline_dir/refinement-${refn_baseline_id}.json"
  if [[ -f "$refn_baseline_path" ]]; then
    "$boundary_gate" --skill refinement --check \
      --source-container "$source_container" --repo "$boundary_repo"
  fi
fi

echo "PASS refinement handoff: $json_path"
