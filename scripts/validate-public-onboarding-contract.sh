#!/usr/bin/env bash
set -euo pipefail

# validate-public-onboarding-contract.sh
#
# Ensures public onboarding docs expose the runtime/toolchain contract declared
# by polaris-toolchain.yaml. This catches semantic drift that skill-count docs
# lint cannot see.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import re
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"ERROR: PyYAML is required to validate public onboarding contract: {exc}", file=sys.stderr)
    raise SystemExit(2)

root = Path(sys.argv[1])
manifest_path = root / "polaris-toolchain.yaml"

if not manifest_path.exists():
    print("public onboarding contract: SKIP (polaris-toolchain.yaml missing)")
    raise SystemExit(0)

manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8")) or {}
minimum = manifest.get("minimum_environment") or {}
capabilities = manifest.get("capabilities") or {}
required_caps = [
    name for name, spec in capabilities.items()
    if isinstance(spec, dict) and spec.get("required") is True
]

docs = [
    "README.md",
    "README.zh-TW.md",
    "docs/quick-start-zh.md",
    "docs/codex-quick-start.md",
    "docs/codex-quick-start.zh-TW.md",
    "docs/pm-setup-checklist.md",
    "docs/pm-setup-checklist.zh-TW.md",
]

doc_text = {}
for rel in docs:
    path = root / rel
    if path.exists():
        doc_text[rel] = path.read_text(encoding="utf-8")

failures = []

def require(rel: str, label: str, pattern: str, flags: int = re.IGNORECASE):
    text = doc_text.get(rel)
    if text is None:
        failures.append(f"{rel}: missing public onboarding doc")
        return
    if not re.search(pattern, text, flags):
        failures.append(f"{rel}: missing {label}")

doctor_pattern = r"scripts/polaris-toolchain\.sh\s+doctor\s+--required"
for rel in docs:
    require(rel, "`scripts/polaris-toolchain.sh doctor --required`", doctor_pattern)

technical_docs = [
    "README.md",
    "README.zh-TW.md",
    "docs/quick-start-zh.md",
    "docs/codex-quick-start.md",
    "docs/codex-quick-start.zh-TW.md",
]

if minimum.get("node"):
    for rel in technical_docs:
        require(rel, "Node >= 20 prerequisite", r"Node(?:\.js)?[^\n|,;。]*20")

if minimum.get("package_manager"):
    for rel in technical_docs:
        require(rel, "pnpm prerequisite", r"\bpnpm\b")

if minimum.get("python"):
    for rel in technical_docs:
        require(rel, "Python prerequisite", r"Python(?:3)?[^\n|,;。]*3")

cap_patterns = {
    "docs.viewer": r"docs?\s*viewer|文件.*viewer|文件.*檢視",
    "fixtures.mockoon": r"Mockoon|mockoon",
    "browser.playwright": r"Playwright|playwright",
}
for cap in required_caps:
    pattern = cap_patterns.get(cap)
    if not pattern:
        continue
    for rel in ("README.md", "README.zh-TW.md"):
        require(rel, f"required capability `{cap}`", pattern)

stale_l3_patterns = [
    r"\{company\}/\{project\}/CLAUDE\.md",
    r"\.claude/CLAUDE\.md[^\n]*(?:L3|專案層級規則)",
    r"專案層級規則[^\n]*CLAUDE\.md",
]
for rel, text in doc_text.items():
    for pattern in stale_l3_patterns:
        if re.search(pattern, text):
            failures.append(
                f"{rel}: stale project-level CLAUDE.md L3 claim; use "
                "`{company}/polaris-config/{project}/handbook/` instead"
            )
            break

if failures:
    print("Public onboarding contract drift:")
    for item in failures:
        print(f"  - {item}")
    print("\nAction: update README / quick-start / PM setup docs to match polaris-toolchain.yaml.")
    raise SystemExit(1)

print("PASS: public onboarding docs mention required Polaris toolchain contract")
PY
