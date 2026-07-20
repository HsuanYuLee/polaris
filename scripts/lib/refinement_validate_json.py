"""refinement.json 的 canonical schema validator。"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def usage() -> int:
    cli = os.environ.get("POLARIS_COMPAT_CLI", "validate-refinement-json.sh")
    print(f"usage: {cli} <path/to/refinement.json>", file=sys.stderr)
    print(f"       {cli} --scan <workspace_root>", file=sys.stderr)
    return 2


def validate_formatted(path: Path, quiet: bool = False) -> int:
    if not path.is_file():
        if not quiet:
            print(f"error: file not found: {path}", file=sys.stderr)
        return 2
    result = subprocess.run(
        [sys.executable, __file__, "--raw", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode and not quiet:
        print(f"✗ refinement.json schema violations in {path}:", file=sys.stderr)
        for line in result.stdout.splitlines():
            if line:
                print(f"  - {line}", file=sys.stderr)
        print("", file=sys.stderr)
        print(
            "Contract: skills/references/pipeline-handoff.md § Artifact Schemas — refinement.json",
            file=sys.stderr,
        )
    return result.returncode


def scan(root: Path) -> int:
    if not root.is_dir():
        print(f"error: scan root not found: {root}", file=sys.stderr)
        return 2
    specs_root = root / "docs-manager/src/content/docs/specs"
    search_root = specs_root if specs_root.is_dir() else root
    paths = sorted(
        path for path in search_root.rglob("refinement.json")
        if not any(part in {".git", ".worktrees", "node_modules", "archive"} for part in path.parts)
    )
    passed = failed = 0
    for path in paths:
        rc = validate_formatted(path, quiet=True)
        print(f"{'PASS' if rc == 0 else 'FAIL'}  {path}")
        if rc == 0:
            passed += 1
        else:
            failed += 1
            result = subprocess.run(
                [sys.executable, __file__, str(path)],
                capture_output=True,
                text=True,
                check=False,
            )
            for line in result.stderr.splitlines():
                if line:
                    print(f"      {line}", file=sys.stderr)
    print("")
    print(f"refinement.json scan: {passed} pass, {failed} fail (total {passed + failed})")
    return 0


args = sys.argv[1:]
if args and args[0] == "--raw":
    if len(args) != 2:
        raise SystemExit(usage())
    sys.argv = [sys.argv[0], args[1]]
elif args and args[0] == "--scan":
    if len(args) != 2:
        raise SystemExit(usage())
    raise SystemExit(scan(Path(args[1])))
elif args and args[0] in {"-h", "--help"}:
    raise SystemExit(usage())
elif len(args) != 1:
    raise SystemExit(usage())
else:
    raise SystemExit(validate_formatted(Path(args[0])))

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
    # DP-269 D1: JIRA-Epic-backed source must declare the product repo slug and
    # base branch so the derive jira mode can inject Repo / Base branch. These
    # are jira-only fields (mirrors the DP-228 jira-only consent field pattern);
    # the dp branch below fail-closes when they are present.
    if isinstance(source, dict):
        jira_repo = source.get("repo")
        if not isinstance(jira_repo, str) or not jira_repo.strip():
            errors.append("source.repo is required for source.type=jira (product repo slug)")
        jira_base_branch = source.get("base_branch")
        if not isinstance(jira_base_branch, str) or not jira_base_branch.strip():
            errors.append("source.base_branch is required for source.type=jira (product base branch)")
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
        if source_type == "bug":
            if jira_key not in (None, "", "N/A") and (
                not isinstance(jira_key, str) or not JIRA_KEY.match(jira_key)
            ):
                errors.append("source.jira_key must be a JIRA key, null, or N/A for source.type=bug")
        elif jira_key not in (None, "", "N/A"):
            errors.append(f"source.jira_key must be null/N/A for source.type={source_type}")

        # DP-269 AC-NEG1: source.repo stays a jira-only field. It must NOT appear
        # on a non-jira source (fail-closed, mirroring the DP-228 jira-only field
        # prohibition). This prevents the jira-only schema relaxation from leaking
        # into the non-jira branch.
        if source.get("repo") is not None:
            errors.append(
                f"POLARIS_REFINEMENT_JIRA_ONLY_FIELD: source.repo is jira-only and "
                f"must be absent for source.type={source_type}"
            )

        # DP-337: source.base_branch is graduated from a jira-only field to a
        # universal field, but only for dp sources (the feat-lane release model).
        #   - dp source, base_branch absent      → schema-optional (PASS). ~230
        #     historical dp refinement.json carry base_branch=None and must not be
        #     retroactively broken; the delivery-boundary required gate
        #     (validate-breakdown-ready.sh, T2) enforces presence at breakdown.
        #   - dp source, base_branch present      → must equal feat/<source.id>;
        #     any other value fail-closed with POLARIS_REFINEMENT_DP_BASE_BRANCH_INVALID.
        #   - other non-jira source (topic/etc.)  → base_branch stays jira-only
        #     (the graduation does not leak beyond dp).
        base_branch = source.get("base_branch")
        if base_branch is not None:
            if source_type == "dp":
                expected_base = f"feat/{source_id}" if source_id else None
                if not isinstance(base_branch, str) or base_branch != expected_base:
                    errors.append(
                        f"POLARIS_REFINEMENT_DP_BASE_BRANCH_INVALID: source.base_branch "
                        f"'{base_branch}' must equal 'feat/{source_id}' for source.type=dp"
                    )
            else:
                errors.append(
                    f"POLARIS_REFINEMENT_JIRA_ONLY_FIELD: source.base_branch is jira-only and "
                    f"must be absent for source.type={source_type}"
                )

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
# DP-359 D3 / AC-NF1: curated_tokens is the single source of truth for
# SCSS-removal scan tokens. It lives ONLY on the AC entry's verification block.
# Collect it here keyed by AC id (lowercased token strings) so the verify_command
# SCSS-removal subset gate below resolves the curated set from the AC entries the
# task references — there is no second token definition path.
ac_curated_tokens = {}
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

            # DP-359 D3: curated_tokens — optional, validated-when-present. When
            # present it must be an array of non-empty strings (the curated
            # SCSS/CSS class selector tokens this AC declares in scope). It is the
            # single source the SCSS-removal verify_command subset gate reads.
            if "curated_tokens" in ver:
                tokens = ver.get("curated_tokens")
                if not isinstance(tokens, list):
                    errors.append(
                        f"acceptance_criteria[{idx}].verification.curated_tokens "
                        "must be an array when present"
                    )
                else:
                    collected = []
                    for tidx, tok in enumerate(tokens):
                        if not isinstance(tok, str) or not tok.strip():
                            errors.append(
                                f"acceptance_criteria[{idx}].verification.curated_tokens[{tidx}] "
                                "must be a non-empty string"
                            )
                        else:
                            collected.append(tok.strip().lstrip(".").lower())
                    if isinstance(aid, str) and aid.strip():
                        ac_curated_tokens[aid.strip()] = set(collected)

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

# DP-417 T9: replaces_existing — optional source-level replacement discipline
# block. A refinement source that supersedes an existing mechanism declares it
# here so the LOCK preflight (validate-refinement-lock-preflight.sh) can enforce
# the enumeration gate (all existing sources enumerated with runtime/build-output
# evidence) and the anti-dead-code-port gate (ported symbols usage-checked). This
# block validates SHAPE only (validated-when-present, additive): a refinement
# WITHOUT the field is a non-replacing source and stays valid. The LOCK-time
# semantic gates (enumeration sufficiency / dead-symbol disposition) live in the
# single canonical preflight, not here — no second enforcement path.
VALID_EXISTING_SOURCE_EVIDENCE = {"runtime", "build-output", "cdn", "inline", "source-grep"}
VALID_PORT_DISPOSITION = {"removable", "kept"}
replaces_existing = data.get("replaces_existing")
if replaces_existing is not None:
    if not isinstance(replaces_existing, dict):
        errors.append("replaces_existing must be an object when present")
    else:
        replaced = replaces_existing.get("replaced")
        if not isinstance(replaced, str) or not replaced.strip():
            errors.append("replaces_existing.replaced must be a non-empty string")

        existing_sources = replaces_existing.get("existing_sources")
        if not isinstance(existing_sources, list) or not existing_sources:
            errors.append(
                "replaces_existing.existing_sources must be a non-empty array "
                "(enumerate ALL existing sources of the replaced thing)"
            )
        else:
            for sidx, src in enumerate(existing_sources):
                label = f"replaces_existing.existing_sources[{sidx}]"
                if not isinstance(src, dict):
                    errors.append(f"{label}: expected object, got {type(src).__name__}")
                    continue
                poc = src.get("path_or_channel")
                if not isinstance(poc, str) or not poc.strip():
                    errors.append(f"{label}.path_or_channel must be a non-empty string")
                evidence = src.get("evidence")
                if evidence not in VALID_EXISTING_SOURCE_EVIDENCE:
                    errors.append(
                        f"{label}.evidence must be one of {sorted(VALID_EXISTING_SOURCE_EVIDENCE)} "
                        f"(got: {evidence!r})"
                    )
                evidence_ref = src.get("evidence_ref")
                if not isinstance(evidence_ref, str) or not evidence_ref.strip():
                    errors.append(f"{label}.evidence_ref must be a non-empty string")

        # ported_symbols is optional (a pure removal ports nothing); validated
        # when present. usage_count must be a non-negative integer (bool excluded).
        ported_symbols = replaces_existing.get("ported_symbols")
        if ported_symbols is not None:
            if not isinstance(ported_symbols, list):
                errors.append("replaces_existing.ported_symbols must be an array when present")
            else:
                for pidx, sym in enumerate(ported_symbols):
                    label = f"replaces_existing.ported_symbols[{pidx}]"
                    if not isinstance(sym, dict):
                        errors.append(f"{label}: expected object, got {type(sym).__name__}")
                        continue
                    symbol = sym.get("symbol")
                    if not isinstance(symbol, str) or not symbol.strip():
                        errors.append(f"{label}.symbol must be a non-empty string")
                    usage_evidence = sym.get("usage_evidence")
                    if not isinstance(usage_evidence, str) or not usage_evidence.strip():
                        errors.append(f"{label}.usage_evidence must be a non-empty string")
                    usage_count = sym.get("usage_count")
                    if not isinstance(usage_count, int) or isinstance(usage_count, bool) or usage_count < 0:
                        errors.append(f"{label}.usage_count must be a non-negative integer")
                    disposition = sym.get("disposition")
                    if disposition not in VALID_PORT_DISPOSITION:
                        errors.append(
                            f"{label}.disposition must be one of {sorted(VALID_PORT_DISPOSITION)} "
                            f"(got: {disposition!r})"
                        )


def strong_error(field):
    errors.append(f"strong-bound schema: {field}")


# DP-302 T1: per-task verification body field schema. The derive
# (derive-task-md-from-refinement-json.sh, T2) reads these field-driven inputs to
# build the task.md body for ALL source types — no jira-only branch and no
# hardcoded framework default. They are validated-when-present: a task that omits
# them is still valid (back-compat with active refinement.json that predate the
# fields). When a field IS present its shape is enforced fail-loud so the derive
# never silently falls back to a framework default (AC3 / AC-NEG1).
VALID_TEST_ENVIRONMENT_LEVELS = {"static", "component", "integration", "runtime"}


def validate_task_verification_body(verification, label):
    # behavior_contract — object with required boolean `applies`; when
    # applies=false a non-empty `reason` must justify why no behavior contract
    # runs (mirrors the task.md frontmatter contract).
    if "behavior_contract" in verification:
        bc = verification.get("behavior_contract")
        if not isinstance(bc, dict):
            errors.append(f"{label}.behavior_contract must be an object when present")
        else:
            applies = bc.get("applies")
            if not isinstance(applies, bool):
                errors.append(f"{label}.behavior_contract.applies is required and must be boolean")
            elif applies is False:
                reason = bc.get("reason")
                if not isinstance(reason, str) or not reason.strip():
                    errors.append(
                        f"{label}.behavior_contract.applies=false requires a non-empty 'reason'"
                    )

    # test_environment — object with required `level` drawn from the canonical enum.
    if "test_environment" in verification:
        te = verification.get("test_environment")
        if not isinstance(te, dict):
            errors.append(f"{label}.test_environment must be an object when present")
        else:
            level = te.get("level")
            if not isinstance(level, str) or not level.strip():
                errors.append(f"{label}.test_environment.level is required and must be a non-empty string")
            elif level not in VALID_TEST_ENVIRONMENT_LEVELS:
                errors.append(
                    f"{label}.test_environment.level '{level}' is invalid "
                    f"(must be one of {sorted(VALID_TEST_ENVIRONMENT_LEVELS)})"
                )

    # verify_command — non-empty string (the task.md Verify Command body).
    if "verify_command" in verification:
        vc = verification.get("verify_command")
        if not isinstance(vc, str) or not vc.strip():
            errors.append(f"{label}.verify_command must be a non-empty string when present")

    # references — array of non-empty strings (the task.md References to load).
    if "references" in verification:
        refs = verification.get("references")
        if not isinstance(refs, list):
            errors.append(f"{label}.references must be an array when present")
        else:
            for ridx, ref in enumerate(refs):
                if not isinstance(ref, str) or not ref.strip():
                    errors.append(f"{label}.references[{ridx}] must be a non-empty string")


# DP-359 D4: SCSS-removal verify_command curated-token subset gate.
#
# A "SCSS-removal clause" is a negative-assertion `! rg ... <class-token> ...`
# that scans the SCSS/CSS layer (a path containing assets/style/css, or a *.scss
# / *.css path). It exists to assert that a CSS class selector no longer appears
# in the stylesheet layer after a Bootstrap-removal style refactor. The scanned
# class-token(s) must be a SUBSET of the curated-token set the task's AC entries
# declare (the single source of truth, AC-NF1). Over-scope — a scanned token not
# in the curated set, OR an un-anchored over-broad family pattern not tied to the
# curated-token list — is fail-closed exit 2 + POLARIS_REFINEMENT_SCSS_VERIFY_TOKEN_OVERSCOPE.
#
# This signals the SCSS-overscope verdict separately so the shell wrapper can
# propagate the distinct exit-2 contract (other schema violations stay exit 1).
scss_overscope_violation = [False]

# DP-341 / AC-NEG1: signals that a refinement.json tasks[] entry carried a
# forbidden per-task packaging field (allowed_files / estimate_points). Like the
# SCSS-overscope sentinel, this is a fail-closed A-class gate that exits 2
# (distinct from the generic schema exit 1) so the shell wrapper surfaces the
# dedicated contract. The gate fires for every source.type (dp + jira parity).
packaging_field_violation = [False]

# Match a negative ripgrep assertion: `! rg <flags...> '<pattern>' <path...>`.
# The pattern may be single- or double-quoted; trailing args carry the scan path.
# The clause body runs to the next SHELL command boundary (newline, `;`, `&&`,
# `||`) — a single `|` is NOT a boundary because it can be a regex-alternation
# `|` inside the quoted rg pattern (e.g. `'\.form-input|\.form-select'`); the
# quoted pattern is pulled out by _split_rg_args, which keeps the alternation
# intact.
_SCSS_RG_CLAUSE = re.compile(r"!\s*rg\b(.*?)(?=$|;|&&|\|\||\n)", re.MULTILINE)
# A scan target that hits the SCSS/CSS layer.
_SCSS_PATH = re.compile(r"(assets/style/css|\.scss\b|\.css\b)")
# Extract class tokens from an rg pattern: `\.<token>` occurrences. The leading
# `\.` anchors the token to a class selector; a bare token without it is treated
# as an un-anchored over-broad family pattern.
_SCSS_ANCHORED_TOKEN = re.compile(r"\\\.([A-Za-z][A-Za-z0-9_-]*)")
# A family-style metacharacter in the pattern (wildcard / char class / etc.)
# beyond the anchored class tokens marks it over-broad when not pinned to curated.
_SCSS_BARE_DOTSTAR = re.compile(r"\\\.[A-Za-z][A-Za-z0-9_-]*[*+?]")


def _split_rg_args(segment):
    # Split an rg invocation tail into (first quoted-or-bare pattern, rest path
    # args). `segment` is the text following `! rg` up to the clause terminator.
    # The pattern may be single- or double-quoted; the rest carries the scan path.
    dq = chr(34)
    # Match a single-quoted OR double-quoted argument (group 2 / group 3).
    quoted_re = re.compile("('([^']*)'|" + dq + "([^" + dq + "]*)" + dq + ")")
    m = quoted_re.search(segment)
    if m:
        pattern = m.group(2) if m.group(2) is not None else m.group(3)
        rest = segment[m.end():]
        return pattern, rest
    # Fallback: first whitespace-delimited non-flag token is the pattern.
    non_flags = [t for t in segment.split() if not t.startswith("-")]
    if not non_flags:
        return "", ""
    return non_flags[0], " ".join(non_flags[1:])


def check_scss_removal_verify_command(verify_command, curated, label):
    """Gate an SCSS-removal verify_command against the curated-token set.

    Args:
        verify_command: the task verify_command string.
        curated: set of curated token strings (lowercased, no leading dot).
        label: task label for error messages.

    Side effects: appends to `errors` and flips scss_overscope_violation on
        over-scope; no-op when the command carries no SCSS-removal clause.
    """
    if not isinstance(verify_command, str) or not verify_command:
        return
    for m in _SCSS_RG_CLAUSE.finditer(verify_command):
        tail = m.group(1)
        pattern, rest = _split_rg_args(tail)
        scan_path = rest if rest.strip() else tail
        # Only an rg negative assertion that scans the SCSS/CSS layer is a
        # SCSS-removal clause (AC-NEG1: non-SCSS commands are no-ops).
        if not _SCSS_PATH.search(scan_path):
            continue
        # Over-broad family pattern (e.g. `\.modal[s-]?`) not pinned to curated:
        # an anchored token followed by a regex quantifier widens the match
        # beyond the exact curated selector.
        if _SCSS_BARE_DOTSTAR.search(pattern):
            errors.append(
                f"POLARIS_REFINEMENT_SCSS_VERIFY_TOKEN_OVERSCOPE: {label}.verify_command "
                f"uses an un-anchored over-broad family pattern '{pattern}' not tied to "
                "the AC curated-token list"
            )
            scss_overscope_violation[0] = True
            continue
        # A bare `\.<token>` (e.g. `\.modal`, `\.btn`) IS an anchored token; it
        # is rejected by the subset check below when <token> is not curated —
        # that is exactly the "bare family pattern not tied to curated" case.
        scanned = {t.lower() for t in _SCSS_ANCHORED_TOKEN.findall(pattern)}
        overscoped = sorted(t for t in scanned if t not in curated)
        if overscoped:
            errors.append(
                f"POLARIS_REFINEMENT_SCSS_VERIFY_TOKEN_OVERSCOPE: {label}.verify_command "
                f"scans SCSS token(s) {overscoped} not in the AC curated-token set "
                f"{sorted(curated)} (curated-token is the single source of truth)"
            )
            scss_overscope_violation[0] = True


# DP-296: top-level planned_tasks[] is removed. task_shape /
# tracked_deliverable_hint are now first-class tasks[] fields (canonical home).
# Reject any artifact that still carries a top-level planned_tasks[] key
# (fail-closed; no bypass). Migrate via
# scripts/migrate-refinement-planned-tasks-to-canonical.sh.
if "planned_tasks" in data:
    errors.append(
        "POLARIS_REFINEMENT_LEGACY_PLANNED_TASKS: top-level 'planned_tasks[]' is "
        "removed (DP-296); task_shape / tracked_deliverable_hint are now first-class "
        "tasks[] fields. Run scripts/migrate-refinement-planned-tasks-to-canonical.sh "
        "to fold planned_tasks[] into tasks[]."
    )

schema_version = data.get("schema_version")
if schema_version in (None, ""):
    strong_error("schema_version")

verification_strategy = data.get("verification_strategy")
if verification_strategy is not None:
    if not isinstance(verification_strategy, dict):
        errors.append("verification_strategy must be an object when present")
    else:
        strategy_mode = verification_strategy.get("mode")
        valid_strategy_modes = {"per_task_self_verify", "source_level_v_required", "external_ac_ticket"}
        if strategy_mode not in valid_strategy_modes:
            errors.append(
                "POLARIS_REFINEMENT_VERIFICATION_STRATEGY_INVALID: "
                f"verification_strategy.mode must be one of {sorted(valid_strategy_modes)} "
                f"(got: {strategy_mode!r})"
            )
        for field in ("reason", "authority"):
            value = verification_strategy.get(field)
            if not isinstance(value, str) or not value.strip():
                errors.append(
                    "POLARIS_REFINEMENT_VERIFICATION_STRATEGY_INVALID: "
                    f"verification_strategy.{field} must be a non-empty string"
                )
        if strategy_mode == "external_ac_ticket":
            external_ticket = (
                verification_strategy.get("ticket")
                or verification_strategy.get("ticket_key")
                or verification_strategy.get("ac_ticket")
                or verification_strategy.get("external_ticket")
            )
            if not isinstance(external_ticket, str) or not external_ticket.strip():
                errors.append(
                    "POLARIS_REFINEMENT_VERIFICATION_STRATEGY_INVALID: "
                    "verification_strategy.mode=external_ac_ticket requires a non-empty "
                    "ticket/ticket_key/ac_ticket/external_ticket identity"
                )

ac_ids = {str(item.get("id")) for item in (ac or []) if isinstance(item, dict)}
tasks = data.get("tasks")
if not isinstance(tasks, list) or not tasks:
    strong_error("tasks")
else:
    # DP-341: per-task packaging fields (allowed_files / estimate_points) are
    # NOT part of the refinement.json intent layer. refinement.json tasks[]
    # carries planning intent only; the breakdown writer path (task.md) owns the
    # packaging fields. These two keys are therefore removed from task_required
    # and are fail-closed when PRESENT (see PACKAGING_FORBIDDEN gate below). The
    # gate fires for EVERY source.type (dp + jira parity); it must not branch on
    # source.type.
    task_required = {
        "id",
        "kind",
        "title",
        "scope",
        "modules",
        "ac_ids",
        "dependencies",
        "verification",
    }
    # DP-341: per-task packaging fields forbidden on refinement.json tasks[].
    packaging_forbidden_fields = ("allowed_files", "estimate_points")
    for idx, task in enumerate(tasks):
        if not isinstance(task, dict):
            strong_error(f"tasks[{idx}]")
            continue
        for field in sorted(task_required):
            if field not in task:
                strong_error(f"tasks[{idx}].{field}")
        # DP-296: task_shape / tracked_deliverable_hint are first-class tasks[]
        # fields (canonical home, migrated from the removed top-level
        # planned_tasks[]). They are validated-when-present: a task that omits
        # them is still valid (implementation / tracked default). When present
        # they must be a string drawn from the canonical enum.
        if "task_shape" in task:
            task_shape = task.get("task_shape")
            if task_shape not in {"implementation", "audit", "confirmation"}:
                errors.append(
                    f"tasks[{idx}].task_shape '{task_shape!r}' is invalid "
                    "(must be one of ['audit', 'confirmation', 'implementation'])"
                )
        if "tracked_deliverable_hint" in task:
            hint = task.get("tracked_deliverable_hint")
            if hint not in {"tracked", "specs_only"}:
                errors.append(
                    f"tasks[{idx}].tracked_deliverable_hint '{hint!r}' is invalid "
                    "(must be one of ['specs_only', 'tracked'])"
                )
        # DP-260 T1: tasks[].id must be short form (T1/V1, optionally a-suffix)
        # OR full form (EPIC-NNN-Tn) whose source prefix equals source.id.
        # Foreign prefixes and malformed strings are fail-stop with marker.
        raw_task_id = task.get("id")
        if isinstance(raw_task_id, str) and raw_task_id != "":
            short_re = re.fullmatch(r"[TV][0-9]+[a-z]?", raw_task_id)
            full_re = re.fullmatch(r"([A-Z][A-Z0-9]*-[0-9]+)-([TV][0-9]+[a-z]?)", raw_task_id)
            if short_re is None and full_re is None:
                errors.append(
                    "POLARIS_REFINEMENT_TASK_ID_INVALID: "
                    f"tasks[{idx}].id='{raw_task_id}' must be short form (T1/V1) or "
                    "full form (EPIC-NNN-Tn) matching source.id"
                )
            elif full_re is not None:
                source_prefix = str(source_id or "").strip()
                if source_prefix and full_re.group(1) != source_prefix:
                    errors.append(
                        "POLARIS_REFINEMENT_TASK_ID_INVALID: "
                        f"tasks[{idx}].id='{raw_task_id}' source prefix "
                        f"'{full_re.group(1)}' does not match source.id '{source_prefix}'"
                    )
        elif "id" in task:
            errors.append(
                "POLARIS_REFINEMENT_TASK_ID_INVALID: "
                f"tasks[{idx}].id must be a non-empty string"
            )
        # DP-269 D1 / AC-NEG1: tasks[].jira_key is a jira-only field. For
        # source.type=jira it may be a non-empty JIRA key string or null (not
        # yet populated). For non-jira (dp) sources it must be absent entirely
        # (fail-closed, mirroring the source-level jira-only prohibition above).
        if "jira_key" in task:
            task_jira_key = task.get("jira_key")
            if source_type == "jira":
                if task_jira_key is not None and (
                    not isinstance(task_jira_key, str) or not JIRA_KEY.match(task_jira_key.strip())
                ):
                    errors.append(
                        f"tasks[{idx}].jira_key must be a valid JIRA key string or null "
                        f"(got: {task_jira_key!r})"
                    )
            else:
                errors.append(
                    f"POLARIS_REFINEMENT_JIRA_ONLY_FIELD: tasks[{idx}].jira_key is jira-only "
                    f"and must be absent for source.type={source_type}"
                )
        # DP-364 D1: tasks[].repo / tasks[].base_branch are jira-only per-task
        # overrides for cross-repo JIRA Epics. They are optional for jira sources
        # (fallback to source.repo/source.base_branch), and forbidden elsewhere so
        # the jira-only capability cannot leak into DP-backed framework sources.
        # Authored as explicit `if "X" in task:` anchors (single validation path,
        # not a for-loop) so the canonical tasks[] field whitelist extractor in
        # validate-refinement-consumer-schema-binding.sh recognises them as
        # first-class validated-when-present fields (DP-417 base-reconcile).
        if "repo" in task:
            repo = task.get("repo")
            if source_type == "jira":
                if not isinstance(repo, str) or not repo.strip():
                    errors.append(
                        f"tasks[{idx}].repo must be a non-empty string when present "
                        f"for source.type=jira (got: {repo!r})"
                    )
            else:
                errors.append(
                    f"POLARIS_REFINEMENT_JIRA_ONLY_FIELD: tasks[{idx}].repo is jira-only "
                    f"and must be absent for source.type={source_type}"
                )
        if "base_branch" in task:
            base_branch = task.get("base_branch")
            if source_type == "jira":
                if not isinstance(base_branch, str) or not base_branch.strip():
                    errors.append(
                        f"tasks[{idx}].base_branch must be a non-empty string when present "
                        f"for source.type=jira (got: {base_branch!r})"
                    )
            else:
                errors.append(
                    f"POLARIS_REFINEMENT_JIRA_ONLY_FIELD: tasks[{idx}].base_branch is jira-only "
                    f"and must be absent for source.type={source_type}"
                )
        # DP-341 / AC-NEG1: per-task packaging fields are forbidden on the
        # refinement.json intent layer. If a tasks[] entry CONTAINS
        # allowed_files or estimate_points (key present at all), fail-closed.
        # This gate fires for EVERY source.type (dp + jira parity) — it does
        # NOT branch on source_type. The packaging fields are owned by the
        # breakdown writer path (task.md), not refinement.json tasks[].
        for forbidden_field in packaging_forbidden_fields:
            if forbidden_field in task:
                packaging_field_violation[0] = True
                errors.append(
                    "POLARIS_REFINEMENT_PACKAGING_FIELD_FORBIDDEN: "
                    f"tasks[{idx}].{forbidden_field} is a per-task packaging field "
                    "owned by the breakdown writer path (task.md) and must be absent "
                    "from the refinement.json intent layer"
                )
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
        # DP-341: the estimate_points positive shape check is removed —
        # estimate_points is now forbidden on refinement.json tasks[] (handled by
        # the PACKAGING_FIELD_FORBIDDEN gate above), not a required/validated field.
        task_verification = task.get("verification")
        if not isinstance(task_verification, dict):
            strong_error(f"tasks[{idx}].verification")
        else:
            # DP-302 T1: per-task verification body fields (behavior_contract /
            # test_environment / verify_command / references). These are the
            # field-driven inputs derive (T2) reads to build the task.md body,
            # for ALL source types (not jira-only). They are validated-when-present
            # (mirroring the DP-296 task_shape pattern): a task that omits them is
            # still valid (existing active refinement.json predate the fields), but
            # when a field IS present its shape is enforced fail-loud (AC-NEG1) so
            # the derive cannot silently fall back to a framework default.
            validate_task_verification_body(task_verification, f"tasks[{idx}].verification")
        task_ac_ids = task.get("ac_ids")
        if not isinstance(task_ac_ids, list) or not task_ac_ids:
            strong_error(f"tasks[{idx}].ac_ids")
        else:
            for aid in task_ac_ids:
                if str(aid) not in ac_ids:
                    strong_error(f"tasks[{idx}].ac_ids[{aid}]")

        # DP-359 D4: SCSS-removal verify_command curated-token subset gate. Resolve
        # the curated set as the UNION of curated_tokens declared on the AC entries
        # this task references (task.ac_ids -> acceptance_criteria curated_tokens)
        # — the single source of truth (AC-NF1) — and gate the verify_command.
        if isinstance(task_verification, dict) and isinstance(task_ac_ids, list):
            curated_union = set()
            for aid in task_ac_ids:
                curated_union |= ac_curated_tokens.get(str(aid), set())
            check_scss_removal_verify_command(
                task_verification.get("verify_command"),
                curated_union,
                f"tasks[{idx}]",
            )

valid_task_ids = set()
if isinstance(tasks, list):
    source_prefix = str(source_id or data.get("epic") or "").strip()
    for task in tasks:
        if not isinstance(task, dict):
            continue
        raw_task_id = task.get("id")
        if not isinstance(raw_task_id, str) or not raw_task_id.strip():
            continue
        task_id = raw_task_id.strip()
        valid_task_ids.add(task_id)
        short_match = re.fullmatch(r"[TV][0-9]+[a-z]?", task_id)
        full_match = re.fullmatch(r"([A-Z][A-Z0-9]*-[0-9]+)-([TV][0-9]+[a-z]?)", task_id)
        if source_prefix and short_match:
            valid_task_ids.add(f"{source_prefix}-{task_id}")
        if full_match:
            valid_task_ids.add(full_match.group(2))

handoff_advisories = data.get("handoff_advisories")
if handoff_advisories is not None:
    valid_dispositions = {"pending", "absorbed_by_task", "waived", "route_back_refinement"}
    if not isinstance(handoff_advisories, list):
        errors.append("handoff_advisories must be an array when present")
    else:
        seen_advisory_ids = set()
        for idx, advisory in enumerate(handoff_advisories):
            label = f"handoff_advisories[{idx}]"
            if not isinstance(advisory, dict):
                errors.append(f"{label}: expected object, got {type(advisory).__name__}")
                continue
            for field in ("id", "producer", "severity", "recommended_action", "disposition"):
                value = advisory.get(field)
                if not isinstance(value, str) or not value.strip():
                    errors.append(f"{label}.{field} must be a non-empty string")
            advisory_id = advisory.get("id")
            if isinstance(advisory_id, str) and advisory_id.strip():
                if advisory_id.strip() in seen_advisory_ids:
                    errors.append(f"{label}.id '{advisory_id.strip()}' is duplicated")
                seen_advisory_ids.add(advisory_id.strip())
            disposition = advisory.get("disposition")
            if isinstance(disposition, str) and disposition.strip() and disposition not in valid_dispositions:
                errors.append(
                    f"{label}.disposition '{disposition}' is invalid "
                    f"(must be one of {sorted(valid_dispositions)})"
                )
            task_ids = advisory.get("task_ids")
            if task_ids is not None:
                if not isinstance(task_ids, list) or not task_ids:
                    errors.append(f"{label}.task_ids must be a non-empty array when present")
                else:
                    for tidx, task_id in enumerate(task_ids):
                        if not isinstance(task_id, str) or not task_id.strip():
                            errors.append(f"{label}.task_ids[{tidx}] must be a non-empty string")
                        elif task_id.strip() not in valid_task_ids:
                            errors.append(
                                f"{label}.task_ids[{tidx}] '{task_id.strip()}' "
                                "does not match an existing task"
                            )
            if disposition == "absorbed_by_task":
                if not isinstance(task_ids, list) or not task_ids:
                    errors.append(f"{label}: absorbed_by_task requires non-empty task_ids")
            if disposition == "waived":
                reason = advisory.get("reason")
                if not isinstance(reason, str) or not reason.strip():
                    errors.append(f"{label}: waived requires a non-empty reason")

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

required_bug_fields = {"reproduction_steps", "root_cause", "source_pr", "severity", "impact_scope", "regression"}
bug_fields = required_bug_fields | {"reproduction"}
present_bug_fields = bug_fields & set(data.keys())
if source_type == "bug":
    for field in sorted(required_bug_fields):
        if field not in data:
            strong_error(field)

    steps = data.get("reproduction_steps")
    if not isinstance(steps, list) or not steps:
        errors.append("bug field reproduction_steps must be a non-empty array")
    elif any(not isinstance(step, str) or not step.strip() for step in steps):
        errors.append("bug field reproduction_steps[] entries must be non-empty strings")

    for field in ("root_cause", "source_pr", "severity", "impact_scope"):
        value = data.get(field)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"bug field {field} must be a non-empty string")

    regression = data.get("regression")
    if not isinstance(regression, bool) and (not isinstance(regression, str) or not regression.strip()):
        errors.append("bug field regression must be boolean or a non-empty string")
else:
    for field in sorted(present_bug_fields):
        strong_error(field)

if errors:
    for e in errors:
        print(e)
    # DP-359 D4: the SCSS-removal curated-token over-scope violation is a
    # fail-closed A-class gate that exits 2 (distinct from the generic schema
    # exit 1) so the shell wrapper can surface the dedicated contract.
    # DP-341: the per-task packaging-field gate is an A-class fail-closed gate
    # that also exits 2 (alongside the SCSS-overscope gate); all other schema
    # violations stay exit 1.
    sys.exit(2 if (scss_overscope_violation[0] or packaging_field_violation[0]) else 1)

sys.exit(0)
