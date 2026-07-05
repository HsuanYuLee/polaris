#!/usr/bin/env python3
"""Detect explicit Bug source signals for refinement Bug source mode."""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any


BUG_SUBSTEPS = [
    "reproduction",
    "rca_investigation",
    "source_pr_identification",
    "severity_impact_assessment",
]


def _lower(value: object) -> str:
    return str(value or "").strip().lower()


def _issue_type_from_payload(payload: dict[str, Any]) -> str:
    fields = payload.get("fields") if isinstance(payload.get("fields"), dict) else {}
    issue_type = fields.get("issuetype") if isinstance(fields.get("issuetype"), dict) else {}
    return str(issue_type.get("name") or payload.get("issue_type") or "")


def detect(
    source_kind: str = "",
    source_type: str = "",
    issue_type: str = "",
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload = payload or {}
    payload_issue_type = _issue_type_from_payload(payload)
    is_bug = any(
        value == "bug"
        for value in (
            _lower(source_kind),
            _lower(source_type),
            _lower(issue_type),
            _lower(payload_issue_type),
        )
    )
    return {
        "bug_source_mode": is_bug,
        "source_kind": "bug" if is_bug else (source_kind or source_type or "unknown"),
        "required_substeps": BUG_SUBSTEPS if is_bug else [],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-kind", default="")
    parser.add_argument("--source-type", default="")
    parser.add_argument("--issue-type", default="")
    parser.add_argument("--payload-json", default="")
    args = parser.parse_args()

    payload: dict[str, Any] = {}
    if args.payload_json:
        try:
            decoded = json.loads(args.payload_json)
        except json.JSONDecodeError as exc:
            print(f"invalid --payload-json: {exc}", file=sys.stderr)
            return 2
        if not isinstance(decoded, dict):
            print("--payload-json must decode to an object", file=sys.stderr)
            return 2
        payload = decoded

    print(
        json.dumps(
            detect(
                source_kind=args.source_kind,
                source_type=args.source_type,
                issue_type=args.issue_type,
                payload=payload,
            ),
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
