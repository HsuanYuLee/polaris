#!/usr/bin/env python3
"""Structured helpers for refinement LOCK preflight shell orchestration."""
from __future__ import annotations

import sys

def validate_replaces_existing(path: str) -> None:
    original = sys.argv
    sys.argv = [original[0], path]
    try:
        import json
        from pathlib import Path

        try:
            data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
        except Exception:
            # A malformed/unparseable refinement.json is the json schema validator's
            # concern; the replace-existing gate treats it as a no-op and lets the
            # downstream derive loop fail-loud on the real problem.
            raise SystemExit(0)

        rx = data.get("replaces_existing")
        if rx is None:
            raise SystemExit(0)  # non-replacing source: strict no-op (AC-N1)

        errs = []
        # Runtime/build-output evidence channels — the ones that CAN see build-time /
        # CDN / inline injection paths. source-grep is a valid discovery method but is
        # insufficient on its own (AC-NEG4), so it is deliberately excluded here.
        RUNTIME_BUILD_EVIDENCE = {"runtime", "build-output", "cdn", "inline"}

        if not isinstance(rx, dict):
            errs.append(
                "POLARIS_REFINEMENT_REPLACE_EXISTING_ENUMERATION: replaces_existing must be an object"
            )
        else:
            # Enumeration gate (AC9 / AC-NEG4).
            existing_sources = rx.get("existing_sources")
            if not isinstance(existing_sources, list) or not existing_sources:
                errs.append(
                    "POLARIS_REFINEMENT_REPLACE_EXISTING_ENUMERATION: replaces_existing marked but "
                    "existing_sources is empty — enumerate ALL existing sources of the replaced thing "
                    "with runtime/build-output evidence (source-grep cannot see build-time / CDN / "
                    "inline injection paths)"
                )
            else:
                for idx, src in enumerate(existing_sources):
                    if not isinstance(src, dict):
                        errs.append(
                            f"POLARIS_REFINEMENT_REPLACE_EXISTING_ENUMERATION: existing_sources[{idx}] "
                            "is not an object"
                        )
                        continue
                    evidence = src.get("evidence")
                    if evidence not in RUNTIME_BUILD_EVIDENCE:
                        errs.append(
                            f"POLARIS_REFINEMENT_REPLACE_EXISTING_ENUMERATION: existing_sources[{idx}] "
                            f"evidence={evidence!r} is not runtime/build-output enumeration evidence "
                            "(source-grep alone cannot see build-time / CDN / inline injection paths); "
                            f"must be one of {sorted(RUNTIME_BUILD_EVIDENCE)}"
                        )

            # Anti-dead-code-port gate (AC11 / AC-NEG6).
            ported = rx.get("ported_symbols")
            if ported is not None:
                if not isinstance(ported, list):
                    errs.append(
                        "POLARIS_REFINEMENT_REPLACE_EXISTING_DEAD_PORT: ported_symbols must be an array"
                    )
                else:
                    for idx, sym in enumerate(ported):
                        if not isinstance(sym, dict):
                            errs.append(
                                f"POLARIS_REFINEMENT_REPLACE_EXISTING_DEAD_PORT: ported_symbols[{idx}] "
                                "is not an object"
                            )
                            continue
                        name = sym.get("symbol")
                        usage_evidence = sym.get("usage_evidence")
                        if not isinstance(usage_evidence, str) or not usage_evidence.strip():
                            errs.append(
                                f"POLARIS_REFINEMENT_REPLACE_EXISTING_DEAD_PORT: ported symbol {name!r} "
                                "lacks usage_evidence — each ported symbol must carry a site-wide usage check"
                            )
                        usage_count = sym.get("usage_count")
                        disposition = sym.get("disposition")
                        if isinstance(usage_count, int) and not isinstance(usage_count, bool) and usage_count == 0:
                            if disposition != "removable":
                                errs.append(
                                    f"POLARIS_REFINEMENT_REPLACE_EXISTING_DEAD_PORT: ported symbol {name!r} "
                                    f"has zero site-wide usage but disposition={disposition!r}; a dead symbol "
                                    "must be flagged 'removable', not silently ported (new legacy)"
                                )

        if errs:
            for e in errs:
                print(e, file=sys.stderr)
            raise SystemExit(2)
        raise SystemExit(0)
    finally:
        sys.argv = original


def source_id(path: str) -> None:
    original = sys.argv
    sys.argv = [original[0], path]
    try:
        import json
        from pathlib import Path

        try:
            data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
        except Exception:
            print("DP-262")
            raise SystemExit(0)
        print(str((data.get("source") or {}).get("id") or "DP-262").strip() or "DP-262")
    finally:
        sys.argv = original


def task_ids(path: str) -> None:
    original = sys.argv
    sys.argv = [original[0], path]
    try:
        import json
        import re
        from pathlib import Path

        path = Path(sys.argv[1])
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            print(f"PARSE_ERROR\t{exc}", file=sys.stderr)
            raise SystemExit(3)


        def short_work_item_id(value, fallback):
            """Normalize a tasks[].id (short T1/V1 or full DP-NNN-Tn) to its short form."""
            value = str(value or "").strip()
            if re.fullmatch(r"[TV][0-9]+[a-z]?", value):
                return value
            m = re.fullmatch(r"[A-Z][A-Z0-9]*-[0-9]+-([TV][0-9]+[a-z]?)", value)
            if m:
                return m.group(1)
            return fallback


        tasks = data.get("tasks")
        if not isinstance(tasks, list):
            raise SystemExit(0)

        for idx, entry in enumerate(tasks):
            if not isinstance(entry, dict):
                print(f"BADENTRY\t{idx}", file=sys.stderr)
                raise SystemExit(3)
            task_id = short_work_item_id(entry.get("id"), f"PT{idx + 1}")
            if "\n" in task_id:
                print(f"BADFIELD\t{idx}", file=sys.stderr)
                raise SystemExit(3)
            print(task_id)
    finally:
        sys.argv = original


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[0] not in {"validate-replaces-existing", "source-id", "task-ids"}:
        print("usage: refinement_lock_preflight_helpers.py <validate-replaces-existing|source-id|task-ids> <refinement.json>", file=sys.stderr)
        return 2
    globals()[argv[0].replace("-", "_")](argv[1])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
