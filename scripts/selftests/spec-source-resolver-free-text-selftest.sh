#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d -t resolver-free-text.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
out="$(bash "$ROOT/scripts/spec-source-resolver.sh" --specs-root "$tmp" --source-kind free-text --source-ref "Same title body A")"
echo "$out" | grep -q '"source_kind": "free-text"'
echo "$out" | grep -q 'free-text-same-title-body-a-'
echo "PASS: spec-source resolver free-text"
