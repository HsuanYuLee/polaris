"""Structured validator authority extracted from scripts/validate-script-categorization.sh."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

mode = sys.argv[1]
base_ref = sys.argv[2]
root = Path(sys.argv[3]).resolve()
exception_file = Path(sys.argv[4])

audit_blob = os.environ.get("POLARIS_SCRIPT_CATEGORIZATION_AUDIT_JSON") or ""
explicit_raw = os.environ.get("POLARIS_SCRIPT_CATEGORIZATION_EXPLICIT_FILES") or ""

try:
    audit = json.loads(audit_blob) if audit_blob else {"scripts": []}
except json.JSONDecodeError as exc:
    sys.stderr.write(f"error: cannot parse audit JSON: {exc}\n")
    sys.exit(2)

scripts_by_path = {row["path"]: row for row in audit.get("scripts", [])}
taxonomy_summary = audit.get("summary", {}).get("taxonomy", {})

HOT_PATH_EXTS = {".sh", ".py", ".mjs", ".ts"}

# Exclusion globs aligned with AC-NEG2 + EC4. Generated runtime targets
# are .md (out of HOT_PATH_EXTS) and never reach this filter, but we keep
# them documented here for parity with validate-script-header-comment.sh.
EXCLUDE_GLOBS = [
    "CLAUDE.md",
    "AGENTS.md",
    ".codex/AGENTS.md",
    ".github/copilot-instructions.md",
    "scripts/fixtures/**",
    "docs-manager/dist/**",
    "docs-manager/node_modules/**",
    "node_modules/**",
    ".worktrees/**",
    ".polaris/**",
]


def excluded(rel_posix: str) -> bool:
    p = Path(rel_posix)
    for pat in EXCLUDE_GLOBS:
        if p.match(pat):
            return True
        if pat.endswith("/**"):
            prefix = pat[:-3].rstrip("/")
            if rel_posix == prefix or rel_posix.startswith(prefix + "/"):
                return True
    return False


def load_exceptions(path: Path) -> dict:
    """Return {script_path: {"skill": str, "reason": str}} for entries
    that have BOTH a non-empty owning-skill and reason. Entries missing
    either field are intentionally treated as invalid — adversarial pass
    for AC4: the exception is only honoured when accompanied by owner +
    rationale, otherwise the fixture is still classified misplaced.
    """
    out = {}
    if not path.exists():
        return out
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            # Malformed entry — ignore so misplaced fixture still fails.
            continue
        script_path, skill, reason = (
            parts[0].strip(),
            parts[1].strip(),
            parts[2].strip(),
        )
        if not script_path or not skill or not reason:
            continue
        out[script_path] = {"skill": skill, "reason": reason}
    return out


exceptions = load_exceptions(exception_file)


def git_diff_files(base: str) -> list[str]:
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "diff", "--name-only", "--diff-filter=AM", base],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(
            f"error: git diff failed against base {base!r}: {exc.stderr}\n"
        )
        sys.exit(2)
    paths = []
    for line in out.stdout.splitlines():
        rel = line.strip()
        if rel:
            paths.append(rel)
    return paths


def normalise_explicit(raw: str) -> list[str]:
    out = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        p = Path(line)
        if p.is_absolute():
            try:
                rel = p.resolve().relative_to(root).as_posix()
            except ValueError:
                continue
        else:
            rel = p.as_posix()
        out.append(rel)
    return out


def in_scope(rel: str) -> bool:
    # Only consider root-level scripts/ entries; skill-local scripts in
    # .claude/skills/{skill}/scripts/ are intentionally OUT of scope.
    if not rel.startswith("scripts/"):
        return False
    if Path(rel).suffix not in HOT_PATH_EXTS:
        return False
    if excluded(rel):
        return False
    # Bare scripts/ root only (no nested gates/, env/, lib/, selftests/, …).
    rest = rel[len("scripts/") :]
    if "/" in rest:
        return False
    return True


def classify_violation(rel: str) -> tuple[str, str] | None:
    """Return (owning_skill, marker_line) when `rel` is a misplaced
    single-skill root script, else None.
    """
    row = scripts_by_path.get(rel)
    if not row:
        return None
    if row.get("classification") != "skill_local":
        return None
    owner = row.get("owner_skill") or "unknown-skill"
    if rel in exceptions:
        # Honour exception only if the allowlist entry has owner + reason.
        return None
    target = f".claude/skills/{owner}/scripts/"
    marker = f"POLARIS_SCRIPT_MISPLACED:{rel} -> {target}"
    return owner, marker


# Determine candidate set.
explicit_paths = normalise_explicit(explicit_raw)
if explicit_paths:
    candidate_rels = explicit_paths
elif mode == "diff":
    candidate_rels = git_diff_files(base_ref)
else:
    candidate_rels = list(scripts_by_path.keys())

violations = []
audit_candidates = []
checked = 0
for rel in candidate_rels:
    if not in_scope(rel):
        continue
    checked += 1
    res = classify_violation(rel)
    if res is None:
        continue
    if mode == "diff":
        violations.append(res)
    else:
        audit_candidates.append(res)

if mode == "diff":
    if violations:
        for _, marker in violations:
            sys.stdout.write(marker + "\n")
        sys.stdout.write(
            f"FAIL: {len(violations)} script(s) misplaced under single skill "
            f"(checked {checked})\n"
        )
        sys.exit(2)
    sys.stdout.write(f"PASS: validate-script-categorization (checked {checked})\n")
    sys.exit(0)

# audit mode
sys.stdout.write(
    f"AUDIT: validate-script-categorization scanned {checked} script(s); "
    f"{len(audit_candidates)} skill_local candidate(s)\n"
)
if taxonomy_summary:
    rendered = ", ".join(
        f"{name}={taxonomy_summary[name]}" for name in sorted(taxonomy_summary)
    )
    sys.stdout.write(f"  taxonomy: {rendered}\n")
for owner, marker in audit_candidates:
    rel = marker.split(":", 1)[1].split(" -> ", 1)[0]
    sys.stdout.write(f"  legacy-debt: {rel} -> .claude/skills/{owner}/scripts/\n")
sys.exit(0)
