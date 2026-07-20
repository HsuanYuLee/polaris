"""綁定 refinement.json consumer 與 canonical tasks[] schema。"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


def usage() -> int:
    print("usage: validate-refinement-consumer-schema-binding.sh [--root <repo>]", file=sys.stderr)
    print("                                                      [--refinement-json <path>]...", file=sys.stderr)
    print("                                                      [--language <LANG>]", file=sys.stderr)
    print("                                                      [--workspace-root <dir>]", file=sys.stderr)
    return 2


raw_args = sys.argv[1:]
if any(arg in {"-h", "--help"} for arg in raw_args):
    raise SystemExit(usage())
parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
parser.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
parser.add_argument("--refinement-json", action="append", default=[])
parser.add_argument("--language", default="")
parser.add_argument("--workspace-root", default="")
try:
    cli = parser.parse_args(raw_args)
except SystemExit:
    raise SystemExit(usage())

root_path = Path(cli.root).resolve()
schema_path = Path(
    os.environ.get(
        "POLARIS_REFINEMENT_SCHEMA_VALIDATOR",
        str(root_path / "scripts/validate-refinement-json.sh"),
    )
)
registry_path = Path(
    os.environ.get(
        "POLARIS_REFINEMENT_CONSUMER_REGISTRY",
        str(root_path / "scripts/refinement-consumer-registry.json"),
    )
)
language_policy = Path(
    os.environ.get(
        "POLARIS_VALIDATE_LANGUAGE_POLICY_BIN",
        str(root_path / "scripts/validate-language-policy.sh"),
    )
)
sys.argv = [sys.argv[0], str(root_path), str(schema_path), str(registry_path)]

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
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
schema_validator = Path(sys.argv[2]).resolve()
consumer_registry = Path(sys.argv[3]).resolve()

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
    shim_target = re.search(r'exec python3 "\$SCRIPT_DIR/([^"\n]+)" "\$@"', text)
    if shim_target:
        delegated = path.parent / shim_target.group(1)
        if not delegated.is_file():
            fail(f"schema validator shim target not found: {path} -> {delegated}")
            return set()
        text = delegated.read_text(encoding="utf-8")
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
def load_consumer_registry(path):
    if not path.is_file():
        fail(f"consumer registry not found: {path}")
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"consumer registry is not valid JSON: {exc}")
        return {}
    if data.get("schema_version") != 1 or not isinstance(data.get("consumers"), list):
        fail("consumer registry requires schema_version=1 and consumers[]")
        return {}
    result = {}
    for index, record in enumerate(data["consumers"]):
        if not isinstance(record, dict):
            fail(f"consumer registry consumers[{index}] must be an object")
            continue
        rel = record.get("path")
        accessors = record.get("accessor_vars")
        expected_fields = record.get("expected_fields")
        if not isinstance(rel, str) or not rel.startswith("scripts/"):
            fail(f"consumer registry consumers[{index}].path must be scripts/... repo-relative")
            continue
        if rel in result:
            fail(f"consumer registry duplicate path: {rel}")
            continue
        if not isinstance(accessors, list) or not accessors or any(not isinstance(v, str) or not v for v in accessors):
            fail(f"consumer registry {rel} accessor_vars must be a non-empty string array")
            continue
        if (not isinstance(expected_fields, dict)
                or set(expected_fields) != set(accessors)
                or any(not isinstance(fields, list) or not fields
                       or any(not isinstance(field, str) or not field for field in fields)
                       or len(fields) != len(set(fields))
                       for fields in expected_fields.values())):
            fail(f"consumer registry {rel} expected_fields must bind every accessor_var to a non-empty unique string array")
            continue
        result[rel] = {
            "accessor_vars": tuple(accessors),
            "expected_fields": {var: set(expected_fields[var]) for var in accessors},
        }
    return result


REGISTRY = load_consumer_registry(consumer_registry)


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
        # Dynamic required_fields reads belong to this accessor only when the
        # consumer actually dereferences that accessor with the loop variable.
        # Without this binding, a bogus accessor could inherit an unrelated tuple
        # and make expected_fields non-vacuity pass.
        dynamic_read = (
            re.search(rf'\b{re.escape(var)}\[\s*field\s*\]', text)
            or re.search(rf'\b{re.escape(var)}\.get\(\s*field\b', text)
        )
        if dynamic_read:
            for m in re.finditer(r"required_fields\s*=\s*\(([^)]*)\)", text):
                fields |= set(re.findall(r'"([^"]+)"', m.group(1)))
                fields |= set(re.findall(r"'([^']+)'", m.group(1)))
    return fields


# --- 3. Scan declared consumers against the whitelist -------------------------
for rel, binding in sorted(REGISTRY.items()):
    path = root / rel
    if not path.is_file():
        fail(f"declared consumer not found: {rel} "
             "(registry references a missing file)")
        continue
    text = path.read_text()
    shim_target = re.search(r'exec python3 "\$SCRIPT_DIR/([^"\n]+)" "\$@"', text)
    if shim_target:
        delegated = path.parent / shim_target.group(1)
        if not delegated.is_file():
            fail(f"declared consumer shim target not found: {rel} -> {delegated}")
            continue
        text = delegated.read_text(encoding="utf-8")
    accessor_vars = binding["accessor_vars"]
    reads = consumer_field_reads(text, accessor_vars)
    for accessor_var in accessor_vars:
        live_reads = consumer_field_reads(text, (accessor_var,))
        missing_expected = sorted(binding["expected_fields"][accessor_var] - live_reads)
        if missing_expected:
            fail(f"consumer {rel} accessor '{accessor_var}' has stale/missing live binding for "
                 f"expected fields {missing_expected}; actual reads={sorted(live_reads)}")
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
    "scripts/lib/refinement_validate_json.py",
    "scripts/lib/refinement_migrate_planned_tasks.py",
    "scripts/lib/refinement_migrate_packaging_fields.py",
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

if cli.refinement_json:
    if not language_policy.is_file():
        print(
            f"POLARIS_REFINEMENT_CONSUMER_SCHEMA_BINDING:language gate not found: {language_policy} "
            "(POLARIS_VALIDATE_LANGUAGE_POLICY_BIN / scripts/validate-language-policy.sh)",
            file=sys.stderr,
        )
        raise SystemExit(2)
    language_args = ["--blocking", "--mode", "json-fields"]
    if cli.language:
        language_args += ["--language", cli.language]
    if cli.workspace_root:
        language_args += ["--workspace-root", cli.workspace_root]
    boundary_failed = False
    for target_arg in cli.refinement_json:
        target = Path(target_arg)
        if not target.is_file():
            print(
                f"POLARIS_REFINEMENT_CONSUMER_SCHEMA_BINDING:refinement.json delivery target not found: {target}",
                file=sys.stderr,
            )
            boundary_failed = True
            continue
        result = subprocess.run(
            ["bash", str(language_policy), *language_args, str(target)],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode:
            print(
                "POLARIS_REFINEMENT_CONSUMER_SCHEMA_BINDING:delivery boundary language "
                f"violation in {target} (producer output is not config language); offending fields:",
                file=sys.stderr,
            )
            combined = (result.stderr + result.stdout).rstrip()
            if combined:
                for line in combined.splitlines():
                    print(f"  {line}", file=sys.stderr)
            boundary_failed = True
    if boundary_failed:
        raise SystemExit(2)

print("PASS: refinement consumer schema binding")
