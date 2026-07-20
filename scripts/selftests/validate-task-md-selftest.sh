#!/usr/bin/env bash
# Compatibility entrypoint; assertions live in tests/test_validate_task_md.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
exec mise exec -- pytest tests/test_validate_task_md.py -q "$@"
