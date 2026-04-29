#!/usr/bin/env bash
# validate-language-policy.sh — workspace artifact language policy gate.
#
# Purpose: validate skill-produced artifacts against workspace-config.yaml language.
# Exit codes:
#   0 — PASS, or advisory findings only
#   1 — blocking language policy violations
#   2 — usage error / file not found / unsupported mode
#
# Usage:
#   validate-language-policy.sh [--blocking|--advisory] [--mode artifact|bilingual|bilingual-source|bilingual-translation] [--language LANG] [--workspace-root DIR] <file>...
#   validate-language-policy.sh --selftest
#   LANGUAGE_POLICY_SELFTEST=1 validate-language-policy.sh

set -euo pipefail

usage() {
  cat >&2 <<EOF
usage: $0 [--blocking|--advisory] [--mode artifact|bilingual|bilingual-source|bilingual-translation] [--language LANG] [--workspace-root DIR] <file>...

Options:
  --blocking            Exit 1 when violations are found.
  --advisory            Print findings but exit 0. Default.
  --mode artifact       Enforce normal artifact policy. Default.
  --mode bilingual      Allow bilingual/source documents without zh-TW-only enforcement.
  --mode bilingual-source|bilingual-translation
                        Aliases for bilingual documentation pairs.
  --language LANG       Override workspace-config.yaml language.
  --workspace-root DIR  Root used to find workspace-config.yaml.
  --selftest            Run embedded selftest.
EOF
  exit 2
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

read_language_from_config() {
  local config="$1"
  if [[ ! -f "$config" ]]; then
    return 0
  fi
  awk -F ':' '
    /^[[:space:]]*language[[:space:]]*:/ {
      v=$2
      sub(/#.*/, "", v)
      gsub(/^[[:space:]"'\''"]+|[[:space:]"'\''"]+$/, "", v)
      if (v != "") {
        print v
      }
      exit
    }
  ' "$config"
}

read_workspace_language_upward() {
  local start="${1:-$PWD}"
  local dir="$start"
  if [[ -f "$dir" ]]; then
    dir="$(dirname "$dir")"
  fi
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/workspace-config.yaml" ]]; then
      local language
      language="$(read_language_from_config "$dir/workspace-config.yaml" || true)"
      if [[ -n "$language" ]]; then
        printf '%s\n' "$language"
        return 0
      fi
    fi
    dir="$(dirname "$dir")"
  done
  return 0
}

run_validator() {
  local enforcement="$1"
  local mode="$2"
  local language="$3"
  shift 3

  python3 - "$enforcement" "$mode" "$language" "$@" <<'PY'
import re
import sys
from pathlib import Path

enforcement = sys.argv[1]
mode = sys.argv[2]
language = sys.argv[3]
files = sys.argv[4:]

if mode not in {"artifact", "bilingual", "bilingual-source", "bilingual-translation"}:
    print(f"error: unsupported mode '{mode}' (expected artifact|bilingual|bilingual-source|bilingual-translation)", file=sys.stderr)
    sys.exit(2)

if enforcement not in {"blocking", "advisory"}:
    print(f"error: unsupported enforcement '{enforcement}'", file=sys.stderr)
    sys.exit(2)

if not files:
    print("error: no artifact files supplied", file=sys.stderr)
    sys.exit(2)

if not language:
    missing = [f for f in files if not Path(f).is_file()]
    if missing:
        for f in missing:
            print(f"error: file not found: {f}", file=sys.stderr)
        sys.exit(2)
    print("language_unset: no non-empty language found in workspace-config.yaml ancestry", file=sys.stderr)
    sys.exit(1 if enforcement == "blocking" else 0)

if mode in {"bilingual", "bilingual-source", "bilingual-translation"} or language not in {"zh-TW", "zh-Hant", "zh"}:
    missing = [f for f in files if not Path(f).is_file()]
    if missing:
        for f in missing:
            print(f"error: file not found: {f}", file=sys.stderr)
        sys.exit(2)
    sys.exit(0)

CJK_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
URL_RE = re.compile(r"https?://\S+|www\.\S+")
INLINE_CODE_RE = re.compile(r"`[^`]*`")
HTML_TAG_RE = re.compile(r"<[^>]+>")
TICKET_RE = re.compile(r"\b[A-Z][A-Z0-9]+-\d+(?:-T\d+[a-z]*)?\b")
BRANCH_RE = re.compile(r"\b(?:task|feat|feature|bugfix|hotfix|release|wip|origin|main|develop|master|rc)/[A-Za-z0-9._/-]+\b")
PATH_RE = re.compile(r"(?:^|\s)(?:[./~]?[A-Za-z0-9._-]+/)+(?:[A-Za-z0-9._-]+)?")
FLAG_RE = re.compile(r"(?<!\w)--?[A-Za-z][A-Za-z0-9_-]*(?:[= ][A-Za-z0-9._/:@-]+)?")
ENV_RE = re.compile(r"\b[A-Z][A-Z0-9_]{2,}\b")
KEY_VALUE_RE = re.compile(r"^\s*[-*]?\s*[A-Za-z0-9_.-]+\s*[:=]\s*(?:[`'\"]?[A-Za-z0-9_.:/-]+[`'\"]?)?\s*$")
MARKDOWN_LINK_RE = re.compile(r"\[[^\]]+\]\([^)]+\)")
WORD_RE = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)?")

FUNCTION_WORDS = {
    "a", "an", "and", "are", "as", "at", "be", "because", "by", "can",
    "could", "do", "does", "for", "from", "has", "have", "if", "in", "into",
    "is", "it", "its", "must", "not", "of", "on", "or", "should", "that",
    "the", "their", "there", "these", "this", "to", "was", "were", "when",
    "where", "which", "will", "with", "without", "would", "you", "your",
}

def strip_markdown_prefix(line: str) -> str:
    line = re.sub(r"^\s{0,3}>\s?", "", line)
    line = re.sub(r"^\s*[-*+]\s+", "", line)
    line = re.sub(r"^\s*\d+[.)]\s+", "", line)
    return line.strip()

def is_structural_line(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return True
    if stripped.startswith("|"):
        return True
    if re.match(r"^\s{0,3}#{1,6}\s+", stripped):
        return True
    if re.match(r"^\s*-{3,}\s*$", stripped):
        return True
    if stripped.startswith("```") or stripped.startswith("~~~"):
        return True
    if KEY_VALUE_RE.match(stripped):
        return True
    return False

def paragraphs(path: Path):
    in_fence = False
    fence_marker = ""
    current = []

    def flush():
        nonlocal current
        if current:
            yield " ".join(current).strip()
            current = []

    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = raw.strip()
        if stripped.startswith(("```", "~~~")):
            yield from flush()
            if not in_fence:
                in_fence = True
                fence_marker = stripped[:3]
            elif stripped.startswith(fence_marker):
                in_fence = False
            continue
        if in_fence:
            continue
        if is_structural_line(raw):
            yield from flush()
            continue
        is_list_item = bool(re.match(r"^\s*(?:[-*+]|\d+[.)])\s+", raw))
        if is_list_item:
            yield from flush()
        line = strip_markdown_prefix(raw)
        if not line:
            yield from flush()
            continue
        if is_list_item:
            yield line
        else:
            current.append(line)
    yield from flush()

def cleaned_for_language(text: str) -> str:
    text = INLINE_CODE_RE.sub(" ", text)
    text = MARKDOWN_LINK_RE.sub(" ", text)
    text = URL_RE.sub(" ", text)
    text = HTML_TAG_RE.sub(" ", text)
    text = TICKET_RE.sub(" ", text)
    text = BRANCH_RE.sub(" ", text)
    text = PATH_RE.sub(" ", text)
    text = FLAG_RE.sub(" ", text)
    text = ENV_RE.sub(" ", text)
    text = re.sub(r"\b[A-Za-z0-9_.-]+\.(?:sh|py|js|ts|tsx|vue|json|ya?ml|md|txt)\b", " ", text)
    text = re.sub(r"\b[A-Za-z_][A-Za-z0-9_]*\(\)", " ", text)
    text = re.sub(r"\b[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z0-9_.-]+\b", " ", text)
    return re.sub(r"\s+", " ", text).strip()

def is_full_english_natural_language(text: str) -> bool:
    if CJK_RE.search(text):
        return False
    cleaned = cleaned_for_language(text)
    if CJK_RE.search(cleaned):
        return False
    alpha_chars = sum(ch.isalpha() and ch.isascii() for ch in cleaned)
    if alpha_chars < 45:
        return False
    words = [w.lower() for w in WORD_RE.findall(cleaned)]
    if len(words) < 8:
        return False
    function_count = sum(1 for w in words if w in FUNCTION_WORDS)
    if function_count < 3:
        return False
    identifierish = sum(1 for w in words if "_" in w or any(ch.isdigit() for ch in w))
    if identifierish / max(len(words), 1) > 0.35:
        return False
    return True

violations = []
for file_name in files:
    path = Path(file_name)
    if not path.is_file():
        print(f"error: file not found: {file_name}", file=sys.stderr)
        sys.exit(2)
    for idx, para in enumerate(paragraphs(path), start=1):
        if is_full_english_natural_language(para):
            snippet = re.sub(r"\s+", " ", para).strip()
            if len(snippet) > 140:
                snippet = snippet[:137] + "..."
            violations.append((str(path), idx, snippet))

if violations:
    label = "language policy violations" if enforcement == "blocking" else "language policy advisory findings"
    print(f"✗ {label}:", file=sys.stderr)
    for path, idx, snippet in violations:
        print(f"  - {path}: paragraph {idx}: full English natural-language paragraph under zh-TW policy", file=sys.stderr)
        print(f"    {snippet}", file=sys.stderr)
    sys.exit(1 if enforcement == "blocking" else 0)

sys.exit(0)
PY
}

selftest() {
  local tmpdir pass fail total
  tmpdir="$(mktemp -d)"
  pass=0
  fail=0
  total=0

  assert_rc() {
    local expected="$1"
    shift
    total=$((total + 1))
    set +e
    "$@" >/tmp/language-policy-selftest.out 2>/tmp/language-policy-selftest.err
    local actual=$?
    set -e
    if [[ "$actual" == "$expected" ]]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "FAIL [$total]: expected rc=$expected got rc=$actual — $*" >&2
      sed 's/^/  stderr: /' /tmp/language-policy-selftest.err >&2 || true
    fi
  }

  cat > "$tmpdir/zh.md" <<'MD'
# 目標

這是一段繁體中文 artifact，包含 `scripts/validate-language-policy.sh`、https://example.com/path 與 `JSON` key，應該通過。
MD

  cat > "$tmpdir/en.md" <<'MD'
This is a full English paragraph that should fail zh-TW artifact policy because it is natural language output.
MD

  cat > "$tmpdir/code-heavy.md" <<'MD'
```bash
LANGUAGE_POLICY_SELFTEST=1 bash scripts/validate-language-policy.sh
```

- `source_type`: `dp`
- `task/DP-050-T3-workspace-language-policy-gate-script`
- https://example.com/docs/path
- `scripts/validate-language-policy.sh --blocking --mode artifact`
MD

  mkdir -p "$tmpdir/root/company"
  cat > "$tmpdir/root/workspace-config.yaml" <<'YAML'
language: zh-TW
YAML
  cat > "$tmpdir/root/company/workspace-config.yaml" <<'YAML'
# Company config intentionally does not override language.
projects: []
YAML
  cp "$tmpdir/en.md" "$tmpdir/root/company/en.md"

  mkdir -p "$tmpdir/no-language"
  cat > "$tmpdir/no-language/workspace-config.yaml" <<'YAML'
projects: []
YAML
  cp "$tmpdir/zh.md" "$tmpdir/no-language/zh.md"

  assert_rc 0 env -u LANGUAGE_POLICY_SELFTEST bash "$script_dir/validate-language-policy.sh" --blocking --language zh-TW --mode artifact "$tmpdir/zh.md"
  assert_rc 1 env -u LANGUAGE_POLICY_SELFTEST bash "$script_dir/validate-language-policy.sh" --blocking --language zh-TW --mode artifact "$tmpdir/en.md"
  assert_rc 0 env -u LANGUAGE_POLICY_SELFTEST bash "$script_dir/validate-language-policy.sh" --advisory --language zh-TW --mode artifact "$tmpdir/en.md"
  assert_rc 0 env -u LANGUAGE_POLICY_SELFTEST bash "$script_dir/validate-language-policy.sh" --blocking --language zh-TW --mode artifact "$tmpdir/code-heavy.md"
  assert_rc 0 env -u LANGUAGE_POLICY_SELFTEST bash "$script_dir/validate-language-policy.sh" --blocking --language zh-TW --mode bilingual "$tmpdir/en.md"
  assert_rc 0 env -u LANGUAGE_POLICY_SELFTEST bash "$script_dir/validate-language-policy.sh" --blocking --language zh-TW --mode bilingual-source "$tmpdir/en.md"
  assert_rc 0 env -u LANGUAGE_POLICY_SELFTEST bash "$script_dir/validate-language-policy.sh" --blocking --language en --mode artifact "$tmpdir/en.md"
  assert_rc 1 bash -c "cd '$tmpdir/root/company' && env -u LANGUAGE_POLICY_SELFTEST bash '$script_dir/validate-language-policy.sh' --blocking --mode artifact '$tmpdir/root/company/en.md'"
  assert_rc 1 bash -c "cd '$tmpdir/no-language' && env -u LANGUAGE_POLICY_SELFTEST bash '$script_dir/validate-language-policy.sh' --blocking --mode artifact '$tmpdir/no-language/zh.md'"
  assert_rc 0 bash -c "cd '$tmpdir/no-language' && env -u LANGUAGE_POLICY_SELFTEST bash '$script_dir/validate-language-policy.sh' --advisory --mode artifact '$tmpdir/no-language/zh.md'"

  echo "validate-language-policy.sh selftest: $pass/$total passed, $fail failed"
  rm -rf "$tmpdir"
  [[ "$fail" -eq 0 ]]
}

if [[ "${LANGUAGE_POLICY_SELFTEST:-}" == "1" ]]; then
  selftest
  exit $?
fi

enforcement="advisory"
mode="artifact"
language=""
workspace_root=""
files=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --blocking)
      enforcement="blocking"
      shift
      ;;
    --advisory)
      enforcement="advisory"
      shift
      ;;
    --mode)
      [[ $# -ge 2 ]] || usage
      mode="$2"
      shift 2
      ;;
    --language)
      [[ $# -ge 2 ]] || usage
      language="$2"
      shift 2
      ;;
    --workspace-root)
      [[ $# -ge 2 ]] || usage
      workspace_root="$2"
      shift 2
      ;;
    --selftest)
      selftest
      exit $?
      ;;
    --help|-h)
      usage
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage
      ;;
    *)
      files+=("$1")
      shift
      ;;
  esac
done

if [[ ${#files[@]} -eq 0 ]]; then
  usage
fi

if [[ -z "$language" ]]; then
  if [[ -n "$workspace_root" ]]; then
    language="$(read_workspace_language_upward "$workspace_root" || true)"
  else
    language="$(read_workspace_language_upward "$PWD" || true)"
  fi
fi

run_validator "$enforcement" "$mode" "$language" "${files[@]}"
