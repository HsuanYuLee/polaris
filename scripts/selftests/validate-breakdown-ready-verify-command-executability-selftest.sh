#!/usr/bin/env bash
# Purpose: selftest for the DP-311 T6 Verify/Test Command executability gate —
#   validate-breakdown-ready.sh must fail-close (exit 2 +
#   POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE) on prose Verify Command / Test
#   Command fenced blocks, and must NOT false-block executable commands
#   (including quoted CJK grep patterns). The verdict is shared with
#   derive-task-md-from-refinement-json.sh through
#   scripts/lib/check-verify-command-executability.sh (D9: one helper, no
#   second judgment) — this selftest also unit-covers the helper directly.
# Inputs:  none (derives task.md fixtures into a tmpdir via the production
#          derive script, then perturbs the command fences)
# Outputs: stdout PASS line on success; non-zero exit + stderr on failure
# Exit code: 0 = pass, non-zero = fail
#
# AC coverage (DP-311):
#   AC8     : prose Verify Command (DP-252-T1 original prose) -> exit 2 + marker;
#             prose Test Command -> exit 2 + marker; directory scan mode too.
#   AC-NEG7 : executable commands (incl. quoted CJK grep pattern) -> PASS,
#             zero false-block.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVE="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"
VALIDATOR="$ROOT_DIR/scripts/validate-breakdown-ready.sh"
HELPER="$ROOT_DIR/scripts/lib/check-verify-command-executability.sh"

[[ -x "$DERIVE" ]] || { echo "FAIL: derive script not executable: $DERIVE" >&2; exit 1; }
[[ -x "$VALIDATOR" ]] || { echo "FAIL: validate-breakdown-ready.sh not executable: $VALIDATOR" >&2; exit 1; }
[[ -f "$HELPER" ]] || { echo "FAIL: shared helper missing: $HELPER" >&2; exit 1; }

tmpdir="$(mktemp -d -t vbr-verify-cmd-exec.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# DP-252-T1 original prose (escalations/T1-1.md raw evidence) — the must-block
# fixture. `Don't` carries an unterminated quote (bash -n catches it) and the
# CJK words sit outside quotes (the primary interceptor catches them).
DP252_PROSE="$tmpdir/dp252-prose.txt"
cat >"$DP252_PROSE" <<'EOF'
set -euo pipefail
檔案 existence + frontmatter assert + 5 H2 sections grep + language table 4 rows + 每 row code block fence
+ Don't/Do >= 2 對 + grandfather/new-modified/modified-邊界 wording + advisory/reviewer-signoff/mechanism-registry
pointer wording + wc -l <= 500 + 2 個 gate replay
EOF

# ---------------------------------------------------------------------------
# Helper unit coverage (shared judgment, used by BOTH derive and readiness).
# ---------------------------------------------------------------------------

# H1: executable command -> exit 0.
printf '%s\n' "bash scripts/selftests/sample-selftest.sh" | bash "$HELPER" --label h1 || {
  echo "FAIL [helper H1]: plain executable command was blocked" >&2
  exit 1
}

# H2: quoted CJK grep pattern -> exit 0 (EC10 / AC-NEG7).
printf '%s\n' "grep -q '既有未動' file.md && grep -q \"邊界判定\" file.md" | bash "$HELPER" --label h2 || {
  echo "FAIL [helper H2]: quoted CJK pattern was falsely blocked" >&2
  exit 1
}

# H3: DP-252-T1 prose -> exit 2 + marker (bash -n path).
set +e
h3_err="$(bash "$HELPER" --label h3 --file "$DP252_PROSE" 2>&1)"
h3_rc=$?
set -e
if [[ "$h3_rc" -ne 2 ]] || ! grep -q 'POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE:h3' <<<"$h3_err"; then
  echo "FAIL [helper H3]: DP-252-T1 prose must exit 2 with marker (got rc=$h3_rc)" >&2
  printf '%s\n' "$h3_err" >&2
  exit 1
fi

# H4: bash-parseable CJK prose (EC11: CJK bare word as command name) -> exit 2.
set +e
h4_err="$(printf '%s\n' "檔案 existence + frontmatter assert" | bash "$HELPER" --label h4 2>&1)"
h4_rc=$?
set -e
if [[ "$h4_rc" -ne 2 ]] || ! grep -q 'CJK outside quotes' <<<"$h4_err"; then
  echo "FAIL [helper H4]: bash-parseable CJK prose must exit 2 via the CJK check (got rc=$h4_rc)" >&2
  printf '%s\n' "$h4_err" >&2
  exit 1
fi

# H5: empty input -> fail-closed exit 2 (certifying nothing is contract misuse).
set +e
printf '' | bash "$HELPER" --label h5 2>/dev/null
h5_rc=$?
set -e
if [[ "$h5_rc" -ne 2 ]]; then
  echo "FAIL [helper H5]: empty command text must fail-close with exit 2 (got rc=$h5_rc)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Fixture build: derive a constructible task.md through the PRODUCTION derive
# script (executable verify_command containing a quoted CJK pattern), placed
# folder-native so the validator actually scans it (loose /tmp basenames are
# skipped by task_id_for_file).
# ---------------------------------------------------------------------------
refinement_json="$tmpdir/refinement.json"
cat >"$refinement_json" <<'JSON'
{
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "/tmp/dp-999",
    "plan_path": "/tmp/dp-999/index.md",
    "base_branch": "feat/DP-999",
    "jira_key": null
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "implementation",
      "title": "executability gate fixture",
      "scope": "驗證 readiness gate 對可執行命令零誤擋、對 prose fail-closed。",
      "allowed_files": ["scripts/sample.sh", "scripts/selftests/sample-selftest.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC8"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/sample-selftest.sh",
        "verify_command": "grep -q '既有未動' scripts/sample.sh && bash scripts/selftests/sample-selftest.sh",
        "behavior_contract": { "applies": false, "reason": "framework selftest fixture; no runtime behavior" },
        "test_environment": { "level": "static" },
        "references": ["scripts/sample.sh"]
      }
    }
  ]
}
JSON

mkdir -p "$tmpdir/tasks/T1"
valid_task="$tmpdir/tasks/T1/index.md"
bash "$DERIVE" --refinement-json "$refinement_json" --task-id "DP-999-T1" >"$valid_task"

# rewrite_fence <task.md> <heading> <replacement-file>
# Replaces the fenced code block under the given H2 heading with the
# replacement file's content (used to inject prose into a derived task.md,
# since the production derive now refuses to emit prose itself).
rewrite_fence() {
  local file="$1" heading="$2" replacement="$3"
  REWRITE_FILE="$file" REWRITE_HEADING="$heading" REWRITE_WITH="$replacement" python3 - <<'PY'
import os
import re
from pathlib import Path

path = Path(os.environ["REWRITE_FILE"])
heading = os.environ["REWRITE_HEADING"]
replacement = Path(os.environ["REWRITE_WITH"]).read_text(encoding="utf-8").rstrip("\n")
text = path.read_text(encoding="utf-8")
pattern = re.compile(
    rf"(^{re.escape(heading)}\n\n```bash\n)(.*?)(\n```)", re.DOTALL | re.MULTILINE
)
new_text, count = pattern.subn(lambda m: m.group(1) + replacement + m.group(3), text, count=1)
if count != 1:
    raise SystemExit(f"fence under {heading} not found in {path}")
path.write_text(new_text, encoding="utf-8")
PY
}

# ---------------------------------------------------------------------------
# Case 1 (AC-NEG7): executable commands (quoted CJK included) -> PASS exit 0.
# ---------------------------------------------------------------------------
if ! bash "$VALIDATOR" "$valid_task" >/dev/null; then
  echo "FAIL [case 1 / AC-NEG7]: executable verify/test commands were falsely blocked" >&2
  bash "$VALIDATOR" "$valid_task" >&2 || true
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 2 (AC8): DP-252-T1 prose in the ## Verify Command fence -> exit 2 +
# POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE marker.
# ---------------------------------------------------------------------------
mkdir -p "$tmpdir/prose-verify/tasks/T1"
prose_verify_task="$tmpdir/prose-verify/tasks/T1/index.md"
cp "$valid_task" "$prose_verify_task"
rewrite_fence "$prose_verify_task" "## Verify Command" "$DP252_PROSE"

prose_verify_err="$tmpdir/prose-verify.err"
set +e
bash "$VALIDATOR" "$prose_verify_task" >/dev/null 2>"$prose_verify_err"
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL [case 2 / AC8]: prose Verify Command must exit 2 (got rc=$rc)" >&2
  cat "$prose_verify_err" >&2
  exit 1
fi
if ! grep -q "POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE:$prose_verify_task" "$prose_verify_err"; then
  echo "FAIL [case 2 / AC8]: stderr missing POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE:<file> marker" >&2
  cat "$prose_verify_err" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 3 (AC8): prose in the ## Test Command fence only -> exit 2 + marker
# (both fences are gated; the defect ships as two copies, DP-252-T1 evidence).
# ---------------------------------------------------------------------------
mkdir -p "$tmpdir/prose-test/tasks/T1"
prose_test_task="$tmpdir/prose-test/tasks/T1/index.md"
cp "$valid_task" "$prose_test_task"
rewrite_fence "$prose_test_task" "## Test Command" "$DP252_PROSE"

prose_test_err="$tmpdir/prose-test.err"
set +e
bash "$VALIDATOR" "$prose_test_task" >/dev/null 2>"$prose_test_err"
rc=$?
set -e
if [[ "$rc" -ne 2 ]] || ! grep -q 'POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE' "$prose_test_err"; then
  echo "FAIL [case 3 / AC8]: prose Test Command must exit 2 with marker (got rc=$rc)" >&2
  cat "$prose_test_err" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 4 (AC8): directory scan mode hits the same gate (the shape
# validate-refinement-lock-preflight delegates into).
# ---------------------------------------------------------------------------
dir_err="$tmpdir/dir-scan.err"
set +e
bash "$VALIDATOR" "$tmpdir/prose-verify/tasks" >/dev/null 2>"$dir_err"
rc=$?
set -e
if [[ "$rc" -ne 2 ]] || ! grep -q 'POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE' "$dir_err"; then
  echo "FAIL [case 4 / AC8]: directory scan must exit 2 with marker on prose fence (got rc=$rc)" >&2
  cat "$dir_err" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 5 (AC8 adversarial): bash-parseable CJK prose in the Verify Command
# fence (EC11) -> exit 2 via the CJK interceptor (bash -n alone would pass).
# ---------------------------------------------------------------------------
ec11_prose="$tmpdir/ec11-prose.txt"
printf '%s\n' "檔案 existence + frontmatter assert" >"$ec11_prose"
mkdir -p "$tmpdir/ec11/tasks/T1"
ec11_task="$tmpdir/ec11/tasks/T1/index.md"
cp "$valid_task" "$ec11_task"
rewrite_fence "$ec11_task" "## Verify Command" "$ec11_prose"

ec11_err="$tmpdir/ec11.err"
set +e
bash "$VALIDATOR" "$ec11_task" >/dev/null 2>"$ec11_err"
rc=$?
set -e
if [[ "$rc" -ne 2 ]] || ! grep -q 'POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE' "$ec11_err"; then
  echo "FAIL [case 5 / AC8]: bash-parseable CJK prose fence must exit 2 with marker (got rc=$rc)" >&2
  cat "$ec11_err" >&2
  exit 1
fi

echo "PASS: validate-breakdown-ready verify-command executability selftest"
