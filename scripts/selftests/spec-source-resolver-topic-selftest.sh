#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d -t resolver-topic.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
out="$(bash "$ROOT/scripts/spec-source-resolver.sh" --specs-root "$tmp" --source-kind topic --source-ref "topic text")"
echo "$out" | grep -q '"source_kind": "topic"'
echo "$out" | grep -q 'sources/topic-topic-text-'
echo "PASS: spec-source resolver topic"
