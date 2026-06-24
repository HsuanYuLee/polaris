#!/usr/bin/env bash
# Purpose: DP-344 selftest — changeset files pass the scope/boundary/changeset
#   gates ONLY by being in task.md `## Allowed Files`, never via a `.changeset`
#   carve-out. Covers the convergence of changeset Allowed-Files admission into a
#   single mechanism: derive injects the deterministic changeset path (D1), and
#   check-scope / skill-workflow-boundary-gate / gate-changeset all admit it
#   purely through Allowed-Files matching (D2/D3/D6).
# Inputs:  none (builds hermetic git repos + refinement.json fixtures in tmpdirs)
# Outputs: stdout PASS line on success; non-zero exit + stderr on failure
# Exit code: 0 = pass, non-zero = fail
#
# AC coverage:
#   AC2 : check-scope — (a) changeset IN Allowed Files → within_scope (exit 0);
#         (b) changeset NOT in Allowed Files → out_of_scope (exit 1). Proves the
#         `.changeset/*.md` auto-within-scope back door is gone.
#   AC3 : skill-workflow-boundary-gate --check — task.md Allowed Files contains
#         the changeset path + changeset is committed → no out-of-scope violation
#         (boundary gate is pure Allowed-Files matching; no .changeset carve-out).
#   AC5 : re-derive DP-343-T1 (in-flight migration) → task.md Allowed Files
#         contains the changeset path, and the deliverable (with committed
#         changeset) passes check-scope + boundary-gate + gate-changeset (all 3).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVE="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"
CHECK_SCOPE="$ROOT_DIR/scripts/check-scope.sh"
BOUNDARY_GATE="$ROOT_DIR/scripts/skill-workflow-boundary-gate.sh"
GATE_CHANGESET="$ROOT_DIR/scripts/gates/gate-changeset.sh"
POLARIS_CHANGESET="$ROOT_DIR/scripts/polaris-changeset.sh"
PARSE_TASK_MD="$ROOT_DIR/scripts/parse-task-md.sh"

for s in "$DERIVE" "$CHECK_SCOPE" "$BOUNDARY_GATE" "$GATE_CHANGESET" "$POLARIS_CHANGESET" "$PARSE_TASK_MD"; do
  [[ -x "$s" ]] || { echo "FAIL: not executable: $s" >&2; exit 1; }
done

tmproot="$(mktemp -d -t check-scope-changeset.XXXXXX)"
trap 'rm -rf "$tmproot"' EXIT

# ---------------------------------------------------------------------------
# Static check: the `.changeset/*.md` auto-within-scope carve-out must not exist
# as live logic in check-scope.sh or the boundary gate. (Comments documenting
# the removal are allowed; an active startswith('.changeset') branch is not.)
# ---------------------------------------------------------------------------
if grep -nE "startswith\(['\"]\.changeset" "$CHECK_SCOPE" >/dev/null 2>&1; then
  echo "FAIL [static / D2]: check-scope.sh still has an active .changeset carve-out branch" >&2
  exit 1
fi
if grep -n "changeset" "$BOUNDARY_GATE" >/dev/null 2>&1; then
  echo "FAIL [static / D3]: skill-workflow-boundary-gate.sh references changeset (must be pure Allowed-Files matching)" >&2
  exit 1
fi

# build_changeset_repo: create a hermetic single-package git repo that
# participates in Changesets. Echoes the repo root path.
build_changeset_repo() {
  local repo="$1"
  mkdir -p "$repo/.changeset"
  cat > "$repo/.changeset/config.json" <<'EOF'
{ "$schema": "x", "changelog": "@changesets/cli/changelog", "commit": false, "fixed": [], "linked": [], "access": "restricted", "baseBranch": "main", "updateInternalDependencies": "patch", "ignore": [] }
EOF
  cat > "$repo/package.json" <<'EOF'
{ "name": "@selftest/changeset-repo", "version": "1.0.0" }
EOF
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest
  git -C "$repo" checkout -q -b main
  echo "init" > "$repo/src.js"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "init"
  printf '%s\n' "$repo"
}

# make_ref_json: write a DP-backed refinement.json fixture for one impl task.
# Args: $1 = out path, $2 = task id (e.g. DP-343-T1), $3 = title
make_ref_json() {
  local out="$1" tid="$2" title="$3"
  local dpid="${tid%-T*}"
  cat > "$out" <<JSON
{
  "source": { "type": "dp", "id": "$dpid", "container": "/tmp/$dpid", "plan_path": "/tmp/$dpid/index.md", "jira_key": null },
  "schema_version": 1,
  "tasks": [
    {
      "id": "$tid",
      "kind": "implementation",
      "title": "$title",
      "scope": "changeset migration scope.",
      "allowed_files": ["scripts/derive-task-md-from-refinement-json.sh"],
      "modules": ["scripts/derive-task-md-from-refinement-json.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "behavior_contract": { "applies": false, "reason": "framework infra; no runtime behavior" },
      "test_environment": { "level": "static" },
      "references": ["scripts/sample.sh"],
      "verification": { "method": "unit_test", "detail": "bash scripts/selftests/sample-selftest.sh", "verify_command": "bash scripts/selftests/sample-selftest.sh" }
    }
  ]
}
JSON
}

# ===========================================================================
# AC2 — check-scope admits a changeset file ONLY through Allowed Files.
# ===========================================================================
ac2_repo="$tmproot/ac2-repo"
build_changeset_repo "$ac2_repo" >/dev/null

ac2_changeset=".changeset/dp-344-t1-scope-case.md"
# Create the changeset file as an uncommitted (untracked) change.
cat > "$ac2_repo/$ac2_changeset" <<'EOF'
---
"@selftest/changeset-repo": patch
---

DP-344-T1 scope case
EOF

# (a) Allowed Files CONTAINS the changeset path → within_scope.
ac2_task_in="$tmproot/ac2-task-in.md"
cat > "$ac2_task_in" <<EOF
# T1 — AC2 changeset in Allowed Files

> Epic: DP-344 | JIRA: DP-344-T1 | Repo: changeset-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-344-T1 |
| Parent Epic | DP-344 |
| Base branch | main |
| Task branch | task/DP-344-T1-scope |

## Allowed Files

- \`$ac2_changeset\`

## Test Command

echo ok
EOF

set +e
out_in="$(git -C "$ac2_repo" stash list >/dev/null 2>&1; cd "$ac2_repo" && bash "$CHECK_SCOPE" "$ac2_task_in" 2>/dev/null)"
rc_in=$?
set -e
if [[ "$rc_in" != "0" ]]; then
  echo "FAIL [AC2a]: changeset in Allowed Files should be within_scope (rc=$rc_in)" >&2
  echo "$out_in" >&2
  exit 1
fi

# (b) Allowed Files does NOT contain the changeset path → out_of_scope.
ac2_task_out="$tmproot/ac2-task-out.md"
cat > "$ac2_task_out" <<EOF
# T1 — AC2 changeset NOT in Allowed Files

> Epic: DP-344 | JIRA: DP-344-T1 | Repo: changeset-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-344-T1 |
| Parent Epic | DP-344 |
| Base branch | main |
| Task branch | task/DP-344-T1-scope |

## Allowed Files

- \`scripts/some-other-file.sh\`

## Test Command

echo ok
EOF

set +e
out_out="$(cd "$ac2_repo" && bash "$CHECK_SCOPE" "$ac2_task_out" 2>/dev/null)"
rc_out=$?
set -e
if [[ "$rc_out" != "1" ]]; then
  echo "FAIL [AC2b]: changeset NOT in Allowed Files should be out_of_scope (exit 1), got rc=$rc_out (carve-out back door still present?)" >&2
  echo "$out_out" >&2
  exit 1
fi
if ! printf '%s' "$out_out" | grep -qF -- "$ac2_changeset"; then
  echo "FAIL [AC2b]: scope_additions should list the un-allowed changeset file" >&2
  echo "$out_out" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# AC2 (CJK) — a changeset filename derived from a CJK task title contains CJK
# codepoints but is still a file PATH (has '/', ends in .md, no whitespace). It
# must be honored as an Allowed-Files entry, not silently dropped as if it were
# Chinese prose. This guards the is_path_pattern path-shape carve-out: a CJK
# changeset path in Allowed Files → within_scope; absent → out_of_scope.
# ---------------------------------------------------------------------------
ac2cjk_repo="$tmproot/ac2cjk-repo"
build_changeset_repo "$ac2cjk_repo" >/dev/null

ac2cjk_changeset=".changeset/dp-344-t1-注入-移除-case.md"
cat > "$ac2cjk_repo/$ac2cjk_changeset" <<'EOF'
---
"@selftest/changeset-repo": patch
---

DP-344-T1 注入 移除 case
EOF

ac2cjk_task="$tmproot/ac2cjk-task.md"
cat > "$ac2cjk_task" <<EOF
# T1 — AC2 CJK changeset path in Allowed Files

> Epic: DP-344 | JIRA: DP-344-T1 | Repo: changeset-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-344-T1 |
| Parent Epic | DP-344 |
| Base branch | main |
| Task branch | task/DP-344-T1-scope |

## Allowed Files

- \`$ac2cjk_changeset\`

## Test Command

echo ok
EOF

set +e
out_cjk="$(cd "$ac2cjk_repo" && bash "$CHECK_SCOPE" "$ac2cjk_task" 2>/dev/null)"
rc_cjk=$?
set -e
if [[ "$rc_cjk" != "0" ]]; then
  echo "FAIL [AC2 CJK]: CJK changeset path in Allowed Files should be within_scope (rc=$rc_cjk); is_path_pattern must not drop CJK file paths" >&2
  echo "$out_cjk" >&2
  exit 1
fi

# But a bare CJK prose entry (no '/', no extension, no whitespace) must STILL be
# skipped — the path-shape carve-out only admits path-shaped tokens.
ac2cjk_prose_repo="$tmproot/ac2cjk-prose-repo"
build_changeset_repo "$ac2cjk_prose_repo" >/dev/null
echo "untracked stray" > "$ac2cjk_prose_repo/stray.js"
ac2cjk_prose_task="$tmproot/ac2cjk-prose-task.md"
cat > "$ac2cjk_prose_task" <<EOF
# T1 — AC2 CJK prose stays skipped

> Epic: DP-344 | JIRA: DP-344-T1 | Repo: changeset-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-344-T1 |
| Parent Epic | DP-344 |
| Base branch | main |
| Task branch | task/DP-344-T1-prose |

## Allowed Files

- \`中文描述沒有路徑形狀\`

## Test Command

echo ok
EOF
set +e
out_prose="$(cd "$ac2cjk_prose_repo" && bash "$CHECK_SCOPE" "$ac2cjk_prose_task" 2>/dev/null)"
rc_prose=$?
set -e
if [[ "$rc_prose" != "1" ]]; then
  echo "FAIL [AC2 CJK prose]: bare CJK prose entry must still be skipped (file out_of_scope, exit 1), got rc=$rc_prose" >&2
  echo "$out_prose" >&2
  exit 1
fi

# ===========================================================================
# AC3 — boundary gate admits the committed changeset purely via Allowed Files.
# ===========================================================================
ac3_repo="$tmproot/ac3-repo"
build_changeset_repo "$ac3_repo" >/dev/null

ac3_changeset=".changeset/dp-344-t1-boundary-case.md"
ac3_task="$tmproot/ac3-task.md"
cat > "$ac3_task" <<EOF
# T1 — AC3 boundary gate

> Epic: DP-344 | JIRA: DP-344-T1 | Repo: changeset-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-344-T1 |
| Parent Epic | DP-344 |
| Base branch | main |
| Task branch | task/DP-344-T1-boundary |

## Allowed Files

- \`$ac3_changeset\`

## Test Command

echo ok
EOF

# Establish boundary baseline on a feature branch, then commit the changeset.
git -C "$ac3_repo" checkout -q -b task/DP-344-T1-boundary
export POLARIS_RUNTIME_DIR="$tmproot/ac3-runtime"
bash "$BOUNDARY_GATE" --skill engineering --start \
  --source-container "$tmproot" --repo "$ac3_repo" --task-md "$ac3_task" \
  --session-id ac3 >/dev/null 2>&1 || {
  echo "FAIL [AC3]: boundary gate --start failed" >&2
  exit 1
}
cat > "$ac3_repo/$ac3_changeset" <<'EOF'
---
"@selftest/changeset-repo": patch
---

DP-344-T1 boundary case
EOF
git -C "$ac3_repo" add -A
git -C "$ac3_repo" commit -q -m "add changeset"

set +e
bash "$BOUNDARY_GATE" --skill engineering --check \
  --source-container "$tmproot" --repo "$ac3_repo" --task-md "$ac3_task" \
  --session-id ac3 >/dev/null 2>&1
rc_b=$?
set -e
unset POLARIS_RUNTIME_DIR
if [[ "$rc_b" != "0" ]]; then
  echo "FAIL [AC3]: boundary gate --check flagged the in-Allowed-Files committed changeset as a violation (rc=$rc_b)" >&2
  exit 1
fi

# ===========================================================================
# AC5 — re-derive DP-343-T1 migration: derive injects the changeset path; the
# committed deliverable passes check-scope + boundary-gate + gate-changeset.
# ===========================================================================
ac5_repo="$tmproot/ac5-repo"
build_changeset_repo "$ac5_repo" >/dev/null

ac5_ref="$tmproot/ac5-ref.json"
make_ref_json "$ac5_ref" "DP-343-T1" "in flight migration smoke"

ac5_task="$tmproot/ac5-task.md"
bash "$DERIVE" --refinement-json "$ac5_ref" --task-id "DP-343-T1" --repo-root "$ac5_repo" > "$ac5_task" || {
  echo "FAIL [AC5]: re-derive DP-343-T1 failed" >&2
  exit 1
}

# (1) task.md Allowed Files contains the injected changeset path.
ac5_injected="$(awk '/^## Allowed Files/{f=1;next} /^## /{f=0} f' "$ac5_task" | grep -oE '\.changeset/[^`[:space:]]+\.md' | head -1 || true)"
if [[ -z "$ac5_injected" ]]; then
  echo "FAIL [AC5]: re-derive did not inject a changeset path into Allowed Files" >&2
  cat "$ac5_task" >&2
  exit 1
fi

# The injected path must equal what gate-changeset will demand (slug-source parity).
ac5_jk="$(bash "$PARSE_TASK_MD" --field task_jira_key "$ac5_task" 2>/dev/null || true)"
ac5_sm="$(bash "$PARSE_TASK_MD" --field summary "$ac5_task" 2>/dev/null || true)"
ac5_expected="$(bash "$POLARIS_CHANGESET" slug --ticket "$ac5_jk" --title "$ac5_sm" --print path)"
if [[ "$ac5_injected" != "$ac5_expected" ]]; then
  echo "FAIL [AC5]: injected path '$ac5_injected' != gate-changeset-expected '$ac5_expected' (slug source diverged)" >&2
  exit 1
fi

# Commit the changeset at the injected path on a feature branch.
git -C "$ac5_repo" checkout -q -b task/DP-343-T1-migration
cat > "$ac5_repo/$ac5_injected" <<'EOF'
---
"@selftest/changeset-repo": patch
---

DP-343-T1 in flight migration smoke
EOF
git -C "$ac5_repo" add -A
git -C "$ac5_repo" commit -q -m "add changeset"

# (2) gate 1 — check-scope passes (changeset is in Allowed Files).
set +e
out5_scope="$(cd "$ac5_repo" && bash "$CHECK_SCOPE" "$ac5_task" 2>/dev/null)"
rc5_scope=$?
set -e
if [[ "$rc5_scope" != "0" ]]; then
  echo "FAIL [AC5 / gate check-scope]: deliverable out_of_scope (rc=$rc5_scope)" >&2
  echo "$out5_scope" >&2
  exit 1
fi

# (3) gate 2 — boundary gate passes (start baseline before the changeset commit).
ac5_repo_bg="$tmproot/ac5-repo-bg"
build_changeset_repo "$ac5_repo_bg" >/dev/null
git -C "$ac5_repo_bg" checkout -q -b task/DP-343-T1-migration
export POLARIS_RUNTIME_DIR="$tmproot/ac5-runtime"
bash "$BOUNDARY_GATE" --skill engineering --start \
  --source-container "$tmproot" --repo "$ac5_repo_bg" --task-md "$ac5_task" \
  --session-id ac5 >/dev/null 2>&1 || {
  echo "FAIL [AC5 / gate boundary]: --start failed" >&2
  exit 1
}
cat > "$ac5_repo_bg/$ac5_injected" <<'EOF'
---
"@selftest/changeset-repo": patch
---

DP-343-T1 in flight migration smoke
EOF
git -C "$ac5_repo_bg" add -A
git -C "$ac5_repo_bg" commit -q -m "add changeset"
set +e
bash "$BOUNDARY_GATE" --skill engineering --check \
  --source-container "$tmproot" --repo "$ac5_repo_bg" --task-md "$ac5_task" \
  --session-id ac5 >/dev/null 2>&1
rc5_b=$?
set -e
unset POLARIS_RUNTIME_DIR
if [[ "$rc5_b" != "0" ]]; then
  echo "FAIL [AC5 / gate boundary]: deliverable flagged a violation (rc=$rc5_b)" >&2
  exit 1
fi

# (4) gate 3 — gate-changeset passes (the expected changeset exists & committed).
set +e
bash "$GATE_CHANGESET" --repo "$ac5_repo" --task-md "$ac5_task" >/dev/null 2>&1
rc5_g=$?
set -e
if [[ "$rc5_g" != "0" ]]; then
  echo "FAIL [AC5 / gate gate-changeset]: blocked despite the expected changeset being committed (rc=$rc5_g)" >&2
  exit 1
fi

echo "PASS: check-scope-changeset-allowed-files selftest (AC2 / AC3 / AC5)"
