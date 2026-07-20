"""Purpose: build a deterministic semantic ledger for the script-layer union.

Inputs / Outputs / Side effects: scan production and test script surfaces, join
manifest facts when available, and write one current-filesystem JSON ledger.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, Iterator


SCRIPT_SUFFIXES = {".sh", ".py", ".mjs", ".ts"}
EXCLUDED_DIRS = {".git", ".worktrees", "node_modules", "__pycache__", ".astro", "dist"}
LANGUAGE_BY_SUFFIX = {".sh": "bash", ".py": "python", ".mjs": "node", ".ts": "node"}
CORE_TASK_MD_SCRIPTS = {
    "scripts/validate-task-md.sh",
    "scripts/parse-task-md.sh",
    "scripts/derive-task-md-from-refinement-json.sh",
    "scripts/resolve-task-md.sh",
}
CORE_TASK_MD_PYTHON_TARGETS = {
    "scripts/validate-task-md.sh": "scripts/lib/validate_task_md.py",
    "scripts/parse-task-md.sh": "scripts/lib/parse_task_md.py",
    "scripts/derive-task-md-from-refinement-json.sh": "scripts/lib/derive_task_md_from_refinement_json.py",
    "scripts/resolve-task-md.sh": "scripts/lib/resolve_task_md.py",
}
CORE_TASK_MD_SELFTESTS = {
    "scripts/selftests/validate-task-md-selftest.sh",
    "scripts/selftests/parse-task-md-selftest.sh",
    "scripts/selftests/derive-task-md-from-refinement-json-selftest.sh",
    "scripts/selftests/resolve-task-md-selftest.sh",
}
PYTEST_WRAPPER_TARGETS = {
    "scripts/selftests/validate-task-md-selftest.sh": "tests/test_validate_task_md.py",
    "scripts/selftests/parse-task-md-selftest.sh": "tests/test_parse_task_md.py",
    "scripts/selftests/derive-task-md-from-refinement-json-selftest.sh": "tests/test_derive_task_md_from_refinement_json.py",
    "scripts/selftests/resolve-task-md-selftest.sh": "tests/test_resolve_task_md.py",
}
REFINEMENT_PYTHON_TARGETS = {
    "scripts/backfill-refinement-predecessor-audit.sh": "scripts/lib/refinement_backfill_predecessor_audit.py",
    "scripts/backfill-refinement-verification-strategy.sh": "scripts/lib/refinement_backfill_verification_strategy.py",
    "scripts/migrate-epic-refinement-handoff.sh": "scripts/lib/refinement_migrate_epic_handoff.py",
    "scripts/migrate-refinement-packaging-fields.sh": "scripts/lib/refinement_migrate_packaging_fields.py",
    "scripts/migrate-refinement-planned-tasks-to-canonical.sh": "scripts/lib/refinement_migrate_planned_tasks.py",
    "scripts/render-refinement-md.sh": "scripts/lib/refinement_render_md.py",
    "scripts/resolve-refinement-template.sh": "scripts/lib/refinement_resolve_template.py",
    "scripts/validate-refinement-ac-coverage.sh": "scripts/lib/refinement_validate_ac_coverage.py",
    "scripts/validate-refinement-artifact-parity.sh": "scripts/lib/refinement_validate_artifact_parity.py",
    "scripts/validate-refinement-consumer-schema-binding.sh": "scripts/lib/refinement_validate_consumer_schema_binding.py",
    "scripts/validate-refinement-inbox-record.sh": "scripts/lib/refinement_validate_inbox_record.py",
    "scripts/validate-refinement-json.sh": "scripts/lib/refinement_validate_json.py",
    "scripts/validate-refinement-locked-scope.sh": "scripts/lib/refinement_validate_locked_scope.py",
    "scripts/verify-refinement-convergence.sh": "scripts/lib/refinement_verify_convergence.py",
}
STRUCTURED_VALIDATOR_SHELL_FIT = {
    # These three files are audited composition-only entrypoints: they dispatch
    # to canonical resolver/evidence or authoring gate authorities and contain
    # no independent schema/parser decision surface.
    "scripts/validate-artifact-location.sh",
    "scripts/validate-dp-plan-authoring.sh",
    "scripts/validate-engineering-self-review-result.sh",
    "scripts/validate-handbook-load-gate.sh",
    "scripts/validate-handbook-path-contract.sh",
    "scripts/validate-memory-write.sh",
    "scripts/validate-safe-cli-introspection.sh",
    "scripts/validate-spec-primary-doc-authoring.sh",
}
ARRAY_DELEGATING_PYTHON_TARGETS = {
    "scripts/validate-current-head-gap-ledger.sh": "scripts/lib/validate_current_head_gap_ledger.py",
}


def is_canonical_pytest_wrapper(path: Path, relative: str) -> bool:
    """Return whether a core wrapper delegates exclusively to its exact pytest owner."""

    target = PYTEST_WRAPPER_TARGETS.get(relative)
    if target is None:
        return False
    executable = [
        line.strip()
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    invocation = f'exec mise exec -- pytest {target} -q "$@"'
    root_assignment = 'ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"'
    allowed = {
        "set -euo pipefail",
        root_assignment,
        'cd "$ROOT"',
        invocation,
    }
    return (
        executable.count(invocation) == 1
        and executable[-1] == invocation
        and all(line in allowed for line in executable)
    )


def is_canonical_task_md_python_wrapper(path: Path, relative: str) -> bool:
    """Return whether a core production wrapper delegates only to its exact module."""

    target = CORE_TASK_MD_PYTHON_TARGETS.get(relative)
    if target is None:
        return False
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    if not lines or lines[0] != "#!/usr/bin/env bash":
        return False
    executable = [
        line.strip()
        for line in lines
        if line.strip() and not line.lstrip().startswith("#")
    ]
    target_from_scripts = Path(target).relative_to("scripts").as_posix()
    expected = [
        "set -euo pipefail",
        'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
        f'exec python3 "$SCRIPT_DIR/{target_from_scripts}" "$@"',
    ]
    workspace_root = path.parent.parent
    return executable == expected and (workspace_root / target).is_file()


def is_canonical_refinement_python_wrapper(path: Path, relative: str) -> bool:
    """Return whether a refinement CLI is only a compatibility shim."""

    target = REFINEMENT_PYTHON_TARGETS.get(relative)
    if target is None:
        return False
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    if not lines or lines[0] != "#!/usr/bin/env bash":
        return False
    executable = [
        line.strip()
        for line in lines
        if line.strip() and not line.lstrip().startswith("#")
    ]
    target_from_scripts = Path(target).relative_to("scripts").as_posix()
    expected = [
        "set -euo pipefail",
        'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
        'export POLARIS_COMPAT_CLI="$0"',
        f'exec python3 "$SCRIPT_DIR/{target_from_scripts}" "$@"',
    ]
    workspace_root = path.parent.parent
    return executable == expected and (workspace_root / target).is_file()


def is_shell_orchestration_language_fit(path: Path) -> bool:
    """只接受無 inline structured logic、確實組合多個 command 的 shell。"""

    text = path.read_text(encoding="utf-8", errors="ignore")
    if (
        re.search(r"python3\s+-[^\n]*<<['\"]?PY", text)
        or re.search(r"<<['\"]?PY['\"]?", text)
        or re.search(r"python3\s+-c\s+['\"]\s*\n", text)
    ):
        return False
    direct_invocations = re.findall(
        r"(?m)^\s*(?:if\s+!\s+|elif\s+!\s+)?(?:bash|\"?\$[A-Z_]+\"?)\s+", text
    )
    function_names = set(re.findall(r"(?m)^([a-z][a-z0-9_]*)\(\)\s*\{", text))
    function_invocations = [
        match.group(1)
        for match in re.finditer(r"(?m)^\s*([a-z][a-z0-9_]*)\b", text)
        if match.group(1) in function_names
    ]
    return len(direct_invocations) + len(function_invocations) >= 2


def shell_executable_text(text: str) -> str:
    """Return shell command lines while excluding comments and heredoc bodies."""

    executable: list[str] = []
    heredoc_delimiter: str | None = None
    strip_tabs = False
    heredoc_start = re.compile(r"<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
    for line in text.splitlines():
        if heredoc_delimiter is not None:
            candidate = line.lstrip("\t") if strip_tabs else line
            if candidate.strip() == heredoc_delimiter:
                heredoc_delimiter = None
                strip_tabs = False
            continue
        if line.lstrip().startswith("#"):
            continue
        executable.append(line)
        match = heredoc_start.search(line)
        if match:
            strip_tabs = match.group(1) == "-"
            heredoc_delimiter = match.group(3)
    return "\n".join(executable)


def is_structured_validator_python_delegation(path: Path) -> bool:
    """Accept only a real executable delegation to an existing Python module."""

    text = path.read_text(encoding="utf-8", errors="ignore")
    if re.search(r"python3\s+-[^\n]*<<['\"]?PY", text):
        return False
    executable_text = shell_executable_text(text)
    modules = set(
        re.findall(
            r'(?m)^\s*(?:if\s+!?\s*)?'
            r'(?:[A-Z_][A-Z0-9_]*=\S+\s+)*'
            r'(?:exec\s+)?(?:python3|"?\$[A-Z_]+"?)\b[^\n#]*?'
            r'(lib/[A-Za-z0-9_.-]+_[0-9]+\.py)',
            executable_text,
        )
    )
    return bool(modules) and all((path.parent / module).is_file() for module in modules)


def is_thin_python_compatibility_wrapper(path: Path) -> bool:
    """Require a real executable Python module invocation for the generic shim rule."""

    text = path.read_text(encoding="utf-8", errors="ignore")
    if len(text.splitlines()) > 80:
        return False
    executable_text = shell_executable_text(text)
    modules = set(
        re.findall(
            r'(?m)^\s*(?:if\s+!?\s*)?'
            r'(?:[A-Z_][A-Z0-9_]*=\S+\s+)*'
            r'(?:exec\s+)?python3\b[^\n#]*?'
            r'((?:scripts/)?lib/[A-Za-z0-9_.-]+\.py)',
            executable_text,
        )
    )
    if not modules:
        return False
    workspace_root = path.parent.parent
    for module in modules:
        module_path = workspace_root / module if module.startswith("scripts/") else path.parent / module
        if not module_path.is_file():
            return False
    return True


def is_array_delegating_python_wrapper(path: Path, relative: str) -> bool:
    """Recognize the one audited command-array compatibility wrapper."""

    target = ARRAY_DELEGATING_PYTHON_TARGETS.get(relative)
    if target is None:
        return False
    text = path.read_text(encoding="utf-8", errors="ignore")
    executable_text = shell_executable_text(text)
    workspace_root = path.parent.parent
    target_from_root = target.removeprefix("scripts/")
    assignment = re.search(
        rf'(?m)^\s*CMD=\(python3\s+"\$ROOT/scripts/{re.escape(target_from_root)}"(?:\s+[^\n]*)?\)\s*$',
        executable_text,
    )
    execution = re.search(r'(?m)^\s*exec\s+"\$\{CMD\[@\]\}"\s*$', executable_text)
    return (
        (workspace_root / target).is_file()
        and assignment is not None
        and execution is not None
    )


def iter_surface_files(root: Path) -> Iterator[Path]:
    """Yield the authoritative scripts/tests filesystem union in stable order."""

    paths: list[Path] = []
    for scan_root in (root / "scripts", root / "tests"):
        if not scan_root.exists():
            continue
        for path in scan_root.rglob("*"):
            relative_parts = path.relative_to(root).parts
            if (
                path.is_file()
                and path.suffix in SCRIPT_SUFFIXES
                and not any(part in EXCLUDED_DIRS for part in relative_parts)
            ):
                paths.append(path)
    yield from sorted(paths)


def load_manifest(root: Path) -> dict[str, dict[str, Any]]:
    manifest_path = root / "scripts/manifest.json"
    if not manifest_path.is_file():
        return {}
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    return {
        entry["path"]: entry
        for entry in data.get("scripts", [])
        if isinstance(entry, dict) and isinstance(entry.get("path"), str)
    }


def surface_for(
    relative: str, manifest_entry: dict[str, Any] | None
) -> tuple[str, str]:
    """Return authoritative test/production surface and the deciding rule."""

    name = Path(relative).name
    if relative.startswith("tests/"):
        return "test", "tests_directory"
    if relative.startswith("scripts/selftests/"):
        return "test", "selftests_directory"
    if name.endswith("-selftest.sh") or name.endswith("_selftest.py"):
        return "test", "root_selftest_suffix"
    if manifest_entry and manifest_entry.get("kind") == "selftest":
        return "test", "manifest_kind_selftest"
    return "production", "production_default"


def migration_owner(
    path: Path, relative: str, surface: str, language: str
) -> tuple[str | None, str]:
    """Return the unique DP-420 migration owner and semantic rule, if any."""

    if language != "bash":
        return None, "already_language_fit"
    name = Path(relative).name
    if surface == "test":
        if is_canonical_pytest_wrapper(path, relative):
            return None, "thin_pytest_compatibility_wrapper"
        if relative in CORE_TASK_MD_SELFTESTS:
            return "DP-420-T4", "task_md_core_selftest_wave"
        return None, "legacy_shell_test_contract"
    if is_canonical_task_md_python_wrapper(path, relative):
        return None, "thin_task_md_python_compatibility_wrapper"
    if is_canonical_refinement_python_wrapper(path, relative):
        return None, "thin_refinement_python_compatibility_wrapper"
    if is_array_delegating_python_wrapper(path, relative):
        return None, "thin_python_compatibility_wrapper"
    if relative in CORE_TASK_MD_SCRIPTS:
        return "DP-420-T5", "task_md_core_production_wave"
    if (
        "refinement" in name or relative.startswith("scripts/lib/refinement")
    ) and (
        is_shell_orchestration_language_fit(path)
        or is_structured_validator_python_delegation(path)
    ):
        return None, "refinement_shell_orchestration_language_fit"
    if (
        "release" in name or "closeout" in name
    ) and (
        is_shell_orchestration_language_fit(path)
        or is_structured_validator_python_delegation(path)
    ):
        return None, "release_closeout_shell_orchestration_language_fit"
    if (
        "auto-pass" in name or name.startswith("ci-")
    ) and (
        is_shell_orchestration_language_fit(path)
        or is_structured_validator_python_delegation(path)
    ):
        return None, "auto_pass_ci_shell_orchestration_language_fit"
    if relative in STRUCTURED_VALIDATOR_SHELL_FIT:
        return None, "audited_structured_validator_shell_language_fit"
    category_owned = (
        "refinement" in name
        or relative.startswith("scripts/lib/refinement")
        or "release" in name
        or "closeout" in name
        or "auto-pass" in name
        or name.startswith("ci-")
    )
    if (
        not category_owned
        and name.startswith(("validate-", "parse-", "render-"))
        and is_structured_validator_python_delegation(path)
    ):
        return None, "structured_validator_python_delegating_shell_fit"
    if is_thin_python_compatibility_wrapper(path):
        return None, "thin_python_compatibility_wrapper"
    if "refinement" in name or relative.startswith("scripts/lib/refinement"):
        return "DP-420-T10", "refinement_residual_wave"
    if "release" in name or "closeout" in name:
        return "DP-420-T11", "release_closeout_residual_wave"
    if "auto-pass" in name or name.startswith("ci-"):
        return "DP-420-T12", "auto_pass_ci_residual_wave"
    if name.startswith(("validate-", "parse-", "render-")):
        return "DP-420-T13", "structured_validator_residual_wave"
    return None, "shell_orchestration_language_fit"


def classification_for(
    relative: str, surface: str, manifest_entry: dict[str, Any] | None
) -> str:
    if surface == "test":
        return "test"
    if relative.startswith("scripts/fixtures/"):
        return "fixture"
    if relative.startswith("scripts/lib/"):
        return "library"
    if manifest_entry and isinstance(manifest_entry.get("kind"), str):
        return manifest_entry["kind"]
    return "production"


def build_entry(
    root: Path, path: Path, manifest: dict[str, dict[str, Any]]
) -> dict[str, Any]:
    relative = path.relative_to(root).as_posix()
    manifest_entry = manifest.get(relative)
    surface, surface_rule = surface_for(relative, manifest_entry)
    language = LANGUAGE_BY_SUFFIX[path.suffix]
    owner, disposition_rule = migration_owner(path, relative, surface, language)
    if owner:
        disposition = "migrate"
        terminal = False
        rationale = (
            f"{relative} matches {disposition_rule} and is assigned only to {owner}"
        )
    elif language == "bash":
        disposition = "stay_shell"
        terminal = True
        rationale = f"{relative} is {surface}; {disposition_rule} keeps its observable shell contract"
    elif language == "python":
        disposition = "stay_python"
        terminal = True
        rationale = f"{relative} already uses Python for its {surface} contract"
    else:
        disposition = "stay_node"
        terminal = True
        rationale = f"{relative} remains Node-owned for its {surface} contract"
    return {
        "path": relative,
        "surface": surface,
        "language": language,
        "classification": classification_for(relative, surface, manifest_entry),
        "disposition": disposition,
        "owner": owner,
        "terminal": terminal,
        "evidence": {
            "surface_rule": surface_rule,
            "disposition_rule": disposition_rule,
            "observed": f"path={relative}; suffix={path.suffix}; manifest_kind={(manifest_entry or {}).get('kind', 'unregistered')}",
            "rationale": rationale,
        },
    }


def build_ledger(root: Path) -> dict[str, Any]:
    manifest = load_manifest(root)
    entries = [build_entry(root, path, manifest) for path in iter_surface_files(root)]
    dispositions = sorted({entry["disposition"] for entry in entries})
    return {
        "schema_version": 2,
        "source": "DP-420",
        "inventory_root": ["scripts", "tests"],
        "entries": entries,
        "summary": {
            "total": len(entries),
            "test": sum(entry["surface"] == "test" for entry in entries),
            "production": sum(entry["surface"] == "production" for entry in entries),
            "by_disposition": {
                disposition: sum(
                    entry["disposition"] == disposition for entry in entries
                )
                for disposition in dispositions
            },
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    root = Path(args.workspace).resolve()
    if not root.is_dir():
        parser.error(f"workspace is not a directory: {root}")
    output = Path(args.output)
    if not output.is_absolute():
        output = root / output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(build_ledger(root), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
