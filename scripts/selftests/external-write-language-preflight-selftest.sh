#!/usr/bin/env bash
# external-write-language-preflight-selftest.sh — DP-230 D17 AC13.
#
# Verifies pre-write-language-policy.sh external-write writer registry:
#   1. Registered writer + zh-TW body file → exit 0 (PASS).
#   2. Registered writer + English body file (out-of-scope path) → exit 0
#      (language gate only applies on in-scope paths).
#   3. Unregistered writer → exit 2 + stderr POLARIS_EXTERNAL_WRITE_WRITER_UNREGISTERED.
#   4. Unregistered writer + POLARIS_LANGUAGE_POLICY_BYPASS=1 → still exit 2.
#   5. No env var set → legacy behaviour preserved (out-of-scope path → exit 0).
#   6. workspace-language-policy.md contains the "External Write Preflight" section.
#   7. external-write-writer-registry.md line count ≤ 300.
#   8. Registry consistency: every token listed in the hook array also appears in
#      the reference document.
#
# Exit codes:
#   0  selftest PASS
#   1  selftest FAIL

set -euo pipefail

# DP-230 D19 boots will use lib/selftest-bootstrap.sh; until then use the
# legacy BASH_SOURCE-relative resolution.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT_DIR/.claude/hooks/pre-write-language-policy.sh"
REGISTRY_REF="$ROOT_DIR/.claude/skills/references/external-write-writer-registry.md"
POLICY_REF="$ROOT_DIR/.claude/skills/references/workspace-language-policy.md"
WORKDIR="$(mktemp -d -t dp230-d17-external-write.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -x "$HOOK" ]]; then
  echo "FAIL: hook is not executable: $HOOK" >&2
  exit 1
fi
if [[ ! -f "$REGISTRY_REF" ]]; then
  echo "FAIL: missing external-write-writer-registry.md at $REGISTRY_REF" >&2
  exit 1
fi
if [[ ! -f "$POLICY_REF" ]]; then
  echo "FAIL: missing workspace-language-policy.md at $POLICY_REF" >&2
  exit 1
fi

# AC13 #7: line count ceiling on the registry reference.
reg_lines=$(wc -l <"$REGISTRY_REF" | tr -d ' ')
if [[ "$reg_lines" -gt 300 ]]; then
  echo "FAIL: external-write-writer-registry.md has $reg_lines lines (> 300)" >&2
  exit 1
fi

# AC13 #6: workspace-language-policy.md must contain the External Write
# Preflight section heading.
if ! grep -q '^## 9\. External Write Preflight' "$POLICY_REF"; then
  echo "FAIL: workspace-language-policy.md missing '## 9. External Write Preflight' section" >&2
  exit 1
fi

build_payload() {
  local tool="$1" path="$2" content="$3"
  python3 - "$tool" "$path" "$content" <<'PY'
import json, sys
tool, path, content = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    "tool_name": tool,
    "tool_input": {"file_path": path, "content": content},
}))
PY
}

run_hook_env() {
  local payload="$1" expected_exit="$2" label="$3"
  shift 3
  local out_file="$WORKDIR/${label}.out"
  set +e
  printf '%s' "$payload" | env "$@" "$HOOK" >"$out_file" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -ne "$expected_exit" ]]; then
    echo "FAIL ($label): expected exit $expected_exit, got $rc" >&2
    cat "$out_file" >&2
    exit 1
  fi
  printf '%s' "$out_file"
}

# Body file path that lives outside the in-scope artifact dirs so the existing
# language gate does not run; this matches how producers stage external-write
# body files (e.g., /tmp/polaris-*.md or .polaris/runtime/external-writes/).
body_path="$WORKDIR/polaris-jira-comment.md"

# Case 1: Registered writer (intake-triage:jira-comment) + zh-TW body → PASS.
payload1=$(build_payload Write "$body_path" "這是中文 JIRA comment，描述 root cause 與 impact。")
out1=$(run_hook_env "$payload1" 0 case1-registered-zh \
  POLARIS_EXTERNAL_WRITE_WRITER=intake-triage:jira-comment)
grep -q 'BYPASS external-write-writer registered=intake-triage:jira-comment' "$out1" \
  || { echo "FAIL case1: expected registered bypass log" >&2; cat "$out1" >&2; exit 1; }

# Case 2: Registered writer + English body on out-of-scope path → PASS
# (legacy in-scope path filter exits 0; registry only attests writer identity).
payload2=$(build_payload Write "$body_path" "Plain English JIRA comment body that producers may localize before send.")
out2=$(run_hook_env "$payload2" 0 case2-registered-en-oos \
  POLARIS_EXTERNAL_WRITE_WRITER=engineering:pr-body)
grep -q 'BYPASS external-write-writer registered=engineering:pr-body' "$out2" \
  || { echo "FAIL case2: expected registered bypass log" >&2; cat "$out2" >&2; exit 1; }

# Case 3: Unregistered writer → exit 2 + POLARIS_EXTERNAL_WRITE_WRITER_UNREGISTERED.
payload3=$(build_payload Write "$body_path" "這是中文 body，但 writer token 未登錄。")
out3=$(run_hook_env "$payload3" 2 case3-unregistered \
  POLARIS_EXTERNAL_WRITE_WRITER=ghost-skill:jira-comment)
grep -q 'POLARIS_EXTERNAL_WRITE_WRITER_UNREGISTERED: writer=ghost-skill:jira-comment' "$out3" \
  || { echo "FAIL case3: expected POLARIS_EXTERNAL_WRITE_WRITER_UNREGISTERED in stderr" >&2; cat "$out3" >&2; exit 1; }

# Case 4 (AC13 attack): unregistered writer + POLARIS_LANGUAGE_POLICY_BYPASS=1
# → still exit 2. Bypass must not grant escape for unregistered writers.
out4=$(run_hook_env "$payload3" 2 case4-bypass-attempt \
  POLARIS_EXTERNAL_WRITE_WRITER=ghost-skill:jira-comment \
  POLARIS_LANGUAGE_POLICY_BYPASS=1)
grep -q 'POLARIS_EXTERNAL_WRITE_WRITER_UNREGISTERED: writer=ghost-skill:jira-comment' "$out4" \
  || { echo "FAIL case4: bypass must not silence unregistered writer fail-stop" >&2; cat "$out4" >&2; exit 1; }

# Case 5: legacy path — no env var, out-of-scope path → exit 0 (no-op).
payload5=$(build_payload Write "$body_path" "Plain English text without external-write declaration.")
run_hook_env "$payload5" 0 case5-legacy-no-env >/dev/null

# Case 8: registry consistency — every token in the hook array must appear in
# the reference doc (so future maintainers can read the registry there too).
# Parse the hook array between POLARIS_EXTERNAL_WRITERS=( ... ) markers.
tokens_file="$WORKDIR/hook-tokens.txt"
python3 - "$HOOK" "$tokens_file" <<'PY'
import re, sys
hook, out = sys.argv[1], sys.argv[2]
text = open(hook, encoding="utf-8").read()
m = re.search(r"POLARIS_EXTERNAL_WRITERS=\(([^)]*)\)", text, flags=re.S)
if not m:
    sys.exit("FAIL: POLARIS_EXTERNAL_WRITERS array not found in hook")
tokens = re.findall(r'"([^"]+)"', m.group(1))
with open(out, "w", encoding="utf-8") as fh:
    fh.write("\n".join(tokens))
PY
if [[ ! -s "$tokens_file" ]]; then
  echo "FAIL: hook token list empty" >&2
  exit 1
fi
while IFS= read -r token; do
  [[ -z "$token" ]] && continue
  if ! grep -qF "$token" "$REGISTRY_REF"; then
    echo "FAIL case8: hook token $token not documented in external-write-writer-registry.md" >&2
    exit 1
  fi
done <"$tokens_file"

echo "PASS: external-write-language-preflight selftest (registry_lines=$reg_lines)"
