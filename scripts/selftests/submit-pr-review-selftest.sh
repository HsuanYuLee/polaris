#!/usr/bin/env bash
# Purpose: validate canonical PR review identity, payload shape, and submit wrapper.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$ROOT/scripts/submit-pr-review.sh"
TMP="$(mktemp -d -t submit-pr-review.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

printf '已完成檢查，沒有阻擋問題。\n' >"$TMP/body.md"
cat >"$TMP/comments.json" <<'JSON'
[{"path":"src/a.ts","line":7,"side":"RIGHT","body":"請補上此分支的測試。"}]
JSON

bash "$WRAPPER" --repository acme/widgets --pull-number 42 --event COMMENT \
  --body-file "$TMP/body.md" --comments-file "$TMP/comments.json" >"$TMP/payload.json"
jq -e '.owner=="acme" and .repo=="widgets" and .pull_number==42 and .event=="COMMENT" and (.comments|length)==1' "$TMP/payload.json" >/dev/null

if bash "$WRAPPER" --repository acme/widgets --pull-number 42 --event COMMENT \
  --body-file "$TMP/body.md" --tool-identity mcp__github__submit_review >/dev/null 2>"$TMP/old-tool.err"; then
  echo "FAIL: old/ad-hoc tool identity should fail" >&2
  exit 1
fi
grep -Fq 'POLARIS_EXTERNAL_WRITE_TOOL_IDENTITY_INVALID' "$TMP/old-tool.err"

printf '{"body":"ad-hoc root"}\n' >"$TMP/bad-comments.json"
if bash "$WRAPPER" --repository acme/widgets --pull-number 42 --event COMMENT \
  --body-file "$TMP/body.md" --comments-file "$TMP/bad-comments.json" >/dev/null 2>"$TMP/bad-payload.err"; then
  echo "FAIL: ad-hoc comments payload should fail" >&2
  exit 1
fi
grep -Fq 'POLARIS_EXTERNAL_WRITE_PAYLOAD_INVALID' "$TMP/bad-payload.err"

cat >"$TMP/bad-range-type.json" <<'JSON'
[{"path":"src/a.ts","line":10,"side":"RIGHT","body":"錯誤 type。","start_line":"oops","start_side":"RIGHT"}]
JSON
if bash "$WRAPPER" --repository acme/widgets --pull-number 42 --event COMMENT \
  --body-file "$TMP/body.md" --comments-file "$TMP/bad-range-type.json" >/dev/null 2>"$TMP/bad-range-type.err"; then
  echo "FAIL: invalid start_line type should fail" >&2
  exit 1
fi
grep -Fq 'start_line must be a positive integer' "$TMP/bad-range-type.err"

cat >"$TMP/bad-range-pair.json" <<'JSON'
[{"path":"src/a.ts","line":10,"side":"RIGHT","body":"缺少 start_side。","start_line":4}]
JSON
if bash "$WRAPPER" --repository acme/widgets --pull-number 42 --event COMMENT \
  --body-file "$TMP/body.md" --comments-file "$TMP/bad-range-pair.json" >/dev/null 2>"$TMP/bad-range-pair.err"; then
  echo "FAIL: unpaired multi-line range should fail" >&2
  exit 1
fi
grep -Fq 'start_line/start_side must be paired' "$TMP/bad-range-pair.err"

cat >"$TMP/bad-range-order.json" <<'JSON'
[{"path":"src/a.ts","line":10,"side":"RIGHT","body":"錯誤順序。","start_line":10,"start_side":"RIGHT"}]
JSON
if bash "$WRAPPER" --repository acme/widgets --pull-number 42 --event COMMENT \
  --body-file "$TMP/body.md" --comments-file "$TMP/bad-range-order.json" >/dev/null 2>"$TMP/bad-range-order.err"; then
  echo "FAIL: start_line >= line should fail" >&2
  exit 1
fi
grep -Fq 'start_line must be less than line' "$TMP/bad-range-order.err"

cat >"$TMP/bad-range-side.json" <<'JSON'
[{"path":"src/a.ts","line":10,"side":"RIGHT","body":"錯誤 side。","start_line":4,"start_side":"MIDDLE"}]
JSON
if bash "$WRAPPER" --repository acme/widgets --pull-number 42 --event COMMENT \
  --body-file "$TMP/body.md" --comments-file "$TMP/bad-range-side.json" >/dev/null 2>"$TMP/bad-range-side.err"; then
  echo "FAIL: invalid start_side should fail" >&2
  exit 1
fi
grep -Fq 'start_side invalid' "$TMP/bad-range-side.err"

cat >"$TMP/good-range.json" <<'JSON'
[{"path":"src/a.ts","start_line":4,"start_side":"RIGHT","line":7,"side":"RIGHT","body":"請一起修正此範圍。"}]
JSON
bash "$WRAPPER" --repository acme/widgets --pull-number 42 --event COMMENT \
  --body-file "$TMP/body.md" --comments-file "$TMP/good-range.json" >/dev/null

cat >"$TMP/gh-stub" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$POLARIS_GH_LOG"
input=""
while [[ $# -gt 0 ]]; do
  [[ "$1" == "--input" ]] && { input="$2"; break; }
  shift
done
jq -e '.event=="COMMENT" and .pull_number==42' "$input" >/dev/null
printf '{"id":123}\n'
SH
chmod +x "$TMP/gh-stub"
POLARIS_GH_BIN="$TMP/gh-stub" POLARIS_GH_LOG="$TMP/gh.log" \
  bash "$WRAPPER" --repository acme/widgets --pull-number 42 --event COMMENT \
    --body-file "$TMP/body.md" --comments-file "$TMP/comments.json" --submit >"$TMP/response.json"
grep -Fq 'repos/acme/widgets/pulls/42/reviews' "$TMP/gh.log"
jq -e '.id==123' "$TMP/response.json" >/dev/null

echo "PASS: submit PR review wrapper selftest"
