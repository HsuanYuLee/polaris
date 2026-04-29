#!/usr/bin/env bash
set -euo pipefail

# gate-pr-language.sh — GitHub PR metadata language gate.
#
# Validates PR title/body/comment/review prose before it is sent to GitHub.
# It accepts explicit metadata fields or parses a `gh pr ...` command string.
#
# Usage:
#   gate-pr-language.sh [--repo <path>] [--title <text>] [--body <text>] [--body-file <path>]
#   gate-pr-language.sh [--repo <path>] --command "gh pr edit --title ... --body-file ..."
#
# Exit: 0 = pass/skip, 2 = block
# Bypass: POLARIS_SKIP_PR_LANGUAGE_GATE=1

PREFIX="[polaris gate-pr-language]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_SCRIPTS="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATOR="$WORKSPACE_SCRIPTS/validate-language-policy.sh"

REPO_ROOT=""
TITLE=""
BODY=""
BODY_FILE=""
COMMAND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --body) BODY="${2:-}"; shift 2 ;;
    --body-file) BODY_FILE="${2:-}"; shift 2 ;;
    --command) COMMAND="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '3,16p' "$0"
      exit 0
      ;;
    *) shift ;;
  esac
done

if [[ "${POLARIS_SKIP_PR_LANGUAGE_GATE:-}" == "1" ]]; then
  echo "$PREFIX POLARIS_SKIP_PR_LANGUAGE_GATE=1 — bypassing." >&2
  exit 0
fi

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

if [[ -n "$COMMAND" ]]; then
  parsed_json="$(
    python3 - "$COMMAND" <<'PY'
import json
import shlex
import sys

command = sys.argv[1]
try:
    tokens = shlex.split(command)
except ValueError:
    print(json.dumps({"skip": True}))
    raise SystemExit(0)

while tokens and "=" in tokens[0] and not tokens[0].startswith("-") and tokens[0].split("=", 1)[0].replace("_", "").isalnum():
    tokens = tokens[1:]

if len(tokens) < 3 or tokens[0] != "gh" or tokens[1] != "pr":
    print(json.dumps({"skip": True}))
    raise SystemExit(0)

subcommand = tokens[2]
if subcommand not in {"create", "edit", "comment", "review"}:
    print(json.dumps({"skip": True}))
    raise SystemExit(0)

title = ""
body = ""
body_file = ""
i = 3
while i < len(tokens):
    token = tokens[i]
    if token == "--title" and i + 1 < len(tokens):
        title = tokens[i + 1]
        i += 2
        continue
    if token.startswith("--title="):
        title = token.split("=", 1)[1]
        i += 1
        continue
    if token == "--body" and i + 1 < len(tokens):
        body = tokens[i + 1]
        i += 2
        continue
    if token.startswith("--body="):
        body = token.split("=", 1)[1]
        i += 1
        continue
    if token == "--body-file" and i + 1 < len(tokens):
        body_file = tokens[i + 1]
        i += 2
        continue
    if token.startswith("--body-file="):
        body_file = token.split("=", 1)[1]
        i += 1
        continue
    i += 1

print(json.dumps({
    "skip": False,
    "subcommand": subcommand,
    "title": title,
    "body": body,
    "body_file": body_file,
}))
PY
  )"
  if [[ "$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("skip", False))' <<<"$parsed_json")" == "True" ]]; then
    exit 0
  fi
  TITLE="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("title", ""))' <<<"$parsed_json")"
  BODY="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("body", ""))' <<<"$parsed_json")"
  BODY_FILE="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("body_file", ""))' <<<"$parsed_json")"
fi

tmp_file="$(mktemp -t polaris-pr-language.XXXXXX.md)"
cleanup() {
  rm -f "$tmp_file"
}
trap cleanup EXIT

body_text=""
if [[ -n "$BODY_FILE" ]]; then
  if [[ "$BODY_FILE" == "-" ]]; then
    echo "$PREFIX BLOCKED: --body-file - cannot be inspected before GitHub write." >&2
    exit 2
  elif [[ -f "$BODY_FILE" ]]; then
    body_text="$(<"$BODY_FILE")"
  elif [[ -f "$REPO_ROOT/$BODY_FILE" ]]; then
    body_text="$(<"$REPO_ROOT/$BODY_FILE")"
  else
    echo "$PREFIX BLOCKED: --body-file does not exist: $BODY_FILE" >&2
    exit 2
  fi
elif [[ -n "$BODY" ]]; then
  body_text="$BODY"
fi

if [[ -n "$TITLE" ]]; then
  if ! python3 - "$REPO_ROOT" "$TITLE" <<'PY'
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1])
title = sys.argv[2]

def read_language_from_config(path: Path) -> str:
    if not path.is_file():
        return ""
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"\s*language\s*:\s*([^#]+)", line)
        if match:
            return match.group(1).strip().strip("\"'")
    return ""

def workspace_language(start: Path) -> str:
    cur = start if start.is_dir() else start.parent
    while cur != cur.parent:
        language = read_language_from_config(cur / "workspace-config.yaml")
        if language:
            return language
        cur = cur.parent
    return ""

language = workspace_language(repo)
if language not in {"zh-TW", "zh-Hant", "zh"}:
    raise SystemExit(0)
if re.search(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", title):
    raise SystemExit(0)

cleaned = re.sub(r"`[^`]*`", " ", title)
cleaned = re.sub(r"^\s*(?:\[[^\]]+\]\s*)?(?:[a-z]+)(?:\([^)]+\))?!?:\s*", " ", cleaned)
cleaned = re.sub(r"\b[A-Z][A-Z0-9]+-\d+(?:-T\d+[a-z]*)?\b", " ", cleaned)
cleaned = re.sub(r"\b(?:task|feat|feature|bugfix|hotfix|release|wip|origin|main|develop|master)/[A-Za-z0-9._/-]+\b", " ", cleaned)
cleaned = re.sub(r"\b[A-Za-z0-9_.-]+\.(?:sh|py|js|ts|tsx|vue|json|ya?ml|md|txt)\b", " ", cleaned)
cleaned = re.sub(r"(?<!\w)--?[A-Za-z][A-Za-z0-9_-]*(?:[= ][A-Za-z0-9._/:@-]+)?", " ", cleaned)
words = re.findall(r"[A-Za-z]+(?:'[A-Za-z]+)?", cleaned)
alpha = sum(ch.isalpha() and ch.isascii() for ch in cleaned)

if alpha >= 12 and len(words) >= 2:
    print("[polaris gate-pr-language] BLOCKED: PR title appears to be English prose under zh-TW policy.", file=sys.stderr)
    print(f"  Title: {title}", file=sys.stderr)
    raise SystemExit(2)
PY
  then
    exit 2
  fi
fi

if [[ -z "$body_text" ]]; then
  echo "$PREFIX ✅ PR language gate passed." >&2
  exit 0
fi

{
  if [[ -n "$TITLE" ]]; then
    printf 'PR title\n\n%s\n\n' "$TITLE"
  fi
  printf '%s\n' "$body_text"
} > "$tmp_file"

if ! "$VALIDATOR" --blocking --mode artifact --workspace-root "$REPO_ROOT" "$tmp_file"; then
  echo "$PREFIX BLOCKED: PR text violates workspace language policy." >&2
  exit 2
fi

echo "$PREFIX ✅ PR language gate passed." >&2
