#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d -t resolver-article.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
out="$(bash "$ROOT/scripts/spec-source-resolver.sh" --specs-root "$tmp" --source-kind article --source-ref '{"url":"https://example.com/a","archive_snapshot":"snap"}')"
echo "$out" | grep -q '"source_kind": "article"'
echo "$out" | grep -q '"url": "https://example.com/a"'
echo "$out" | grep -q '"archive_snapshot": "snap"'
echo "PASS: spec-source resolver article"
