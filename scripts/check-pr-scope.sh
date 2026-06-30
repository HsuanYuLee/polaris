#!/usr/bin/env bash
# scripts/check-pr-scope.sh — DP-230 T16 (D37)
#
# Aggregate-release scope gate. Reads a PR's "Bundle Identity" block from the
# remote PR body (via `gh pr view --json body`), discovers the bundled tasks'
# task.md Allowed Files, and validates the PR diff against the union of those
# Allowed Files. Release-tail files (VERSION / package.json / CHANGELOG.md /
# scripts/manifest.json / sync-to-polaris.sh) are tolerated per refinement EC11
# so framework release metadata can ship with the bundle PR.
#
# Usage:
#   bash scripts/check-pr-scope.sh --pr <N> [--repo <path>] [--gh-repo <owner/repo>]
#
# Exit codes:
#   0  PR diff fits union(allowed files of bundled tasks) ∪ release-tail set
#   1  Scope exceeded — out-of-union files reported in JSON
#   2  Error — bundle identity missing / malformed / gh failure
#
# Output: JSON on stdout describing within_scope / scope_additions /
# bundled_tasks / source / version / release_tail_tolerated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="[polaris-check-pr-scope]"
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"

PR_NUMBER=""
REPO_PATH=""
GH_REPO=""
WORKSPACE_ROOT="${POLARIS_WORKSPACE_ROOT:-}"

usage() {
  cat >&2 <<EOF
Usage: bash scripts/check-pr-scope.sh --pr <N> [--repo <path>] [--gh-repo <owner/repo>]

Validates an aggregate-release PR's diff against the union of bundled tasks'
Allowed Files. Reads PR body via gh, parses the "Bundle Identity" block, and
resolves task.md files from the local workspace tree.

Exit: 0 = within scope, 1 = scope exceeded, 2 = error.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR_NUMBER="$2"; shift 2 ;;
    --pr=*) PR_NUMBER="${1#--pr=}"; shift ;;
    --repo) REPO_PATH="$2"; shift 2 ;;
    --repo=*) REPO_PATH="${1#--repo=}"; shift ;;
    --gh-repo) GH_REPO="$2"; shift 2 ;;
    --gh-repo=*) GH_REPO="${1#--gh-repo=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$PR_NUMBER" ]]; then
  echo "ERROR: --pr <N> is required" >&2
  exit 2
fi
REPO_PATH="${REPO_PATH:-$(pwd)}"

# Resolve workspace root (where docs-manager/.../specs/... live). If not set
# via env, search upward from REPO_PATH for a docs-manager/src/content/docs/specs
# directory.
if [[ -z "$WORKSPACE_ROOT" ]]; then
  probe="$REPO_PATH"
  while [[ "$probe" != "/" && -n "$probe" ]]; do
    if [[ -d "$probe/docs-manager/src/content/docs/specs" ]]; then
      WORKSPACE_ROOT="$probe"
      break
    fi
    probe="$(dirname "$probe")"
  done
fi
if [[ -z "$WORKSPACE_ROOT" || ! -d "$WORKSPACE_ROOT/docs-manager/src/content/docs/specs" ]]; then
  echo "ERROR: cannot locate workspace specs root (set POLARIS_WORKSPACE_ROOT)" >&2
  exit 2
fi

# Read PR body via gh.
GH_VIEW_ARGS=(pr view "$PR_NUMBER" --json body)
if [[ -n "$GH_REPO" ]]; then
  GH_VIEW_ARGS+=(--repo "$GH_REPO")
fi
set +e
PR_VIEW_JSON="$(gh "${GH_VIEW_ARGS[@]}" 2>/dev/null)"
gh_rc=$?
set -e
if [[ "$gh_rc" -ne 0 || -z "$PR_VIEW_JSON" ]]; then
  echo "ERROR: gh pr view failed (rc=$gh_rc)" >&2
  exit 2
fi

PR_BODY="$(printf '%s' "$PR_VIEW_JSON" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("body") or "")')"
if [[ -z "$PR_BODY" ]]; then
  echo "ERROR: PR body is empty; cannot resolve bundle identity" >&2
  exit 2
fi

# Parse the Bundle Identity block. Accept either real newlines or escaped
# `\n` sequences (some gh responses embed escaped newlines inside the JSON
# value when --json body is used inside scripts).
parse_identity() {
  python3 - "$PR_BODY" <<'PY'
import json
import re
import sys

body = sys.argv[1]
# Normalize potential escape sequences left over from JSON decoding twice.
body = body.replace("\r\n", "\n")
body = body.replace("\\n", "\n")

def grab(pattern, text):
    m = re.search(pattern, text, flags=re.MULTILINE)
    return m.group(1).strip() if m else ""

alias = grab(r"^bundle_branch_alias:\s*(.+)$", body)
tasks_raw = grab(r"^bundled_tasks:\s*(.+)$", body)
source = grab(r"^source:\s*(.+)$", body)
version = grab(r"^version:\s*(.+)$", body)

# bundled_tasks may be "[T1, T2, T3]" or "T1, T2, T3"
tasks_raw = tasks_raw.strip()
if tasks_raw.startswith("[") and tasks_raw.endswith("]"):
    tasks_raw = tasks_raw[1:-1]
tasks = [t.strip() for t in tasks_raw.split(",") if t.strip()]

if not (alias and tasks and source and version):
    sys.stderr.write("identity block incomplete: alias={!r} tasks={!r} source={!r} version={!r}\n".format(
        alias, tasks, source, version))
    sys.exit(2)

print(json.dumps({
    "bundle_branch_alias": alias,
    "bundled_tasks": tasks,
    "source": source,
    "version": version,
}))
PY
}

set +e
IDENTITY_JSON="$(parse_identity)"
identity_rc=$?
set -e
if [[ "$identity_rc" -ne 0 ]]; then
  echo "ERROR: cannot parse Bundle Identity block from PR body" >&2
  exit 2
fi

# Resolve each bundled task's task.md and collect Allowed Files.
collect_union() {
  python3 - "$IDENTITY_JSON" "$WORKSPACE_ROOT" "$PARSE_TASK_MD" <<'PY'
import json
import os
import subprocess
import sys

identity = json.loads(sys.argv[1])
workspace = sys.argv[2]
parser = sys.argv[3]

tasks = identity.get("bundled_tasks") or []
specs_root = os.path.join(workspace, "docs-manager", "src", "content", "docs", "specs")

found = []
union = set()
missing = []
for task_id in tasks:
    # Task id like DP-NNN-T{n}. Source ID = DP-NNN. Task suffix = T{n}.
    parts = task_id.split("-")
    if len(parts) < 3:
        missing.append(task_id)
        continue
    source_id = "-".join(parts[:2])  # DP-NNN
    task_suffix = parts[-1]          # T{n}
    # Look under active/archive design-plan and company task locations. Finalized
    # framework tasks live in tasks/pr-release/<task_suffix>/index.md, which must
    # resolve the same as the canonical task resolver.
    candidates = []
    dp_roots = [
        os.path.join(specs_root, "design-plans"),
        os.path.join(specs_root, "design-plans", "archive"),
    ]
    for dp_root in dp_roots:
        if not os.path.isdir(dp_root):
            continue
        for entry in sorted(os.listdir(dp_root)):
            if entry.startswith(source_id):
                for rel in [
                    ("tasks", task_suffix, "index.md"),
                    ("tasks", "pr-release", task_suffix, "index.md"),
                ]:
                    p = os.path.join(dp_root, entry, *rel)
                    if os.path.isfile(p):
                        candidates.append(p)
    companies_root = os.path.join(specs_root, "companies")
    if os.path.isdir(companies_root):
        for company in sorted(os.listdir(companies_root)):
            for rel in [
                (company, source_id, "tasks", task_suffix, "index.md"),
                (company, source_id, "tasks", "pr-release", task_suffix, "index.md"),
                (company, "archive", source_id, "tasks", task_suffix, "index.md"),
                (company, "archive", source_id, "tasks", "pr-release", task_suffix, "index.md"),
            ]:
                p = os.path.join(companies_root, *rel)
                if os.path.isfile(p):
                    candidates.append(p)
    if not candidates:
        missing.append(task_id)
        continue
    # Pick first candidate; deterministic by os.listdir lexical default we sort.
    candidates.sort()
    task_md = candidates[0]
    proc = subprocess.run(
        ["bash", parser, task_md, "--no-resolve"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode != 0:
        missing.append(task_id)
        continue
    data = json.loads(proc.stdout)
    for entry in data.get("allowed_files") or []:
        s = entry.strip()
        if s.startswith("`") and s.endswith("`"):
            s = s[1:-1]
        if s:
            union.add(s)
    found.append({"task_id": task_id, "task_md": task_md})

if missing:
    sys.stderr.write("ERROR: cannot resolve task.md for: {}\n".format(", ".join(missing)))
    sys.exit(2)

print(json.dumps({"found": found, "union": sorted(union)}))
PY
}

set +e
UNION_JSON="$(collect_union)"
union_rc=$?
set -e
if [[ "$union_rc" -ne 0 ]]; then
  echo "ERROR: failed to collect union of Allowed Files" >&2
  exit 2
fi

# Fetch PR diff names.
GH_DIFF_ARGS=(pr diff "$PR_NUMBER" --name-only)
if [[ -n "$GH_REPO" ]]; then
  GH_DIFF_ARGS+=(--repo "$GH_REPO")
fi
set +e
PR_DIFF_RAW="$(gh "${GH_DIFF_ARGS[@]}" 2>/dev/null)"
diff_rc=$?
set -e
if [[ "$diff_rc" -ne 0 ]]; then
  # Fallback: read full diff text and parse "diff --git a/<path>" lines.
  GH_DIFF_FALLBACK=(pr diff "$PR_NUMBER")
  if [[ -n "$GH_REPO" ]]; then
    GH_DIFF_FALLBACK+=(--repo "$GH_REPO")
  fi
  set +e
  PR_DIFF_RAW="$(gh "${GH_DIFF_FALLBACK[@]}" 2>/dev/null | awk '/^diff --git / { sub(/^a\//, "", $3); print $3 }')"
  diff_rc=$?
  set -e
fi
if [[ "$diff_rc" -ne 0 ]]; then
  echo "ERROR: gh pr diff failed (rc=$diff_rc)" >&2
  exit 2
fi
DIFF_FILES="$(printf '%s\n' "$PR_DIFF_RAW" | sed '/^$/d' | sort -u)"

# Persist diff to a tmpfile so the python program can read it from arg[3]
# (avoids the heredoc-vs-pipe stdin collision).
DIFF_TMP="$(mktemp -t polaris-check-pr-scope-diff.XXXXXX)"
printf '%s\n' "$DIFF_FILES" > "$DIFF_TMP"

# Match diff files against union ∪ release-tail.
EVALUATION_JSON="$(
  python3 - "$IDENTITY_JSON" "$UNION_JSON" "$DIFF_TMP" <<'PY'
import fnmatch
import json
import sys

identity = json.loads(sys.argv[1])
union_payload = json.loads(sys.argv[2])
diff_path = sys.argv[3]
patterns = union_payload.get("union") or []
with open(diff_path, "r", encoding="utf-8") as fh:
    diff_files = [line.strip() for line in fh.read().splitlines() if line.strip()]

# DP-230 EC11 / R4: release-tail Allowed Files are tolerated in aggregate-release union.
RELEASE_TAIL = {
    "VERSION",
    "package.json",
    "CHANGELOG.md",
    "scripts/manifest.json",
    "scripts/sync-to-polaris.sh",
}

def matches_pattern(fp, pattern):
    if fp == pattern:
        return True
    parts_f = fp.split("/")
    parts_p = pattern.split("/")
    return _match_parts(parts_f, 0, parts_p, 0)

def _match_parts(fparts, fi, pparts, pi):
    if fi == len(fparts) and pi == len(pparts):
        return True
    if pi == len(pparts):
        return False
    if fi == len(fparts):
        return all(p == "**" for p in pparts[pi:])
    pseg = pparts[pi]
    if pseg == "**":
        if _match_parts(fparts, fi, pparts, pi + 1):
            return True
        if _match_parts(fparts, fi + 1, pparts, pi):
            return True
        return False
    return fnmatch.fnmatchcase(fparts[fi], pseg) and _match_parts(
        fparts, fi + 1, pparts, pi + 1
    )

within = []
additions = []
release_tail_hits = []
for fp in diff_files:
    if fp in RELEASE_TAIL:
        within.append(fp)
        release_tail_hits.append(fp)
        continue
    if any(matches_pattern(fp, p) for p in patterns):
        within.append(fp)
    else:
        additions.append(fp)

print(json.dumps({
    "bundle_branch_alias": identity.get("bundle_branch_alias"),
    "bundled_tasks": identity.get("bundled_tasks"),
    "source": identity.get("source"),
    "version": identity.get("version"),
    "allowed_union": patterns,
    "diff_count": len(diff_files),
    "within_scope": within,
    "scope_additions": additions,
    "release_tail_tolerated": release_tail_hits,
}, indent=2))
PY
)"
rm -f "$DIFF_TMP"

printf '%s\n' "$EVALUATION_JSON"

OUT_OF_SCOPE=$(printf '%s' "$EVALUATION_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("scope_additions") or []))')
if [[ "$OUT_OF_SCOPE" -gt 0 ]]; then
  echo "SCOPE_EXCEEDED: $OUT_OF_SCOPE file(s) outside aggregate-release union" >&2
  exit 1
fi
exit 0
