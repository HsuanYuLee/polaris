#!/usr/bin/env bash
# Purpose: Single source of truth for bundle-aware closeout ancestry detection.
#          Extracted from framework-release-closeout.sh Wall A (DP-273) so that
#          framework-release-closeout.sh AND check-local-extension-completion.sh
#          share ONE bundle detector — there must be no second copy.
# Inputs:  Sourced (not executed). Callers invoke the two functions below.
# Outputs: Function stdout (alias value / intersection count). No side effects.
#
# This file is sourced, not executed — no set -e, no top-level side effects.
#
# Provides:
#   bundle_branch_alias_for_task <task_md>
#     Echoes the task.md frontmatter `bundle_branch_alias` value (empty when
#     absent). Uses the SAME awk parse shape that gate-work-source.sh and
#     resolve-task-md-by-branch.sh (DP-237 / DP-270) already use, keeping a
#     single canonical reader for bundle detection.
#
#   release_diff_intersects_allowed_files <task_md> <release_commit> <repo_root> <parser_json>
#     Echoes the count of files in the release commit's diff that match this
#     task's Allowed Files. This is the PRIMARY bundle-delivery signal (release
#     diff ∩ task Allowed Files non-empty). It is best-effort: a bundle task
#     whose delivery only touches generated / shared (carved-out) files may
#     legitimately have an EMPTY intersection (DP-273 Blind Spots), so callers
#     must NOT treat an empty result as a delivery failure — the bundle release
#     head remains the authoritative head and verify evidence is enforced
#     downstream by the completion gate.

# DP-273 Wall A: read `bundle_branch_alias` from task.md frontmatter.
bundle_branch_alias_for_task() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk '
    /^---$/ { fm++; next }
    fm == 1 && /^bundle_branch_alias:/ {
      sub(/^bundle_branch_alias:[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print
      exit
    }
  ' "$file" 2>/dev/null || true
}

# DP-273 Wall A: report whether the release commit's diff touches any file owned
# by this task's Allowed Files. Echoes the count of intersecting files.
release_diff_intersects_allowed_files() {
  local task_md="$1"
  local release_commit="$2"
  local repo_root="$3"
  local parser_json="$4"
  python3 - "$task_md" "$release_commit" "$repo_root" "$parser_json" <<'PY'
import json
import subprocess
import sys

task_md, release_commit, repo_root, parser_json = sys.argv[1:5]

data = json.loads(parser_json)
patterns = []
for entry in data.get("allowed_files") or []:
    s = entry.strip()
    if s.startswith("`") and s.endswith("`"):
        s = s[1:-1]
    if s:
        patterns.append(s)

# Release diff = files changed by the release commit relative to its first
# parent. Squashed cherry-pick / fresh-commit bundles land as a single commit,
# so commit^..commit captures the bundled delivery. When the commit has no
# parent (root), fall back to the full tree listing.
def diff_files():
    rc = subprocess.run(
        ["git", "-C", repo_root, "rev-parse", "--verify", "--quiet",
         release_commit + "^"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    if rc.returncode == 0:
        proc = subprocess.run(
            ["git", "-C", repo_root, "diff", "--name-only",
             release_commit + "^", release_commit],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
    else:
        proc = subprocess.run(
            ["git", "-C", repo_root, "ls-tree", "-r", "--name-only",
             release_commit],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
    return [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]

def match_parts(fparts, fi, pparts, pi):
    import fnmatch
    if fi == len(fparts) and pi == len(pparts):
        return True
    if pi == len(pparts):
        return False
    if fi == len(fparts):
        return all(p == "**" for p in pparts[pi:])
    pseg = pparts[pi]
    if pseg == "**":
        if match_parts(fparts, fi, pparts, pi + 1):
            return True
        if match_parts(fparts, fi + 1, pparts, pi):
            return True
        return False
    return fnmatch.fnmatchcase(fparts[fi], pseg) and match_parts(
        fparts, fi + 1, pparts, pi + 1
    )

def matches(fp, pattern):
    if fp == pattern:
        return True
    return match_parts(fp.split("/"), 0, pattern.split("/"), 0)

count = 0
for fp in diff_files():
    if any(matches(fp, p) for p in patterns):
        count += 1
print(count)
PY
}
