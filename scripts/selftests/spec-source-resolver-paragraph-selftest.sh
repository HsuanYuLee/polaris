#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d -t resolver-paragraph.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
out="$(bash "$ROOT/scripts/spec-source-resolver.sh" --specs-root "$tmp" --source-kind paragraph --source-ref '{"url":"https://example.com/a","selector":"#p1","paragraph_index":3,"text":"hello"}')"
echo "$out" | grep -q '"source_kind": "paragraph"'
echo "$out" | grep -q '"selector": "#p1"'
echo "$out" | grep -q '"paragraph_index": 3'
echo "PASS: spec-source resolver paragraph"
