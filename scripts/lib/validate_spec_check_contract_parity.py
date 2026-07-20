#!/usr/bin/env python3
"""Validate bidirectional parity between refinement producer specs and checks."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


AUTHORITY = {
    "authority_id": "producer_consumer_validator_parity",
    "registry": "scripts/lib/producer-consumer-bridges.json",
    "validator": "scripts/validate-spec-check-contract-parity.sh",
}
CHECK_KINDS = {
    "documented",
    "in_required_enum",
    "not_in_required_enum",
    "not_in_jira_only_enum",
}


def usage() -> None:
    print(
        "usage: validate-spec-check-contract-parity.sh "
        "[--repo-root PATH | --describe-authority]",
        file=sys.stderr,
    )


def parse_args(argv: list[str]) -> tuple[Path | None, bool]:
    repo_root: Path | None = None
    describe_authority = False
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--repo-root":
            if index + 1 >= len(argv) or not argv[index + 1]:
                print(
                    "POLARIS_SPEC_CHECK_PARITY_USAGE: --repo-root requires a path",
                    file=sys.stderr,
                )
                raise SystemExit(2)
            repo_root = Path(argv[index + 1])
            index += 2
        elif arg == "--describe-authority":
            describe_authority = True
            index += 1
        elif arg in {"-h", "--help"}:
            usage()
            raise SystemExit(0)
        else:
            print(
                f"POLARIS_SPEC_CHECK_PARITY_USAGE: unknown option: {arg}",
                file=sys.stderr,
            )
            raise SystemExit(2)
    if describe_authority and repo_root is not None:
        print(
            "POLARIS_SPEC_CHECK_PARITY_USAGE: --describe-authority does not accept --repo-root",
            file=sys.stderr,
        )
        raise SystemExit(2)
    return repo_root, describe_authority


def resolve_repo_root(explicit: Path | None) -> Path:
    if explicit is not None:
        try:
            return explicit.resolve(strict=True)
        except OSError:
            print(
                f"POLARIS_SPEC_CHECK_PARITY_USAGE: invalid repo root: {explicit}",
                file=sys.stderr,
            )
            raise SystemExit(2)
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0 and result.stdout.strip():
        return Path(result.stdout.strip()).resolve()
    return Path(__file__).resolve().parents[2]


class ParityValidator:
    def __init__(self, repo: Path) -> None:
        self.repo = repo
        self.errors: list[str] = []
        self.spec_files = {
            "refinement-artifact": repo
            / ".claude/skills/references/refinement-artifact.md",
            "pipeline-handoff": repo / ".claude/skills/references/pipeline-handoff.md",
        }
        self.validator_paths = {
            repo / "scripts/lib/refinement_validate_json.py",
            repo / "scripts/lib/refinement_validate_artifact_parity.py",
            repo / "scripts/lib/validate_breakdown_ready_1.py",
        }

    def read(self, path: Path) -> str | None:
        if not path.is_file():
            self.errors.append(
                f"POLARIS_SPEC_CHECK_PARITY_USAGE: missing input file: {path}"
            )
            return None
        return path.read_text(encoding="utf-8")

    @staticmethod
    def region(text: str, marker: str, sentinel: str) -> str:
        start = text.find(marker)
        if start == -1:
            return ""
        end = text.find(sentinel, start)
        return text[start : end if end != -1 else len(text)]

    def load_manifest(self, path: Path) -> list[dict[str, object]]:
        if not path.is_file():
            self.errors.append(
                "POLARIS_SPEC_CHECK_PARITY_MISSING_PRODUCER: "
                f"bridge registry missing: {path}"
            )
            return []
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            self.errors.append(
                "POLARIS_SPEC_CHECK_PARITY_MISSING_PRODUCER: "
                f"bridge registry invalid JSON: {exc}"
            )
            return []
        records = data.get("bridges")
        required_fields = data.get("required_bridge_fields")
        if (
            data.get("schema_version") != 1
            or not isinstance(records, list)
            or not isinstance(required_fields, list)
            or not required_fields
            or any(not isinstance(field, str) or not field for field in required_fields)
            or len(required_fields) != len(set(required_fields))
        ):
            self.errors.append(
                "POLARIS_SPEC_CHECK_PARITY_MISSING_PRODUCER: "
                "bridge registry schema/completeness authority invalid"
            )
            return []

        result: list[dict[str, object]] = []
        seen: set[str] = set()
        for index, record in enumerate(records):
            if not isinstance(record, dict):
                self.errors.append(
                    "POLARIS_SPEC_CHECK_PARITY_MISSING_PRODUCER: "
                    f"bridges[{index}] not object"
                )
                continue
            field = record.get("field")
            if not isinstance(field, str) or not field or field in seen:
                self.errors.append(
                    "POLARIS_SPEC_CHECK_PARITY_MISSING_PRODUCER: "
                    f"bridges[{index}] field missing/duplicate"
                )
                continue
            seen.add(field)
            validator = record.get("validator")
            if not isinstance(validator, str) or not validator.startswith("scripts/"):
                self.errors.append(
                    f"POLARIS_SPEC_CHECK_PARITY_MISSING_VALIDATOR: {field} validator missing"
                )
                continue
            validator_path = self.repo / validator
            if not validator_path.is_file():
                self.errors.append(
                    "POLARIS_SPEC_CHECK_PARITY_MISSING_VALIDATOR: "
                    f"{field} validator not found: {validator}"
                )
                continue
            check_kind = record.get("check_kind")
            if check_kind not in CHECK_KINDS:
                self.errors.append(
                    "POLARIS_SPEC_CHECK_PARITY_MISSING_PRODUCER: "
                    f"{field} check_kind invalid"
                )
                continue
            if not isinstance(record.get("token"), str) or not isinstance(
                record.get("anchor"), str
            ):
                self.errors.append(
                    "POLARIS_SPEC_CHECK_PARITY_MISSING_PRODUCER: "
                    f"{field} token/anchor missing"
                )
                continue
            if check_kind == "documented":
                specs = record.get("specs")
                if (
                    not isinstance(specs, list)
                    or not specs
                    or any(spec not in self.spec_files for spec in specs)
                ):
                    self.errors.append(
                        "POLARIS_SPEC_CHECK_PARITY_MISSING_PRODUCER: "
                        f"{field} producer specs missing/unregistered"
                    )
                    continue
            normalized = dict(record)
            normalized["validator"] = str(validator_path)
            result.append(normalized)

        registered_fields = {str(record["field"]) for record in result}
        required_field_set = set(required_fields)
        missing = sorted(required_field_set - registered_fields)
        unexpected = sorted(registered_fields - required_field_set)
        if missing or unexpected:
            self.errors.append(
                "POLARIS_SPEC_CHECK_PARITY_MISSING_PRODUCER: "
                "bridge registry completeness mismatch; "
                f"missing={missing}, unexpected={unexpected}"
            )
        return result

    def run(self) -> int:
        texts = {name: self.read(path) for name, path in self.spec_files.items()}
        validators = {str(path): self.read(path) for path in self.validator_paths}
        if self.errors:
            for error in self.errors:
                print(error, file=sys.stderr)
            return 2

        refinement_text = texts["refinement-artifact"] or ""
        required_region = self.region(refinement_text, "每筆必填", "。")
        jira_only_region = self.region(
            refinement_text, "只允許 `source.type=jira`", "是 derived view"
        )
        manifest = self.load_manifest(
            self.repo / "scripts/lib/producer-consumer-bridges.json"
        )

        for entry in manifest:
            field = str(entry["field"])
            token = str(entry["token"])
            kind = str(entry["check_kind"])
            validator_path = str(entry["validator"])
            anchor = str(entry["anchor"])
            validator_text = validators.get(validator_path)
            if validator_text is None or anchor not in validator_text:
                self.errors.append(
                    "POLARIS_SPEC_CHECK_PARITY_ANCHOR_STALE: "
                    f"manifest entry for '{field}' references anchor '{anchor}' no longer "
                    f"present in {Path(validator_path).name}; the parity manifest has "
                    "drifted from the live check"
                )
                continue
            if kind == "documented":
                specs = entry["specs"]
                assert isinstance(specs, list)
                if not any(token in (texts[str(spec)] or "") for spec in specs):
                    self.errors.append(
                        "POLARIS_SPEC_CHECK_PARITY_UNDOCUMENTED: "
                        f"validator {Path(validator_path).name} hard-requires '{field}' "
                        f"but no producer spec ({' / '.join(map(str, specs))}) documents {token}"
                    )
            elif kind == "in_required_enum" and token not in required_region:
                self.errors.append(
                    "POLARIS_SPEC_CHECK_PARITY_UNDOCUMENTED: "
                    f"validator {Path(validator_path).name} hard-requires tasks[] field "
                    f"'{field}' but {token} is missing from the refinement-artifact.md "
                    "tasks[] 必填 enumeration"
                )
            elif kind == "not_in_required_enum" and token in required_region:
                self.errors.append(
                    "POLARIS_SPEC_CHECK_PARITY_CONTRADICTION: "
                    f"validator {Path(validator_path).name} FORBIDS tasks[] field '{field}' "
                    "(packaging field) but the refinement-artifact.md tasks[] 必填 "
                    f"enumeration declares {token} required"
                )
            elif kind == "not_in_jira_only_enum":
                bullet = re.compile(r"(?m)^\s*-\s*" + re.escape(token) + r"\s*[：:]")
                if bullet.search(jira_only_region):
                    self.errors.append(
                        "POLARIS_SPEC_CHECK_PARITY_CONTRADICTION: "
                        f"validator {Path(validator_path).name} requires '{field}' for dp "
                        "sources (feat/<id>) but refinement-artifact.md still declares "
                        f"{token} as a jira-only (dp-forbidden) field bullet"
                    )

        if self.errors:
            print("FAIL: spec↔check contract parity", file=sys.stderr)
            for error in self.errors:
                print(f"  - {error}", file=sys.stderr)
            return 2
        print(f"PASS: spec↔check contract parity ({len(manifest)} manifest entries)")
        return 0


def main(argv: list[str]) -> int:
    repo_root, describe_authority = parse_args(argv)
    if describe_authority:
        print(json.dumps(AUTHORITY, separators=(",", ":")))
        return 0
    return ParityValidator(resolve_repo_root(repo_root)).run()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
