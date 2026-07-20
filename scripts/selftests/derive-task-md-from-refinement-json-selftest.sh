#!/usr/bin/env bash
# Compatibility entrypoint; assertions live in
# tests/test_derive_task_md_from_refinement_json.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
exec mise exec -- pytest tests/test_derive_task_md_from_refinement_json.py -q "$@"
