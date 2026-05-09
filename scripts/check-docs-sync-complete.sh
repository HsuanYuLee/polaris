#!/usr/bin/env bash
# check-docs-sync-complete.sh — deterministic closeout gate for docs-sync.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: check-docs-sync-complete.sh [--repo PATH] [--base-ref REF] [--head-ref REF] [--format json|text]

Defaults:
  --repo     current working directory
  --base-ref HEAD
  --head-ref worktree
  --format   text
EOF
  exit 2
}

repo=""
base_ref="HEAD"
head_ref=""
format="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --base-ref)
      base_ref="${2:-}"
      shift 2
      ;;
    --head-ref)
      head_ref="${2:-}"
      shift 2
      ;;
    --format)
      format="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$repo" ]]; then
  repo="$(pwd)"
fi

if [[ "$format" != "text" && "$format" != "json" ]]; then
  echo "error: --format must be text or json" >&2
  exit 2
fi

python3 - "$repo" "$base_ref" "$head_ref" "$format" <<'PY'
import json
import os
import re
import subprocess
import sys
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
base_ref = sys.argv[2]
head_ref = sys.argv[3]
fmt = sys.argv[4]

PUBLIC_DOCS = {
    "README.md",
    "README.zh-TW.md",
    "docs/chinese-triggers.md",
    "docs/workflow-guide.md",
    "docs/workflow-guide.zh-TW.md",
    "docs/pm-setup-checklist.md",
    "docs/pm-setup-checklist.zh-TW.md",
    "docs/codex-quick-start.md",
    "docs/codex-quick-start.zh-TW.md",
    "docs/quick-start-zh.md",
}

PAIR_REQUIREMENTS = [
    ("README.md", "README.zh-TW.md"),
    ("docs/workflow-guide.md", "docs/workflow-guide.zh-TW.md"),
    ("docs/pm-setup-checklist.md", "docs/pm-setup-checklist.zh-TW.md"),
    ("docs/codex-quick-start.md", "docs/codex-quick-start.zh-TW.md"),
]

SKILL_RE = re.compile(r"^\.claude/skills/([^/]+)/SKILL\.md$")


def run_git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True)


def changed_entries():
    if head_ref:
        out = run_git("diff", "--name-status", "--find-renames", f"{base_ref}", f"{head_ref}", "--")
    else:
        out = run_git("diff", "--name-status", "--find-renames", base_ref, "--")
    entries = []
    for raw in out.splitlines():
        if not raw.strip():
            continue
        parts = raw.split("\t")
        status = parts[0]
        if status.startswith("R"):
            entries.append({"status": "R", "old": parts[1], "path": parts[2]})
        else:
            entries.append({"status": status, "old": parts[1] if len(parts) > 2 else None, "path": parts[1]})
    return entries


def read_ref(path: str, ref: str | None):
    if ref is None:
        p = repo / path
        return p.read_text(encoding="utf-8") if p.exists() else None
    try:
        return run_git("show", f"{ref}:{path}")
    except subprocess.CalledProcessError:
        return None


def extract_frontmatter_payload(text: str | None):
    if not text or not text.startswith("---"):
        return {"name": None, "description": None, "scope": None}
    lines = text.splitlines()
    end = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end = idx
            break
    if end is None:
        return {"name": None, "description": None, "scope": None}
    fm = lines[1:end]
    payload = {"name": None, "description": [], "scope": None}
    i = 0
    while i < len(fm):
        line = fm[i]
        if line.startswith("name:"):
            payload["name"] = line.split(":", 1)[1].strip()
        elif line.startswith("scope:"):
            payload["scope"] = line.split(":", 1)[1].strip()
        elif line.startswith("description:"):
            tail = line.split(":", 1)[1].strip()
            if tail and tail not in {">", "|"}:
                payload["description"].append(tail)
            i += 1
            while i < len(fm):
                cont = fm[i]
                if cont.startswith(" ") or cont.startswith("\t"):
                    payload["description"].append(cont.strip())
                    i += 1
                    continue
                i -= 1
                break
        i += 1
    payload["description"] = "\n".join(payload["description"]).strip() or None
    return payload


def is_maintainer_only(old_text: str | None, new_text: str | None):
    for text in (new_text, old_text):
        payload = extract_frontmatter_payload(text)
        if payload["scope"] == "maintainer-only":
            return True
    return False


def is_docs_impacting_skill_change(entry):
    m = SKILL_RE.match(entry["path"])
    if not m:
        return False, None
    skill = m.group(1)
    old_text = read_ref(entry["old"] or entry["path"], base_ref) if entry["status"] in {"M", "D", "R"} else None
    new_text = read_ref(entry["path"], head_ref or None) if entry["status"] in {"M", "A", "R"} else None
    if is_maintainer_only(old_text, new_text):
        return False, skill
    if entry["status"] in {"A", "D", "R"}:
        return True, skill
    old_payload = extract_frontmatter_payload(old_text)
    new_payload = extract_frontmatter_payload(new_text)
    impacting = (
        old_payload["name"] != new_payload["name"]
        or old_payload["description"] != new_payload["description"]
    )
    return impacting, skill


entries = changed_entries()
changed_paths = {entry["path"] for entry in entries}
docs_changed = sorted(path for path in changed_paths if path in PUBLIC_DOCS)

impact_skills = []
for entry in entries:
    impacting, skill = is_docs_impacting_skill_change(entry)
    if impacting and skill:
        impact_skills.append(skill)
impact_skills = sorted(set(impact_skills))

pair_failures = []
for left, right in PAIR_REQUIREMENTS:
    if (left in changed_paths) ^ (right in changed_paths):
        pair_failures.append({"pair": [left, right], "reason": "translation_pair_mismatch"})

missing_targets = []
if impact_skills:
    if "docs/chinese-triggers.md" not in changed_paths:
        missing_targets.append("docs/chinese-triggers.md")
    if "README.md" not in changed_paths:
        missing_targets.append("README.md")
    if "README.zh-TW.md" not in changed_paths:
        missing_targets.append("README.zh-TW.md")

lint_script = repo / "scripts" / "readme-lint.py"
lint_ok = False
lint_output = ""
if lint_script.exists():
    proc = subprocess.run(
        [sys.executable, str(lint_script)],
        cwd=repo,
        text=True,
        capture_output=True,
    )
    lint_ok = proc.returncode == 0
    lint_output = (proc.stdout + proc.stderr).strip()
else:
    lint_output = f"missing lint script: {lint_script}"

passed = lint_ok and not pair_failures and not missing_targets

result = {
    "passed": passed,
    "impact_skills": impact_skills,
    "docs_changed": docs_changed,
    "missing_targets": missing_targets,
    "pair_failures": pair_failures,
    "lint_ok": lint_ok,
    "lint_output": lint_output,
    "base_ref": base_ref,
    "head_ref": head_ref or "worktree",
}

if fmt == "json":
    print(json.dumps(result, ensure_ascii=False))
else:
    if passed:
        skills = ", ".join(impact_skills) if impact_skills else "none"
        print(f"PASS: docs-sync complete (impact_skills={skills})")
    else:
        print("FAIL: docs-sync incomplete")
        if not lint_ok:
            print("  - readme-lint failed")
        if missing_targets:
            print("  - missing docs targets: " + ", ".join(missing_targets))
        for failure in pair_failures:
            print("  - translation pair mismatch: " + " <-> ".join(failure["pair"]))

sys.exit(0 if passed else 1)
PY
