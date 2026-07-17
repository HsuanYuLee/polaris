#!/usr/bin/env bash
# Selftest for polaris-external-write-gate.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/scripts/polaris-external-write-gate.sh"

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

pass_body="$tmp/jira-comment.md"
cat > "$pass_body" <<'EOF'
這是一段要送到 JIRA comment 的中文內容。
EOF

POLARIS_EXTERNAL_WRITE_WRITER=engineering:jira-comment \
  bash "$GATE" --surface jira-comment --body-file "$pass_body" --workspace-root "$ROOT" >/dev/null

if POLARIS_EXTERNAL_WRITE_WRITER=engineering:jira-comment bash "$GATE" --surface jira-comment --body-file "$tmp/missing.md" --workspace-root "$ROOT" >/dev/null 2>&1; then
  echo "FAIL: missing body file should fail" >&2
  exit 1
fi

if POLARIS_EXTERNAL_WRITE_WRITER=engineering:jira-comment bash "$GATE" --surface unknown --body-file "$pass_body" --workspace-root "$ROOT" >/dev/null 2>&1; then
  echo "FAIL: unknown surface should fail" >&2
  exit 1
fi

starlight_body="$tmp/spec.md"
cat > "$starlight_body" <<'EOF'
---
title: "測試文件"
description: "這是 selftest 使用的 Starlight markdown。"
---

## 內容

這是一段符合語言政策的內容。
EOF

POLARIS_EXTERNAL_WRITE_WRITER=engineering:pr-body \
  bash "$GATE" --surface artifact --body-file "$starlight_body" --workspace-root "$ROOT" --starlight >/dev/null

if POLARIS_EXTERNAL_WRITE_WRITER=unknown:writer bash "$GATE" --surface jira-comment --body-file "$pass_body" --workspace-root "$ROOT" >/dev/null 2>"$tmp/unknown.err"; then
  echo "FAIL: unknown writer token should fail" >&2
  exit 1
fi
grep -Fq 'POLARIS_EXTERNAL_WRITE_WRITER_UNREGISTERED' "$tmp/unknown.err"

if bash "$GATE" --surface jira-comment --body-file "$pass_body" --workspace-root "$ROOT" >/dev/null 2>"$tmp/missing-writer.err"; then
  echo "FAIL: missing writer token should fail" >&2
  exit 1
fi
grep -Fq 'POLARIS_EXTERNAL_WRITE_WRITER_REQUIRED' "$tmp/missing-writer.err"

cat >"$tmp/review.json" <<'JSON'
{"owner":"acme","repo":"widgets","pull_number":1,"event":"COMMENT","body":"已完成檢查。\n","comments":[]}
JSON
printf '已完成檢查。\n' >"$tmp/review.md"
if POLARIS_EXTERNAL_WRITE_WRITER=engineering:jira-comment bash "$GATE" \
  --surface github-review --body-file "$tmp/review.md" \
  --tool-identity github.pull_request_review.submit --payload-file "$tmp/review.json" \
  --workspace-root "$ROOT" >/dev/null 2>"$tmp/wrong-surface.err"; then
  echo "FAIL: registered writer on wrong surface should fail" >&2
  exit 1
fi
grep -Fq 'POLARIS_EXTERNAL_WRITE_WRITER_SURFACE_MISMATCH' "$tmp/wrong-surface.err"

echo "PASS: polaris external write gate selftest"
