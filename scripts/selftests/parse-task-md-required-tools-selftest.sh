#!/usr/bin/env bash
# Purpose: Selftest for parse-task-md.sh `required_tools` field output (DP-345 AC2).
# Inputs:  none (builds task.md fixtures in a temp dir)
# Outputs: TAP-ish lines to stdout; exit 0 on PASS, 1 on FAIL
# Side effects: writes/removes a temp dir only
#
# Asserts:
#   1. parse-task-md.sh emits a structured `required_tools` array parsed from the
#      `## Required Tools` markdown table (name/owner/install_authority/check_command/
#      install_command/runtime_profile/goes_to_mise/handoff_hint).
#   2. A frontmatter `description` containing the literal `## Required Tools`
#      (DP-344-T1 collision shape) does NOT pollute the parse — the canonical
#      parser strips frontmatter before line-anchoring `^## `, so the real body
#      section is returned, not the frontmatter literal.
#   3. install_command "N/A" normalizes to empty string.
#   4. A task.md with no Required Tools section yields an empty array.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PARSER="$REPO_ROOT/scripts/parse-task-md.sh"

TOTAL=0
PASS=0
fail() { printf 'not ok %s\n' "$1" >&2; }
ok() { printf 'ok %s\n' "$1"; }

assert_eq() {
  local label="$1" got="$2" want="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); ok "$label"
  else
    fail "$label: got '$got' want '$want'"
  fi
}

tmpdir="$(mktemp -d -t parse-task-md-required-tools.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# Fixture 1: frontmatter description literally contains "## Required Tools"
# (DP-344-T1 collision shape) AND a real ## Required Tools body section.
fixture="$tmpdir/T1.md"
cat > "$fixture" <<'MD'
---
title: "T1: tooling fixture (2 pt)"
description: "This task touches the ## Required Tools section and the ## Allowed Files section. The naive parser would mis-fire on these frontmatter literals."
status: IN_PROGRESS
task_kind: T
task_shape: implementation
verification:
  behavior_contract:
    applies: false
    reason: "static"
depends_on: []
---

# T1: tooling fixture (2 pt)

> Source: DP-345 | Task: DP-345-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-345 |
| Task ID | DP-345-T1 |
| JIRA key | N/A |
| Base branch | feat/DP-345 |

## Required Tools

| Tool | Owner | install_authority | check_command | install_command | runtime_profile | goes_to_mise | handoff_hint |
|------|-------|-------------------|---------------|-----------------|-----------------|--------------|--------------|
| `jq` | framework | root_mise | `jq --version` | `mise install` | core | true | run mise install |
| `mockoon-cli` | ticket | manual_user_action | `mockoon-cli --version` | N/A | ticket | false | install mockoon-cli manually |

## Allowed Files

- `scripts/parse-task-md.sh`

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A
MD

json="$(bash "$PARSER" "$fixture" --no-resolve)"

count="$(printf '%s' "$json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("required_tools") or []))')"
assert_eq "F1.tool_count" "$count" "2"

first_name="$(printf '%s' "$json" | python3 -c 'import json,sys; t=json.load(sys.stdin)["required_tools"]; print(t[0]["name"])')"
assert_eq "F1.first_name" "$first_name" "jq"

first_owner="$(printf '%s' "$json" | python3 -c 'import json,sys; t=json.load(sys.stdin)["required_tools"]; print(t[0]["owner"])')"
assert_eq "F1.first_owner" "$first_owner" "framework"

first_check="$(printf '%s' "$json" | python3 -c 'import json,sys; t=json.load(sys.stdin)["required_tools"]; print(t[0]["check_command"])')"
assert_eq "F1.first_check" "$first_check" "jq --version"

first_mise="$(printf '%s' "$json" | python3 -c 'import json,sys; t=json.load(sys.stdin)["required_tools"]; print(t[0]["goes_to_mise"])')"
assert_eq "F1.first_goes_to_mise" "$first_mise" "true"

# install_command N/A normalizes to empty
second_install="$(printf '%s' "$json" | python3 -c 'import json,sys; t=json.load(sys.stdin)["required_tools"]; print(repr(t[1]["install_command"]))')"
assert_eq "F1.second_install_na_empty" "$second_install" "''"

second_handoff="$(printf '%s' "$json" | python3 -c 'import json,sys; t=json.load(sys.stdin)["required_tools"]; print(t[1]["handoff_hint"])')"
assert_eq "F1.second_handoff" "$second_handoff" "install mockoon-cli manually"

# Adversarial: the frontmatter description literal "## Required Tools" must NOT
# pollute parsing. If naive text.find were used, the frontmatter line (no table)
# would be matched first and the result would be 0 tools. We assert 2.
assert_eq "F1.no_frontmatter_pollution" "$count" "2"

# Fixture 2: no Required Tools section → empty array
fixture2="$tmpdir/T2.md"
cat > "$fixture2" <<'MD'
# T2: no tools (1 pt)

> Source: DP-345 | Task: DP-345-T2 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-345 |
| Task ID | DP-345-T2 |
| JIRA key | N/A |
| Base branch | feat/DP-345 |

## Allowed Files

- `scripts/foo.sh`

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A
MD

count2="$(bash "$PARSER" "$fixture2" --no-resolve | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("required_tools") or []))')"
assert_eq "F2.empty_tools" "$count2" "0"

echo "---"
echo "$PASS/$TOTAL passed"
[[ "$PASS" -eq "$TOTAL" ]] || exit 1
echo "[selftest] PASS"
