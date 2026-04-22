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
    if raw is None:
        return None
    if isinstance(raw, (int, float)):
        val = float(raw)
        return val * 100 if val <= 1 else val
    text = str(raw).strip()
    if text == "auto":
        return None
    if text.endswith("%"):
        text = text[:-1]
    try:
        val = float(text)
        return val * 100 if val <= 1 else val
    except ValueError:
        return None


def discover_codecov_patch_gates():
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
            statuses = flag.get("statuses", [])
            if not isinstance(statuses, list):
                continue

            patch_status = None
            for status in statuses:
                if isinstance(status, dict) and str(status.get("type", "")).lower() == "patch":
                    patch_status = status
                    break
            if not patch_status:
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

            gates.append(
                {
                    "source_file": filename,
                    "flag": str(flag.get("name", "default")),
                    "target_percent": parse_target_percent(patch_status.get("target")),
                    "include_paths": include,
                    "exclude_paths": exclude,
                }
            )

    return gates


provider = discover_woodpecker() or discover_github_actions() or discover_gitlab_ci() or {
    "provider": "unknown",
    "files": [],
    "checks": [],
}

contract = {
    "schema_version": 1,
    "repo": str(repo),
    "provider": provider["provider"],
    "files": provider["files"],
    "checks": provider["checks"],
    "codecov_patch_gates": discover_codecov_patch_gates(),
}

print(json.dumps(contract, ensure_ascii=False, indent=2))
PY
