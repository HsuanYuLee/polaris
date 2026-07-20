"""Structured validator authority extracted from scripts/validate-specs-collection-shape.sh."""

import sys
from pathlib import Path

specs_root = Path(sys.argv[1]).resolve()
list_file = Path(sys.argv[2])


def is_markdown(path: Path) -> bool:
    return path.suffix in {
        ".md",
        ".mdx",
        ".markdown",
        ".mdown",
        ".mkdn",
        ".mkd",
        ".mdwn",
    }


def frontmatter_keys(path: Path) -> set[str]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    if not lines or lines[0].strip() != "---":
        return set()
    keys: set[str] = set()
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if ":" not in line or line.startswith((" ", "\t", "-")):
            continue
        key, value = line.split(":", 1)
        if key.strip() and value.strip():
            keys.add(key.strip())
    return keys


def is_excluded_sidecar(rel: str) -> bool:
    parts = rel.split("/")
    return any(
        part in {"jira-comments", "escalations", "refinement-inbox", "tests"}
        for part in parts
    )


def is_d2_transport(rel: str) -> bool:
    marker = (
        "/artifacts/external-writes/" in f"/{rel}"
        or "/artifacts/research/" in f"/{rel}"
    )
    return marker and rel.endswith(".md")


failures: dict[str, list[str]] = {}
for raw in list_file.read_text(encoding="utf-8").splitlines():
    if not raw:
        continue
    path = Path(raw).resolve()
    if not is_markdown(path):
        continue
    try:
        rel = path.relative_to(specs_root).as_posix()
    except ValueError:
        continue
    if is_excluded_sidecar(rel):
        continue
    keys = frontmatter_keys(path)
    required = (
        {"artifact_type", "source", "created"}
        if is_d2_transport(rel)
        else {"title", "description"}
    )
    missing = sorted(required - keys)
    if missing:
        failures[rel] = missing

if failures:
    for rel, missing in failures.items():
        if {"artifact_type", "source", "created"} & set(missing):
            for key in missing:
                print(
                    f"ERROR: D2 transport artifact missing `{key}`: {rel}",
                    file=sys.stderr,
                )
        else:
            for key in missing:
                print(
                    f"ERROR: docs collection page missing `{key}`: {rel}",
                    file=sys.stderr,
                )
    print(
        f"FAIL: specs collection shape violations: {len(failures)} file(s)",
        file=sys.stderr,
    )
    raise SystemExit(1)
