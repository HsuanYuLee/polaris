#!/usr/bin/env bash
# Purpose: Selftest for scripts/lib/task-md-header-fields.sh — canonical
#          parse_task_md_repo_name() (DP-090 T1, AC1/AC2/AC-NEG1).
# Inputs:  none (builds fixture task.md files in a temp dir).
# Outputs: stdout PASS/FAIL lines; exit 0 = all pass, exit 1 = any failure.
#
# Contract under test:
#   - AC1: long frontmatter (behavior_contract.applies=true + assertions,
#     pushing `Repo:` past line 20) still resolves the repo name.
#   - AC2: short frontmatter (behavior_contract.applies=false) resolves the
#     same as before the fix (regression safety).
#   - AC-NEG1: task.md with no `Repo:` field returns empty string, no crash.
#   - Adversarial: a coincidental "Repo:" occurrence in a later body section
#     (after the first `## ` heading) must not be picked up.
set -euo pipefail

# shellcheck source=../lib/selftest-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/selftest-bootstrap.sh"
init_ROOT_DIR "${BASH_SOURCE[0]}"

# shellcheck source=../lib/task-md-header-fields.sh
source "$ROOT_DIR/scripts/lib/task-md-header-fields.sh"

FAIL=0
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

assert_eq() {
  # Args: <label> <expected> <actual>
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf 'PASS: %s (got %s)\n' "$label" "$actual"
  else
    printf 'FAIL: %s — expected %s, got %s\n' "$label" "$expected" "$actual" >&2
    FAIL=1
  fi
}

# --- AC1: long frontmatter (behavior_contract.applies=true + assertions) -----

long_fm="$FIXTURE_DIR/long-frontmatter.md"
cat > "$long_fm" <<'EOF'
---
title: "EXPROJ-9999 T1: fixture (1 pt)"
description: "fixture task with a long frontmatter block"
draft: true
sidebar:
  hidden: true
status: IN_PROGRESS
task_kind: T
verification:
  behavior_contract:
    applies: true
    mode: parity
    source_of_truth: existing_behavior
    fixture_policy: live_allowed
    baseline_ref: develop
    flow: "fixture flow line one, long enough to push past line 20"
    assertions:
      - "assertion one"
      - "assertion two"
      - "assertion three"
      - "assertion four"
      - "assertion five"
depends_on: []
---

# T1: fixture (1 pt)

> Source: EXPROJ-9999 | Task: EXPROJ-9999 | JIRA: EXPROJ-9999 | Repo: exampleco-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
EOF

out="$(parse_task_md_repo_name "$long_fm" || true)"
assert_eq "AC1 long-frontmatter repo resolves" "exampleco-web" "$out"

# --- AC2: short frontmatter (behavior_contract.applies=false) ---------------

short_fm="$FIXTURE_DIR/short-frontmatter.md"
cat > "$short_fm" <<'EOF'
---
title: "EXPROJ-8888 T1: fixture (1 pt)"
description: "fixture task with a short frontmatter block"
draft: true
sidebar:
  hidden: true
status: IN_PROGRESS
task_kind: T
verification:
  behavior_contract:
    applies: false
    reason: "fixture, no runtime behavior"
depends_on: []
---

# T1: fixture (1 pt)

> Source: EXPROJ-8888 | Task: EXPROJ-8888 | JIRA: EXPROJ-8888 | Repo: exampleco-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
EOF

out="$(parse_task_md_repo_name "$short_fm" || true)"
assert_eq "AC2 short-frontmatter repo resolves (regression)" "exampleco-web" "$out"

# --- AC-NEG1: no Repo: field at all -----------------------------------------

missing_fm="$FIXTURE_DIR/missing-repo.md"
cat > "$missing_fm" <<'EOF'
---
title: "DP-999-T1: fixture (1 pt)"
description: "fixture task with no repo field in the header"
draft: true
sidebar:
  hidden: true
status: IN_PROGRESS
task_kind: T
depends_on: []
---

# T1: fixture (1 pt)

> Source: DP-999 | Task: DP-999-T1

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
EOF

out="$(parse_task_md_repo_name "$missing_fm" || true)"
assert_eq "AC-NEG1 missing Repo: returns empty" "" "$out"

# --- Adversarial: coincidental "Repo:" text after the first heading ---------

adversarial_fm="$FIXTURE_DIR/coincidental-repo-in-body.md"
cat > "$adversarial_fm" <<'EOF'
---
title: "EXPROJ-7777 T1: fixture (1 pt)"
description: "fixture task with no repo field in the header block"
draft: true
sidebar:
  hidden: true
status: IN_PROGRESS
task_kind: T
depends_on: []
---

# T1: fixture (1 pt)

> Source: EXPROJ-7777 | Task: EXPROJ-7777 | JIRA: EXPROJ-7777

## Scope Trace Matrix

Cross-repo note: the upstream service lives in a different repo. Repo: not-the-real-repo
EOF

out="$(parse_task_md_repo_name "$adversarial_fm" || true)"
assert_eq "adversarial: coincidental body Repo: text is not picked up" "" "$out"

if [[ "$FAIL" -eq 0 ]]; then
  printf 'ALL PASS\n'
  exit 0
fi
exit 1
