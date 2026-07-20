"""Structured validator authority extracted from scripts/validate-framework-source-write.sh."""

from pathlib import Path
import sys

repo = Path(sys.argv[1])
required = {
    ".claude/hooks/pre-framework-source-write.sh": "validate-framework-source-write.sh",
    ".claude/hooks/post-framework-source-diff-audit.sh": "validate-framework-source-write.sh",
    ".codex/hooks/pre-framework-source-write.sh": "validate-framework-source-write.sh",
    ".codex/hooks/post-framework-source-diff-audit.sh": "validate-framework-source-write.sh",
    "scripts/codex-guarded-bash.sh": "validate-framework-source-write.sh",
    "scripts/check-framework-pr-gate.sh": "W17 framework source write authority",
    ".codex/config.toml": "pre-framework-source-write.sh",
}
missing = []
for rel, needle in required.items():
    path = repo / rel
    if not path.is_file():
        missing.append(f"{rel}: missing")
        continue
    text = path.read_text(encoding="utf-8")
    if needle not in text:
        missing.append(f"{rel}: missing {needle}")
settings = repo / ".claude/settings.json"
if settings.is_file():
    text = settings.read_text(encoding="utf-8")
    for needle in (
        "pre-framework-source-write.sh",
        "post-framework-source-diff-audit.sh",
    ):
        if needle not in text:
            missing.append(f".claude/settings.json: missing {needle}")
else:
    missing.append(".claude/settings.json: missing")
registry = repo / ".claude/rules/mechanism-registry.md"
if registry.is_file():
    text = registry.read_text(encoding="utf-8")
    for hook in (
        "pre-framework-source-write.sh",
        "post-framework-source-diff-audit.sh",
    ):
        if hook not in text or "scripts/validate-framework-source-write.sh" not in text:
            missing.append(f"mechanism-registry.md: missing parity row for {hook}")
else:
    missing.append(".claude/rules/mechanism-registry.md: missing")
if missing:
    print("POLARIS_FRAMEWORK_SOURCE_WRITE_BLOCKED:self-check-wiring", file=sys.stderr)
    for item in missing:
        print(f"  - {item}", file=sys.stderr)
    sys.exit(2)
print(
    "PASS: framework source write wiring delegates to validate-framework-source-write.sh"
)
