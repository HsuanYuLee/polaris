#!/usr/bin/env bash
# Purpose: Canonical parser for task.md header-block fields (DP-090 T1).
#          Single shared implementation for resolve-task-base.sh,
#          engineering-branch-setup.sh, and polaris-pr-create.sh so there is
#          exactly one place that knows where the `Repo:` field lives.
# Inputs:  parse_task_md_repo_name <task_md_path>
# Outputs: stdout the repo name (e.g. "exampleco-web"), or empty string when
#          the task.md has no `Repo:` field. Always exit 0.
#
# The canonical header line format (produced by
# derive-task-md-from-refinement-json.sh) is:
#   > Source: {source} | Task: {task} | JIRA: {jira} | Repo: {name}
# right after the H1 heading, before the first `## ` section. A fixed
# `head -n 20` line-count bound previously missed this line whenever
# frontmatter grew past 20 lines (e.g. verification.behavior_contract with a
# full assertions list) — see DP-090 Background for the incident evidence.
# Scanning up to the first `## ` heading instead is bounded by document
# structure rather than an arbitrary line count, and cannot match text in
# later body sections (Scope Trace Matrix, References to load, etc.).
#
# This file is sourced, not executed — no set -e, no top-level side effects.

parse_task_md_repo_name() {
  local task_md="$1"
  awk '/^## /{exit} {print}' "$task_md" 2>/dev/null \
    | grep -oE 'Repo:[[:space:]]*[A-Za-z0-9._/-]+' \
    | head -n 1 | sed -E 's/^Repo:[[:space:]]*//'
}
