"""Structured validator authority extracted from scripts/validate-spec-boundary.sh."""

from pathlib import Path
import re
import sys

target = Path(sys.argv[1])
if not target.exists():
    print(f"validate-spec-boundary: path not found: {target}", file=sys.stderr)
    raise SystemExit(2)

if target.is_file():
    files = [target]
else:
    files = sorted(
        p
        for p in target.rglob("*.md")
        if "/archive/" not in str(p) and "/tasks/pr-release/" not in str(p)
    )

errors = []
for path in files:
    normalized = str(path)
    if "docs-manager/src/content/docs/specs/" not in normalized:
        continue
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        errors.append(f"{path}: missing frontmatter boundary declaration")
        continue
    end = text.find("\n---\n", 4)
    if end == -1:
        errors.append(f"{path}: malformed frontmatter")
        continue
    frontmatter = text[4:end]
    if not re.search(
        r"^(?:storage_boundary|spec_boundary):\s*(?:local_only|publish_ready)\s*$",
        frontmatter,
        re.M,
    ):
        errors.append(
            f"{path}: missing storage_boundary/spec_boundary local_only|publish_ready"
        )

if errors:
    print("validate-spec-boundary.sh FAIL", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)

print(f"validate-spec-boundary.sh PASS - {target}")
