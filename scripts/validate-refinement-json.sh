#!/usr/bin/env bash
# validate-refinement-json.sh — schema validator for refinement.json artifacts.
#
# Usage:
#   validate-refinement-json.sh <path/to/refinement.json>
#   validate-refinement-json.sh --scan <workspace_root>
#
# Exit:
#   0 = schema pass (single) / scan complete (scan mode, always 0)
#   1 = schema violations (single mode; details printed to stderr)
#   2 = usage error / file not found
#
# Contract source: skills/references/pipeline-handoff.md § Artifact Schemas — refinement.json
# DP-025: hard-fail on any missing required field.

set -euo pipefail

usage() {
  cat >&2 <<EOF
usage: $0 <path/to/refinement.json>
       $0 --scan <workspace_root>
EOF
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

case "${1:-}" in
  -h|--help)
    usage
    ;;
esac

# Core validator: print violations to stderr, return 0 (pass) / 1 (fail).
validate_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "error: file not found: $file" >&2
    return 2
  fi

  # Delegate structural validation to python3 — regex parsing of JSON is fragile.
  local result
  local rc
  set +e
  result=$(python3 - "$file" <<'PY'
import json
import os
import re
import sys

path = sys.argv[1]
artifact_path = os.path.abspath(path)
skip_path_currentness = "/archive/" in artifact_path
errors = []

try:
    with open(path) as f:
        data = json.load(f)
except json.JSONDecodeError as exc:
    print(f"parse_error: {exc}")
    sys.exit(1)
except Exception as exc:
    print(f"io_error: {exc}")
    sys.exit(1)

if not isinstance(data, dict):
    print("error: refinement.json root must be a JSON object")
    sys.exit(1)

JIRA_KEY = re.compile(r"^[A-Z][A-Z0-9]+-[0-9]+$")
DP_ID = re.compile(r"^DP-[0-9]{3}$")

# --- Top-level required fields ---
def require_nonempty_string(field):
    val = data.get(field)
    if not isinstance(val, str) or not val.strip():
        errors.append(f"missing or empty required field: '{field}' (expected non-empty string)")
        return None
    return val

source = data.get("source")
source_type = "jira"
source_id = None
if source is not None:
    if not isinstance(source, dict):
        errors.append("'source' must be an object when present")
    else:
        raw_source_type = source.get("type")
        if not isinstance(raw_source_type, str) or not raw_source_type.strip():
            errors.append("source.type is required when source is present")
        else:
            source_type = raw_source_type

if source_type not in {"jira", "dp", "topic", "free-text", "article", "paragraph", "bug"}:
    errors.append(
        f"source.type '{source_type}' is invalid "
        "(must be one of ['jira', 'dp', 'topic', 'free-text', 'article', 'paragraph', 'bug'])"
    )

if source_type == "jira":
    epic = require_nonempty_string("epic")
    if epic is not None and not JIRA_KEY.match(epic):
        errors.append(f"'epic' value '{epic}' does not match JIRA key format [A-Z][A-Z0-9]+-[0-9]+")
else:
    epic = data.get("epic")
    if epic is not None:
        errors.append(f"'epic' must be null for source.type={source_type}")
    if not isinstance(source, dict):
        errors.append(f"source object is required for source.type={source_type}")
    else:
        source_id = source.get("id")
        if not isinstance(source_id, str) or not source_id.strip():
            errors.append("source.id is required for DP-backed refinement artifacts")
        elif source_type == "dp" and not DP_ID.match(source_id):
            errors.append(f"source.id '{source_id}' does not match DP id format DP-NNN")

        container = source.get("container")
        if not isinstance(container, str) or not container.strip():
            errors.append("source.container is required for DP-backed refinement artifacts")
        elif not skip_path_currentness and not os.path.isdir(container):
            errors.append(f"source.container does not exist: {container}")

        plan_path = source.get("plan_path")
        if source_type == "dp" and (not isinstance(plan_path, str) or not plan_path.strip()):
            errors.append("source.plan_path is required for source.type=dp")
        elif source_type == "dp" and not skip_path_currentness:
            if not os.path.isfile(plan_path):
                legacy_index_fallback = (
                    isinstance(container, str)
                    and container.strip()
                    and os.path.basename(plan_path) == "plan.md"
                    and os.path.isfile(os.path.join(container, "index.md"))
                )
                if not legacy_index_fallback:
                    errors.append(f"source.plan_path does not exist: {plan_path}")
            if isinstance(container, str) and container.strip():
                expected_json = os.path.abspath(os.path.join(container, "refinement.json"))
                if expected_json != artifact_path:
                    errors.append(
                        "source.container is not current for this refinement.json "
                        f"(expected {expected_json}, got {artifact_path})"
                    )

        jira_key = source.get("jira_key")
        if jira_key not in (None, "", "N/A"):
            errors.append(f"source.jira_key must be null/N/A for source.type={source_type}")

require_nonempty_string("version")
require_nonempty_string("created_at")

# --- modules: array with ≥ 1, each with path + action ---
modules = data.get("modules")
if not isinstance(modules, list):
    errors.append("missing required field 'modules' (expected array)")
elif len(modules) == 0:
    errors.append("'modules' array must contain ≥ 1 module (received empty array)")
else:
    valid_actions = {"create", "modify", "delete", "investigate"}
    for idx, mod in enumerate(modules):
        if not isinstance(mod, dict):
            errors.append(f"modules[{idx}]: expected object, got {type(mod).__name__}")
            continue
        p = mod.get("path")
        if not isinstance(p, str) or not p.strip():
            errors.append(f"modules[{idx}]: missing or empty 'path'")
        a = mod.get("action")
        if not isinstance(a, str) or not a.strip():
            errors.append(f"modules[{idx}]: missing or empty 'action'")
        elif a not in valid_actions:
            errors.append(f"modules[{idx}]: invalid action '{a}' (must be one of {sorted(valid_actions)})")

# --- acceptance_criteria: array with ≥ 1, each with id + text + verification{method,detail} ---
ac = data.get("acceptance_criteria")
if not isinstance(ac, list):
    errors.append("missing required field 'acceptance_criteria' (expected array)")
elif len(ac) == 0:
    errors.append("'acceptance_criteria' array must contain ≥ 1 AC (received empty array)")
else:
    valid_methods = {"playwright", "lighthouse", "curl", "unit_test", "manual"}
    valid_categories = {"functional", "non_functional", "negative"}
    for idx, item in enumerate(ac):
        if not isinstance(item, dict):
            errors.append(f"acceptance_criteria[{idx}]: expected object, got {type(item).__name__}")
            continue
        aid = item.get("id")
        if not isinstance(aid, str) or not aid.strip():
            errors.append(f"acceptance_criteria[{idx}]: missing or empty 'id'")
        text = item.get("text")
        if not isinstance(text, str) or not text.strip():
            errors.append(f"acceptance_criteria[{idx}]: missing or empty 'text'")
        category = item.get("category")
        if category is not None:
            if not isinstance(category, str) or not category.strip():
                errors.append(f"acceptance_criteria[{idx}]: 'category' must be a non-empty string when present")
            elif category not in valid_categories:
                errors.append(
                    f"acceptance_criteria[{idx}]: invalid category '{category}' "
                    f"(must be one of {sorted(valid_categories)})"
                )
            negative = item.get("negative")
            if category == "negative" and negative is False:
                errors.append(
                    f"acceptance_criteria[{idx}]: category=negative conflicts with negative=false"
                )
            if category != "negative" and negative is True:
                errors.append(
                    f"acceptance_criteria[{idx}]: negative=true conflicts with category='{category}'"
                )
        ver = item.get("verification")
        if not isinstance(ver, dict):
            errors.append(f"acceptance_criteria[{idx}]: missing or non-object 'verification'")
        else:
            m = ver.get("method")
            if not isinstance(m, str) or not m.strip():
                errors.append(f"acceptance_criteria[{idx}].verification: missing 'method'")
            elif m not in valid_methods:
                errors.append(
                    f"acceptance_criteria[{idx}].verification: invalid method '{m}' "
                    f"(must be one of {sorted(valid_methods)})"
                )
            d = ver.get("detail")
            if not isinstance(d, str) or not d.strip():
                errors.append(f"acceptance_criteria[{idx}].verification: missing or empty 'detail'")

# --- dependencies: array (may be empty); if non-empty, each must have type + target + blocking ---
deps = data.get("dependencies")
if not isinstance(deps, list):
    errors.append("missing required field 'dependencies' (expected array; use [] if none)")
else:
    for idx, dep in enumerate(deps):
        if not isinstance(dep, dict):
            errors.append(f"dependencies[{idx}]: expected object, got {type(dep).__name__}")
            continue
        if not isinstance(dep.get("type"), str) or not dep["type"].strip():
            errors.append(f"dependencies[{idx}]: missing or empty 'type'")
        if not isinstance(dep.get("target"), str) or not dep["target"].strip():
            errors.append(f"dependencies[{idx}]: missing or empty 'target'")
        if "blocking" not in dep or not isinstance(dep["blocking"], bool):
            errors.append(f"dependencies[{idx}]: missing 'blocking' (must be boolean)")

# --- tool_requirements: optional structured handoff for ticket-scoped / project-owned tools ---
VALID_TOOL_OWNERS = {"framework", "delivery", "project", "ticket", "user"}
VALID_INSTALL_AUTHORITIES = {
    "root_mise",
    "system",
    "project_package_manager",
    "workspace_dependency_consent",
    "manual_user_action",
}
VALID_RUNTIME_PROFILES = {"core", "runtime", "delivery", "ticket"}

def validate_tool_requirement(item, label):
    if not isinstance(item, dict):
        errors.append(f"{label}: expected object, got {type(item).__name__}")
        return
    for field in ("name", "owner", "install_authority", "check_command", "runtime_profile", "goes_to_mise", "handoff_hint"):
        if field not in item:
            errors.append(f"{label}: missing required field '{field}'")
    name = item.get("name")
    if not isinstance(name, str) or not name.strip():
        errors.append(f"{label}.name must be a non-empty string")
    owner = item.get("owner")
    if owner not in VALID_TOOL_OWNERS:
        errors.append(f"{label}.owner must be one of {sorted(VALID_TOOL_OWNERS)} (got: {owner!r})")
    authority = item.get("install_authority")
    if authority not in VALID_INSTALL_AUTHORITIES:
        errors.append(
            f"{label}.install_authority must be one of {sorted(VALID_INSTALL_AUTHORITIES)} "
            f"(got: {authority!r})"
        )
    check_command = item.get("check_command")
    if not isinstance(check_command, str) or not check_command.strip():
        errors.append(f"{label}.check_command must be a non-empty string")
    install_command = item.get("install_command")
    if install_command is not None and not isinstance(install_command, str):
        errors.append(f"{label}.install_command must be a string or null when present")
    runtime_profile = item.get("runtime_profile")
    if runtime_profile not in VALID_RUNTIME_PROFILES:
        errors.append(
            f"{label}.runtime_profile must be one of {sorted(VALID_RUNTIME_PROFILES)} "
            f"(got: {runtime_profile!r})"
        )
    goes_to_mise = item.get("goes_to_mise")
    if not isinstance(goes_to_mise, bool):
        errors.append(f"{label}.goes_to_mise must be boolean")
    elif owner == "ticket" and goes_to_mise:
        errors.append(f"{label}: ticket-scoped tools must set goes_to_mise=false")
    elif runtime_profile == "ticket" and goes_to_mise:
        errors.append(f"{label}: runtime_profile=ticket must set goes_to_mise=false")
    handoff_hint = item.get("handoff_hint")
    if not isinstance(handoff_hint, str) or not handoff_hint.strip():
        errors.append(f"{label}.handoff_hint must be a non-empty string")

tool_requirements = data.get("tool_requirements")
if tool_requirements is not None:
    if not isinstance(tool_requirements, list):
        errors.append("tool_requirements must be an array when present")
    else:
        for idx, item in enumerate(tool_requirements):
            validate_tool_requirement(item, f"tool_requirements[{idx}]")

for idx, dep in enumerate(deps if isinstance(deps, list) else []):
    if not isinstance(dep, dict) or dep.get("type") != "tool":
        continue
    # Legacy-compatible mapping: dependencies[type=tool] may either point to a
    # named tool only, or carry the same structured fields as tool_requirements.
    structured_keys = {
        "name",
        "owner",
        "install_authority",
        "check_command",
        "install_command",
        "runtime_profile",
        "goes_to_mise",
        "handoff_hint",
    }
    if structured_keys.intersection(dep):
        mapped = dict(dep)
        mapped.setdefault("name", dep.get("target"))
        validate_tool_requirement(mapped, f"dependencies[{idx}]")

# --- edge_cases: array (may be empty); if non-empty, each must have scenario + handling ---
edges = data.get("edge_cases")
if not isinstance(edges, list):
    errors.append("missing required field 'edge_cases' (expected array; use [] if none)")
else:
    for idx, edge in enumerate(edges):
        if not isinstance(edge, dict):
            errors.append(f"edge_cases[{idx}]: expected object, got {type(edge).__name__}")
            continue
        if not isinstance(edge.get("scenario"), str) or not edge["scenario"].strip():
            errors.append(f"edge_cases[{idx}]: missing or empty 'scenario'")
        if not isinstance(edge.get("handling"), str) or not edge["handling"].strip():
            errors.append(f"edge_cases[{idx}]: missing or empty 'handling'")

# --- predecessor_audit: array (may be empty); each item must describe disposition + writeback ---
preds = data.get("predecessor_audit")
if not isinstance(preds, list):
    errors.append("missing required field 'predecessor_audit' (expected array; use [] if none)")
else:
    valid_dispositions = {"KEEP", "PARTIAL_ABSORB", "FULLY_SUPERSEDED"}
    valid_expected_status = {"UNCHANGED", "SUPERSEDED"}
    for idx, pred in enumerate(preds):
        if not isinstance(pred, dict):
            errors.append(f"predecessor_audit[{idx}]: expected object, got {type(pred).__name__}")
            continue
        spec_id = pred.get("spec_id")
        if not isinstance(spec_id, str) or not spec_id.strip():
            errors.append(f"predecessor_audit[{idx}]: missing or empty 'spec_id'")
        disposition = pred.get("disposition")
        if not isinstance(disposition, str) or not disposition.strip():
            errors.append(f"predecessor_audit[{idx}]: missing or empty 'disposition'")
        elif disposition not in valid_dispositions:
            errors.append(
                f"predecessor_audit[{idx}]: invalid disposition '{disposition}' "
                f"(must be one of {sorted(valid_dispositions)})"
            )
        rationale = pred.get("rationale")
        if not isinstance(rationale, str) or not rationale.strip():
            errors.append(f"predecessor_audit[{idx}]: missing or empty 'rationale'")

        writeback = pred.get("writeback")
        if not isinstance(writeback, dict):
            errors.append(f"predecessor_audit[{idx}]: missing or non-object 'writeback'")
            continue

        required = writeback.get("required")
        if not isinstance(required, bool):
            errors.append(f"predecessor_audit[{idx}].writeback: missing 'required' (must be boolean)")
        summary = writeback.get("summary")
        if not isinstance(summary, str) or not summary.strip():
            errors.append(f"predecessor_audit[{idx}].writeback: missing or empty 'summary'")
        expected_status = writeback.get("expected_status")
        if not isinstance(expected_status, str) or not expected_status.strip():
            errors.append(f"predecessor_audit[{idx}].writeback: missing 'expected_status'")
        elif expected_status not in valid_expected_status:
            errors.append(
                f"predecessor_audit[{idx}].writeback: invalid expected_status '{expected_status}' "
                f"(must be one of {sorted(valid_expected_status)})"
            )
        checklist = writeback.get("checklist_attribution")
        if not isinstance(checklist, list):
            errors.append(
                f"predecessor_audit[{idx}].writeback: missing 'checklist_attribution' "
                "(expected array; use [] if none)"
            )
        else:
            for cidx, item in enumerate(checklist):
                if not isinstance(item, str) or not item.strip():
                    errors.append(
                        f"predecessor_audit[{idx}].writeback.checklist_attribution[{cidx}]: "
                        "must be a non-empty string"
                    )

        if disposition == "KEEP":
            if required is not False:
                errors.append(
                    f"predecessor_audit[{idx}]: disposition KEEP requires writeback.required=false"
                )
            if expected_status != "UNCHANGED":
                errors.append(
                    f"predecessor_audit[{idx}]: disposition KEEP requires writeback.expected_status=UNCHANGED"
                )
            if isinstance(checklist, list) and checklist:
                errors.append(
                    f"predecessor_audit[{idx}]: disposition KEEP requires empty checklist_attribution"
                )
        elif disposition == "PARTIAL_ABSORB":
            if required is not True:
                errors.append(
                    f"predecessor_audit[{idx}]: disposition PARTIAL_ABSORB requires writeback.required=true"
                )
            if expected_status != "UNCHANGED":
                errors.append(
                    f"predecessor_audit[{idx}]: disposition PARTIAL_ABSORB requires "
                    "writeback.expected_status=UNCHANGED"
                )
        elif disposition == "FULLY_SUPERSEDED":
            if required is not True:
                errors.append(
                    f"predecessor_audit[{idx}]: disposition FULLY_SUPERSEDED requires writeback.required=true"
                )
            if expected_status != "SUPERSEDED":
                errors.append(
                    f"predecessor_audit[{idx}]: disposition FULLY_SUPERSEDED requires "
                    "writeback.expected_status=SUPERSEDED"
                )

def strong_error(field):
    errors.append(f"strong-bound schema: {field}")


schema_version = data.get("schema_version")
if schema_version in (None, ""):
    strong_error("schema_version")

ac_ids = {str(item.get("id")) for item in (ac or []) if isinstance(item, dict)}
tasks = data.get("tasks")
if not isinstance(tasks, list) or not tasks:
    strong_error("tasks")
else:
    task_required = {
        "id",
        "kind",
        "title",
        "scope",
        "allowed_files",
        "modules",
        "ac_ids",
        "dependencies",
        "estimate_points",
        "verification",
    }
    for idx, task in enumerate(tasks):
        if not isinstance(task, dict):
            strong_error(f"tasks[{idx}]")
            continue
        for field in sorted(task_required):
            if field not in task:
                strong_error(f"tasks[{idx}].{field}")
        if not isinstance(task.get("allowed_files"), list) or not task.get("allowed_files"):
            strong_error(f"tasks[{idx}].allowed_files")
        if not isinstance(task.get("modules"), list):
            strong_error(f"tasks[{idx}].modules")
        task_deps = task.get("dependencies")
        if not isinstance(task_deps, list):
            strong_error(f"tasks[{idx}].dependencies")
        else:
            local_deps = []
            task_id = str(task.get("id") or "")
            source_prefix = str(source_id or data.get("epic") or "").strip()
            for dep_idx, dep in enumerate(task_deps):
                dep_value = str(dep).strip()
                if not dep_value:
                    strong_error(f"tasks[{idx}].dependencies[{dep_idx}]")
                    continue
                is_short_work_item = re.fullmatch(r"[TV][0-9]+[a-z]?", dep_value) is not None
                full_match = re.fullmatch(r"([A-Z][A-Z0-9]*-[0-9]+)-([TV][0-9]+[a-z]?)", dep_value)
                is_full_work_item = full_match is not None
                is_bare_source = re.fullmatch(r"[A-Z][A-Z0-9]*-[0-9]+", dep_value) is not None
                if is_bare_source and not is_full_work_item:
                    errors.append(
                        "POLARIS_REFINEMENT_TASK_DEPENDENCY_INVALID: "
                        f"tasks[{idx}].dependencies[{dep_idx}]='{dep_value}' is a bare source id; "
                        "put predecessor sources in top-level dependencies[], not task dependencies"
                    )
                    continue
                if not is_short_work_item and not is_full_work_item:
                    errors.append(
                        "POLARIS_REFINEMENT_TASK_DEPENDENCY_INVALID: "
                        f"tasks[{idx}].dependencies[{dep_idx}]='{dep_value}' must be a short work item "
                        "(T1/V1) or full work item (DP-231-T1)"
                    )
                    continue
                if is_short_work_item or (full_match and full_match.group(1) == source_prefix):
                    local_deps.append(dep_value)
            if re.fullmatch(r"[A-Z][A-Z0-9]*-[0-9]+-T[0-9]+[a-z]?", task_id) and len(local_deps) > 1:
                errors.append(
                    "POLARIS_REFINEMENT_TASK_DEPENDENCY_INVALID: "
                    f"task {task_id} has non-linear local dependencies {local_deps}; "
                    "breakdown task.md dependency binding is linear"
                )
        if not isinstance(task.get("estimate_points"), (int, float)):
            strong_error(f"tasks[{idx}].estimate_points")
        if not isinstance(task.get("verification"), dict):
            strong_error(f"tasks[{idx}].verification")
        task_ac_ids = task.get("ac_ids")
        if not isinstance(task_ac_ids, list) or not task_ac_ids:
            strong_error(f"tasks[{idx}].ac_ids")
        else:
            for aid in task_ac_ids:
                if str(aid) not in ac_ids:
                    strong_error(f"tasks[{idx}].ac_ids[{aid}]")

adversarial_pass = data.get("adversarial_pass")
if not isinstance(adversarial_pass, list) or not adversarial_pass:
    strong_error("adversarial_pass")
else:
    for idx, item in enumerate(adversarial_pass):
        if not isinstance(item, dict):
            strong_error(f"adversarial_pass[{idx}]")
            continue
        for field in ("ac_id", "attack", "enforce"):
            if not isinstance(item.get(field), str) or not item.get(field).strip():
                strong_error(f"adversarial_pass[{idx}].{field}")
        if str(item.get("ac_id")) not in ac_ids:
            strong_error(f"adversarial_pass[{idx}].ac_id")

bug_fields = {"reproduction", "root_cause", "source_pr", "severity", "impact_scope", "regression"}
present_bug_fields = bug_fields & set(data.keys())
if source_type == "bug":
    for field in sorted(bug_fields):
        if field not in data:
            strong_error(field)
else:
    for field in sorted(present_bug_fields):
        strong_error(field)

if errors:
    for e in errors:
        print(e)
    sys.exit(1)

sys.exit(0)
PY
)
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    return 0
  fi

  echo "✗ refinement.json schema violations in $file:" >&2
  while IFS= read -r line; do
    [[ -n "$line" ]] && echo "  - $line" >&2
  done <<< "$result"
  echo "" >&2
  echo "Contract: skills/references/pipeline-handoff.md § Artifact Schemas — refinement.json" >&2
  return 1
}

# Scan mode: walk workspace, report per-file status, always exit 0.
if [[ "$1" == "--scan" ]]; then
  if [[ $# -ne 2 ]]; then
    usage
  fi
  root="$2"
  if [[ ! -d "$root" ]]; then
    echo "error: scan root not found: $root" >&2
    exit 2
  fi

  pass=0
  fail=0
  specs_root="$root/docs-manager/src/content/docs/specs"
  if [[ -d "$specs_root" ]]; then
    search_root="$specs_root"
  else
    search_root="$root"
  fi

  # Prefer the canonical specs root when available; fallback keeps backward compatibility for
  # ad-hoc paths while still pruning known non-source trees.
  while IFS= read -r f; do
    if validate_file "$f" >/dev/null 2>&1; then
      printf "PASS  %s\n" "$f"
      pass=$((pass+1))
    else
      printf "FAIL  %s\n" "$f"
      # Re-run to print errors without aborting scan mode on the first failing artifact.
      set +e
      error_output="$(validate_file "$f" 2>&1)"
      set -e
      while IFS= read -r line; do
        [[ -n "$line" ]] && printf '      %s\n' "$line" >&2
      done <<< "$error_output"
      fail=$((fail+1))
    fi
  done < <(
    find "$search_root" \
      \( -path '*/.git/*' -o -path '*/.worktrees/*' -o -path '*/node_modules/*' -o -path '*/archive/*' \) -prune \
      -o -type f -name 'refinement.json' -print 2>/dev/null | sort
  )

  echo ""
  echo "refinement.json scan: $pass pass, $fail fail (total $((pass+fail)))"
  exit 0
fi

# Single-file mode
validate_file "$1"
exit $?
