#!/usr/bin/env bash
# Compatibility entrypoint for the DP-420-T13 long-chain resolver regression.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
exec mise exec -- pytest tests/test_resolve_task_base.py -q
