#!/usr/bin/env bash
set -euo pipefail

echo "verify-docs-viewer-runtime.sh is deprecated; use verify-docs-manager-runtime.sh." >&2
exec "$(cd "$(dirname "$0")" && pwd)/verify-docs-manager-runtime.sh" "$@"
