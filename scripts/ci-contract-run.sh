#!/usr/bin/env bash
# ci-contract-run.sh — Execute normalized CI contract locally
#
# Usage:
#   scripts/ci-contract-run.sh --repo <path> [--intent pr|push|tag|manual|all] [--skip-install] [--include-hooks] [--dry-run]
#
# --include-hooks: Phase A pass-through flag — records include_hooks=true in the
# output report's contract metadata. The runner does NOT currently execute
# repo dev hooks (husky / pre-commit / lint-staged) — that is deferred to
# Phase C. This flag exists so callers (engineering sub-agent) can signal
# intent without changing runtime behavior yet.
#
# Exit 0: contract pass
# Exit 1: contract fail

set -euo pipefail

REPO_DIR=""
SKIP_INSTALL=0
DRY_RUN=0
INCLUDE_HOOKS=0
INTENT="pr"
BASE_BRANCH_OVERRIDE=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_DIR="$2"; shift 2 ;;
    --skip-install) SKIP_INSTALL=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --include-hooks) INCLUDE_HOOKS=1; shift ;;
    --intent) INTENT="$2"; shift 2 ;;
    --base-branch) BASE_BRANCH_OVERRIDE="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO_DIR" ]]; then
  echo "Usage: ci-contract-run.sh --repo <path> [--intent pr|push|tag|manual|all] [--base-branch <name>] [--skip-install] [--include-hooks] [--dry-run]" >&2
  exit 1
fi

REPO_DIR="$(cd "$REPO_DIR" && pwd)"

python3 - "$REPO_DIR" "$SKIP_INSTALL" "$DRY_RUN" "$SCRIPT_DIR" "$INTENT" "$BASE_BRANCH_OVERRIDE" "$INCLUDE_HOOKS" <<'PY'
import json
import os
import re
import subprocess
import sys
from fnmatch import fnmatch
from pathlib import Path

repo = Path(sys.argv[1])
skip_install = sys.argv[2] == "1"
dry_run = sys.argv[3] == "1"
script_dir = Path(sys.argv[4])
intent = (sys.argv[5] or "pr").strip().lower()
base_branch_override = (sys.argv[6] or "").strip() if len(sys.argv) > 6 else ""
include_hooks = (sys.argv[7] == "1") if len(sys.argv) > 7 else False

if intent not in {"pr", "push", "tag", "manual", "all"}:
    raise SystemExit(f"Unknown --intent value: {intent}")


def run_cmd(cmd: str, cwd: Path):
    proc = subprocess.run(
        ["bash", "-lc", cmd],
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return proc.returncode, proc.stdout


def git(args):
    proc = subprocess.run(["git", *args], cwd=str(repo), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        return ""
    return proc.stdout.strip()


contract_raw = subprocess.check_output(
    [str(script_dir / "ci-contract-discover.sh"), "--repo", str(repo)],
    text=True,
)
contract = json.loads(contract_raw)

checks = contract.get("checks", [])
ordered_categories = ["install", "lint", "typecheck", "test", "coverage"]

results = []
failed = False

for category in ordered_categories:
    if category == "install" and skip_install:
        continue

    category_checks = []
    for c in checks:
        if c.get("category") != category or not c.get("local_executable"):
            continue
        check_intents = [str(x).lower() for x in (c.get("intents") or [])]
        if intent != "all" and check_intents and intent not in check_intents:
            continue
        if intent != "all" and not check_intents:
            # Backward compatibility for old contracts without intent metadata.
            continue
        category_checks.append(c)
    for check in category_checks:
        cmd = check.get("command", "")
        if dry_run:
            rc, out = 0, ""
        else:
            rc, out = run_cmd(cmd, repo)
        result = {
            "category": category,
            "job": check.get("job", ""),
            "source_file": check.get("source_file", ""),
            "command": cmd,
            "exit_code": rc,
            "status": "PLANNED" if dry_run else ("PASS" if rc == 0 else "FAIL"),
            "output_tail": "\n".join(out.strip().splitlines()[-40:]),
        }
        results.append(result)
        if (not dry_run) and rc != 0 and category in {"lint", "typecheck", "test", "coverage"}:
            failed = True


def resolve_base_branch(override: str):
    if override:
        return override
    for candidate in ["develop", "main", "master"]:
        if git(["rev-parse", f"origin/{candidate}"]):
            return candidate
    return "main"


def parse_changed_lines(diff_text: str):
    file_lines = {}
    current_file = None
    for line in diff_text.splitlines():
        if line.startswith("+++ b/"):
            current_file = line[6:]
            file_lines.setdefault(current_file, set())
            continue
        if line.startswith("@@") and current_file:
            m = re.search(r"\+(\d+)(?:,(\d+))?", line)
            if not m:
                continue
            start = int(m.group(1))
            length = int(m.group(2) or "1")
            if length == 0:
                continue
            for n in range(start, start + length):
                file_lines[current_file].add(n)
    return file_lines


def merge_line_maps(*maps):
    merged = {}
    for m in maps:
        for f, lines in m.items():
            merged.setdefault(f, set()).update(lines)
    return merged


base_branch = resolve_base_branch(base_branch_override)
merge_base = git(["merge-base", "HEAD", f"origin/{base_branch}"]) or git(["merge-base", "HEAD", base_branch])

branch_diff = ""
if merge_base:
    branch_diff = git(["diff", "-U0", "--no-color", f"{merge_base}...HEAD"])
working_diff = git(["diff", "-U0", "--no-color"])
staged_diff = git(["diff", "-U0", "--no-color", "--cached"])

changed_lines = merge_line_maps(
    parse_changed_lines(branch_diff),
    parse_changed_lines(working_diff),
    parse_changed_lines(staged_diff),
)


def parse_lcov_files(root: Path):
    data = {}
    for lcov in root.rglob("lcov.info"):
        try:
            lines = lcov.read_text(encoding="utf-8", errors="ignore").splitlines()
        except Exception:
            continue

        current_file = None
        for line in lines:
            if line.startswith("SF:"):
                sf = line[3:].strip()
                sf_path = Path(sf)
                if sf_path.is_absolute():
                    try:
                        rel = sf_path.resolve().relative_to(root.resolve())
                        current_file = rel.as_posix()
                    except Exception:
                        current_file = sf_path.as_posix()
                else:
                    current_file = sf_path.as_posix()
                data.setdefault(current_file, {})
            elif line.startswith("DA:") and current_file:
                try:
                    num_s, hit_s = line[3:].split(",", 1)
                    num = int(num_s)
                    hit = int(float(hit_s))
                    data[current_file][num] = hit
                except Exception:
                    continue
    return data


lcov_map = parse_lcov_files(repo)


def normalize_pattern(p: str):
    p = p.strip()
    if p.endswith("/"):
        return p + "**"
    return p


def path_matches(path: str, include_patterns, exclude_patterns):
    includes = [normalize_pattern(p) for p in include_patterns or []]
    excludes = [normalize_pattern(p) for p in exclude_patterns or []]

    included = True if not includes else any(fnmatch(path, pat) for pat in includes)
    if not included:
        return False
    if any(fnmatch(path, pat) for pat in excludes):
        return False
    return True


def compute_flag_coverage(include, exclude):
    """Compute (matched_files, covered_lines, total_lines) for a flag's paths."""
    matched_files = [f for f in changed_lines.keys() if path_matches(f, include, exclude)]
    total = 0
    covered = 0
    include_prefixes = [inc.rstrip("/") for inc in (include or []) if inc and "*" not in inc]

    for f in matched_files:
        lines = changed_lines.get(f, set())

        lcov_lines = lcov_map.get(f)
        if lcov_lines is None:
            # Monorepo: lcov SF paths are typically relative to package root
            # (e.g. apps/main/coverage/lcov.info has SF:app.vue), while git
            # diff emits paths from repo root (apps/main/app.vue). Try
            # stripping each flag include_path prefix before lookup.
            for prefix in include_prefixes:
                if f.startswith(prefix + "/"):
                    stripped = f[len(prefix) + 1 :]
                    lcov_lines = lcov_map.get(stripped)
                    if lcov_lines is not None:
                        break
        if lcov_lines is None:
            # Fallback: bidirectional suffix match.
            for key, val in lcov_map.items():
                if key.endswith(f) or f.endswith(key):
                    lcov_lines = val
                    break

        if not lcov_lines:
            continue

        for ln in lines:
            if ln not in lcov_lines:
                continue
            total += 1
            if lcov_lines[ln] > 0:
                covered += 1
    return matched_files, covered, total


flag_results = []
for gate in contract.get("codecov_flag_gates", []):
    flag_name = gate.get("flag")
    include = gate.get("include_paths", [])
    exclude = gate.get("exclude_paths", [])
    statuses = gate.get("statuses", []) or []

    matched_files, covered, total = compute_flag_coverage(include, exclude)
    coverage_percent = round((covered / total) * 100, 2) if total > 0 else None

    if not statuses:
        # Flag exists but has no enforcement — e.g. report-only.
        flag_results.append(
            {
                "flag": flag_name,
                "status_type": None,
                "target_raw": None,
                "target_percent": None,
                "threshold_percent": None,
                "effective_target_percent": None,
                "is_auto": False,
                "status": "PLANNED" if dry_run else "SKIP",
                "reason": "flag_has_no_statuses",
                "covered_lines": covered,
                "total_lines": total,
                "coverage_percent": coverage_percent,
                "matched_files": matched_files,
            }
        )
        continue

    for status in statuses:
        status_type = status.get("type")
        target_raw = status.get("target_raw")
        target_percent = status.get("target_percent")
        threshold_percent = status.get("threshold_percent")
        is_auto = bool(status.get("is_auto"))

        if target_percent is not None:
            effective_target = float(target_percent) - float(threshold_percent or 0)
        else:
            effective_target = None

        # Base entry template — fields may be overridden below.
        entry = {
            "flag": flag_name,
            "status_type": status_type,
            "target_raw": target_raw,
            "target_percent": target_percent,
            "threshold_percent": threshold_percent,
            "effective_target_percent": effective_target,
            "is_auto": is_auto,
            "covered_lines": covered,
            "total_lines": total,
            "coverage_percent": coverage_percent,
            "matched_files": matched_files,
        }

        # Decide disposition.
        if status_type == "project":
            # Project gate — deferred to Phase C.
            entry["status"] = "PLANNED" if dry_run else "SKIP"
            entry["reason"] = "project_gate_not_implemented"
            flag_results.append(entry)
            continue

        if status_type == "patch" and is_auto:
            entry["status"] = "PLANNED" if dry_run else "SKIP"
            entry["reason"] = "patch_auto_target_not_supported_locally"
            flag_results.append(entry)
            continue

        if status_type != "patch":
            # Unknown status type — be strict, SKIP with reason.
            entry["status"] = "PLANNED" if dry_run else "SKIP"
            entry["reason"] = f"unknown_status_type_{status_type}"
            flag_results.append(entry)
            continue

        # Patch, explicit numeric target.
        if total == 0:
            entry["status"] = "PLANNED" if dry_run else "SKIP"
            entry["reason"] = "no_instrumented_patch_lines"
            flag_results.append(entry)
            continue

        if effective_target is None:
            entry["status"] = "PLANNED" if dry_run else "SKIP"
            entry["reason"] = "patch_target_missing"
            flag_results.append(entry)
            continue

        if dry_run:
            entry["status"] = "PLANNED"
            entry["reason"] = None
        else:
            if coverage_percent is not None and coverage_percent >= effective_target:
                entry["status"] = "PASS"
                entry["reason"] = None
            else:
                entry["status"] = "FAIL"
                entry["reason"] = None
                failed = True

        flag_results.append(entry)

summary = {
    "provider": contract.get("provider"),
    "executed_checks": len(results),
    "failed_checks": len([r for r in results if r["status"] == "FAIL"]),
    "flag_gate_failures": len([g for g in flag_results if g["status"] == "FAIL"]),
}

report = {
    "contract": {
        "provider": contract.get("provider"),
        "files": contract.get("files", []),
        "intent": intent,
        "base_branch": base_branch,
        "include_hooks": include_hooks,
    },
    "checks": results,
    "flag_results": flag_results,
    "summary": summary,
    "status": "DRY_RUN" if dry_run else ("FAIL" if failed else "PASS"),
}

print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(1 if failed else 0)
PY
