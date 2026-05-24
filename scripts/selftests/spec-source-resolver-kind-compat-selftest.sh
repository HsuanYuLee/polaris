#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d -t resolver-kind.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/design-plans/DP-999-topic"
cat >"$tmp/design-plans/DP-999-topic/index.md" <<'MD'
---
title: "DP-999"
description: "fixture"
status: LOCKED
---
MD
touch "$tmp/design-plans/DP-999-topic/refinement.md" "$tmp/design-plans/DP-999-topic/refinement.json"
bash "$ROOT/scripts/spec-source-resolver.sh" --specs-root "$tmp" --source-kind dp --source-ref DP-999 | grep -q '"source_id": "DP-999"'
one="$(bash "$ROOT/scripts/spec-source-resolver.sh" --specs-root "$tmp" --source-kind free-text --source-ref "same slug A")"
two="$(bash "$ROOT/scripts/spec-source-resolver.sh" --specs-root "$tmp" --source-kind free-text --source-ref "same slug B")"
test "$one" != "$two"
echo "PASS: spec-source resolver kind compat"
