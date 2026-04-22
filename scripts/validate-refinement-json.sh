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

# Core validator: print violations to stderr, return 0 (pass) / 1 (fail).
validate_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "error: file not found: $file" >&2
    return 2
  fi

  # Delegate structural validation to python3 — regex parsing of JSON is fragile.
  local result
  result=$(python3 - "$file" <<'PY'
import json
import re
import sys

path = sys.argv[1]
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

# --- Top-level required fields ---
def require_nonempty_string(field):
    val = data.get(field)
    if not isinstance(val, str) or not val.strip():
        errors.append(f"missing or empty required field: '{field}' (expected non-empty string)")
        return None
    return val

epic = require_nonempty_string("epic")
if epic is not None and not JIRA_KEY.match(epic):
    errors.append(f"'epic' value '{epic}' does not match JIRA key format [A-Z][A-Z0-9]+-[0-9]+")

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

if errors:
    for e in errors:
        print(e)
    sys.exit(1)

sys.exit(0)
PY
)
  local rc=$?

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
  # Match both company-scoped and root-scoped specs. Max depth limited to avoid .worktrees / node_modules.
  while IFS= read -r f; do
    # Skip files under .worktrees/ or node_modules/
    case "$f" in
      */.worktrees/*|*/node_modules/*|*/archive/*) continue ;;
    esac
    if validate_file "$f" >/dev/null 2>&1; then
      printf "PASS  %s\n" "$f"
      pass=$((pass+1))
    else
      printf "FAIL  %s\n" "$f"
      # Re-run to print errors
      validate_file "$f" 2>&1 | sed 's/^/      /' >&2
      fail=$((fail+1))
    fi
  done < <(find "$root" -type f -name 'refinement.json' 2>/dev/null | sort)

  echo ""
  echo "refinement.json scan: $pass pass, $fail fail (total $((pass+fail)))"
  exit 0
fi

# Single-file mode
validate_file "$1"
exit $?
