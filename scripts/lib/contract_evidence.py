"""Shared validation for Polaris repo-root-bound contract evidence.

The canonical shape is ``repo/path:line``. A valid entry must resolve under the
workspace root, point at an existing readable file, and reference a line within
that file.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any


CONTRACT_EVIDENCE_PATTERN = re.compile(r"^.+:[1-9][0-9]*$")


def validate_contract_evidence_entries(
    value: Any,
    *,
    repo_root: Path,
    prefix: str,
    require_non_empty: bool = False,
    missing_error: str | None = None,
    not_array_error: str | None = None,
    empty_error: str | None = None,
    item_empty_error: str | None = None,
    shape_error: str | None = None,
    outside_root_error: str | None = None,
    not_found_error: str | None = None,
    unreadable_error: str | None = None,
    out_of_range_error: str | None = None,
) -> list[str]:
    """Return validation errors for contract_evidence entries.

    Callers own field-specific wording; this helper owns the semantics.
    Template variables available to message strings: ``prefix``, ``field``,
    ``raw``, ``path``, ``line``, and ``exc``.
    """

    root = repo_root.resolve()
    errors: list[str] = []

    def render(template: str, **extra: object) -> str:
        values = {"prefix": prefix, "field": prefix, "raw": "", "path": "", "line": "", "exc": ""}
        values.update(extra)
        return template.format(**values)

    if value is None:
        if require_non_empty:
            errors.append(missing_error or f"{prefix} is required")
        return errors
    if not isinstance(value, list):
        errors.append(not_array_error or f"{prefix} must be an array of repo/path:line strings")
        return errors
    if require_non_empty and not value:
        errors.append(empty_error or f"{prefix} must contain at least one repo/path:line string")

    for idx, item in enumerate(value):
        field = f"{prefix}[{idx}]"
        if not isinstance(item, str) or not item.strip():
            errors.append(item_empty_error.format(field=field) if item_empty_error else f"{field} must be a non-empty string")
            continue

        raw = item.strip()
        if not CONTRACT_EVIDENCE_PATTERN.fullmatch(raw):
            errors.append(
                render(
                    shape_error or "{field} must match repo/path:line with a positive line number",
                    field=field,
                    raw=raw,
                )
            )
            continue

        path_part, line_part = raw.rsplit(":", 1)
        candidate = Path(path_part)
        if not candidate.is_absolute():
            candidate = root / candidate
        resolved = candidate.resolve()

        try:
            resolved.relative_to(root)
        except ValueError:
            errors.append(
                render(
                    outside_root_error or "{field} path must resolve under repo root",
                    field=field,
                    raw=raw,
                    path=path_part,
                    line=line_part,
                )
            )
            continue

        if not resolved.is_file():
            errors.append(
                render(
                    not_found_error or "{field} path not found: {path}",
                    field=field,
                    raw=raw,
                    path=path_part,
                    line=line_part,
                )
            )
            continue

        try:
            line_count = len(resolved.read_text(encoding="utf-8").splitlines())
        except Exception as exc:  # pragma: no cover - depends on filesystem permissions
            errors.append(
                render(
                    unreadable_error or "{field} path could not be read: {path} ({exc})",
                    field=field,
                    raw=raw,
                    path=path_part,
                    line=line_part,
                    exc=exc,
                )
            )
            continue

        if int(line_part) > line_count:
            errors.append(
                render(
                    out_of_range_error or "{field} line {line} is outside file range for {path}",
                    field=field,
                    raw=raw,
                    path=path_part,
                    line=line_part,
                )
            )

    return errors
