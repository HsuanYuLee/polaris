#!/usr/bin/env bash
# ci-contract-discover.sh — Discover repo CI strategy and normalize into a local contract
#
# Usage:
#   scripts/ci-contract-discover.sh --repo <path>
#
# Output:
#   JSON contract to stdout

set -euo pipefail

REPO_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO_DIR" ]]; then
  echo "Usage: ci-contract-discover.sh --repo <path>" >&2
  exit 1
fi

REPO_DIR="$(cd "$REPO_DIR" && pwd)"

python3 - "$REPO_DIR" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

import yaml

repo = Path(sys.argv[1])


def load_yaml(path: Path):
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def flatten_commands(raw):
    if raw is None:
        return []
    if isinstance(raw, str):
        return [raw.strip()] if raw.strip() else []
    result = []
    if isinstance(raw, list):
        for item in raw:
            if isinstance(item, str):
                s = item.strip()
                if s:
                    result.append(s)
    return result


def categorize_command(cmd: str):
    lower = cmd.lower()

    if any(k in lower for k in ["pnpm install", "npm ci", "npm install", "yarn install", "bundle install", "composer install", "pip install"]):
        return "install"

    if "typecheck" in lower or re.search(r"\btsc\b", lower):
        return "typecheck"

    if any(k in lower for k in ["eslint", "prettier --check", "check-lint-baseline", "stylelint"]) or re.search(r"\blint\b", lower):
        return "lint"

    if "--coverage" in lower or "coverage" in lower or "nyc " in lower:
        return "coverage"

    if re.search(r"\b(test|vitest|jest|pytest|go test|phpunit|rspec)\b", lower):
        return "test"

    return "other"


def normalize_events(raw):
    if raw is None:
        return []
    if isinstance(raw, dict):
        return [str(k).strip() for k in raw.keys() if str(k).strip()]
    if isinstance(raw, str):
        return [raw.strip()] if raw.strip() else []
    events = []
    if isinstance(raw, list):
        for item in raw:
            if isinstance(item, str):
                s = item.strip()
                if s:
                    events.append(s)
    return events


def normalize_event_name(event: str):
    normalized = event.strip().lower().replace("-", "_")
    aliases = {
        "pr": "pull_request",
        "pullrequest": "pull_request",
        "pull_request_target": "pull_request",
        "merge_request": "pull_request",
        "merge_request_event": "pull_request",
    }
    return aliases.get(normalized, normalized)


def infer_intents(provider: str, events):
    normalized = {normalize_event_name(e) for e in events if e}
    intents = []

    if "pull_request" in normalized:
        intents.append("pr")
    if "push" in normalized:
        intents.append("push")
    if "tag" in normalized:
        intents.append("tag")
    if "workflow_dispatch" in normalized or "schedule" in normalized:
        intents.append("manual")

    if not intents:
        if provider == "woodpecker":
            # Woodpecker pipelines are commonly used for PR checks; default to PR intent.
            intents = ["pr"]
        else:
            intents = ["all"]
    return intents


def is_local_executable(cmd: str):
    lower = cmd.lower()
    if "codecov" in lower:
        return False
    if "uploader.codecov.io" in lower:
        return False
    if "curl -os" in lower and "codecov" in lower:
        return False
    if "secrets:" in lower:
        return False
    if re.search(r"\bgit\s+push\b", lower):
        return False
    if re.search(r"\bgit\s+commit\b", lower):
        return False
    if re.search(r"\bgh\s+pr\s+(comment|edit)\b", lower):
        return False
    if re.search(r"\bgh\s+api\b", lower) and "issues/comments" in lower:
        return False
    if re.search(r"\bchangeset\s+version\b", lower):
        return False
    if re.search(r"\b(pnpm|npm|yarn)\s+publish\b", lower):
        return False
    if re.search(r"\bdocker\s+push\b", lower):
        return False
    return True


def discover_woodpecker():
    root = repo / ".woodpecker"
    if not root.is_dir():
        return None

    files = sorted(root.glob("*.yml")) + sorted(root.glob("*.yaml"))
    checks = []

    for path in files:
        payload = load_yaml(path)
        if not isinstance(payload, dict):
            continue
        pipeline = payload.get("pipeline")
        if not isinstance(pipeline, dict):
            continue

        for job_name, job in pipeline.items():
            if not isinstance(job, dict):
                continue
            when = job.get("when", {})
            events = []
            if isinstance(when, dict):
                events = normalize_events(when.get("event"))
            intents = infer_intents("woodpecker", events)
            for cmd in flatten_commands(job.get("commands")):
                category = categorize_command(cmd)
                checks.append(
                    {
                        "source_file": str(path.relative_to(repo)),
                        "job": job_name,
                        "category": category,
                        "command": cmd,
                        "events": [normalize_event_name(e) for e in events],
                        "intents": intents,
                        "local_executable": is_local_executable(cmd),
                    }
                )

    return {
        "provider": "woodpecker",
        "files": [str(f.relative_to(repo)) for f in files],
        "checks": checks,
    }


def discover_github_actions():
    root = repo / ".github" / "workflows"
    if not root.is_dir():
        return None

    files = sorted(root.glob("*.yml")) + sorted(root.glob("*.yaml"))
    checks = []

    for path in files:
        payload = load_yaml(path)
        if not isinstance(payload, dict):
            continue
        workflow_events = normalize_events(payload.get("on"))
        workflow_intents = infer_intents("github_actions", workflow_events)
        jobs = payload.get("jobs")
        if not isinstance(jobs, dict):
            continue

        for job_name, job in jobs.items():
            if not isinstance(job, dict):
                continue
            events = workflow_events
            intents = workflow_intents
            steps = job.get("steps", [])
            if not isinstance(steps, list):
                continue
            for step in steps:
                if not isinstance(step, dict):
                    continue
                run = step.get("run")
                if not run:
                    continue
                for cmd in flatten_commands(run):
                    category = categorize_command(cmd)
                    checks.append(
                        {
                            "source_file": str(path.relative_to(repo)),
                            "job": job_name,
                            "category": category,
                            "command": cmd,
                            "events": [normalize_event_name(e) for e in events],
                            "intents": intents,
                            "local_executable": is_local_executable(cmd),
                        }
                    )

    return {
        "provider": "github_actions",
        "files": [str(f.relative_to(repo)) for f in files],
        "checks": checks,
    }


def discover_gitlab_ci():
    candidates = [repo / ".gitlab-ci.yml", repo / ".gitlab-ci.yaml"]
    existing = [p for p in candidates if p.exists()]
    if not existing:
        return None

    path = existing[0]
    payload = load_yaml(path)
    if not isinstance(payload, dict):
        return None

    reserved = {
        "stages",
        "workflow",
        "default",
        "variables",
        "include",
        "image",
        "services",
        "before_script",
        "after_script",
        "cache",
    }

    checks = []
    for job_name, job in payload.items():
        if job_name in reserved or not isinstance(job, dict):
            continue

        events = []
        only = job.get("only")
        if isinstance(only, str):
            events = [only]
        elif isinstance(only, list):
            events = [str(x) for x in only]
        intents = infer_intents("gitlab_ci", events)
        script = job.get("script")
        for cmd in flatten_commands(script):
            category = categorize_command(cmd)
            checks.append(
                {
                    "source_file": str(path.relative_to(repo)),
                    "job": str(job_name),
                    "category": category,
                    "command": cmd,
                    "events": [normalize_event_name(e) for e in events],
                    "intents": intents,
                    "local_executable": is_local_executable(cmd),
                }
            )

    return {
        "provider": "gitlab_ci",
        "files": [str(path.relative_to(repo))],
        "checks": checks,
    }


def parse_target_percent(raw):
    """Parse target value into (target_raw, target_percent, is_auto).

    - ``auto`` → ("auto", None, True)
    - numeric / percent string → (original_string, float_percent, False)
    - missing / unparseable → (None, None, False)
    """
    if raw is None:
        return (None, None, False)
    if isinstance(raw, bool):
        # treat as unknown / invalid
        return (str(raw), None, False)
    if isinstance(raw, (int, float)):
        val = float(raw)
        pct = val * 100 if val <= 1 else val
        return (raw, pct, False)
    text = str(raw).strip()
    if text == "":
        return (None, None, False)
    if text.lower() == "auto":
        return ("auto", None, True)
    cleaned = text[:-1] if text.endswith("%") else text
    try:
        val = float(cleaned)
        pct = val * 100 if val <= 1 and not text.endswith("%") else val
        return (text, pct, False)
    except ValueError:
        return (text, None, False)


def parse_threshold_percent(raw):
    """Parse threshold (e.g. ``1%`` / ``1`` / ``1.0``) into float percent, or None."""
    if raw is None:
        return None
    if isinstance(raw, bool):
        return None
    if isinstance(raw, (int, float)):
        val = float(raw)
        return val * 100 if val <= 1 else val
    text = str(raw).strip()
    if text == "" or text.lower() == "auto":
        return None
    cleaned = text[:-1] if text.endswith("%") else text
    try:
        val = float(cleaned)
        return val * 100 if val <= 1 and not text.endswith("%") else val
    except ValueError:
        return None


def discover_husky_hooks():
    """Scan .husky/ directory for hook shell scripts.

    Produces one entry per non-boilerplate command line per hook file.
    File name = hook_type (pre-commit, commit-msg, post-merge, etc.).
    """
    entries = []
    husky_dir = repo / ".husky"
    if not husky_dir.is_dir():
        return entries

    for path in sorted(husky_dir.iterdir()):
        # Skip subdirectories (e.g., .husky/_/ boilerplate)
        if not path.is_file():
            continue
        # Hook filenames have no extension or .sh
        suffix = path.suffix.lower()
        if suffix not in ("", ".sh"):
            continue
        hook_type = path.stem if suffix == ".sh" else path.name

        try:
            content = path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue

        for raw_line in content.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith("#"):
                continue
            # Shebang
            if line.startswith("#!"):
                continue
            # Husky boilerplate: `. "$(dirname -- "$0")/_/husky.sh"` or similar
            if line.startswith(".") or line.startswith("source"):
                if ".husky/_/" in line or "husky.sh" in line:
                    continue
            # Skip echo / exit lines
            lowered = line.lower()
            if lowered.startswith("echo ") or lowered == "echo":
                continue
            if re.match(r"^exit\s+\d+\s*$", lowered) or lowered == "exit":
                continue

            entries.append(
                {
                    "source_file": str(path.relative_to(repo)),
                    "hook_type": hook_type,
                    "command": line,
                    "category": categorize_command(line),
                    "local_executable": is_local_executable(line),
                }
            )

    return entries


def discover_pre_commit_config():
    """Scan .pre-commit-config.yaml / .pre-commit-hooks.yaml for hook definitions."""
    entries = []
    for filename in (".pre-commit-config.yaml", ".pre-commit-hooks.yaml"):
        path = repo / filename
        if not path.exists():
            continue
        payload = load_yaml(path)
        if not isinstance(payload, dict):
            continue

        repos_list = payload.get("repos", [])
        if not isinstance(repos_list, list):
            continue

        for repo_entry in repos_list:
            if not isinstance(repo_entry, dict):
                continue
            hooks_list = repo_entry.get("hooks", [])
            if not isinstance(hooks_list, list):
                continue
            for hook in hooks_list:
                if not isinstance(hook, dict):
                    continue
                hook_id = str(hook.get("id", "")).strip()
                entry_cmd = hook.get("entry")
                entry_cmd_str = str(entry_cmd).strip() if entry_cmd else ""
                command = entry_cmd_str or hook_id

                stages = hook.get("stages")
                if isinstance(stages, list) and stages:
                    hook_type = str(stages[0]).strip() or "pre-commit"
                else:
                    hook_type = "pre-commit"

                category_target = entry_cmd_str or hook_id
                entries.append(
                    {
                        "source_file": filename,
                        "hook_type": hook_type,
                        "command": command,
                        "category": categorize_command(category_target),
                        "local_executable": True,
                    }
                )

    return entries


def _lintstaged_marker_for_file(source_file: str):
    return {
        "source_file": source_file,
        "hook_type": "lint-staged-config",
        "command": None,
        "category": "lint",
        "local_executable": False,
    }


def _scan_package_json(pkg_path: Path):
    """Scan a single package.json for husky.hooks + lint-staged markers."""
    entries = []
    try:
        raw = pkg_path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return entries
    try:
        data = json.loads(raw)
    except Exception:
        return entries
    if not isinstance(data, dict):
        return entries

    rel = str(pkg_path.relative_to(repo))

    # Legacy husky v4 config: husky.hooks = { "pre-commit": "cmd", ... }
    husky = data.get("husky")
    if isinstance(husky, dict):
        hooks = husky.get("hooks")
        if isinstance(hooks, dict):
            for hook_name, cmd in hooks.items():
                if not isinstance(cmd, str):
                    continue
                cmd_s = cmd.strip()
                if not cmd_s:
                    continue
                entries.append(
                    {
                        "source_file": rel,
                        "hook_type": str(hook_name),
                        "command": cmd_s,
                        "category": categorize_command(cmd_s),
                        "local_executable": is_local_executable(cmd_s),
                    }
                )

    # lint-staged config block directly in package.json
    if "lint-staged" in data:
        entries.append(_lintstaged_marker_for_file(rel))

    return entries


def discover_package_json_hooks():
    """Scan root + workspace package.json for husky.hooks + lint-staged configs.

    Also picks up standalone .lintstagedrc.* files at repo root.
    """
    entries = []

    # 1. Root package.json
    root_pkg = repo / "package.json"
    if root_pkg.exists():
        entries.extend(_scan_package_json(root_pkg))

    # 2. Workspace packages (apps/* / packages/*)
    workspace_globs = ["apps/*/package.json", "packages/*/package.json"]
    for pattern in workspace_globs:
        for pkg_path in sorted(repo.glob(pattern)):
            entries.extend(_scan_package_json(pkg_path))

    # 3. Standalone lint-staged rc files at repo root
    lintstaged_rc_names = [
        ".lintstagedrc",
        ".lintstagedrc.js",
        ".lintstagedrc.cjs",
        ".lintstagedrc.mjs",
        ".lintstagedrc.json",
        ".lintstagedrc.yaml",
        ".lintstagedrc.yml",
        "lint-staged.config.js",
        "lint-staged.config.cjs",
        "lint-staged.config.mjs",
    ]
    for name in lintstaged_rc_names:
        if (repo / name).exists():
            entries.append(_lintstaged_marker_for_file(name))

    return entries


def discover_codecov_flag_gates():
    """Extract every flag in ``flag_management.individual_flags`` with full statuses.

    Schema v2: each flag lists ALL statuses (patch + project), preserving raw
    target / threshold so the runner can decide how to enforce each one.
    Flags without ``statuses`` are still listed (empty list) to surface their
    path configuration for downstream tooling.
    """
    gates = []
    for filename in ("codecov.yml", ".codecov.yml"):
        path = repo / filename
        if not path.exists():
            continue
        payload = load_yaml(path)
        if not isinstance(payload, dict):
            continue

        fm = payload.get("flag_management", {})
        individual_flags = fm.get("individual_flags", []) if isinstance(fm, dict) else []
        for flag in individual_flags:
            if not isinstance(flag, dict):
                continue

            include = []
            exclude = []
            for p in flag.get("paths", []) or []:
                if not isinstance(p, str):
                    continue
                if p.startswith("!"):
                    exclude.append(p[1:])
                else:
                    include.append(p)

            raw_statuses = flag.get("statuses", [])
            statuses = []
            if isinstance(raw_statuses, list):
                for status in raw_statuses:
                    if not isinstance(status, dict):
                        continue
                    status_type = str(status.get("type", "")).strip().lower()
                    if not status_type:
                        continue
                    target_raw, target_percent, is_auto = parse_target_percent(
                        status.get("target")
                    )
                    threshold_percent = parse_threshold_percent(status.get("threshold"))
                    statuses.append(
                        {
                            "type": status_type,
                            "target_raw": target_raw,
                            "target_percent": target_percent,
                            "threshold_percent": threshold_percent,
                            "is_auto": is_auto,
                        }
                    )

            gates.append(
                {
                    "source_file": filename,
                    "flag": str(flag.get("name", "default")),
                    "include_paths": include,
                    "exclude_paths": exclude,
                    "statuses": statuses,
                }
            )

    return gates


provider = discover_woodpecker() or discover_github_actions() or discover_gitlab_ci() or {
    "provider": "unknown",
    "files": [],
    "checks": [],
}

dev_hooks = (
    discover_husky_hooks()
    + discover_pre_commit_config()
    + discover_package_json_hooks()
)

contract = {
    "schema_version": 2,
    "repo": str(repo),
    "provider": provider["provider"],
    "files": provider["files"],
    "checks": provider["checks"],
    "codecov_flag_gates": discover_codecov_flag_gates(),
    "dev_hooks": dev_hooks,
}

print(json.dumps(contract, ensure_ascii=False, indent=2))
PY
