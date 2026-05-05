#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR=""

usage() {
  cat >&2 <<'EOF'
usage: skill-routing-canary.sh [options]

Options:
  --root <path>        Workspace root (default: script parent)
  --skills-dir <path>  Explicit skills directory (default: <root>/.claude/skills)
  -h, --help           Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --skills-dir) SKILLS_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "skill-routing-canary: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

python3 - "$ROOT" "$SKILLS_DIR" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).expanduser().resolve()
skills_arg = sys.argv[2]
skills_dir = Path(skills_arg).expanduser().resolve() if skills_arg else root / ".claude" / "skills"

cases = [
    ("review 這個 PR", "review-pr", [r"review", r"PR"]),
    ("我的 PR 狀態", "check-pr-approvals", [r"我的 PR", r"PR 狀態"]),
    ("修 bug DEMO-123", "bug-triage", [r"修 bug", r"bug"]),
    ("做 DEMO-123", "engineering", [r"做", r"engineering"]),
    ("討論需求", "refinement", [r"討論需求", r"refinement"]),
    ("learning 這篇文章", "learning", [r"learning", r"學習"]),
    ("validate mechanisms", "validate", [r"validate", r"檢查機制"]),
]

def frontmatter(text: str) -> str:
    if not text.startswith("---\n"):
        return ""
    end = text.find("\n---", 4)
    return text[4:end] if end != -1 else text

failures = []
for prompt, skill, patterns in cases:
    path = skills_dir / skill / "SKILL.md"
    if not path.exists():
        failures.append((prompt, skill, "missing SKILL.md"))
        continue
    searchable = frontmatter(path.read_text(encoding="utf-8", errors="replace"))
    if not any(re.search(pattern, searchable, re.IGNORECASE) for pattern in patterns):
        failures.append((prompt, skill, "missing trigger pattern in frontmatter"))

if failures:
    print("skill-routing-canary: FAIL")
    for prompt, skill, reason in failures:
        print(f"FAIL\t{skill}\t{prompt}\t{reason}")
    sys.exit(1)

print("skill-routing-canary: PASS")
for prompt, skill, _ in cases:
    print(f"PASS\t{skill}\t{prompt}")
PY
