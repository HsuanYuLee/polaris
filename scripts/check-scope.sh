#!/usr/bin/env bash
# scripts/check-scope.sh — DP-032 Wave γ D20
#
# Mechanical scope gate: compares `git diff --name-only` against the task.md
# `## Allowed Files` section. Used by engineer-delivery-flow.md § Step 1.5
# (Scope Gate, after Simplify, before Quality).
#
# Contract:
#   check-scope.sh <task_md>
#
# Steps:
#   1. parse-task-md.sh → allowed_files array + resolved_base + task_jira_key
#   2. git diff --name-only origin/{resolved_base}..HEAD → changed files
#   3. For each changed file: check against allowed patterns
#   4. Emit JSON: {within_scope, scope_additions, task_key, allowed_count, diff_count}
#
# Pattern matching:
#   - Exact path: `src/foo.ts` matches `src/foo.ts`
#   - Glob `**`: `src/products/**` matches `src/products/index.ts`
#   - Glob `*`: `src/*.ts` matches `src/foo.ts`
#   - Backtick-wrapped entries are unwrapped: `\`src/foo.ts\`` → `src/foo.ts`
#   - Non-path entries (Chinese text, descriptions) are skipped
#
# Exit codes:
#   0  All changes within scope (scope_additions is empty)
#   1  Scope exceeded — scope_additions is non-empty
#   2  Error — parse failure / git error / usage error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"

usage() {
  cat <<EOF >&2
Usage:
  $(basename "$0") <task_md>

Compares git diff against task.md Allowed Files. Outputs JSON.

Exit:  0 = within scope, 1 = scope exceeded, 2 = error.
EOF
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Match files against allowed patterns using Python (correct path-aware globbing).
# * matches within a single directory segment (does NOT cross /)
# ** matches across directory boundaries
# Reads patterns from $1 (JSON array file), diff files from $2 (newline file)
# Outputs JSON: {"within_scope": [...], "scope_additions": [...]}
_match_files_py() {
  local patterns_json="$1"
  local diff_file="$2"
  python3 -c "
import json, sys, re, os

def match_pattern(filepath, pattern):
    \"\"\"Path-aware glob matching. * = single segment, ** = cross-segment.\"\"\"
    # Exact match
    if filepath == pattern:
        return True

    parts_f = filepath.split('/')
    parts_p = pattern.split('/')
    return _match_parts(parts_f, 0, parts_p, 0)

def _match_parts(fparts, fi, pparts, pi):
    # Both exhausted
    if fi == len(fparts) and pi == len(pparts):
        return True
    # Pattern exhausted but file not (or vice versa)
    if pi == len(pparts):
        return False
    if fi == len(fparts):
        # Remaining pattern segments must all be '**'
        return all(p == '**' for p in pparts[pi:])

    pseg = pparts[pi]

    if pseg == '**':
        # ** matches zero or more path segments
        # Try matching zero segments (skip **)
        if _match_parts(fparts, fi, pparts, pi + 1):
            return True
        # Try matching one or more segments (consume one file part, keep **)
        if _match_parts(fparts, fi + 1, pparts, pi):
            return True
        return False
    else:
        # Single segment match (supports * and ? within segment)
        if _seg_match(fparts[fi], pseg):
            return _match_parts(fparts, fi + 1, pparts, pi + 1)
        return False

def _seg_match(text, pattern):
    \"\"\"fnmatch-style matching for a single path segment (no / crossing).\"\"\"
    import fnmatch
    return fnmatch.fnmatchcase(text, pattern)

with open(sys.argv[1]) as f:
    patterns = json.load(f)
with open(sys.argv[2]) as f:
    files = [l.strip() for l in f if l.strip()]

# Clean patterns: strip backticks, filter non-path entries
clean_patterns = []
for p in patterns:
    s = p.strip()
    if s.startswith('\`') and s.endswith('\`'):
        s = s[1:-1]
    if '/' in s or '.' in s or '*' in s or '?' in s:
        clean_patterns.append(s)

within = []
additions = []
for f in files:
    matched = any(match_pattern(f, p) for p in clean_patterns)
    if matched:
        within.append(f)
    else:
        additions.append(f)

print(json.dumps({'within_scope': within, 'scope_additions': additions}))
" "$patterns_json" "$diff_file"
}

# Thin wrappers for selftest (these call the Python matcher under the hood)
matches_pattern() {
  local file="$1"
  local pattern="$2"
  local tmp_p; tmp_p=$(mktemp)
  local tmp_f; tmp_f=$(mktemp)
  echo "[\"$pattern\"]" > "$tmp_p"
  echo "$file" > "$tmp_f"
  local result
  result=$(_match_files_py "$tmp_p" "$tmp_f" 2>/dev/null)
  rm -f "$tmp_p" "$tmp_f"
  local additions
  additions=$(echo "$result" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['scope_additions']))" 2>/dev/null)
  [[ "$additions" == "0" ]] && return 0 || return 1
}

# ---------------------------------------------------------------------------
# Selftest
# ---------------------------------------------------------------------------
if [[ "${CHECK_SCOPE_SELFTEST:-}" == "1" ]]; then
  PASS=0; FAIL=0; TOTAL=0
  _assert() {
    TOTAL=$((TOTAL + 1))
    if [[ "$1" == "$2" ]]; then
      PASS=$((PASS + 1))
    else
      FAIL=$((FAIL + 1))
      echo "FAIL [$TOTAL]: expected='$2' got='$1' — $3" >&2
    fi
  }

  # Test matches_pattern directly
  matches_pattern "src/foo.ts" "src/foo.ts" && r="y" || r="n"
  _assert "$r" "y" "exact match"

  matches_pattern "src/products/index.ts" "src/products/**" && r="y" || r="n"
  _assert "$r" "y" "** glob"

  matches_pattern "src/products/sub/deep.ts" "src/products/**" && r="y" || r="n"
  _assert "$r" "y" "** deep glob"

  matches_pattern "src/other.ts" "src/products/**" && r="y" || r="n"
  _assert "$r" "n" "** glob no match"

  matches_pattern "src/foo.ts" "src/*.ts" && r="y" || r="n"
  _assert "$r" "y" "* glob with extension"

  matches_pattern "src/sub/foo.ts" "src/*.ts" && r="y" || r="n"
  _assert "$r" "n" "* glob no deep match"

  # Test strip_backticks → handled by Python now, test via matches_pattern
  matches_pattern "src/foo.ts" '`src/foo.ts`' && r="y" || r="n"
  _assert "$r" "y" "backtick-wrapped pattern"

  # Test non-path entries are skipped (Python filters these)
  # "上述檔案的 test 檔" has no /, ., *, ? → skipped by Python
  tmp_p=$(mktemp); tmp_f=$(mktemp)
  echo '["上述檔案的 test 檔"]' > "$tmp_p"
  echo "src/foo.ts" > "$tmp_f"
  result=$(_match_files_py "$tmp_p" "$tmp_f" 2>/dev/null)
  additions=$(echo "$result" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['scope_additions']))" 2>/dev/null)
  _assert "$additions" "1" "Chinese description not a pattern → file is scope_addition"
  rm -f "$tmp_p" "$tmp_f"

  matches_pattern "file.md" "*.md" && r="y" || r="n"
  _assert "$r" "y" "glob pattern at root"

  # Integration test with git repo
  TMPDIR_ST=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_ST"' EXIT

  REMOTE="$TMPDIR_ST/remote.git"
  LOCAL="$TMPDIR_ST/local"
  git init --bare "$REMOTE" >/dev/null 2>&1
  git clone "$REMOTE" "$LOCAL" >/dev/null 2>&1
  (
    cd "$LOCAL"
    git checkout -b main >/dev/null 2>&1
    mkdir -p src/products
    echo "init" > src/index.ts
    echo "init" > src/products/list.ts
    git add -A && git commit -m "init" >/dev/null 2>&1
    git push -u origin main >/dev/null 2>&1
    git checkout -b task/TEST-1-demo >/dev/null 2>&1
    # Change an allowed file
    echo "changed" >> src/products/list.ts
    git add -A && git commit -m "allowed change" >/dev/null 2>&1
  )

  TASK_MD="$TMPDIR_ST/task.md"
  cat > "$TASK_MD" <<'TASK'
# T1 — Demo

> Epic: TEST-1 | JIRA: TEST-1 | Repo: test

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | TEST-1 |
| Parent Epic | TEST-1 |
| Base branch | main |
| Task branch | task/TEST-1-demo |
| Depends on | — |

## Allowed Files

- `src/products/**`

## Test Command

echo ok
TASK

  # Unset selftest env to avoid infinite recursion when calling self
  _run() { env -u CHECK_SCOPE_SELFTEST bash "$SCRIPT_DIR/check-scope.sh" "$@"; }

  # T-int-1: within scope
  out=$(cd "$LOCAL" && _run "$TASK_MD" 2>/dev/null)
  rc=$?
  _assert "$rc" "0" "T-int-1: allowed change should pass"

  # T-int-2: scope exceeded — add a file outside allowed
  (
    cd "$LOCAL"
    echo "extra" >> src/index.ts
    git add -A && git commit -m "out of scope" >/dev/null 2>&1
  )
  out=$(cd "$LOCAL" && _run "$TASK_MD" 2>/dev/null)
  rc=$?
  _assert "$rc" "1" "T-int-2: out-of-scope change should exit 1"
  echo "$out" | grep -q "SCOPE_EXCEEDED" && t="found" || t="missing"
  _assert "$t" "found" "T-int-2: stdout should contain SCOPE_EXCEEDED"
  echo "$out" | grep -q "src/index.ts" && t="found" || t="missing"
  _assert "$t" "found" "T-int-2: scope_additions should list src/index.ts"

  # T-int-3: error — no args
  out=$(env -u CHECK_SCOPE_SELFTEST bash "$SCRIPT_DIR/check-scope.sh" 2>/dev/null)
  rc=$?
  _assert "$rc" "2" "T-int-3: no args should exit 2"

  echo ""
  echo "check-scope.sh selftest: $PASS/$TOTAL passed, $FAIL failed"
  [[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
fi

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

TASK_MD="$1"

if [[ ! -f "$TASK_MD" ]]; then
  echo "ERROR: task_md not found: $TASK_MD" >&2
  exit 2
fi

# Step 1: Parse task.md
TASK_JSON=$("$PARSE_TASK_MD" "$TASK_MD" 2>/dev/null)
if [[ $? -ne 0 || -z "$TASK_JSON" ]]; then
  echo "ERROR: parse-task-md.sh failed for $TASK_MD" >&2
  exit 2
fi

RESOLVED_BASE=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('resolved_base') or '')" 2>/dev/null)
TASK_KEY=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); oc=d.get('operational_context',{}); m=d.get('metadata',{}); print(oc.get('task_jira_key') or m.get('jira') or '')" 2>/dev/null)
ALLOWED_JSON=$(echo "$TASK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get('allowed_files') or []))" 2>/dev/null)

if [[ -z "$RESOLVED_BASE" || "$RESOLVED_BASE" == "null" ]]; then
  echo "ERROR: could not resolve base branch from $TASK_MD" >&2
  exit 2
fi

# Step 2: Get changed files
DIFF_FILES=$(git diff --name-only "origin/$RESOLVED_BASE"..HEAD 2>/dev/null)
if [[ $? -ne 0 ]]; then
  echo "ERROR: git diff failed for origin/$RESOLVED_BASE..HEAD" >&2
  exit 2
fi

# Step 3+4: Match files against patterns using Python
TMPDIR_SCOPE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_SCOPE"' EXIT

echo "$ALLOWED_JSON" > "$TMPDIR_SCOPE/patterns.json"
echo "$DIFF_FILES" > "$TMPDIR_SCOPE/diff_files.txt"

MATCH_RESULT=$(_match_files_py "$TMPDIR_SCOPE/patterns.json" "$TMPDIR_SCOPE/diff_files.txt" 2>/dev/null)
if [[ $? -ne 0 || -z "$MATCH_RESULT" ]]; then
  echo "ERROR: file matching failed" >&2
  exit 2
fi

# Step 5: Emit full JSON with metadata
SCOPE_ADDITIONS_COUNT=$(echo "$MATCH_RESULT" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['scope_additions']))" 2>/dev/null)
ALLOWED_COUNT=$(echo "$ALLOWED_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
DIFF_COUNT=$(echo "$DIFF_FILES" | grep -c '.' 2>/dev/null || echo "0")
[[ -z "$DIFF_FILES" ]] && DIFF_COUNT=0

python3 -c "
import json, sys
match = json.loads(sys.argv[1])
match['task_key'] = sys.argv[2]
match['allowed_count'] = int(sys.argv[3])
match['diff_count'] = int(sys.argv[4])
print(json.dumps(match, indent=2))
" "$MATCH_RESULT" "${TASK_KEY:-unknown}" "${ALLOWED_COUNT:-0}" "$DIFF_COUNT"

# Step 6: Exit code
if [[ "$SCOPE_ADDITIONS_COUNT" -gt 0 ]]; then
  echo "SCOPE_EXCEEDED: $SCOPE_ADDITIONS_COUNT file(s) outside Allowed Files"
  exit 1
else
  exit 0
fi
