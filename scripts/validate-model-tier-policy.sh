#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

fail=0

file_matches() {
  local pattern="$1"
  local file="$2"

  if command -v rg >/dev/null 2>&1; then
    rg -q "$pattern" "$file"
  else
    grep -Eq "$pattern" "$file"
  fi
}

check_mirror_mode() {
  local agents_skills="$ROOT_DIR/.agents/skills"
  local expected_target="../.claude/skills"

  if [[ ! -L "$agents_skills" ]]; then
    echo "FAIL: $agents_skills is not a symlink." >&2
    fail=1
    return
  fi

  local actual_target
  actual_target="$(readlink "$agents_skills")"
  if [[ "$actual_target" != "$expected_target" ]]; then
    echo "FAIL: $agents_skills points to '$actual_target', expected '$expected_target'." >&2
    fail=1
    return
  fi

  echo "OK: .agents/skills -> $expected_target"
}

check_codex_agent_profiles() {
  local agents_dir="$ROOT_DIR/.codex/agents"
  local file

  if [[ ! -d "$agents_dir" ]]; then
    echo "FAIL: .codex/agents is missing; Codex model-class adapter profiles are required." >&2
    fail=1
    return
  fi

  file="$agents_dir/polaris-small-fast.toml"
  if [[ ! -f "$file" ]]; then
    echo "FAIL: invalid Codex small_fast adapter profile: .codex/agents/polaris-small-fast.toml" >&2
    fail=1
  elif ! file_matches '^name = "polaris-small-fast"$' "$file"; then
    echo "FAIL: invalid Codex small_fast adapter profile: .codex/agents/polaris-small-fast.toml" >&2
    fail=1
  elif ! file_matches '^model = "gpt-5\.4-mini"$' "$file"; then
    echo "FAIL: invalid Codex small_fast adapter profile: .codex/agents/polaris-small-fast.toml" >&2
    fail=1
  elif ! file_matches 'Model Class: small_fast' "$file"; then
    echo "FAIL: invalid Codex small_fast adapter profile: .codex/agents/polaris-small-fast.toml" >&2
    fail=1
  fi

  file="$agents_dir/polaris-realtime-fast.toml"
  if [[ ! -f "$file" ]]; then
    echo "FAIL: invalid Codex realtime_fast adapter profile: .codex/agents/polaris-realtime-fast.toml" >&2
    fail=1
  elif ! file_matches '^name = "polaris-realtime-fast"$' "$file"; then
    echo "FAIL: invalid Codex realtime_fast adapter profile: .codex/agents/polaris-realtime-fast.toml" >&2
    fail=1
  elif ! file_matches '^model = "gpt-5\.3-codex-spark"$' "$file"; then
    echo "FAIL: invalid Codex realtime_fast adapter profile: .codex/agents/polaris-realtime-fast.toml" >&2
    fail=1
  elif ! file_matches 'Model Class: realtime_fast' "$file"; then
    echo "FAIL: invalid Codex realtime_fast adapter profile: .codex/agents/polaris-realtime-fast.toml" >&2
    fail=1
  fi

  file="$agents_dir/polaris-standard-coding.toml"
  if [[ ! -f "$file" ]]; then
    echo "FAIL: invalid Codex standard_coding adapter profile: .codex/agents/polaris-standard-coding.toml" >&2
    fail=1
  elif ! file_matches '^name = "polaris-standard-coding"$' "$file"; then
    echo "FAIL: invalid Codex standard_coding adapter profile: .codex/agents/polaris-standard-coding.toml" >&2
    fail=1
  elif ! file_matches 'Model Class: standard_coding' "$file"; then
    echo "FAIL: invalid Codex standard_coding adapter profile: .codex/agents/polaris-standard-coding.toml" >&2
    fail=1
  elif file_matches '^model[[:space:]]*=' "$file"; then
    echo "FAIL: polaris-standard-coding must inherit the parent model and omit model." >&2
    fail=1
  fi

  file="$agents_dir/polaris-frontier-reasoning.toml"
  if [[ ! -f "$file" ]]; then
    echo "FAIL: invalid Codex frontier_reasoning adapter profile: .codex/agents/polaris-frontier-reasoning.toml" >&2
    fail=1
  elif ! file_matches '^name = "polaris-frontier-reasoning"$' "$file"; then
    echo "FAIL: invalid Codex frontier_reasoning adapter profile: .codex/agents/polaris-frontier-reasoning.toml" >&2
    fail=1
  elif ! file_matches '^model = "gpt-5\.5"$' "$file"; then
    echo "FAIL: invalid Codex frontier_reasoning adapter profile: .codex/agents/polaris-frontier-reasoning.toml" >&2
    fail=1
  elif ! file_matches 'Model Class: frontier_reasoning' "$file"; then
    echo "FAIL: invalid Codex frontier_reasoning adapter profile: .codex/agents/polaris-frontier-reasoning.toml" >&2
    fail=1
  fi
}

scan_raw_model_policy() {
  if ! python3 - "$ROOT_DIR" <<'PY'
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
pattern = re.compile(
    r'model:[ \t]*"?((haiku)|(sonnet)|(opus)|(claude-[A-Za-z0-9._-]+)|(gpt-[A-Za-z0-9._-]+))"?'
    r'|claude-sonnet-[A-Za-z0-9._-]+'
    r'|gpt-[0-9][A-Za-z0-9._-]*'
    r'|\b(haiku|sonnet|opus)[ \t]+(model|sub-agent|subagent)\b'
    r'|\b(haiku|sonnet|opus)\b[ \t]+for[ \t]+.*(batch|jira|explore|execute|review|implementation|coding)'
)

def rel(path: Path) -> str:
    return os.path.relpath(path, root)

def is_allowed(path: str) -> bool:
    if path == ".claude/skills/references/model-tier-policy.md":
        return True
    if path == "CHANGELOG.md" or path.endswith("/CHANGELOG.md"):
        return True
    if "release-notes" in path or "ReleaseNotes" in path:
        return True
    if "runtime" in path and "example" in path:
        return True
    if "runtime" in path and "adapter" in path:
        return True
    if "model" in path and "adapter" in path:
        return True
    if re.fullmatch(r"specs/[^/]+/artifacts/research-report-.*\.md", path):
        return True
    if re.fullmatch(r"specs/design-plans/[^/]+/artifacts/research-report-.*\.md", path):
        return True
    return False

def candidate_files():
    roots: list[Path] = []
    for path in [root / ".claude/skills", root / ".claude/rules"]:
        if path.is_dir():
            roots.append(path)
    for path in [root / "CLAUDE.md", root / "AGENTS.md"]:
        if path.is_file():
            roots.append(path)

    for scan_root in roots:
        if scan_root.is_file():
            yield scan_root
            continue
        for dirpath, dirnames, filenames in os.walk(scan_root):
            dirnames[:] = [name for name in dirnames if name not in {".git", "node_modules"}]
            for name in filenames:
                path = Path(dirpath) / name
                if name == "SKILL.md" or path.suffix in {".md", ".json", ".yaml", ".yml"}:
                    yield path

failed = False
for path in candidate_files():
    relative = rel(path)
    if is_allowed(relative):
        continue
    matches: list[str] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        continue
    for line_no, line in enumerate(lines, start=1):
        if pattern.search(line):
            matches.append(f"{line_no}:{line}")
    if matches:
        failed = True
        print(f"FAIL: raw provider model policy outside approved mapping location: {relative}", file=sys.stderr)
        print("\n".join(matches), file=sys.stderr)

sys.exit(1 if failed else 0)
PY
  then
    fail=1
  fi
}

check_mirror_mode
check_codex_agent_profiles
scan_raw_model_policy

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "PASS: model tier policy drift check passed"
