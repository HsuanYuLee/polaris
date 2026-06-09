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
# Inputs:  optional --root <repo> (defaults to the script's repo root); env override
#          POLARIS_REFINEMENT_SCHEMA_VALIDATOR for the canonical schema source.
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

usage() {
  cat >&2 <<'USAGE'
usage: validate-refinement-consumer-schema-binding.sh [--root <repo>]
USAGE
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_DIR="${2:?--root needs a value}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  exit 2
fi

SCHEMA_VALIDATOR="${POLARIS_REFINEMENT_SCHEMA_VALIDATOR:-$ROOT_DIR/scripts/validate-refinement-json.sh}"

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

print("PASS: refinement consumer schema binding")
PY
