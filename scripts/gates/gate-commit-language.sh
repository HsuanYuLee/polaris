#!/usr/bin/env bash
set -euo pipefail

# gate-commit-language.sh — commit message language policy gate.
#
# Commit message prose follows PR author language when known. Without PR
# context, it falls back to the workspace `language` setting. Structural tokens
# such as conventional commit type/scope, ticket keys, paths, and API names are
# ignored before language detection.
#
# Usage:
#   gate-commit-language.sh [--repo <path>] (--message <text> | --message-file <path>)
#   gate-commit-language.sh [--repo <path>] --command "git commit -m ..."
#
# Test helpers:
#   --pr-author-language <zh-TW|en|unknown>
#   --pr-description-file <path>
#
# Exit: 0 = pass/skip, 2 = block
# Bypass: POLARIS_SKIP_COMMIT_LANGUAGE_GATE=1

PREFIX="[polaris gate-commit-language]"

REPO_ROOT=""
MESSAGE=""
MESSAGE_FILE=""
COMMAND=""
PR_AUTHOR_LANGUAGE="${POLARIS_COMMIT_PR_AUTHOR_LANGUAGE:-}"
PR_DESCRIPTION_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --message) MESSAGE="${2:-}"; shift 2 ;;
    --message-file) MESSAGE_FILE="${2:-}"; shift 2 ;;
    --command) COMMAND="${2:-}"; shift 2 ;;
    --pr-author-language) PR_AUTHOR_LANGUAGE="${2:-}"; shift 2 ;;
    --pr-description-file) PR_DESCRIPTION_FILE="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '3,19p' "$0"
      exit 0
      ;;
    *) shift ;;
  esac
done

if [[ "${POLARIS_SKIP_COMMIT_LANGUAGE_GATE:-}" == "1" ]]; then
  echo "$PREFIX POLARIS_SKIP_COMMIT_LANGUAGE_GATE=1 — bypassing." >&2
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

if not tokens or tokens[0] != "git":
    print(json.dumps({"skip": True}))
    raise SystemExit(0)

i = 1
while i < len(tokens):
    token = tokens[i]
    if token == "-C" and i + 1 < len(tokens):
        i += 2
        continue
    if token.startswith("-c") and token != "commit":
        if token == "-c" and i + 1 < len(tokens):
            i += 2
        else:
            i += 1
        continue
    break

if i >= len(tokens) or tokens[i] != "commit":
    print(json.dumps({"skip": True}))
    raise SystemExit(0)

messages = []
message_file = ""
uses_no_edit = False
i += 1
while i < len(tokens):
    token = tokens[i]
    if token in {"-m", "--message"} and i + 1 < len(tokens):
        messages.append(tokens[i + 1])
        i += 2
        continue
    if token.startswith("--message="):
        messages.append(token.split("=", 1)[1])
        i += 1
        continue
    if token in {"-F", "--file"} and i + 1 < len(tokens):
        message_file = tokens[i + 1]
        i += 2
        continue
    if token.startswith("--file="):
        message_file = token.split("=", 1)[1]
        i += 1
        continue
    if token == "--no-edit":
        uses_no_edit = True
    i += 1

print(json.dumps({
    "skip": False,
    "message": "\n\n".join(messages),
    "message_file": message_file,
    "uses_no_edit": uses_no_edit,
}))
PY
  )"
  if [[ "$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("skip", False))' <<<"$parsed_json")" == "True" ]]; then
    exit 0
  fi
  MESSAGE="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("message", ""))' <<<"$parsed_json")"
  MESSAGE_FILE="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("message_file", ""))' <<<"$parsed_json")"
  uses_no_edit="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("uses_no_edit", False))' <<<"$parsed_json")"
  if [[ -z "$MESSAGE" && -z "$MESSAGE_FILE" && "$uses_no_edit" == "True" ]]; then
    MESSAGE="$(git -C "$REPO_ROOT" log -1 --pretty=%B 2>/dev/null || true)"
  fi
fi

if [[ -n "$MESSAGE_FILE" ]]; then
  if [[ -f "$MESSAGE_FILE" ]]; then
    MESSAGE="$(<"$MESSAGE_FILE")"
  elif [[ -f "$REPO_ROOT/$MESSAGE_FILE" ]]; then
    MESSAGE="$(<"$REPO_ROOT/$MESSAGE_FILE")"
  else
    echo "$PREFIX BLOCKED: commit message file does not exist: $MESSAGE_FILE" >&2
    exit 2
  fi
fi

if [[ -z "$MESSAGE" ]]; then
  echo "$PREFIX BLOCKED: commit message cannot be inspected before commit. Use -m or -F." >&2
  exit 2
fi

if ! python3 - "$REPO_ROOT" "$PR_AUTHOR_LANGUAGE" "$PR_DESCRIPTION_FILE" "$MESSAGE" <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path

repo = Path(sys.argv[1])
author_language = sys.argv[2].strip()
pr_description_file = sys.argv[3].strip()
message = sys.argv[4]

CJK_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
WORD_RE = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)?")

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

def infer_language(text: str) -> str:
    cjk = len(CJK_RE.findall(text))
    words = WORD_RE.findall(text)
    alpha = sum(ch.isalpha() and ch.isascii() for ch in text)
    if cjk >= 4:
        return "zh-TW"
    if alpha >= 45 and len(words) >= 8:
        return "en"
    return ""

def read_pr_description() -> str:
    if pr_description_file:
        path = Path(pr_description_file)
        if path.is_file():
            return path.read_text(encoding="utf-8", errors="replace")
    env_text = ""
    try:
        import os
        env_text = os.environ.get("POLARIS_COMMIT_PR_DESCRIPTION", "")
    except Exception:
        env_text = ""
    if env_text:
        return env_text
    try:
        proc = subprocess.run(
            ["gh", "pr", "view", "--json", "title,body"],
            cwd=str(repo),
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            data = json.loads(proc.stdout)
            return f"{data.get('title') or ''}\n\n{data.get('body') or ''}"
    except Exception:
        return ""
    return ""

def target_language() -> str:
    if author_language and author_language.lower() not in {"unknown", "n/a", "none", "-"}:
        return "zh-TW" if author_language.lower() in {"zh", "zh-tw", "zh-hant"} else author_language
    pr_lang = infer_language(read_pr_description())
    if pr_lang:
        return pr_lang
    return workspace_language(repo)

def clean_commit_text(text: str) -> str:
    lines = []
    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            continue
        if re.match(r"^[-*]\s*$", stripped):
            continue
        stripped = re.sub(r"^\s{0,3}#{1,6}\s+", "", stripped)
        stripped = re.sub(r"^\s*[-*+]\s+", "", stripped)
        stripped = re.sub(r"^\s*\d+[.)]\s+", "", stripped)
        lines.append(stripped)
    text = " ".join(lines)
    text = re.sub(r"`[^`]*`", " ", text)
    text = re.sub(r"https?://\S+|www\.\S+", " ", text)
    text = re.sub(r"^\s*(?:\[[^\]]+\]\s*)?(?:feat|fix|refactor|test|docs|chore|style|perf|build|ci|revert)(?:\([^)]+\))?!?:\s*", " ", text, flags=re.I)
    text = re.sub(r"\b[A-Z][A-Z0-9]+-\d+(?:-T\d+[a-z]*)?\b", " ", text)
    text = re.sub(r"\bDP-\d{3}(?:-T\d+[a-z]*)?\b", " ", text)
    text = re.sub(r"\b(?:task|feat|feature|bugfix|hotfix|release|wip|origin|main|develop|master)/[A-Za-z0-9._/-]+\b", " ", text)
    text = re.sub(r"(?:^|\s)(?:[./~]?[A-Za-z0-9._-]+/)+(?:[A-Za-z0-9._-]+)?", " ", text)
    text = re.sub(r"\b[A-Za-z0-9_.-]+\.(?:sh|py|js|ts|tsx|vue|json|ya?ml|md|txt)\b", " ", text)
    text = re.sub(r"(?<!\w)--?[A-Za-z][A-Za-z0-9_-]*(?:[= ][A-Za-z0-9._/:@-]+)?", " ", text)
    text = re.sub(r"\b[A-Z][A-Z0-9_]{2,}\b", " ", text)
    text = re.sub(r"\b[A-Za-z_][A-Za-z0-9_]*\(\)", " ", text)
    text = re.sub(r"\b[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z0-9_.-]+\b", " ", text)
    return re.sub(r"\s+", " ", text).strip()

target = target_language()
cleaned = clean_commit_text(message)
words = WORD_RE.findall(cleaned)
alpha = sum(ch.isalpha() and ch.isascii() for ch in cleaned)
cjk = len(CJK_RE.findall(cleaned))

if target in {"zh-TW", "zh-Hant", "zh"}:
    if cjk == 0 and alpha >= 12 and len(words) >= 2:
        print("[polaris gate-commit-language] BLOCKED: commit message appears to be English prose under zh-TW policy.", file=sys.stderr)
        print(f"  Target language: {target}", file=sys.stderr)
        print(f"  Message: {message.splitlines()[0] if message.splitlines() else message}", file=sys.stderr)
        raise SystemExit(2)
elif target.lower().startswith("en"):
    if cjk >= 4:
        print("[polaris gate-commit-language] BLOCKED: commit message appears to be Chinese prose under English policy.", file=sys.stderr)
        print(f"  Target language: {target}", file=sys.stderr)
        print(f"  Message: {message.splitlines()[0] if message.splitlines() else message}", file=sys.stderr)
        raise SystemExit(2)

raise SystemExit(0)
PY
then
  exit 2
fi

echo "$PREFIX ✅ commit message language gate passed." >&2
