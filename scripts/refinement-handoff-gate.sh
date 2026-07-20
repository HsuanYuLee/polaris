#!/usr/bin/env bash
# refinement-handoff-gate.sh — hard gate before refinement hands off to breakdown.
#
# Purpose: Run the full refinement->breakdown handoff contract chain (schema,
#          ac-coverage, artifact-parity, advisory validators, residue, skill
#          boundary) against a refinement.json.
# Inputs:  <spec-container|refinement.md|refinement.json> plus optional
#          --closeout / --aggregate / --enumerate mode flags.
# Outputs: stdout PASS line + exit codes below.
#
# Modes:
#   (default, fail-first)  Run the chain, stop at the first failing gate,
#                          propagate that gate's exit code.
#   --aggregate            Run EVERY chain stage plus the lock-preflight ->
#                          derive -> validate-breakdown-ready leg, collect ALL
#                          failures, and report them in ONE run (DP-417 AC12).
#   --enumerate            Print the complete required-field / gate set for the
#                          whole chain WITHOUT reading or mutating any artifact
#                          (DP-417 AC13 dry-run contract).
#
# Exit:
#   0 = handoff clean (or enumerate mode)
#   1 = handoff blocked (missing or invalid artifact; fail-first mode)
#   2 = usage/path error, strong-bound schema violation, or aggregate mode with
#       one or more collected failures

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: refinement-handoff-gate.sh [--closeout|--aggregate|--enumerate] <spec-container|refinement.md|refinement.json>

Modes:
  (default)     fail-first chain; stops at the first failing gate.
  --aggregate   run the entire chain (+ lock-preflight/derive/breakdown-ready),
                collect ALL violations, report them together (exit 2 if any).
  --enumerate   print the complete required-field / gate set for the whole
                chain without reading or mutating any artifact.

Examples:
  refinement-handoff-gate.sh specs/companies/exampleco/EPIC-495
  refinement-handoff-gate.sh --aggregate specs/companies/exampleco/EPIC-495/refinement.json
  refinement-handoff-gate.sh --enumerate specs/companies/exampleco/EPIC-495
EOF
  exit 2
}

# DP-273 Wall B: a release-tail (closeout) caller passes --closeout (or sets
# POLARIS_REFINEMENT_HANDOFF_CLOSEOUT=1) to declare that this is NOT a live
# refinement->breakdown handoff. In closeout context the refinement-session
# boundary check is skipped (it would falsely BLOCK on a stale refinement
# baseline against a release diff that contains code deliverables). The live
# refinement->breakdown handoff boundary is left untouched.
CLOSEOUT="${POLARIS_REFINEMENT_HANDOFF_CLOSEOUT:-0}"
# DP-417 T10: fail-first (default) | aggregate | enumerate.
MODE="default"
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --closeout) CLOSEOUT=1; shift ;;
    --aggregate) MODE="aggregate"; shift ;;
    --enumerate) MODE="enumerate"; shift ;;
    --) shift; while [[ $# -gt 0 ]]; do positional+=("$1"); shift; done ;;
    *) positional+=("$1"); shift ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lib_dir="$script_dir/lib"
validator="$script_dir/validate-refinement-json.sh"
ac_coverage_validator="$script_dir/validate-refinement-ac-coverage.sh"
parity_validator="$script_dir/validate-refinement-artifact-parity.sh"
residue_checker="$script_dir/check-runtime-cache-residue.sh"
lock_preflight="$script_dir/validate-refinement-lock-preflight.sh"
repo_root="$(cd "$script_dir/.." && pwd)"

# --------------------------------------------------------------------------
# Canonical chain stage list. Both the default fail-first driver and the
# --aggregate driver walk exactly this ordered set of advisory stages; the
# enumerate driver prints it. This is the single source of truth for the chain
# order — do not duplicate it into a second gate runner.
# Each line: "<label> <lib-script.py> [extra argv...]"; $json_path is appended
# by run_advisory at call time.
# --------------------------------------------------------------------------
advisory_specs() {
  cat <<'SPECS'
predecessor-scan refinement-section-presence-advisory.py --mode predecessor
adversarial-pass refinement-section-presence-advisory.py --mode adversarial
decision-ac-coverage refinement-decision-ac-coverage.py
module-ac-coverage refinement-module-ac-coverage.py
script-help-advisory refinement-script-help-advisory.py
selftest-parity refinement-selftest-parity.py
release-surface-advisory refinement-release-surface-advisory.py
handoff-advisory-collector refinement-handoff-advisory-collector.py
referrer-cascade refinement-referrer-cascade.py
intra-dp-consistency refinement-intra-dp-consistency.py
ac-id-shape refinement-ac-id-shape.py
SPECS
}

# --------------------------------------------------------------------------
# Enumerate mode: print the complete chain contract without reading / mutating
# any artifact. DP-417 AC13 (up-front dry-run). This lists every producer-write
# and handoff gate a single refinement.json write must satisfy, so a producer
# can see the entire required-field / gate set in one shot instead of
# discovering each gate on a separate rejected run.
# --------------------------------------------------------------------------
print_enumeration() {
  cat <<'ENUM'
refinement handoff contract chain (enumerate / dry-run — no artifact read or write)

Stage order (each stage exits non-zero on violation; --aggregate collects all):

  1.  schema                    validate-refinement-json.sh
                                required top-level: goal, background, decisions,
                                modules[], acceptance_criteria[], predecessor_audit,
                                writeback; strong-bound schema violation -> exit 2.
  2.  ac-coverage               validate-refinement-ac-coverage.sh
                                every changed surface has >=1 acceptance criterion.
  3.  artifact-parity           validate-refinement-artifact-parity.sh
                                refinement.md derived view AC ids == refinement.json AC ids.
  4.  predecessor-scan          refinement-section-presence-advisory.py --mode predecessor
  5.  adversarial-pass          refinement-section-presence-advisory.py --mode adversarial
  6.  decision-ac-coverage      refinement-decision-ac-coverage.py
  7.  module-ac-coverage        refinement-module-ac-coverage.py
                                every module maps to >=1 AC (POLARIS_MODULE_AC_MISSING).
  8.  script-help-advisory      refinement-script-help-advisory.py
  9.  selftest-parity           refinement-selftest-parity.py
  10. release-surface-advisory  refinement-release-surface-advisory.py
  11. handoff-advisory-collector refinement-handoff-advisory-collector.py
  12. referrer-cascade          refinement-referrer-cascade.py
  13. intra-dp-consistency      refinement-intra-dp-consistency.py
  14. ac-id-shape               refinement-ac-id-shape.py
                                AC ids match required shape (POLARIS_AC_ID_SHAPE_INVALID).
  15. md-hand-edit-detector     refinement-md-hand-edit-detector.py (when renderer present)
  16. residue                   check-runtime-cache-residue.sh
  17. skill-workflow-boundary   skill-workflow-boundary-gate.sh --check (live handoff only)

LOCK-readiness leg (also run by --aggregate; producer LOCK pre-write gate runs it too):

  18. lock-preflight            validate-refinement-lock-preflight.sh
        -> verification-strategy gate
        -> replaces_existing gate
        -> per planned task:
             derive                     derive-task-md-from-refinement-json.sh
                                        required task fields: id, title, scope, verification.
             validate-breakdown-ready   validate-breakdown-ready.sh
                                        task_shape / Allowed Files / branch identity / AC parity.

Run `refinement-handoff-gate.sh --aggregate <container>` to execute every stage and
report all violations for a single write in one run.
ENUM
}

if [[ "$MODE" == "enumerate" ]]; then
  # Enumerate is a static contract listing; it needs no positional artifact and
  # performs no read/write. Accept an optional positional for CLI symmetry.
  if [[ "${#positional[@]}" -gt 1 ]]; then
    usage
  fi
  print_enumeration
  exit 0
fi

if [[ "${#positional[@]}" -ne 1 ]]; then
  usage
fi

input="${positional[0]}"

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

source_container="$(cd "$(dirname "$json_path")" && pwd)"
handbook="$repo_root/.claude/skills/references/ac-required-by-surface-defaults.yaml"
ac_coverage_args=("$json_path" --handbook "$handbook")
if [[ -n "${POLARIS_AC_COMPANY_OVERRIDE:-}" ]]; then
  ac_coverage_args+=(--company-override "$POLARIS_AC_COMPANY_OVERRIDE")
fi

# --------------------------------------------------------------------------
# Gate helper functions. Each runs one stage and returns its exit code; none
# toggle `set -e` — the driver holds `set +e` while calling them. This keeps
# the default and aggregate drivers walking identical stages.
# --------------------------------------------------------------------------

gate_schema() {
  local out st
  out="$("$validator" "$json_path" 2>&1)"
  st=$?
  if [[ "$st" -ne 0 ]]; then
    printf '%s\n' "$out" >&2
    if printf '%s\n' "$out" | grep -q 'strong-bound schema'; then
      local first_field
      first_field="$(printf '%s\n' "$out" | sed -n 's/^.*strong-bound schema: //p' | head -n 1)"
      echo "POLARIS_REFINEMENT_JSON_SCHEMA_VIOLATION: ${first_field:-unknown}" >&2
      return 2
    fi
    cat >&2 <<EOF

BLOCKED: refinement.json exists but does not satisfy the pipeline handoff schema.
Fix the artifact, including predecessor_audit / writeback fields, before proceeding to breakdown.
EOF
    return 1
  fi
  printf '%s\n' "$out"
  return 0
}

gate_ac_coverage() {
  [[ -x "$ac_coverage_validator" ]] || return 0
  "$ac_coverage_validator" "${ac_coverage_args[@]}"
}

gate_artifact_parity() {
  [[ -x "$parity_validator" ]] || return 0
  "$parity_validator" "$(dirname "$json_path")"
}

run_advisory() {
  local label="$1" script="$2"
  shift 2
  python3 "$lib_dir/$script" "$@" "$json_path"
}

gate_md_hand_edit() {
  if [[ -x "$script_dir/render-refinement-md.sh" && -f "$lib_dir/refinement-md-hand-edit-detector.py" ]]; then
    python3 "$lib_dir/refinement-md-hand-edit-detector.py" "$json_path"
    return $?
  fi
  return 0
}

gate_residue() {
  [[ -x "$residue_checker" ]] || return 0
  "$residue_checker" --repo "$repo_root" --source-container "$source_container"
}

gate_lock_preflight() {
  [[ -x "$lock_preflight" ]] || return 0
  "$lock_preflight" "$json_path"
}

# DP-230 D40 skill-workflow boundary check (refinement handoff time).
# Verbatim port of the historical inline block; returns the boundary gate's
# exit code (0 when skipped or the session is not live).
gate_boundary() {
  local boundary_gate="$script_dir/skill-workflow-boundary-gate.sh"
  [[ -x "$boundary_gate" ]] || return 0

  local boundary_repo boundary_real_container runtime_dir baseline_dir
  local refn_baseline_id refn_baseline_path
  boundary_repo="$(git -C "$source_container" rev-parse --show-toplevel 2>/dev/null || echo "$repo_root")"
  boundary_real_container="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$source_container")"
  runtime_dir="${POLARIS_RUNTIME_DIR:-$boundary_repo/.polaris/runtime}"
  baseline_dir="$runtime_dir/skill-workflow-boundary"
  refn_baseline_id="$(printf '%s|%s' refinement "$boundary_real_container" \
    | python3 -c "import hashlib,sys; print(hashlib.sha1(sys.stdin.read().encode()).hexdigest()[:16])")"
  refn_baseline_path="$baseline_dir/refinement-${refn_baseline_id}.json"

  if [[ -f "$refn_baseline_path" && "$CLOSEOUT" -ne 1 ]]; then
    # Liveness auto-detection: inspect the committed diff between the baseline
    # HEAD and current HEAD. If downstream (non-refinement-owned) files were
    # already committed, this is a closeout, not a live handoff.
    local refn_baseline_head session_live=1
    refn_baseline_head="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('head_sha',''))" "$refn_baseline_path")"
    if [[ -n "$refn_baseline_head" ]]; then
      local rel_container committed_diff downstream
      rel_container="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" \
        "$boundary_real_container" "$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$boundary_repo")")"
      rel_container="${rel_container%/}"
      committed_diff="$(git -C "$boundary_repo" diff --name-only "$refn_baseline_head" HEAD 2>/dev/null || true)"
      if [[ -n "$committed_diff" ]]; then
        downstream="$(printf '%s\n' "$committed_diff" \
          | python3 "$lib_dir/refinement_handoff_helpers.py" filter-downstream "$rel_container")"
        [[ -n "$downstream" ]] && session_live=0
      fi
    fi
    if [[ "$session_live" -eq 1 ]]; then
      "$boundary_gate" --skill refinement --check \
        --source-container "$source_container" --repo "$boundary_repo"
      return $?
    else
      # Closeout / stale session: skip the boundary check AND retire the stale
      # baseline (EC4 defense-in-depth) so it cannot re-trip on a later run.
      rm -f "$refn_baseline_path"
    fi
  elif [[ -f "$refn_baseline_path" && "$CLOSEOUT" -eq 1 ]]; then
    # Explicit closeout: skip the boundary check and retire the stale baseline.
    rm -f "$refn_baseline_path"
  fi
  return 0
}

# --------------------------------------------------------------------------
# Default fail-first driver: identical ordering and exit codes to the historical
# inline chain — stops at the first failing gate and propagates its exit code.
# --------------------------------------------------------------------------
run_default_chain() {
  set +e
  local rc line label script
  gate_schema; rc=$?; [[ $rc -ne 0 ]] && return $rc
  gate_ac_coverage; rc=$?; [[ $rc -ne 0 ]] && return $rc
  gate_artifact_parity; rc=$?; [[ $rc -ne 0 ]] && return $rc
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    read -ra parts <<< "$line"
    label="${parts[0]}"; script="${parts[1]}"
    run_advisory "$label" "$script" "${parts[@]:2}"; rc=$?
    [[ $rc -ne 0 ]] && return $rc
  done < <(advisory_specs)
  gate_md_hand_edit; rc=$?; [[ $rc -ne 0 ]] && return $rc
  gate_residue; rc=$?; [[ $rc -ne 0 ]] && return $rc
  gate_boundary; rc=$?; [[ $rc -ne 0 ]] && return $rc
  echo "PASS refinement handoff: $json_path"
  return 0
}

# --------------------------------------------------------------------------
# Aggregate driver (DP-417 AC12 / AC-NEG7): run EVERY chain stage plus the
# lock-preflight -> derive -> validate-breakdown-ready leg, collect ALL
# failures, and report them together. Exits 2 if any stage failed so a producer
# sees the complete violation set for one write in a single run.
# --------------------------------------------------------------------------
run_aggregate_chain() {
  set +e
  local rc line label script
  local -a failures=()
  gate_schema; rc=$?; [[ $rc -ne 0 ]] && failures+=("schema (exit $rc)")
  gate_ac_coverage; rc=$?; [[ $rc -ne 0 ]] && failures+=("ac-coverage (exit $rc)")
  gate_artifact_parity; rc=$?; [[ $rc -ne 0 ]] && failures+=("artifact-parity (exit $rc)")
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    read -ra parts <<< "$line"
    label="${parts[0]}"; script="${parts[1]}"
    run_advisory "$label" "$script" "${parts[@]:2}"; rc=$?
    [[ $rc -ne 0 ]] && failures+=("$label (exit $rc)")
  done < <(advisory_specs)
  gate_md_hand_edit; rc=$?; [[ $rc -ne 0 ]] && failures+=("md-hand-edit (exit $rc)")
  gate_residue; rc=$?; [[ $rc -ne 0 ]] && failures+=("residue (exit $rc)")
  gate_boundary; rc=$?; [[ $rc -ne 0 ]] && failures+=("boundary (exit $rc)")
  # AC12: the chain also spans lock-preflight -> derive -> validate-breakdown-ready.
  gate_lock_preflight; rc=$?; [[ $rc -ne 0 ]] && failures+=("lock-preflight (exit $rc)")

  if (( ${#failures[@]} > 0 )); then
    {
      echo ""
      echo "POLARIS_REFINEMENT_HANDOFF_AGGREGATE_FAILURES: ${#failures[@]}"
      local f
      for f in "${failures[@]}"; do
        echo "  - $f"
      done
      echo "Fix all listed violations, then rerun the handoff gate."
    } >&2
    return 2
  fi
  echo "PASS refinement handoff (aggregate): $json_path"
  return 0
}

if [[ "$MODE" == "aggregate" ]]; then
  run_aggregate_chain
  exit $?
fi

run_default_chain
exit $?
