#!/usr/bin/env bash
# Purpose: deterministic gate that binds every DECLARED refinement.json consumer to
#          the canonical tasks[] schema field whitelist (the field set validated by
#          scripts/validate-refinement-json.sh, the SINGLE SOURCE OF TRUTH). If a
#          declared consumer reads a tasks[]-entry field OUTSIDE that whitelist the
#          gate fails closed; a refinement.json tasks[] consumer that is not
#          registered also fails closed (forcing registration). This is NOT a static
#          literal `grep planned_tasks` scan — the whitelist is derived from the
#          schema validator source, so dynamic-field-access drift is caught by the
#          out-of-schema field rule rather than a bypassable literal match (AC3).
#
#          DP-298 T4 (AC3/AC5) adds the DELIVERY/RECEIVING-BOUNDARY language check:
#          when one or more --refinement-json targets are supplied, the gate also
#          binds the prose-field language invariant. Each target refinement.json is
#          handed to validate-language-policy.sh --mode json-fields (the SINGLE
#          language detector authored in DP-298 T3 — no second heuristic); a
#          non-config-language human-facing prose field (tasks[].title / scope,
#          acceptance_criteria[].text) fails the consumer gate closed, naming the
#          violating field path. This binds "what the consumer receives" to
#          "producer output is already config language". When no --refinement-json
#          target is supplied the language boundary check is skipped, so the repo-wide
#          framework-pr-gate run keeps the schema-binding-only behaviour (and does not
#          retroactively block legacy refinement.json artifacts).
# Inputs:  optional --root <repo> (defaults to the script's repo root); env override
#          POLARIS_REFINEMENT_SCHEMA_VALIDATOR for the canonical schema source;
#          repeatable --refinement-json <path> for receiving-boundary language checks;
#          optional --language <LANG> / --workspace-root <dir> passed through to the
#          language gate (default: workspace-config.yaml language under --root).
# Outputs: stdout "PASS: refinement consumer schema binding" on success;
#          exit 2 + POLARIS_REFINEMENT_CONSUMER_SCHEMA_BINDING:{detail} on violation;
#          exit 2 on usage / IO error.
#
# Declared consumer registry (refinement.json canonical tasks[] consumers):
#   - scripts/derive-task-md-from-refinement-json.sh   (task-entry vars: match, entry)
#   - scripts/validate-refinement-lock-preflight.sh    (task-entry vars: entry)
#   - scripts/lib/refinement-md-generator.py           (task-entry vars: task)
#   - scripts/lib/refinement-module-ac-coverage.py     (task-entry vars: task)
# Adding a new script that reads refinement.json tasks[]-entry fields requires
# registering it below AND in the python REGISTRY mapping; an unregistered consumer
# (detected via the discovery scan) is a fail-stop until registered.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANGUAGE_OVERRIDE=""
WORKSPACE_ROOT_OVERRIDE=""
REFINEMENT_TARGETS=()

usage() {
  cat >&2 <<'USAGE'
usage: validate-refinement-consumer-schema-binding.sh [--root <repo>]
                                                      [--refinement-json <path>]...
                                                      [--language <LANG>]
                                                      [--workspace-root <dir>]
USAGE
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_DIR="${2:?--root needs a value}"; shift 2 ;;
    --refinement-json) REFINEMENT_TARGETS+=("${2:?--refinement-json needs a value}"); shift 2 ;;
    --language) LANGUAGE_OVERRIDE="${2:?--language needs a value}"; shift 2 ;;
    --workspace-root) WORKSPACE_ROOT_OVERRIDE="${2:?--workspace-root needs a value}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  exit 2
fi

SCHEMA_VALIDATOR="${POLARIS_REFINEMENT_SCHEMA_VALIDATOR:-$ROOT_DIR/scripts/validate-refinement-json.sh}"
LANGUAGE_POLICY_BIN="${POLARIS_VALIDATE_LANGUAGE_POLICY_BIN:-$ROOT_DIR/scripts/validate-language-policy.sh}"

python3 - "$ROOT_DIR" "$SCHEMA_VALIDATOR" <<'PY'
"""Bind declared refinement.json consumers to the canonical tasks[] schema whitelist.

The canonical whitelist is the single source of truth: it is extracted from
scripts/validate-refinement-json.sh (the schema validator). Two anchors are read:

  1. the `task_required = { ... }` set literal (required tasks[] fields), and
  2. every `if "<field>" in task:` line (first-class validated-when-present fields
     such as task_shape / tracked_deliverable_hint / jira_key).

Their union is the canonical tasks[]-entry field whitelist. Each DECLARED consumer
is scanned for the tasks[]-entry fields it reads (restricted to its registered
task-entry accessor variables so top-level data.get(...) reads are not misattributed).
Any consumer read of a field outside the whitelist fails closed. A script that reads
refinement.json tasks[]-entry fields but is not registered also fails closed.
"""
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
schema_validator = Path(sys.argv[2]).resolve()

errors = []


def fail(detail):
    errors.append(detail)


# --- 1. Extract the canonical tasks[] field whitelist (single source of truth) ---
def extract_schema_whitelist(path):
    if not path.is_file():
        fail(f"schema validator not found: {path} "
             "(POLARIS_REFINEMENT_SCHEMA_VALIDATOR / scripts/validate-refinement-json.sh)")
        return set()
    text = path.read_text()
    whitelist = set()

    # Anchor 1: task_required = { "id", "kind", ... }
    block = re.search(r"task_required\s*=\s*\{(.*?)\}", text, re.DOTALL)
    if block is None:
        fail("could not locate `task_required = { ... }` set in schema validator; "
             "the canonical whitelist anchor is missing or renamed")
    else:
        whitelist |= set(re.findall(r'"([^"]+)"', block.group(1)))

    # Anchor 2: first-class validated-when-present fields — `if "X" in task:`
    whitelist |= set(re.findall(r'if\s+"([^"]+)"\s+in\s+task\s*:', text))

    if not whitelist:
        fail("extracted an empty canonical tasks[] field whitelist from schema "
             "validator; refusing to pass (fail-closed on missing SoT input)")
    return whitelist


WHITELIST = extract_schema_whitelist(schema_validator)

# --- 2. Declared consumer registry --------------------------------------------
# path (repo-relative) -> tuple of task-entry accessor variable names. Field reads
# are only attributed to the whitelist check when they are subkey accesses on one
# of these variables, so top-level data.get(...) reads are not misclassified.
REGISTRY = {
    "scripts/derive-task-md-from-refinement-json.sh": ("match", "entry"),
    "scripts/validate-refinement-lock-preflight.sh": ("entry",),
    "scripts/lib/refinement-md-generator.py": ("task",),
    "scripts/lib/refinement-module-ac-coverage.py": ("task",),
}


def consumer_field_reads(text, accessor_vars):
    """Return the set of tasks[]-entry field literals read via the accessor vars."""
    fields = set()
    for var in accessor_vars:
        # var["field"] and var['field']
        fields |= set(re.findall(rf'\b{re.escape(var)}\[\s*"([^"]+)"\s*\]', text))
        fields |= set(re.findall(rf"\b{re.escape(var)}\[\s*'([^']+)'\s*\]", text))
        # var.get("field") and var.get('field')
        fields |= set(re.findall(rf'\b{re.escape(var)}\.get\(\s*"([^"]+)"', text))
        fields |= set(re.findall(rf"\b{re.escape(var)}\.get\(\s*'([^']+)'", text))
    # required_fields / task_required tuples or sets iterated then `match[field]`:
    # capture `required_fields = ( "id", "title", ... )` style literals that the
    # consumer loops over to access task-entry fields.
    for m in re.finditer(r"required_fields\s*=\s*\(([^)]*)\)", text):
        fields |= set(re.findall(r'"([^"]+)"', m.group(1)))
        fields |= set(re.findall(r"'([^']+)'", m.group(1)))
    return fields


# --- 3. Scan declared consumers against the whitelist -------------------------
for rel, accessor_vars in sorted(REGISTRY.items()):
    path = root / rel
    if not path.is_file():
        fail(f"declared consumer not found: {rel} "
             "(registry references a missing file)")
        continue
    text = path.read_text()
    reads = consumer_field_reads(text, accessor_vars)
    out_of_schema = sorted(f for f in reads if f not in WHITELIST)
    for field in out_of_schema:
        fail(f"consumer {rel} reads tasks[]-entry field '{field}' which is OUTSIDE "
             f"the canonical schema whitelist {sorted(WHITELIST)}; either add the "
             "field to scripts/validate-refinement-json.sh schema or stop reading it")


# --- 4. Registration enforcement: discover unregistered tasks[] consumers ------
# A script that reads refinement.json AND accesses tasks[] entries via a recognised
# accessor variable but is not in REGISTRY must be registered. Schema-authoring and
# migration scripts are excluded by design (they own / rewrite the schema itself).
DISCOVERY_EXCLUDE = {
    # the schema validator (owns the whitelist) and the migration script that
    # rewrites the schema are not consumers in the binding sense.
    "scripts/validate-refinement-json.sh",
    "scripts/migrate-refinement-planned-tasks-to-canonical.sh",
    "scripts/migrate-refinement-packaging-fields.sh",
    # this gate is the schema-binding meta-scanner, not a tasks[] consumer; its
    # REGISTRY / regex literals would otherwise self-trip the discovery heuristic.
    "scripts/validate-refinement-consumer-schema-binding.sh",
}
# Accessor-variable patterns that indicate per-task-entry field reads bound to a
# tasks[] iteration. `data.get("tasks")` / `data["tasks"]` plus a subsequent entry
# accessor (.get on entry/match/task within the same file) is the discovery signal.
TASKS_ITER_RE = re.compile(r'data\s*(?:\.get\(\s*["\']tasks["\']|\[\s*["\']tasks["\']\s*\])')

scripts_dir = root / "scripts"
if scripts_dir.is_dir():
    for path in sorted(scripts_dir.rglob("*")):
        if not path.is_file() or path.suffix not in (".sh", ".py"):
            continue
        rel = path.relative_to(root).as_posix()
        if rel in REGISTRY or rel in DISCOVERY_EXCLUDE:
            continue
        if "/selftests/" in rel:
            continue
        try:
            text = path.read_text()
        except (UnicodeDecodeError, OSError):
            continue
        if "refinement.json" not in text and "refinement_json" not in text:
            continue
        # Does it iterate tasks[] AND read entry fields via a task-entry accessor?
        if not TASKS_ITER_RE.search(text):
            continue
        entry_reads = consumer_field_reads(
            text, ("match", "entry", "task", "t")
        )
        if entry_reads:
            fail(f"unregistered refinement.json tasks[] consumer: {rel} reads "
                 f"tasks[]-entry fields {sorted(entry_reads)} but is not in the "
                 "declared consumer registry; register it in "
                 "scripts/validate-refinement-consumer-schema-binding.sh (REGISTRY) "
                 "so its field reads are schema-bound")

if errors:
    for e in errors:
        print(f"POLARIS_REFINEMENT_CONSUMER_SCHEMA_BINDING:{e}", file=sys.stderr)
    sys.exit(2)
PY

# --- 5. Delivery/receiving-boundary language check (DP-298 T4, AC3/AC5) ---------
# The schema-binding + registration checks above passed (any failure would have
# exited the python block with status 2 under `set -e`). When the caller supplies
# one or more refinement.json delivery targets, bind the prose-field language
# invariant: each target must already be config language. We delegate to the
# DP-298 T3 json-fields language gate — the single authored detector — instead of
# re-implementing a second language heuristic here (canonical-contract-governance:
# one canonical writer/detector path).
if [[ ${#REFINEMENT_TARGETS[@]} -gt 0 ]]; then
  if [[ ! -f "$LANGUAGE_POLICY_BIN" ]]; then
    echo "POLARIS_REFINEMENT_CONSUMER_SCHEMA_BINDING:language gate not found: ${LANGUAGE_POLICY_BIN} (POLARIS_VALIDATE_LANGUAGE_POLICY_BIN / scripts/validate-language-policy.sh)" >&2
    exit 2
  fi

  lang_args=(--blocking --mode json-fields)
  if [[ -n "$LANGUAGE_OVERRIDE" ]]; then
    lang_args+=(--language "$LANGUAGE_OVERRIDE")
  fi
  if [[ -n "$WORKSPACE_ROOT_OVERRIDE" ]]; then
    lang_args+=(--workspace-root "$WORKSPACE_ROOT_OVERRIDE")
  fi

  boundary_failed=0
  for target in "${REFINEMENT_TARGETS[@]}"; do
    if [[ ! -f "$target" ]]; then
      echo "POLARIS_REFINEMENT_CONSUMER_SCHEMA_BINDING:refinement.json delivery target not found: ${target}" >&2
      boundary_failed=1
      continue
    fi
    set +e
    lang_stderr="$(bash "$LANGUAGE_POLICY_BIN" "${lang_args[@]}" "$target" 2>&1 1>/dev/null)"
    lang_rc=$?
    set -e
    if [[ "$lang_rc" -ne 0 ]]; then
      # The language gate names each violating field path (e.g. tasks[0].title);
      # surface those lines under the consumer-gate marker so the boundary failure
      # is grep-able with the same POLARIS_REFINEMENT_CONSUMER_SCHEMA_BINDING token.
      echo "POLARIS_REFINEMENT_CONSUMER_SCHEMA_BINDING:delivery boundary language violation in ${target} (producer output is not config language); offending fields:" >&2
      printf '%s\n' "$lang_stderr" | sed 's/^/  /' >&2
      boundary_failed=1
    fi
  done

  if [[ "$boundary_failed" -ne 0 ]]; then
    exit 2
  fi
fi

echo "PASS: refinement consumer schema binding"
